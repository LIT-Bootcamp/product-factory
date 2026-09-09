# frozen_string_literal: true

RSpec.describe ProductFactory::Setup::ProductContextWizard do
  let(:answers) do
    {
      "mission" => "Help people learn with mentors",
      "target_users" => "Students and mentors",
      "primary_user_problem" => "Learning lacks feedback",
      "desired_outcome" => "Students complete guided courses",
      "markets_and_languages" => "Ukraine; Ukrainian and English",
      "competitor_seeds" => "Coursera, Udemy",
      "constraints" => "Small team",
      "non_goals" => "Marketplace"
    }
  end

  it "collects the Product Context answers when v1 is absent" do
    input = StringIO.new("#{answers.values.join("\n")}\n")

    expect(described_class.call(input:, output: StringIO.new, snapshot: { "documents" => {} },
                                document_ids: %w[context context/v1]))
      .to eq(answers)
  end

  it "repeats required prompts after blank input" do
    output = StringIO.new
    input = StringIO.new("\n#{answers.values.join("\n")}\n")

    described_class.call(input:, output:, snapshot: { "documents" => {} }, document_ids: %w[context context/v1])

    expect(output.string.scan("Mission: ").size).to eq(2)
  end

  it "raises instead of looping when a required answer reaches end of input" do
    expect do
      described_class.call(input: StringIO.new, output: StringIO.new, snapshot: { "documents" => {} },
                           document_ids: %w[context context/v1])
    end.to raise_error(ProductFactory::UsageError, "Mission is required")
  end

  it "accepts blank optional answers" do
    required = answers.values.first(5).join("\n")
    input = StringIO.new("#{required}\n\n\n\n")

    expect(described_class.call(input:, output: StringIO.new, snapshot: { "documents" => {} },
                                document_ids: %w[context context/v1]))
      .to include("competitor_seeds" => "", "constraints" => "", "non_goals" => "")
  end

  it "does not prompt when immutable Product Context already exists" do
    input = instance_double(StringIO)
    output = instance_double(StringIO)
    snapshot = {
      "documents" => {
        "context/v1" => <<~MD
          <!-- product-factory:v1:artifact:context/v1 -->
          # Product Context — Example Product

          ## Mission
          Help people learn with mentors
        MD
      }
    }

    allow(input).to receive(:gets)
    allow(output).to receive(:print)

    expect(described_class.call(
             input:, output:, snapshot:, document_ids: %w[context context/v1]
           )).to eq("mission" => "Help people learn with mentors")
    expect(input).not_to have_received(:gets)
    expect(output).not_to have_received(:print)
  end
end
