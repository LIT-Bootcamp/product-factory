# frozen_string_literal: true

module ProductFactory
  module Wiki
    class Planner < Service
      def initialize(
        schema:, snapshot:, installed_hashes:, adoptions:, run_id:, recorded_at:, operation_summaries:, failures:
      )
        super()
        @schema = schema
        @snapshot = snapshot
        @installed_hashes = installed_hashes
        @adoptions = adoptions
        @run_id = run_id
        @recorded_at = recorded_at
        @operation_summaries = operation_summaries
        @failures = failures
        @changes = {}
        @conflicts = []
      end

      def call
        desired_pages.each { |name, content| compare(name, content) }
        operations = @changes.empty? ? [] : [operation]
        { operations:, conflicts: @conflicts }
      end

      private

      def desired_pages
        {
          "_Sidebar.md" => page("_Sidebar", "Navigation", sidebar),
          "Setup-Log.md" => setup_log,
          "Ideas.md" => page("Ideas", "Ideas", "No Ideas have been published yet."),
          "Epics.md" => page("Epics", "Epics", "No Epics have been published yet."),
          "Tickets.md" => page("Tickets", "Tickets", "No Tickets have been published yet."),
          "Research.md" => page("Research", "Research", "No research records have been published yet."),
          "Factory-Runs.md" => page("Factory-Runs", "Factory Runs", "No factory phase runs have been published yet.")
        }
      end

      def page(name, heading, body)
        "#{marker(name)}\n# #{heading}\n\n#{body}\n"
      end

      def sidebar
        %w[Home Ideas Epics Tickets Research Factory-Runs Setup-Log]
          .map { |name| "- [#{name.tr('-', ' ')}](#{name})" }.join("\n")
      end

      def setup_log
        current = @snapshot.dig("pages", "Setup-Log.md")
        base = page("Setup-Log", "Setup Log", "| Run | Recorded at | Changes |\n|---|---|---|")
        return current if current&.include?(marker("Setup-Log")) && log_changes.empty?
        return base if log_changes.empty?

        "#{current&.include?(marker('Setup-Log')) ? current.rstrip : base.rstrip}\n" \
          "| #{safe(@run_id)} | #{safe(@recorded_at)} | #{safe(log_changes.join('; '))} |\n"
      end

      def log_changes
        applied = @operation_summaries.empty? ? [] : ["Applied: #{@operation_summaries.join(', ')}"]
        applied + unpublished_failures.map do |failure|
          "Failure #{failure.fetch('operation_id')}: #{failure.fetch('responsible_component')} — " \
            "#{failure.fetch('root_cause')}; recovery: #{failure.fetch('recovery_action')}"
        end
      end

      def unpublished_failures
        current = @snapshot.dig("pages", "Setup-Log.md").to_s
        @failures.reject { |failure| current.include?(failure.fetch("operation_id")) }
      end

      def compare(name, desired)
        current = @snapshot.dig("pages", name)
        return @changes[name] = desired unless current
        return if current == desired

        key = "wiki:#{name.delete_suffix('.md')}"
        return collision(key) unless owned?(name, current) || @adoptions.include?(key)

        compare_versions(name, key, current, desired)
      end

      def compare_versions(name, key, current, desired)
        installed = @installed_hashes[name]
        current_hash = digest(current)
        desired_hash = digest(desired)
        return @changes[name] = desired unless installed
        return @changes[name] = desired if current_hash == installed
        return conflict(key, "remote drift") if desired_hash == installed

        conflict(key, "concurrent change")
      end

      def collision(key)
        @conflicts << {
          "resource" => key, "reason" => "name collision",
          "adopt_with" => "product-factory setup --adopt #{key}"
        }
      end

      def conflict(key, reason) = @conflicts << { "resource" => key, "reason" => reason }

      def operation
        Operation.new(
          kind: Operation::SYNC_WIKI,
          target: "wiki:factory-pages",
          attributes: {
            "expected_head" => @snapshot.fetch("head"),
            "pages" => @changes,
            "reason" => "synchronize factory Wiki pages"
          }
        )
      end

      def owned?(name, content) = content.include?(marker(name.delete_suffix(".md")))
      def marker(name) = format(@schema.dig("markers", "wiki"), page: name)
      def digest(content) = Digest::SHA256.hexdigest(content)
      def safe(value) = value.to_s.gsub("|", "\\|").gsub(/[\r\n]+/, " ")
    end
  end
end
