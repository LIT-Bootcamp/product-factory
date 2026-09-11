# frozen_string_literal: true

RSpec.describe ProductFactory::CLI do
  let(:root) { File.realpath(Dir.mktmpdir("product-factory-artifact-storage")) }
  let(:target) { File.join(root, "application") }
  let(:wiki_remote) { File.join(root, "application.wiki.git") }
  let(:github) { FakeGitHub.new }

  before { create_application }

  after { FileUtils.remove_entry(root) }

  it "defaults to repository artifacts through two real CLI setup runs", :aggregate_failures do
    head_before_setup = git!("rev-parse", "HEAD", chdir: target)
    remote_before = git!("remote", "get-url", "origin", chdir: target)
    first_output = StringIO.new
    first_error = StringIO.new
    first_status = run_setup(input: "Bootcamper\n#{product_context_input('yes')}", output: first_output,
                             error: first_error)
    second_output = StringIO.new
    second_error = StringIO.new
    second_status = run_setup(input: "", output: second_output, error: second_error)

    expect(first_status).to eq(0), first_error.string
    expect(second_status).to eq(0), second_error.string
    expect_repository_documents
    expect(File.binread(File.join(target, "product/context.md"))).to include("Current version: [v1](context/v1.md)")
    expect(File.read(File.join(target, "product/context/v1.md"))).to include(
      "# Product Context", "| Version | 1 |", "## Mission"
    )
    expect(ProductFactory::Config.load(target).artifacts).to eq("adapter" => "repository", "root" => "product")
    installation = ProductFactory::Installation.load(target)
    repository_store = ProductFactory::Artifacts::Repository.new(target_root: target, root: "product")
    product_context_ids = ProductFactory::Artifacts::Planner::DOCUMENT_IDS + %w[context context/v1]
    expect(installation.artifact_adapter).to eq("repository")
    expect(installation.artifact_document_hashes).to include(
      "context" => Digest::SHA256.hexdigest(File.binread(File.join(target, "product/context.md"))),
      "context/v1" => Digest::SHA256.hexdigest(File.binread(File.join(target, "product/context/v1.md")))
    )
    expect(installation.artifact_revision).to eq(repository_store.revision(document_ids: product_context_ids))
    expect(second_output.string).to include("Product Factory is up to date")
    expect(second_output.string).not_to include(
      "CREATE ", "UPDATE ", "ADOPT ", "SYNC ", "Apply this plan? [yes/no]"
    )
    expect(git!("rev-parse", "HEAD", chdir: target)).to eq(head_before_setup)
    expect(git!("remote", "get-url", "origin", chdir: target)).to eq(remote_before)
  end

  it "recreates a deleted landing context from v1 without prompting for context answers" do
    expect(run_setup(input: "Bootcamper\n#{product_context_input('yes')}")).to eq(0)
    version_path = File.join(target, "product/context/v1.md")
    version = File.binread(version_path)
    File.delete(File.join(target, "product/context.md"))
    output = StringIO.new

    expect(run_setup(input: "yes\n", output:)).to eq(0)
    expect(output.string).not_to include("Mission: ")
    expect(File.binread(File.join(target, "product/context.md"))).to include("Help people learn with mentors")
    expect(File.binread(version_path)).to eq(version)
  end

  it "reports a collision for foreign immutable context without overwriting it" do
    foreign_context = "# Human Product Context\n"
    write(target, "product/context/v1.md", foreign_context)
    error = StringIO.new

    status = run_setup(input: "Bootcamper\n#{product_context_input('yes')}", error:)

    expect(status).to eq(2)
    expect(error.string).to include("plan has conflicts")
    expect(File.binread(File.join(target, "product/context/v1.md"))).to eq(foreign_context)
  end

  context "with a legacy v1 Wiki installation" do
    before do
      create_wiki
      write_legacy_config
      write_legacy_installation
    end

    it "migrates physical pages and state without changing Home or _Sidebar", :aggregate_failures do
      first_output = StringIO.new
      first_error = StringIO.new
      first_status = run_setup(input: product_context_input("yes"), output: first_output, error: first_error,
                               artifact_store: wiki_store)
      second_output = StringIO.new
      second_error = StringIO.new
      second_status = run_setup(input: "", output: second_output, error: second_error, artifact_store: wiki_store)
      installation = ProductFactory::Installation.load(target)

      expect(first_status).to eq(0), first_error.string
      expect(second_status).to eq(0), second_error.string
      expect(wiki_page("Home.md")).to eq(home)
      expect(wiki_page("_Sidebar.md")).to eq(sidebar)
      expect_generic_wiki_documents
      expect(wiki_page("Product-Factory--context.md")).to include(
        "Current version: [v1](Product-Factory--context--v1)"
      )
      expect(wiki_page("Product-Factory--context--v1.md")).to include("Initial Product Context")
      expect(ProductFactory::Config.load(target).artifacts).to eq("adapter" => "wiki")
      expect(installation.to_h).to include(
        "artifact_adapter" => "wiki", "artifact_revision" => wiki_head,
        "artifact_document_hashes" => a_hash_including(*wiki_documents.values, "context", "context/v1")
      )
      expect(installation.artifact_revision).to eq(
        wiki_store.revision(document_ids: ProductFactory::Artifacts::Planner::DOCUMENT_IDS + %w[context context/v1])
      )
      expect(installation.to_h).not_to include("wiki_page_hashes", "wiki_head")
      expect(first_output.string).to include("SYNC artifacts:documents")
      expect(second_output.string).to include("Product Factory is up to date")
    end

    it "switches to repository artifacts without touching the Wiki" do
      expect(run_setup(input: product_context_input("yes"), artifact_store: wiki_store)).to eq(0)
      wiki_head_before = wiki_head
      wiki_tree_before = wiki_tree
      application_head_before = git!("rev-parse", "HEAD", chdir: target)
      switch_to_repository
      switch_output = StringIO.new
      switch_error = StringIO.new
      switch_status = run_setup(input: product_context_input("yes"), output: switch_output, error: switch_error)
      second_output = StringIO.new
      second_status = run_setup(input: "", output: second_output)

      expect(switch_status).to eq(0), switch_error.string
      expect(second_status).to eq(0)
      expect_repository_documents
      expect(wiki_head).to eq(wiki_head_before)
      expect(wiki_tree).to eq(wiki_tree_before)
      expect(ProductFactory::Installation.load(target).artifact_adapter).to eq("repository")
      expect(second_output.string).to include("Product Factory is up to date")
      expect(git!("rev-parse", "HEAD", chdir: target)).to eq(application_head_before)
    end

    it "persists an adapter switch when every repository document already matches" do
      expect(run_setup(input: product_context_input("yes"), artifact_store: wiki_store)).to eq(0)
      switch_to_repository
      desired_repository_documents.each { |path, content| write(target, path, content) }
      output = StringIO.new
      error = StringIO.new

      status = run_setup(input: product_context_input("yes"), output:, error:)

      expect(status).to eq(0), error.string
      expect(output.string).to include("SYNC artifacts:documents")
      expect(ProductFactory::Installation.load(target).artifact_adapter).to eq("repository")
      expect_repository_documents
    end
  end

  private

  def run_setup(input:, output: StringIO.new, error: StringIO.new, artifact_store: nil)
    runner = ProductFactory::Setup::Runner.new(
      distribution_root: FileHelpers::FACTORY_ROOT, target_root: target,
      input: StringIO.new(input), output:, clock: -> { Time.utc(2026, 9, 7) },
      shell: ProductFactory::StreamShell.new(output, error), github_client: github,
      github_state: github, github_writer: github, artifact_store:
    )
    described_class.start(
      ["setup"], input: StringIO.new(input), output:, error:, cwd: target, setup_runner: runner
    )
  end

  def create_application
    FileUtils.mkdir_p(target)
    git!("init", "--quiet", target)
    write(target, "README.md", "application\n")
    git!("add", "README.md", chdir: target)
    git!("-c", "user.name=Human", "-c", "user.email=human@example.com", "-c", "commit.gpgsign=false",
         "commit", "--quiet", "-m", "Initial application", chdir: target)
    git!("remote", "add", "origin", "git@github.com:LIT-Bootcamp/bootcamper.git", chdir: target)
  end

  def create_wiki
    source = File.join(root, "wiki-source")
    git!("init", "--bare", "--quiet", wiki_remote)
    git!("init", "--quiet", source)
    write(source, "Home.md", home)
    write(source, "_Sidebar.md", sidebar)
    wiki_documents.each_key do |page|
      title = File.basename(page, ".md").tr("-", " ")
      write(source, page, "<!-- product-factory:v1:wiki:#{File.basename(page, '.md')} -->\n# #{title}\n\nLegacy.\n")
    end
    git!("add", ".", chdir: source)
    git!("-c", "user.name=Human", "-c", "user.email=human@example.com", "-c", "commit.gpgsign=false",
         "commit", "--quiet", "-m", "Legacy Wiki", chdir: source)
    git!("remote", "add", "origin", wiki_remote, chdir: source)
    git!("push", "--quiet", "origin", "HEAD", chdir: source)
  end

  def write_legacy_config
    config = YAML.safe_load_file(File.join(FileHelpers::FACTORY_ROOT, "templates/config.yml"))
    product = config.fetch("product")
    product["name"] = "Bootcamper"
    product["context_page"] = product.delete("context_document")
    product["inventory_page"] = product.delete("inventory_document")
    config.delete("artifacts")
    config.fetch("github").replace(
      "organization" => "LIT-Bootcamp", "repository" => "bootcamper",
      "project_title" => "Bootcamper Product Factory"
    )
    write(target, ProductFactory::Config::PATH, YAML.dump(config))
  end

  def write_legacy_installation
    hashes = wiki_documents.keys.to_h { |page| [page, Digest::SHA256.hexdigest(wiki_page(page))] }
    hashes["_Sidebar.md"] = Digest::SHA256.hexdigest(sidebar)
    write(
      target, ProductFactory::Installation::PATH,
      YAML.dump("schema_version" => 1, "wiki_page_hashes" => hashes, "wiki_head" => wiki_head)
    )
  end

  def switch_to_repository
    config = YAML.safe_load_file(File.join(target, ProductFactory::Config::PATH))
    config["artifacts"] = { "adapter" => "repository", "root" => "product" }
    write(target, ProductFactory::Config::PATH, YAML.dump(config))
  end

  def expect_repository_documents
    expect(Dir.glob(File.join(target, "product/**/*.md")).map { |path| path.delete_prefix("#{target}/") })
      .to include(*repository_documents.keys, "product/context.md", "product/context/v1.md")
    repository_documents.each do |path, document|
      expect(File.binread(File.join(target, path))).to include("product-factory:v1:artifact:#{document}")
    end
  end

  def expect_generic_wiki_documents
    wiki_documents.each do |page, document|
      content = wiki_page(page)
      expect(content).to include("product-factory:v1:artifact:#{document}")
      expect(content).not_to include("product-factory:v1:wiki:")
    end
  end

  def wiki_store
    ProductFactory::Artifacts::Wiki.new(
      organization: "LIT-Bootcamp", repository: "bootcamper",
      shell: ProductFactory::StreamShell.new(StringIO.new, StringIO.new), remote: wiki_remote
    )
  end

  def wiki_tree
    pages = git!("--git-dir", wiki_remote, "ls-tree", "-r", "--name-only", "HEAD").lines(chomp: true)
    pages.to_h { |page| [page, wiki_page(page)] }
  end

  def repository_documents
    {
      "product/README.md" => "index",
      "product/setup-log.md" => "setup-log",
      "product/ideas/README.md" => "ideas/index",
      "product/epics/README.md" => "epics/index",
      "product/tickets/README.md" => "tickets/index",
      "product/research/README.md" => "research/index",
      "product/factory-runs/README.md" => "factory-runs/index"
    }
  end

  def wiki_documents
    {
      "Product-Factory.md" => "index",
      "Setup-Log.md" => "setup-log",
      "Ideas.md" => "ideas/index",
      "Epics.md" => "epics/index",
      "Tickets.md" => "tickets/index",
      "Research.md" => "research/index",
      "Factory-Runs.md" => "factory-runs/index"
    }
  end

  def desired_repository_documents
    {
      "product/README.md" => "<!-- product-factory:v1:artifact:index -->\n# Product Factory\n\n" \
                             "Canonical product artifacts and factory run records.\n",
      "product/setup-log.md" => "<!-- product-factory:v1:artifact:setup-log -->\n# Setup Log\n\n" \
                                "| Run | Recorded at | Changes |\n|---|---|---|\n",
      "product/ideas/README.md" => "<!-- product-factory:v1:artifact:ideas/index -->\n# Ideas\n\n" \
                                   "No Ideas have been published yet.\n",
      "product/epics/README.md" => "<!-- product-factory:v1:artifact:epics/index -->\n# Epics\n\n" \
                                   "No Epics have been published yet.\n",
      "product/tickets/README.md" => "<!-- product-factory:v1:artifact:tickets/index -->\n# Tickets\n\n" \
                                     "No Tickets have been published yet.\n",
      "product/research/README.md" => "<!-- product-factory:v1:artifact:research/index -->\n# Research\n\n" \
                                      "No research records have been published yet.\n",
      "product/factory-runs/README.md" => "<!-- product-factory:v1:artifact:factory-runs/index -->\n" \
                                          "# Factory Runs\n\nNo factory phase runs have been published yet.\n"
    }
  end

  def product_context_input(confirmation)
    "#{[
      'Help people learn with mentors',
      'Students and mentors',
      'Learning lacks feedback',
      'Students complete guided courses',
      'Ukraine; Ukrainian and English',
      'Coursera, Udemy',
      'Small team',
      'Marketplace',
      confirmation
    ].join("\n")}\n"
  end

  def home = "# Human Home\n\nNever replace this.\n"
  def sidebar = "<!-- product-factory:v1:wiki:_Sidebar -->\n# Human navigation\n\nKeep this byte-for-byte.\n"

  def wiki_page(page) = git!("--git-dir", wiki_remote, "show", "HEAD:#{page}")
  def wiki_head = git!("--git-dir", wiki_remote, "rev-parse", "HEAD").strip

  def git!(*command, chdir: root)
    output, error, status = Open3.capture3("git", *command, chdir:)
    raise error unless status.success?

    output
  end
end
