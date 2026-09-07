# frozen_string_literal: true

module ProductFactory
  module Artifacts
    class Planner < Service
      DOCUMENT_IDS = %w[
        index setup-log ideas/index epics/index tickets/index research/index factory-runs/index
      ].freeze

      def initialize(
        schema:, snapshot:, installed_hashes:, adoptions:, run_id:, recorded_at:, adapter:, operation_summaries:,
        failures:
      )
        super()
        @schema = schema
        @snapshot = snapshot
        @installed_hashes = installed_hashes
        @adoptions = adoptions
        @run_id = run_id
        @recorded_at = recorded_at
        @adapter = adapter
        @operation_summaries = operation_summaries
        @failures = failures
        @changes = {}
        @conflicts = []
      end

      def call
        desired_documents.each { |document, content| compare(document, content) }
        { operations: @changes.empty? ? [] : [operation], conflicts: @conflicts }
      end

      private

      def desired_documents
        {
          "index" => page("index", "Product Factory", "Canonical product artifacts and factory run records."),
          "setup-log" => setup_log,
          "ideas/index" => page("ideas/index", "Ideas", "No Ideas have been published yet."),
          "epics/index" => page("epics/index", "Epics", "No Epics have been published yet."),
          "tickets/index" => page("tickets/index", "Tickets", "No Tickets have been published yet."),
          "research/index" => page("research/index", "Research", "No research records have been published yet."),
          "factory-runs/index" => page(
            "factory-runs/index", "Factory Runs", "No factory phase runs have been published yet."
          )
        }
      end

      def page(document, heading, body)
        "#{marker(document)}\n# #{heading}\n\n#{body}\n"
      end

      def setup_log
        current = @snapshot.fetch("documents")["setup-log"]
        base = page("setup-log", "Setup Log", "| Run | Recorded at | Changes |\n|---|---|---|")
        return current if current&.include?(marker("setup-log")) && log_changes.empty?
        return base if log_changes.empty?

        row = safe((log_changes + ["Storage: #{@adapter}"]).join("; "))
        "#{current&.include?(marker('setup-log')) ? current.rstrip : base.rstrip}\n" \
          "| #{safe(@run_id)} | #{safe(@recorded_at)} | #{row} |\n"
      end

      def log_changes
        applied = @operation_summaries.empty? ? [] : ["Applied: #{@operation_summaries.join(', ')}"]
        applied + unpublished_failures.map do |failure|
          "Failure #{failure.fetch('operation_id')}: #{failure.fetch('responsible_component')} — " \
            "#{failure.fetch('root_cause')}; recovery: #{failure.fetch('recovery_action')}"
        end
      end

      def unpublished_failures
        current = @snapshot.fetch("documents")["setup-log"].to_s
        @failures.reject { |failure| current.include?(failure.fetch("operation_id")) }
      end

      def compare(document, desired)
        current = @snapshot.fetch("documents")[document]
        return @changes[document] = desired unless current
        return if current == desired

        key = "artifact:#{document}"
        return collision(document) unless owned?(document, current) || @adoptions.include?(key)

        compare_versions(document, key, current, desired)
      end

      def compare_versions(document, key, current, desired)
        installed = @installed_hashes[document]
        current_hash = digest(current)
        desired_hash = digest(desired)
        return @changes[document] = desired unless installed
        return @changes[document] = desired if current_hash == installed
        return conflict(key, "remote drift") if desired_hash == installed

        conflict(key, "concurrent change")
      end

      def owned?(document, content)
        content.include?(marker(document)) || @snapshot.fetch("legacy_owned_documents", []).include?(document)
      end

      def collision(document)
        key = "artifact:#{document}"
        @conflicts << {
          "resource" => key,
          "reason" => "name collision",
          "adopt_with" => "product-factory setup --adopt #{key}"
        }
      end

      def conflict(key, reason) = @conflicts << { "resource" => key, "reason" => reason }

      def operation
        Operation.new(
          kind: Operation::SYNC_ARTIFACTS,
          target: "artifacts:documents",
          attributes: {
            "adapter" => @adapter,
            "expected_revision" => @snapshot.fetch("revision"),
            "expected_hashes" => DOCUMENT_IDS.to_h do |document|
              content = @snapshot.fetch("documents")[document]
              [document, content && digest(content)]
            end,
            "documents" => @changes,
            "reason" => "synchronize Product Factory artifacts"
          }
        )
      end

      def marker(document) = format(@schema.dig("markers", "artifact"), document:)
      def digest(content) = Digest::SHA256.hexdigest(content)
      def safe(value) = value.to_s.gsub("|", "\\|").gsub(/[\r\n]+/, " ")
    end
  end
end
