# frozen_string_literal: true

module ProductFactory
  module Setup
    class Workflow < Service
      def initialize(
        distribution:, target_root:, input:, output:, clock:, shell:, github_client:,
        github_state: nil, github_writer: nil, artifact_store: nil, arguments: []
      )
        super()
        @distribution = distribution
        @root = target_root
        @input = input
        @output = output
        @clock = clock
        @shell = shell
        @github_client = github_client
        @github_state = github_state
        @github_writer = github_writer
        @artifact_store = artifact_store
        @arguments = arguments
      end

      def call
        validate_target
        options = Options.call(arguments: @arguments)
        pending = run_store.pending_plan
        return resume(pending) if pending

        configuration = Configuration.call(
          distribution: @distribution, target_root: @root, input: @input, output: @output,
          github_client: @github_client, shell: @shell
        )
        config = configuration.fetch(:config)
        prepare_external(config)
        @github_state.snapshot
        artifact_snapshot, product_context = snapshot_product_context(config)
        plan = build_plan(configuration, artifact_snapshot, options, product_context:)
        Preview.call(plan:, output: @output, target_root: @root)
        raise ConflictError, "plan has conflicts" unless plan.applicable?
        return complete_noop(plan) if plan.operations.empty?
        return :declined unless confirmed?

        run_store.confirm(plan)
        execute(plan)
      end

      private

      def build_plan(configuration, artifact_snapshot, options, product_context:)
        PlanBuilder.call(
          distribution: @distribution, target_root: @root, clock: @clock,
          plan_validator:, resolutions: options.fetch(:resolutions), configuration:,
          github_state: @github_state, artifact_snapshot:, schema: provisioning_schema,
          adoptions: options.fetch(:adoptions), journal_events: run_store.journal.events,
          product_context:, actor: "human:#{ENV.fetch('USER', 'unknown')}",
          version_link: @artifact_store.link(ProductContext.document_ids(configuration.fetch(:config)).last)
        )
      end

      def snapshot_product_context(config)
        document_ids = Artifacts::Planner::DOCUMENT_IDS + ProductContext.document_ids(config)
        snapshot = @artifact_store.snapshot(document_ids:)
        [snapshot, ProductContextWizard.call(input: @input, output: @output, snapshot:, document_ids:)]
      end

      def resume(plan)
        validate_plan!(plan)
        validate_configuration!(plan)
        config = config_from(plan)
        prepare_external(config)
        @github_state.snapshot
        document_ids = Artifacts::Planner::DOCUMENT_IDS + ProductContext.document_ids(config)
        @artifact_store.snapshot(document_ids:)
        @output.puts("Resuming #{plan.run_id}")
        execute(plan)
      end

      def execute(plan)
        validate_plan!(plan)
        validate_configuration!(plan)
        handlers.validate_preconditions!(plan)
        Executor.new(journal: run_store.journal, handlers: handlers.to_h).apply(plan)
      end

      def prepare_external(config)
        @github_state ||= GitHub::State.new(config:, client: @github_client)
        @github_writer ||= GitHub::Writer.new(config:, client: @github_client, state: @github_state)
        artifact_store(config)
      end

      def artifact_store(cfg) = @artifact_store ||= Artifacts.build(config: cfg, target_root: @root, shell: @shell)

      def config_from(plan)
        return Config.load(@root) if File.exist?(File.join(@root, Config::PATH))

        Config.new(YAML.safe_load(seed_config_bytes(plan), aliases: false))
      end

      def validate_configuration!(plan)
        return unless plan.configuration_fingerprint
        return if Digest::SHA256.hexdigest(config_bytes(plan)) == plan.configuration_fingerprint

        raise ConflictError, "configuration changed after planning"
      end

      def config_bytes(plan)
        path = File.join(@root, Config::PATH)
        return File.binread(path) if File.exist?(path)

        seed_config_bytes(plan)
      end

      def seed_config_bytes(plan)
        seed = plan.operations.find { |operation| operation.kind == Operation::SEED_CONFIG }
        raise ValidationError, "stored plan has no configuration" unless seed

        seed.attributes.fetch("content_base64").unpack1("m0")
      end

      def validate_plan!(plan)
        plan_validator.call(plan, sources: @distribution.factory_sources)
        raise ConflictError, "plan has conflicts" unless plan.applicable?
      end

      def complete_noop(plan)
        @output.puts("Product Factory is up to date")
        run_store.complete_noop(plan)
        :success
      end

      def confirmed?
        @output.print("Apply this plan? [yes/no] ")
        @input.gets&.chomp == "yes"
      end

      def validate_target = TargetValidator.call(root: @root)
      def provisioning_schema = Schema.call(bytes: @distribution.provisioning_schema_bytes)
      def run_store = @run_store ||= RunStore.new(root: @root, clock: @clock)
      def plan_validator = @plan_validator ||= PlanValidator.new(target_root: @root)

      def handlers
        @handlers ||= OperationHandlers.new(
          target_root: @root, github_writer: @github_writer,
          github_state: @github_state, artifact_store: @artifact_store
        )
      end
    end
  end
end
