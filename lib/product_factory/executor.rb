# frozen_string_literal: true

module ProductFactory
  class Executor
    def initialize(journal:, handlers:)
      @journal = journal
      @handlers = handlers.transform_keys(&:to_s)
    end

    def apply(plan)
      raise ConflictError, "plan has conflicts" unless plan.applicable?

      handlers = plan.operations.map { |operation| [operation, handler_for(operation)] }
      completed_ids = @journal.completed_operation_ids(plan.run_id)

      handlers.each do |operation, handler|
        next if completed_ids.include?(operation.id) && handler.fetch(:verify).call(operation)

        execute(plan.run_id, operation, handler)
      end

      @journal.append(event: "run_completed", run_id: plan.run_id, status: "success")
      :success
    end

    private

    def handler_for(operation)
      handler = @handlers[operation.kind]
      raise ValidationError, "unknown operation handler: #{operation.kind}" unless handler
      raise ValidationError, "invalid handler for #{operation.kind}" unless handler[:apply].respond_to?(:call)
      raise ValidationError, "missing verifier for #{operation.kind}" unless handler[:verify].respond_to?(:call)

      handler
    rescue TypeError, NoMethodError
      raise ValidationError, "invalid handler for #{operation.kind}"
    end

    def execute(run_id, operation, handler)
      started = {
        event: "operation_started",
        run_id:,
        operation_id: operation.id
      }
      reason = operation.attributes["reason"] if operation.attributes.is_a?(Hash)
      started[:reason] = reason if reason.is_a?(String)
      @journal.append(started)

      handler.fetch(:apply).call(operation)
      raise ValidationError, "verification failed for #{operation.id}" unless handler.fetch(:verify).call(operation)

      @journal.append(
        event: "operation_completed",
        run_id:,
        operation_id: operation.id
      )
    rescue StandardError => e
      @journal.append(
        event: "operation_failed",
        run_id:,
        operation_id: operation.id,
        error_class: e.class.name,
        message: e.message
      )
      raise
    end
  end
end
