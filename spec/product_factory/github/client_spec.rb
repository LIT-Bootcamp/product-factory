# frozen_string_literal: true

RSpec.describe ProductFactory::GitHub::Client do
  subject(:client) { described_class.new(shell:) }

  let(:shell) { instance_double(ProductFactory::StreamShell) }
  let(:status) { instance_double(Process::Status, success?: true, exitstatus: 0) }

  it "sends JSON through stdin with the pinned REST version" do
    allow(shell).to receive(:capture3).and_return(["{\"id\":410}", "", status])

    result = client.post("orgs/acme/issue-types", "name" => "Idea", "is_enabled" => true)

    expect(result).to eq("id" => 410)
    expect(shell).to have_received(:capture3).with(
      "gh", "api", "orgs/acme/issue-types", "--method", "POST",
      "--header", "Accept: application/vnd.github+json",
      "--header", "X-GitHub-Api-Version: 2026-03-10",
      "--input", "-",
      chdir: nil,
      stdin_data: "{\"name\":\"Idea\",\"is_enabled\":true}"
    )
  end

  it "sends GraphQL variables as JSON" do
    allow(shell).to receive(:capture3).and_return(["{\"data\":{}}", "", status])

    result = client.graphql("query($login:String!){organization(login:$login){id}}", "login" => "acme")

    expect(result).to eq("data" => {})
    expect(shell).to have_received(:capture3).with(
      "gh", "api", "graphql", "--method", "POST",
      "--header", "Accept: application/vnd.github+json",
      "--header", "X-GitHub-Api-Version: 2026-03-10",
      "--input", "-",
      chdir: nil,
      stdin_data: JSON.generate(
        "query" => "query($login:String!){organization(login:$login){id}}",
        "variables" => { "login" => "acme" }
      )
    )
  end

  it "redacts credentials from failures" do
    failed = instance_double(Process::Status, success?: false, exitstatus: 1)
    allow(shell).to receive(:capture3)
      .and_return(["", "token ghp_SECRET Authorization: Bearer ghp_OTHER", failed])

    expect { client.get("user") }
      .to raise_error(ProductFactory::ExternalFailure, /token \[REDACTED\] \[REDACTED\]/)
  end

  it "rejects a non-container JSON response" do
    allow(shell).to receive(:capture3).and_return(["true", "", status])

    expect { client.get("user") }
      .to raise_error(ProductFactory::ExternalFailure, /invalid GitHub JSON/)
  end
end
