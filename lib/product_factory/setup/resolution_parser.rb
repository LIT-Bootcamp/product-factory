# frozen_string_literal: true

module ProductFactory
  class Setup
    class ResolutionParser
      def self.call(arguments) = new(arguments).call

      def initialize(arguments)
        @arguments = arguments.dup
      end

      def call
        resolutions = {}
        until @arguments.empty?
          path, resolution = next_resolution
          resolutions[path] = resolution
        end
        resolutions
      end

      private

      def next_resolution
        argument = @arguments.shift
        value = argument == "--resolve" ? @arguments.shift : argument&.delete_prefix("--resolve=")
        path, resolution = value&.split("=", 2)
        raise UsageError, "resolve must be PATH=VALUE" unless path && resolution

        [path, resolution]
      end
    end
  end
end
