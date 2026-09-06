# frozen_string_literal: true

RSpec.describe ProductFactory::Wiki::Repository do
  subject(:repository) do
    described_class.new(
      organization: "LIT-Bootcamp",
      repository: "bootcamper",
      shell: ProductFactory::StreamShell.new(StringIO.new, StringIO.new),
      remote:
    )
  end

  let(:root) { Dir.mktmpdir("product-factory-wiki") }
  let(:remote) { File.join(root, "application.wiki.git") }
  let(:home) { "# Human Home\n\nKeep this byte-for-byte.\n" }

  before { create_wiki(home:) }
  after { FileUtils.remove_entry(root) }

  it "reads the current head and Markdown pages" do
    snapshot = repository.snapshot

    expect(snapshot.fetch("head")).to match(/\A[0-9a-f]{40,64}\z/)
    expect(snapshot.fetch("pages")).to eq("Home.md" => home)
  end

  it "requires a manually initialized Home page" do
    FileUtils.remove_entry(remote)
    create_wiki(home: nil)

    expect { repository.snapshot }
      .to raise_error(
        ProductFactory::ExternalFailure,
        "GitHub Wiki has no Home page"
      ) do |failure|
        expect(failure.recovery_action)
          .to eq("Create the Home page in GitHub Wiki, then rerun product-factory setup")
      end
  end

  it "commits only listed owned pages and preserves Home byte-for-byte" do
    operation = sync_operation(
      repository.snapshot.fetch("head"),
      "_Sidebar.md" => "<!-- product-factory:v1:wiki:_Sidebar -->\n# Navigation\n"
    )

    expect(repository.apply(operation)).to be(true)
    expect(repository.snapshot.fetch("pages")).to include(
      "Home.md" => home,
      "_Sidebar.md" => "<!-- product-factory:v1:wiki:_Sidebar -->\n# Navigation\n"
    )
  end

  it "refuses an unexpected head without changing the Wiki" do
    original = repository.snapshot.fetch("head")
    operation = sync_operation("stale", "_Sidebar.md" => "owned\n")

    expect { repository.apply(operation) }
      .to raise_error(ProductFactory::ConflictError, "Wiki changed after planning")
    expect(repository.snapshot.fetch("head")).to eq(original)
  end

  it "reapplying desired pages creates no commit" do
    content = "<!-- product-factory:v1:wiki:_Sidebar -->\n# Navigation\n"
    repository.apply(sync_operation(repository.head, "_Sidebar.md" => content))
    applied_head = repository.head

    expect(repository.apply(sync_operation(applied_head, "_Sidebar.md" => content))).to be(true)
    expect(repository.head).to eq(applied_head)
  end

  private

  def create_wiki(home:)
    source = File.join(root, "source")
    git!("init", "--bare", remote)
    git!("init", source)
    return unless home

    File.write(File.join(source, "Home.md"), home)
    git!("add", "Home.md", chdir: source)
    git!("-c", "user.name=Human", "-c", "user.email=human@example.com", "commit", "-m", "Initialize Wiki",
         chdir: source)
    git!("remote", "add", "origin", remote, chdir: source)
    git!("push", "origin", "HEAD", chdir: source)
  end

  def git!(*, chdir: nil)
    _output, error, status = Open3.capture3("git", *, chdir: chdir || root)
    raise error unless status.success?
  end

  def sync_operation(expected_head, pages)
    ProductFactory::Operation.new(
      kind: ProductFactory::Operation::SYNC_WIKI,
      target: "wiki:factory-pages",
      attributes: { "expected_head" => expected_head, "pages" => pages, "reason" => "synchronize" }
    )
  end
end
