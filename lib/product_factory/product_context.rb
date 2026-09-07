# frozen_string_literal: true

module ProductFactory
  class ProductContext < Service
    REQUIRED_ANSWERS = %w[
      mission target_users primary_user_problem desired_outcome markets_and_languages
    ].freeze
    OPTIONAL_ANSWERS = %w[competitor_seeds constraints non_goals].freeze

    def self.document_ids(config)
      landing_id = config.product.fetch("context_document")
      [landing_id, "#{landing_id}/v1"]
    end

    def initialize(config:, snapshot:, answers:, actor:, run_id:, recorded_at:, version_link:)
      super()
      @config = config
      @snapshot = snapshot
      @answers = answers
      @actor = actor
      @run_id = run_id
      @recorded_at = recorded_at
      @version_link = version_link
    end

    def call
      documents = { landing_id => render(landing_lines) }
      documents[version_id] = render(version_lines) unless version_exists?
      documents
    end

    private

    attr_reader :config, :snapshot, :answers, :actor, :run_id, :recorded_at, :version_link

    def landing_id
      @landing_id ||= config.product.fetch("context_document")
    end

    def version_id
      @version_id ||= "#{landing_id}/v1"
    end

    def version_exists?
      snapshot.fetch("documents", {}).key?(version_id)
    end

    def landing_lines
      [
        marker(landing_id),
        "# Product Context — #{product_name}",
        "",
        "Current version: [v1](#{version_link})",
        "",
        required_answer("mission"),
        ""
      ]
    end

    def version_lines
      [
        marker(version_id),
        "# Product Context — #{product_name}",
        "",
        *metadata_lines,
        *section_lines
      ]
    end

    def metadata_lines
      [
        "| Field | Value |",
        "|---|---|",
        "| Version | 1 |",
        "| Created at | #{table_value(recorded_at)} |",
        "| Created by | #{table_value(actor)} |",
        "| Factory run | #{table_value(run_id)} |",
        "| Change reason | Initial Product Context |",
        ""
      ]
    end

    def section_lines
      [
        content_section("Mission", required_answer("mission")),
        content_section("Target Users", required_answer("target_users")),
        content_section("Primary User Problem", required_answer("primary_user_problem")),
        content_section("Desired Outcome", required_answer("desired_outcome")),
        content_section("Markets and Languages", required_answer("markets_and_languages")),
        content_section("Competitor Seeds", optional_answer("competitor_seeds")),
        content_section("Constraints", optional_answer("constraints")),
        content_section("Non-goals", optional_answer("non_goals"))
      ].flatten
    end

    def content_section(title, body)
      ["## #{title}", body, ""]
    end

    def render(lines)
      lines.join("\n")
    end

    def required_answer(key)
      value = answers.fetch(key, nil)
      return value if value.is_a?(String) && !value.empty?

      raise ValidationError, "#{key} must be a non-empty string"
    end

    def optional_answer(key)
      value = answers.fetch(key, nil)
      return value if value.is_a?(String) && !value.empty?

      "Not provided"
    end

    def product_name = config.product.fetch("name")
    def marker(document) = format("<!-- product-factory:v1:artifact:%<document>s -->", document:)
    def table_value(value) = value.to_s.gsub("|", "\\|")
  end
end
