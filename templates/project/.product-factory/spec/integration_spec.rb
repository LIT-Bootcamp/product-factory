# frozen_string_literal: true

require_relative "../runtime/lib/product_factory"

RSpec.describe "installed Product Factory integration" do
  let(:project_root) { File.expand_path("../..", __dir__) }

  it "loads the project's configuration" do
    expect(ProductFactory::Config.load(project_root)).to be_a(ProductFactory::Config)
  end

  it "loads the Product Factory installation state" do
    expect(ProductFactory::Installation.load(project_root)).to be_a(ProductFactory::Installation)
  end
end
