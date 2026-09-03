# frozen_string_literal: true

module ProductFactory
  module FileSync
    class Path
      attr_reader :root, :relative

      def initialize(root:, relative:)
        @root = validate_root(root)
        @relative = relative.to_s
        validate_relative!
      end

      def to_s
        validate_ancestors!
        File.expand_path(relative, root)
      end

      def prepare_parent!
        parent_parts.each do |parts|
          directory = File.join(root, *parts)
          stat = directory_stat(directory)
          raise ValidationError, "factory target ancestor is a symlink: #{relative}" if stat.symlink?
          raise ValidationError, "factory target ancestor is not a directory: #{relative}" unless stat.directory?
        end
      end

      def remove_empty_parents!
        directory = File.dirname(to_s)
        while directory != root
          begin
            Dir.rmdir(directory)
            directory = File.dirname(directory)
          rescue Errno::ENOTEMPTY, Errno::ENOENT
            break
          end
        end
      end

      private

      def validate_root(root)
        expanded = File.expand_path(root)
        stat = File.lstat(expanded)
        raise ValidationError, "target root is a symlink: #{root}" if stat.symlink?
        raise ValidationError, "target root is not a directory: #{root}" unless stat.directory?

        expanded
      rescue Errno::ENOENT
        raise ValidationError, "target root does not exist: #{root}"
      end

      def validate_relative!
        parts = relative.split(File::SEPARATOR, -1)
        unsafe = relative.empty? || relative.include?("\0") || Pathname.new(relative).absolute? ||
                 parts.any? { |part| part.empty? || part == "." || part == ".." }
        raise ValidationError, "unsafe factory target path: #{relative}" if unsafe

        destination = File.expand_path(relative, root)
        return if destination.start_with?("#{root}#{File::SEPARATOR}")

        raise ValidationError, "unsafe factory target path: #{relative}"
      end

      def validate_ancestors!
        path_parts.each_with_index do |parts, index|
          stat = File.lstat(File.join(root, *parts))
          raise ValidationError, "factory target is a symlink: #{relative}" if stat.symlink?
          next if index == path_parts.length - 1 || stat.directory?

          raise ValidationError, "factory target ancestor is not a directory: #{relative}"
        rescue Errno::ENOENT
          break
        end
      end

      def path_parts
        @path_parts ||= begin
          parts = relative.split(File::SEPARATOR)
          parts.each_index.map { |index| parts.first(index + 1) }
        end
      end

      def parent_parts = path_parts.first(path_parts.length - 1)

      def directory_stat(path)
        File.lstat(path)
      rescue Errno::ENOENT
        Dir.mkdir(path)
        File.lstat(path)
      rescue Errno::EEXIST
        File.lstat(path)
      end
    end
  end
end
