# frozen_string_literal: true

module LiveGitHub
  REPOSITORY = "LIT-Bootcamp/product-factory-sandbox"

  def live_github_enabled? = ENV["PRODUCT_FACTORY_LIVE_GITHUB"] == REPOSITORY
end

RSpec.configure do |config|
  config.include LiveGitHub
  config.filter_run_excluding(live_github: true) unless ENV["PRODUCT_FACTORY_LIVE_GITHUB"] == LiveGitHub::REPOSITORY
end
