# frozen_string_literal: true

RSpec.describe ProductFactory::Validator do
  def install_valid_factory(root, pending_operations: [])
    installation = install_product_factory(root)
    installation.with("pending_operations" => pending_operations).write(root) if pending_operations.any?
  end

  it "accepts a complete installation" do
    in_tmp_repo do |root|
      install_valid_factory(root)

      expect(described_class.new(root: root).call).to be(true)
    end
  end

  it "rejects a modified factory file" do
    in_tmp_repo do |root|
      install_valid_factory(root)
      write(root, ".product-factory/runtime/lib/product_factory.rb", "changed\n")

      expect { described_class.new(root: root).call }
        .to raise_error(ProductFactory::ValidationError, %r{\.product-factory/runtime/lib/product_factory\.rb})
    end
  end

  it "never treats the human-owned config as a factory file" do
    in_tmp_repo do |root|
      install_valid_factory(root)
      config_path = File.join(root, ProductFactory::Config::PATH)
      ProductFactory::Installation.load(root).with(
        "factory_file_hashes" => {
          ProductFactory::Config::PATH => Digest::SHA256.file(config_path).hexdigest
        }
      ).write(root)

      expect { described_class.new(root: root).call }
        .to raise_error(ProductFactory::ValidationError, /invalid factory file path/)
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

  it "rejects a missing installed test runner" do
    in_tmp_repo do |root|
      install_valid_factory(root)
      File.delete(File.join(root, ProductFactory::FactoryFilesValidator::INTEGRATION_SPEC))

      expect { described_class.new(root: root).call }
        .to raise_error(ProductFactory::ValidationError, /integration_spec.rb/)
    end
  end

  it "rejects factory files reached through a symlinked directory" do
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
      previous = ENV.fetch("FACTORY_STUDENT_CREDENTIALS", nil)
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
