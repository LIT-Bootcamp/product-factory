# frozen_string_literal: true

module ProductFactory
  class Setup
    class OperationHandlers
      def initialize(target_root:)
        @files = FileSync::Target.new(root: target_root)
        @config = ConfigFile.new(root: target_root)
        @installation = InstallationFile.new(root: target_root, files: @files)
      end

      def to_h
        {
          "write_file" => handler(
            apply: ->(operation) { @files.apply(operation) },
            verify: method(:factory_file?)
          ),
          "delete_file" => handler(
            apply: ->(operation) { @files.apply(operation) },
            verify: method(:factory_file_deleted?)
          ),
          "seed_config" => handler(apply: @config.method(:apply), verify: @config.method(:matches?)),
          "write_installation" => handler(apply: @installation.method(:apply), verify: @installation.method(:matches?))
        }
      end

      def validate_preconditions!(plan)
        handlers = to_h
        plan.operations.each do |operation|
          next unless PlanValidator::FILE_KINDS.include?(operation.kind)
          next if handlers.fetch(operation.kind).verify.call(operation)

          expected = operation.attributes.fetch("expected_local_hash")
          actual = @files.hash(operation.target)
          raise ConflictError, "#{operation.target} changed since plan" unless actual == expected
        end
      end

      private

      def handler(apply:, verify:)
        Executor::Handler.new(apply:, verify:)
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
    end
  end
end
