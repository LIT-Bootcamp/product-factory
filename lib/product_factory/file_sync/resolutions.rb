# frozen_string_literal: true

module ProductFactory
  module FileSync
    class Resolutions
      def initialize(values)
        @values = string_keyed(values).to_h do |path, value|
          choice, merged_hash = unpack(value)
          validate!(path, choice, merged_hash)
          [path, [choice, merged_hash]]
        end
      end

      def fetch(path) = @values.fetch(path, [nil, nil])

      def validate_targets!(paths)
        unknown = @values.keys - paths
        raise ValidationError, "resolution targets unknown path: #{unknown.first}" if unknown.any?
      end

      private

      def unpack(value)
        return [value, nil] unless value.is_a?(Hash)

        [
          value["resolution"] || value[:resolution] || value["choice"] || value[:choice],
          value["merged_hash"] || value[:merged_hash]
        ]
      end

      def validate!(path, choice, merged_hash)
        raise ValidationError, "invalid resolution for #{path}: #{choice.inspect}" unless RESOLUTIONS.include?(choice)
        return unless choice == "manual_merge" && merged_hash && !merged_hash.match?(/\A[0-9a-f]{64}\z/)

        raise ValidationError, "invalid merged hash for #{path}"
      end

      def string_keyed(values)
        values.to_h { |path, value| [path.to_s, value] }
      end
    end
  end
end
