# frozen_string_literal: true

module ProductFactory
  module FileSync
    class Planner
      def self.call(...) = new(...).call

      def initialize(sources:, target_root:, installed_hashes:, resolutions: {})
        @sources = sources.to_h { |target, source| [target.to_s.dup.freeze, source.to_s.dup.freeze] }.freeze
        @target = Target.new(root: target_root)
        @installed_hashes = string_keyed(installed_hashes)
        @resolutions = Resolutions.new(resolutions)
      end

      def call
        @operations = []
        @conflicts = []
        @next_hashes = {}

        paths = (@sources.keys | @installed_hashes.keys).sort
        @resolutions.validate_targets!(paths)
        paths.each { |path| plan(path) }

        { operations: @operations, conflicts: @conflicts, next_hashes: @next_hashes }
      end

      private

      def plan(path)
        local = @target.hash(path)
        installed = @installed_hashes[path]
        upstream, bytes, mode = source_state(path)
        decision = Decision.call(source_present: @sources.key?(path), installed:, local:, upstream:)

        if decision == :conflict
          resolve(path, installed:, local:, upstream:, bytes:, mode:)
        else
          record(path, decision, local:, upstream:, bytes:, mode:)
        end
      end

      def source_state(path)
        return [nil, nil, nil] unless @sources.key?(path)

        bytes, mode = Source.read(@sources.fetch(path))
        [Digest::SHA256.hexdigest(bytes), bytes, mode]
      end

      def resolve(path, installed:, local:, upstream:, bytes:, mode:)
        resolution, merged_hash = @resolutions.fetch(path)

        case resolution
        when "keep_local" then @next_hashes[path] = upstream if upstream
        when "take_upstream" then take_upstream(path, local:, upstream:, bytes:, mode:)
        when "manual_merge" then accept_manual_merge(path, installed:, local:, upstream:, merged_hash:)
        else add_conflict(path, installed:, local:, upstream:, resolution:)
        end
      end

      def take_upstream(path, local:, upstream:, bytes:, mode:)
        if upstream
          @operations << write_operation(path, bytes, mode, local, "take_upstream")
          @next_hashes[path] = upstream
        else
          @operations << delete_operation(path, local, "take_upstream")
        end
      end

      def accept_manual_merge(path, installed:, local:, upstream:, merged_hash:)
        return @next_hashes[path] = upstream if merged_hash && local == merged_hash && upstream
        return if merged_hash && local == merged_hash

        add_conflict(path, installed:, local:, upstream:, resolution: "manual_merge")
      end

      def add_conflict(path, installed:, local:, upstream:, resolution:)
        @conflicts << {
          "path" => path,
          "installed_hash" => installed,
          "local_hash" => local,
          "upstream_hash" => upstream,
          "resolution" => resolution
        }
        @next_hashes[path] = installed if installed
      end

      def record(path, decision, local:, upstream:, bytes:, mode:)
        case decision
        when :write_upstream
          @operations << write_operation(path, bytes, mode, local)
          @next_hashes[path] = upstream
        when :preserve_local, :adopt, :noop
          @next_hashes[path] = upstream
        when :delete_upstream
          @operations << delete_operation(path, local)
        end
      end

      def write_operation(path, bytes, mode, expected_hash, reason = nil)
        attributes = { "content_base64" => [bytes].pack("m0"), "expected_local_hash" => expected_hash, "mode" => mode }
        attributes["reason"] = reason if reason
        Operation.new(kind: "write_file", target: path, attributes:)
      end

      def delete_operation(path, expected_hash, reason = nil)
        attributes = { "expected_local_hash" => expected_hash }
        attributes["reason"] = reason if reason
        Operation.new(kind: "delete_file", target: path, attributes:)
      end

      def string_keyed(values)
        values.to_h { |path, value| [path.to_s, value] }
      end
    end
  end
end
