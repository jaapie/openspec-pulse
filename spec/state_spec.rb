# frozen_string_literal: true

require "date"
require "openspec_pulse/state"

RSpec.describe OpenspecPulse::State do
  around do |example|
    Dir.mktmpdir { |dir| @dir = dir; example.run }
  end

  describe ".dir" do
    it "uses XDG_STATE_HOME when set" do
      expect(described_class.dir({ "XDG_STATE_HOME" => "/tmp/st", "HOME" => "/h" })).to eq("/tmp/st/openspec-pulse")
    end

    it "falls back to ~/.local/state" do
      expect(described_class.dir({ "HOME" => "/h" })).to eq("/h/.local/state/openspec-pulse")
    end
  end

  let(:state) { described_class.new(dir: File.join(@dir, "openspec-pulse")) }

  describe "nudges" do
    it "is on by default" do
      expect(state.nudges?).to be(true)
    end

    it "persists off and on across instances" do
      state.nudges = false
      expect(described_class.new(dir: state.dir).nudges?).to be(false)
      state.nudges = true
      expect(described_class.new(dir: state.dir).nudges?).to be(true)
    end

    it "is stored as the word on or off in a file called nudges" do
      state.nudges = false
      expect(File.read(File.join(state.dir, "nudges")).strip).to eq("off")
    end
  end

  describe "last digest" do
    it "is nil when no digest has been sent" do
      expect(state.last_digest).to be_nil
    end

    it "persists as a single YYYY-MM-DD line" do
      state.last_digest = Date.new(2026, 11, 6)
      expect(File.read(File.join(state.dir, "last_digest"))).to eq("2026-11-06\n")
      expect(described_class.new(dir: state.dir).last_digest).to eq(Date.new(2026, 11, 6))
    end
  end

  describe "a state folder that can't be written" do
    before do
      FileUtils.mkdir_p(state.dir)
      File.chmod(0o500, state.dir)
    end

    after { File.chmod(0o700, state.dir) }

    it "raises an error naming the file when nudges can't be saved" do
      expect { state.nudges = false }
        .to raise_error(OpenspecPulse::StateError, /Could not save .*nudges/)
    end

    it "raises an error naming the file when the digest date can't be saved" do
      expect { state.last_digest = Date.new(2026, 11, 9) }
        .to raise_error(OpenspecPulse::StateError, /Could not save .*last_digest/)
    end
  end
end
