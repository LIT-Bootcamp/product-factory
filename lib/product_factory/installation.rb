# frozen_string_literal: true

module ProductFactory
  class Installation
    PATH = ".product-factory/installation.yml"
    LEGACY_DOCUMENTS = {
      "Setup-Log.md" => "setup-log",
      "Ideas.md" => "ideas/index",
      "Epics.md" => "epics/index",
      "Tickets.md" => "tickets/index",
      "Research.md" => "research/index",
      "Factory-Runs.md" => "factory-runs/index"
    }.freeze
    DEFAULTS = {
      "schema_version" => 1,
      "factory_version" => nil,
      "installed_at" => nil,
      "installed_by" => nil,
      "github_resource_ids" => {},
      "github_resource_hashes" => {},
      "artifact_adapter" => nil,
      "artifact_document_hashes" => {},
      "artifact_revision" => nil,
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

      @data = immutable_copy(DEFAULTS.merge(normalize(data)))
      raise ValidationError, "installation schema_version must equal 1" unless @data["schema_version"] == 1

      validate_artifacts!
    end

    def factory_version = @data["factory_version"]
    def factory_file_hashes = mutable_copy(@data["factory_file_hashes"])
    def github_resource_hashes = mutable_copy(@data["github_resource_hashes"])
    def artifact_adapter = @data["artifact_adapter"]
    def artifact_document_hashes = mutable_copy(@data["artifact_document_hashes"])
    def artifact_revision = @data["artifact_revision"]
    def wiki_page_hashes
      LEGACY_DOCUMENTS.invert.filter_map do |document, page|
        hash = @data["artifact_document_hashes"][document]
        [page, hash] if hash
      end.to_h
    end
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

    def normalize(data)
      state = data.transform_keys(&:to_s)
      legacy = state.key?("wiki_page_hashes") || state.key?("wiki_head")
      hashes = state.delete("wiki_page_hashes")
      head = state.delete("wiki_head")
      return state unless legacy

      raise ValidationError, "wiki_page_hashes must be a mapping" unless hashes.nil? || hashes.is_a?(Hash)
      raise ValidationError, "wiki_head must be a string or null" unless head.nil? || head.is_a?(String)

      state["artifact_adapter"] ||= "wiki"
      state["artifact_revision"] ||= head
      state["artifact_document_hashes"] ||= hashes.to_h.filter_map do |page, hash|
        document = LEGACY_DOCUMENTS[page]
        [document, hash] if document
      end.to_h
      state
    end

    def validate_artifacts!
      adapter = @data["artifact_adapter"]
      raise ValidationError, "artifact_adapter is unsupported" unless [nil, "repository", "wiki"].include?(adapter)

      revision = @data["artifact_revision"]
      raise ValidationError, "artifact_revision must be a string or null" unless revision.nil? || revision.is_a?(String)

      hashes = @data["artifact_document_hashes"]
      valid = hashes.is_a?(Hash) && hashes.all? do |document, hash|
        document.is_a?(String) && hash.is_a?(String) && /\A[a-f0-9]{64}\z/.match?(hash)
      end
      raise ValidationError, "artifact_document_hashes must contain string IDs and SHA-256 hashes" unless valid
    end

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
