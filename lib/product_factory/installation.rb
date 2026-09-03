require "fileutils"
require "yaml"

module ProductFactory
  class Installation
    PATH = ".product-factory/installation.yml"
    DEFAULTS = {
      "schema_version" => 1,
      "factory_version" => nil,
      "installed_at" => nil,
      "installed_by" => nil,
      "github_resource_ids" => {},
      "managed_file_hashes" => {},
      "last_successful_setup_run" => nil,
      "pending_operations" => []
    }.freeze

    def self.load(root)
      path = File.join(root, PATH)
      return empty unless File.exist?(path)

      new(YAML.safe_load_file(path, aliases: false) || {})
    rescue Psych::Exception => exception
      raise ValidationError, "Invalid #{PATH}: #{exception.message}"
    end

    def self.empty = new(DEFAULTS)

    def initialize(data)
      @data = DEFAULTS.merge(data.transform_keys(&:to_s)).freeze
      raise ValidationError, "installation schema_version must equal 1" unless @data["schema_version"] == 1
    end

    def factory_version = @data["factory_version"]
    def managed_file_hashes = @data["managed_file_hashes"].dup
    def pending_operations = @data["pending_operations"].dup
    def to_h = @data.dup
    def with(attributes) = self.class.new(@data.merge(attributes.transform_keys(&:to_s)))

    def write(root)
      path = File.join(root, PATH)
      temporary = "#{path}.tmp"
      FileUtils.mkdir_p(File.dirname(path))
      File.write(temporary, YAML.dump(@data))
      File.rename(temporary, path)
    ensure
      File.delete(temporary) if temporary && File.exist?(temporary)
    end
  end
end
