# frozen_string_literal: true

RSpec.describe ProductFactory::Setup::Runner do
  it "runs first setup and then reports a no-op without another confirmation" do
    in_tmp_repo do |target|
      github = FakeGitHub.new
      wiki = FakeWiki.new
      first_output = StringIO.new
      first = build_full_setup(target, github:, wiki:, input: StringIO.new("Bootcamper\nyes\n"), output: first_output)

      expect(first.run([])).to eq(:success)
      expect(github.issue_type_names).to eq(%w[Idea Epic Ticket])
      expect(github.project.fetch("public")).to be(false)
      expect(github.view_names).to eq(%w[Ideas Epics Tickets])
      expect(first_output.string).to include("CREATE #{ProductFactory::Config::PATH}")
      expect(first_output.string.scan("Apply this plan? [yes/no]").size).to eq(1)

      second_output = StringIO.new
      second = build_full_setup(target, github:, wiki:, input: StringIO.new, output: second_output)
      expect(second.run([])).to eq(:success)
      expect(second_output.string).to include("Product Factory is up to date")
      expect(second_output.string).not_to include("Apply this plan?")
    end
  end

  it "stops before every target mutation when Wiki preflight fails" do
    in_tmp_repo do |target|
      wiki = instance_double(FakeWiki)
      failure = ProductFactory::ExternalFailure.new(
        failed_rule: "wiki_home_required", responsible_component: "wiki prerequisite",
        root_cause: "GitHub Wiki has no Home page", impact: "setup stopped",
        recovery_action: "Create the Home page in GitHub Wiki, then rerun product-factory setup"
      )
      allow(wiki).to receive(:snapshot).and_raise(failure)
      setup = build_full_setup(target, github: FakeGitHub.new, wiki:, input: StringIO.new("Bootcamper\n"))

      expect { setup.run([]) }.to raise_error(failure)
      expect(Dir.children(target)).to be_empty
    end
  end

  it "persists and resumes the confirmed plan without asking again" do
    in_tmp_repo do |target|
      github = FakeGitHub.new(fail_once_after: ProductFactory::Operation::ENSURE_PROJECT)
      wiki = FakeWiki.new
      first = build_full_setup(target, github:, wiki:, input: StringIO.new("Bootcamper\nyes\n"))

      expect { first.run([]) }.to raise_error(ProductFactory::ExternalFailure, "simulated interruption")
      plans = Dir.glob(File.join(target, ".product-factory/runs/*.json"))
      expect(plans.size).to eq(1)

      output = StringIO.new
      resumed = build_full_setup(target, github:, wiki:, input: StringIO.new, output:)
      expect(resumed.run([])).to eq(:success)
      expect(output.string).to include("Resuming ")
      expect(output.string).not_to include("Apply this plan?")
      expect(github.project.fetch("title")).to eq("Bootcamper Product Factory")
    end
  end

  it "rejects an unknown adoption key before planning" do
    in_tmp_repo do |target|
      setup = build_full_setup(target, github: FakeGitHub.new, wiki: FakeWiki.new)

      expect { setup.run(["--adopt", "everything"]) }
        .to raise_error(ProductFactory::UsageError, "unknown adoption: everything")
      expect(Dir.children(target)).to be_empty
    end
  end

  it "requires the full semantic adoption key" do
    in_tmp_repo do |target|
      setup = build_full_setup(target, github: FakeGitHub.new, wiki: FakeWiki.new)

      expect { setup.run(["--adopt", "Idea"]) }
        .to raise_error(ProductFactory::UsageError, "unknown adoption: Idea")
    end
  end

  it "accepts both resolution option forms" do
    in_tmp_repo do |target|
      setup = build_setup(target)
      plan = ProductFactory::Plan.new(run_id: "RUN-OPTIONS", mode: "refresh", operations: [])
      allow(setup).to receive(:plan).and_return(plan)

      setup.plan_and_print(["--resolve", "a.txt=keep_local"])
      setup.plan_and_print(["--resolve=b.txt=take_upstream"])

      expect(setup).to have_received(:plan).with(resolutions: { "a.txt" => "keep_local" })
      expect(setup).to have_received(:plan).with(resolutions: { "b.txt" => "take_upstream" })
    end
  end

  it "rejects an incomplete resolution option" do
    in_tmp_repo do |target|
      expect { build_setup(target).plan_and_print(["--resolve"]) }
        .to raise_error(ProductFactory::UsageError, "resolve must be PATH=VALUE")
    end
  end

  it "applies an initial setup, resumes without reconfirming, and plans the next refresh as a no-op" do
    in_tmp_repo do |target|
      setup = described_class.new(
        distribution_root: FileHelpers::FACTORY_ROOT,
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
      expect(installation.factory_file_hashes).not_to have_key(ProductFactory::Config::PATH)

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

  it "rejects an unowned factory target before asking or writing a journal" do
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
        .to raise_error(ProductFactory::ValidationError, /invalid factory target/)
      expect(Dir.children(target)).to be_empty
    end
  end

  it "rejects unowned paths injected through installation state" do
    in_tmp_repo do |target|
      template = File.join(FileHelpers::FACTORY_ROOT, "templates/config.yml")
      write(target, ProductFactory::Config::PATH, File.read(template))
      ProductFactory::Installation.empty.with(
        "factory_file_hashes" => { ".git/config" => "a" * 64 }
      ).write(target)

      expect { build_setup(target).plan }
        .to raise_error(ProductFactory::ValidationError, /invalid factory file hash/)
      expect(File).not_to exist(File.join(target, ".product-factory-journal.jsonl"))
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

  it "resumes when a started config seed is already byte-identical" do
    in_tmp_repo do |target|
      setup = build_setup(target)
      plan = setup.plan
      seed = plan.operations.find { |operation| operation.kind == "seed_config" }
      journal = ProductFactory::Journal.new(
        path: File.join(target, ".product-factory-journal.jsonl"),
        clock: -> { Time.utc(2026, 9, 2) }
      )
      journal.append(event: "run_confirmed", run_id: plan.run_id)
      journal.append(event: "operation_started", run_id: plan.run_id, operation_id: seed.id)
      write(target, ProductFactory::Config::PATH, seed.attributes.fetch("content_base64").unpack1("m0"))

      expect(setup.apply(plan)).to eq(:success)
      expect(ProductFactory::Validator.call(root: target)).to be(true)
    end
  end

  it "allows a verified completed file operation during resume" do
    in_tmp_repo do |target|
      setup = build_setup(target)
      plan = setup.plan
      operation = plan.operations.find { |item| item.kind == "write_file" }
      ProductFactory::FileSync::Target.new(root: target).apply(operation)
      journal = ProductFactory::Journal.new(
        path: File.join(target, ".product-factory-journal.jsonl"),
        clock: -> { Time.utc(2026, 9, 2) }
      )
      journal.append(event: "run_confirmed", run_id: plan.run_id)
      journal.append(event: "operation_started", run_id: plan.run_id, operation_id: operation.id)
      journal.append(event: "operation_completed", run_id: plan.run_id, operation_id: operation.id)

      expect(setup.apply(plan)).to eq(:success)
      expect(ProductFactory::Validator.call(root: target)).to be(true)
    end
  end

  it "resumes a started file operation that already reached its desired state" do
    in_tmp_repo do |target|
      setup = build_setup(target)
      plan = setup.plan
      operation = plan.operations.find { |item| item.kind == "write_file" }
      ProductFactory::FileSync::Target.new(root: target).apply(operation)
      journal = ProductFactory::Journal.new(
        path: File.join(target, ".product-factory-journal.jsonl"),
        clock: -> { Time.utc(2026, 9, 2) }
      )
      journal.append(event: "run_confirmed", run_id: plan.run_id)
      journal.append(event: "operation_started", run_id: plan.run_id, operation_id: operation.id)

      expect(setup.apply(plan)).to eq(:success)
      expect(ProductFactory::Validator.call(root: target)).to be(true)
    end
  end

  it "never verifies a completed file operation through a symlinked ancestor" do
    in_tmp_repo do |target|
      setup = build_setup(target)
      generated = setup.plan
      operation = generated.operations.find do |item|
        item.kind == "write_file" && item.target.start_with?(".product-factory/runtime/lib/")
      end
      outside = File.realpath(Dir.mktmpdir("product-factory-verified-"))
      external_path = File.join(outside, operation.target.delete_prefix(".product-factory/runtime/"))
      FileUtils.mkdir_p(File.dirname(external_path))
      File.binwrite(external_path, operation.attributes.fetch("content_base64").unpack1("m0"))
      File.chmod(operation.attributes.fetch("mode"), external_path)
      FileUtils.mkdir_p(File.join(target, ".product-factory"))
      File.symlink(outside, File.join(target, ".product-factory/runtime"))
      state = ProductFactory::Installation.empty.with(
        "factory_file_hashes" => {
          operation.target => Digest::SHA256.file(external_path).hexdigest
        },
        "last_successful_setup_run" => generated.run_id
      ).to_h
      installation = ProductFactory::Operation.new(
        kind: "write_installation",
        target: ProductFactory::Installation::PATH,
        attributes: state
      )
      plan = ProductFactory::Plan.new(
        run_id: generated.run_id,
        mode: "setup",
        operations: [operation, installation],
        target_root: target
      )
      journal = ProductFactory::Journal.new(
        path: File.join(target, ".product-factory-journal.jsonl"),
        clock: -> { Time.utc(2026, 9, 2) }
      )
      journal.append(event: "run_confirmed", run_id: plan.run_id)
      journal.append(event: "operation_completed", run_id: plan.run_id, operation_id: operation.id)

      expect { setup.apply(plan) }
        .to raise_error(ProductFactory::ValidationError, /symlink/)
      expect(File.binread(external_path)).to eq(operation.attributes.fetch("content_base64").unpack1("m0"))
    ensure
      FileUtils.remove_entry(outside) if outside && File.exist?(outside)
    end
  end

  def build_setup(target)
    described_class.new(
      distribution_root: FileHelpers::FACTORY_ROOT,
      target_root: target,
      input: StringIO.new("yes\n"),
      output: StringIO.new,
      clock: -> { Time.utc(2026, 9, 2) }
    )
  end

  def build_full_setup(target, github:, wiki:, input: StringIO.new("Bootcamper\nyes\n"), output: StringIO.new)
    status = instance_double(Process::Status, success?: true, exitstatus: 0)
    shell = instance_double(ProductFactory::StreamShell)
    allow(shell).to receive(:capture3).and_return(["git@github.com:LIT-Bootcamp/bootcamper.git\n", "", status])
    described_class.new(
      distribution_root: FileHelpers::FACTORY_ROOT,
      target_root: target,
      input:,
      output:,
      clock: -> { Time.utc(2026, 9, 5) },
      shell:,
      github_client: github,
      github_state: github,
      github_writer: github,
      wiki_repository: wiki
    )
  end
end
