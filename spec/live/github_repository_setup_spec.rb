# frozen_string_literal: true

RSpec.describe ProductFactory::CLI, :live_github do
  it "converges the exact private sandbox with repository artifacts and no Git mutation" do
    raise "live sandbox confirmation is missing" unless live_github_enabled?

    Dir.mktmpdir("product-factory-live") do |temporary|
      target = File.join(File.realpath(temporary), "application")
      clone_sandbox(target)
      verify_remote_config!(target)
      local_head_before = head(target)
      remote_head_before = remote_head(target)
      first_output = StringIO.new
      first = described_class.start(
        ["setup"], cwd: target, input: setup_input(target), output: first_output, error: first_output
      )
      second_output = StringIO.new
      second = described_class.start(
        ["setup"], cwd: target, input: StringIO.new, output: second_output, error: second_output
      )

      expect(head(target)).to eq(local_head_before)
      expect(remote_head(target)).to eq(remote_head_before)
      expect(first).to eq(0), first_output.string
      expect(second).to eq(0), second_output.string
      expect(repository_visibility).to eq("PRIVATE")
      expect(ProductFactory::Config.load(target).artifacts)
        .to eq("adapter" => "repository", "root" => "product")
      expect(ProductFactory::Installation.load(target).artifact_adapter).to eq("repository")
      expect_repository_documents(target)
      expect(second_output.string).to include("Product Factory is up to date")
    end
  end

  private

  def clone_sandbox(target)
    run!(
      "git", "-c", "credential.https://github.com.helper=!gh auth git-credential",
      "clone", "--quiet", "https://github.com/#{LiveGitHub::REPOSITORY}.git", target
    )
  end

  def setup_input(target)
    return StringIO.new("yes\n") if File.exist?(File.join(target, ProductFactory::Config::PATH))

    StringIO.new("Product Factory Sandbox\nyes\n")
  end

  def verify_remote_config!(target)
    path = File.join(target, ProductFactory::Config::PATH)
    return unless File.exist?(path)
    return if ProductFactory::Config.load(target).artifacts == { "adapter" => "repository", "root" => "product" }

    raise "sandbox config does not select repository artifacts under product/"
  end

  def expect_repository_documents(target)
    paths = Dir.glob(File.join(target, "product/**/*.md")).map { |path| path.delete_prefix("#{target}/") }
    expect(paths).to match_array(documents.keys)
    documents.each do |path, document|
      expect(File.binread(File.join(target, path))).to include("product-factory:v1:artifact:#{document}")
    end
  end

  def documents
    {
      "product/README.md" => "index",
      "product/setup-log.md" => "setup-log",
      "product/ideas/README.md" => "ideas/index",
      "product/epics/README.md" => "epics/index",
      "product/tickets/README.md" => "tickets/index",
      "product/research/README.md" => "research/index",
      "product/factory-runs/README.md" => "factory-runs/index"
    }
  end

  def repository_visibility
    JSON.parse(run!("gh", "repo", "view", LiveGitHub::REPOSITORY, "--json", "visibility")).fetch("visibility")
  end

  def head(target) = run!("git", "-C", target, "rev-parse", "HEAD").strip
  def remote_head(target) = run!("git", "-C", target, "ls-remote", "origin", "HEAD").split.first

  def run!(*command)
    output, error, status = Open3.capture3(*command)
    raise error unless status.success?

    output
  end
end
