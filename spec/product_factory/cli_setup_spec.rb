# frozen_string_literal: true

RSpec.describe ProductFactory::CLI do
  it "leaves git status unchanged while planning" do
    in_tmp_repo do |target|
      raise "git init failed" unless system("git", "init", "-q", target)

      write(target, "README.md", "existing\n")
      raise "git add failed" unless system("git", "-C", target, "add", "README.md")

      status = -> { IO.popen(["git", "-C", target, "status", "--porcelain"], &:read) }
      before = status.call

      expect(described_class.start(["plan"], cwd: target, output: StringIO.new)).to eq(0)
      expect(status.call).to eq(before)
    end
  end

  it "plans without mutating the target and declines apply without mutation" do
    in_tmp_repo do |target|
      plan_output = StringIO.new
      expect(described_class.start(["plan"], cwd: target, output: plan_output)).to eq(0)
      expect(Dir.children(target)).to be_empty

      path = plan_output.string[/Plan path: (.+)\n/, 1]
      expect(
        described_class.start(["apply", path], cwd: target, input: StringIO.new("no\n"), output: StringIO.new)
      ).to eq(0)
      expect(Dir.children(target)).to be_empty
    end
  end

  it "installs files after a yes confirmation" do
    in_tmp_repo do |target|
      plan_output = StringIO.new
      described_class.start(["plan"], cwd: target, output: plan_output)
      path = plan_output.string[/Plan path: (.+)\n/, 1]

      expect(
        described_class.start(["apply", path], cwd: target, input: StringIO.new("yes\n"), output: StringIO.new)
      ).to eq(0)
      expect(File).to exist(File.join(target, ".product-factory/config.yml"))
      expect(File).to exist(File.join(target, ".product-factory/installation.yml"))
    end
  end

  it "preserves a config created after planning and stops before managed writes" do
    in_tmp_repo do |target|
      plan_output = StringIO.new
      described_class.start(["plan"], cwd: target, output: plan_output)
      path = plan_output.string[/Plan path: (.+)\n/, 1]
      write(target, ProductFactory::Config::PATH, "human: true\n")
      error = StringIO.new

      status = described_class.start(
        ["apply", path],
        cwd: target,
        input: StringIO.new("yes\n"),
        output: StringIO.new,
        error:
      )

      expect(status).to eq(2)
      expect(File.read(File.join(target, ProductFactory::Config::PATH))).to eq("human: true\n")
      expect(File).not_to exist(File.join(target, ".product-factory/runtime"))
    end
  end

  it "returns conflict status for a conflicted plan and never applies it" do
    in_tmp_repo do |target|
      plan = ProductFactory::Plan.new(
        run_id: "RUN-CONFLICT",
        mode: "refresh",
        operations: [],
        conflicts: [{ "path" => "managed.rb" }],
        target_root: target
      )
      path = File.join(Dir.tmpdir, "product-factory-conflict.json")
      plan.write(path)
      error = StringIO.new

      expect(described_class.start(["apply", path], cwd: target, error:)).to eq(2)
      expect(error.string).to include("plan has conflicts")
      expect(Dir.children(target)).to be_empty
    ensure
      File.delete(path) if path && File.exist?(path)
    end
  end

  it "returns conflict status when planning reports unresolved conflicts" do
    setup = instance_double(ProductFactory::Setup)
    allow(ProductFactory::Setup).to receive(:from_cli).and_return(setup)
    allow(setup).to receive(:plan_and_print).and_raise(ProductFactory::ConflictError, "plan has conflicts")
    error = StringIO.new

    expect(described_class.start(["plan"], error:)).to eq(2)
    expect(error.string).to include("plan has conflicts")
  end
end
