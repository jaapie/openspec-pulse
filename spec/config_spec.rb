# frozen_string_literal: true

require "openspec_pulse/config"

RSpec.describe OpenspecPulse::Config do
  describe ".path" do
    it "uses XDG_CONFIG_HOME when set" do
      env = { "XDG_CONFIG_HOME" => "/tmp/cfg", "HOME" => "/home/someone" }
      expect(described_class.path(env)).to eq("/tmp/cfg/openspec-pulse/config.yml")
    end

    it "falls back to ~/.config when XDG_CONFIG_HOME is unset" do
      env = { "HOME" => "/home/someone" }
      expect(described_class.path(env)).to eq("/home/someone/.config/openspec-pulse/config.yml")
    end

    it "treats an empty XDG_CONFIG_HOME as unset" do
      env = { "XDG_CONFIG_HOME" => "", "HOME" => "/home/someone" }
      expect(described_class.path(env)).to eq("/home/someone/.config/openspec-pulse/config.yml")
    end
  end
end

RSpec.describe OpenspecPulse::Config, ".load" do
  around do |example|
    Dir.mktmpdir { |dir| @dir = dir; example.run }
  end

  let(:path) { File.join(@dir, "config.yml") }

  def write(text) = File.write(path, text)

  it "raises an error naming the path when the file is missing" do
    expect { described_class.load(path) }
      .to raise_error(OpenspecPulse::ConfigError, /#{Regexp.escape(path)}/)
  end

  it "raises an error naming the path when the YAML is broken" do
    write("scan: [unclosed\n")
    expect { described_class.load(path) }
      .to raise_error(OpenspecPulse::ConfigError, /#{Regexp.escape(path)}/)
  end

  it "raises an error when the file is not a mapping" do
    write("- just a list\n")
    expect { described_class.load(path) }
      .to raise_error(OpenspecPulse::ConfigError, /#{Regexp.escape(path)}/)
  end

  it "defaults stale_after_days to 14" do
    write("scan: []\n")
    expect(described_class.load(path).stale_after_days).to eq(14)
  end

  it "accepts a custom stale_after_days" do
    write("stale_after_days: 7\n")
    expect(described_class.load(path).stale_after_days).to eq(7)
  end

  it "rejects a stale_after_days that is not a positive integer" do
    write("stale_after_days: 0\n")
    expect { described_class.load(path) }
      .to raise_error(OpenspecPulse::ConfigError, /stale_after_days/)
  end

  it "expands a leading ~ in scan and repos" do
    write("scan:\n  - ~/code\nrepos:\n  - ~/elsewhere/tool\n  - /abs/path\n")
    config = described_class.load(path, home: "/home/someone")
    expect(config.scan).to eq(["/home/someone/code"])
    expect(config.repos).to eq(["/home/someone/elsewhere/tool", "/abs/path"])
  end

  it "treats missing scan and repos as empty lists" do
    write("stale_after_days: 14\n")
    config = described_class.load(path)
    expect(config.scan).to eq([])
    expect(config.repos).to eq([])
  end

  it "rejects scan when it is not a list" do
    write("scan: ~/code\n")
    expect { described_class.load(path) }
      .to raise_error(OpenspecPulse::ConfigError, /scan/)
  end
end
