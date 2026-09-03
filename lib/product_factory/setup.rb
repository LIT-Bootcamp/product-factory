require "digest"
require "fileutils"
require "tempfile"
require "time"
require "tmpdir"

module ProductFactory
  class Setup
    attr_reader :plan_path

    def self.from_cli(cwd:, input:, output:)
      new(
        distribution_root: File.expand_path("../..", __dir__),
        target_root: cwd,
        input:,
        output:,
        clock: -> { Time.now }
      )
    end

    def initialize(distribution_root:, target_root:, input:, output:, clock:)
      @distribution_root = File.expand_path(distribution_root)
      @target_root = File.expand_path(target_root)
      @input = input
      @output = output
      @clock = clock
    end

    def plan(resolutions: {})
      installation = Installation.load(@target_root)
      installed = File.exist?(File.join(@target_root, Installation::PATH))
      mode = installed ? "refresh" : "setup"
      Config.load(@target_root) if File.exist?(File.join(@target_root, Config::PATH))
      run_id = RunId.generate(clock: @clock)

      managed = ManagedFiles.new(sources: managed_sources)
      result = managed.plan(
        target_root: @target_root,
        installed_hashes: installation.managed_file_hashes,
        resolutions:
      )
      operations = result.fetch(:operations)
      operations.unshift(seed_config_operation) unless File.exist?(File.join(@target_root, Config::PATH))

      next_hashes = result.fetch(:next_hashes)
      state_changed = !installed || operations.any? || next_hashes != installation.managed_file_hashes
      if state_changed
        state = installation.with(
          "factory_version" => VERSION,
          "installed_at" => @clock.call.utc.iso8601,
          "installed_by" => ENV.fetch("USER", "unknown"),
          "managed_file_hashes" => next_hashes,
          "last_successful_setup_run" => run_id,
          "pending_operations" => []
        ).to_h
        operations << Operation.new(
          kind: "write_installation",
          target: Installation::PATH,
          attributes: state
        )
      end

      save_plan(Plan.new(
        run_id:,
        mode:,
        operations:,
        conflicts: result.fetch(:conflicts)
      ))
    end

    def plan_and_print(argv)
      result = plan(resolutions: parse_resolutions(argv))
      @output.puts("Mode: #{result.mode}")
      @output.puts("Target: #{@target_root}")
      result.operations.each do |operation|
        @output.puts("#{operation.id} #{operation.kind} #{operation.target}")
      end
      result.conflicts.each do |conflict|
        @output.puts("Conflict: #{conflict.fetch("path")} (keep_local, take_upstream, manual_merge)")
      end
      @output.puts("Plan path: #{plan_path}")
      raise ConflictError, "plan has conflicts" unless result.applicable?

      result
    end

    def load_and_apply(path)
      apply(Plan.load(path))
    end

    def apply(plan)
      raise ConflictError, "plan has conflicts" unless plan.applicable?
      return :success if plan.operations.empty?

      journal = Journal.new(path: journal_path, clock: @clock)
      unless confirmed?(journal, plan.run_id)
        @output.puts("#{plan.operations.count} operations")
        @output.print("Apply this plan? [yes/no] ")
        return :declined unless @input.gets&.chomp == "yes"

        ensure_factory_directory
        journal.append(event: "run_confirmed", run_id: plan.run_id)
      end

      Executor.new(journal:, handlers: handlers).apply(plan)
    end

    private

    def managed_sources
      sources = {}
      Dir.glob(File.join(@distribution_root, "lib/**/*.rb")).sort.each do |source|
        relative = source.delete_prefix("#{@distribution_root}/")
        sources[File.join(".product-factory/runtime", relative)] = source
      end
      Dir.glob(
        File.join(@distribution_root, "templates/project/**/*"),
        File::FNM_DOTMATCH
      ).sort.each do |source|
        next unless File.file?(source)

        relative = source.delete_prefix("#{@distribution_root}/templates/project/")
        sources[relative] = source
      end
      sources
    end

    def seed_config_operation
      Operation.new(
        kind: "seed_config",
        target: Config::PATH,
        attributes: {
          "content_base64" => [File.binread(File.join(@distribution_root, "templates/config.yml"))].pack("m0")
        }
      )
    end

    def save_plan(plan)
      @plan_path = File.join(Dir.tmpdir, "product-factory-#{plan.run_id}.json")
      plan.write(@plan_path)
      plan
    end

    def parse_resolutions(argv)
      arguments = argv.dup
      resolutions = {}
      until arguments.empty?
        argument = arguments.shift
        value = if argument == "--resolve"
          arguments.shift
        elsif argument.start_with?("--resolve=")
          argument.delete_prefix("--resolve=")
        end
        raise UsageError, "resolve must be PATH=VALUE" unless value

        path, resolution = value.split("=", 2)
        raise UsageError, "resolve must be PATH=VALUE" unless path && resolution

        resolutions[path] = resolution
      end
      resolutions
    end

    def journal_path = File.join(@target_root, ".product-factory/journal.jsonl")

    def ensure_factory_directory
      directory = File.join(@target_root, ".product-factory")
      if File.symlink?(directory)
        raise ValidationError, "factory directory is a symlink"
      end

      FileUtils.mkdir_p(directory)
      raise ValidationError, "factory directory is not a directory" unless File.directory?(directory)
    end

    def confirmed?(journal, run_id)
      journal.events.any? { |event| event["event"] == "run_confirmed" && event["run_id"] == run_id }
    end

    def handlers
      managed = ManagedFiles.new(sources: {})
      {
        "write_file" => Executor::Handler.new(
          apply: ->(operation) { managed.apply(operation, target_root: @target_root) },
          verify: ->(operation) { verified_managed_file?(operation) }
        ),
        "delete_file" => Executor::Handler.new(
          apply: ->(operation) { managed.apply(operation, target_root: @target_root) },
          verify: ->(operation) { !File.exist?(File.join(@target_root, operation.target)) }
        ),
        "seed_config" => Executor::Handler.new(
          apply: ->(operation) { seed_config(operation) },
          verify: ->(operation) { seeded_config?(operation) }
        ),
        "write_installation" => Executor::Handler.new(
          apply: ->(operation) { write_installation(operation) },
          verify: ->(operation) { verified_installation?(operation) }
        )
      }
    end

    def seed_config(operation)
      validate_seed_operation(operation)
      path = File.join(@target_root, Config::PATH)
      ensure_factory_directory
      bytes = operation.attributes.fetch("content_base64").unpack1("m0")

      Tempfile.create([".product-factory-config-", ".tmp"], File.dirname(path)) do |temp|
        temp.binmode
        temp.write(bytes)
        temp.flush
        temp.fsync
        temp.chmod(0o644)
        File.link(temp.path, path)
      rescue Errno::EEXIST
        raise ConflictError, "#{Config::PATH} already exists"
      end
    end

    def validate_seed_operation(operation)
      attributes = operation.attributes
      valid = operation.target == Config::PATH &&
        attributes.is_a?(Hash) && attributes["content_base64"].is_a?(String)
      raise ValidationError, "invalid config seed operation" unless valid
    end

    def seeded_config?(operation)
      validate_seed_operation(operation)
      File.binread(File.join(@target_root, Config::PATH)) ==
        operation.attributes.fetch("content_base64").unpack1("m0")
    rescue Errno::ENOENT
      false
    end

    def verified_managed_file?(operation)
      path = File.join(@target_root, operation.target)
      return false unless File.exist?(path) && File.lstat(path).file?

      attributes = operation.attributes
      File.binread(path) == attributes.fetch("content_base64").unpack1("m0") &&
        (File.stat(path).mode & 0o7777) == attributes.fetch("mode")
    rescue Errno::ENOENT, KeyError, ArgumentError
      false
    end

    def verified_installation?(operation)
      return false unless operation.target == Installation::PATH && operation.attributes.is_a?(Hash)

      state = Installation.load(@target_root).to_h
      return false unless state == operation.attributes

      state.fetch("managed_file_hashes").all? do |path, expected_hash|
        target = File.join(@target_root, path)
        File.lstat(target).file? && Digest::SHA256.file(target).hexdigest == expected_hash
      end
    rescue Errno::ENOENT, ValidationError, KeyError, TypeError
      false
    end

    def write_installation(operation)
      unless operation.target == Installation::PATH && operation.attributes.is_a?(Hash)
        raise ValidationError, "invalid installation operation"
      end

      ensure_factory_directory
      Installation.new(operation.attributes).write(@target_root)
    end
  end
end
