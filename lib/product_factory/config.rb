# frozen_string_literal: true

require "yaml"

module ProductFactory
  class Config
    PATH = ".product-factory/config.yml"
    REQUIRED = %w[
      product.name product.context_page product.inventory_page
      github.organization github.repository github.project_title
      research.freshness_days workflow.clarification_rounds
      workflow.claim_lease_minutes workflow.max_ticket_human_hours
    ].freeze

    MISSING = Object.new.freeze
    MAPPING_FIELDS = %w[
      product github research workflow agents
      agents.ideator agents.business_analyst agents.technical_lead agents.manual_qa
      qa qa.credential_env knowledge
    ].freeze
    STRING_FIELDS = %w[
      product.name product.context_page product.inventory_page
      github.organization github.repository github.project_title
      agents.ideator.model agents.ideator.reasoning
      agents.business_analyst.model agents.business_analyst.reasoning
      agents.technical_lead.model agents.technical_lead.reasoning
      agents.manual_qa.model agents.manual_qa.reasoning
      qa.local_url qa.start_command qa.setup_command
      qa.credential_env.student qa.credential_env.mentor qa.credential_env.admin
    ].freeze
    INTEGER_FIELDS = %w[
      product.max_active_ideas research.freshness_days
      workflow.clarification_rounds workflow.claim_lease_minutes
      workflow.max_ticket_human_hours
    ].freeze

    attr_reader :schema_version, :product, :github, :research, :workflow,
                :agents, :qa, :knowledge

    def self.load(root)
      path = File.join(root, PATH)
      data = YAML.safe_load_file(path, aliases: false) || {}
      new(data)
    rescue Errno::ENOENT
      raise ValidationError, "Missing #{PATH}"
    rescue Psych::Exception => e
      raise ValidationError, "Invalid #{PATH}: #{e.message}"
    end

    def initialize(data)
      raise ValidationError, "configuration must be a mapping" unless data.is_a?(Hash)

      @data = stringify(data)
      @schema_version = @data["schema_version"]
      validate_schema!
      validate_mappings
      validate_required_fields
      validate_types
      assign_sections
    end

    def to_h = @data.dup

    private

    def validate_schema!
      validate_type("schema_version", "an integer") { |value| value.is_a?(Integer) }
      raise ValidationError, "schema_version must equal 1" unless schema_version == 1
    end

    def validate_required_fields
      REQUIRED.each do |path|
        value = fetch_path(path)
        raise ValidationError, "#{path} is required" if value.equal?(MISSING) || value.nil?
      end
    end

    def assign_sections
      @product = @data.fetch("product")
      @github = @data.fetch("github")
      @research = @data.fetch("research")
      @workflow = @data.fetch("workflow")
      @agents = @data.fetch("agents", {})
      @qa = @data.fetch("qa", {})
      @knowledge = @data.fetch("knowledge", {})
    end

    def fetch_path(path)
      path.split(".").reduce(@data) do |value, key|
        return MISSING unless value.is_a?(Hash) && value.key?(key)

        value[key]
      end
    end

    def validate_mappings
      MAPPING_FIELDS.each do |path|
        value = fetch_path(path)
        next if value.equal?(MISSING)

        raise ValidationError, "#{path} must be a mapping" unless value.is_a?(Hash)
      end
    end

    def validate_types
      STRING_FIELDS.each do |path|
        validate_type(path, "a string") { |value| value.is_a?(String) }
      end
      INTEGER_FIELDS.each do |path|
        validate_type(path, "an integer") { |value| value.is_a?(Integer) }
      end
      validate_type("qa.staging_url", "a string or null") do |value|
        value.nil? || value.is_a?(String)
      end
      validate_type("knowledge.paths", "an array of strings") do |value|
        value.is_a?(Array) && value.all?(String)
      end
    end

    def validate_type(path, description)
      value = fetch_path(path)
      return if value.equal?(MISSING)

      raise ValidationError, "#{path} must be #{description}" unless yield(value)
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
