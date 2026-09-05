# frozen_string_literal: true

module ProductFactory
  module Setup
    class Options < Service
      def initialize(arguments:)
        super()
        @arguments = arguments
      end

      def call
        values = @arguments.dup
        options = { resolutions: {}, adoptions: [] }
        add_option(options, values) until values.empty?
        options
      end

      private

      def add_option(options, values)
        argument = values.shift
        return add_adoption(options.fetch(:adoptions), argument, values) if argument.start_with?("--adopt")

        add_resolution(options.fetch(:resolutions), argument, values)
      end

      def add_adoption(adoptions, argument, values)
        value = argument == "--adopt" ? values.shift : argument.delete_prefix("--adopt=")
        raise UsageError, "unknown adoption: #{value}" unless valid_adoption?(value)

        adoptions << value
      end

      def add_resolution(resolutions, argument, values)
        value = argument == "--resolve" ? values.shift : argument.delete_prefix("--resolve=")
        path, resolution = value&.split("=", 2)
        raise UsageError, "resolve must be PATH=VALUE" unless path && resolution

        resolutions[path] = resolution
      end

      def valid_adoption?(value)
        issue = value&.start_with?("issue-type:") && %w[Idea Epic Ticket].include?(value.delete_prefix("issue-type:"))
        wiki = Wiki::Repository::OWNED_PAGES.map { |name| "wiki:#{name.delete_suffix('.md')}" }.include?(value)
        value == "project" || issue || wiki
      end
    end
  end
end
