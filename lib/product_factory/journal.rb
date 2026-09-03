require "json"
require "time"

module ProductFactory
  class Journal
    EVENT_FIELDS = {
      "run_confirmed" => %w[run_id],
      "operation_started" => %w[run_id operation_id],
      "operation_completed" => %w[run_id operation_id],
      "operation_failed" => %w[run_id operation_id error_class message],
      "run_completed" => %w[run_id status]
    }.freeze

    def initialize(path:, clock:)
      @path = path
      @clock = clock
    end

    def append(event)
      record = event.transform_keys(&:to_s).merge("recorded_at" => @clock.call.utc.iso8601)
      validate_event!(record)
      File.open(@path, File::WRONLY | File::CREAT | File::APPEND) do |file|
        file.write(JSON.generate(record) + "\n")
        file.flush
        file.fsync
      end
      record
    end

    def events
      return [] unless File.exist?(@path)

      File.foreach(@path).with_index(1).map do |line, number|
        event = JSON.parse(line)
        validate_event!(event)
        event
      rescue JSON::ParserError, ValidationError
        raise ValidationError, "Invalid journal line #{number}"
      end
    end

    def completed_operation_ids(run_id)
      events.filter_map do |event|
        event["operation_id"] if event["event"] == "operation_completed" &&
          event["run_id"] == run_id
      end
    end

    private

    def validate_event!(event)
      raise ValidationError, "Invalid journal event" unless event.is_a?(Hash)

      required = EVENT_FIELDS[event["event"]]
      raise ValidationError, "Invalid journal event" unless required
      unless (required + ["recorded_at"]).all? { |key| event[key].is_a?(String) }
        raise ValidationError, "Invalid journal event"
      end
      if event["event"] == "run_completed" && event["status"] != "success"
        raise ValidationError, "Invalid journal event"
      end

      Time.iso8601(event["recorded_at"])
    rescue ArgumentError
      raise ValidationError, "Invalid journal event"
    end
  end
end
