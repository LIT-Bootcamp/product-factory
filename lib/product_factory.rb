# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "securerandom"
require "tempfile"
require "thor"
require "time"
require "tmpdir"
require "yaml"
require "zeitwerk"

loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect("cli" => "CLI", "github" => "GitHub")
loader.setup

module ProductFactory
end
