# frozen_string_literal: true

require "json"
require "open3"

RSpec.describe "bin/openspec-pulse status" do
  BIN = File.expand_path("../bin/openspec-pulse", __dir__)

  around do |example|
    Dir.mktmpdir { |dir| @dir = File.realpath(dir); example.run }
  end

  def run_cli(*args)
    env = { "XDG_CONFIG_HOME" => File.join(@dir, "config"), "XDG_STATE_HOME" => File.join(@dir, "state") }
    Open3.capture3(env, BIN, *args, chdir: @dir)
  end

  def write_config(text)
    FileUtils.mkdir_p(File.join(@dir, "config/openspec-pulse"))
    File.write(File.join(@dir, "config/openspec-pulse/config.yml"), text)
  end

  it "exits non-zero naming the config path when there is no config" do
    _out, err, status = run_cli("status")
    expect(status).not_to be_success
    expect(err).to include(File.join(@dir, "config/openspec-pulse/config.yml"))
  end

  it "exits non-zero for --json too, printing nothing on stdout" do
    out, _err, status = run_cli("status", "--json")
    expect(status).not_to be_success
    expect(out).to eq("")
  end

  it "exits 0 with a partial error and reports it" do
    write_config("scan:\n  - #{@dir}/missing\n")
    out, _err, status = run_cli("status", "--json")
    expect(status).to be_success
    json = JSON.parse(out)
    expect(json["repos"].first["error"]).to match(/does not exist/)
    expect(json["summary"]["errors"]).to eq(1)
  end

  it "prints the table without --json" do
    write_config("scan:\n  - #{@dir}/missing\n")
    out, _err, status = run_cli("status")
    expect(status).to be_success
    expect(out).to include("does not exist")
  end
end
