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
        process_status = instance_double(Process::Status, exitstatus: 3)
        expect(Open3).to receive(:capture3)
          .with("bundle", "exec", "rspec", ".product-factory/spec/runtime_spec.rb", chdir: root)
          .and_return(["out", "err", process_status])
        output = StringIO.new
        error = StringIO.new

        expect(described_class.start(["test"], cwd: root, output:, error:)).to eq(3)
        expect(output.string).to eq("out")
        expect(error.string).to eq("err")
      end
    end
  end
end
