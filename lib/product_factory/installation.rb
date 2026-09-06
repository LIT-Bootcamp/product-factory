# frozen_string_literal: true

module ProductFactory
  class Installation
    PATH = ".product-factory/installation.yml"
    DEFAULTS = {
      "schema_version" => 1,
      "factory_version" => nil,
      "installed_at" => nil,
      "installed_by" => nil,
      "github_resource_ids" => {},
      "github_resource_hashes" => {},
      "wiki_page_hashes" => {},
      "wiki_head" => nil,
      "factory_file_hashes" => {},
      "last_successful_setup_run" => nil,
      "pending_operations" => []
    }.freeze

    def self.load(root)
      path = File.join(root, PATH)
      return empty unless File.exist?(path)

      new(YAML.safe_load_file(path, aliases: false) || {})
    rescue Psych::Exception => e
      raise ValidationError, "Invalid #{PATH}: #{e.message}"
    end

    def self.empty = new(DEFAULTS)

    def initialize(data)
      raise ValidationError, "installation state must be a mapping" unless data.is_a?(Hash)

      @data = immutable_copy(DEFAULTS.merge(data.transform_keys(&:to_s)))
      raise ValidationError, "installation schema_version must equal 1" unless @data["schema_version"] == 1
    end

    def factory_version = @data["factory_version"]
    def factory_file_hashes = mutable_copy(@data["factory_file_hashes"])
    def github_resource_hashes = mutable_copy(@data["github_resource_hashes"])
    def wiki_page_hashes = mutable_copy(@data["wiki_page_hashes"])
    def pending_operations = mutable_copy(@data["pending_operations"])
    def to_h = mutable_copy(@data)
    def with(attributes) = self.class.new(@data.merge(attributes.transform_keys(&:to_s)))

    def write(root)
      root = validated_root(root)
      directory = state_directory(root)
      path = File.join(root, PATH)
      validate_state_path!(path)
      write_state(path, directory)
    rescue Errno::ENOENT
      raise ValidationError, "target root does not exist"
    end

    private

    def validated_root(root)
      root = File.expand_path(root)
      stat = File.lstat(root)
      raise ValidationError, "target root is a symlink" if stat.symlink?
      raise ValidationError, "target root is not a directory" unless stat.directory?
      raise ValidationError, "target root path contains a symlink" unless File.realpath(root) == root

      root
    end

    def state_directory(root)
      directory = File.join(root, ".product-factory")
      if File.exist?(directory) || File.symlink?(directory)
        stat = File.lstat(directory)
        raise ValidationError, "state directory is a symlink" if stat.symlink?
        raise ValidationError, "state directory is not a directory" unless stat.directory?
      else
        FileUtils.mkdir(directory)
      end
      directory
    end

    def validate_state_path!(path)
      return unless File.symlink?(path) || (File.exist?(path) && !File.lstat(path).file?)

      raise ValidationError, "installation state is not a regular file"
    end

    def write_state(path, directory)
      Tempfile.create([".installation-", ".tmp"], directory) do |temporary|
        temporary.write(YAML.dump(@data))
        temporary.flush
        temporary.fsync
        temporary.chmod(0o644)
        File.rename(temporary.path, path)
      end
    end

    def immutable_copy(value)
      case value
      when Hash then value.to_h { |key, item| [immutable_copy(key), immutable_copy(item)] }.freeze
      when Array then value.map { |item| immutable_copy(item) }.freeze
      when String then value.dup.freeze
      else value
      end
    end

    def mutable_copy(value)
      case value
      when Hash then value.to_h { |key, item| [mutable_copy(key), mutable_copy(item)] }
      when Array then value.map { |item| mutable_copy(item) }
      when String then value.dup
      else value
      end
    end
  end
end
