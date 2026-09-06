# frozen_string_literal: true

module ProductFactory
  module Setup
    class Workflow < Service
      def initialize(
        distribution:, target_root:, input:, output:, clock:, shell:, github_client:,
        github_state: nil, github_writer: nil, wiki_repository: nil, arguments: []
      )
        super()
        @distribution = distribution
        @target_root = target_root
        @input = input
        @output = output
        @clock = clock
        @shell = shell
        @github_client = github_client
        @github_state = github_state
        @github_writer = github_writer
        @wiki_repository = wiki_repository
        @arguments = arguments
      end

      def call
        validate_target
        options = Options.call(arguments: @arguments)
        pending = run_store.pending_plan
        return resume(pending) if pending

        configuration = Configuration.call(
          distribution: @distribution, target_root: @target_root, input: @input, output: @output,
          github_client: @github_client, shell: @shell
        )
        prepare_external(configuration.fetch(:config))
        @github_state.snapshot
        wiki_snapshot = @wiki_repository.snapshot
        plan = build_plan(configuration, wiki_snapshot, options)
        Preview.call(plan:, output: @output, target_root: @target_root)
        raise ConflictError, "plan has conflicts" unless plan.applicable?
        return complete_noop(plan) if plan.operations.empty?
        return :declined unless confirmed?

        run_store.confirm(plan)
        execute(plan)
      end

      private

      def build_plan(configuration, wiki_snapshot, options)
        PlanBuilder.call(
          distribution: @distribution, target_root: @target_root, clock: @clock,
          plan_validator:, resolutions: options.fetch(:resolutions), configuration:,
          github_state: @github_state, wiki_snapshot:, schema: provisioning_schema,
          adoptions: options.fetch(:adoptions), journal_events: run_store.journal.events
        )
      end

      def resume(plan)
        prepare_external(config_from(plan))
        @github_state.snapshot
        @wiki_repository.snapshot
        @output.puts("Resuming #{plan.run_id}")
        execute(plan)
      end

      def execute(plan)
        validate_plan!(plan)
        handlers.validate_preconditions!(plan)
        Executor.new(journal: run_store.journal, handlers: handlers.to_h).apply(plan)
      end

      def prepare_external(config)
        @github_state ||= GitHub::State.new(config:, client: @github_client)
        @github_writer ||= GitHub::Writer.new(config:, client: @github_client, state: @github_state)
        wiki_repository(config)
      end

      def wiki_repository(config)
        @wiki_repository ||= Wiki::Repository.new(
          organization: config.github.fetch("organization"),
          repository: config.github.fetch("repository"), shell: @shell
        )
      end

      def config_from(plan)
        return Config.load(@target_root) if File.exist?(File.join(@target_root, Config::PATH))

        seed = plan.operations.find { |operation| operation.kind == Operation::SEED_CONFIG }
        raise ValidationError, "stored plan has no configuration" unless seed

        Config.new(YAML.safe_load(seed.attributes.fetch("content_base64").unpack1("m0"), aliases: false))
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

      def validate_target = TargetValidator.call(root: @target_root)
      def provisioning_schema = Schema.call(bytes: @distribution.provisioning_schema_bytes)
      def run_store = @run_store ||= RunStore.new(root: @target_root, clock: @clock)
      def plan_validator = @plan_validator ||= PlanValidator.new(target_root: @target_root)

      def handlers
        @handlers ||= OperationHandlers.new(
          target_root: @target_root, github_writer: @github_writer,
          github_state: @github_state, wiki_repository: @wiki_repository
        )
      end
    end
  end
end
