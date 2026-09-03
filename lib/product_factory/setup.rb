require "digest"
require "fileutils"
require "tempfile"
require "time"
require "tmpdir"

module ProductFactory
  class Setup
    LEGACY_MANAGED_PREFIXES = %w[
      .product-factory/runtime/
      .product-factory/schemas/
      .product-factory/spec/
    ].freeze
    REQUIRED_DISTRIBUTION_FILES = %w[
      lib/product_factory.rb
      templates/config.yml
      templates/project/bin/product-factory
      templates/project/.product-factory/spec/runtime_spec.rb
      templates/project/.product-factory/schemas/config-v1.yml
      templates/project/.product-factory/schemas/installation-v1.yml
    ].freeze

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
      validate_target!
      installation = Installation.load(@target_root)
      sources = managed_sources
      installed_hashes = installation.managed_file_hashes
      validate_installed_hashes!(installed_hashes, current_targets: sources.keys)
      installed = File.exist?(File.join(@target_root, Installation::PATH))
      mode = installed ? "refresh" : "setup"
      Config.load(@target_root) if File.exist?(File.join(@target_root, Config::PATH))
      run_id = RunId.generate(clock: @clock)

      managed = ManagedFiles.new(sources:)
      result = managed.plan(
        target_root: @target_root,
        installed_hashes:,
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
        conflicts: result.fetch(:conflicts),
        target_root: @target_root
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
      validate_target!
      validate_plan!(plan)
      raise ConflictError, "plan has conflicts" unless plan.applicable?
      return :success if plan.operations.empty?

      journal = Journal.new(path: journal_path, clock: @clock)
      validate_preconditions!(plan)
      unless confirmed?(journal, plan.run_id)
        @output.puts("#{plan.operations.count} operations")
        @output.print("Apply this plan? [yes/no] ")
        return :declined unless @input.gets&.chomp == "yes"

        journal.append(event: "run_confirmed", run_id: plan.run_id)
      end

      Executor.new(journal:, handlers: handlers).apply(plan)
    end

    private

    def managed_sources
      library_root = File.join(@distribution_root, "lib")
      config_source = File.join(@distribution_root, "templates/config.yml")
      project_root = File.join(@distribution_root, "templates/project")
      complete = File.directory?(library_root) && File.directory?(project_root) &&
        REQUIRED_DISTRIBUTION_FILES.all? { |path| File.file?(File.join(@distribution_root, path)) }
      unless complete
        raise ValidationError, "Product Factory distribution is incomplete"
      end

      sources = {}
      Dir.glob(File.join(library_root, "**/*.rb")).sort.each do |source|
        relative = source.delete_prefix("#{@distribution_root}/")
        sources[File.join(".product-factory/runtime", relative)] = source
      end
      sources[".product-factory/runtime/templates/config.yml"] = config_source
      Dir.glob(
        File.join(project_root, "**/*"),
        File::FNM_DOTMATCH
      ).sort.each do |source|
        next unless File.file?(source)

        relative = source.delete_prefix("#{project_root}/")
        sources[relative] = source
        sources[File.join(".product-factory/runtime/templates/project", relative)] = source
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

    def journal_path = File.join(@target_root, ".product-factory-journal.jsonl")

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
          verify: ->(operation) { managed.current_state(target_root: @target_root, path: operation.target).nil? }
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
      if File.exist?(path)
        return if File.binread(path) == bytes

        raise ConflictError, "#{Config::PATH} already exists"
      end

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
      attributes = operation.attributes
      expected_hash = Digest::SHA256.hexdigest(attributes.fetch("content_base64").unpack1("m0"))
      state = ManagedFiles.new(sources: {}).current_state(target_root: @target_root, path: operation.target)
      state && state.fetch(:hash) == expected_hash && state.fetch(:mode) == attributes.fetch("mode")
    rescue Errno::ENOENT, KeyError, ArgumentError
      false
    end

    def verified_installation?(operation)
      return false unless operation.target == Installation::PATH && operation.attributes.is_a?(Hash)

      state = Installation.load(@target_root).to_h
      return false unless state == operation.attributes

      state.fetch("managed_file_hashes").all? do |path, expected_hash|
        ManagedFiles.new(sources: {}).current_hash(target_root: @target_root, path:) == expected_hash
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

    def validate_target!
      root = File.lstat(@target_root)
      raise ValidationError, "target root is a symlink" if root.symlink?
      raise ValidationError, "target root is not a directory" unless root.directory?
      raise ValidationError, "target root path contains a symlink" unless File.realpath(@target_root) == @target_root

      factory = File.join(@target_root, ".product-factory")
      if File.exist?(factory) || File.symlink?(factory)
        stat = File.lstat(factory)
        raise ValidationError, ".product-factory is a symlink" if stat.symlink?
        raise ValidationError, ".product-factory is not a directory" unless stat.directory?
      end

      [Config::PATH, Installation::PATH].each do |relative_path|
        path = File.join(@target_root, relative_path)
        next unless File.exist?(path) || File.symlink?(path)

        stat = File.lstat(path)
        raise ValidationError, "#{relative_path} is a symlink" if stat.symlink?
        raise ValidationError, "#{relative_path} is not a file" unless stat.file?
      end
    rescue Errno::ENOENT
      raise ValidationError, "target root does not exist"
    end

    def validate_plan!(plan)
      raise ValidationError, "plan target does not match setup target" unless plan.target_root == @target_root

      installation = Installation.load(@target_root)
      sources = managed_sources
      installed_hashes = installation.managed_file_hashes
      validate_installed_hashes!(installed_hashes, current_targets: sources.keys)
      managed_targets = sources.keys | installed_hashes.keys
      operations = plan.operations
      seed_operations = operations.select { |operation| operation.kind == "seed_config" }
      managed_operations = operations.select { |operation| %w[write_file delete_file].include?(operation.kind) }
      installation_operations = operations.select { |operation| operation.kind == "write_installation" }

      unless operations.length == seed_operations.length + managed_operations.length + installation_operations.length
        raise ValidationError, "plan contains unsupported operation"
      end
      unless seed_operations.length <= 1 && seed_operations.all? { |operation| operation.target == Config::PATH }
        raise ValidationError, "plan has invalid config seed"
      end
      unless managed_operations.map(&:target).uniq.length == managed_operations.length &&
          managed_operations.all? { |operation| managed_targets.include?(operation.target) }
        raise ValidationError, "plan has invalid managed target"
      end

      seed_operations.each { |operation| validate_seed_operation(operation) }
      managed_operations.each { |operation| validate_managed_operation(operation) }
      installation_operations.each do |operation|
        unless operation.target == Installation::PATH && operation.attributes.is_a?(Hash)
          raise ValidationError, "plan has invalid installation state"
        end
        state = Installation.new(operation.attributes)
        validate_installed_hashes!(state.managed_file_hashes, current_targets: sources.keys)
      end

      return if operations.empty?

      unless installation_operations.length == 1 && operations.last == installation_operations.first
        raise ValidationError, "plan must end with installation state"
      end
      expected = seed_operations + managed_operations + installation_operations
      raise ValidationError, "plan operation order is invalid" unless operations == expected
    end

    def validate_managed_operation(operation)
      attributes = operation.attributes
      reason = attributes["reason"] if attributes.is_a?(Hash)
      valid_reason = reason.nil? || ManagedFiles::RESOLUTIONS.include?(reason)
      expected_hash = attributes["expected_local_hash"] if attributes.is_a?(Hash)
      valid_expected_hash = attributes.is_a?(Hash) && attributes.key?("expected_local_hash") &&
        (expected_hash.nil? || expected_hash.is_a?(String) && expected_hash.match?(/\A[0-9a-f]{64}\z/))
      if operation.kind == "delete_file"
        valid = attributes.is_a?(Hash) &&
          (attributes.keys - %w[expected_local_hash reason]).empty? &&
          valid_expected_hash && valid_reason
        raise ValidationError, "plan has invalid managed operation" unless valid

        return
      end

      valid = operation.kind == "write_file" &&
        attributes.is_a?(Hash) &&
        attributes["content_base64"].is_a?(String) &&
        attributes["mode"].is_a?(Integer) &&
        attributes["mode"].between?(0, 0o7777) &&
        (attributes.keys - %w[content_base64 expected_local_hash mode reason]).empty? &&
        valid_expected_hash && valid_reason
      raise ValidationError, "plan has invalid managed operation" unless valid

      attributes.fetch("content_base64").unpack1("m0")
    rescue ArgumentError
      raise ValidationError, "plan has invalid managed operation"
    end

    def validate_installed_hashes!(hashes, current_targets:)
      valid = hashes.is_a?(Hash) && hashes.all? do |path, hash|
        path.is_a?(String) && hash.is_a?(String) && hash.match?(/\A[0-9a-f]{64}\z/) &&
          managed_target?(path, current_targets:)
      end
      raise ValidationError, "installation has invalid managed file hash" unless valid
    end

    def managed_target?(path, current_targets:)
      parts = path.split(File::SEPARATOR, -1)
      safe = !path.empty? && !path.start_with?(File::SEPARATOR) &&
        parts.none? { |part| part.empty? || part == "." || part == ".." }
      safe && (
        current_targets.include?(path) ||
        path == "bin/product-factory" ||
        LEGACY_MANAGED_PREFIXES.any? { |prefix| path.start_with?(prefix) }
      )
    end

    def validate_preconditions!(plan)
      operation_handlers = handlers
      files = ManagedFiles.new(sources: {})

      plan.operations.each do |operation|
        next unless %w[write_file delete_file].include?(operation.kind)

        handler = operation_handlers.fetch(operation.kind)
        next if handler.verify.call(operation)

        expected = operation.attributes.fetch("expected_local_hash")
        actual = files.current_hash(target_root: @target_root, path: operation.target)
        next if actual == expected

        raise ConflictError, "#{operation.target} changed since plan"
      end
    end
  end
end
