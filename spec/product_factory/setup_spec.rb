RSpec.describe ProductFactory::Setup do
  it "generates timestamped run IDs with four random bytes" do
    random = double
    allow(random).to receive(:hex).with(4).and_return("deadbeef")

    expect(ProductFactory::RunId.generate(clock: -> { Time.utc(2026, 9, 2, 12, 34, 56) }, random:))
      .to eq("RUN-20260902T123456Z-deadbeef")
  end

  it "applies an initial setup, resumes without reconfirming, and plans the next refresh as a no-op" do
    in_tmp_repo do |target|
      setup = described_class.new(
        distribution_root: File.expand_path("../..", __dir__),
        target_root: target,
        input: StringIO.new("yes\n"),
        output: StringIO.new,
        clock: -> { Time.utc(2026, 9, 2) }
      )

      first = setup.plan
      expect(first.mode).to eq("setup")
      expect(first).to be_applicable
      expect(setup.plan_path).not_to start_with(target)
      expect(setup.apply(first)).to eq(:success)
      expect(setup.apply(first)).to eq(:success)

      installation = ProductFactory::Installation.load(target)
      expect(installation.to_h.fetch("last_successful_setup_run")).to eq(first.run_id)
      expect(installation.managed_file_hashes).not_to have_key(ProductFactory::Config::PATH)

      second = setup.plan
      expect(second.mode).to eq("refresh")
      expect(second.operations).to be_empty
    end
  end
end
