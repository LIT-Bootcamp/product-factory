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

    attr_reader :schema_version, :product, :github, :research, :workflow,
                :agents, :qa, :knowledge

    def self.load(root)
      path = File.join(root, PATH)
      data = YAML.safe_load_file(path, aliases: false) || {}
      new(data)
    rescue Errno::ENOENT
      raise ValidationError, "Missing #{PATH}"
    rescue Psych::Exception => exception
      raise ValidationError, "Invalid #{PATH}: #{exception.message}"
    end

    def initialize(data)
      @data = stringify(data)
      @schema_version = @data["schema_version"]
      raise ValidationError, "schema_version must equal 1" unless schema_version == 1

      REQUIRED.each do |path|
        raise ValidationError, "#{path} is required" if fetch_path(path).nil?
      end

      @product = @data.fetch("product")
      @github = @data.fetch("github")
      @research = @data.fetch("research")
      @workflow = @data.fetch("workflow")
      @agents = @data.fetch("agents", {})
      @qa = @data.fetch("qa", {})
      @knowledge = @data.fetch("knowledge", {})
    end

    def to_h = @data.dup

    private

    def fetch_path(path)
      path.split(".").reduce(@data) { |value, key| value.is_a?(Hash) ? value[key] : nil }
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
