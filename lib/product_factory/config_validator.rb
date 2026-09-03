# frozen_string_literal: true

module ProductFactory
  class ConfigValidator
    REQUIRED = %w[
      product.name product.context_page product.inventory_page
      github.organization github.repository github.project_title
      research.freshness_days workflow.clarification_rounds
      workflow.claim_lease_minutes workflow.max_ticket_human_hours
    ].freeze
    MAPPINGS = %w[
      product github research workflow agents
      agents.ideator agents.business_analyst agents.technical_lead agents.manual_qa
      qa qa.credential_env knowledge
    ].freeze
    STRINGS = %w[
      product.name product.context_page product.inventory_page
      github.organization github.repository github.project_title
      agents.ideator.model agents.ideator.reasoning
      agents.business_analyst.model agents.business_analyst.reasoning
      agents.technical_lead.model agents.technical_lead.reasoning
      agents.manual_qa.model agents.manual_qa.reasoning
      qa.local_url qa.start_command qa.setup_command
      qa.credential_env.student qa.credential_env.mentor qa.credential_env.admin
    ].freeze
    INTEGERS = %w[
      product.max_active_ideas research.freshness_days
      workflow.clarification_rounds workflow.claim_lease_minutes
      workflow.max_ticket_human_hours
    ].freeze
    MISSING = Object.new.freeze

    def self.call(data) = new(data).call

    def initialize(data)
      raise ValidationError, "configuration must be a mapping" unless data.is_a?(Hash)

      @data = stringify(data)
    end

    def call
      validate_schema!
      validate_mappings!
      validate_required_fields!
      validate_types!
      @data
    end

    private

    def validate_schema!
      validate_type("schema_version", "an integer") { |value| value.is_a?(Integer) }
      raise ValidationError, "schema_version must equal 1" unless @data["schema_version"] == 1
    end

    def validate_mappings!
      MAPPINGS.each do |path|
        value = fetch(path)
        next if value.equal?(MISSING) || value.is_a?(Hash)

        raise ValidationError, "#{path} must be a mapping"
      end
    end

    def validate_required_fields!
      REQUIRED.each do |path|
        value = fetch(path)
        raise ValidationError, "#{path} is required" if value.equal?(MISSING) || value.nil?
      end
    end

    def validate_types!
      STRINGS.each { |path| validate_type(path, "a string") { |value| value.is_a?(String) } }
      INTEGERS.each { |path| validate_type(path, "an integer") { |value| value.is_a?(Integer) } }
      validate_type("qa.staging_url", "a string or null") { |value| value.nil? || value.is_a?(String) }
      validate_type("knowledge.paths", "an array of strings") do |value|
        value.is_a?(Array) && value.all?(String)
      end
    end

    def validate_type(path, description)
      value = fetch(path)
      return if value.equal?(MISSING) || yield(value)

      raise ValidationError, "#{path} must be #{description}"
    end

    def fetch(path)
      path.split(".").reduce(@data) do |value, key|
        return MISSING unless value.is_a?(Hash) && value.key?(key)

        value[key]
      end
    end

    def stringify(value)
      case value
      when Hash then value.to_h { |key, item| [key.to_s, stringify(item)] }
      when Array then value.map { |item| stringify(item) }
      else value
      end
    end
  end
end
