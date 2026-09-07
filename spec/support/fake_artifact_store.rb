# frozen_string_literal: true

class FakeArtifactStore
  attr_reader :revision

  def initialize
    @revision = "ARTIFACTS-1"
    @documents = {}
  end

  def snapshot = { "revision" => revision, "documents" => @documents }

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
