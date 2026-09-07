# frozen_string_literal: true

module ProductFactory
  module Artifacts
    SHA256 = /\A[0-9a-f]{64}\z/

    def self.build(config:, target_root:, shell:)
      case config.artifacts.fetch("adapter")
      when "repository"
        Repository.new(target_root:, root: config.artifacts.fetch("root"))
      when "wiki"
        Wiki.new(
          organization: config.github.fetch("organization"),
          repository: config.github.fetch("repository"),
          shell:
        )
      else
        raise ValidationError, "artifacts.adapter is unsupported"
      end
    end

    def self.valid_operation?(operation)
      attributes = operation.attributes
      operation.kind == Operation::SYNC_ARTIFACTS && operation.target == "artifacts:documents" &&
        attributes["adapter"].is_a?(String) && attributes["expected_revision"].is_a?(String) &&
        valid_hashes?(attributes["expected_hashes"]) &&
        valid_documents?(attributes["documents"], attributes["expected_hashes"])
    end

    def self.valid_document_id?(document)
      return false unless document.is_a?(String) && !document.empty? && !document.include?("\0")

      segments = document.split("/", -1)
      segments.all? do |segment|
        segment.match?(/\A[A-Za-z0-9][A-Za-z0-9._-]*\z/) &&
          !segment.end_with?(".md") && !segment.include?("--")
      end
    end

    def self.valid_hashes?(hashes)
      hashes.is_a?(Hash) && hashes.keys.all? { |document| valid_document_id?(document) } &&
        hashes.values.all? { |hash| hash.nil? || (hash.is_a?(String) && hash.match?(SHA256)) }
    end
    private_class_method :valid_hashes?

    def self.valid_documents?(documents, expected_hashes)
      documents.is_a?(Hash) && !documents.empty? &&
        documents.keys.all? { |document| valid_document_id?(document) && expected_hashes.key?(document) } &&
        documents.values.all?(String)
    end
    private_class_method :valid_documents?
  end
end
