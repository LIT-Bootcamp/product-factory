RSpec.describe ProductFactory::Plan do
  it "keeps operation IDs stable across recursive hash order" do
    first = ProductFactory::Operation.new(
      kind: "write_file",
      target: "a",
      attributes: { "outer" => { "b" => 2, "a" => 1 }, "list" => [{ "d" => 4, "c" => 3 }] }
    )
    second = ProductFactory::Operation.new(
      kind: "write_file",
      target: "a",
      attributes: { "list" => [{ "c" => 3, "d" => 4 }], "outer" => { "a" => 1, "b" => 2 } }
    )

    expect(first.id).to eq("839eac00724f528b4fd8")
    expect(second.id).to eq(first.id)
  end

  it "does not expose an operation to input or nested mutation" do
    kind = "write_file"
    target = "a"
    attributes = { "nested" => [{ "value" => "original" }] }
    operation = ProductFactory::Operation.new(kind:, target:, attributes:)

    kind << "_changed"
    target << "_changed"
    attributes["nested"].first["value"] << "_changed"

    expect(operation.to_h).to eq(
      "kind" => "write_file",
      "target" => "a",
      "attributes" => { "nested" => [{ "value" => "original" }] }
    )
    expect { operation.attributes["nested"].first["value"] << "_changed" }.to raise_error(FrozenError)
  end

  it "cannot apply a plan with conflicts" do
    plan = described_class.new(
      run_id: "RUN-1",
      mode: "refresh",
      operations: [],
      conflicts: [{ "path" => "a" }]
    )

    expect(plan).not_to be_applicable
  end

  it "round-trips through JSON without exposing plan data to mutation" do
    run_id = "RUN-1"
    mode = "refresh"
    operations = [
      ProductFactory::Operation.new(
        kind: "write_file",
        target: "a",
        attributes: { "content" => ["hello"] }
      )
    ]
    conflicts = [{ "path" => ["a"] }]
    plan = described_class.new(run_id:, mode:, operations:, conflicts:)

    run_id << "-changed"
    mode << "-changed"
    operations.clear
    conflicts.first["path"] << "changed"

    in_tmp_repo do |root|
      path = File.join(root, "plan.json")
      plan.write(path)
      loaded = described_class.load(path)

      expect(loaded.to_h).to eq(plan.to_h)
      expect(File.read(path)).to end_with("\n")
    end
    expect { plan.conflicts.first["path"] << "changed" }.to raise_error(FrozenError)
  end
end
