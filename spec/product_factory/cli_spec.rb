# frozen_string_literal: true

RSpec.describe ProductFactory::CLI do
  describe ".start" do
    it "prints the version and succeeds" do
      output = StringIO.new

      status = described_class.start(["--version"], output: output)

      expect(status).to eq(0)
      expect(output.string).to eq("product-factory #{ProductFactory::VERSION}\n")
    end

    it "returns a usage error for an unknown command" do
      error = StringIO.new

      status = described_class.start(["unknown"], error: error)

      expect(status).to eq(64)
      expect(error.string).to include("Unknown command: unknown")
    end

    it "returns success after printing help" do
      output = StringIO.new

      status = described_class.start(["--help"], output: output)

      expect(status).to eq(0)
      expect(output.string).to include("product-factory commands:")
    end

    it "runs installed tests with argument arrays and returns their status" do
      in_tmp_repo do |root|
        write(root, ProductFactory::Installation::PATH, "schema_version: 1\n")
        allow(ProductFactory::Validator).to receive(:call).and_return(true)
        process_status = instance_double(Process::Status, exitstatus: 3)
        allow(Open3).to receive(:capture3)
          .and_return(["out", "err", process_status])
        output = StringIO.new
        error = StringIO.new

        expect(described_class.start(["test"], cwd: root, output:, error:)).to eq(3)
        expect(output.string).to eq("out")
        expect(error.string).to eq("err")
        expect(ProductFactory::Validator).to have_received(:call).with(root: root)
        expect(Open3).to have_received(:capture3)
          .with("bundle", "exec", "rspec", ".product-factory/spec/runtime_spec.rb", chdir: root)
      end
    end

    it "does not execute an installed test through symlinked state" do
      in_tmp_repo do |root|
        outside = File.realpath(Dir.mktmpdir("product-factory-state-"))
        File.write(File.join(outside, "installation.yml"), "schema_version: 1\n")
        write(root, ProductFactory::Config::PATH, File.read(File.expand_path("../../templates/config.yml", __dir__)))
        File.symlink(File.join(outside, "installation.yml"), File.join(root, ProductFactory::Installation::PATH))
        allow(Open3).to receive(:capture3)
        error = StringIO.new

        expect(described_class.start(["test"], cwd: root, error:)).to eq(1)
        expect(error.string).to include("symlink")
        expect(Open3).not_to have_received(:capture3)
      ensure
        FileUtils.remove_entry(outside) if outside && File.exist?(outside)
      end
    end
  end
end
