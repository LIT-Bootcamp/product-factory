# frozen_string_literal: true

require "digest"

module ProductFactory
  class ManagedFiles
    class Planner
      def initialize(sources:, store:)
        @sources = sources
        @store = store
      end

      def call(target_root:, installed_hashes:, resolutions:)
        @target_root = target_root
        @installed_hashes = string_keyed(installed_hashes)
        @resolutions = normalized_resolutions(resolutions)
        @operations = []
        @conflicts = []
        @next_hashes = {}

        paths = (@sources.keys | @installed_hashes.keys).sort
        validate_resolutions!(paths)
        paths.each { |path| plan_path(path) }

        { operations: @operations, conflicts: @conflicts, next_hashes: @next_hashes }
      end

      private

      def plan_path(path)
        local = @store.current_hash(target_root: @target_root, path:)
        installed = @installed_hashes[path]
        upstream, bytes, mode = upstream_state(path)
        decision = if @sources.key?(path)
                     refresh_decision(installed:, local:, upstream:)
                   else
                     removal_decision(installed:, local:)
                   end

        if decision == :conflict
          resolve_conflict(path, installed:, local:, upstream:, bytes:, mode:)
        else
          record_decision(path, decision, local:, upstream:, bytes:, mode:)
        end
      end

      def upstream_state(path)
        return [nil, nil, nil] unless @sources.key?(path)

        bytes, mode = @store.read_source(@sources.fetch(path))
        [Digest::SHA256.hexdigest(bytes), bytes, mode]
      end

      def resolve_conflict(path, installed:, local:, upstream:, bytes:, mode:)
        resolution, merged_hash = @resolutions.fetch(path, [nil, nil])

        case resolution
        when "keep_local"
          @next_hashes[path] = upstream if upstream
        when "take_upstream"
          take_upstream(path, local:, upstream:, bytes:, mode:, resolution:)
        when "manual_merge"
          record_manual_merge(path, installed:, local:, upstream:, merged_hash:, resolution:)
        else
          record_conflict(path, installed:, local:, upstream:, resolution:)
        end
      end

      def take_upstream(path, local:, upstream:, bytes:, mode:, resolution:)
        if upstream
          @operations << write_operation(path, bytes, mode, expected_local_hash: local, reason: resolution)
          @next_hashes[path] = upstream
        else
          @operations << delete_operation(path, local, resolution)
        end
      end

      def record_manual_merge(path, installed:, local:, upstream:, merged_hash:, resolution:)
        if merged_hash && local == merged_hash
          @next_hashes[path] = upstream if upstream
        else
          record_conflict(path, installed:, local:, upstream:, resolution:)
        end
      end

      def record_conflict(path, installed:, local:, upstream:, resolution:)
        @conflicts << {
          "path" => path,
          "installed_hash" => installed,
          "local_hash" => local,
          "upstream_hash" => upstream,
          "resolution" => resolution
        }
        @next_hashes[path] = installed if installed
      end

      def record_decision(path, decision, local:, upstream:, bytes:, mode:)
        case decision
        when :write_upstream
          @operations << write_operation(path, bytes, mode, expected_local_hash: local)
          @next_hashes[path] = upstream
        when :preserve_local, :adopt, :noop
          @next_hashes[path] = upstream
        when :delete_upstream
          @operations << delete_operation(path, local)
        end
      end

      def write_operation(path, bytes, mode, expected_local_hash:, reason: nil)
        attributes = {
          "content_base64" => [bytes].pack("m0"),
          "expected_local_hash" => expected_local_hash,
          "mode" => mode
        }
        attributes["reason"] = reason if reason
        Operation.new(kind: "write_file", target: path, attributes:)
      end

      def delete_operation(path, local, reason = nil)
        attributes = { "expected_local_hash" => local }
        attributes["reason"] = reason if reason
        Operation.new(kind: "delete_file", target: path, attributes:)
      end

      def normalized_resolutions(values)
        string_keyed(values).to_h do |path, value|
          choice, merged_hash = resolution(value)
          raise ValidationError, "invalid resolution for #{path}: #{choice.inspect}" unless RESOLUTIONS.include?(choice)
          if choice == "manual_merge" && merged_hash && !merged_hash.match?(/\A[0-9a-f]{64}\z/)
            raise ValidationError, "invalid merged hash for #{path}"
          end

          [path, [choice, merged_hash]]
        end
      end

      def resolution(value)
        return [value, nil] if value.is_a?(String)
        return [value, nil] unless value.is_a?(Hash)

        [
          value["resolution"] || value[:resolution] || value["choice"] || value[:choice],
          value["merged_hash"] || value[:merged_hash]
        ]
      end

      def validate_resolutions!(paths)
        unknown = @resolutions.keys - paths
        raise ValidationError, "resolution targets unknown path: #{unknown.first}" if unknown.any?
      end

      def refresh_decision(installed:, local:, upstream:)
        return initial_decision(local:, upstream:) if installed.nil?
        return :write_upstream if local == installed && upstream != installed
        return :preserve_local if local != installed && upstream == installed
        return :adopt if local == upstream
        return :conflict if local != installed && upstream != installed

        :noop
      end

      def initial_decision(local:, upstream:)
        return :write_upstream if local.nil?
        return :adopt if local == upstream

        :conflict
      end

      def removal_decision(installed:, local:)
        return :removed if installed.nil? || local.nil?
        return :delete_upstream if local == installed

        :conflict
      end

      def string_keyed(values)
        values.to_h { |path, value| [path.to_s, value] }
      end
    end
  end
end
