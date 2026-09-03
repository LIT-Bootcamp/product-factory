# frozen_string_literal: true

module ProductFactory
  class Setup
    class PlanValidator
      FILE_KINDS = %w[write_file delete_file].freeze

      def initialize(target_root:)
        @target_root = target_root
      end

      def call(plan, sources:)
        raise ValidationError, "plan target does not match setup target" unless plan.target_root == @target_root

        installation = Installation.load(@target_root)
        installed_hashes = installation.factory_file_hashes
        validate_hashes!(installed_hashes, current_targets: sources.keys)
        OperationValidator.call(
          operations: plan.operations,
          factory_targets: sources.keys | installed_hashes.keys,
          hash_validator: method(:validate_hashes!)
        )
      end

      def validate_hashes!(hashes, current_targets:)
        valid = hashes.is_a?(Hash) && hashes.all? do |path, hash|
          path.is_a?(String) && hash.is_a?(String) && hash.match?(/\A[0-9a-f]{64}\z/) &&
            factory_target?(path, current_targets:)
        end
        raise ValidationError, "installation has invalid factory file hash" unless valid
      end

      private

      def factory_target?(path, current_targets:)
        parts = path.split(File::SEPARATOR, -1)
        safe = !path.empty? && !path.start_with?(File::SEPARATOR) &&
               parts.none? { |part| part.empty? || part == "." || part == ".." }
        safe && (
          current_targets.include?(path) ||
          FileSync.factory_path?(path)
        )
      end
    end
  end
end
