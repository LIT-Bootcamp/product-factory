# frozen_string_literal: true

module ProductFactory
  module FileSync
    class Source
      def self.read(path) = new(path).read

      def initialize(path)
        @path = path
      end

      def read
        raise ValidationError, "factory source must be absolute: #{@path}" unless Pathname.new(@path).absolute?

        stat = stat_without_symlinks
        raise ValidationError, "factory source is not a file: #{@path}" unless stat.file?

        File.open(@path, File::RDONLY | File::NOFOLLOW) do |file|
          raise ValidationError, "factory source is not a file: #{@path}" unless file.stat.file?

          [file.binmode.read, file.stat.mode & 0o7777]
        end
      rescue Errno::ENOENT, Errno::ELOOP, Errno::EACCES => e
        raise ValidationError, "cannot read factory source #{@path}: #{e.message}"
      end

      private

      def stat_without_symlinks
        current = File::SEPARATOR
        stat = nil
        Pathname.new(@path).each_filename do |part|
          current = File.join(current, part)
          stat = File.lstat(current)
          raise ValidationError, "factory source path contains a symlink: #{@path}" if stat.symlink?
        end
        stat
      end
    end
  end
end
