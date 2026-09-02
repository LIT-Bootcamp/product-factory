require "thor"

module ProductFactory
  class StreamShell < Thor::Shell::Basic
    def initialize(output, error)
      super()
      @output = output
      @error = error
    end

    def stdout
      @output
    end

    def stderr
      @error
    end
  end

  class Application < Thor
    package_name "product-factory"

    map "--version" => :version

    desc "version", "Print the Product Factory version"
    def version
      say "product-factory #{VERSION}"
      0
    end

    %w[doctor plan apply validate test].each do |command|
      desc command, "#{command.capitalize} the Product Factory environment"
      define_method(command) { raise UsageError, "#{command} is not installed" }
    end

    class << self
      def start(argv, output:, error:, cwd:)
        dispatch(nil, argv.dup, nil, shell: StreamShell.new(output, error), cwd: cwd)
      rescue Thor::Error => exception
        message = if exception.is_a?(Thor::UndefinedCommandError)
          "Unknown command: #{exception.command}"
        else
          exception.message
        end
        raise UsageError, message
      end
    end
  end

  class CLI
    COMMANDS = %w[doctor plan apply validate test].freeze

    def self.start(argv, input: $stdin, output: $stdout, error: $stderr, cwd: Dir.pwd)
      Application.start(argv, output:, error:, cwd:) || 0
    rescue UsageError => exception
      error.puts(exception.message)
      64
    rescue Error => exception
      error.puts(exception.message)
      1
    end
  end
end
