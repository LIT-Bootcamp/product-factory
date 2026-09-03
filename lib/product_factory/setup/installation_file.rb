# frozen_string_literal: true

module ProductFactory
  class Setup
    class InstallationFile
      def initialize(root:, files:)
        @root = root
        @files = files
      end

      def apply(operation)
        validate!(operation)
        Installation.new(operation.attributes).write(@root)
      end

      def matches?(operation)
        validate!(operation)
        state = Installation.load(@root).to_h
        return false unless state == operation.attributes

        state.fetch("factory_file_hashes").all? { |path, hash| @files.hash(path) == hash }
      rescue Errno::ENOENT, ValidationError, KeyError, TypeError
        false
      end

      private

      def validate!(operation)
        return if operation.target == Installation::PATH && operation.attributes.is_a?(Hash)

        raise ValidationError, "invalid installation operation"
      end
    end
  end
end
