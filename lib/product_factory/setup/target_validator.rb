# frozen_string_literal: true

module ProductFactory
  module Setup
    class TargetValidator < Service
      def initialize(root:)
        super()
        @root = root
      end

      def call
        validate_root!
        validate_factory_directory!
        validate_state_files!
      rescue Errno::ENOENT
        raise ValidationError, "target root does not exist"
      end

      private

      def validate_root!
        stat = File.lstat(@root)
        raise ValidationError, "target root is a symlink" if stat.symlink?
        raise ValidationError, "target root is not a directory" unless stat.directory?
        raise ValidationError, "target root path contains a symlink" unless File.realpath(@root) == @root
      end

      def validate_factory_directory!
        path = File.join(@root, ".product-factory")
        return unless File.exist?(path) || File.symlink?(path)

        stat = File.lstat(path)
        raise ValidationError, ".product-factory is a symlink" if stat.symlink?
        raise ValidationError, ".product-factory is not a directory" unless stat.directory?
      end

      def validate_state_files!
        [Config::PATH, Installation::PATH].each do |relative_path|
          path = File.join(@root, relative_path)
          next unless File.exist?(path) || File.symlink?(path)

          stat = File.lstat(path)
          raise ValidationError, "#{relative_path} is a symlink" if stat.symlink?
          raise ValidationError, "#{relative_path} is not a file" unless stat.file?
        end
      end
    end
  end
end
