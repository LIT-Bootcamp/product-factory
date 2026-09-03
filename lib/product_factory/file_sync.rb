# frozen_string_literal: true

module ProductFactory
  module FileSync
    RESOLUTIONS = %w[keep_local take_upstream manual_merge].freeze
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
