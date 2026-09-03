# frozen_string_literal: true

require "securerandom"

module ProductFactory
  class RunId
    def self.generate(clock:, random: SecureRandom)
      "RUN-#{clock.call.utc.strftime('%Y%m%dT%H%M%SZ')}-#{random.hex(4)}"
    end
  end
end
