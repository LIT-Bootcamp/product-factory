# frozen_string_literal: true

module ProductFactory
  module FileSync
    class Planner < Service
      def initialize(sources:, target_root:, installed_hashes:, resolutions: {})
        super()
        @sources = sources.to_h { |target, source| [target.to_s.dup.freeze, source.to_s.dup.freeze] }.freeze
        @target = Target.new(root: target_root)
        @installed_hashes = string_keyed(installed_hashes)
        @resolutions = string_keyed(resolutions)
      end

      def call
        paths = (@sources.keys | @installed_hashes.keys).sort
        validate_resolution_targets!(paths)
        changes = paths.map { |path| change(path) }

        {
          operations: changes.filter_map { |change| change[:operation] },
          conflicts: changes.filter_map { |change| change[:conflict] },
          next_hashes: next_hashes(changes)
        }
      end

      private

      def change(path)
        Change.call(
          path:,
          source: @sources[path],
          target: @target,
          installed_hash: @installed_hashes[path],
          resolution: @resolutions[path]
        )
      end

      def string_keyed(values)
        values.to_h { |path, value| [path.to_s, value] }
      end

      def validate_resolution_targets!(paths)
        unknown = @resolutions.keys - paths
        raise ValidationError, "resolution targets unknown path: #{unknown.first}" if unknown.any?
      end

      def next_hashes(changes)
        changes.each_with_object({}) do |change, hashes|
          hashes[change[:path]] = change[:next_hash] if change[:next_hash]
        end
      end
    end
  end
end
