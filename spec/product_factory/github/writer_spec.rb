# frozen_string_literal: true

RSpec.describe ProductFactory::GitHub::Writer do
  subject(:writer) { described_class.new(config:, client:, state:) }

  let(:config) { product_config }
  let(:client) { instance_double(ProductFactory::GitHub::Client) }
  let(:state) { instance_double(ProductFactory::GitHub::State, snapshot:) }
  let(:snapshot) do
    {
      "organization" => { "id" => "O_1" },
      "repository" => { "id" => "R_1", "name_with_owner" => "LIT-Bootcamp/bootcamper" }
    }
  end

  before { allow(state).to receive(:matches?).and_return(true) }

  it "creates and verifies an Issue Type" do
    operation = build_operation(
      ProductFactory::Operation::ENSURE_ISSUE_TYPE,
      "github:issue-type:Idea",
      issue_type
    )
    allow(state).to receive(:resource).with(operation.target, refresh: true).and_return(nil)
    allow(client).to receive(:post).and_return("id" => 410)

    expect(writer.apply(operation)).to be(true)
    expect(client).to have_received(:post).with(
      "orgs/LIT-Bootcamp/issue-types",
      "name" => "Idea",
      "description" => issue_type.fetch("description"),
      "color" => "purple",
      "is_enabled" => true
    )
    expect(state).to have_received(:matches?).with(operation)
  end

  it "updates an explicitly adopted Issue Type" do
    current = issue_type.merge("id" => 410, "description" => "foreign")
    operation = build_operation(
      ProductFactory::Operation::ENSURE_ISSUE_TYPE,
      "github:issue-type:Idea",
      issue_type,
      current:,
      adopt: true
    )
    allow(state).to receive(:resource).with(operation.target, refresh: true).and_return(current)
    allow(client).to receive(:put).and_return("id" => 410)

    writer.apply(operation)

    expect(client).to have_received(:put).with(
      "orgs/LIT-Bootcamp/issue-types/410",
      hash_including("description" => issue_type.fetch("description"))
    )
  end

  it "creates a temporarily marked private Project and finalizes it" do
    operation = build_operation(ProductFactory::Operation::ENSURE_PROJECT, "github:project", project)
    created = project.merge("id" => "P_2", "title" => temporary_title, "short_description" => nil)
    allow(state).to receive(:resource).with(operation.target, refresh: true).and_return(nil, created)
    allow(client).to receive(:graphql).and_return("data" => {})

    writer.apply(operation)

    expect(client).to have_received(:graphql).with(
      a_string_including("createProjectV2"),
      "input" => {
        "ownerId" => "O_1", "repositoryId" => "R_1", "title" => temporary_title,
        "clientMutationId" => operation.id
      }
    )
    expect(client).to have_received(:graphql).with(
      a_string_including("updateProjectV2"),
      "input" => hash_including(
        "projectId" => "P_2", "title" => project.fetch("title"), "public" => false,
        "shortDescription" => project.fetch("short_description")
      )
    )
  end

  it "finalizes a Project left in the temporary-title crash window" do
    temporary = project.merge("id" => "P_2", "title" => temporary_title, "short_description" => nil)
    operation = build_operation(ProductFactory::Operation::ENSURE_PROJECT, "github:project", project)
    allow(state).to receive(:resource).with(operation.target, refresh: true).and_return(temporary)
    allow(client).to receive(:graphql).and_return("data" => {})

    writer.apply(operation)

    expect(client).not_to have_received(:graphql).with(a_string_including("createProjectV2"), anything)
    expect(client).to have_received(:graphql).with(a_string_including("updateProjectV2"), anything)
  end

  it "links an existing adopted Project to the repository" do
    current = project.merge("id" => "P_2", "repositories" => [])
    operation = build_operation(ProductFactory::Operation::ENSURE_PROJECT, "github:project", project, current:,
                                                                                                      adopt: true)
    allow(state).to receive(:resource).with(operation.target, refresh: true).and_return(current)
    allow(client).to receive(:graphql).and_return("data" => {})

    writer.apply(operation)

    expect(client).to have_received(:graphql).with(
      a_string_including("linkProjectV2ToRepository"),
      "input" => { "projectId" => "P_2", "repositoryId" => "R_1" }
    )
  end

  %w[text date number single_select].each do |type|
    it "creates a #{type} Project field" do
      options = type == "single_select" ? [{ "name" => "One", "color" => "BLUE", "description" => "First" }] : []
      desired = { "name" => "Example", "type" => type, "options" => options }
      operation = build_operation(ProductFactory::Operation::ENSURE_PROJECT_FIELD, "github:field:Example", desired)
      allow(state).to receive(:resource).with(operation.target, refresh: true).and_return(nil)
      allow(state).to receive(:resource).with("github:project", refresh: true).and_return(project_state)
      allow(client).to receive(:post).and_return("id" => 20)

      writer.apply(operation)

      expect(client).to have_received(:post).with(
        "orgs/LIT-Bootcamp/projectsV2/2/fields",
        { "name" => "Example", "data_type" => type }.tap do |payload|
          payload["single_select_options"] = options if type == "single_select"
        end
      )
    end
  end

  it "replaces the empty Project's automatic Status field" do
    current = {
      "id" => 20, "node_id" => "F_1", "name" => "Status", "type" => "single_select",
      "options" => ["Todo", "In Progress", "Done"].map { |name| { "id" => name, "name" => name } }
    }
    desired = {
      "name" => "Status", "type" => "single_select",
      "options" => [{ "name" => "Created", "color" => "GRAY", "description" => "New" }]
    }
    operation = build_operation(ProductFactory::Operation::ENSURE_PROJECT_FIELD, "github:field:Status", desired)
    allow(state).to receive(:resource).with(operation.target, refresh: true).and_return(current)
    allow(state).to receive(:resource).with("github:project", refresh: true).and_return(project_state)
    allow(client).to receive(:graphql).and_return("data" => {})

    expect(writer.apply(operation)).to be(true)
    expect(client).to have_received(:graphql).with(
      a_string_including("updateProjectV2Field"),
      "input" => {
        "fieldId" => "F_1", "name" => "Status",
        "singleSelectOptions" => [{ "name" => "Created", "color" => "GRAY", "description" => "New" }]
      }
    )
  end

  it "preserves matching option IDs while updating a select field" do
    current = {
      "id" => 20, "node_id" => "F_1", "name" => "Priority", "type" => "single_select",
      "options" => [{ "id" => "O_1", "name" => "P1", "color" => "RED", "description" => "old" }]
    }
    desired = current.except("id", "node_id").merge(
      "options" => [{ "name" => "P1", "color" => "RED", "description" => "Highest" }]
    )
    operation = build_operation(ProductFactory::Operation::ENSURE_PROJECT_FIELD, "github:field:Priority", desired,
                                current:)
    allow(state).to receive(:resource).with(operation.target, refresh: true).and_return(current)
    allow(state).to receive(:resource).with("github:project", refresh: true).and_return(project_state)
    allow(client).to receive(:graphql).and_return("data" => {})

    writer.apply(operation)

    expect(client).to have_received(:graphql).with(
      a_string_including("updateProjectV2Field"),
      "input" => {
        "fieldId" => "F_1", "name" => "Priority",
        "singleSelectOptions" => [hash_including("id" => "O_1", "name" => "P1", "description" => "Highest")]
      }
    )
  end

  it "refuses to remove select options from a non-empty Project" do
    current = {
      "id" => 20, "node_id" => "F_1", "name" => "Status", "type" => "single_select",
      "options" => [{ "id" => "O_1", "name" => "Todo" }]
    }
    desired = current.except("id", "node_id").merge("options" => [])
    operation = build_operation(ProductFactory::Operation::ENSURE_PROJECT_FIELD, "github:field:Status", desired,
                                current:)
    allow(state).to receive(:resource).with(operation.target, refresh: true).and_return(current)
    allow(state).to receive(:resource).with("github:project", refresh: true)
                                      .and_return(project_state.merge("item_count" => 1))

    expect { writer.apply(operation) }
      .to raise_error(ProductFactory::ConflictError, "cannot remove Project field options while items exist")
  end

  it "reuses the empty default view for Ideas and resolves field IDs" do
    operation = build_operation(ProductFactory::Operation::ENSURE_PROJECT_VIEW, "github:view:Ideas", ideas_view)
    default = { "id" => "V_1", "number" => 1, "name" => "View 1" }
    allow(state).to receive(:resource).with(operation.target, refresh: true).and_return(nil)
    allow(state).to receive(:resource).with("github:project", refresh: true)
                                      .and_return(project_state.merge("views" => [default], "fields" => visible_fields))
    allow(client).to receive(:graphql).and_return("data" => {})

    writer.apply(operation)

    expect(client).to have_received(:graphql).with(
      a_string_including("updateProjectV2View"),
      "input" => {
        "viewId" => "V_1", "name" => "Ideas", "layout" => "TABLE_LAYOUT",
        "filter" => "type:\"Idea\"", "configuration" => { "visibleFieldIds" => %w[TITLE STATUS] }
      }
    )
  end

  it "creates non-default views through the REST endpoint" do
    desired = ideas_view.merge("name" => "Epics", "filter" => "type:\"Epic\"")
    operation = build_operation(ProductFactory::Operation::ENSURE_PROJECT_VIEW, "github:view:Epics", desired)
    allow(state).to receive(:resource).with(operation.target, refresh: true).and_return(nil)
    allow(state).to receive(:resource).with("github:project", refresh: true)
                                      .and_return(project_state.merge("fields" => visible_fields))
    allow(client).to receive(:post).and_return("id" => "V_2")

    writer.apply(operation)

    expect(client).to have_received(:post).with(
      "orgs/LIT-Bootcamp/projectsV2/2/views",
      {
        "name" => "Epics", "layout" => "table", "filter" => "type:\"Epic\"",
        "visible_fields" => [1, 2]
      }
    )
  end

  it "rejects a stale expected fingerprint before mutation" do
    current = issue_type.merge("id" => 410, "description" => "changed")
    operation = ProductFactory::Operation.new(
      kind: ProductFactory::Operation::ENSURE_ISSUE_TYPE,
      target: "github:issue-type:Idea",
      attributes: { "desired" => issue_type, "expected_fingerprint" => "stale", "reason" => "update" }
    )
    allow(state).to receive(:resource).with(operation.target, refresh: true).and_return(current)

    expect { writer.apply(operation) }
      .to raise_error(ProductFactory::ConflictError, "github:issue-type:Idea changed after planning")
  end

  private

  def build_operation(kind, target, desired, current: nil, adopt: false)
    ProductFactory::Operation.new(
      kind:,
      target:,
      attributes: {
        "desired" => desired,
        "expected_fingerprint" => current && ProductFactory::GitHub::State.fingerprint(current),
        "reason" => current ? "update" : "missing",
        "adopt" => adopt
      }
    )
  end

  def product_config
    data = YAML.safe_load(ProductFactory::Distribution.new(FileHelpers::FACTORY_ROOT).config_bytes, aliases: false)
    data["github"] = {
      "organization" => "LIT-Bootcamp",
      "repository" => "bootcamper",
      "project_title" => "Bootcamper Product Factory"
    }
    ProductFactory::Config.new(data)
  end

  def issue_type
    {
      "name" => "Idea", "description" => "Idea product-factory:v1:issue-type:Idea",
      "color" => "purple", "is_enabled" => true
    }
  end

  def project
    {
      "title" => "Bootcamper Product Factory", "public" => false,
      "short_description" => "product-factory:v1:project:LIT-Bootcamp/bootcamper",
      "repositories" => ["LIT-Bootcamp/bootcamper"]
    }
  end

  def temporary_title = "#{project.fetch('title')} [#{project.fetch('short_description')}]"

  def project_state
    project.merge("id" => "P_2", "number" => 2, "item_count" => 0, "fields" => [], "views" => [])
  end

  def visible_fields
    [
      { "id" => 1, "node_id" => "TITLE", "name" => "Title" },
      { "id" => 2, "node_id" => "STATUS", "name" => "Status" }
    ]
  end

  def ideas_view
    {
      "name" => "Ideas", "layout" => "TABLE", "filter" => "type:\"Idea\"",
      "visible_fields" => %w[Title Status]
    }
  end
end
