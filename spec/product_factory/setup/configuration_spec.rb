# frozen_string_literal: true

RSpec.describe ProductFactory::Setup::Configuration do
  subject(:configuration) do
    described_class.call(
      distribution:,
      target_root:, input:, output:, github_client:, shell:
    )
  end

  let(:target_root) { Dir.mktmpdir("product-factory-configuration") }
  let(:input) { StringIO.new("Bootcamper\n") }
  let(:output) { StringIO.new }
  let(:github_client) { instance_double(ProductFactory::GitHub::Client) }
  let(:shell) { instance_double(ProductFactory::StreamShell) }

  before do
    status = instance_double(Process::Status, success?: true, exitstatus: 0)
    allow(shell).to receive(:capture3).and_return(["git@github.com:LIT-Bootcamp/bootcamper.git\n", "", status])
    allow(github_client).to receive(:get).with("repos/LIT-Bootcamp/bootcamper").and_return(
      "id" => 1, "name" => "bootcamper", "full_name" => "LIT-Bootcamp/bootcamper"
    )
  end

  after { FileUtils.remove_entry(target_root) }

  it "builds first-run configuration in memory from the Git remote" do
    result = configuration
    data = YAML.safe_load(result.fetch(:bytes), aliases: false)

    expect(result.fetch(:config).github).to eq(
      "organization" => "LIT-Bootcamp",
      "repository" => "bootcamper",
      "project_title" => "Bootcamper Product Factory"
    )
    expect(data.dig("product", "name")).to eq("Bootcamper")
    expect(result.fetch(:repository)).to include("full_name" => "LIT-Bootcamp/bootcamper")
    expect(Dir.children(target_root)).to be_empty
    expect(output.string).to eq("Product name [Bootcamper]: ")
  end

  it "uses a titleized repository name when the answer is blank" do
    status = instance_double(Process::Status, success?: true, exitstatus: 0)
    allow(shell).to receive(:capture3).and_return(["https://github.com/LIT-Bootcamp/mentor_portal.git\n", "", status])
    allow(github_client).to receive(:get).with("repos/LIT-Bootcamp/mentor_portal").and_return(
      "id" => 2, "name" => "mentor_portal", "full_name" => "LIT-Bootcamp/mentor_portal"
    )
    allow(input).to receive(:gets).and_return("\n")

    result = configuration

    expect(result.fetch(:config).product.fetch("name")).to eq("Mentor Portal")
    expect(result.fetch(:config).github.fetch("project_title")).to eq("Mentor Portal Product Factory")
  end

  it "loads existing bytes without prompting" do
    bytes = distribution.config_bytes.sub("example-org", "LIT-Bootcamp").sub("example-repo", "bootcamper")
    write(target_root, ProductFactory::Config::PATH, bytes)

    result = configuration

    expect(result.fetch(:bytes)).to eq(bytes)
    expect(output.string).to be_empty
  end

  it "rejects a config that differs from the detected remote" do
    write(target_root, ProductFactory::Config::PATH, distribution.config_bytes)

    expect { configuration }
      .to raise_error(ProductFactory::ValidationError, "configured GitHub repository does not match origin")
  end

  def distribution = ProductFactory::Distribution.new(FileHelpers::FACTORY_ROOT)
end
