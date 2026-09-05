# frozen_string_literal: true

module ProductFactory
  module GitHub
    class State
      TRANSIENT_KEYS = %w[closed fields id item_count node_id number updatedAt updated_at views].freeze

      def self.fingerprint(resource)
        Digest::SHA256.hexdigest(JSON.generate(scrub(resource)))
      end

      def self.scrub(value)
        case value
        when Hash
          value.reject { |key, _item| TRANSIENT_KEYS.include?(key.to_s) }
               .map { |key, item| [key.to_s, scrub(item)] }.sort_by(&:first).to_h
        when Array then value.map { |item| scrub(item) }
        else value
        end
      end
      private_class_method :scrub

      def initialize(config:, client:)
        @github = config.github
        @snapshot_loader = -> { Snapshot.call(config:, client:) }
      end

      def snapshot = @snapshot ||= @snapshot_loader.call

      def resource(target, refresh: false)
        @snapshot = nil if refresh
        key = target.delete_prefix("github:")
        return project if key == "project"

        collection, name = key.split(":", 2)
        resources(collection).find { |item| item["name"] == name }
      end

      def matches?(operation)
        current = resource(operation.target, refresh: true)
        current && self.class.fingerprint(current) == self.class.fingerprint(operation.attributes.fetch("desired"))
      end

      def resource_ids
        resources_by_key.transform_values { |resource| resource["node_id"] || resource["id"] }.compact
      end

      def resource_hashes
        resources_by_key.transform_values { |resource| self.class.fingerprint(resource) }
      end

      private

      def project
        snapshot.fetch("projects").find { |item| item["short_description"].to_s.include?(marker) } ||
          snapshot.fetch("projects").find { |item| item["title"] == @github.fetch("project_title") }
      end

      def resources(collection)
        return snapshot.fetch("issue_types") if collection == "issue-type"
        return project&.fetch("fields", []) if collection == "field"
        return project&.fetch("views", []) if collection == "view"

        []
      end

      def resources_by_key
        result = snapshot.fetch("issue_types").to_h { |item| ["issue-type:#{item.fetch('name')}", item] }
        result["project"] = project if project
        project&.fetch("fields", [])&.each { |item| result["field:#{item.fetch('name')}"] = item }
        project&.fetch("views", [])&.each { |item| result["view:#{item.fetch('name')}"] = item }
        result
      end

      def marker
        "product-factory:v1:project:#{@github.fetch('organization')}/#{@github.fetch('repository')}"
      end
    end
  end
end
