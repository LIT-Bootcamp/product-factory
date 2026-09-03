# frozen_string_literal: true

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.include FileHelpers
  config.order = :random

  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  Kernel.srand(config.seed)
end
