# frozen_string_literal: true

module ProductFactory
  module GitHub
    class Client
      HEADERS = [
        "--header", "Accept: application/vnd.github+json",
        "--header", "X-GitHub-Api-Version: 2026-03-10"
      ].freeze

      def initialize(shell:)
        @shell = shell
      end

      def get(endpoint) = request(endpoint, method: "GET")
      def post(endpoint, body) = request(endpoint, method: "POST", body:)
      def put(endpoint, body) = request(endpoint, method: "PUT", body:)

      def graphql(query, variables = {})
        post("graphql", "query" => query, "variables" => variables)
      end

      def auth_status
        _output, error, status = @shell.capture3("gh", "auth", "status", "--active", chdir: nil, stdin_data: nil)
        return true if status.success?

        raise failure(error, status.exitstatus)
      end

      private

      def request(endpoint, method:, body: nil)
        command = ["gh", "api", endpoint, "--method", method, *HEADERS]
        command += ["--input", "-"] if body
        output, error, status = @shell.capture3(
          *command,
          chdir: nil,
          stdin_data: body && JSON.generate(body)
        )
        return parse(output) if status.success?

        raise failure(error, status.exitstatus)
      rescue JSON::ParserError => e
        raise failure("invalid GitHub JSON: #{e.message}", 1)
      end

      def parse(output)
        data = JSON.parse(output)
        return data if data.is_a?(Hash) || data.is_a?(Array)

        raise JSON::ParserError, "response must be an object or array"
      end

      def failure(error, exit_status)
        root_cause = "GitHub request failed (exit #{exit_status}): #{redact(error)}"
        ExternalFailure.new(
          failed_rule: "github_request",
          responsible_component: "github",
          root_cause:,
          impact: "GitHub state was not read or changed",
          recovery_action: "fix GitHub CLI authentication or permissions, then rerun product-factory setup"
        )
      end

      def redact(value)
        value.to_s
             .gsub(/gh[a-z]_[A-Za-z0-9_]+/, "[REDACTED]")
             .gsub(/Authorization:[^\r\n]*/i, "[REDACTED]")
             .strip
      end
    end
  end
end
