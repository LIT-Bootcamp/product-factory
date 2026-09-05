# frozen_string_literal: true

require "fileutils"
require "open3"
require "stringio"
require "tmpdir"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "product_factory"
require_relative "support/file_helpers"
require_relative "support/rspec"
