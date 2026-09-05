# frozen_string_literal: true

RSpec.describe ProductFactory::CLI, :live_github do
  it "converges the exact private sandbox and preserves Home" do
    raise "live sandbox confirmation is missing" unless live_github_enabled?

    Dir.mktmpdir("product-factory-live") do |temporary|
      root = File.realpath(temporary)
      target = File.join(root, "application")
      clone_sandbox(target)
      home = wiki_snapshot.fetch("pages").fetch("Home.md")
      output = StringIO.new
      first = described_class.start(
        ["setup"], cwd: target, input: setup_input(target), output:, error: output
      )
      second_output = StringIO.new
      second = described_class.start(
        ["setup"], cwd: target, input: StringIO.new, output: second_output, error: second_output
      )

      expect(first).to eq(0), output.string
      expect(second).to eq(0), second_output.string
      verify_live_state(target, home)
      expect(second_output.string).to include("Product Factory is up to date")
      expect(completed_runs(target).last).to include("status" => "no-op")
    end
  end

  private

  def clone_sandbox(target)
    run!(
      "git", "-c", "credential.https://github.com.helper=!gh auth git-credential",
      "clone", "--quiet", "https://github.com/#{LiveGitHub::REPOSITORY}.git", target
    )
  end

  def setup_input(target)
    return StringIO.new("yes\n") if File.exist?(File.join(target, ProductFactory::Config::PATH))

    StringIO.new("Product Factory Sandbox\nyes\n")
  end

  def verify_live_state(target, home)
    config = ProductFactory::Config.load(target)
    shell = ProductFactory::StreamShell.new(StringIO.new, StringIO.new)
    client = ProductFactory::GitHub::Client.new(shell:)
    state = ProductFactory::GitHub::State.new(config:, client:)
    schema = ProductFactory::Setup::Schema.call(
      bytes: ProductFactory::Distribution.new(FileHelpers::FACTORY_ROOT).provisioning_schema_bytes
    )
    project = state.resource("github:project")
    snapshot = wiki_snapshot

    expect(repository_visibility).to eq("PRIVATE")
    expect(config.github.slice("organization", "repository").values.join("/")).to eq(LiveGitHub::REPOSITORY)
    expect_resource(project, desired_project(config, schema))
    expect_collection(state.snapshot.fetch("issue_types"), desired_issue_types(schema))
    expect_collection(project.fetch("fields"), desired_fields(schema))
    expect_collection(project.fetch("views"), desired_views(schema))
    expect(snapshot.fetch("pages").fetch("Home.md")).to eq(home)
    owned_pages = snapshot.fetch("pages").slice(*ProductFactory::Wiki::Repository::OWNED_PAGES)
    expect(owned_pages.keys).to match_array(ProductFactory::Wiki::Repository::OWNED_PAGES)
    owned_pages.each do |name, content|
      expect(content).to include("product-factory:v1:wiki:#{name.delete_suffix('.md')}")
    end
  end

  def desired_project(config, schema)
    schema.fetch("project").merge(
      "title" => config.github.fetch("project_title"),
      "short_description" => "product-factory:v1:project:#{LiveGitHub::REPOSITORY}",
      "repositories" => [LiveGitHub::REPOSITORY]
    )
  end

  def desired_issue_types(schema)
    schema.fetch("issue_types").map do |name, attributes|
      attributes.merge("name" => name, "is_enabled" => true)
    end
  end

  def desired_fields(schema)
    schema.fetch("fields").map do |name, attributes|
      attributes.merge("name" => name, "options" => attributes.fetch("options", []))
    end
  end

  def desired_views(schema)
    schema.fetch("views").map do |name, attributes|
      attributes.except("issue_type").merge(
        "name" => name, "layout" => "TABLE", "filter" => %(type:"#{attributes.fetch('issue_type')}")
      )
    end
  end

  def expect_collection(actual, expected)
    expect(actual.map { |resource| resource.fetch("name") })
      .to match_array(expected.map { |resource| resource.fetch("name") })
    expected.each do |resource|
      expect_resource(actual.find { |item| item.fetch("name") == resource.fetch("name") }, resource)
    end
  end

  def expect_resource(actual, expected)
    expect(ProductFactory::GitHub::State.fingerprint(actual))
      .to eq(ProductFactory::GitHub::State.fingerprint(expected))
  end

  def wiki_snapshot
    shell = ProductFactory::StreamShell.new(StringIO.new, StringIO.new)
    ProductFactory::Wiki::Repository.new(
      organization: "LIT-Bootcamp", repository: "product-factory-sandbox", shell:
    ).snapshot
  end

  def completed_runs(target)
    ProductFactory::Journal.new(
      path: File.join(target, ".product-factory-journal.jsonl"), clock: -> { Time.now }
    ).events.select { |event| event["event"] == "run_completed" }
  end

  def repository_visibility
    JSON.parse(run!("gh", "repo", "view", LiveGitHub::REPOSITORY, "--json", "visibility")).fetch("visibility")
  end

  def run!(*command)
    output, error, status = Open3.capture3(*command)
    raise error unless status.success?

    output
  end
end
