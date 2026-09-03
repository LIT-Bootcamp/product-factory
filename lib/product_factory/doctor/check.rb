# frozen_string_literal: true

module ProductFactory
  module Doctor
    Check = Data.define(:name, :status, :message)
  end
end
