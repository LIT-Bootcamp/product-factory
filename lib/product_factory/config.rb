# frozen_string_literal: true

module ProductFactory
  class Config
    PATH = ".product-factory/config.yml"

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
      @data = ConfigValidator.call(data)
      @schema_version = @data["schema_version"]
      assign_sections
    end

    def to_h = @data.dup

    private

    def assign_sections
      @product = @data.fetch("product")
      @github = @data.fetch("github")
      @research = @data.fetch("research")
      @workflow = @data.fetch("workflow")
      @agents = @data.fetch("agents", {})
      @qa = @data.fetch("qa", {})
      @knowledge = @data.fetch("knowledge", {})
    end
  end
end
