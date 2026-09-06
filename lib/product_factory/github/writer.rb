# frozen_string_literal: true

module ProductFactory
  module GitHub
    class Writer
      DEFAULT_STATUS_OPTIONS = ["Todo", "In Progress", "Done"].freeze

      def initialize(config:, client:, state:)
        @github = config.github
        @client = client
        @state = state
      end

      def apply(operation)
        validate_kind!(operation)
        current = @state.resource(operation.target, refresh: true)
        return true if desired?(current, operation)

        verify_precondition!(operation, current)
        send("apply_#{operation.kind}", operation, current)
        raise ValidationError, "verification failed for #{operation.target}" unless @state.matches?(operation)

        true
      end

      private

      def apply_ensure_issue_type(operation, current)
        desired = operation.attributes.fetch("desired")
        body = desired.slice("name", "description", "color", "is_enabled")
        return @client.post("orgs/#{organization}/issue-types", body) unless current

        @client.put("orgs/#{organization}/issue-types/#{current.fetch('id')}", body)
      end

      def apply_ensure_project(operation, current)
        desired = operation.attributes.fetch("desired")
        current ||= create_project(operation, desired)
        raise ValidationError, "created Project was not found" unless current

        update_project(current, desired)
        link_project(current) unless current.fetch("repositories", []).include?(repository_name)
      end

      def create_project(operation, desired)
        input = {
          "ownerId" => snapshot.dig("organization", "id"),
          "repositoryId" => snapshot.dig("repository", "id"),
          "title" => temporary_title(desired),
          "clientMutationId" => operation.id
        }
        @client.graphql(Mutations::CREATE_PROJECT, "input" => input)
        @state.resource(operation.target, refresh: true)
      end

      def update_project(current, desired)
        input = {
          "projectId" => current.fetch("id"), "title" => desired.fetch("title"),
          "public" => false, "shortDescription" => desired.fetch("short_description")
        }
        @client.graphql(Mutations::UPDATE_PROJECT, "input" => input)
      end

      def link_project(current)
        input = { "projectId" => current.fetch("id"), "repositoryId" => snapshot.dig("repository", "id") }
        @client.graphql(Mutations::LINK_PROJECT, "input" => input)
      end

      def apply_ensure_project_field(operation, current)
        desired = operation.attributes.fetch("desired")
        project = project_state
        return create_field(project, desired) unless current

        update_field(project, current, desired)
      end

      def create_field(project, desired)
        body = { "name" => desired.fetch("name"), "data_type" => desired.fetch("type") }
        body["single_select_options"] = desired.fetch("options") if desired["type"] == "single_select"
        @client.post("orgs/#{organization}/projectsV2/#{project.fetch('number')}/fields", body)
      end

      def update_field(project, current, desired)
        input = { "fieldId" => current["node_id"] || current.fetch("id"), "name" => desired.fetch("name") }
        if desired["type"] == "single_select"
          input["singleSelectOptions"] = Payloads.select_options(project, current, desired)
        end
        @client.graphql(Mutations::UPDATE_FIELD, "input" => input)
      end

      def apply_ensure_project_view(operation, current)
        desired = operation.attributes.fetch("desired")
        project = project_state
        current ||= default_view(project, desired)
        return update_view(project, current, desired) if current

        create_view(project, desired)
      end

      def default_view(project, desired)
        return unless desired["name"] == "Ideas" && project.fetch("item_count").zero?

        project.fetch("views", []).find { |view| view["name"] == "View 1" }
      end

      def create_view(project, desired)
        body = Payloads.rest_view(project, desired).merge("name" => desired.fetch("name"), "layout" => "table")
        @client.post("orgs/#{organization}/projectsV2/#{project.fetch('number')}/views", body)
      end

      def update_view(project, current, desired)
        input = Payloads.graphql_view(project, desired).merge(
          "viewId" => current.fetch("id"), "name" => desired.fetch("name"), "layout" => "TABLE_LAYOUT"
        )
        @client.graphql(Mutations::UPDATE_VIEW, "input" => input)
      end

      def project_state
        @state.resource("github:project", refresh: true) || raise(ValidationError, "Project is missing")
      end

      def verify_precondition!(operation, current)
        expected = operation.attributes["expected_fingerprint"]
        return if current.nil? && expected.nil?
        return if expected.nil? && temporary_project?(operation, current)
        return if expected.nil? && default_status?(operation, current)
        return if current && State.fingerprint(current) == expected

        raise ConflictError, "#{operation.target} changed after planning"
      end

      def temporary_project?(operation, current)
        operation.target == "github:project" && current &&
          current["title"] == temporary_title(operation.attributes.fetch("desired"))
      end

      def default_status?(operation, current)
        operation.target == "github:field:Status" && current["type"] == "single_select" &&
          current.fetch("options", []).map { |option| option["name"] } == DEFAULT_STATUS_OPTIONS &&
          project_state.fetch("item_count").zero?
      end

      def desired?(current, operation)
        current && State.fingerprint(current) == State.fingerprint(operation.attributes.fetch("desired"))
      end

      def temporary_title(desired) = "#{desired.fetch('title')} [#{desired.fetch('short_description')}]"

      def validate_kind!(operation)
        return if Operation::GITHUB_KINDS.include?(operation.kind)

        raise ValidationError, "unsupported GitHub operation: #{operation.kind}"
      end

      def organization = @github.fetch("organization")
      def repository_name = "#{organization}/#{@github.fetch('repository')}"
      def snapshot = @state.snapshot
    end
  end
end
