# frozen_string_literal: true

class FakeArtifactStore
  attr_reader :requested_document_ids, :revision

  def initialize
    @revision = "ARTIFACTS-1"
    @documents = {}
  end

  def snapshot(document_ids: ProductFactory::Artifacts::Planner::DOCUMENT_IDS)
    @requested_document_ids = document_ids
    { "revision" => revision, "documents" => @documents.slice(*document_ids) }
  end

  def link(document) = "#{document}.md"

  def apply(operation)
    return true if matches?(operation)

    @documents.merge!(operation.attributes.fetch("documents"))
    @revision = "ARTIFACTS-#{revision.delete_prefix('ARTIFACTS-').to_i + 1}"
    true
  end

  def matches?(operation)
    operation.attributes.fetch("documents").all? do |document, content|
      @documents[document] == content
    end
  end

  def document_hashes
    @documents.transform_values { |content| Digest::SHA256.hexdigest(content) }
  end
end
