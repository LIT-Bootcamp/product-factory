runtime_lib = File.expand_path("../runtime/lib", __dir__)
$LOAD_PATH.unshift(runtime_lib)
require "product_factory"

RSpec.describe "installed Product Factory runtime" do
  it "loads and validates its installation" do
    root = File.expand_path("../..", __dir__)

    expect(ProductFactory::Config.load(root)).to be_a(ProductFactory::Config)
    expect(ProductFactory::Installation.load(root)).to be_a(ProductFactory::Installation)
    expect(ProductFactory::Validator.new(root: root).call).to eq(true)
  end
end
