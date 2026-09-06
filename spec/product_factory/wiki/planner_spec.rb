# frozen_string_literal: true

RSpec.describe ProductFactory::Wiki::Planner do
  subject(:result) { plan(snapshot:, installed_hashes:, adoptions:, operation_summaries:, failures:) }

  let(:snapshot) { { "head" => "HEAD-1", "pages" => { "Home.md" => "# Home\n" } } }
  let(:installed_hashes) { {} }
  let(:adoptions) { [] }
  let(:operation_summaries) { ["created GitHub Project"] }
  let(:failures) { [] }

  it "plans all seven marked factory pages without Home" do
    expect(result.fetch(:operations).size).to eq(1)
    operation = result.fetch(:operations).fetch(0)

    expect(operation).to have_attributes(
      kind: ProductFactory::Operation::SYNC_WIKI,
      target: "wiki:factory-pages"
    )
    expect(operation.attributes.fetch("pages").keys).to contain_exactly(
      "_Sidebar.md", "Setup-Log.md", "Ideas.md", "Epics.md", "Tickets.md", "Research.md", "Factory-Runs.md"
    )
    expect(operation.attributes.dig("pages", "Home.md")).to be_nil
    expect(operation.attributes.fetch("pages").values).to all(include("<!-- product-factory:v1:wiki:"))
  end

  it "reports a foreign same-name page with an exact adoption command" do
    snapshot.fetch("pages")["_Sidebar.md"] = "# Human sidebar\n"

    expect(result.fetch(:conflicts)).to include(
      "resource" => "wiki:_Sidebar",
      "reason" => "name collision",
      "adopt_with" => "product-factory setup --adopt wiki:_Sidebar"
    )
  end

  it "adopts only the explicitly named page" do
    snapshot.fetch("pages")["_Sidebar.md"] = "# Human sidebar\n"
    snapshot.fetch("pages")["Ideas.md"] = "# Human ideas\n"
    adoptions << "wiki:_Sidebar"

    expect(result.fetch(:operations).fetch(0).attributes.fetch("pages")).to have_key("_Sidebar.md")
    expect(result.fetch(:conflicts)).to contain_exactly(include("resource" => "wiki:Ideas"))
  end

  it "preserves remote drift" do
    desired = initial_pages
    snapshot["pages"] = desired.merge("Ideas.md" => "<!-- product-factory:v1:wiki:Ideas -->\n# Changed\n")
    installed_hashes.merge!(hashes(desired))
    operation_summaries.clear

    expect(result.fetch(:conflicts)).to include(include("resource" => "wiki:Ideas", "reason" => "remote drift"))
  end

  it "reports concurrent page changes" do
    desired = initial_pages
    snapshot["pages"] = desired.merge("Ideas.md" => "<!-- product-factory:v1:wiki:Ideas -->\n# Remote\n")
    installed_hashes.merge!(hashes(desired).merge("Ideas.md" => Digest::SHA256.hexdigest("older")))
    operation_summaries.clear

    expect(result.fetch(:conflicts)).to include(include("resource" => "wiki:Ideas", "reason" => "concurrent change"))
  end

  it "publishes previously unrecorded structured failures" do
    snapshot["pages"] = initial_pages
    installed_hashes.merge!(hashes(snapshot.fetch("pages")))
    operation_summaries.clear
    failures << {
      "operation_id" => "OP-1", "responsible_component" => "github", "root_cause" => "denied",
      "recovery_action" => "grant access"
    }

    log = result.fetch(:operations).fetch(0).attributes.dig("pages", "Setup-Log.md")
    expect(log).to include("OP-1", "github", "denied", "grant access")
  end

  it "is a pure no-op when desired pages and log are unchanged" do
    snapshot["pages"] = initial_pages
    installed_hashes.merge!(hashes(snapshot.fetch("pages")))
    operation_summaries.clear

    expect(result).to eq(operations: [], conflicts: [])
  end

  private

  def plan(**arguments)
    described_class.call(
      schema:,
      run_id: "RUN-1",
      recorded_at: "2026-09-05T00:00:00Z",
      **arguments
    )
  end

  def schema
    @schema ||= ProductFactory::Setup::Schema.call(
      bytes: ProductFactory::Distribution.new(FileHelpers::FACTORY_ROOT).provisioning_schema_bytes
    )
  end

  def initial_pages
    @initial_pages ||= plan(
      snapshot: { "head" => "HEAD-0", "pages" => { "Home.md" => "# Home\n" } },
      installed_hashes: {},
      adoptions: [],
      operation_summaries: ["initial setup"],
      failures: []
    ).fetch(:operations).fetch(0).attributes.fetch("pages")
  end

  def hashes(pages)
    pages.to_h { |name, content| [name, Digest::SHA256.hexdigest(content)] }
  end
end
