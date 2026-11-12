# frozen_string_literal: true

require "json"
require "open3"

# The plugin runs bin/openspec-pulse straight after `omarchy plugin add`, with
# no `bundle install`, so the CLI must need nothing beyond Ruby itself.
RSpec.describe "bin/openspec-pulse with no gems installed" do
  BIN_PATH = File.expand_path("../bin/openspec-pulse", __dir__)

  around do |example|
    Dir.mktmpdir { |dir| @dir = File.realpath(dir); example.run }
  end

  # No Bundler environment, and an empty gem folder in place of the installed gems.
  def run_without_gems(*args)
    gems = FileUtils.mkdir_p(File.join(@dir, "gems")).first
    env = { "GEM_HOME" => gems, "GEM_PATH" => gems, "RUBYOPT" => nil, "BUNDLE_GEMFILE" => nil,
            "XDG_CONFIG_HOME" => File.join(@dir, "config"), "XDG_STATE_HOME" => File.join(@dir, "state") }
    Bundler.with_unbundled_env { Open3.capture3(env, BIN_PATH, *args, chdir: @dir) }
  end

  it "prints the version" do
    out, err, status = run_without_gems("version")
    expect(status).to be_success, err
    expect(out.strip).to eq(OpenspecPulse::VERSION)
  end

  it "prints the status report as JSON" do
    skip "openspec is not on PATH" unless system("command -v openspec >/dev/null")
    repo = init_repo(FileUtils.mkdir_p(File.join(@dir, "scan/tool")).first)
    write_change(repo, "quiet", "tasks.md", "- [x] 1.1 done\n- [ ] 1.2 open\n")
    commit_all(repo, at: Time.now - (30 * 86_400))
    FileUtils.mkdir_p(File.join(@dir, "config/openspec-pulse"))
    File.write(File.join(@dir, "config/openspec-pulse/config.yml"), "scan:\n  - #{@dir}/scan\n")

    out, err, status = run_without_gems("status", "--json")
    expect(status).to be_success, err
    expect(JSON.parse(out)["changes"].map { it["name"] }).to eq(["quiet"])
  end
end
