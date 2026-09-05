# frozen_string_literal: true

module ProductFactory
  module Setup
    class OperationHandlers
      def initialize(target_root:)
        @root = target_root
        @files = FileSync::Target.new(root: target_root)
      end

      def to_h
        {
          Operation::WRITE_FILE => handler(
            apply: ->(operation) { @files.apply(operation) },
            verify: method(:factory_file?)
          ),
          Operation::DELETE_FILE => handler(
            apply: ->(operation) { @files.apply(operation) },
            verify: method(:factory_file_deleted?)
          ),
          Operation::SEED_CONFIG => handler(apply: method(:apply_config), verify: method(:config_matches?)),
          Operation::WRITE_INSTALLATION => handler(
            apply: method(:apply_installation),
            verify: method(:installation_matches?)
          )
        }
      end

      def validate_preconditions!(plan)
        handlers = to_h
        plan.operations.each do |operation|
          next unless PlanValidator::FILE_KINDS.include?(operation.kind)
          next if handlers.fetch(operation.kind).fetch(:verify).call(operation)

          expected = operation.attributes.fetch("expected_local_hash")
          actual = @files.hash(operation.target)
          raise ConflictError, "#{operation.target} changed since plan" unless actual == expected
        end
      end

      private

      def handler(apply:, verify:)
        { apply:, verify: }
      end

      def factory_file?(operation)
        attributes = operation.attributes
        expected_hash = Digest::SHA256.hexdigest(attributes.fetch("content_base64").unpack1("m0"))
        state = @files.state(operation.target)
        state && state.fetch(:hash) == expected_hash && state.fetch(:mode) == attributes.fetch("mode")
      rescue Errno::ENOENT, KeyError, ArgumentError
        false
      end

      def factory_file_deleted?(operation)
        @files.state(operation.target).nil?
      end

      def apply_config(operation)
        validate_config!(operation)
        ensure_factory_directory!
        return if config_matches?(operation)
        raise ConflictError, "#{Config::PATH} already exists" if File.exist?(config_path)

        create_config(operation.attributes.fetch("content_base64").unpack1("m0"))
      end

      def config_matches?(operation)
        validate_config!(operation)
        File.binread(config_path) == operation.attributes.fetch("content_base64").unpack1("m0")
      rescue Errno::ENOENT
        false
      end

      def validate_config!(operation)
        valid = operation.target == Config::PATH && operation.attributes.is_a?(Hash) &&
                operation.attributes["content_base64"].is_a?(String)
        raise ValidationError, "invalid config seed operation" unless valid
      end

      def ensure_factory_directory!
        directory = File.dirname(config_path)
        raise ValidationError, "factory directory is a symlink" if File.symlink?(directory)

        FileUtils.mkdir_p(directory)
        raise ValidationError, "factory directory is not a directory" unless File.directory?(directory)
      end

      def create_config(bytes)
        Tempfile.create([".product-factory-config-", ".tmp"], File.dirname(config_path)) do |temporary|
          temporary.binmode
          temporary.write(bytes)
          temporary.flush
          temporary.fsync
          temporary.chmod(0o644)
          File.link(temporary.path, config_path)
        rescue Errno::EEXIST
          raise ConflictError, "#{Config::PATH} already exists"
        end
      end

      def config_path = File.join(@root, Config::PATH)

      def apply_installation(operation)
        validate_installation!(operation)
        Installation.new(operation.attributes).write(@root)
      end

      def installation_matches?(operation)
        validate_installation!(operation)
        state = Installation.load(@root).to_h
        return false unless state == operation.attributes

        state.fetch("factory_file_hashes").all? { |path, hash| @files.hash(path) == hash }
      rescue Errno::ENOENT, ValidationError, KeyError, TypeError
        false
      end

      def validate_installation!(operation)
        return if operation.target == Installation::PATH && operation.attributes.is_a?(Hash)

        raise ValidationError, "invalid installation operation"
      end
    end
  end
end
