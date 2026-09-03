# frozen_string_literal: true

require "time"
require "tmpdir"

module ProductFactory
  class Setup
    LEGACY_MANAGED_PREFIXES = %w[
      .product-factory/runtime/
      .product-factory/schemas/
      .product-factory/spec/
    ].freeze
    REQUIRED_DISTRIBUTION_FILES = Distribution::REQUIRED_FILES

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
      @distribution = Distribution.new(distribution_root)
      @target_root = File.expand_path(target_root)
      @input = input
      @output = output
      @clock = clock
    end

    def plan(resolutions: {})
      validate_target!
      installation = Installation.load(@target_root)
      sources = @distribution.managed_sources
      installed_hashes = installation.managed_file_hashes
      plan_validator.validate_hashes!(installed_hashes, current_targets: sources.keys)
      Config.load(@target_root) if config_exists?

      result = ManagedFiles.new(sources:).plan(
        target_root: @target_root,
        installed_hashes:,
        resolutions:
      )
      run_id = RunId.generate(clock: @clock)
      operations = result.fetch(:operations)
      operations.unshift(seed_config_operation) unless config_exists?
      append_installation_operation(operations, installation, result.fetch(:next_hashes), run_id)

      save_plan(build_plan(run_id:, operations:, conflicts: result.fetch(:conflicts)))
    end

    def plan_and_print(argv)
      result = plan(resolutions: parse_resolutions(argv))
      @output.puts("Mode: #{result.mode}")
      @output.puts("Target: #{@target_root}")
      result.operations.each do |operation|
        @output.puts("#{operation.id} #{operation.kind} #{operation.target}")
      end
      result.conflicts.each do |conflict|
        @output.puts("Conflict: #{conflict.fetch('path')} (keep_local, take_upstream, manual_merge)")
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
      plan_validator.call(plan, sources: @distribution.managed_sources)
      raise ConflictError, "plan has conflicts" unless plan.applicable?
      return :success if plan.operations.empty?

      journal = Journal.new(path: journal_path, clock: @clock)
      operation_handlers.validate_preconditions!(plan)
      return :declined unless confirm?(journal, plan)

      Executor.new(journal:, handlers: operation_handlers.to_h).apply(plan)
    end

    private

    def seed_config_operation
      Operation.new(
        kind: "seed_config",
        target: Config::PATH,
        attributes: {
          "content_base64" => [@distribution.config_bytes].pack("m0")
        }
      )
    end

    def append_installation_operation(operations, installation, next_hashes, run_id)
      return unless installation_changed?(operations, installation, next_hashes)

      state = installation.with(
        "factory_version" => VERSION,
        "installed_at" => @clock.call.utc.iso8601,
        "installed_by" => ENV.fetch("USER", "unknown"),
        "managed_file_hashes" => next_hashes,
        "last_successful_setup_run" => run_id,
        "pending_operations" => []
      ).to_h
      operations << Operation.new(kind: "write_installation", target: Installation::PATH, attributes: state)
    end

    def installation_changed?(operations, installation, next_hashes)
      !installed? || operations.any? || next_hashes != installation.managed_file_hashes
    end

    def build_plan(run_id:, operations:, conflicts:)
      Plan.new(
        run_id:,
        mode: installed? ? "refresh" : "setup",
        operations:,
        conflicts:,
        target_root: @target_root
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
    def config_exists? = File.exist?(File.join(@target_root, Config::PATH))
    def installed? = File.exist?(File.join(@target_root, Installation::PATH))

    def confirmed?(journal, run_id)
      journal.events.any? { |event| event["event"] == "run_confirmed" && event["run_id"] == run_id }
    end

    def confirm?(journal, plan)
      return true if confirmed?(journal, plan.run_id)

      @output.puts("#{plan.operations.count} operations")
      @output.print("Apply this plan? [yes/no] ")
      return false unless @input.gets&.chomp == "yes"

      journal.append(event: "run_confirmed", run_id: plan.run_id)
      true
    end

    def validate_target!
      root = File.lstat(@target_root)
      raise ValidationError, "target root is a symlink" if root.symlink?
      raise ValidationError, "target root is not a directory" unless root.directory?
      raise ValidationError, "target root path contains a symlink" unless File.realpath(@target_root) == @target_root

      validate_factory_directory!
      validate_state_files!
    rescue Errno::ENOENT
      raise ValidationError, "target root does not exist"
    end

    def validate_factory_directory!
      factory = File.join(@target_root, ".product-factory")
      return unless File.exist?(factory) || File.symlink?(factory)

      stat = File.lstat(factory)
      raise ValidationError, ".product-factory is a symlink" if stat.symlink?
      raise ValidationError, ".product-factory is not a directory" unless stat.directory?
    end

    def validate_state_files!
      [Config::PATH, Installation::PATH].each do |relative_path|
        path = File.join(@target_root, relative_path)
        next unless File.exist?(path) || File.symlink?(path)

        stat = File.lstat(path)
        raise ValidationError, "#{relative_path} is a symlink" if stat.symlink?
        raise ValidationError, "#{relative_path} is not a file" unless stat.file?
      end
    end

    def plan_validator
      @plan_validator ||= PlanValidator.new(target_root: @target_root)
    end

    def operation_handlers
      @operation_handlers ||= OperationHandlers.new(target_root: @target_root)
    end
  end
end
