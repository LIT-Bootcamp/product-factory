# frozen_string_literal: true

module ProductFactory
  class Setup
    class PlanValidator
      MANAGED_KINDS = %w[write_file delete_file].freeze

      def initialize(target_root:)
        @target_root = target_root
      end

      def call(plan, sources:)
        raise ValidationError, "plan target does not match setup target" unless plan.target_root == @target_root

        installation = Installation.load(@target_root)
        installed_hashes = installation.managed_file_hashes
        validate_hashes!(installed_hashes, current_targets: sources.keys)
        validate_operations!(plan.operations, sources.keys | installed_hashes.keys)
      end

      def validate_hashes!(hashes, current_targets:)
        valid = hashes.is_a?(Hash) && hashes.all? do |path, hash|
          path.is_a?(String) && hash.is_a?(String) && hash.match?(/\A[0-9a-f]{64}\z/) &&
            managed_target?(path, current_targets:)
        end
        raise ValidationError, "installation has invalid managed file hash" unless valid
      end

      private

      def validate_operations!(operations, managed_targets)
        seeds = operations.select { |operation| operation.kind == "seed_config" }
        managed = operations.select { |operation| MANAGED_KINDS.include?(operation.kind) }
        installations = operations.select { |operation| operation.kind == "write_installation" }

        validate_operation_types!(operations, seeds, managed, installations)
        validate_seed_operations!(seeds)
        validate_managed_operations!(managed, managed_targets)
        validate_installation_operations!(installations, managed_targets)
        validate_order!(operations, seeds, managed, installations)
      end

      def validate_operation_types!(operations, seeds, managed, installations)
        return if operations.length == seeds.length + managed.length + installations.length

        raise ValidationError, "plan contains unsupported operation"
      end

      def validate_seed_operations!(operations)
        unless operations.length <= 1 && operations.all? { |operation| operation.target == Config::PATH }
          raise ValidationError, "plan has invalid config seed"
        end

        operations.each { |operation| validate_seed!(operation) }
      end

      def validate_managed_operations!(operations, targets)
        unique = operations.map(&:target).uniq.length == operations.length
        raise ValidationError, "plan has invalid managed target" unless unique && operations.all? do |operation|
          targets.include?(operation.target)
        end

        operations.each { |operation| validate_managed!(operation) }
      end

      def validate_installation_operations!(operations, managed_targets)
        operations.each do |operation|
          unless operation.target == Installation::PATH && operation.attributes.is_a?(Hash)
            raise ValidationError, "plan has invalid installation state"
          end

          state = Installation.new(operation.attributes)
          validate_hashes!(state.managed_file_hashes, current_targets: managed_targets)
        end
      end

      def validate_order!(operations, seeds, managed, installations)
        return if operations.empty?
        unless installations.one? && operations.last == installations.first
          raise ValidationError, "plan must end with installation state"
        end

        expected = seeds + managed + installations
        raise ValidationError, "plan operation order is invalid" unless operations == expected
      end

      def validate_seed!(operation)
        attributes = operation.attributes
        valid = operation.target == Config::PATH &&
                attributes.is_a?(Hash) && attributes["content_base64"].is_a?(String)
        raise ValidationError, "invalid config seed operation" unless valid
      end

      def validate_managed!(operation)
        attributes = operation.attributes
        raise ValidationError, "plan has invalid managed operation" unless attributes.is_a?(Hash)

        valid = operation.kind == "delete_file" ? valid_delete?(attributes) : valid_write?(operation, attributes)
        raise ValidationError, "plan has invalid managed operation" unless valid
      rescue ArgumentError
        raise ValidationError, "plan has invalid managed operation"
      end

      def valid_delete?(attributes)
        (attributes.keys - %w[expected_local_hash reason]).empty? &&
          valid_expected_hash?(attributes) && valid_reason?(attributes["reason"])
      end

      def valid_write?(operation, attributes)
        operation.kind == "write_file" &&
          attributes["content_base64"].is_a?(String) &&
          attributes["mode"].is_a?(Integer) &&
          attributes["mode"].between?(0, 0o7777) &&
          (attributes.keys - %w[content_base64 expected_local_hash mode reason]).empty? &&
          valid_expected_hash?(attributes) &&
          valid_reason?(attributes["reason"]) &&
          attributes.fetch("content_base64").unpack1("m0")
      end

      def valid_expected_hash?(attributes)
        return false unless attributes.key?("expected_local_hash")

        hash = attributes["expected_local_hash"]
        hash.nil? || (hash.is_a?(String) && hash.match?(/\A[0-9a-f]{64}\z/))
      end

      def valid_reason?(reason)
        reason.nil? || ManagedFiles::RESOLUTIONS.include?(reason)
      end

      def managed_target?(path, current_targets:)
        parts = path.split(File::SEPARATOR, -1)
        safe = !path.empty? && !path.start_with?(File::SEPARATOR) &&
               parts.none? { |part| part.empty? || part == "." || part == ".." }
        safe && (
          current_targets.include?(path) ||
          path == "bin/product-factory" ||
          LEGACY_MANAGED_PREFIXES.any? { |prefix| path.start_with?(prefix) }
        )
      end
    end
  end
end
