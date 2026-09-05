# frozen_string_literal: true

RSpec.describe ProductFactory::Setup::Schema do
  subject(:schema) do
    described_class.call(bytes: ProductFactory::Distribution.new(FileHelpers::FACTORY_ROOT).provisioning_schema_bytes)
  end

  it "loads the exact private v1 resource model" do
    expect(schema.dig("project", "public")).to be(false)
    expect(schema.fetch("issue_types").keys).to eq(%w[Idea Epic Ticket])
    expect(schema.dig("fields", "Priority", "options").map { |option| option.fetch("name") })
      .to eq((1..10).map { |number| "P#{number}" })
    expect(schema.fetch("views").keys).to eq(%w[Ideas Epics Tickets])
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
