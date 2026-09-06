# frozen_string_literal: true

RSpec.describe ProductFactory::CLI do
  let(:root) { File.realpath(Dir.mktmpdir("product-factory-setup-integration")) }
  let(:target) { File.join(root, "application") }
  let(:wiki_remote) { File.join(root, "application.wiki.git") }
  let(:home) { "# Human Home\n\nNever replace this.\n" }
  let(:github) { FakeGitHub.new }

  before do
    create_application
    create_wiki
  end

  after { FileUtils.remove_entry(root) }

  it "converges through the CLI and repeats as a no-op" do
    first_output = StringIO.new
    first_error = StringIO.new
    first_status = run_setup(input: "Bootcamper\nyes\n", output: first_output, error: first_error)
    second_output = StringIO.new
    second_error = StringIO.new
    second_status = run_setup(input: "", output: second_output, error: second_error)

    expect(first_status).to eq(0), first_error.string
    expect(second_status).to eq(0), second_error.string
    expect(github.issue_type_names).to eq(%w[Idea Epic Ticket])
    expect(github.project.fetch("public")).to be(false)
    expect(github.view_names).to eq(%w[Ideas Epics Tickets])
    expect(wiki_pages.fetch("Home.md")).to eq(home)
    expect(second_output.string).to include("Product Factory is up to date")
  end

  it "resumes a remote write without duplicating the Project or prompting" do
    failing_github = FakeGitHub.new(fail_once_after: ProductFactory::Operation::ENSURE_PROJECT)
    first_error = StringIO.new

    expect(run_setup(input: "Bootcamper\nyes\n", github: failing_github, error: first_error)).to eq(1)
    output = StringIO.new
    error = StringIO.new
    expect(run_setup(input: "", output:, error:, github: failing_github)).to eq(0), error.string

    expect(output.string).to include("Resuming ")
    expect(output.string).not_to include("Apply this plan?")
    expect(failing_github.project.fetch("id")).to eq("P_1")
    failure = journal_events.find { |event| event["event"] == "operation_failed" }
    expect(failure).to include(
      "responsible_component" => "github", "root_cause" => "simulated interruption",
      "recovery_action" => "rerun product-factory setup"
    )
  end

  private

  def run_setup(input:, output: StringIO.new, error: StringIO.new, github: self.github)
    runner = ProductFactory::Setup::Runner.new(
      distribution_root: FileHelpers::FACTORY_ROOT, target_root: target,
      input: StringIO.new(input), output:, clock: -> { Time.utc(2026, 9, 5) },
      shell: ProductFactory::StreamShell.new(output, error), github_client: github,
      github_state: github, github_writer: github, wiki_repository:
    )
    ProductFactory::CLI.start(["setup"], input: StringIO.new(input), output:, error:, cwd: target, setup_runner: runner)
  end

  def wiki_repository
    ProductFactory::Wiki::Repository.new(
      organization: "LIT-Bootcamp", repository: "bootcamper",
      shell: ProductFactory::StreamShell.new(StringIO.new, StringIO.new), remote: wiki_remote
    )
  end

  def create_application
    FileUtils.mkdir_p(target)
    git!("init", target)
    git!("remote", "add", "origin", "git@github.com:LIT-Bootcamp/bootcamper.git", chdir: target)
  end

  def create_wiki
    source = File.join(root, "wiki-source")
    git!("init", "--bare", wiki_remote)
    git!("init", source)
    File.write(File.join(source, "Home.md"), home)
    git!("add", "Home.md", chdir: source)
    git!("-c", "user.name=Human", "-c", "user.email=human@example.com", "commit", "-m", "Home", chdir: source)
    git!("remote", "add", "origin", wiki_remote, chdir: source)
    git!("push", "origin", "HEAD", chdir: source)
  end

  def wiki_pages = wiki_repository.snapshot.fetch("pages")

  def journal_events
    ProductFactory::Journal.new(
      path: File.join(target, ".product-factory-journal.jsonl"), clock: -> { Time.utc(2026, 9, 5) }
    ).events
  end

  def git!(*, chdir: root)
    _output, error, status = Open3.capture3("git", *, chdir:)
    raise error unless status.success?
  end
end
