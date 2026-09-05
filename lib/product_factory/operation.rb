# frozen_string_literal: true

module ProductFactory
  class Operation
    WRITE_FILE = "write_file"
    DELETE_FILE = "delete_file"
    SEED_CONFIG = "seed_config"
    WRITE_INSTALLATION = "write_installation"
    ENSURE_ISSUE_TYPE = "ensure_issue_type"
    ENSURE_PROJECT = "ensure_project"
    ENSURE_PROJECT_FIELD = "ensure_project_field"
    ENSURE_PROJECT_VIEW = "ensure_project_view"
    SYNC_WIKI = "sync_wiki"
    GITHUB_KINDS = [ENSURE_ISSUE_TYPE, ENSURE_PROJECT, ENSURE_PROJECT_FIELD, ENSURE_PROJECT_VIEW].freeze

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
