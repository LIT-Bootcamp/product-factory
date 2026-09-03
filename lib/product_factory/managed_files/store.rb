# frozen_string_literal: true

require "digest"
require "tempfile"

module ProductFactory
  class ManagedFiles
    class Store
      def apply(operation, target_root:)
        root = validated_target_root(target_root)
        destination = target_path(root, operation.target)

        case operation.kind
        when "write_file" then apply_write(operation, root, destination)
        when "delete_file" then apply_delete(root, destination)
        else raise ValidationError, "unsupported managed-file operation: #{operation.kind}"
        end
      end

      def current_hash(target_root:, path:)
        current_state(target_root:, path:)&.fetch(:hash)
      end

      def current_state(target_root:, path:)
        root = validated_target_root(target_root)
        destination = target_path(root, path)
        return unless File.exist?(destination)

        File.open(destination, File::RDONLY | File::NOFOLLOW) do |file|
          stat = file.stat
          raise ValidationError, "managed target is not a file: #{path}" unless stat.file?

          { hash: Digest::SHA256.hexdigest(file.binmode.read), mode: stat.mode & 0o7777 }
        end
      rescue Errno::ELOOP
        raise ValidationError, "managed target is a symlink: #{path}"
      end

      def read_source(path)
        raise ValidationError, "managed source must be absolute: #{path}" unless Pathname.new(path).absolute?

        stat = source_stat(path)
        raise ValidationError, "managed source is not a file: #{path}" unless stat.file?

        File.open(path, File::RDONLY | File::NOFOLLOW) do |file|
          opened_stat = file.stat
          raise ValidationError, "managed source is not a file: #{path}" unless opened_stat.file?

          [file.binmode.read, opened_stat.mode & 0o7777]
        end
      rescue Errno::ENOENT, Errno::ELOOP, Errno::EACCES => e
        raise ValidationError, "cannot read managed source #{path}: #{e.message}"
      end

      private

      def source_stat(path)
        current = File::SEPARATOR
        stat = nil
        Pathname.new(path).each_filename do |part|
          current = File.join(current, part)
          stat = File.lstat(current)
          raise ValidationError, "managed source path contains a symlink: #{path}" if stat.symlink?
        end
        stat
      end

      def validated_target_root(target_root)
        root = File.expand_path(target_root)
        stat = File.lstat(root)
        raise ValidationError, "target root is a symlink: #{target_root}" if stat.symlink?
        raise ValidationError, "target root is not a directory: #{target_root}" unless stat.directory?

        root
      rescue Errno::ENOENT
        raise ValidationError, "target root does not exist: #{target_root}"
      end

      def target_path(root, relative_path)
        validate_relative_path(relative_path)
        destination = File.expand_path(relative_path, root)
        prefix = "#{root}#{File::SEPARATOR}"
        raise ValidationError, "unsafe managed target path: #{relative_path}" unless destination.start_with?(prefix)

        validate_ancestors!(root, relative_path)
        destination
      end

      def validate_ancestors!(root, relative_path)
        current = root
        parts = relative_path.split(File::SEPARATOR)
        parts.each_with_index do |part, index|
          current = File.join(current, part)
          stat = File.lstat(current)
          raise ValidationError, "managed target is a symlink: #{relative_path}" if stat.symlink?
          if index < parts.length - 1 && !stat.directory?
            raise ValidationError, "managed target ancestor is not a directory: #{relative_path}"
          end
        rescue Errno::ENOENT
          break
        end
      end

      def validate_relative_path(path)
        parts = path.to_s.split(File::SEPARATOR, -1)
        unsafe = path.to_s.empty? || path.to_s.include?("\0") || Pathname.new(path.to_s).absolute? ||
                 parts.any? { |part| part.empty? || part == "." || part == ".." }
        raise ValidationError, "unsafe managed target path: #{path}" if unsafe
      end

      def apply_write(operation, root, destination)
        bytes, mode = write_attributes(operation)
        ensure_destination_directory(root, File.dirname(destination))
        destination = target_path(root, operation.target)
        if File.exist?(destination) && !File.lstat(destination).file?
          raise ValidationError, "managed target is not a file: #{operation.target}"
        end

        replace_file(destination, bytes, mode)
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
        Tempfile.create([".product-factory-", ".tmp"], File.dirname(destination)) do |temp|
          temp.binmode
          temp.write(bytes)
          temp.flush
          temp.fsync
          temp.chmod(mode)
          File.rename(temp.path, destination)
        end
      end

      def ensure_destination_directory(root, directory)
        return if directory == root

        current = root
        relative = directory.delete_prefix("#{root}#{File::SEPARATOR}")
        relative.split(File::SEPARATOR).each do |part|
          current = File.join(current, part)
          stat = directory_stat(current)
          raise ValidationError, "managed target ancestor is a symlink: #{current}" if stat.symlink?
          raise ValidationError, "managed target ancestor is not a directory: #{current}" unless stat.directory?
        end
      end

      def directory_stat(path)
        File.lstat(path)
      rescue Errno::ENOENT
        Dir.mkdir(path)
        File.lstat(path)
      rescue Errno::EEXIST
        File.lstat(path)
      end

      def apply_delete(root, destination)
        if File.exist?(destination)
          raise ValidationError, "managed target is not a file: #{destination}" unless File.lstat(destination).file?

          File.delete(destination)
        end
        remove_empty_ancestors(root, File.dirname(destination))
      end

      def remove_empty_ancestors(root, directory)
        while directory != root
          begin
            Dir.rmdir(directory)
            directory = File.dirname(directory)
          rescue Errno::ENOTEMPTY, Errno::ENOENT
            break
          end
        end
      end
    end
  end
end
