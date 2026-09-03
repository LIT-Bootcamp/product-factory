# frozen_string_literal: true

require "fileutils"
require "open3"
require "stringio"
require "tmpdir"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "product_factory"

module SpecHelpers
  def in_tmp_repo
    Dir.mktmpdir("product-factory-test") { |root| yield File.realpath(root) }
  end

  def write(root, relative_path, content)
    path = File.join(root, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end
end

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.include SpecHelpers
  config.order = :random

  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  Kernel.srand(config.seed)
end
