# frozen_string_literal: true

module ProductFactory
  module Setup
    class PlanBuilder < Service
      def initialize(
        distribution:, target_root:, clock:, plan_validator:, resolutions:, configuration: nil,
        github_state: nil, wiki_snapshot: nil, schema: nil, adoptions: [], journal_events: []
      )
        super()
        @distribution = distribution
        @target_root = target_root
        @clock = clock
        @plan_validator = plan_validator
        @resolutions = resolutions
        @configuration = configuration
        @github_state = github_state
        @wiki_snapshot = wiki_snapshot
        @schema = schema
        @adoptions = adoptions
        @journal_events = journal_events
      end

      def call
        installation = Installation.load(@target_root)
        sources = @distribution.factory_sources
        @plan_validator.validate_hashes!(installation.factory_file_hashes, current_targets: sources.keys)
        Config.load(@target_root) if config_exists? && !full_setup?

        sync = FileSync::Planner.call(
          sources:,
          target_root: @target_root,
          installed_hashes: installation.factory_file_hashes,
          resolutions: @resolutions
        )
        build_plan(installation, sync)
      end

      private

      def build_plan(installation, sync)
        run_id = RunId.generate(clock: @clock)
        operations = sync.fetch(:operations)
        operations.unshift(config_operation) unless config_exists?
        conflicts = sync.fetch(:conflicts)
        add_remote_operations(operations, conflicts, installation, run_id) if full_setup?
        append_installation(operations, installation, sync.fetch(:next_hashes), run_id)

        Plan.new(
          run_id:,
          mode: installed? ? "refresh" : "setup",
          operations:,
          conflicts:,
          target_root: @target_root
        )
      end

      def config_operation
        Operation.new(
          kind: Operation::SEED_CONFIG,
          target: Config::PATH,
          attributes: { "content_base64" => [config_bytes].pack("m0") }
        )
      end

      def append_installation(operations, installation, next_hashes, run_id)
        return unless installation_changed?(operations, installation, next_hashes)

        state = installation.with(
          "factory_version" => VERSION,
          "installed_at" => @clock.call.utc.iso8601,
          "installed_by" => ENV.fetch("USER", "unknown"),
          "factory_file_hashes" => next_hashes,
          "last_successful_setup_run" => run_id,
          "pending_operations" => []
        ).to_h
        operations << Operation.new(kind: Operation::WRITE_INSTALLATION, target: Installation::PATH, attributes: state)
      end

      def installation_changed?(operations, installation, next_hashes)
        !installed? || operations.any? || next_hashes != installation.factory_file_hashes
      end

      def add_remote_operations(operations, conflicts, installation, run_id)
        github = GitHub::Planner.call(
          config: @configuration.fetch(:config), schema: @schema, state: @github_state,
          installed_hashes: installation.github_resource_hashes, adoptions: @adoptions
        )
        operations.concat(github.fetch(:operations))
        conflicts.concat(github.fetch(:conflicts))
        wiki = Wiki::Planner.call(
          schema: @schema, snapshot: @wiki_snapshot, installed_hashes: installation.wiki_page_hashes,
          adoptions: @adoptions, run_id:, recorded_at: @clock.call.utc.iso8601,
          operation_summaries: operations.map(&:target), failures: setup_failures
        )
        operations.concat(wiki.fetch(:operations))
        conflicts.concat(wiki.fetch(:conflicts))
      end

      def setup_failures = @journal_events.select { |event| event["event"] == "operation_failed" }
      def config_bytes = @configuration ? @configuration.fetch(:bytes) : @distribution.config_bytes
      def full_setup? = !@configuration.nil?

      def config_exists? = File.exist?(File.join(@target_root, Config::PATH))
      def installed? = File.exist?(File.join(@target_root, Installation::PATH))
    end
  end
end
