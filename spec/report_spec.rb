# frozen_string_literal: true

require "json"
require "openspec_pulse/report"

RSpec.describe OpenspecPulse::Report do
  around do |example|
    Dir.mktmpdir { |dir| @root = File.realpath(dir); example.run }
  end

  let(:now) { Time.utc(2026, 11, 5, 12, 0, 0) }
  let(:runner) { FakeRunner.new }

  def make_repo(name, changes = {})
    path = File.join(@root, name)
    FileUtils.mkdir_p(File.join(path, "openspec", "changes"))
    changes.each do |change, text|
      dir = File.join(path, "openspec", "changes", change)
      FileUtils.mkdir_p(dir)
      next if text.nil?

      File.write(File.join(dir, "tasks.md"), text)
      File.utime(now - (3 * 86_400), now - (3 * 86_400), File.join(dir, "tasks.md"))
    end
    OpenspecPulse::Discovery::Repo.new(path:, name:, error: nil)
  end

  def openspec_says(repo, *entries)
    runner.on("openspec", "list", chdir: repo.path, stdout: JSON.generate({ "changes" => entries }))
  end

  def entry(name, done, total, status = "in-progress")
    { "name" => name, "completedTasks" => done, "totalTasks" => total, "status" => status }
  end

  def build(repos, jira_url: nil)
    described_class.build(repos:, runner:, stale_after_days: 14, now:, nudges: true, jira_url:)
  end

  describe "reading repos (6.1)" do
    it "lists the changes openspec list --json reports, with the repo's name" do
      api = make_repo("acme-api", "add-inbound-tls" => "- [ ] 1.1 a\n",
                                   "secure-api-access" => "- [x] 1.1 a\n- [ ] 1.2 b\n")
      openspec_says(api, entry("add-inbound-tls", 0, 1), entry("secure-api-access", 1, 2))

      report = build([api])

      expect(report.changes.map { [it.repo, it.name] })
        .to contain_exactly(%w[acme-api add-inbound-tls], %w[acme-api secure-api-access])
      expect(runner.calls.map { it[:command] }).to include(%w[openspec list --json])
    end

    it "gives a repo an error when openspec is missing and still reports other repos" do
      broken = make_repo("broken")
      fine = make_repo("fine", "c" => "- [x] 1.1 a\n- [ ] 1.2 b\n")
      runner.on("openspec", chdir: broken.path, stderr: "openspec: command not found", exitstatus: 127, missing: true)
      openspec_says(fine, entry("c", 1, 2))

      report = build([broken, fine])

      expect(report.repos.find { it.name == "broken" }.error).to match(/openspec.*not found/i)
      expect(report.changes.map(&:name)).to eq(["c"])
    end

    it "gives a repo an error with stderr when openspec exits non-zero" do
      repo = make_repo("r")
      runner.on("openspec", chdir: repo.path, stderr: "boom\n", exitstatus: 1)
      expect(build([repo]).repos.first.error).to match(/boom/)
    end

    it "gives a repo an error when openspec prints invalid JSON" do
      repo = make_repo("r")
      runner.on("openspec", chdir: repo.path, stdout: "not json")
      expect(build([repo]).repos.first.error).to match(/JSON/)
    end

    it "gives a repo an error when the JSON is missing fields it relies on" do
      repo = make_repo("r", "c" => "- [ ] 1.1 a\n")
      runner.on("openspec", chdir: repo.path, stdout: JSON.generate({ "changes" => [{ "name" => "c" }] }))
      expect(build([repo]).repos.first.error).to match(/completedTasks/)
    end

    it "keeps a discovery error on the repo without running openspec" do
      repo = OpenspecPulse::Discovery::Repo.new(path: "/nope", name: "~/nope", error: "Scan root ~/nope does not exist")
      report = build([repo])
      expect(report.repos.first.error).to eq("Scan root ~/nope does not exist")
      expect(runner.calls).to be_empty
    end

    it "gives a change with an unreadable tasks.md an error, and it is not stale" do
      repo = make_repo("r", "locked" => "- [x] 1.1 a\n- [ ] 1.2 b\n")
      tasks = File.join(repo.path, "openspec/changes/locked/tasks.md")
      File.chmod(0o000, tasks)
      openspec_says(repo, entry("locked", 1, 2))

      change = build([repo]).changes.first

      expect(change.error).to match(/tasks\.md/)
      expect(change.stale).to be(false)
    ensure
      File.chmod(0o644, tasks) if tasks
    end

    it "treats a change without tasks.md as having no tasks" do
      repo = make_repo("r", "empty" => nil)
      openspec_says(repo, entry("empty", 0, 0, "no-tasks"))

      change = build([repo]).changes.first

      expect(change.tasks_file).to be(false)
      expect(change.kind).to eq("not_started")
      expect(change.error).to be_nil
    end
  end

  describe "purpose" do
    def write_proposal(repo, change, text)
      File.write(File.join(repo.path, "openspec/changes", change, "proposal.md"), text)
    end

    it "gives a change the purpose from its proposal" do
      repo = make_repo("acme-api", "add-rate-limits" => "- [ ] 1.1 a\n")
      write_proposal(repo, "add-rate-limits", "## Why\n\nJira: ABC-12.\n\nOne noisy client can starve the rest.\n")
      openspec_says(repo, entry("add-rate-limits", 0, 1))

      expect(build([repo]).changes.first.purpose).to eq("One noisy client can starve the rest.")
    end

    it "gives nil, and no error, when there is no proposal" do
      repo = make_repo("acme-api", "add-rate-limits" => "- [ ] 1.1 a\n")
      openspec_says(repo, entry("add-rate-limits", 0, 1))

      change = build([repo]).changes.first

      expect(change.purpose).to be_nil
      expect(change.error).to be_nil
    end

    it "keeps the purpose on a change with an unreadable tasks.md" do
      repo = make_repo("acme-api", "locked" => "- [x] 1.1 a\n")
      write_proposal(repo, "locked", "## Why\n\nRefunds vanish from the export.\n")
      tasks = File.join(repo.path, "openspec/changes/locked/tasks.md")
      File.chmod(0o000, tasks)
      openspec_says(repo, entry("locked", 1, 1))

      change = build([repo]).changes.first

      expect(change.error).to match(/tasks\.md/)
      expect(change.purpose).to eq("Refunds vanish from the export.")
    ensure
      File.chmod(0o644, tasks) if tasks
    end
  end

  describe "jira" do
    def change_with(proposal, jira_url: nil)
      repo = make_repo("acme-api", "add-rate-limits" => "- [ ] 1.1 a\n")
      if proposal
        File.write(File.join(repo.path, "openspec/changes/add-rate-limits/proposal.md"), proposal)
      end
      openspec_says(repo, entry("add-rate-limits", 0, 1))
      build([repo], jira_url:).changes.first
    end

    let(:proposal) { "## Why\n\nJira: ABC-12 (under epic ABC-1). One noisy client can starve the rest.\n" }

    it "gives the task key and its link when jira_url is set" do
      change = change_with(proposal, jira_url: "https://example.atlassian.net")
      expect(change.jira).to eq(key: "ABC-12", url: "https://example.atlassian.net/browse/ABC-12")
    end

    it "gives the key with no link when jira_url is not set" do
      expect(change_with(proposal).jira).to eq(key: "ABC-12", url: nil)
    end

    it "gives nil, and no error, when the proposal names no task" do
      change = change_with("## Why\n\nNo Jira. Refunds vanish.\n", jira_url: "https://example.atlassian.net")
      expect(change.jira).to be_nil
      expect(change.error).to be_nil
    end

    it "gives nil, and no error, when there is no proposal" do
      change = change_with(nil)
      expect(change.jira).to be_nil
      expect(change.error).to be_nil
    end

    it "puts jira in the JSON" do
      repo = make_repo("acme-api", "add-rate-limits" => "- [ ] 1.1 a\n")
      File.write(File.join(repo.path, "openspec/changes/add-rate-limits/proposal.md"), proposal)
      openspec_says(repo, entry("add-rate-limits", 0, 1))

      json = JSON.parse(build([repo], jira_url: "https://example.atlassian.net").to_json)

      expect(json["changes"].first["jira"])
        .to eq("key" => "ABC-12", "url" => "https://example.atlassian.net/browse/ABC-12")
    end
  end

  describe "sorting, summary and JSON (6.3)" do
    def change(repo:, name:, kind:, days:, stale: false, error: nil)
      described_class::Change.new(
        repo:, repo_path: "/r/#{repo}", name:, path: "/r/#{repo}/openspec/changes/#{name}",
        last_touched: now - (days * 86_400), touched_source: "git", days_quiet: days,
        kind:, openspec_status: "in-progress", stale:, done: 1, total: 2, ready: 1,
        openspec_done: 1, openspec_total: 2, count_mismatch: false, tasks_file: true, error:, groups: [], purpose: nil, jira: nil
      )
    end

    it "orders stale, complete, other in progress, then not started" do
      list = [
        change(repo: "a", name: "done", kind: "complete", days: 300),
        change(repo: "a", name: "new", kind: "not_started", days: 400),
        change(repo: "a", name: "fresh", kind: "in_progress", days: 2),
        change(repo: "a", name: "quiet", kind: "in_progress", days: 91, stale: true)
      ]
      expect(described_class.sort(list).map(&:name)).to eq(%w[quiet done fresh new])
    end

    it "puts the quietest first among stale and among other in progress" do
      list = [
        change(repo: "a", name: "s20", kind: "in_progress", days: 20, stale: true),
        change(repo: "a", name: "s91", kind: "in_progress", days: 91, stale: true),
        change(repo: "a", name: "p1", kind: "in_progress", days: 1),
        change(repo: "a", name: "p9", kind: "in_progress", days: 9)
      ]
      expect(described_class.sort(list).map(&:name)).to eq(%w[s91 s20 p9 p1])
    end

    it "breaks ties by repo name, then change name" do
      list = [
        change(repo: "b", name: "x", kind: "complete", days: 5),
        change(repo: "a", name: "z", kind: "complete", days: 1),
        change(repo: "a", name: "y", kind: "complete", days: 9)
      ]
      expect(described_class.sort(list).map { "#{it.repo}/#{it.name}" }).to eq(%w[a/y a/z b/x])
    end

    it "puts changes with errors after not started" do
      list = [
        change(repo: "a", name: "broken", kind: nil, days: 1, error: "Could not read tasks.md"),
        change(repo: "a", name: "new", kind: "not_started", days: 1)
      ]
      expect(described_class.sort(list).map(&:name)).to eq(%w[new broken])
    end

    describe "a built report" do
      let(:report) do
        repo = make_repo("acme-api", "stale-one" => "## 1. Group\n\n- [x] 1.1 a\n- [ ] 1.2 b\n",
                                   "fresh-one" => "- [x] 1.1 a\n- [ ] 1.2 b\n",
                                   "done-one" => "- [x] 1.1 a\n",
                                   "new-one" => "- [ ] 1.1 a\n",
                                   "locked" => "- [ ] 1.1 a\n")
        stale_tasks = File.join(repo.path, "openspec/changes/stale-one/tasks.md")
        File.utime(now - (91 * 86_400), now - (91 * 86_400), stale_tasks)
        File.chmod(0o000, File.join(repo.path, "openspec/changes/locked/tasks.md"))
        openspec_says(repo, entry("locked", 0, 1), entry("new-one", 0, 1), entry("done-one", 1, 1, "complete"),
                      entry("fresh-one", 1, 2), entry("stale-one", 1, 2))
        broken = make_repo("broken")
        runner.on("openspec", chdir: broken.path, stdout: "nope")
        build([repo, broken])
      ensure
        File.chmod(0o644, File.join(@root, "acme-api/openspec/changes/locked/tasks.md"))
      end

      it "returns changes already sorted" do
        expect(report.changes.map(&:name)).to eq(%w[stale-one done-one fresh-one new-one locked])
      end

      it "summarises counts, including repo and change errors" do
        expect(report.summary).to eq(
          changes: 5, stale: 1, in_progress: 2, not_started: 1, complete: 1, errors: 2
        )
      end

      it "prints one JSON document with every listed field" do
        json = JSON.parse(report.to_json)

        expect(json.keys).to contain_exactly("generated_at", "stale_after_days", "nudges", "summary", "repos", "changes")
        expect(json["nudges"]).to be(true)
        expect(json["stale_after_days"]).to eq(14)
        expect(json["generated_at"]).to eq("2026-11-05T12:00:00Z")
        expect(json["summary"].keys)
          .to contain_exactly("changes", "stale", "in_progress", "not_started", "complete", "errors")
        expect(json["repos"].first.keys).to contain_exactly("path", "name", "error")
        expect(json["changes"].first.keys).to include(
          "repo", "repo_path", "name", "path", "last_touched", "touched_source", "days_quiet", "kind",
          "openspec_status", "stale", "done", "total", "ready", "count_mismatch", "tasks_file", "error", "groups", "purpose", "jira"
        )
        stale = json["changes"].first
        expect(stale).to include("name" => "stale-one", "days_quiet" => 91, "stale" => true, "ready" => 1,
                                 "touched_source" => "mtime")
        expect(stale["groups"]).to eq([
          { "title" => "1. Group", "done" => 1, "total" => 2, "tasks" => [
            { "id" => "1.1", "text" => "a", "done" => true, "indent" => 0 },
            { "id" => "1.2", "text" => "b", "done" => false, "indent" => 0 }
          ] }
        ])
      end
    end
  end

  describe "table output (6.5)" do
    let(:table) do
      repo = make_repo("acme-api", "fresh-one" => "- [x] 1.1 a\n- [ ] 1.2 b\n",
                                 "stale-one" => "- [x] 1.1 a\n- [ ] 1.2 b\n",
                                 "done-one" => "- [x] 1.1 a\n",
                                 "drift" => "- [x] 1.1 a\n- [ ] 1.2 b\n",
                                 "new-one" => "- [ ] 1.1 a\n")
      File.utime(now - (91 * 86_400), now - (91 * 86_400), File.join(repo.path, "openspec/changes/stale-one/tasks.md"))
      openspec_says(repo, entry("fresh-one", 1, 2), entry("done-one", 1, 1, "complete"),
                    entry("stale-one", 1, 2), entry("drift", 1, 3), entry("new-one", 0, 1))
      broken = make_repo("broken")
      runner.on("openspec", chdir: broken.path, stderr: "boom", exitstatus: 2)
      build([repo, broken]).to_table
    end

    def row(name) = table.lines.find { it.include?(name) }&.chomp

    it "puts the stale change first and marks it" do
      first_row = table.lines[1].chomp
      expect(first_row).to include("stale-one", "1/2", "91d")
      expect(first_row).to match(/\bstale\z/)
    end

    it "marks a fresh in-progress change as in progress" do
      expect(row("fresh-one")).to match(/\bin progress\z/)
    end

    it "shows a stale change only as stale, not also in progress" do
      expect(row("stale-one")).not_to include("in progress")
    end

    it "marks a change with no ticked tasks as not started" do
      expect(row("new-one")).to match(/\bnot started\z/)
    end

    it "marks complete changes as ready to archive" do
      expect(row("done-one")).to include("ready to archive")
    end

    it "notes a count mismatch with OpenSpec's numbers" do
      expect(row("drift")).to include("openspec says 1/3")
    end

    it "lists repo errors after the changes" do
      error_at = table.lines.index { it.include?("broken") }
      last_change = table.lines.rindex { it.match?(/new-one|drift|done-one|fresh-one/) }
      expect(error_at).to be > last_change
      expect(table.lines[error_at]).to include("boom")
    end
  end
end
