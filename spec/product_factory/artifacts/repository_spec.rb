# frozen_string_literal: true

RSpec.describe ProductFactory::Artifacts::Repository do
  subject(:adapter) { described_class.new(target_root: target, root:) }

  let(:target) { File.realpath(Dir.mktmpdir("product-factory-artifacts-")) }
  let(:root) { "product" }
  let(:documents) do
    {
      "index" => "<!-- product-factory:v1:artifact:index -->\n# Product Factory\n",
      "ideas/index" => "<!-- product-factory:v1:artifact:ideas/index -->\n# Ideas\n"
    }
  end

  after { FileUtils.rm_rf(target) }

  it "maps logical documents into the configured repository root" do
    operation = sync_operation(documents:)

    expect(adapter.apply(operation)).to be(true)
    expect(File.read(File.join(target, "product/README.md"))).to eq(documents.fetch("index"))
    expect(File.read(File.join(target, "product/ideas/README.md"))).to eq(documents.fetch("ideas/index"))
    expect(adapter.snapshot.fetch("documents")).to include(documents)
    expect(adapter.document_hashes.fetch("index")).to eq(Digest::SHA256.hexdigest(documents.fetch("index")))
  end

  it "does not replace an already synchronized document" do
    operation = sync_operation(documents:)
    adapter.apply(operation)
    path = File.join(target, "product/README.md")
    inode = File.stat(path).ino

    expect(adapter.apply(operation)).to be(true)
    expect(File.stat(path).ino).to eq(inode)
  end

  it "rejects a document changed after planning" do
    write(target, "product/README.md", "planned\n")
    operation = sync_operation(documents: { "index" => "factory\n" })
    write(target, "product/README.md", "human\n")

    expect { adapter.apply(operation) }
      .to raise_error(ProductFactory::ConflictError, "Artifacts changed after planning")
    expect(File.read(File.join(target, "product/README.md"))).to eq("human\n")
  end

  it "resumes after a previously completed document" do
    operation = sync_operation(documents:)
    write(target, "product/README.md", documents.fetch("index"))
    index = File.stat(File.join(target, "product/README.md")).ino

    expect(adapter.apply(operation)).to be(true)
    expect(File.stat(File.join(target, "product/README.md")).ino).to eq(index)
    expect(File.read(File.join(target, "product/ideas/README.md"))).to eq(documents.fetch("ideas/index"))
  end

  it "rejects absolute and traversal artifact roots" do
    [File.join(target, "product"), "../product"].each do |unsafe_root|
      expect { described_class.new(target_root: target, root: unsafe_root) }
        .to raise_error(ProductFactory::ValidationError, /unsafe factory target path/)
    end
  end

  it "rejects a symlinked artifact root without touching its destination" do
    in_tmp_repo do |outside|
      File.symlink(outside, File.join(target, "product"))

      expect { adapter.snapshot }.to raise_error(ProductFactory::ValidationError, /symlink/)
      expect(Dir.children(outside)).to be_empty
    end
  end

  it "rejects a symlinked artifact root ancestor without touching its destination" do
    in_tmp_repo do |outside|
      File.symlink(outside, File.join(target, "storage"))

      expect { described_class.new(target_root: target, root: "storage/product").snapshot }
        .to raise_error(ProductFactory::ValidationError, /symlink/)
      expect(Dir.children(outside)).to be_empty
    end
  end

  it "rejects a symlinked artifact target without touching its destination" do
    in_tmp_repo do |outside|
      write(outside, "victim.md", "human\n")
      FileUtils.mkdir_p(File.join(target, "product"))
      File.symlink(File.join(outside, "victim.md"), File.join(target, "product/README.md"))

      expect { adapter.apply(sync_operation(documents: { "index" => "factory\n" })) }
        .to raise_error(ProductFactory::ValidationError, /symlink/)
      expect(File.read(File.join(outside, "victim.md"))).to eq("human\n")
    end
  end

  it "leaves Git metadata unchanged" do
    git!("init", "-q", target)
    write(target, "README.md", "human\n")
    git!("add", "README.md", chdir: target)
    git!("-c", "user.name=Human", "-c", "user.email=human@example.com", "commit", "-qm", "Initial", chdir: target)
    git!("remote", "add", "origin", "https://example.test/product-factory.git", chdir: target)
    before = git_state

    expect(adapter.apply(sync_operation(documents:))).to be(true)
    expect(git_state).to eq(before)
  end

  private

  def sync_operation(documents:, snapshot: adapter.snapshot)
    ProductFactory::Operation.new(
      kind: ProductFactory::Operation::SYNC_ARTIFACTS,
      target: "artifacts:documents",
      attributes: {
        "adapter" => "repository",
        "expected_revision" => snapshot.fetch("revision"),
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

  def git_state
    {
      "HEAD" => File.binread(File.join(target, ".git/HEAD")),
      "config" => File.binread(File.join(target, ".git/config")),
      "remotes" => git!("remote", "-v", chdir: target)
    }
  end

  def git!(*, chdir: nil)
    output, error, status = Open3.capture3("git", *, chdir: chdir || target)
    raise error unless status.success?

    output
  end
end
