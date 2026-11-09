# frozen_string_literal: true

require "json"
require "open3"

RSpec.describe "openspec-pulse status is read-only towards repos" do
  around do |example|
    Dir.mktmpdir { |dir| @dir = File.realpath(dir); example.run }
  end

  it "leaves git status --porcelain and the index unchanged" do
    skip "openspec is not on PATH" unless system("command -v openspec >/dev/null")

    repo = init_repo(FileUtils.mkdir_p(File.join(@dir, "scan/tool")).first)
    write_change(repo, "quiet", "tasks.md", "## 1. A\n\n- [x] 1.1 done\n- [ ] 1.2 open\n")
    busy = write_change(repo, "busy", "tasks.md", "- [x] 1.1 done\n- [ ] 1.2 open\n")
    commit_all(repo, at: Time.utc(2026, 8, 6))
    File.write(busy, "- [x] 1.1 done\n- [x] 1.2 open\n")
    write_change(repo, "brand-new", "tasks.md", "- [ ] 1.1 open\n")
    FileUtils.touch(File.join(repo, "openspec/changes/quiet/tasks.md"), mtime: Time.now + 60)

    snapshot = lambda do
      [git(repo, "status", "--porcelain", "--untracked-files=all", env: { "GIT_OPTIONAL_LOCKS" => "0" }),
       File.binread(File.join(repo, ".git/index")),
       Dir.glob("**/*", File::FNM_DOTMATCH, base: repo).sort]
    end
    before = snapshot.call

    FileUtils.mkdir_p(File.join(@dir, "config/openspec-pulse"))
    File.write(File.join(@dir, "config/openspec-pulse/config.yml"), "scan:\n  - #{@dir}/scan\n")
    env = { "XDG_CONFIG_HOME" => File.join(@dir, "config"), "XDG_STATE_HOME" => File.join(@dir, "state") }
    out, err, status = Open3.capture3(env, File.expand_path("../bin/openspec-pulse", __dir__), "status", "--json")

    expect(status).to be_success, err
    expect(JSON.parse(out)["changes"].map { it["name"] }).to contain_exactly("quiet", "busy", "brand-new")
    expect(snapshot.call).to eq(before)
  end
end
