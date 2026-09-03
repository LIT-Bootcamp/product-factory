RSpec.describe ProductFactory::Validator do
  def install_valid_factory(root, pending_operations: [])
    write(root, ProductFactory::Config::PATH, File.read(File.expand_path("../../templates/config.yml", __dir__)))
    managed_path = ".product-factory/runtime/lib/product_factory.rb"
    write(root, managed_path, "managed\n")
    ProductFactory::Installation.empty.with(
      "managed_file_hashes" => { managed_path => Digest::SHA256.hexdigest("managed\n") },
      "pending_operations" => pending_operations,
      "last_successful_setup_run" => "RUN-1"
    ).write(root)
    ProductFactory::Journal.new(
      path: File.join(root, ".product-factory-journal.jsonl"),
      clock: -> { Time.utc(2026, 9, 2) }
    ).append(event: "run_completed", run_id: "RUN-1", status: "success")
  end

  it "accepts a complete installation" do
    in_tmp_repo do |root|
      install_valid_factory(root)

      expect(described_class.new(root: root).call).to eq(true)
    end
  end

  it "rejects a modified managed file" do
    in_tmp_repo do |root|
      config_template = File.expand_path("../../templates/config.yml", __dir__)
      write(root, ".product-factory/config.yml", File.read(config_template))
      write(root, ".product-factory/runtime/lib/product_factory.rb", "changed\n")
      ProductFactory::Installation.empty.with(
        "managed_file_hashes" => { ".product-factory/runtime/lib/product_factory.rb" => "0" * 64 }
      ).write(root)

      expect { described_class.new(root: root).call }
        .to raise_error(ProductFactory::ValidationError, /\.product-factory\/runtime\/lib\/product_factory\.rb/)
    end
  end

  it "requires an intact journal and no pending operations" do
    in_tmp_repo do |root|
      install_valid_factory(root, pending_operations: [{ "id" => "pending" }])

      expect { described_class.new(root: root).call }
        .to raise_error(ProductFactory::ValidationError, /pending operations/)

      ProductFactory::Installation.load(root).with("pending_operations" => []).write(root)
      File.write(File.join(root, ".product-factory-journal.jsonl"), "{")
      expect { described_class.new(root: root).call }
        .to raise_error(ProductFactory::ValidationError, /journal line 1/)
    end
  end

  it "rejects a missing journal" do
    in_tmp_repo do |root|
      install_valid_factory(root)
      File.delete(File.join(root, ".product-factory-journal.jsonl"))

      expect { described_class.new(root: root).call }
        .to raise_error(ProductFactory::ValidationError, /Missing.*journal/)
    end
  end

  it "rejects managed files reached through a symlinked directory" do
    in_tmp_repo do |root|
      install_valid_factory(root)
      runtime = File.join(root, ".product-factory/runtime")
      outside = File.realpath(Dir.mktmpdir("product-factory-runtime-"))
      FileUtils.mv(runtime, File.join(outside, "runtime"))
      File.symlink(File.join(outside, "runtime"), runtime)

      expect { described_class.new(root: root).call }
        .to raise_error(ProductFactory::ValidationError, /symlink/)
    ensure
      FileUtils.remove_entry(outside) if outside && File.exist?(outside)
    end
  end

  it "rejects credential values stored in factory state" do
    in_tmp_repo do |root|
      install_valid_factory(root)
      secret = "factory\"test\\secret"
      previous = ENV["FACTORY_STUDENT_CREDENTIALS"]
      ENV["FACTORY_STUDENT_CREDENTIALS"] = secret
      ProductFactory::Installation.load(root)
        .with("github_resource_ids" => { "leak" => secret })
        .write(root)

      expect { described_class.new(root: root).call }
        .to raise_error(ProductFactory::ValidationError, /credential value/)
    ensure
      previous.nil? ? ENV.delete("FACTORY_STUDENT_CREDENTIALS") : ENV["FACTORY_STUDENT_CREDENTIALS"] = previous
    end
  end

  it "requires journal success for the installation run" do
    in_tmp_repo do |root|
      install_valid_factory(root)
      ProductFactory::Installation.load(root)
        .with("last_successful_setup_run" => "RUN-OTHER")
        .write(root)

      expect { described_class.new(root: root).call }
        .to raise_error(ProductFactory::ValidationError, /successful setup run/)
    end
  end
end
