# frozen_string_literal: true

module ProductFactory
  module Setup
    class Schema < Service
      REQUIRED_KEYS = %w[api_version artifacts fields issue_types markers project schema_version views wiki].freeze
      ARTIFACT_DOCUMENTS = %w[
        index setup-log ideas/index epics/index tickets/index research/index factory-runs/index
      ].freeze
      OPEN_BRACE = "{"
      ARTIFACT_MARKER = "<!-- product-factory:v1:artifact:%#{OPEN_BRACE}document} -->".freeze
      WIKI_MARKER = "<!-- product-factory:v1:wiki:%#{OPEN_BRACE}page} -->".freeze
      WIKI_PAGES = %w[_Sidebar Setup-Log Ideas Epics Tickets Research Factory-Runs].freeze
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
          data.dig("markers", "artifact") == ARTIFACT_MARKER,
          data.dig("markers", "wiki") == WIKI_MARKER,
          data.dig("wiki", "pages") == WIKI_PAGES
        ].all?
      rescue KeyError, NoMethodError
        false
      end
    end
  end
end
