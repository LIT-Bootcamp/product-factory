# frozen_string_literal: true

RSpec.describe ProductFactory::GitHub::State do
  subject(:state) { described_class.new(config:, client:) }

  let(:config) { product_config }
  let(:client) { instance_double(ProductFactory::GitHub::Client) }

  before do
    allow(client).to receive_messages(auth_status: true, graphql: graphql_response)
    allow(client).to receive(:get) do |endpoint|
      case endpoint
      when "user/memberships/orgs/LIT-Bootcamp"
        { "state" => "active", "role" => "admin", "organization" => { "id" => 1, "node_id" => "O_1" } }
      when "orgs/LIT-Bootcamp/issue-types"
        [{ "id" => 410, "name" => "Idea", "description" => "idea", "color" => "purple", "is_enabled" => true }]
      when "orgs/LIT-Bootcamp/projectsV2/2/fields?per_page=100"
        [{
          "id" => 20,
          "node_id" => "F_1",
          "name" => "Priority",
          "data_type" => "SINGLE_SELECT",
          "updated_at" => "ignored",
          "options" => [{ "id" => "O_1", "name" => "P1", "color" => "RED", "description" => "Highest" }]
        }]
      else
        raise "unexpected GET #{endpoint}"
      end
    end
  end

  it "normalizes organization, repository, and project state" do
    expect(state.snapshot).to include(
      "actor" => "denys",
      "organization" => { "id" => "O_1", "login" => "LIT-Bootcamp", "role" => "admin" },
      "repository" => { "id" => "R_1", "name" => "bootcamper", "name_with_owner" => "LIT-Bootcamp/bootcamper" }
    )
    expect(state.snapshot.dig("projects", 0)).to include(
      "id" => "P_2",
      "number" => 2,
      "title" => "Bootcamper Product Factory",
      "public" => false
    )
  end

  it "fingerprints semantic values without response order or timestamps" do
    first = state.resource_hashes
    reordered = described_class.new(config:, client: reordered_client).resource_hashes

    expect(reordered).to eq(first)
  end

  private

  def product_config
    data = YAML.safe_load(ProductFactory::Distribution.new(FileHelpers::FACTORY_ROOT).config_bytes, aliases: false)
    data["product"]["name"] = "Bootcamper"
    data["github"] = {
      "organization" => "LIT-Bootcamp",
      "repository" => "bootcamper",
      "project_title" => "Bootcamper Product Factory"
    }
    ProductFactory::Config.new(data)
  end

  def graphql_response
    {
      "data" => {
        "viewer" => { "login" => "denys" },
        "organization" => {
          "id" => "O_1",
          "projectsV2" => {
            "nodes" => [{
              "id" => "P_2",
              "number" => 2,
              "title" => "Bootcamper Product Factory",
              "shortDescription" => "product-factory:v1:project:LIT-Bootcamp/bootcamper",
              "public" => false,
              "closed" => false,
              "items" => { "totalCount" => 0 },
              "repositories" => { "nodes" => [{ "nameWithOwner" => "LIT-Bootcamp/bootcamper" }] },
              "views" => {
                "nodes" => [{
                  "id" => "V_1", "number" => 1, "name" => "Ideas", "layout" => "TABLE_LAYOUT",
                  "filter" => "type:\"Idea\"", "visibleFields" => { "nodes" => [{ "name" => "Title" }] },
                  "updatedAt" => "ignored"
                }]
              }
            }],
            "pageInfo" => { "hasNextPage" => false, "endCursor" => nil }
          }
        },
        "repository" => { "id" => "R_1", "name" => "bootcamper", "nameWithOwner" => "LIT-Bootcamp/bootcamper" }
      }
    }
  end

  def reordered_client
    instance_double(ProductFactory::GitHub::Client).tap do |other|
      allow(other).to receive_messages(
        auth_status: true,
        graphql: JSON.parse(JSON.generate(graphql_response), object_class: Hash)
      )
      allow(other).to receive(:get) do |endpoint|
        value = client.get(endpoint)
        value.is_a?(Array) ? value.map { |item| item.to_a.reverse.to_h.merge("updated_at" => "different") } : value
      end
    end
  end
end
