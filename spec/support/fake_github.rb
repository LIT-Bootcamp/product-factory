# frozen_string_literal: true

class FakeGitHub
  attr_reader :project

  def initialize(fail_once_after: nil)
    @issue_types = []
    @project = nil
    @fail_once_after = fail_once_after
  end

  def get(endpoint)
    owner, repository = endpoint.delete_prefix("repos/").split("/", 2)
    { "id" => 1, "name" => repository, "full_name" => "#{owner}/#{repository}" }
  end

  def snapshot
    {
      "actor" => "factory-test", "organization" => { "id" => "O_1", "login" => "LIT-Bootcamp", "role" => "admin" },
      "repository" => { "id" => "R_1", "name" => "bootcamper", "name_with_owner" => "LIT-Bootcamp/bootcamper" },
      "issue_types" => @issue_types, "projects" => [@project].compact
    }
  end

  def apply(operation)
    return true if matches?(operation)

    desired = operation.attributes.fetch("desired")
    case operation.kind
    when ProductFactory::Operation::ENSURE_ISSUE_TYPE then add_issue_type(desired)
    when ProductFactory::Operation::ENSURE_PROJECT then add_project(desired)
    when ProductFactory::Operation::ENSURE_PROJECT_FIELD then add_child("fields", desired)
    when ProductFactory::Operation::ENSURE_PROJECT_VIEW then add_child("views", desired)
    end
    fail_once!(operation.kind)
    true
  end

  def resource(target, refresh: false) # rubocop:disable Lint/UnusedMethodArgument
    key = target.delete_prefix("github:")
    return @project if key == "project"

    collection, name = key.split(":", 2)
    resources(collection).find { |resource| resource["name"] == name }
  end

  def matches?(operation)
    current = resource(operation.target)
    current && fingerprint(current) == fingerprint(operation.attributes.fetch("desired"))
  end

  def resource_ids
    resources_by_key.transform_values { |resource| resource["id"] }
  end

  def resource_hashes
    resources_by_key.transform_values { |resource| fingerprint(resource) }
  end

  def issue_type_names = @issue_types.map { |item| item.fetch("name") }
  def view_names = @project.to_h.fetch("views", []).map { |item| item.fetch("name") }

  private

  def add_issue_type(desired)
    @issue_types.reject! { |item| item["name"] == desired["name"] }
    @issue_types << desired.merge("id" => "IT_#{@issue_types.length + 1}")
  end

  def add_project(desired)
    children = @project ? @project.slice("fields", "views") : default_project_children
    @project = desired.merge(
      "id" => "P_1", "number" => 1, "item_count" => 0, "closed" => false, **children
    )
  end

  def add_child(collection, desired)
    items = @project.fetch(collection)
    items.reject! { |item| item["name"] == desired["name"] }
    items.reject! { |item| collection == "views" && desired["name"] == "Ideas" && item["name"] == "View 1" }
    items << desired.merge("id" => "#{collection}_#{items.length + 1}", "node_id" => "N_#{items.length + 1}")
  end

  def default_project_children
    {
      "fields" => [{
        "id" => "fields_1", "node_id" => "STATUS", "name" => "Status", "type" => "single_select",
        "options" => ["Todo", "In Progress", "Done"].map { |name| { "id" => name, "name" => name } }
      }],
      "views" => [{ "id" => "views_1", "node_id" => "VIEW_1", "name" => "View 1" }]
    }
  end

  def resources(collection)
    return @issue_types if collection == "issue-type"
    return [] unless @project

    @project.fetch(collection == "field" ? "fields" : "views")
  end

  def resources_by_key
    values = @issue_types.to_h { |item| ["issue-type:#{item.fetch('name')}", item] }
    values["project"] = @project if @project
    @project.to_h.fetch("fields", []).each { |item| values["field:#{item.fetch('name')}"] = item }
    @project.to_h.fetch("views", []).each { |item| values["view:#{item.fetch('name')}"] = item }
    values
  end

  def fail_once!(kind)
    return unless @fail_once_after == kind

    @fail_once_after = nil
    raise ProductFactory::ExternalFailure.new(
      failed_rule: "fake_interruption", responsible_component: "github",
      root_cause: "simulated interruption", impact: "operation completion was not journaled",
      recovery_action: "rerun product-factory setup"
    )
  end

  def fingerprint(resource) = ProductFactory::GitHub::State.fingerprint(resource)
end
