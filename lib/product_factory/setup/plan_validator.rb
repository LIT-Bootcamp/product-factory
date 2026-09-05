# frozen_string_literal: true

module ProductFactory
  module Setup
    class PlanValidator
      FILE_KINDS = [Operation::WRITE_FILE, Operation::DELETE_FILE].freeze

      def initialize(target_root:)
        @target_root = target_root
      end

      def call(plan, sources:)
        raise ValidationError, "plan target does not match setup target" unless plan.target_root == @target_root

        installation = Installation.load(@target_root)
        installed_hashes = installation.factory_file_hashes
        validate_hashes!(installed_hashes, current_targets: sources.keys)
        @operations = plan.operations
        @factory_targets = sources.keys | installed_hashes.keys
        validate_operations!
      end

      def validate_hashes!(hashes, current_targets:)
        valid = hashes.is_a?(Hash) && hashes.all? do |path, hash|
          path.is_a?(String) && hash.is_a?(String) && hash.match?(/\A[0-9a-f]{64}\z/) &&
            factory_target?(path, current_targets:)
        end
        raise ValidationError, "installation has invalid factory file hash" unless valid
      end

      private

      def validate_operations!
        validate_types!
        validate_config!
        validate_files!
        validate_installation!
        validate_order!
      end

      def config_operations = @operations.select { |operation| operation.kind == Operation::SEED_CONFIG }
      def file_operations = @operations.select { |operation| FILE_KINDS.include?(operation.kind) }

      def installation_operations
        @operations.select { |operation| operation.kind == Operation::WRITE_INSTALLATION }
      end

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
                (operation.kind == Operation::DELETE_FILE ? valid_delete?(attributes) : valid_write?(attributes))
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
          validate_hashes!(state.factory_file_hashes, current_targets: @factory_targets)
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
