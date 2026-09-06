# frozen_string_literal: true

module ProductFactory
  module Setup
    class RunStore
      RUNS_PATH = ".product-factory/runs"

      attr_reader :journal

      def initialize(root:, clock:)
        @root = root
        @journal = Journal.new(path: File.join(root, ".product-factory-journal.jsonl"), clock:)
      end

      def pending_plan
        events = journal.events
        completed = events.filter_map { |event| event["run_id"] if event["event"] == "run_completed" }
        confirmed = events.rfind do |event|
          event["event"] == "run_confirmed" && !completed.include?(event["run_id"])
        end
        confirmed && load(confirmed.fetch("run_id"))
      end

      def confirm(plan)
        persist(plan)
        journal.append(event: "run_confirmed", run_id: plan.run_id)
      end

      def complete_noop(plan)
        journal.append(event: "run_completed", run_id: plan.run_id, status: "no-op")
      end

      private

      def persist(plan)
        directory = runs_directory
        Tempfile.create([".run-", ".tmp"], directory) do |file|
          file.write("#{JSON.pretty_generate(plan.to_h)}\n")
          file.flush
          file.fsync
          File.rename(file.path, path(plan.run_id))
        end
      end

      def load(run_id)
        plan_path = path(run_id)
        raise ValidationError, "stored run plan is a symlink" if File.symlink?(plan_path)

        Plan.load(plan_path)
      end

      def runs_directory
        factory = File.join(@root, ".product-factory")
        validate_directory!(factory)
        FileUtils.mkdir_p(factory)
        validate_directory!(factory)
        directory = File.join(@root, RUNS_PATH)
        validate_directory!(directory)
        FileUtils.mkdir_p(directory)
        validate_directory!(directory)
        directory
      end

      def validate_directory!(directory)
        return unless File.exist?(directory) || File.symlink?(directory)
        return if File.directory?(directory) && !File.symlink?(directory)

        raise ValidationError, "run storage must be a directory"
      end

      def path(run_id)
        raise ValidationError, "invalid stored run ID" unless run_id.match?(/\ARUN-[A-Za-z0-9-]+\z/)

        File.join(@root, RUNS_PATH, "#{run_id}.json")
      end
    end
  end
end
