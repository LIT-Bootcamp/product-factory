# frozen_string_literal: true

require "open3"

RSpec.describe ProductFactory do
  describe "loading" do
    it "loads components on demand" do
      script = <<~RUBY
        def cli_loaded?
          $LOADED_FEATURES.any? { |path| path.end_with?("/product_factory/cli.rb") }
        end

        before = cli_loaded?
        ProductFactory::CLI
        puts [before, cli_loaded?].join(",")
      RUBY

      output, status = Open3.capture2e(
        RbConfig.ruby,
        "-I#{File.expand_path('../../lib', __dir__)}",
        "-rproduct_factory",
        "-e",
        script
      )

      expect([status.success?, output]).to eq([true, "false,true\n"])
    end
  end
end
