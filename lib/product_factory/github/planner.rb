# frozen_string_literal: true

module ProductFactory
  module GitHub
    class Planner < Service
      KINDS = {
        "issue-type" => Operation::ENSURE_ISSUE_TYPE,
        "project" => Operation::ENSURE_PROJECT,
        "field" => Operation::ENSURE_PROJECT_FIELD,
        "view" => Operation::ENSURE_PROJECT_VIEW
      }.freeze

      def initialize(config:, schema:, state:, installed_hashes:, adoptions:)
        super()
        @github = config.github
        @schema = schema
        @snapshot = state.snapshot
        @installed_hashes = installed_hashes
        @adoptions = adoptions
        @operations = []
        @conflicts = []
      end

      def call
        plan_issue_types
        current_project = find_project
        project_owned = plan_project(current_project)
        plan_project_children(current_project) if project_owned
        { operations: @operations, conflicts: @conflicts }
      end

      private

      def plan_issue_types
        @schema.fetch("issue_types").each do |name, attributes|
          current = @snapshot.fetch("issue_types").find { |item| item["name"] == name }
          desired = attributes.merge("name" => name, "is_enabled" => true)
          owned = current&.dig("description")&.include?(issue_marker(name))
          compare("issue-type:#{name}", desired, current, owned:)
        end
      end

      def plan_project(current)
        owned = current&.dig("short_description")&.include?(project_marker)
        compare("project", desired_project, current, owned:)
        current.nil? || owned || adopted?("project")
      end

      def plan_project_children(current)
        @schema.fetch("fields").each do |name, attributes|
          desired = attributes.merge("name" => name, "options" => attributes.fetch("options", []))
          found = current&.fetch("fields", [])&.find { |field| field["name"] == name }
          compare("field:#{name}", desired, found, owned: true, immutable_type: attributes.fetch("type"))
        end
        @schema.fetch("views").each do |name, attributes|
          filter = %(type:"#{attributes.fetch('issue_type')}")
          desired = attributes.except("issue_type").merge("name" => name, "layout" => "TABLE", "filter" => filter)
          found = current&.fetch("views", [])&.find { |view| view["name"] == name }
          compare("view:#{name}", desired, found, owned: true)
        end
      end

      def compare(key, desired, current, owned:, immutable_type: nil)
        return add_operation(key, desired, nil, "missing") unless current
        return if fingerprint(current) == fingerprint(desired)
        return add_conflict(key, "incompatible type") if immutable_type && current["type"] != immutable_type
        return add_conflict(key, "name collision", adopt: true) unless owned || adopted?(key)
        return add_operation(key, desired, current, "adopted") if adopted?(key) && !owned

        compare_versions(key, desired, current)
      end

      def compare_versions(key, desired, current)
        installed = @installed_hashes[key]
        current_hash = fingerprint(current)
        desired_hash = fingerprint(desired)
        return add_operation(key, desired, current, "untracked resource") unless installed
        return add_operation(key, desired, current, "desired changed") if current_hash == installed
        return add_conflict(key, "remote drift") if desired_hash == installed

        add_conflict(key, "concurrent change")
      end

      def add_operation(key, desired, current, reason)
        @operations << Operation.new(
          kind: KINDS.fetch(key.split(":", 2).first),
          target: "github:#{key}",
          attributes: {
            "desired" => desired,
            "expected_fingerprint" => current && fingerprint(current),
            "reason" => reason,
            "adopt" => adopted?(key)
          }
        )
      end

      def add_conflict(key, reason, adopt: false)
        conflict = { "resource" => key, "reason" => reason }
        conflict["adopt_with"] = "product-factory setup --adopt #{key}" if adopt
        @conflicts << conflict
      end

      def find_project
        projects = @snapshot.fetch("projects")
        projects.find { |item| item["short_description"].to_s.include?(project_marker) } ||
          projects.find { |item| item["title"] == @github.fetch("project_title") }
      end

      def desired_project
        @schema.fetch("project").merge(
          "title" => @github.fetch("project_title"),
          "short_description" => project_marker,
          "repositories" => ["#{organization}/#{repository}"]
        )
      end

      def project_marker = format(@schema.dig("markers", "project"), organization:, repository:)
      def issue_marker(name) = format(@schema.dig("markers", "issue_type"), name:)
      def organization = @github.fetch("organization")
      def repository = @github.fetch("repository")
      def adopted?(key) = @adoptions.include?(key)
      def fingerprint(resource) = State.fingerprint(resource)
    end
  end
end
