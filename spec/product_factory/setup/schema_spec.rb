# frozen_string_literal: true

RSpec.describe ProductFactory::Setup::Schema do
  subject(:schema) do
    described_class.call(bytes: ProductFactory::Distribution.new(FileHelpers::FACTORY_ROOT).provisioning_schema_bytes)
  end

  it "loads the exact private v1 resource model" do
    open_brace = "{"

    expect(schema.dig("project", "public")).to be(false)
    expect(schema.fetch("issue_types").keys).to eq(%w[Idea Epic Ticket])
    expect(schema.dig("fields", "Priority", "options").map { |option| option.fetch("name") })
      .to eq((1..10).map { |number| "P#{number}" })
    expect(schema.fetch("views").keys).to eq(%w[Ideas Epics Tickets])
    expect(schema.dig("artifacts", "documents")).to eq(
      %w[index setup-log ideas/index epics/index tickets/index research/index factory-runs/index]
    )
    expect(schema.dig("markers", "artifact"))
      .to eq("<!-- product-factory:v1:artifact:%#{open_brace}document} -->")
    expect(schema.dig("markers", "wiki"))
      .to eq("<!-- product-factory:v1:wiki:%#{open_brace}page} -->")
    expect(schema.dig("wiki", "pages")).to eq(
      %w[_Sidebar Setup-Log Ideas Epics Tickets Research Factory-Runs]
    )
    expect(schema).to be_frozen
  end

  it "rejects an unsafe or incomplete manifest" do
    bytes = YAML.dump("schema_version" => 1, "project" => { "public" => true })

    expect { described_class.call(bytes:) }
      .to raise_error(ProductFactory::ValidationError, "invalid provisioning schema")
  end
end
