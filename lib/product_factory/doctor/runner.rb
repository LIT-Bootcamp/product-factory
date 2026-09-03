# frozen_string_literal: true

module ProductFactory
  module Doctor
    class Runner
      def self.call(...) = new(...).call

      def initialize(root:, command_runner: nil)
        @root = File.expand_path(root)
        @command_runner = command_runner || method(:capture)
      end

      def call
        system_checks + project_checks
      end

      private

      def system_checks = [ruby_check, git_check, github_check, work_tree_check]
      def project_checks = [config_check, installation_check, knowledge_check].compact

      def capture(*command)
        output, error, status = Open3.capture3(*command)
        [status.success?, (output + error).strip]
      rescue SystemCallError => e
        [false, e.message]
      end

      def ruby_check
        success, message = @command_runner.call("ruby", "--version")
        status = success && message.match?(/\Aruby 4\.0\.6(?:\s|\z)/) ? :pass : :fail

        Check.new("ruby", status, message)
      end

      def git_check = command_check("git", "git", "--version")
      def github_check = command_check("gh", "gh", "--version")

      def command_check(name, *command)
        success, message = @command_runner.call(*command)
        Check.new(name, success ? :pass : :fail, message)
      end

      def work_tree_check
        success, message = @command_runner.call("git", "-C", @root, "rev-parse", "--is-inside-work-tree")
        status = success && message.strip == "true" ? :pass : :fail

        Check.new("work_tree", status, message)
      end

      def config_check = state_file_check("config", Config::PATH) { Config.load(@root) }
      def installation_check = state_file_check("installation", Installation::PATH) { Installation.load(@root) }

      def state_file_check(name, relative_path)
        path = File.join(@root, relative_path)
        return Check.new(name, :warn, "not installed") unless File.exist?(path) || File.symlink?(path)
        return Check.new(name, :fail, "must be a regular file") unless File.lstat(path).file?

        yield
        Check.new(name, :pass, "readable")
      rescue ValidationError => e
        Check.new(name, :fail, e.message)
      end

      def knowledge_check
        return unless File.exist?(File.join(@root, Installation::PATH))

        missing = Config.load(@root).knowledge.fetch("paths", []).reject { |path| knowledge_path?(path) }
        message = missing.empty? ? "present" : "missing: #{missing.join(', ')}"
        Check.new("knowledge", missing.empty? ? :pass : :fail, message)
      rescue ValidationError => e
        Check.new("knowledge", :fail, e.message)
      end

      def knowledge_path?(relative_path)
        return false unless relative_path.is_a?(String)

        parts = relative_path.split(File::SEPARATOR, -1)
        return false if parts.any? { |part| part.empty? || part == "." || part == ".." }
        return false unless File.expand_path(relative_path, @root).start_with?("#{@root}#{File::SEPARATOR}")

        path_without_symlinks?(parts)
      end

      def path_without_symlinks?(parts)
        parts.reduce(@root) do |current, part|
          path = File.join(current, part)
          return false if File.lstat(path).symlink?

          path
        end
        true
      rescue Errno::ENOENT
        false
      end
    end
  end
end
