# frozen_string_literal: true

module ProductFactory
  module Setup
    class Schema < Service
      REQUIRED_KEYS = %w[api_version fields issue_types markers project schema_version views wiki].freeze
      FIELD_TYPES = %w[date number single_select text].freeze

      def initialize(bytes:)
        super()
        @bytes = bytes
      end

      def call
        data = YAML.safe_load(@bytes, aliases: false)
        validate!(data)
        JSON.parse(JSON.generate(data), freeze: true)
      rescue Psych::Exception, JSON::GeneratorError
        raise ValidationError, "invalid provisioning schema"
      end

      private

      def validate!(data)
        raise ValidationError, "invalid provisioning schema" unless valid?(data)
      end

      def valid?(data)
        [
          data.is_a?(Hash),
          data.keys.sort == REQUIRED_KEYS,
          data["schema_version"] == 1,
          data.dig("project", "public") == false,
          data.fetch("issue_types").keys == %w[Idea Epic Ticket],
          data.fetch("fields").values.all? { |field| FIELD_TYPES.include?(field["type"]) },
          data.fetch("views").keys == %w[Ideas Epics Tickets],
          data.dig("wiki", "pages") == %w[_Sidebar Setup-Log Ideas Epics Tickets Research Factory-Runs]
        ].all?
      rescue KeyError, NoMethodError
        false
      end
    end
  end
end
