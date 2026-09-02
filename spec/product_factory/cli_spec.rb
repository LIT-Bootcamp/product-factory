require "spec_helper"

RSpec.describe ProductFactory::CLI do
  describe ".start" do
    it "prints the version and succeeds" do
      output = StringIO.new

      status = ProductFactory::CLI.start(["--version"], output: output)

      expect(status).to eq(0)
      expect(output.string).to eq("product-factory #{ProductFactory::VERSION}\n")
    end

    it "returns a usage error for an unknown command" do
      error = StringIO.new

      status = ProductFactory::CLI.start(["unknown"], error: error)

      expect(status).to eq(64)
      expect(error.string).to include("Unknown command: unknown")
    end

    it "returns success after printing help" do
      output = StringIO.new

      status = ProductFactory::CLI.start(["--help"], output: output)

      expect(status).to eq(0)
      expect(output.string).to include("product-factory commands:")
    end
  end
end
