# frozen_string_literal: true

class FakeWiki
  def initialize
    @head = "WIKI-1"
    @pages = { "Home.md" => "# Human Home\n" }
  end

  def snapshot = { "head" => @head, "pages" => @pages }

  def apply(operation)
    return true if matches?(operation)

    @pages.merge!(operation.attributes.fetch("pages"))
    @head = "WIKI-#{@head.delete_prefix('WIKI-').to_i + 1}"
    true
  end

  def matches?(operation)
    operation.attributes.fetch("pages").all? { |name, content| @pages[name] == content }
  end

  def page_hashes
    @pages.except("Home.md").transform_values { |content| Digest::SHA256.hexdigest(content) }
  end

  attr_reader :head
end
