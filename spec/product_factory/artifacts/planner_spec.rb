# frozen_string_literal: true

RSpec.describe ProductFactory::Artifacts::Planner do
  subject(:result) { plan(snapshot:, installed_hashes:, adoptions:, operation_summaries:, failures:) }

  let(:snapshot) { { "revision" => "REV-1", "documents" => {}, "legacy_owned_documents" => [] } }
  let(:installed_hashes) { {} }
  let(:adoptions) { [] }
  let(:operation_summaries) { ["created GitHub Project"] }
  let(:failures) { [] }

  it "plans all seven marked factory documents" do
    operation = result.fetch(:operations).fetch(0)

    expect(operation).to have_attributes(
      kind: ProductFactory::Operation::SYNC_ARTIFACTS,
      target: "artifacts:documents"
    )
    expect(operation.attributes.fetch("documents").keys).to contain_exactly(
      "index", "setup-log", "ideas/index", "epics/index", "tickets/index",
      "research/index", "factory-runs/index"
    )
    expect(operation.attributes.fetch("documents").values)
      .to all(include("<!-- product-factory:v1:artifact:"))
    expect(operation.attributes.fetch("expected_hashes").values).to all(be_nil)
  end

  it "reports a foreign same-name document with an exact adoption command" do
    snapshot.fetch("documents")["index"] = "# Human index\n"

    expect(result.fetch(:conflicts)).to include(
      "resource" => "artifact:index",
      "reason" => "name collision",
      "adopt_with" => "product-factory setup --adopt artifact:index"
    )
  end

  it "adopts only the explicitly named document" do
    snapshot.fetch("documents")["index"] = "# Human index\n"
    snapshot.fetch("documents")["ideas/index"] = "# Human ideas\n"
    adoptions << "artifact:index"

    expect(result.fetch(:operations).fetch(0).attributes.fetch("documents")).to have_key("index")
    expect(result.fetch(:conflicts)).to contain_exactly(include("resource" => "artifact:ideas/index"))
  end

  it "updates a generic legacy-owned document" do
    snapshot.fetch("documents")["ideas/index"] = "<!-- product-factory:v1:wiki:Ideas -->\n# Old\n"
    snapshot.fetch("legacy_owned_documents") << "ideas/index"

    expect(result.fetch(:operations).fetch(0).attributes.fetch("documents")).to have_key("ideas/index")
    expect(result.fetch(:conflicts)).to be_empty
  end

  it "preserves remote drift" do
    desired = initial_documents
    changed_ideas = "<!-- product-factory:v1:artifact:ideas/index -->\n# Changed\n"
    snapshot["documents"] = desired.merge("ideas/index" => changed_ideas)
    installed_hashes.merge!(hashes(desired))
    operation_summaries.clear

    expect(result.fetch(:conflicts))
      .to include(include("resource" => "artifact:ideas/index", "reason" => "remote drift"))
  end

  it "reports concurrent document changes" do
    desired = initial_documents
    remote_ideas = "<!-- product-factory:v1:artifact:ideas/index -->\n# Remote\n"
    snapshot["documents"] = desired.merge("ideas/index" => remote_ideas)
    installed_hashes.merge!(hashes(desired).merge("ideas/index" => Digest::SHA256.hexdigest("older")))
    operation_summaries.clear

    expect(result.fetch(:conflicts))
      .to include(include("resource" => "artifact:ideas/index", "reason" => "concurrent change"))
  end

  it "publishes previously unrecorded structured failures with the adapter name" do
    snapshot["documents"] = initial_documents
    installed_hashes.merge!(hashes(snapshot.fetch("documents")))
    operation_summaries.clear
    failures << {
      "operation_id" => "OP-1", "responsible_component" => "github", "root_cause" => "denied",
      "recovery_action" => "grant access"
    }

    log = result.fetch(:operations).fetch(0).attributes.dig("documents", "setup-log")
    expect(log).to include("OP-1", "github", "denied", "grant access", "Storage: repository")
  end

  it "is a pure no-op when desired documents and log are unchanged" do
    snapshot["documents"] = initial_documents
    installed_hashes.merge!(hashes(snapshot.fetch("documents")))
    operation_summaries.clear

    expect(result).to eq(operations: [], conflicts: [])
  end

  private

  def plan(**arguments)
    described_class.call(
      schema:,
      run_id: "RUN-1",
      recorded_at: "2026-09-05T00:00:00Z",
      adapter: "repository",
      **arguments
    )
  end

  def schema
    @schema ||= ProductFactory::Setup::Schema.call(
      bytes: ProductFactory::Distribution.new(FileHelpers::FACTORY_ROOT).provisioning_schema_bytes
    )
  end

  def initial_documents
    @initial_documents ||= plan(
      snapshot: { "revision" => "REV-0", "documents" => {}, "legacy_owned_documents" => [] },
      installed_hashes: {},
      adoptions: [],
      operation_summaries: ["initial setup"],
      failures: []
    ).fetch(:operations).fetch(0).attributes.fetch("documents")
  end

  def hashes(documents)
    documents.to_h { |name, content| [name, Digest::SHA256.hexdigest(content)] }
  end
end
