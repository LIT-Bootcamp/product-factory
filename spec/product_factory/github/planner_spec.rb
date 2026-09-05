# frozen_string_literal: true

RSpec.describe ProductFactory::GitHub::Planner do
  subject(:result) { plan(snapshot:, installed_hashes:, adoptions:) }

  let(:snapshot) { empty_snapshot }
  let(:installed_hashes) { {} }
  let(:adoptions) { [] }

  it "plans every missing resource in dependency order" do
    operations = result.fetch(:operations)

    expect(operations.map { |operation| [operation.kind, operation.target] }).to start_with(
      [ProductFactory::Operation::ENSURE_ISSUE_TYPE, "github:issue-type:Idea"],
      [ProductFactory::Operation::ENSURE_ISSUE_TYPE, "github:issue-type:Epic"],
      [ProductFactory::Operation::ENSURE_ISSUE_TYPE, "github:issue-type:Ticket"],
      [ProductFactory::Operation::ENSURE_PROJECT, "github:project"]
    )
    expect(operations.map(&:kind).tally).to eq(
      ProductFactory::Operation::ENSURE_ISSUE_TYPE => 3,
      ProductFactory::Operation::ENSURE_PROJECT => 1,
      ProductFactory::Operation::ENSURE_PROJECT_FIELD => schema.fetch("fields").size,
      ProductFactory::Operation::ENSURE_PROJECT_VIEW => 3
    )
  end

  it "does nothing when every marked resource has the desired shape" do
    snapshot.replace(desired_snapshot)

    expect(result).to eq(operations: [], conflicts: [])
  end

  it "reports exact adoption commands for same-name foreign resources" do
    snapshot["issue_types"] << desired_issue_type("Idea").merge("description" => "foreign")
    snapshot["projects"] << desired_project.merge("short_description" => "foreign")

    expect(result.fetch(:conflicts)).to include(
      include("resource" => "issue-type:Idea", "adopt_with" => "product-factory setup --adopt issue-type:Idea"),
      include("resource" => "project", "adopt_with" => "product-factory setup --adopt project")
    )
  end

  it "adopts only the explicitly named project" do
    snapshot["issue_types"] << desired_issue_type("Idea").merge("description" => "foreign")
    snapshot["projects"] << desired_project.merge("short_description" => "foreign")
    adoptions << "project"

    expect(result.fetch(:operations)).to include(have_attributes(kind: ProductFactory::Operation::ENSURE_PROJECT))
    expect(result.fetch(:conflicts)).to contain_exactly(include("resource" => "issue-type:Idea"))
  end

  it "never adopts a field with an incompatible type" do
    snapshot.replace(desired_snapshot)
    snapshot.dig("projects", 0, "fields", 0)["type"] = "text"
    adoptions << "field:Status"

    expect(result.fetch(:conflicts)).to include(include("resource" => "field:Status", "reason" => "incompatible type"))
    expect(result.fetch(:operations).map(&:target)).not_to include("github:field:Status")
  end

  it "updates when remote still equals the installed version" do
    snapshot.replace(desired_snapshot)
    priority = snapshot.dig("projects", 0, "fields").find { |field| field["name"] == "Priority" }
    priority["options"] = priority.fetch("options").first(1)
    installed_hashes["field:Priority"] = fingerprint(priority)

    expect(result.fetch(:operations)).to include(
      have_attributes(target: "github:field:Priority", attributes: include("reason" => "desired changed"))
    )
  end

  it "preserves remote drift when desired still equals installed" do
    snapshot.replace(desired_snapshot)
    installed_hashes["field:Priority"] = fingerprint(desired_field("Priority"))
    snapshot.dig("projects", 0, "fields").find { |field| field["name"] == "Priority" }["options"] = []

    expect(result.fetch(:conflicts)).to include(include("resource" => "field:Priority", "reason" => "remote drift"))
  end

  it "reports concurrent changes when remote and desired both changed" do
    snapshot.replace(desired_snapshot)
    priority = snapshot.dig("projects", 0, "fields").find { |field| field["name"] == "Priority" }
    installed_hashes["field:Priority"] = fingerprint(priority.merge("options" => priority.fetch("options").first(2)))
    priority["options"] = []

    expect(result.fetch(:conflicts)).to include(
      include("resource" => "field:Priority", "reason" => "concurrent change")
    )
  end

  it "ignores unrelated projects" do
    snapshot["projects"] << desired_project.merge(
      "id" => "P_1",
      "title" => "Bootcamper Product Delivery",
      "short_description" => "unrelated"
    )

    expect(result.fetch(:operations).map(&:target)).to include("github:project")
    expect(result.to_s).not_to include("Bootcamper Product Delivery")
  end

  private

  def plan(snapshot:, installed_hashes:, adoptions:)
    state = instance_double(ProductFactory::GitHub::State, snapshot:)
    described_class.call(config:, schema:, state:, installed_hashes:, adoptions:)
  end

  def config
    @config ||= begin
      data = YAML.safe_load(ProductFactory::Distribution.new(FileHelpers::FACTORY_ROOT).config_bytes, aliases: false)
      data["product"]["name"] = "Bootcamper"
      data["github"] = {
        "organization" => "LIT-Bootcamp",
        "repository" => "bootcamper",
        "project_title" => "Bootcamper Product Factory"
      }
      ProductFactory::Config.new(data)
    end
  end

  def schema
    @schema ||= ProductFactory::Setup::Schema.call(
      bytes: ProductFactory::Distribution.new(FileHelpers::FACTORY_ROOT).provisioning_schema_bytes
    )
  end

  def empty_snapshot
    {
      "actor" => "denys",
      "organization" => { "id" => "O_1", "login" => "LIT-Bootcamp", "role" => "admin" },
      "repository" => { "id" => "R_1", "name" => "bootcamper", "name_with_owner" => "LIT-Bootcamp/bootcamper" },
      "issue_types" => [],
      "projects" => []
    }
  end

  def desired_snapshot
    empty_snapshot.merge(
      "issue_types" => schema.fetch("issue_types").keys.map { |name| desired_issue_type(name) },
      "projects" => [desired_project.merge(
        "fields" => schema.fetch("fields").keys.map { |name| desired_field(name) },
        "views" => schema.fetch("views").keys.map { |name| desired_view(name) }
      )]
    )
  end

  def desired_issue_type(name)
    schema.dig("issue_types", name).merge("id" => name, "name" => name, "is_enabled" => true)
  end

  def desired_project
    {
      "id" => "P_2",
      "number" => 2,
      "title" => "Bootcamper Product Factory",
      "public" => false,
      "closed" => false,
      "short_description" => "product-factory:v1:project:LIT-Bootcamp/bootcamper",
      "repositories" => ["LIT-Bootcamp/bootcamper"],
      "item_count" => 0,
      "fields" => [],
      "views" => []
    }
  end

  def desired_field(name)
    schema.dig("fields", name).merge("id" => name, "node_id" => name, "name" => name).tap do |field|
      field["options"] = field.fetch("options", []).map.with_index do |option, index|
        option.merge("id" => "#{name}-#{index}")
      end
    end
  end

  def desired_view(name)
    schema.dig("views", name).except("issue_type").merge(
      "id" => name,
      "number" => 1,
      "name" => name,
      "layout" => "TABLE",
      "filter" => "type:\"#{schema.dig('views', name, 'issue_type')}\""
    )
  end

  def fingerprint(resource)
    ProductFactory::GitHub::State.fingerprint(resource)
  end
end
