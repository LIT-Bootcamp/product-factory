# frozen_string_literal: true

module ProductFactory
  class Setup
    class PlanBuilder
      def self.call(...) = new(...).call

      def initialize(distribution:, target_root:, clock:, plan_validator:, resolutions:)
        @distribution = distribution
        @target_root = target_root
        @clock = clock
        @plan_validator = plan_validator
        @resolutions = resolutions
      end

      def call
        installation = Installation.load(@target_root)
        sources = @distribution.factory_sources
        @plan_validator.validate_hashes!(installation.factory_file_hashes, current_targets: sources.keys)
        Config.load(@target_root) if config_exists?

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
        append_installation(operations, installation, sync.fetch(:next_hashes), run_id)

        Plan.new(
          run_id:,
          mode: installed? ? "refresh" : "setup",
          operations:,
          conflicts: sync.fetch(:conflicts),
          target_root: @target_root
        )
      end

      def config_operation
        Operation.new(
          kind: "seed_config",
          target: Config::PATH,
          attributes: { "content_base64" => [@distribution.config_bytes].pack("m0") }
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
        operations << Operation.new(kind: "write_installation", target: Installation::PATH, attributes: state)
      end

      def installation_changed?(operations, installation, next_hashes)
        !installed? || operations.any? || next_hashes != installation.factory_file_hashes
      end

      def config_exists? = File.exist?(File.join(@target_root, Config::PATH))
      def installed? = File.exist?(File.join(@target_root, Installation::PATH))
    end
  end
end
