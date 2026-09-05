# frozen_string_literal: true

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
      handler = { apply:, verify: }
      executor = described_class.new(journal:, handlers: { "record" => handler })

      expect { executor.apply(plan) }.to raise_error(ProductFactory::Error, "interrupted")
      expect(executor.apply(plan)).to eq(:success)
      expect(calls).to eq(%w[a b b c])
    end
  end

  it "rejects malformed journal entries" do
    in_tmp_repo do |root|
      path = File.join(root, "journal.jsonl")
      event = {
        event: "operation_completed",
        run_id: "RUN-1",
        operation_id: "abc",
        recorded_at: "2026-09-02T00:00:00Z"
      }
      File.write(path, "#{JSON.generate(event)}\n{")
      journal = ProductFactory::Journal.new(path:, clock: -> { Time.utc(2026, 9, 2) })

      expect { journal.events }
        .to raise_error(ProductFactory::ValidationError, "Invalid journal line 2")
    end
  end

  it "rejects conflicted plans before invoking handlers" do
    in_tmp_repo do |root|
      journal = ProductFactory::Journal.new(path: File.join(root, "journal.jsonl"), clock: -> { Time.utc(2026, 9, 2) })
      calls = []
      handler = {
        apply: ->(operation) { calls << operation.target },
        verify: ->(_operation) { true }
      }
      plan = ProductFactory::Plan.new(
        run_id: "RUN-1",
        mode: "setup",
        operations: [ProductFactory::Operation.new(kind: "record", target: "a")],
        conflicts: [{}]
      )

      expect { described_class.new(journal:, handlers: { "record" => handler }).apply(plan) }
        .to raise_error(ProductFactory::ConflictError, "plan has conflicts")
      expect(calls).to be_empty
    end
  end

  it "validates every handler before invoking any handler" do
    in_tmp_repo do |root|
      journal = ProductFactory::Journal.new(path: File.join(root, "journal.jsonl"), clock: -> { Time.utc(2026, 9, 2) })
      calls = []
      plan = ProductFactory::Plan.new(
        run_id: "RUN-1",
        mode: "setup",
        operations: [
          ProductFactory::Operation.new(kind: "first", target: "a"),
          ProductFactory::Operation.new(kind: "second", target: "b")
        ]
      )
      handlers = {
        "first" => {
          apply: ->(operation) { calls << operation.target },
          verify: ->(_operation) { true }
        },
        "second" => { apply: ->(_operation) {}, verify: nil }
      }

      expect { described_class.new(journal:, handlers:).apply(plan) }
        .to raise_error(ProductFactory::ValidationError, "missing verifier for second")
      expect(calls).to be_empty
    end
  end

  it "rejects unsupported journal event forms on append and read" do
    in_tmp_repo do |root|
      path = File.join(root, "journal.jsonl")
      journal = ProductFactory::Journal.new(path:, clock: -> { Time.utc(2026, 9, 2) })

      expect { journal.append(event: "unknown", run_id: "RUN-1") }
        .to raise_error(ProductFactory::ValidationError, "Invalid journal event")

      File.write(path, "{\"event\":\"operation_completed\",\"run_id\":\"RUN-1\"}\n")
      expect { journal.events }
        .to raise_error(ProductFactory::ValidationError, "Invalid journal line 1")
    end
  end

  it "refuses to read or append through a journal symlink" do
    in_tmp_repo do |root|
      outside = File.join(root, "outside.jsonl")
      path = File.join(root, "journal.jsonl")
      File.write(outside, "untouched\n")
      File.symlink(outside, path)
      journal = ProductFactory::Journal.new(path:, clock: -> { Time.utc(2026, 9, 2) })

      expect { journal.events }
        .to raise_error(ProductFactory::ValidationError, "Journal path must not be a symlink")
      expect { journal.append(event: "run_confirmed", run_id: "RUN-1") }
        .to raise_error(ProductFactory::ValidationError, "Journal path must not be a symlink")
      expect(File.read(outside)).to eq("untouched\n")
    end
  end
end
