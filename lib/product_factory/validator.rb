# frozen_string_literal: true

module ProductFactory
  class Validator
    def self.call(...) = new(...).call

    def initialize(root:)
      @root = File.expand_path(root)
    end

    def call
      Setup::TargetValidator.call(root: @root)
      config = Config.load(@root)
      installation = Installation.load(@root)

      validate_installation(installation)
      CredentialLeakValidator.call(config:, installation:)
      true
    end

    private

    def validate_installation(installation)
      FactoryFilesValidator.call(root: @root, hashes: installation.factory_file_hashes)
      validate_pending_operations(installation)
      validate_completed_run(installation)
    end

    def validate_pending_operations(installation)
      pending = installation.pending_operations
      raise ValidationError, "pending operations remain" unless pending.is_a?(Array) && pending.empty?
    end

    def validate_completed_run(installation)
      journal_path = File.join(@root, ".product-factory-journal.jsonl")
      raise ValidationError, "Missing .product-factory-journal.jsonl" unless File.file?(journal_path)

      events = Journal.new(path: journal_path, clock: -> { Time.now }).events
      run_id = installation.to_h["last_successful_setup_run"]
      valid = run_id.is_a?(String) && events.any? do |event|
        event["event"] == "run_completed" && event["run_id"] == run_id && event["status"] == "success"
      end
      raise ValidationError, "journal has no successful setup run for installation" unless valid
    end
  end
end
