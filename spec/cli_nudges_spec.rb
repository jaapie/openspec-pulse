# frozen_string_literal: true

require "json"
require "open3"

RSpec.describe "bin/openspec-pulse nudges" do
  around do |example|
    Dir.mktmpdir { |dir| @dir = File.realpath(dir); example.run }
  end

  def run_cli(*args)
    env = { "XDG_CONFIG_HOME" => File.join(@dir, "config"), "XDG_STATE_HOME" => File.join(@dir, "state") }
    Open3.capture3(env, File.expand_path("../bin/openspec-pulse", __dir__), *args, chdir: @dir)
  end

  it "prints on when never set" do
    out, _err, status = run_cli("nudges")
    expect(status).to be_success
    expect(out).to eq("on\n")
  end

  it "turns nudges off and on, persisting under XDG_STATE_HOME" do
    expect(run_cli("nudges", "off").last).to be_success
    expect(run_cli("nudges").first).to eq("off\n")
    expect(File.read(File.join(@dir, "state/openspec-pulse/nudges")).strip).to eq("off")
    run_cli("nudges", "on")
    expect(run_cli("nudges").first).to eq("on\n")
  end

  it "rejects anything other than on or off" do
    _out, err, status = run_cli("nudges", "maybe")
    expect(status).not_to be_success
    expect(err).to match(/on or off/)
  end

  it "includes the setting in status --json" do
    FileUtils.mkdir_p(File.join(@dir, "config/openspec-pulse"))
    File.write(File.join(@dir, "config/openspec-pulse/config.yml"), "scan: []\n")
    run_cli("nudges", "off")
    expect(JSON.parse(run_cli("status", "--json").first)["nudges"]).to be(false)
  end

  it "exits non-zero with a one-line message, not a backtrace, when the setting can't be saved" do
    dir = File.join(@dir, "state/openspec-pulse")
    FileUtils.mkdir_p(dir)
    File.chmod(0o500, dir)
    _out, err, status = run_cli("nudges", "off")
    expect(status).not_to be_success
    expect(err).to match(/Could not save .*nudges/)
    expect(err).not_to include("state.rb:")
  ensure
    File.chmod(0o700, dir)
  end
end
