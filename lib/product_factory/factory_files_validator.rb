# frozen_string_literal: true

module ProductFactory
  class FactoryFilesValidator < Service
    INTEGRATION_SPEC = ".product-factory/spec/integration_spec.rb"

    def initialize(root:, hashes:)
      super()
      @root = root
      @hashes = hashes
    end

    def call
      require_file(INTEGRATION_SPEC)
      raise ValidationError, "factory file hashes must be a mapping" unless @hashes.is_a?(Hash)

      @hashes.each { |path, expected_hash| validate_file(path, expected_hash) }
    end

    private

    def validate_file(relative_path, expected_hash)
      raise ValidationError, "invalid factory file path: #{relative_path}" unless factory_path?(relative_path)

      path = require_file(relative_path)
      unless expected_hash.is_a?(String) && expected_hash.match?(/\A[0-9a-f]{64}\z/)
        raise ValidationError, "invalid factory file hash: #{relative_path}"
      end
      return if Digest::SHA256.file(path).hexdigest == expected_hash

      raise ValidationError, "factory file hash mismatch: #{relative_path}"
    end

    def factory_path?(path)
      path.is_a?(String) && FileSync.factory_path?(path)
    end

    def require_file(relative_path)
      path = safe_path(relative_path)
      raise ValidationError, "Missing #{relative_path}" unless File.exist?(path)
      raise ValidationError, "#{relative_path} is not a file" unless File.lstat(path).file?

      path
    end

    def safe_path(relative_path)
      parts = relative_parts(relative_path)
      path = File.expand_path(relative_path, @root)
      raise ValidationError, "unsafe factory file path: #{relative_path}" unless path.start_with?("#{@root}/")

      reject_symlinks(parts, relative_path)
      path
    end

    def relative_parts(relative_path)
      raise ValidationError, "unsafe factory file path: #{relative_path.inspect}" unless relative_path.is_a?(String)

      parts = relative_path.split(File::SEPARATOR, -1)
      unsafe = Pathname.new(relative_path).absolute? || parts.any? { |part| part.empty? || part == "." || part == ".." }
      raise ValidationError, "unsafe factory file path: #{relative_path}" if unsafe

      parts
    end

    def reject_symlinks(parts, relative_path)
      current = @root
      parts.each do |part|
        current = File.join(current, part)
        raise ValidationError, "factory file path contains a symlink: #{relative_path}" if File.lstat(current).symlink?
      rescue Errno::ENOENT
        break
      end
    end
  end
end
