# frozen_string_literal: true

require "thor"

module ProductFactory
  class Application < Thor
    package_name "product-factory"

    map "--version" => :version

    desc "version", "Print the Product Factory version"
    def version
      say "product-factory #{VERSION}"
      0
    end

    %w[doctor validate test].each do |command|
      desc command, "#{command.capitalize} the Product Factory environment"
      define_method(command) { raise UsageError, "#{command} is not installed" }
    end

    class << self
      def start(argv, output:, error:, cwd:)
        dispatch(nil, argv.dup, nil, shell: StreamShell.new(output, error), cwd: cwd)
      rescue Thor::Error => e
        message = if e.is_a?(Thor::UndefinedCommandError)
                    "Unknown command: #{e.command}"
                  else
                    e.message
                  end
        raise UsageError, message
      end
    end
  end
end
