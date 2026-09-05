# frozen_string_literal: true

module ProductFactory
  module GitHub
    class Snapshot < Service
      QUERY = <<~GRAPHQL
        query($organization:String!, $repository:String!, $cursor:String) {
          viewer { login }
          organization(login:$organization) {
            id
            projectsV2(first:100, after:$cursor) {
              nodes {
                id number title shortDescription public closed
                items { totalCount }
                repositories(first:100) { nodes { nameWithOwner } }
                views(first:100) {
                  nodes { id number name layout filter visibleFields(first:100) { nodes { name } } updatedAt }
                }
              }
              pageInfo { hasNextPage endCursor }
            }
          }
          repository(owner:$organization, name:$repository) { id name nameWithOwner }
        }
      GRAPHQL

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
          data = @client.graphql(QUERY, variables).fetch("data")
          page = data.dig("organization", "projectsV2") || {}
          projects.concat(page.fetch("nodes", []))
          return [data, projects] unless page.dig("pageInfo", "hasNextPage")

          cursor = page.dig("pageInfo", "endCursor")
        end
      end

      def project_data(item)
        number = item.fetch("number")
        {
          "id" => item.fetch("id"), "number" => number, "title" => item.fetch("title"),
          "short_description" => item["shortDescription"], "public" => item.fetch("public"),
          "closed" => item.fetch("closed"), "item_count" => item.dig("items", "totalCount"),
          "repositories" => item.dig("repositories", "nodes").to_a.map { |repo| repo.fetch("nameWithOwner") }.sort,
          "fields" => relevant_project?(item) ? project_fields(number) : [],
          "views" => item.dig("views", "nodes").to_a.map { |view| view_data(view) }
        }
      end

      def project_fields(number)
        response = @client.get("orgs/#{organization}/projectsV2/#{number}/fields?per_page=100")
        items = response.is_a?(Hash) ? response.fetch("fields", []) : response
        items.map do |field|
          {
            "id" => field.fetch("id"), "node_id" => field["node_id"], "name" => field.fetch("name"),
            "type" => field.fetch("data_type").downcase,
            "options" => field.fetch("options", []).map { |option| option.slice("id", "name", "color", "description") }
          }
        end
      end

      def view_data(view)
        {
          "id" => view.fetch("id"), "number" => view.fetch("number"), "name" => view.fetch("name"),
          "layout" => view.fetch("layout").delete_suffix("_LAYOUT"), "filter" => view["filter"].to_s,
          "visible_fields" => view.dig("visibleFields", "nodes").to_a.map { |field| field.fetch("name") }
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
        item["title"] == @github.fetch("project_title") || item["shortDescription"].to_s.include?(marker)
      end

      def validate_membership!(membership)
        return if membership["state"] == "active" && membership["role"] == "admin"

        raise failure("active organization admin membership is required")
      end

      def validate_repository!(data)
        return if data && data["nameWithOwner"] == "#{organization}/#{repository}"

        raise failure("configured repository does not match GitHub")
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
