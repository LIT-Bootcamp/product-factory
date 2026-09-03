RSpec.describe ProductFactory::Installation do
  it "loads missing state as empty and round-trips atomically" do
    in_tmp_repo do |root|
      installation = described_class.load(root)
      installation = installation.with(
        "factory_version" => "0.1.0",
        "managed_file_hashes" => { ".product-factory/runtime/lib/product_factory.rb" => "abc" }
      )

      installation.write(root)
      loaded = described_class.load(root)

      expect(loaded.factory_version).to eq("0.1.0")
      expect(loaded.managed_file_hashes).to eq({ ".product-factory/runtime/lib/product_factory.rb" => "abc" })
      expect(File).not_to exist(File.join(root, ".product-factory/installation.yml.tmp"))
    end
  end

  it "keeps the original state unchanged when deriving updated state" do
    original = described_class.empty

    updated = original.with("factory_version" => "0.1.0")

    expect(original.factory_version).to be_nil
    expect(updated.factory_version).to eq("0.1.0")
  end

  it "rejects Ruby objects through safe YAML loading" do
    in_tmp_repo do |root|
      write(root, described_class::PATH, "--- !ruby/object:Object {}\n")

      expect { described_class.load(root) }
        .to raise_error(ProductFactory::ValidationError, /Invalid \.product-factory\/installation\.yml/)
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
      "managed_file_hashes" => { "managed.rb" => "abc" },
      "pending_operations" => [{ "id" => "operation-1" }]
    )

    exposed = installation.to_h
    exposed.fetch("managed_file_hashes")["managed.rb"] = "changed"
    exposed.fetch("pending_operations").first["id"] = "changed"

    expect(installation.managed_file_hashes).to eq({ "managed.rb" => "abc" })
    expect(installation.pending_operations).to eq([{ "id" => "operation-1" }])
  end
end
