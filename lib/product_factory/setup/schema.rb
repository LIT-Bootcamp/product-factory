# frozen_string_literal: true

module ProductFactory
  module Setup
    class Schema < Service
      REQUIRED_KEYS = %w[api_version artifacts fields issue_types markers project schema_version views].freeze
      ARTIFACT_DOCUMENTS = %w[
        index setup-log ideas/index epics/index tickets/index research/index factory-runs/index
      ].freeze
      ARTIFACT_MARKER = "<!-- product-factory:v1:artifact:document -->"
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
          data.dig("artifacts", "documents") == ARTIFACT_DOCUMENTS,
          format(data.dig("markers", "artifact"), document: "document") == ARTIFACT_MARKER
        ].all?
      rescue KeyError, NoMethodError, ArgumentError, TypeError
        false
      end
    end
  end
end
