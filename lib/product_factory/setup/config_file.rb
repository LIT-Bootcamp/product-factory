# frozen_string_literal: true

module ProductFactory
  class Setup
    class ConfigFile
      def initialize(root:)
        @root = root
      end

      def apply(operation)
        validate!(operation)
        ensure_factory_directory!
        return if matches?(operation)
        raise ConflictError, "#{Config::PATH} already exists" if File.exist?(path)

        create(operation.attributes.fetch("content_base64").unpack1("m0"))
      end

      def matches?(operation)
        validate!(operation)
        File.binread(path) == operation.attributes.fetch("content_base64").unpack1("m0")
      rescue Errno::ENOENT
        false
      end

      private

      def path = File.join(@root, Config::PATH)

      def validate!(operation)
        valid = operation.target == Config::PATH && operation.attributes.is_a?(Hash) &&
                operation.attributes["content_base64"].is_a?(String)
        raise ValidationError, "invalid config seed operation" unless valid
      end

      def ensure_factory_directory!
        directory = File.dirname(path)
        raise ValidationError, "factory directory is a symlink" if File.symlink?(directory)

        FileUtils.mkdir_p(directory)
        raise ValidationError, "factory directory is not a directory" unless File.directory?(directory)
      end

      def create(bytes)
        Tempfile.create([".product-factory-config-", ".tmp"], File.dirname(path)) do |temporary|
          temporary.binmode
          temporary.write(bytes)
          temporary.flush
          temporary.fsync
          temporary.chmod(0o644)
          File.link(temporary.path, path)
        rescue Errno::EEXIST
          raise ConflictError, "#{Config::PATH} already exists"
        end
      end
    end
  end
end
