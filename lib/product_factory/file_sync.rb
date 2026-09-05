# frozen_string_literal: true

module ProductFactory
  module FileSync
    KEEP_LOCAL = "keep_local"
    TAKE_UPSTREAM = "take_upstream"
    MANUAL_MERGE = "manual_merge"
    RESOLUTIONS = [KEEP_LOCAL, TAKE_UPSTREAM, MANUAL_MERGE].freeze
    TARGETS = ["bin/product-factory"].freeze
    TARGET_PREFIXES = %w[
      .product-factory/runtime/
      .product-factory/schemas/
      .product-factory/spec/
    ].freeze

    def self.factory_path?(path)
      TARGETS.include?(path) || TARGET_PREFIXES.any? { |prefix| path.start_with?(prefix) }
    end
  end
end
