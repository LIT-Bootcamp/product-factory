# frozen_string_literal: true

module ProductFactory
  module Setup
    class Preview < Service
      def initialize(plan:, output:, target_root:, plan_path: nil)
        super()
        @plan = plan
        @output = output
        @target_root = target_root
        @plan_path = plan_path
      end

      def call
        @output.puts("Mode: #{@plan.mode}")
        @output.puts("Target: #{@target_root}")
        @plan.operations.each do |operation|
          reason = operation.attributes["reason"] || "required"
          @output.puts("#{verb(operation, reason)} #{operation.target} — #{reason}")
        end
        @plan.conflicts.each { |conflict| print_conflict(conflict) }
        @output.puts("Plan path: #{@plan_path}") if @plan_path
      end

      private

      def print_conflict(conflict)
        target = conflict["resource"] || conflict["path"]
        @output.puts("Conflict: #{target} — #{conflict['reason'] || 'resolution required'}")
        @output.puts("  #{conflict['adopt_with']}") if conflict["adopt_with"]
      end

      def verb(operation, reason)
        return "SYNC" if operation.kind == Operation::SYNC_WIKI
        return "ADOPT" if reason == "adopted"
        return "CREATE" if operation.kind == Operation::SEED_CONFIG
        return "CREATE" if new_file?(operation)
        return "CREATE" if reason == "missing"

        "UPDATE"
      end

      def new_file?(operation)
        operation.kind == Operation::WRITE_FILE && operation.attributes["expected_local_hash"].nil?
      end
    end
  end
end
