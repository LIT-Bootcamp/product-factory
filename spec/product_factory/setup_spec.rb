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

  it "rejects a plan for another target before asking or writing a journal" do
    in_tmp_repo do |target|
      setup = build_setup(target)
      plan = setup.plan
      other_target = File.realpath(Dir.mktmpdir("product-factory-other-"))
      other_setup = build_setup(other_target)

      expect { other_setup.apply(plan) }
        .to raise_error(ProductFactory::ValidationError, /target does not match/)
      expect(Dir.children(other_target)).to be_empty
    ensure
      FileUtils.remove_entry(other_target) if other_target && File.exist?(other_target)
    end
  end

  it "rejects an unowned managed target before asking or writing a journal" do
    in_tmp_repo do |target|
      setup = build_setup(target)
      operation = ProductFactory::Operation.new(kind: "delete_file", target: ".git/config", attributes: {})
      installation = ProductFactory::Operation.new(
        kind: "write_installation",
        target: ProductFactory::Installation::PATH,
        attributes: ProductFactory::Installation.empty.to_h
      )
      plan = ProductFactory::Plan.new(
        run_id: "RUN-TAMPERED",
        mode: "setup",
        operations: [operation, installation],
        target_root: target
      )

      expect { setup.apply(plan) }
        .to raise_error(ProductFactory::ValidationError, /invalid managed target/)
      expect(Dir.children(target)).to be_empty
    end
  end

  it "rejects symlinked factory state" do
    in_tmp_repo do |target|
      outside = File.join(Dir.mktmpdir("product-factory-outside-"), "config.yml")
      File.write(outside, "outside: true\n")
      FileUtils.mkdir_p(File.join(target, ".product-factory"))
      File.symlink(outside, File.join(target, ProductFactory::Config::PATH))

      expect { build_setup(target).plan }
        .to raise_error(ProductFactory::ValidationError, /config.yml is a symlink/)
    ensure
      FileUtils.remove_entry(File.dirname(outside)) if outside && File.exist?(File.dirname(outside))
    end
  end

  def build_setup(target)
    described_class.new(
      distribution_root: File.expand_path("../..", __dir__),
      target_root: target,
      input: StringIO.new("yes\n"),
      output: StringIO.new,
      clock: -> { Time.utc(2026, 9, 2) }
    )
  end
end
