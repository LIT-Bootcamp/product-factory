require "open3"

module ProductFactory
  class Doctor
    Check = Data.define(:name, :status, :message)

    def initialize(root:, command_runner: nil)
      @root = File.expand_path(root)
      @command_runner = command_runner || method(:capture)
    end

    def call
      [ruby_check, command_check("git", "git", "--version"), command_check("gh", "gh", "--version"),
       work_tree_check, config_check, installation_check, knowledge_check].compact
    end

    private

    def capture(*command)
      output, error, status = Open3.capture3(*command)
      [status.success?, (output + error).strip]
    rescue SystemCallError => exception
      [false, exception.message]
    end

    def ruby_check
      success, message = @command_runner.call("ruby", "--version")
      Check.new("ruby", success && message.match?(/\Aruby 4\.0\.6(?:\s|\z)/) ? :pass : :fail, message)
    end

    def command_check(name, *command)
      success, message = @command_runner.call(*command)
      Check.new(name, success ? :pass : :fail, message)
    end

    def work_tree_check
      success, message = @command_runner.call("git", "-C", @root, "rev-parse", "--is-inside-work-tree")
      Check.new("work_tree", success && message.strip == "true" ? :pass : :fail, message)
    end

    def config_check
      path = File.join(@root, Config::PATH)
      return Check.new("config", :warn, "not installed") unless File.exist?(path) || File.symlink?(path)
      return Check.new("config", :fail, "must be a regular file") unless File.lstat(path).file?

      Config.load(@root)
      Check.new("config", :pass, "readable")
    rescue ValidationError => exception
      Check.new("config", :fail, exception.message)
    end

    def installation_check
      path = File.join(@root, Installation::PATH)
      return Check.new("installation", :warn, "not installed") unless File.exist?(path) || File.symlink?(path)
      return Check.new("installation", :fail, "must be a regular file") unless File.lstat(path).file?

      Installation.load(@root)
      Check.new("installation", :pass, "readable")
    rescue ValidationError => exception
      Check.new("installation", :fail, exception.message)
    end

    def knowledge_check
      return unless File.exist?(File.join(@root, Installation::PATH))

      paths = Config.load(@root).knowledge.fetch("paths", [])
      missing = paths.reject { |path| knowledge_path?(path) }
      Check.new("knowledge", missing.empty? ? :pass : :fail, missing.empty? ? "present" : "missing: #{missing.join(", ")}")
    rescue ValidationError => exception
      Check.new("knowledge", :fail, exception.message)
    end

    def knowledge_path?(relative_path)
      return false unless relative_path.is_a?(String)

      parts = relative_path.split(File::SEPARATOR, -1)
      return false if parts.any? { |part| part.empty? || part == "." || part == ".." }

      path = File.expand_path(relative_path, @root)
      return false unless path.start_with?("#{@root}#{File::SEPARATOR}")

      current = @root
      parts.each do |part|
        current = File.join(current, part)
        stat = File.lstat(current)
        return false if stat.symlink?
      rescue Errno::ENOENT
        return false
      end
      true
    end
  end
end
