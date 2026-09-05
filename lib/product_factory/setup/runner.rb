# frozen_string_literal: true

module ProductFactory
  module Setup
    class Runner
      attr_reader :plan_path

      def self.from_cli(cwd:, input:, output:)
        new(
          distribution_root: File.expand_path("../../..", __dir__),
          target_root: cwd,
          input:,
          output:,
          clock: -> { Time.now }
        )
      end

      def initialize(distribution_root:, target_root:, input:, output:, clock:)
        @distribution = ProductFactory::Distribution.new(distribution_root)
        @target_root = File.expand_path(target_root)
        @input = input
        @output = output
        @clock = clock
      end

      def plan(resolutions: {})
        validate_target
        save_plan(
          ProductFactory::Setup::PlanBuilder.call(
            distribution: @distribution,
            target_root: @target_root,
            clock: @clock,
            plan_validator:,
            resolutions:
          )
        )
      end

      def plan_and_print(arguments)
        result = plan(resolutions: parse_resolutions(arguments))
        print_plan(result)
        raise ProductFactory::ConflictError, "plan has conflicts" unless result.applicable?

        result
      end

      def load_and_apply(path) = apply(ProductFactory::Plan.load(path))

      def apply(plan)
        validate_target
        plan_validator.call(plan, sources: @distribution.factory_sources)
        raise ProductFactory::ConflictError, "plan has conflicts" unless plan.applicable?
        return :success if plan.operations.empty?

        journal = ProductFactory::Journal.new(path: journal_path, clock: @clock)
        operation_handlers.validate_preconditions!(plan)
        return :declined unless confirm?(journal, plan)

        ProductFactory::Executor.new(journal:, handlers: operation_handlers.to_h).apply(plan)
      end

      private

      def print_plan(plan)
        @output.puts("Mode: #{plan.mode}")
        @output.puts("Target: #{@target_root}")
        plan.operations.each { |operation| @output.puts("#{operation.id} #{operation.kind} #{operation.target}") }
        plan.conflicts.each do |conflict|
          @output.puts("Conflict: #{conflict.fetch('path')} (keep_local, take_upstream, manual_merge)")
        end
        @output.puts("Plan path: #{plan_path}")
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
          raise ProductFactory::UsageError, "resolve must be PATH=VALUE" unless path && resolution

          resolutions[path] = resolution
        end
        resolutions
      end

      def journal_path = File.join(@target_root, ".product-factory-journal.jsonl")

      def confirm?(journal, plan)
        return true if confirmed?(journal, plan.run_id)

        @output.puts("#{plan.operations.count} operations")
        @output.print("Apply this plan? [yes/no] ")
        return false unless @input.gets&.chomp == "yes"

        journal.append(event: "run_confirmed", run_id: plan.run_id)
        true
      end

      def confirmed?(journal, run_id)
        journal.events.any? { |event| event["event"] == "run_confirmed" && event["run_id"] == run_id }
      end

      def validate_target = ProductFactory::Setup::TargetValidator.call(root: @target_root)

      def plan_validator
        @plan_validator ||= ProductFactory::Setup::PlanValidator.new(target_root: @target_root)
      end

      def operation_handlers
        @operation_handlers ||= ProductFactory::Setup::OperationHandlers.new(target_root: @target_root)
      end
    end
  end
end
