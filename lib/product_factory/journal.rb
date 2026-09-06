# frozen_string_literal: true

module ProductFactory
  class Journal
    FAILURE_FIELDS = %w[failed_rule responsible_component root_cause impact recovery_action].freeze
    EVENT_FIELDS = {
      "run_confirmed" => %w[run_id],
      "operation_started" => %w[run_id operation_id],
      "operation_completed" => %w[run_id operation_id],
      "operation_failed" => %w[run_id operation_id error_class message] + FAILURE_FIELDS,
      "run_completed" => %w[run_id status]
    }.freeze

    def initialize(path:, clock:)
      @path = path
      @clock = clock
    end

    def append(event)
      record = event.transform_keys(&:to_s).merge("recorded_at" => @clock.call.utc.iso8601)
      validate_event!(record)
      open_file(File::WRONLY | File::CREAT | File::APPEND) do |file|
        file.write("#{JSON.generate(record)}\n")
        file.flush
        file.fsync
      end
      record
    end

    def events
      return [] unless File.exist?(@path) || File.symlink?(@path)

      open_file(File::RDONLY) do |file|
        file.each_line.with_index(1).map do |line, number|
          event = JSON.parse(line)
          validate_event!(event)
          event
        rescue JSON::ParserError, ValidationError
          raise ValidationError, "Invalid journal line #{number}"
        end
      end
    end

    def completed_operation_ids(run_id)
      events.filter_map do |event|
        event["operation_id"] if event["event"] == "operation_completed" &&
                                 event["run_id"] == run_id
      end
    end

    private

    def open_file(flags, &)
      raise ValidationError, "Journal path must not be a symlink" if File.symlink?(@path)

      File.open(@path, flags | File::NOFOLLOW, &)
    rescue Errno::ELOOP
      raise ValidationError, "Journal path must not be a symlink"
    end

    def validate_event!(event)
      raise ValidationError, "Invalid journal event" unless event.is_a?(Hash)

      EVENT_FIELDS.fetch(event.fetch("event")).each { |key| validate_string!(event, key) }
      validate_string!(event, "recorded_at")
      validate_string!(event, "reason") if event.key?("reason")
      validate_status!(event)
      Time.iso8601(event["recorded_at"])
    rescue KeyError, ArgumentError
      raise ValidationError, "Invalid journal event"
    end

    def validate_string!(event, key)
      raise ValidationError, "Invalid journal event" unless event[key].is_a?(String)
    end

    def validate_status!(event)
      return unless event["event"] == "run_completed"
      return if %w[success no-op].include?(event["status"])

      raise ValidationError, "Invalid journal event"
    end
  end
end
