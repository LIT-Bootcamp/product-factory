# frozen_string_literal: true

RSpec.describe ProductFactory::Artifacts do
  let(:shell) { instance_double(ProductFactory::StreamShell) }
  let(:target_root) { "/application" }

  it "builds the repository adapter selected by configuration" do
    config = instance_double(
      ProductFactory::Config,
      artifacts: { "adapter" => "repository", "root" => "product" }
    )
    adapter = instance_double(ProductFactory::Artifacts::Repository)
    allow(ProductFactory::Artifacts::Repository).to receive(:new).and_return(adapter)

    expect(described_class.build(config:, target_root:, shell:)).to be(adapter)
    expect(ProductFactory::Artifacts::Repository).to have_received(:new).with(target_root:, root: "product")
  end

  it "builds the Wiki adapter selected by legacy configuration" do
    config = instance_double(
      ProductFactory::Config,
      artifacts: { "adapter" => "wiki" },
      github: { "organization" => "LIT-Bootcamp", "repository" => "bootcamper" }
    )
    adapter = instance_double(ProductFactory::Artifacts::Wiki)
    allow(ProductFactory::Artifacts::Wiki).to receive(:new).and_return(adapter)

    expect(described_class.build(config:, target_root:, shell:)).to be(adapter)
    expect(ProductFactory::Artifacts::Wiki).to have_received(:new).with(
      organization: "LIT-Bootcamp", repository: "bootcamper", shell:
    )
  end

  it "accepts only complete generic artifact operations" do
    attributes = {
      "adapter" => "repository", "expected_revision" => "REV-1",
      "expected_hashes" => ProductFactory::Artifacts::Planner::DOCUMENT_IDS.to_h { [it, nil] },
      "documents" => { "index" => "# Product Factory\n" }
    }
    operation = ProductFactory::Operation.new(
      kind: ProductFactory::Operation::SYNC_ARTIFACTS, target: "artifacts:documents", attributes:
    )
    incomplete = ProductFactory::Operation.new(
      kind: ProductFactory::Operation::SYNC_ARTIFACTS, target: "artifacts:documents",
      attributes: attributes.except("expected_hashes")
    )

    expect(described_class.valid_operation?(operation)).to be(true)
    expect(described_class.valid_operation?(incomplete)).to be(false)
  end
end
