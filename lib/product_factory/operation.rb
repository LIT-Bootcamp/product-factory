require "digest"
require "json"

module ProductFactory
  class Operation
    attr_reader :kind, :target, :attributes

    def initialize(kind:, target:, attributes: {})
      @kind = kind.to_s.dup.freeze
      @target = target.to_s.dup.freeze
      @attributes = canonical(attributes)
      freeze
    end

    def id = Digest::SHA256.hexdigest(JSON.generate(to_h))[0, 20]
    def to_h = { "kind" => kind, "target" => target, "attributes" => attributes }

    private

    def canonical(value)
      case value
      when Hash
        value.map { |key, item| [key.to_s.dup.freeze, canonical(item)] }
          .sort_by(&:first).to_h.freeze
      when Array then value.map { |item| canonical(item) }.freeze
      when String then value.dup.freeze
      else value
      end
    end
  end
end
