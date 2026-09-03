# frozen_string_literal: true

require "digest"
require "fileutils"
require "tempfile"

module ProductFactory
  class Setup
    class OperationHandlers
      def initialize(target_root:)
        @target_root = target_root
        @managed_files = ManagedFiles.new(sources: {})
      end

      def to_h
        {
          "write_file" => handler(
            apply: ->(operation) { @managed_files.apply(operation, target_root: @target_root) },
            verify: method(:managed_file?)
          ),
          "delete_file" => handler(
            apply: ->(operation) { @managed_files.apply(operation, target_root: @target_root) },
            verify: method(:managed_file_deleted?)
          ),
          "seed_config" => handler(apply: method(:seed_config), verify: method(:seeded_config?)),
          "write_installation" => handler(apply: method(:write_installation), verify: method(:installation?))
        }
      end

      def validate_preconditions!(plan)
        handlers = to_h
        plan.operations.each do |operation|
          next unless PlanValidator::MANAGED_KINDS.include?(operation.kind)
          next if handlers.fetch(operation.kind).verify.call(operation)

          expected = operation.attributes.fetch("expected_local_hash")
          actual = @managed_files.current_hash(target_root: @target_root, path: operation.target)
          raise ConflictError, "#{operation.target} changed since plan" unless actual == expected
        end
      end

      private

      def handler(apply:, verify:)
        Executor::Handler.new(apply:, verify:)
      end

      def seed_config(operation)
        validate_seed!(operation)
        path = File.join(@target_root, Config::PATH)
        ensure_factory_directory
        bytes = operation.attributes.fetch("content_base64").unpack1("m0")
        if File.exist?(path)
          return if File.binread(path) == bytes

          raise ConflictError, "#{Config::PATH} already exists"
        end

        create_config(path, bytes)
      end

      def create_config(path, bytes)
        Tempfile.create([".product-factory-config-", ".tmp"], File.dirname(path)) do |temp|
          temp.binmode
          temp.write(bytes)
          temp.flush
          temp.fsync
          temp.chmod(0o644)
          File.link(temp.path, path)
        rescue Errno::EEXIST
          raise ConflictError, "#{Config::PATH} already exists"
        end
      end

      def validate_seed!(operation)
        attributes = operation.attributes
        valid = operation.target == Config::PATH &&
                attributes.is_a?(Hash) && attributes["content_base64"].is_a?(String)
        raise ValidationError, "invalid config seed operation" unless valid
      end

      def seeded_config?(operation)
        validate_seed!(operation)
        File.binread(File.join(@target_root, Config::PATH)) ==
          operation.attributes.fetch("content_base64").unpack1("m0")
      rescue Errno::ENOENT
        false
      end

      def managed_file?(operation)
        attributes = operation.attributes
        expected_hash = Digest::SHA256.hexdigest(attributes.fetch("content_base64").unpack1("m0"))
        state = @managed_files.current_state(target_root: @target_root, path: operation.target)
        state && state.fetch(:hash) == expected_hash && state.fetch(:mode) == attributes.fetch("mode")
      rescue Errno::ENOENT, KeyError, ArgumentError
        false
      end

      def managed_file_deleted?(operation)
        @managed_files.current_state(target_root: @target_root, path: operation.target).nil?
      end

      def installation?(operation)
        return false unless operation.target == Installation::PATH && operation.attributes.is_a?(Hash)

        state = Installation.load(@target_root).to_h
        return false unless state == operation.attributes

        state.fetch("managed_file_hashes").all? do |path, expected_hash|
          @managed_files.current_hash(target_root: @target_root, path:) == expected_hash
        end
      rescue Errno::ENOENT, ValidationError, KeyError, TypeError
        false
      end

      def write_installation(operation)
        unless operation.target == Installation::PATH && operation.attributes.is_a?(Hash)
          raise ValidationError, "invalid installation operation"
        end

        ensure_factory_directory
        Installation.new(operation.attributes).write(@target_root)
      end

      def ensure_factory_directory
        directory = File.join(@target_root, ".product-factory")
        raise ValidationError, "factory directory is a symlink" if File.symlink?(directory)

        FileUtils.mkdir_p(directory)
        raise ValidationError, "factory directory is not a directory" unless File.directory?(directory)
      end
    end
  end
end
