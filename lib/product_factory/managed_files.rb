# frozen_string_literal: true

module ProductFactory
  class ManagedFiles
    RESOLUTIONS = %w[keep_local take_upstream manual_merge].freeze

    def initialize(sources:)
      @sources = sources.to_h do |target, source|
        [target.to_s.dup.freeze, source.to_s.dup.freeze]
      end.freeze
      @store = Store.new
    end

    def plan(target_root:, installed_hashes:, resolutions: {})
      Planner.new(sources: @sources, store: @store).call(
        target_root:,
        installed_hashes:,
        resolutions:
      )
    end

    def apply(operation, target_root:)
      @store.apply(operation, target_root:)
    end

    def current_hash(target_root:, path:)
      current_state(target_root:, path:)&.fetch(:hash)
    end

    def current_state(target_root:, path:)
      @store.current_state(target_root:, path:)
    end
  end
end
