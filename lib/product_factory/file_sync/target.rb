# frozen_string_literal: true

module ProductFactory
  module FileSync
    class Target
      def initialize(root:)
        @root = root
      end

      def apply(operation)
        case operation.kind
        when Operation::WRITE_FILE then write(operation)
        when Operation::DELETE_FILE then delete(operation)
        else raise ValidationError, "unsupported file-sync operation: #{operation.kind}"
        end
      end

      def hash(path) = state(path)&.fetch(:hash)

      def state(relative_path)
        destination = path(relative_path).to_s
        return unless File.exist?(destination)

        File.open(destination, File::RDONLY | File::NOFOLLOW) do |file|
          raise ValidationError, "factory target is not a file: #{relative_path}" unless file.stat.file?

          { hash: Digest::SHA256.hexdigest(file.binmode.read), mode: file.stat.mode & 0o7777 }
        end
      rescue Errno::ELOOP
        raise ValidationError, "factory target is a symlink: #{relative_path}"
      end

      private

      def write(operation)
        bytes, mode = write_attributes(operation)
        target_path = path(operation.target)
        target_path.prepare_parent!
        destination = target_path.to_s
        if File.exist?(destination) && !File.lstat(destination).file?
          raise ValidationError, "factory target is not a file: #{operation.target}"
        end

        replace_file(destination, bytes, mode)
      end

      def delete(operation)
        target_path = path(operation.target)
        destination = target_path.to_s
        if File.exist?(destination)
          unless File.lstat(destination).file?
            raise ValidationError, "factory target is not a file: #{operation.target}"
          end

          File.delete(destination)
        end
        target_path.remove_empty_parents!
      end

      def write_attributes(operation)
        attributes = operation.attributes
        valid = attributes.is_a?(Hash) && attributes["content_base64"].is_a?(String) &&
                attributes["mode"].is_a?(Integer) && attributes["mode"].between?(0, 0o7777)
        raise ValidationError, "invalid write operation for #{operation.target}" unless valid

        [attributes.fetch("content_base64").unpack1("m0"), attributes.fetch("mode")]
      rescue KeyError, ArgumentError => e
        raise ValidationError, "invalid write operation for #{operation.target}: #{e.message}"
      end

      def replace_file(destination, bytes, mode)
        Tempfile.create([".product-factory-", ".tmp"], File.dirname(destination)) do |temporary|
          temporary.binmode
          temporary.write(bytes)
          temporary.flush
          temporary.fsync
          temporary.chmod(mode)
          File.rename(temporary.path, destination)
        end
      end

      def path(relative) = Path.new(root: @root, relative:)
    end
  end
end
