# frozen_string_literal: true

RSpec.describe ProductFactory::Artifacts::Wiki do
  subject(:adapter) do
    described_class.new(
      organization: "LIT-Bootcamp",
      repository: "bootcamper",
      shell: ProductFactory::StreamShell.new(StringIO.new, StringIO.new),
      remote:
    )
  end

  let(:root) { Dir.mktmpdir("product-factory-wiki-") }
  let(:remote) { File.join(root, "application.wiki.git") }
  let(:home) { "# Human Home\n\nKeep this byte-for-byte.\n" }
  let(:sidebar) { "# Human Navigation\n\nKeep this too.\n" }
  let(:legacy_ideas) { "<!-- product-factory:v1:wiki:Ideas -->\n# Ideas\n" }

  before { create_wiki(home:, "_Sidebar.md" => sidebar, "Ideas.md" => legacy_ideas) }
  after { FileUtils.remove_entry(root) }

  it "maps Wiki pages to logical documents and identifies exact legacy ownership markers" do
    snapshot = adapter.snapshot

    expect(snapshot).to include(
      "revision" => a_string_matching(/\A[0-9a-f]{40,64}\z/),
      "documents" => { "ideas/index" => legacy_ideas }
    )
    expect(snapshot.fetch("legacy_owned_documents")).to include("ideas/index")
    expect(adapter.document_hashes.fetch("ideas/index")).to eq(Digest::SHA256.hexdigest(legacy_ideas))
  end

  it "requires a manually initialized Home page" do
    FileUtils.remove_entry(remote)
    create_wiki(home: nil)

    expect { adapter.snapshot }
      .to raise_error(
        ProductFactory::ExternalFailure,
        "GitHub Wiki has no Home page"
      ) do |failure|
        expect(failure.recovery_action)
          .to eq("Create the Home page in GitHub Wiki, then rerun product-factory setup")
      end
  end

  it "commits logical documents once and preserves human-owned Wiki pages byte-for-byte" do
    ideas = "<!-- product-factory:v1:artifact:ideas/index -->\n# Current Ideas\n"

    expect(adapter.apply(sync_operation({ "ideas/index" => ideas }))).to be(true)
    expect(adapter.snapshot.fetch("documents")).to include("ideas/index" => ideas)
    expect(wiki_pages).to include("Home.md" => home, "_Sidebar.md" => sidebar, "Ideas.md" => ideas)
    expect(git!("rev-list", "--count", "HEAD", git_dir: remote).strip).to eq("2")
    expect(git!("log", "-1", "--format=%s", git_dir: remote).strip).to eq("Update Product Factory artifacts")
  end

  it "refuses an unexpected revision without changing the Wiki" do
    original = adapter.revision
    operation = sync_operation({ "ideas/index" => "factory\n" }, revision: "stale")

    expect { adapter.apply(operation) }
      .to raise_error(ProductFactory::ConflictError, "Artifacts changed after planning")
    expect(adapter.revision).to eq(original)
    expect(wiki_pages.fetch("Ideas.md")).to eq(legacy_ideas)
  end

  it "reapplies synchronized documents without creating a commit" do
    ideas = "<!-- product-factory:v1:artifact:ideas/index -->\n# Current Ideas\n"
    adapter.apply(sync_operation({ "ideas/index" => ideas }))
    applied_revision = adapter.revision

    expect(adapter.apply(sync_operation({ "ideas/index" => ideas }))).to be(true)
    expect(adapter.revision).to eq(applied_revision)
  end

  private

  def create_wiki(home:, **pages)
    source = File.join(root, "source")
    git!("init", "--bare", "-q", remote)
    git!("init", "-q", source)
    return unless home

    pages.merge("Home.md" => home).each { |name, content| File.binwrite(File.join(source, name), content) }
    git!("add", "--", *pages.keys, "Home.md", chdir: source)
    git!("-c", "user.name=Human", "-c", "user.email=human@example.com", "commit", "-qm", "Initialize Wiki",
         chdir: source)
    git!("remote", "add", "origin", remote, chdir: source)
    git!("push", "-q", "origin", "HEAD", chdir: source)
  end

  def sync_operation(documents, revision: adapter.revision)
    snapshot = adapter.snapshot
    ProductFactory::Operation.new(
      kind: ProductFactory::Operation::SYNC_ARTIFACTS,
      target: "artifacts:documents",
      attributes: {
        "adapter" => "wiki",
        "expected_revision" => revision,
        "expected_hashes" => expected_hashes(snapshot),
        "documents" => documents,
        "reason" => "synchronize Product Factory artifacts"
      }
    )
  end

  def expected_hashes(snapshot)
    %w[index setup-log ideas/index epics/index tickets/index research/index factory-runs/index].to_h do |document|
      content = snapshot.fetch("documents")[document]
      [document, content && Digest::SHA256.hexdigest(content)]
    end
  end

  def wiki_pages
    checkout = File.join(root, "checkout-#{Dir.children(root).length}")
    git!("clone", "-q", remote, checkout)
    Dir.glob(File.join(checkout, "*.md")).to_h { |path| [File.basename(path), File.binread(path)] }
  end

  def git!(*command, chdir: nil, git_dir: nil)
    command.unshift("--git-dir", git_dir) if git_dir
    output, error, status = Open3.capture3("git", *command, chdir: chdir || root)
    raise error unless status.success?

    output
  end
end
