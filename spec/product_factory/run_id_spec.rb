# frozen_string_literal: true

RSpec.describe ProductFactory::RunId do
  it "generates timestamped IDs with four random bytes" do
    random = double
    allow(random).to receive(:hex).with(4).and_return("deadbeef")

    expect(described_class.generate(clock: -> { Time.utc(2026, 9, 2, 12, 34, 56) }, random:))
      .to eq("RUN-20260902T123456Z-deadbeef")
  end
end
