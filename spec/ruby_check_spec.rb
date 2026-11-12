# frozen_string_literal: true

require "openspec_pulse/ruby_check"

RSpec.describe OpenspecPulse::RubyCheck do
  it "names the Ruby it found and the one it needs when it's too old" do
    expect(described_class.problem("3.3.6")).to eq("openspec-pulse needs Ruby 3.4 or later, but this is Ruby 3.3.6.")
  end

  it "has no problem with Ruby 3.4, which Arch's ruby package installs" do
    expect(described_class.problem("3.4.10")).to be_nil
  end

  it "has no problem with Ruby 4.0" do
    expect(described_class.problem("4.0.7")).to be_nil
  end
end
