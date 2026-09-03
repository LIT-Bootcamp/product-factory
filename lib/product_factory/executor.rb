module ProductFactory
  class Executor
    Handler = Data.define(:apply, :verify)

    def initialize(journal:, handlers:)
      @journal = journal
      @handlers = handlers.transform_keys(&:to_s)
    end

    def apply(plan)
      completed_ids = @journal.completed_operation_ids(plan.run_id)

      plan.operations.each do |operation|
        handler = @handlers[operation.kind]
        raise ValidationError, "unknown operation handler: #{operation.kind}" unless handler
        raise ValidationError, "missing verifier for #{operation.kind}" unless handler.verify.respond_to?(:call)
        raise ValidationError, "invalid handler for #{operation.kind}" unless handler.apply.respond_to?(:call)

        next if completed_ids.include?(operation.id) && handler.verify.call(operation)

        execute(plan.run_id, operation, handler)
      end

      @journal.append(event: "run_completed", run_id: plan.run_id, status: "success")
      :success
    end

    private

    def execute(run_id, operation, handler)
      @journal.append(
        event: "operation_started",
        run_id:,
        operation_id: operation.id
      )

      handler.apply.call(operation)
      unless handler.verify.call(operation)
        raise ValidationError, "verification failed for #{operation.id}"
      end

      @journal.append(
        event: "operation_completed",
        run_id:,
        operation_id: operation.id
      )
    rescue StandardError => error
      @journal.append(
        event: "operation_failed",
        run_id:,
        operation_id: operation.id,
        error_class: error.class.name,
        message: error.message
      )
      raise
    end
  end
end
