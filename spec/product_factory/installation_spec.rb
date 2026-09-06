# frozen_string_literal: true

RSpec.describe ProductFactory::Installation do
  it "loads missing state as empty and round-trips atomically" do
    in_tmp_repo do |root|
      installation = described_class.load(root)
      installation = installation.with(
        "factory_version" => "0.1.0",
        "factory_file_hashes" => { ".product-factory/runtime/lib/product_factory.rb" => "abc" }
      )

      installation.write(root)
      loaded = described_class.load(root)

      expect(loaded.factory_version).to eq("0.1.0")
      expect(loaded.factory_file_hashes).to eq({ ".product-factory/runtime/lib/product_factory.rb" => "abc" })
      expect(File).not_to exist(File.join(root, ".product-factory/installation.yml.tmp"))
    end
  end

  it "keeps the original state unchanged when deriving updated state" do
    original = described_class.empty

    updated = original.with("factory_version" => "0.1.0")

    expect(original.factory_version).to be_nil
    expect(updated.factory_version).to eq("0.1.0")
  end

  it "round-trips remote state without exposing it for mutation" do
    in_tmp_repo do |root|
      state = {
        "github_resource_ids" => { "project" => "P_1" },
        "github_resource_hashes" => { "project" => "abc" },
        "wiki_page_hashes" => { "_Sidebar.md" => "def" },
        "wiki_head" => "0123456789"
      }

      described_class.empty.with(state).write(root)
      loaded = described_class.load(root)
      exposed = loaded.to_h
      exposed.fetch("github_resource_ids")["project"] = "changed"
      exposed.fetch("wiki_page_hashes")["_Sidebar.md"] = "changed"

      expect(loaded.to_h).to include(state)
    end
  end

  it "rejects Ruby objects through safe YAML loading" do
    in_tmp_repo do |root|
      write(root, described_class::PATH, "--- !ruby/object:Object {}\n")

      expect { described_class.load(root) }
        .to raise_error(ProductFactory::ValidationError, %r{Invalid \.product-factory/installation\.yml})
    end
  end

  it "rejects a non-mapping document root" do
    in_tmp_repo do |root|
      write(root, described_class::PATH, "true\n")

      expect { described_class.load(root) }
        .to raise_error(ProductFactory::ValidationError, "installation state must be a mapping")
    end
  end

  it "does not expose nested state for mutation" do
    installation = described_class.empty.with(
      "factory_file_hashes" => { "factory.rb" => "abc" },
      "pending_operations" => [{ "id" => "operation-1" }]
    )

    exposed = installation.to_h
    exposed.fetch("factory_file_hashes")["factory.rb"] = "changed"
    exposed.fetch("pending_operations").first["id"] = "changed"

    expect(installation.factory_file_hashes).to eq({ "factory.rb" => "abc" })
    expect(installation.pending_operations).to eq([{ "id" => "operation-1" }])
  end

  it "does not follow a predictable temporary-file symlink" do
    in_tmp_repo do |root|
      FileUtils.mkdir_p(File.join(root, ".product-factory"))
      outside = File.join(root, "outside.yml")
      File.write(outside, "keep\n")
      File.symlink(outside, File.join(root, "#{described_class::PATH}.tmp"))

      described_class.empty.write(root)

      expect(File.read(outside)).to eq("keep\n")
      expect(described_class.load(root).to_h).to eq(described_class.empty.to_h)
    end
  end

  it "rejects a symlinked state directory" do
    in_tmp_repo do |root|
      outside = File.realpath(Dir.mktmpdir("product-factory-installation-"))
      File.symlink(outside, File.join(root, ".product-factory"))

      expect { described_class.empty.write(root) }
        .to raise_error(ProductFactory::ValidationError, /symlink/)
      expect(Dir.children(outside)).to be_empty
    ensure
      FileUtils.remove_entry(outside) if outside && File.exist?(outside)
    end
  end
end
