# frozen_string_literal: true

RSpec.describe ProductFactory::FileSync::Target do
  subject(:target) { described_class.new(root:) }

  let(:root) { File.realpath(Dir.mktmpdir("product-factory-target-")) }

  after { FileUtils.rm_rf(root) }

  def write_operation(path, content: "new\n", mode: 0o644)
    ProductFactory::Operation.new(
      kind: "write_file",
      target: path,
      attributes: { "content_base64" => [content].pack("m0"), "expected_local_hash" => nil, "mode" => mode }
    )
  end

  it "atomically replaces a file with the captured bytes and mode" do
    write(root, "a.txt", "old\n")
    old_inode = File.stat(File.join(root, "a.txt")).ino

    target.apply(write_operation("a.txt", content: "captured\n", mode: 0o751))

    expect(File.binread(File.join(root, "a.txt"))).to eq("captured\n")
    expect(File.stat(File.join(root, "a.txt")).mode & 0o777).to eq(0o751)
    expect(File.stat(File.join(root, "a.txt")).ino).not_to eq(old_inode)
  end

  it "removes empty parent directories after deleting a file" do
    write(root, "nested/a.txt", "old\n")
    operation = ProductFactory::Operation.new(
      kind: "delete_file",
      target: "nested/a.txt",
      attributes: { "expected_local_hash" => Digest::SHA256.hexdigest("old\n") }
    )

    target.apply(operation)

    expect(File).not_to exist(File.join(root, "nested/a.txt"))
    expect(Dir).not_to exist(File.join(root, "nested"))
  end

  it "rejects traversal and absolute paths" do
    ["../escape.txt", File.join(root, "absolute.txt")].each do |path|
      expect { target.apply(write_operation(path)) }
        .to raise_error(ProductFactory::ValidationError, /unsafe factory target path/)
    end
  end

  it "does not follow a target symlink" do
    in_tmp_repo do |outside|
      write(outside, "victim.txt", "outside\n")
      File.symlink(File.join(outside, "victim.txt"), File.join(root, "a.txt"))

      expect { target.apply(write_operation("a.txt")) }
        .to raise_error(ProductFactory::ValidationError, /target is a symlink/)
      expect(File.read(File.join(outside, "victim.txt"))).to eq("outside\n")
    end
  end

  it "does not follow a symlinked parent directory" do
    in_tmp_repo do |outside|
      File.symlink(outside, File.join(root, "nested"))

      expect { target.apply(write_operation("nested/a.txt")) }
        .to raise_error(ProductFactory::ValidationError, /target.*symlink/)
      expect(File).not_to exist(File.join(outside, "a.txt"))
    end
  end

  it "rejects malformed write operations" do
    [nil, [], { "content_base64" => 123, "mode" => 0o644 }].each do |attributes|
      operation = ProductFactory::Operation.new(kind: "write_file", target: "a.txt", attributes:)

      expect { target.apply(operation) }.to raise_error(ProductFactory::ValidationError)
    end
  end
end
