require "fileutils"
require "stringio"
require "tmpdir"
require_relative "../lib/product_factory"

module SpecHelpers
  def in_tmp_repo
    Dir.mktmpdir("product-factory-test") { |root| yield root }
  end

  def write(root, relative_path, content)
    path = File.join(root, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end
end

RSpec.configure do |config|
  config.include SpecHelpers
end
