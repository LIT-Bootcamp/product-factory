require "json"

module ProductFactory
  class Plan
    attr_reader :run_id, :mode, :operations, :conflicts

    def self.load(path)
      data = JSON.parse(File.read(path))
      operations = data.fetch("operations").map do |item|
        Operation.new(
          kind: item.fetch("kind"),
          target: item.fetch("target"),
          attributes: item.fetch("attributes")
        )
      end
      new(
        run_id: data.fetch("run_id"),
        mode: data.fetch("mode"),
        operations:,
        conflicts: data.fetch("conflicts")
      )
    end

    def initialize(run_id:, mode:, operations:, conflicts: [])
      @run_id = immutable_json(run_id)
      @mode = immutable_json(mode)
      @operations = operations.dup.freeze
      @conflicts = immutable_json(conflicts)
      freeze
    end

    def applicable? = conflicts.empty?

    def to_h
      {
        "run_id" => run_id,
        "mode" => mode,
        "operations" => operations.map(&:to_h),
        "conflicts" => conflicts
      }
    end

    def write(path) = File.write(path, JSON.pretty_generate(to_h) + "\n")

    private

    def immutable_json(value) = JSON.parse(JSON.generate(value), freeze: true)
  end
end
