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

  it "maps safe versioned documents to prefixed Wiki pages" do
    versioned_documents = {
      "context" => "# Context\n",
      "context/v1" => "# Context V1\n",
      "ideas/IDEA-141/v2" => "# IDEA-141 V2\n"
    }

    expect(adapter.apply(sync_operation(versioned_documents))).to be(true)
    expect(wiki_pages).to include(
      "Product-Factory--context.md" => "# Context\n",
      "Product-Factory--context--v1.md" => "# Context V1\n",
      "Product-Factory--ideas--IDEA-141--v2.md" => "# IDEA-141 V2\n"
    )
    expect(adapter.snapshot(document_ids: versioned_documents.keys).fetch("documents")).to include(versioned_documents)
    expect(adapter.link("context/v1")).to eq("Product-Factory--context--v1")
  end

  it "rejects unsafe versioned documents before committing" do
    operation = sync_operation({ "../context" => "# Context\n" })
    revision = adapter.revision

    expect { adapter.apply(operation) }
      .to raise_error(ProductFactory::ValidationError, "invalid Artifacts operation")
    expect(adapter.revision).to eq(revision)
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

  it "rejects a mapped page symlink without reading its target" do
    secret = File.join(root, "runner-secret")
    File.binwrite(secret, "do not read\n")
    ideas = File.join(root, "source/Ideas.md")
    File.unlink(ideas)
    File.symlink(secret, ideas)
    git!("add", "--", "Ideas.md", chdir: File.join(root, "source"))
    git!("-c", "user.name=Human", "-c", "user.email=human@example.com", "commit", "-qm", "Link Ideas",
         chdir: File.join(root, "source"))
    git!("push", "-q", "origin", "HEAD", chdir: File.join(root, "source"))

    expect { adapter.snapshot }
      .to raise_error(ProductFactory::ValidationError, "artifact page is a symlink: Ideas.md")
  end

  it "commits logical documents once and preserves human-owned Wiki pages byte-for-byte" do
    ideas = "<!-- product-factory:v1:artifact:ideas/index -->\n# Current Ideas\n"
    operation = sync_operation({ "ideas/index" => ideas })

    expect(adapter.apply(operation)).to be(true)
    expect(adapter.snapshot.fetch("documents")).to include("ideas/index" => ideas)
    expect(wiki_pages).to include("Home.md" => home, "_Sidebar.md" => sidebar, "Ideas.md" => ideas)
    expect(git!("rev-list", "--count", "HEAD", git_dir: remote).strip).to eq("2")
    expect(git!("log", "-1", "--format=%B", git_dir: remote).strip).to eq(<<~MESSAGE.strip)
      Update Product Factory artifacts

      Product-Factory-Operation: #{operation.id}
    MESSAGE
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
    operation = sync_operation({ "ideas/index" => ideas })
    adapter.apply(operation)
    applied_revision = adapter.revision

    expect(adapter.apply(operation)).to be(true)
    expect(adapter.revision).to eq(applied_revision)
  end

  it "rejects a completed operation after a later human-only commit" do
    operation = sync_operation({ "ideas/index" => "factory\n" })
    adapter.apply(operation)
    change_wiki("Home.md" => "# Changed by a human\n")

    expect { adapter.apply(operation) }
      .to raise_error(ProductFactory::ConflictError, "Artifacts changed after planning")
  end

  it "does not match when another managed document drifts after synchronization" do
    operation = sync_operation({ "ideas/index" => "factory\n" })
    adapter.apply(operation)
    change_wiki("Tickets.md" => "human\n")

    expect(adapter.matches?(operation)).to be(false)
  end

  it "rejects operations without the complete expected document hashes" do
    operation = sync_operation({ "ideas/index" => "factory\n" })
    incomplete = ProductFactory::Operation.new(
      kind: operation.kind, target: operation.target, attributes: operation.attributes.except("expected_hashes")
    )

    expect { adapter.matches?(incomplete) }
      .to raise_error(ProductFactory::ValidationError, "invalid Artifacts operation")
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
        "expected_hashes" => expected_hashes(snapshot, documents),
        "documents" => documents,
        "reason" => "synchronize Product Factory artifacts"
      }
    )
  end

  def expected_hashes(snapshot, documents)
    document_ids = ProductFactory::Artifacts::Planner::DOCUMENT_IDS | snapshot.fetch("documents").keys | documents.keys
    document_ids.to_h do |document|
      content = snapshot.fetch("documents")[document]
      [document, content && Digest::SHA256.hexdigest(content)]
    end
  end

  def change_wiki(**pages)
    checkout = File.join(root, "change-#{Dir.children(root).length}")
    git!("clone", "-q", remote, checkout)
    pages.each { |name, content| File.binwrite(File.join(checkout, name), content) }
    git!("add", "--", *pages.keys, chdir: checkout)
    git!("-c", "user.name=Human", "-c", "user.email=human@example.com", "commit", "-qm", "Human edit", chdir: checkout)
    git!("push", "-q", "origin", "HEAD", chdir: checkout)
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
