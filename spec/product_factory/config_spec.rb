# frozen_string_literal: true

RSpec.describe ProductFactory::Config do
  let(:valid_config) do
    {
      "schema_version" => 1,
      "product" => {
        "name" => "Bootcamper",
        "context_document" => "context",
        "inventory_document" => "inventory",
        "max_active_ideas" => 10
      },
      "artifacts" => { "adapter" => "repository", "root" => "product" },
      "github" => {
        "organization" => "LIT-Bootcamp",
        "repository" => "bootcamper",
        "project_title" => "Bootcamper Product Factory"
      },
      "research" => { "freshness_days" => 30 },
      "workflow" => {
        "clarification_rounds" => 3,
        "claim_lease_minutes" => 60,
        "max_ticket_human_hours" => 16
      },
      "agents" => {
        "ideator" => {},
        "business_analyst" => {},
        "technical_lead" => {},
        "manual_qa" => {}
      },
      "qa" => {
        "staging_url" => "https://example.test",
        "credential_env" => {}
      },
      "knowledge" => { "paths" => ["AGENTS.md"] }
    }
  end

  it "loads v1 config and applies fixed defaults" do
    in_tmp_repo do |root|
      write(root, ".product-factory/config.yml", <<~YAML)
        schema_version: 1
        product:
          name: Bootcamper
          context_document: context
          inventory_document: inventory
          max_active_ideas: 10
        artifacts: { adapter: repository, root: product }
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
      expect(config.artifacts).to eq("adapter" => "repository", "root" => "product")
      expect(config.product).to include("context_document" => "context", "inventory_document" => "inventory")
      expect(config.workflow.fetch("max_ticket_human_hours")).to eq(16)
    end
  end

  it "normalizes a legacy v1 Wiki configuration" do
    legacy = YAML.safe_load(YAML.dump(valid_config), aliases: false)
    legacy.fetch("product")["context_page"] = legacy.fetch("product").delete("context_document")
    legacy.fetch("product")["inventory_page"] = legacy.fetch("product").delete("inventory_document")
    legacy.delete("artifacts")

    config = described_class.new(legacy)

    expect(config.artifacts).to eq("adapter" => "wiki")
    expect(config.product).to include("context_document" => "context", "inventory_document" => "inventory")
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

  it "rejects a non-mapping document root" do
    in_tmp_repo do |root|
      write(root, ".product-factory/config.yml", "true\n")

      expect { described_class.load(root) }
        .to raise_error(ProductFactory::ValidationError, "configuration must be a mapping")
    end
  end

  it "rejects null required values" do
    valid_config["product"]["name"] = nil

    in_tmp_repo do |root|
      write(root, ".product-factory/config.yml", YAML.dump(valid_config))

      expect { described_class.load(root) }
        .to raise_error(ProductFactory::ValidationError, "product.name is required")
    end
  end

  [
    ["product.name", false, "a string"],
    ["product.max_active_ideas", "10", "an integer"],
    ["product.max_active_ideas", nil, "an integer"],
    ["qa.staging_url", 123, "a string or null"],
    ["knowledge.paths", ["AGENTS.md", 123], "an array of strings"]
  ].each do |path, invalid_value, expected_type|
    it "rejects invalid #{path} value #{invalid_value.inspect}" do
      keys = path.split(".")
      leaf = keys.pop
      parent = keys.reduce(valid_config) { |value, key| value.fetch(key) }
      parent[leaf] = invalid_value

      in_tmp_repo do |root|
        write(root, ".product-factory/config.yml", YAML.dump(valid_config))

        expect { described_class.load(root) }
          .to raise_error(ProductFactory::ValidationError, "#{path} must be #{expected_type}")
      end
    end
  end

  it "allows a null staging URL" do
    valid_config["qa"]["staging_url"] = nil

    in_tmp_repo do |root|
      write(root, ".product-factory/config.yml", YAML.dump(valid_config))

      expect(described_class.load(root).qa.fetch("staging_url")).to be_nil
    end
  end

  [
    ["adapter", "confluence", "artifacts.adapter is unsupported"],
    ["root", "/product", "artifacts.root must be a safe relative path"],
    ["root", "../product", "artifacts.root must be a safe relative path"]
  ].each do |key, value, message|
    it "rejects an invalid artifact #{key}" do
      valid_config.fetch("artifacts")[key] = value

      expect { described_class.new(valid_config) }
        .to raise_error(ProductFactory::ValidationError, message)
    end
  end

  %w[
    product github research workflow agents artifacts
    agents.ideator agents.business_analyst agents.technical_lead agents.manual_qa
    qa qa.credential_env knowledge
  ].each do |path|
    it "rejects a non-mapping #{path} section" do
      keys = path.split(".")
      leaf = keys.pop
      parent = keys.reduce(valid_config) { |value, key| value.fetch(key) }
      parent[leaf] = false

      in_tmp_repo do |root|
        write(root, ".product-factory/config.yml", YAML.dump(valid_config))

        expect { described_class.load(root) }
          .to raise_error(ProductFactory::ValidationError, "#{path} must be a mapping")
      end
    end
  end
end
