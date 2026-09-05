# frozen_string_literal: true

RSpec.describe ProductFactory::Journal do
  subject(:journal) { described_class.new(path:, clock: -> { Time.utc(2026, 9, 5) }) }

  let(:path) { File.join(root, "journal.jsonl") }
  let(:root) { Dir.mktmpdir("product-factory-journal") }

  after { FileUtils.remove_entry(root) }

  it "records structured operation failure accountability" do
    event = journal.append(
      event: "operation_failed",
      run_id: "RUN-1",
      operation_id: "operation-1",
      error_class: "ProductFactory::ExternalFailure",
      message: "request failed",
      failed_rule: "github_request",
      responsible_component: "github",
      root_cause: "request failed",
      impact: "resource was not verified",
      recovery_action: "rerun product-factory setup"
    )

    expect(journal.events).to contain_exactly(event)
  end

  it "rejects non-string failure details" do
    expect do
      journal.append(
        event: "operation_failed",
        run_id: "RUN-1",
        operation_id: "operation-1",
        error_class: "ProductFactory::Error",
        message: "failed",
        failed_rule: "operation_execution",
        responsible_component: nil,
        root_cause: "failed",
        impact: "not verified",
        recovery_action: "rerun product-factory setup"
      )
    end.to raise_error(ProductFactory::ValidationError, "Invalid journal event")
  end

  it "accepts a no-op completed run" do
    event = journal.append(event: "run_completed", run_id: "RUN-1", status: "no-op")

    expect(journal.events).to contain_exactly(event)
  end
end
