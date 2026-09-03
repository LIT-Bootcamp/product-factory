require "json"
require "time"

module ProductFactory
  class Journal
    def initialize(path:, clock:)
      @path = path
      @clock = clock
    end

    def append(event)
      record = event.transform_keys(&:to_s).merge("recorded_at" => @clock.call.utc.iso8601)
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
        raise ValidationError, "Invalid journal line #{number}" unless event.is_a?(Hash)

        event
      rescue JSON::ParserError
        raise ValidationError, "Invalid journal line #{number}"
      end
    end

    def completed_operation_ids(run_id)
      events.filter_map do |event|
        event["operation_id"] if event["event"] == "operation_completed" &&
          event["run_id"] == run_id
      end
    end
  end
end
