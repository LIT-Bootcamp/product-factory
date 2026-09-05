# frozen_string_literal: true

RSpec.describe ProductFactory do
  it "loads every component through Zeitwerk" do
    expect { Zeitwerk::Loader.eager_load_all }.not_to raise_error
  end
end
