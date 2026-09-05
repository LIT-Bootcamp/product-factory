# frozen_string_literal: true

module FileHelpers
  FACTORY_ROOT = File.expand_path("../..", __dir__)

  def in_tmp_repo
    Dir.mktmpdir("product-factory-test") { |root| yield File.realpath(root) }
  end

  def write(root, relative_path, content)
    path = File.join(root, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  def install_product_factory(root)
    setup = ProductFactory::Setup::Runner.new(
      distribution_root: FACTORY_ROOT,
      target_root: root,
      input: StringIO.new("yes\n"),
      output: StringIO.new,
      clock: -> { Time.utc(2026, 9, 2) }
    )

    raise "Product Factory test setup failed" unless setup.apply(setup.plan) == :success

    ProductFactory::Installation.load(root)
  end
end
