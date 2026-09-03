require "digest"
require "json"
require "pathname"

module ProductFactory
  class Validator
    def initialize(root:)
      @root = File.expand_path(root)
    end

    def call
      validate_root
      require_file(Config::PATH)
      config = Config.load(@root)
      require_file(Installation::PATH)
      installation = Installation.load(@root)
      validate_hashes(installation.managed_file_hashes)
      pending = installation.pending_operations
      raise ValidationError, "pending operations remain" unless pending.is_a?(Array) && pending.empty?

      journal_path = require_file(".product-factory-journal.jsonl")
      Journal.new(path: journal_path, clock: -> { Time.now }).events
      validate_credentials(config, installation)
      true
    end

    private

    def validate_hashes(hashes)
      unless hashes.is_a?(Hash)
        raise ValidationError, "managed file hashes must be a mapping"
      end

      hashes.each do |relative_path, expected_hash|
        path = safe_path(relative_path)
        raise ValidationError, "managed file missing: #{relative_path}" unless File.exist?(path) && File.lstat(path).file?
        unless expected_hash.is_a?(String) && expected_hash.match?(/\A[0-9a-f]{64}\z/)
          raise ValidationError, "invalid managed file hash: #{relative_path}"
        end
        raise ValidationError, "managed file hash mismatch: #{relative_path}" unless Digest::SHA256.file(path).hexdigest == expected_hash
      end
    end

    def safe_path(relative_path)
      unless relative_path.is_a?(String)
        raise ValidationError, "unsafe managed file path: #{relative_path.inspect}"
      end

      parts = relative_path.split(File::SEPARATOR, -1)
      if parts.any? { |part| part.empty? || part == "." || part == ".." } || Pathname.new(relative_path).absolute?
        raise ValidationError, "unsafe managed file path: #{relative_path}"
      end

      path = File.expand_path(relative_path, @root)
      raise ValidationError, "unsafe managed file path: #{relative_path}" unless path.start_with?("#{@root}#{File::SEPARATOR}")

      current = @root
      parts.each do |part|
        current = File.join(current, part)
        stat = File.lstat(current)
        raise ValidationError, "managed file path contains a symlink: #{relative_path}" if stat.symlink?
      rescue Errno::ENOENT
        break
      end

      path
    end

    def validate_root
      stat = File.lstat(@root)
      raise ValidationError, "target root is a symlink" if stat.symlink?
      raise ValidationError, "target root is not a directory" unless stat.directory?
      raise ValidationError, "target root path contains a symlink" unless File.realpath(@root) == @root
    rescue Errno::ENOENT
      raise ValidationError, "target root does not exist"
    end

    def require_file(relative_path)
      path = safe_path(relative_path)
      unless File.exist?(path)
        raise ValidationError, "Missing #{relative_path}"
      end
      raise ValidationError, "#{relative_path} is not a file" unless File.lstat(path).file?

      path
    end

    def validate_credentials(config, installation)
      names = config.qa.fetch("credential_env", {}).values.grep(String)
      values = names.filter_map { |name| ENV[name] }.reject(&:empty?)
      serialized = JSON.generate([config.to_h, installation.to_h])
      raise ValidationError, "credential value is stored in factory state" if values.any? { |value| serialized.include?(value) }
    end
  end
end
