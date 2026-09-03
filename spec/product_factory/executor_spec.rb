RSpec.describe ProductFactory::Executor do
  it "skips verified completed operations when resuming" do
    in_tmp_repo do |root|
      journal = ProductFactory::Journal.new(
        path: File.join(root, "journal.jsonl"),
        clock: -> { Time.utc(2026, 9, 2) }
      )
      calls = []
      applied = []
      operations = %w[a b c].map do |name|
        ProductFactory::Operation.new(kind: "record", target: name)
      end
      plan = ProductFactory::Plan.new(run_id: "RUN-1", mode: "setup", operations:)
      fail_once = true
      apply = lambda do |operation|
        calls << operation.target
        if operation.target == "b" && fail_once
          fail_once = false
          raise ProductFactory::Error, "interrupted"
        end

        applied << operation.target
      end
      verify = ->(operation) { applied.include?(operation.target) }
      handler = described_class::Handler.new(apply:, verify:)
      executor = described_class.new(journal:, handlers: { "record" => handler })

      expect { executor.apply(plan) }.to raise_error(ProductFactory::Error, "interrupted")
      expect(executor.apply(plan)).to eq(:success)
      expect(calls).to eq(%w[a b b c])
    end
  end

  it "rejects malformed journal entries" do
    in_tmp_repo do |root|
      path = File.join(root, "journal.jsonl")
      File.write(path, "{\"event\":\"operation_completed\"}\n{")
      journal = ProductFactory::Journal.new(path:, clock: -> { Time.utc(2026, 9, 2) })

      expect { journal.events }
        .to raise_error(ProductFactory::ValidationError, "Invalid journal line 2")
    end
  end
end
