# frozen_string_literal: true

require "open3"

RSpec.describe "bin/openspec-pulse commands, help and input errors" do
  around do |example|
    Dir.mktmpdir { |dir| @dir = File.realpath(dir); example.run }
  end

  # No config, so a command that really ran would fail on the missing config.
  def run_cli(*args)
    env = { "XDG_CONFIG_HOME" => File.join(@dir, "config"), "XDG_STATE_HOME" => File.join(@dir, "state") }
    Open3.capture3(env, File.expand_path("../bin/openspec-pulse", __dir__), *args, chdir: @dir)
  end

  describe "help" do
    it "lists every command with a description when run with no arguments" do
      out, err, status = run_cli
      expect(status).to be_success
      expect(err).to eq("")
      expect(out).to include("Usage: openspec-pulse <command> [options]")
      expect(out).to match(/^  status \[--json\] +Show every active OpenSpec change, stalest first$/)
      expect(out).to match(/^  notify \[--force\] +Send the daily digest/)
      expect(out).to match(/^  nudges \[on\|off\] +Show, or turn on or off, the daily digest notification$/)
      expect(out).to match(/^  version +Print the version$/)
      expect(out).to match(/^  help \[command\] +/)
      expect(out).not_to include("tree")
    end

    it "prints the same list for help" do
      expect(run_cli("help")).to eq(run_cli)
    end

    it "describes one command with help <command>" do
      out, err, status = run_cli("help", "status")
      expect(status).to be_success
      expect(err).to eq("")
      expect(out).to include("Usage: openspec-pulse status [--json]")
      expect(out).to include("Show every active OpenSpec change, stalest first")
      expect(out).to match(/--json +Print JSON for the Omarchy plugin/)
    end

    it "describes notify's --force" do
      out, _err, status = run_cli("help", "notify")
      expect(status).to be_success
      expect(out).to include("Usage: openspec-pulse notify [--force]")
      expect(out).to match(/--force +Send now, ignoring the daily limit and the nudge setting/)
    end

    it "treats --help and -h after a command as help for it, without running it" do
      expected = run_cli("help", "status")
      expect(run_cli("status", "--help")).to eq(expected)
      expect(run_cli("status", "-h")).to eq(expected)
    end
  end

  describe "input it doesn't understand" do
    def expect_usage_error(args, *fragments)
      out, err, status = run_cli(*args)
      expect(status.exitstatus).to eq(1)
      expect(out).to eq("")
      fragments.each { expect(err).to include(it) }
      expect(err).not_to include("config.yml")
      expect(err.lines.size).to be <= 2
    end

    it "rejects an unknown command" do
      expect_usage_error(["bogus"], %(Unknown command "bogus"), "openspec-pulse help")
    end

    it "rejects help for an unknown command" do
      expect_usage_error(%w[help bogus], %(Unknown command "bogus"), "openspec-pulse help")
    end

    it "rejects an unknown option without running the command" do
      expect_usage_error(%w[status --bogus], %(Unknown option "--bogus" for status), "openspec-pulse help status")
    end

    it "rejects an abbreviated option rather than guessing" do
      expect_usage_error(%w[status --js], %(Unknown option "--js" for status))
      expect_usage_error(%w[status -j], %(Unknown option "-j" for status))
    end

    it "rejects Thor's old negative forms" do
      expect_usage_error(%w[status --no-json], %(Unknown option "--no-json" for status))
    end

    it "rejects an argument a command doesn't take" do
      expect_usage_error(%w[status extra], "status takes no arguments", "openspec-pulse help status")
    end

    it "rejects a second nudges argument" do
      expect_usage_error(%w[nudges on off], "nudges takes one argument at most", "openspec-pulse help nudges")
    end

    it "rejects a second help argument" do
      expect_usage_error(%w[help status extra], "help takes one argument at most")
    end

    it "rejects a nudges setting other than on or off, leaving it unchanged" do
      expect_usage_error(%w[nudges maybe], %(nudges takes on or off, not "maybe"))
      expect(File).not_to exist(File.join(@dir, "state/openspec-pulse/nudges"))
    end
  end
end
