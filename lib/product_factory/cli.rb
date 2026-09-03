# frozen_string_literal: true

require "open3"

module ProductFactory
  class CLI
    COMMANDS = %w[doctor plan apply validate test].freeze

    def self.start(argv, input: $stdin, output: $stdout, error: $stderr, cwd: Dir.pwd)
      new(input:, output:, error:, cwd:).start(argv)
    end

    def initialize(input:, output:, error:, cwd:)
      @input = input
      @output = output
      @error = error
      @cwd = cwd
    end

    def start(argv)
      dispatch(argv) || 0
    rescue UsageError => e
      @error.puts(e.message)
      64
    rescue ConflictError => e
      @error.puts(e.message)
      2
    rescue SystemCallError => e
      @error.puts("Command failed: #{e.message}")
      1
    rescue Error => e
      @error.puts(e.message)
      1
    end

    private

    def dispatch(argv)
      case argv.first
      when "plan" then plan(argv.drop(1))
      when "apply" then apply(argv[1])
      when "doctor" then doctor
      when "validate" then validate
      when "test" then test
      else Application.start(argv, output: @output, error: @error, cwd: @cwd)
      end
    end

    def setup = Setup.from_cli(cwd: @cwd, input: @input, output: @output)

    def plan(arguments)
      setup.plan_and_print(arguments)
      0
    end

    def apply(plan_path)
      raise UsageError, "apply requires PLAN_PATH" unless plan_path

      setup.load_and_apply(plan_path)
      0
    end

    def doctor
      checks = Doctor.new(root: @cwd).call
      checks.each { |check| @output.puts("#{check.name}: #{check.status} #{check.message}") }
      checks.any? { |check| check.status == :fail } ? 1 : 0
    end

    def validate
      Validator.new(root: @cwd).call
      @output.puts("Product Factory installation is valid")
      0
    end

    def test
      command = %w[bundle exec rspec]
      installation_path = File.join(@cwd, Installation::PATH)
      if File.exist?(installation_path) || File.symlink?(installation_path)
        Validator.new(root: @cwd).call
        command << ".product-factory/spec/runtime_spec.rb"
      end
      standard_output, standard_error, status = Open3.capture3(*command, chdir: @cwd)
      @output.print(standard_output)
      @error.print(standard_error)
      status.exitstatus || 1
    end
  end
end
