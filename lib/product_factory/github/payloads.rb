# frozen_string_literal: true

module ProductFactory
  module GitHub
    module Payloads
      module_function

      def select_options(project, current, desired)
        current_by_name = current.fetch("options").to_h { |option| [option.fetch("name"), option] }
        desired_names = desired.fetch("options").map { |option| option.fetch("name") }
        if (current_by_name.keys - desired_names).any? && project.fetch("item_count").positive?
          raise ConflictError, "cannot remove Project field options while items exist"
        end

        desired.fetch("options").map do |option|
          id = current_by_name.dig(option.fetch("name"), "id")
          id ? option.merge("id" => id) : option
        end
      end

      def view_fields(project, names, id_key)
        fields = project.fetch("fields").to_h { |field| [field.fetch("name"), field] }
        names.map { |name| fields.fetch(name).fetch(id_key) { fields.fetch(name).fetch("id") } }
      rescue KeyError => e
        raise ValidationError, "missing Project view field: #{e.key}"
      end

      def rest_view(project, desired)
        {
          "filter" => desired.fetch("filter"),
          "visible_fields" => view_fields(project, desired.fetch("visible_fields"), "id")
        }
      end

      def graphql_view(project, desired)
        ids = view_fields(project, desired.fetch("visible_fields"), "node_id")
        { "filter" => desired.fetch("filter"), "configuration" => { "visibleFieldIds" => ids } }
      end
    end
  end
end
