require "thor"
require "open3"

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

    %w[doctor validate test].each do |command|
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
      case argv.first
      when "plan"
        Setup.from_cli(cwd:, input:, output:).plan_and_print(argv.drop(1))
        0
      when "apply"
        raise UsageError, "apply requires PLAN_PATH" unless argv[1]

        Setup.from_cli(cwd:, input:, output:).load_and_apply(argv[1])
        0
      when "doctor"
        checks = Doctor.new(root: cwd).call
        checks.each { |check| output.puts("#{check.name}: #{check.status} #{check.message}") }
        checks.any? { |check| check.status == :fail } ? 1 : 0
      when "validate"
        Validator.new(root: cwd).call
        output.puts("Product Factory installation is valid")
        0
      when "test"
        command = ["bundle", "exec", "rspec"]
        command << ".product-factory/spec/runtime_spec.rb" if File.exist?(File.join(cwd, Installation::PATH))
        standard_output, standard_error, status = Open3.capture3(*command, chdir: cwd)
        output.print(standard_output)
        error.print(standard_error)
        status.exitstatus || 1
      else
        Application.start(argv, output:, error:, cwd:) || 0
      end
    rescue UsageError => exception
      error.puts(exception.message)
      64
    rescue ConflictError => exception
      error.puts(exception.message)
      2
    rescue SystemCallError => exception
      error.puts("Command failed: #{exception.message}")
      1
    rescue Error => exception
      error.puts(exception.message)
      1
    end
  end
end
