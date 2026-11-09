# frozen_string_literal: true

RSpec.describe OpenspecPulse do
  it "has a version" do
    expect(OpenspecPulse::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
  end
end
