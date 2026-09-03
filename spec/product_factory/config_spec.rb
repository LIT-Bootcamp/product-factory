RSpec.describe ProductFactory::Config do
  it "loads v1 config and applies fixed defaults" do
    in_tmp_repo do |root|
      write(root, ".product-factory/config.yml", <<~YAML)
        schema_version: 1
        product:
          name: Bootcamper
          context_page: Product-Context
          inventory_page: Product-Inventory
          max_active_ideas: 10
        github:
          organization: LIT-Bootcamp
          repository: bootcamper
          project_title: Bootcamper Product Factory
        research: { freshness_days: 30 }
        workflow:
          clarification_rounds: 3
          claim_lease_minutes: 60
          max_ticket_human_hours: 16
        agents: {}
        qa: { credential_env: {} }
        knowledge: { paths: [AGENTS.md] }
      YAML

      config = described_class.load(root)

      expect(config.schema_version).to eq(1)
      expect(config.product.fetch("name")).to eq("Bootcamper")
      expect(config.workflow.fetch("max_ticket_human_hours")).to eq(16)
    end
  end

  it "rejects missing required values" do
    in_tmp_repo do |root|
      write(root, ".product-factory/config.yml", "schema_version: 1\n")

      expect { described_class.load(root) }
        .to raise_error(ProductFactory::ValidationError, /product\.name is required/)
    end
  end

  it "rejects Ruby objects through safe YAML loading" do
    in_tmp_repo do |root|
      write(root, ".product-factory/config.yml", "--- !ruby/object:Object {}\n")

      expect { described_class.load(root) }
        .to raise_error(ProductFactory::ValidationError)
    end
  end
end
