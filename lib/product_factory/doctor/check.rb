# frozen_string_literal: true

module ProductFactory
  class Doctor
    Check = Data.define(:name, :status, :message)
  end
end
