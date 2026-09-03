# frozen_string_literal: true

RSpec.describe ProductFactory::Doctor do
  it "reports missing gh without running setup" do
    commands = []
    runner = lambda do |*command|
      commands << command
      case command
      when ["ruby", "--version"] then [true, "ruby 4.0.6"]
      when ["git", "--version"] then [true, "git version 2.0"]
      when ["gh", "--version"] then [false, "missing"]
      when ["git", "-C", Dir.pwd, "rev-parse", "--is-inside-work-tree"] then [true, "true"]
      else [false, "unexpected command"]
      end
    end
    checks = described_class.new(root: Dir.pwd, command_runner: runner).call

    expect(checks.find { |check| check.name == "ruby" }.status).to eq(:pass)
    expect(checks.find { |check| check.name == "gh" }.status).to eq(:fail)
    expect(checks.find { |check| check.name == "work_tree" }.status).to eq(:pass)
    expect(commands).to include(["git", "-C", Dir.pwd, "rev-parse", "--is-inside-work-tree"])
  end

  it "requires Ruby 4.0.6 exactly" do
    runner = ->(*command) { [true, command.first == "ruby" ? "ruby 4.0.7" : "true"] }

    check = described_class.new(root: Dir.pwd, command_runner: runner).call
                           .find { |result| result.name == "ruby" }

    expect(check.status).to eq(:fail)
  end

  it "does not accept knowledge reached through a symlink" do
    in_tmp_repo do |root|
      config = YAML.safe_load_file(File.expand_path("../../templates/config.yml", __dir__))
      config.fetch("knowledge")["paths"] = ["docs/external"]
      write(root, ProductFactory::Config::PATH, YAML.dump(config))
      ProductFactory::Installation.empty.write(root)
      outside = File.realpath(Dir.mktmpdir("product-factory-knowledge-"))
      File.write(File.join(outside, "external"), "outside\n")
      FileUtils.mkdir_p(File.join(root, "docs"))
      File.symlink(File.join(outside, "external"), File.join(root, "docs/external"))
      runner = ->(*command) { [true, command.first == "ruby" ? "ruby 4.0.6" : "true"] }

      check = described_class.new(root:, command_runner: runner).call
                             .find { |result| result.name == "knowledge" }

      expect(check.status).to eq(:fail)
    ensure
      FileUtils.remove_entry(outside) if outside && File.exist?(outside)
    end
  end
end
