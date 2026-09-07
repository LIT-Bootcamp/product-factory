# frozen_string_literal: true

module ProductFactory
  class Plan
    CONFIGURATION_FINGERPRINT = /\A[0-9a-f]{64}\z/

    attr_reader :run_id, :mode, :operations, :conflicts, :target_root, :configuration_fingerprint

    def self.load(path)
      data = JSON.parse(File.read(path))
      raise ValidationError, "Invalid plan" unless data.is_a?(Hash)

      from_h(data)
    rescue JSON::ParserError, KeyError, TypeError, ArgumentError, SystemCallError => e
      raise ValidationError, "Invalid plan: #{e.message}"
    end

    def self.from_h(data)
      target_root = data.fetch("target_root")
      raise ValidationError, "Invalid plan" unless target_root.nil? || target_root.is_a?(String)
      raise ValidationError, "Invalid plan" unless data.fetch("run_id").is_a?(String)
      raise ValidationError, "Invalid plan" unless data.fetch("mode").is_a?(String)
      raise ValidationError, "Invalid plan" unless data.fetch("conflicts").is_a?(Array)

      new(
        run_id: data.fetch("run_id"),
        mode: data.fetch("mode"),
        operations: load_operations(data.fetch("operations")),
        conflicts: data.fetch("conflicts"),
        target_root:,
        configuration_fingerprint: data["configuration_fingerprint"]
      )
    end

    def self.load_operations(items)
      raise ValidationError, "Invalid plan" unless items.is_a?(Array)

      items.map do |item|
        raise ValidationError, "Invalid plan" unless item.is_a?(Hash)

        operation = Operation.new(
          kind: item.fetch("kind"),
          target: item.fetch("target"),
          attributes: item.fetch("attributes")
        )
        id = item.fetch("id")
        raise ValidationError, "Invalid plan operation ID" unless id.is_a?(String) && id == operation.id

        operation
      end
    end

    private_class_method :from_h, :load_operations

    def initialize(run_id:, mode:, operations:, conflicts: [], target_root: nil, configuration_fingerprint: nil)
      validate_configuration_fingerprint!(configuration_fingerprint)
      @run_id = immutable_json(run_id)
      @mode = immutable_json(mode)
      @operations = operations.dup.freeze
      @conflicts = immutable_json(conflicts)
      @target_root = immutable_json(target_root)
      @configuration_fingerprint = immutable_json(configuration_fingerprint)
      freeze
    end

    def applicable? = conflicts.empty?

    def validate_configuration_binding!(installed_adapter:)
      bound = configuration_fingerprint || operations.none? { |operation| external?(operation, installed_adapter:) }
      return true if bound

      raise ValidationError, "plan has invalid configuration fingerprint"
    end

    def to_h
      {
        "run_id" => run_id,
        "mode" => mode,
        "operations" => operations.map { |operation| operation.to_h.merge("id" => operation.id) },
        "conflicts" => conflicts,
        "target_root" => target_root,
        "configuration_fingerprint" => configuration_fingerprint
      }
    end

    def write(path) = File.write(path, "#{JSON.pretty_generate(to_h)}\n")

    private

    def external?(operation, installed_adapter:)
      Operation::GITHUB_KINDS.include?(operation.kind) || operation.kind == Operation::SYNC_ARTIFACTS ||
        adapter_change?(operation, installed_adapter:)
    end

    def adapter_change?(operation, installed_adapter:)
      operation.kind == Operation::WRITE_INSTALLATION && operation.attributes.is_a?(Hash) &&
        operation.attributes["artifact_adapter"] != installed_adapter
    end

    def validate_configuration_fingerprint!(fingerprint)
      return if fingerprint.nil? || (fingerprint.is_a?(String) && fingerprint.match?(CONFIGURATION_FINGERPRINT))

      raise ValidationError, "Invalid plan configuration fingerprint"
    end

    def immutable_json(value) = JSON.parse(JSON.generate(value), freeze: true)
  end
end
