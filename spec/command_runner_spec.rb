# frozen_string_literal: true

require "openspec_pulse/command_runner"

RSpec.describe OpenspecPulse::CommandRunner do
  subject(:runner) { described_class.new }

  it "runs a real command and returns stdout, stderr and status" do
    result = runner.run("echo", "hello")
    expect(result.stdout).to eq("hello\n")
    expect(result.stderr).to eq("")
    expect(result).to be_success
  end

  it "runs in the given working directory" do
    Dir.mktmpdir do |dir|
      expect(runner.run("pwd", chdir: dir).stdout.strip).to eq(File.realpath(dir))
    end
  end

  it "reports a non-zero exit with its stderr" do
    result = runner.run("sh", "-c", "echo oops >&2; exit 3")
    expect(result).not_to be_success
    expect(result.exitstatus).to eq(3)
    expect(result.stderr).to eq("oops\n")
  end

  it "reports a missing command as a failure, not an exception" do
    result = runner.run("openspec-pulse-no-such-command")
    expect(result).not_to be_success
    expect(result).to be_missing
    expect(result.stderr).to match(/not found/)
  end
end

RSpec.describe FakeRunner do
  it "returns canned output for a matching command prefix" do
    runner = described_class.new.on("openspec", "list", stdout: "{}")
    expect(runner.run("openspec", "list", "--json").stdout).to eq("{}")
  end

  it "only matches a canned command in its directory when one is given" do
    runner = described_class.new.on("echo", chdir: "/somewhere", stdout: "canned")
    expect(runner.run("echo", "real", chdir: Dir.tmpdir).stdout).to eq("real\n")
  end
end
