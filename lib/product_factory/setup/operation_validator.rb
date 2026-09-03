# frozen_string_literal: true

module ProductFactory
  class Setup
    class OperationValidator
      def self.call(...) = new(...).call

      def initialize(operations:, factory_targets:, hash_validator:)
        @operations = operations
        @factory_targets = factory_targets
        @hash_validator = hash_validator
      end

      def call
        validate_types!
        validate_config!
        validate_files!
        validate_installation!
        validate_order!
      end

      private

      def config_operations = @operations.select { |operation| operation.kind == "seed_config" }
      def file_operations = @operations.select { |operation| PlanValidator::FILE_KINDS.include?(operation.kind) }
      def installation_operations = @operations.select { |operation| operation.kind == "write_installation" }

      def validate_types!
        known_count = config_operations.length + file_operations.length + installation_operations.length
        raise ValidationError, "plan contains unsupported operation" unless @operations.length == known_count
      end

      def validate_config!
        valid = config_operations.length <= 1 && config_operations.all? do |operation|
          operation.target == Config::PATH && operation.attributes.is_a?(Hash) &&
            operation.attributes["content_base64"].is_a?(String)
        end
        raise ValidationError, "plan has invalid config seed" unless valid
      end

      def validate_files!
        unique_targets = file_operations.map(&:target).uniq.length == file_operations.length
        known_targets = file_operations.all? { |operation| @factory_targets.include?(operation.target) }
        raise ValidationError, "plan has invalid factory target" unless unique_targets && known_targets

        file_operations.each { |operation| validate_file!(operation) }
      end

      def validate_file!(operation)
        attributes = operation.attributes
        valid = attributes.is_a?(Hash) &&
                (operation.kind == "delete_file" ? valid_delete?(attributes) : valid_write?(attributes))
        raise ValidationError, "plan has invalid file operation" unless valid
      rescue ArgumentError
        raise ValidationError, "plan has invalid file operation"
      end

      def valid_delete?(attributes)
        (attributes.keys - %w[expected_local_hash reason]).empty? && valid_common_attributes?(attributes)
      end

      def valid_write?(attributes)
        attributes["content_base64"].is_a?(String) &&
          attributes["mode"].is_a?(Integer) && attributes["mode"].between?(0, 0o7777) &&
          (attributes.keys - %w[content_base64 expected_local_hash mode reason]).empty? &&
          valid_common_attributes?(attributes) && attributes.fetch("content_base64").unpack1("m0")
      end

      def valid_common_attributes?(attributes)
        return false unless attributes.key?("expected_local_hash")

        hash = attributes["expected_local_hash"]
        valid_hash = hash.nil? || (hash.is_a?(String) && hash.match?(/\A[0-9a-f]{64}\z/))
        valid_reason = attributes["reason"].nil? || FileSync::RESOLUTIONS.include?(attributes["reason"])
        valid_hash && valid_reason
      end

      def validate_installation!
        installation_operations.each do |operation|
          unless operation.target == Installation::PATH && operation.attributes.is_a?(Hash)
            raise ValidationError, "plan has invalid installation state"
          end

          state = Installation.new(operation.attributes)
          @hash_validator.call(state.factory_file_hashes, current_targets: @factory_targets)
        end
      end

      def validate_order!
        return if @operations.empty?
        unless installation_operations.one? && @operations.last == installation_operations.first
          raise ValidationError, "plan must end with installation state"
        end

        expected = config_operations + file_operations + installation_operations
        raise ValidationError, "plan operation order is invalid" unless @operations == expected
      end
    end
  end
end
