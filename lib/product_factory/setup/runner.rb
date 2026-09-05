# frozen_string_literal: true

module ProductFactory
  module Setup
    class Runner
      attr_reader :plan_path

      def self.from_cli(cwd:, input:, output:, error: $stderr)
        new(
          distribution_root: File.expand_path("../../..", __dir__), target_root: cwd,
          input:, output:, clock: -> { Time.now }, shell: StreamShell.new(output, error)
        )
      end

      def initialize(
        distribution_root:, target_root:, input:, output:, clock:, shell: nil, github_client: nil,
        github_state: nil, github_writer: nil, wiki_repository: nil
      )
        @distribution = Distribution.new(distribution_root)
        @target_root = File.expand_path(target_root)
        @input = input
        @output = output
        @clock = clock
        @shell = shell || StreamShell.new(output, $stderr)
        @github_client = github_client || GitHub::Client.new(shell: @shell)
        @github_state = github_state
        @github_writer = github_writer
        @wiki_repository = wiki_repository
      end

      def run(arguments)
        Workflow.call(
          distribution: @distribution, target_root: @target_root, input: @input, output: @output,
          clock: @clock, shell: @shell, github_client: @github_client,
          github_state: @github_state, github_writer: @github_writer,
          wiki_repository: @wiki_repository, arguments:
        )
      end

      def plan(resolutions: {})
        validate_target
        save_plan(
          PlanBuilder.call(
            distribution: @distribution, target_root: @target_root, clock: @clock,
            plan_validator:, resolutions:
          )
        )
      end

      def plan_and_print(arguments)
        result = plan(resolutions: parse_resolutions(arguments))
        Preview.call(plan: result, output: @output, target_root: @target_root, plan_path:)
        raise ConflictError, "plan has conflicts" unless result.applicable?

        result
      end

      def load_and_apply(path) = apply(Plan.load(path))

      def apply(plan)
        validate_plan!(plan)
        return :success if plan.operations.empty?

        journal = Journal.new(path: journal_path, clock: @clock)
        operation_handlers.validate_preconditions!(plan)
        return :declined unless confirm?(journal, plan)

        Executor.new(journal:, handlers: operation_handlers.to_h).apply(plan)
      end

      private

      def validate_plan!(plan)
        validate_target
        plan_validator.call(plan, sources: @distribution.factory_sources)
        raise ConflictError, "plan has conflicts" unless plan.applicable?
      end

      def save_plan(plan)
        @plan_path = File.join(Dir.tmpdir, "product-factory-#{plan.run_id}.json")
        plan.write(@plan_path)
        plan
      end

      def parse_resolutions(arguments)
        values = arguments.dup
        resolutions = {}
        until values.empty?
          argument = values.shift
          value = argument == "--resolve" ? values.shift : argument.delete_prefix("--resolve=")
          path, resolution = value&.split("=", 2)
          raise UsageError, "resolve must be PATH=VALUE" unless path && resolution

          resolutions[path] = resolution
        end
        resolutions
      end

      def confirm?(journal, plan)
        confirmed = journal.events.any? do |event|
          event["event"] == "run_confirmed" && event["run_id"] == plan.run_id
        end
        return true if confirmed

        @output.puts("#{plan.operations.count} operations")
        @output.print("Apply this plan? [yes/no] ")
        return false unless @input.gets&.chomp == "yes"

        journal.append(event: "run_confirmed", run_id: plan.run_id)
        true
      end

      def journal_path = File.join(@target_root, ".product-factory-journal.jsonl")
      def validate_target = TargetValidator.call(root: @target_root)
      def plan_validator = @plan_validator ||= PlanValidator.new(target_root: @target_root)
      def operation_handlers = @operation_handlers ||= OperationHandlers.new(target_root: @target_root)
    end
  end
end
