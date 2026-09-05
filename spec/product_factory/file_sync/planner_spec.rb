# frozen_string_literal: true

RSpec.describe ProductFactory::FileSync::Planner do
  let(:source) { File.realpath(Dir.mktmpdir("product-factory-source-")) }
  let(:target) { File.realpath(Dir.mktmpdir("product-factory-target-")) }

  after do
    [source, target].each { |directory| FileUtils.rm_rf(directory) }
  end

  def plan(sources:, installed_hashes: {}, resolutions: {})
    described_class.call(sources:, target_root: target, installed_hashes:, resolutions:)
  end

  it "plans a new factory file without changing the project" do
    write(source, "a.txt", "upstream\n")

    result = plan(sources: { "a.txt" => File.join(source, "a.txt") })

    expect(result.fetch(:operations).map(&:target)).to eq(["a.txt"])
    expect(File).not_to exist(File.join(target, "a.txt"))
  end

  it "preserves a local-only change" do
    write(source, "a.txt", "upstream\n")
    installed = Digest::SHA256.hexdigest("upstream\n")
    write(target, "a.txt", "local\n")

    result = plan(
      sources: { "a.txt" => File.join(source, "a.txt") },
      installed_hashes: { "a.txt" => installed }
    )

    expect(result.fetch(:operations)).to be_empty
    expect(result.fetch(:conflicts)).to be_empty
  end

  it "reports concurrent local and upstream changes" do
    write(source, "a.txt", "upstream-v2\n")
    write(target, "a.txt", "local-v2\n")
    installed = Digest::SHA256.hexdigest("shared-v1\n")

    result = plan(
      sources: { "a.txt" => File.join(source, "a.txt") },
      installed_hashes: { "a.txt" => installed }
    )

    expect(result.fetch(:conflicts)).to contain_exactly(
      include("path" => "a.txt", "installed_hash" => installed, "resolution" => nil)
    )
  end

  it "applies the selected upstream resolution to a conflict" do
    write(source, "a.txt", "upstream-v2\n")
    write(target, "a.txt", "local-v2\n")
    installed = Digest::SHA256.hexdigest("shared-v1\n")

    result = plan(
      sources: { "a.txt" => File.join(source, "a.txt") },
      installed_hashes: { "a.txt" => installed },
      resolutions: { "a.txt" => "take_upstream" }
    )

    expect(result.fetch(:conflicts)).to be_empty
    expect(result.fetch(:operations).map(&:target)).to eq(["a.txt"])
  end

  it "waits for the recorded manual merge" do
    write(source, "a.txt", "upstream-v2\n")
    write(target, "a.txt", "local-v2\n")
    installed = Digest::SHA256.hexdigest("shared-v1\n")
    merged = Digest::SHA256.hexdigest("merged\n")
    sources = { "a.txt" => File.join(source, "a.txt") }
    resolutions = { "a.txt" => { "resolution" => "manual_merge", "merged_hash" => merged } }

    expect(plan(sources:, installed_hashes: { "a.txt" => installed }, resolutions:).fetch(:conflicts)).not_to be_empty

    write(target, "a.txt", "merged\n")
    result = plan(sources:, installed_hashes: { "a.txt" => installed }, resolutions:)
    expect(result.fetch(:conflicts)).to be_empty
    expect(result.fetch(:operations)).to be_empty
  end

  it "rejects unknown resolutions" do
    write(source, "a.txt", "upstream\n")

    expect do
      plan(sources: { "a.txt" => File.join(source, "a.txt") }, resolutions: { "a.txt" => "overwrite" })
    end.to raise_error(ProductFactory::ValidationError, /invalid resolution/)
  end

  it "deletes only unchanged files removed from the distribution" do
    write(target, "remove.txt", "installed\n")
    write(target, "keep.txt", "changed\n")
    installed = {
      "remove.txt" => Digest::SHA256.hexdigest("installed\n"),
      "keep.txt" => Digest::SHA256.hexdigest("original\n")
    }

    result = plan(sources: {}, installed_hashes: installed)

    expect(result.fetch(:operations).map { |operation| [operation.kind, operation.target] })
      .to eq([["delete_file", "remove.txt"]])
    expect(result.fetch(:conflicts).map { |conflict| conflict.fetch("path") }).to eq(["keep.txt"])
  end

  it "captures source bytes, mode, and order in the immutable plan" do
    write(source, "a.txt", "captured-a\n")
    write(source, "b.txt", "captured-b\n")
    File.chmod(0o751, File.join(source, "a.txt"))
    sources = { "b.txt" => File.join(source, "b.txt"), "a.txt" => File.join(source, "a.txt") }

    result = plan(sources:)
    operation = result.fetch(:operations).first
    sources.clear

    expect(result.fetch(:operations).map(&:target)).to eq(%w[a.txt b.txt])
    expect(operation.attributes.fetch("content_base64").unpack1("m0")).to eq("captured-a\n")
    expect(operation.attributes.fetch("mode")).to eq(0o751)
  end

  it "rejects unsafe target paths" do
    write(source, "a.txt", "upstream\n")

    expect do
      plan(sources: { "../escape.txt" => File.join(source, "a.txt") })
    end.to raise_error(ProductFactory::ValidationError, /unsafe factory target path/)
  end

  it "rejects source files reached through a symlink" do
    write(source, "real.txt", "upstream\n")
    File.symlink(File.join(source, "real.txt"), File.join(source, "linked.txt"))

    expect do
      plan(sources: { "a.txt" => File.join(source, "linked.txt") })
    end.to raise_error(ProductFactory::ValidationError, /source path contains a symlink/)
  end
end
