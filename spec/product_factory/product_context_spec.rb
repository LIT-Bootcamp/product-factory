# frozen_string_literal: true

RSpec.describe ProductFactory::ProductContext do
  subject(:service) { described_class }

  let(:config) do
    ProductFactory::Config.new(
      "schema_version" => 1,
      "product" => {
        "name" => "Example Product",
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
    )
  end

  let(:snapshot) { { "documents" => {} } }
  let(:answers) do
    {
      "mission" => "Help people learn with mentors",
      "target_users" => "Students and mentors",
      "primary_user_problem" => "Learning lacks feedback",
      "desired_outcome" => "Students complete guided courses",
      "markets_and_languages" => "Ukraine; Ukrainian and English",
      "competitor_seeds" => "Coursera, Udemy",
      "constraints" => "Small team",
      "non_goals" => "Marketplace"
    }
  end

  it "returns the landing and immutable document IDs for the configured context document" do
    expect(service.document_ids(config)).to eq(%w[context context/v1])
  end

  it "renders the landing and immutable product context documents" do
    documents = service.call(
      config:,
      snapshot:,
      answers:,
      actor: "human:factory-test",
      run_id: "RUN-1",
      recorded_at: "2026-09-07T10:00:00Z",
      version_link: "context/v1.md"
    )

    expect(documents).to eq(
      "context" => <<~MD,
        <!-- product-factory:v1:artifact:context -->
        # Product Context — Example Product

        Current version: [v1](context/v1.md)

        Help people learn with mentors
      MD
      "context/v1" => <<~MD
        <!-- product-factory:v1:artifact:context/v1 -->
        # Product Context — Example Product

        | Field | Value |
        |---|---|
        | Version | 1 |
        | Created at | 2026-09-07T10:00:00Z |
        | Created by | human:factory-test |
        | Factory run | RUN-1 |
        | Change reason | Initial Product Context |

        ## Mission
        Help people learn with mentors

        ## Target Users
        Students and mentors

        ## Primary User Problem
        Learning lacks feedback

        ## Desired Outcome
        Students complete guided courses

        ## Markets and Languages
        Ukraine; Ukrainian and English

        ## Competitor Seeds
        Coursera, Udemy

        ## Constraints
        Small team

        ## Non-goals
        Marketplace
      MD
    )
  end

  it "returns only the landing document when the immutable version already exists" do
    snapshot_with_version = {
      "documents" => {
        "context/v1" => "<!-- product-factory:v1:artifact:context/v1 -->\n# Existing\n"
      }
    }

    documents = service.call(
      config:,
      snapshot: snapshot_with_version,
      answers:,
      actor: "human:factory-test",
      run_id: "RUN-1",
      recorded_at: "2026-09-07T10:00:00Z",
      version_link: "context/v1.md"
    )

    expect(documents).to eq(
      "context" => <<~MD
        <!-- product-factory:v1:artifact:context -->
        # Product Context — Example Product

        Current version: [v1](context/v1.md)

        Help people learn with mentors
      MD
    )
  end

  it "derives the landing document from an established immutable Product Context" do
    established_snapshot = {
      "documents" => {
        "context/v1" => <<~MD
          <!-- product-factory:v1:artifact:context/v1 -->
          # Product Context — Example Product

          ## Mission
          Help people learn with mentors

          ## Target Users
          Students and mentors
        MD
      }
    }

    documents = service.call(
      config:, snapshot: established_snapshot, answers: nil, actor: "human:factory-test", run_id: "RUN-1",
      recorded_at: "2026-09-07T10:00:00Z", version_link: "context/v1.md"
    )

    expect(documents).to eq(
      "context" => <<~MD
        <!-- product-factory:v1:artifact:context -->
        # Product Context — Example Product

        Current version: [v1](context/v1.md)

        Help people learn with mentors
      MD
    )
  end
end
