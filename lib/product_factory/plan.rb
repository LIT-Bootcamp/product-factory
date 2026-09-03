require "json"

module ProductFactory
  class Plan
    attr_reader :run_id, :mode, :operations, :conflicts, :target_root

    def self.load(path)
      data = JSON.parse(File.read(path))
      raise ValidationError, "Invalid plan" unless data.is_a?(Hash)

      target_root = data.fetch("target_root")
      unless target_root.nil? || target_root.is_a?(String)
        raise ValidationError, "Invalid plan"
      end
      serialized_operations = data.fetch("operations")
      raise ValidationError, "Invalid plan" unless serialized_operations.is_a?(Array)

      operations = serialized_operations.map do |item|
        raise ValidationError, "Invalid plan" unless item.is_a?(Hash)

        id = item.fetch("id")
        operation = Operation.new(
          kind: item.fetch("kind"),
          target: item.fetch("target"),
          attributes: item.fetch("attributes")
        )
        raise ValidationError, "Invalid plan operation ID" unless id.is_a?(String) && id == operation.id

        operation
      end
      raise ValidationError, "Invalid plan" unless data.fetch("run_id").is_a?(String)
      raise ValidationError, "Invalid plan" unless data.fetch("mode").is_a?(String)
      raise ValidationError, "Invalid plan" unless data.fetch("conflicts").is_a?(Array)

      new(
        run_id: data.fetch("run_id"),
        mode: data.fetch("mode"),
        operations:,
        conflicts: data.fetch("conflicts"),
        target_root:
      )
    rescue JSON::ParserError, KeyError, TypeError, ArgumentError, SystemCallError => error
      raise ValidationError, "Invalid plan: #{error.message}"
    end

    def initialize(run_id:, mode:, operations:, conflicts: [], target_root: nil)
      @run_id = immutable_json(run_id)
      @mode = immutable_json(mode)
      @operations = operations.dup.freeze
      @conflicts = immutable_json(conflicts)
      @target_root = immutable_json(target_root)
      freeze
    end

    def applicable? = conflicts.empty?

    def to_h
      {
        "run_id" => run_id,
        "mode" => mode,
        "operations" => operations.map { |operation| operation.to_h.merge("id" => operation.id) },
        "conflicts" => conflicts,
        "target_root" => target_root
      }
    end

    def write(path) = File.write(path, JSON.pretty_generate(to_h) + "\n")

    private

    def immutable_json(value) = JSON.parse(JSON.generate(value), freeze: true)
  end
end
