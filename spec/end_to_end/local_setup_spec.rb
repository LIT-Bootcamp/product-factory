RSpec.describe ProductFactory::Setup do
  def in_factory
    Dir.mktmpdir("product-factory-e2e-") do |temporary|
      root = File.realpath(temporary)
      distribution = File.join(root, "distribution")
      target = File.join(root, "target")
      FileUtils.mkdir_p([File.join(distribution, "templates"), target])
      FileUtils.cp_r(File.expand_path("../../lib", __dir__), distribution)
      FileUtils.cp(File.expand_path("../../templates/config.yml", __dir__), File.join(distribution, "templates/config.yml"))
      FileUtils.cp_r(File.expand_path("../../templates/project", __dir__), File.join(distribution, "templates"))
      yield distribution, target
    end
  end

  def setup_for(distribution, target, answer: "yes\n")
    described_class.new(
      distribution_root: distribution,
      target_root: target,
      input: StringIO.new(answer),
      output: StringIO.new,
      clock: -> { Time.utc(2026, 9, 3) }
    )
  end

  def install(distribution, target)
    setup = setup_for(distribution, target)
    plan = setup.plan
    expect(setup.apply(plan)).to eq(:success)
    plan
  end

  def schema_path(root, name = "config-v1.yml")
    File.join(root, ".product-factory/schemas", name)
  end

  it "keeps initial planning mutation-free" do
    in_factory do |distribution, target|
      setup_for(distribution, target).plan

      expect(Dir.children(target)).to be_empty
    end
  end

  it "keeps a declined apply mutation-free" do
    in_factory do |distribution, target|
      setup = setup_for(distribution, target, answer: "no\n")
      plan = setup.plan

      expect(setup.apply(plan)).to eq(:declined)
      expect(Dir.children(target)).to be_empty
    end
  end

  it "installs and validates" do
    in_factory do |distribution, target|
      install(distribution, target)

      expect(ProductFactory::Validator.new(root: target).call).to eq(true)
    end
  end

  it "refreshes an unchanged installation as a no-op" do
    in_factory do |distribution, target|
      install(distribution, target)

      refresh = setup_for(distribution, target).plan
      expect(refresh.mode).to eq("refresh")
      expect(refresh.operations).to be_empty
    end
  end

  it "refreshes through the installed CLI as a no-op" do
    in_factory do |distribution, target|
      install(distribution, target)
      output, error, status = Open3.capture3(
        "bundle", "exec", "ruby", File.join(target, "bin/product-factory"), "plan",
        chdir: target
      )

      expect(status).to be_success, error
      plan_path = output[/Plan path: (.+)\n/, 1]
      expect(ProductFactory::Plan.load(plan_path).operations).to be_empty
    ensure
      File.delete(plan_path) if plan_path && File.exist?(plan_path)
    end
  end

  it "fails closed when the installed distribution is incomplete" do
    in_factory do |distribution, target|
      install(distribution, target)
      File.delete(File.join(
        target,
        ".product-factory/runtime/templates/project/.product-factory/schemas/config-v1.yml"
      ))
      _output, error, status = Open3.capture3(
        "bundle", "exec", "ruby", File.join(target, "bin/product-factory"), "plan",
        chdir: target
      )

      expect(status).not_to be_success
      expect(error).to include("distribution is incomplete")
      expect(File).to exist(schema_path(target))
    end
  end

  it "applies an upstream-only change" do
    in_factory do |distribution, target|
      install(distribution, target)
      source = schema_path(File.join(distribution, "templates/project"))
      File.write(source, File.read(source) + "# upstream\n")

      setup = setup_for(distribution, target)
      expect(setup.apply(setup.plan)).to eq(:success)
      expect(File.read(schema_path(target))).to end_with("# upstream\n")
    end
  end

  it "rejects local drift after planning before confirmation" do
    in_factory do |distribution, target|
      install(distribution, target)
      source = schema_path(File.join(distribution, "templates/project"))
      destination = schema_path(target)
      File.write(source, File.read(source) + "# upstream\n")
      setup = setup_for(distribution, target)
      plan = setup.plan
      File.write(destination, File.read(destination) + "# late local edit\n")

      expect { setup.apply(plan) }
        .to raise_error(ProductFactory::ConflictError, /changed since plan/)
      expect(File.read(destination)).to end_with("# late local edit\n")
    end
  end

  it "preserves a local-only change" do
    in_factory do |distribution, target|
      install(distribution, target)
      destination = schema_path(target)
      File.write(destination, File.read(destination) + "# local\n")

      plan = setup_for(distribution, target).plan

      expect(plan.operations).to be_empty
      expect(File.read(destination)).to end_with("# local\n")
    end
  end

  it "blocks every operation when one managed file conflicts" do
    in_factory do |distribution, target|
      install(distribution, target)
      upstream_only = schema_path(File.join(distribution, "templates/project"))
      conflicted_source = schema_path(File.join(distribution, "templates/project"), "installation-v1.yml")
      conflicted_target = schema_path(target, "installation-v1.yml")
      original_upstream_only = File.read(schema_path(target))
      File.write(upstream_only, File.read(upstream_only) + "# upstream\n")
      File.write(conflicted_source, File.read(conflicted_source) + "# upstream\n")
      File.write(conflicted_target, File.read(conflicted_target) + "# local\n")
      setup = setup_for(distribution, target)
      plan = setup.plan

      expect(plan.conflicts.map { |conflict| conflict.fetch("path") }).to include(".product-factory/schemas/installation-v1.yml")
      expect { setup.apply(plan) }.to raise_error(ProductFactory::ConflictError)
      expect(File.read(schema_path(target))).to eq(original_upstream_only)
    end
  end

  it "applies take_upstream and journals the resolution" do
    in_factory do |distribution, target|
      install(distribution, target)
      relative = ".product-factory/schemas/config-v1.yml"
      source = schema_path(File.join(distribution, "templates/project"))
      destination = schema_path(target)
      File.write(source, File.read(source) + "# upstream\n")
      File.write(destination, File.read(destination) + "# local\n")
      setup = setup_for(distribution, target)
      plan = setup.plan(resolutions: { relative => "take_upstream" })

      expect(setup.apply(plan)).to eq(:success)
      events = ProductFactory::Journal.new(
        path: File.join(target, ".product-factory-journal.jsonl"),
        clock: -> { Time.utc(2026, 9, 3) }
      ).events
      expect(events).to include(a_hash_including("reason" => "take_upstream"))
      expect(File.binread(destination)).to eq(File.binread(source))
    end
  end

  it "resumes after verifying the two completed operations" do
    in_factory do |_distribution, target|
      operations = %w[one two three].map do |name|
        ProductFactory::Operation.new(kind: "record", target: name)
      end
      plan = ProductFactory::Plan.new(run_id: "RUN-INTERRUPTED", mode: "setup", operations:)
      applied = []
      fail_once = true
      handler = ProductFactory::Executor::Handler.new(
        apply: lambda do |operation|
          raise ProductFactory::Error, "interrupted" if operation.target == "three" && fail_once.tap { fail_once = false }

          applied << operation.target
        end,
        verify: ->(operation) { applied.include?(operation.target) }
      )
      journal = ProductFactory::Journal.new(
        path: File.join(target, "journal.jsonl"),
        clock: -> { Time.utc(2026, 9, 3) }
      )
      executor = ProductFactory::Executor.new(journal:, handlers: { "record" => handler })

      expect { executor.apply(plan) }.to raise_error(ProductFactory::Error, "interrupted")
      expect(executor.apply(plan)).to eq(:success)
      expect(applied).to eq(%w[one two three])
    end
  end

  it "fails closed on a corrupted journal" do
    in_factory do |distribution, target|
      install(distribution, target)
      File.open(File.join(target, ".product-factory-journal.jsonl"), "a") { |file| file.write("{") }

      expect { ProductFactory::Validator.new(root: target).call }
        .to raise_error(ProductFactory::ValidationError, /Invalid journal line \d+/)
    end
  end

  it "fails closed on symlinked sources and destinations" do
    in_factory do |distribution, target|
      source = File.join(distribution, "lib/product_factory.rb")
      outside = File.join(File.dirname(distribution), "outside.rb")
      File.write(outside, "outside\n")
      File.delete(source)
      File.symlink(outside, source)

      expect { setup_for(distribution, target).plan }
        .to raise_error(ProductFactory::ValidationError, /source path contains a symlink/)
    end

    in_factory do |distribution, target|
      install(distribution, target)
      destination = schema_path(target)
      outside = File.join(File.dirname(target), "outside.yml")
      File.write(outside, "outside\n")
      File.delete(destination)
      File.symlink(outside, destination)

      expect { setup_for(distribution, target).plan }
        .to raise_error(ProductFactory::ValidationError, /managed target is a symlink/)
    end
  end

  it "never changes target Git history or remotes" do
    in_factory do |distribution, target|
      expect(system("git", "init", "-q", target)).to eq(true)
      File.write(File.join(target, "README.md"), "target\n")
      expect(system("git", "-C", target, "add", "README.md")).to eq(true)
      expect(system(
        "git", "-C", target,
        "-c", "user.name=Product Factory Test",
        "-c", "user.email=factory@example.test",
        "-c", "commit.gpgsign=false",
        "commit", "-qm", "Initial"
      )).to eq(true)
      expect(system("git", "-C", target, "remote", "add", "origin", "https://example.test/product.git")).to eq(true)
      head = IO.popen(["git", "-C", target, "rev-parse", "HEAD"], &:read)
      remote = IO.popen(["git", "-C", target, "remote", "get-url", "origin"], &:read)

      install(distribution, target)

      expect(IO.popen(["git", "-C", target, "rev-parse", "HEAD"], &:read)).to eq(head)
      expect(IO.popen(["git", "-C", target, "remote", "get-url", "origin"], &:read)).to eq(remote)
    end
  end
end
