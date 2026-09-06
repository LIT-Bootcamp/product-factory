# frozen_string_literal: true

module ProductFactory
  module GitHub
    class Snapshot < Service
      def initialize(config:, client:)
        super()
        @github = config.github
        @client = client
      end

      def call
        @client.auth_status
        membership = @client.get("user/memberships/orgs/#{organization}")
        validate_membership!(membership)
        graph, projects = load_graph
        validate_repository!(graph.fetch("repository"))
        immutable(data(graph, membership, projects))
      rescue KeyError, NoMethodError => e
        raise failure("invalid GitHub state: #{e.message}")
      end

      private

      def data(graph, membership, projects)
        {
          "actor" => graph.dig("viewer", "login"),
          "organization" => {
            "id" => graph.dig("organization", "id"), "login" => organization, "role" => membership.fetch("role")
          },
          "repository" => repository_data(graph.fetch("repository")),
          "issue_types" => issue_types,
          "projects" => projects.map { |item| project_data(item) }
        }
      end

      def load_graph
        projects = []
        cursor = nil
        loop do
          variables = { "organization" => organization, "repository" => repository, "cursor" => cursor }
          data = @client.graphql(Queries::SNAPSHOT, variables).fetch("data")
          page = data.dig("organization", "projectsV2") || {}
          projects.concat(page.fetch("nodes", []))
          return [data, projects] unless page.dig("pageInfo", "hasNextPage")

          cursor = page.dig("pageInfo", "endCursor")
        end
      end

      def project_data(item)
        number = item.fetch("number")
        relevant = relevant_project?(item)
        fields = relevant ? project_fields(number) : []
        {
          "id" => item.fetch("id"), "number" => number, "title" => item.fetch("title"),
          "short_description" => item["shortDescription"], "public" => item.fetch("public"),
          "closed" => item.fetch("closed"), "item_count" => item.dig("items", "totalCount"),
          "repositories" => item.dig("repositories", "nodes").to_a.map { |repo| repo.fetch("nameWithOwner") }.sort,
          "fields" => fields,
          "views" => relevant ? project_views(number) : []
        }
      end

      def project_fields(number)
        response = @client.get("orgs/#{organization}/projectsV2/#{number}/fields?per_page=100")
        items = response.is_a?(Hash) ? response.fetch("fields", []) : response
        items.map do |field|
          {
            "id" => field.fetch("id"), "node_id" => field["node_id"], "name" => field.fetch("name"),
            "type" => field.fetch("data_type").downcase,
            "options" => field.fetch("options", []).map { |option| option_data(option) }
          }
        end
      end

      def option_data(option)
        option.slice("id", "color").merge(
          "name" => raw_text(option["name"]), "description" => raw_text(option["description"])
        )
      end

      def raw_text(value) = value.is_a?(Hash) ? value.fetch("raw") : value

      def project_views(number)
        response = @client.graphql(Queries::VIEWS, "organization" => organization, "number" => number)
        response.dig("data", "organization", "projectV2", "views", "nodes").to_a.map { |view| view_data(view) }
      end

      def view_data(view)
        fields = view.dig("configuration", "visibleFields", "nodes").to_a
        {
          "id" => view.fetch("id"), "number" => view.fetch("number"), "name" => view.fetch("name"),
          "layout" => view.fetch("layout").delete_suffix("_LAYOUT"), "filter" => view["filter"].to_s,
          "visible_fields" => fields.map { |field| field.fetch("name") }
        }
      end

      def issue_types
        response = @client.get("orgs/#{organization}/issue-types")
        items = response.is_a?(Hash) ? response.fetch("issue_types", []) : response
        items.map { |item| item.slice("id", "name", "description", "color", "is_enabled") }
      end

      def repository_data(data) = data.slice("id", "name").merge("name_with_owner" => data.fetch("nameWithOwner"))
      def organization = @github.fetch("organization")
      def repository = @github.fetch("repository")
      def marker = "product-factory:v1:project:#{organization}/#{repository}"

      def relevant_project?(item)
        item["title"] == @github.fetch("project_title") ||
          item["shortDescription"].to_s.include?(marker) || item["title"].to_s.include?("[#{marker}]")
      end

      def validate_membership!(membership)
        valid = membership["state"] == "active" && membership["role"] == "admin"
        raise failure("active organization admin membership is required") unless valid
      end

      def validate_repository!(data)
        valid = data && data["nameWithOwner"] == "#{organization}/#{repository}"
        raise failure("configured repository does not match GitHub") unless valid
      end

      def failure(cause)
        ExternalFailure.new(
          failed_rule: "github_preflight", responsible_component: "authenticated operator",
          root_cause: cause, impact: "setup planning stopped before mutation",
          recovery_action: "fix GitHub access or configuration, then rerun product-factory setup"
        )
      end

      def immutable(value) = JSON.parse(JSON.generate(value), freeze: true)
    end
  end
end
