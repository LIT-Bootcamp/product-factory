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
end
