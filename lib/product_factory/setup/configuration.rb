# frozen_string_literal: true

module ProductFactory
  module Setup
    class Configuration < Service
      GITHUB_REMOTE = %r{(?:github\.com[:/])([^/]+)/([^/]+?)(?:\.git)?\z}

      def initialize(distribution:, target_root:, input:, output:, github_client:, shell:)
        super()
        @distribution = distribution
        @target_root = target_root
        @input = input
        @output = output
        @github_client = github_client
        @shell = shell
      end

      def call
        owner, name = repository_coordinates
        repository = @github_client.get("repos/#{owner}/#{name}")
        bytes, config = config_for(owner, name)
        { config:, bytes:, repository: }
      end

      private

      def repository_coordinates
        output, error, status = @shell.capture3(
          "git", "remote", "get-url", "origin", chdir: @target_root, stdin_data: nil
        )
        raise remote_failure(error) unless status.success?

        match = GITHUB_REMOTE.match(output.strip)
        raise ValidationError, "origin must be a GitHub repository" unless match

        [match[1], match[2]]
      end

      def config_for(owner, repository)
        return existing_config(owner, repository) if File.exist?(config_path)

        first_config(owner, repository)
      end

      def existing_config(owner, repository)
        bytes = File.binread(config_path)
        config = Config.new(YAML.safe_load(bytes, aliases: false) || {})
        expected = { "organization" => owner, "repository" => repository }
        actual = config.github.slice(*expected.keys)
        raise ValidationError, "configured GitHub repository does not match origin" unless actual == expected

        [bytes, config]
      rescue Psych::Exception => e
        raise ValidationError, "Invalid #{Config::PATH}: #{e.message}"
      end

      def first_config(owner, repository)
        data = YAML.safe_load(@distribution.config_bytes, aliases: false)
        default_name = titleize(repository)
        @output.print("Product name [#{default_name}]: ")
        product_name = @input.gets.to_s.chomp.strip
        product_name = default_name if product_name.empty?
        data.fetch("product")["name"] = product_name
        data["github"] = {
          "organization" => owner,
          "repository" => repository,
          "project_title" => "#{default_name} Product Factory"
        }
        [YAML.dump(data), Config.new(data)]
      end

      def titleize(repository) = repository.tr("-_", "  ").split.map(&:capitalize).join(" ")
      def config_path = File.join(@target_root, Config::PATH)

      def remote_failure(cause)
        ExternalFailure.new(
          failed_rule: "git_origin_required", responsible_component: "git",
          root_cause: cause.to_s.strip, impact: "setup planning stopped before mutation",
          recovery_action: "configure a GitHub origin remote, then rerun product-factory setup"
        )
      end
    end
  end
end
