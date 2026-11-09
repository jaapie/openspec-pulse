# frozen_string_literal: true

require "openspec_pulse/git_clock"

RSpec.describe OpenspecPulse::GitClock do
  around do |example|
    Dir.mktmpdir { |dir| @repo = File.realpath(dir); example.run }
  end

  let(:now) { Time.utc(2026, 11, 5, 12, 0, 0) }
  let(:clock) { described_class.new(runner: OpenspecPulse::CommandRunner.new, now: -> { now }) }

  def touched(name) = clock.last_touched(@repo, name)

  it "uses the latest commit touching the change folder" do
    init_repo(@repo)
    write_change(@repo, "quiet")
    commit_all(@repo, at: Time.utc(2026, 8, 6, 5, 57, 0))
    write_change(@repo, "other")
    commit_all(@repo, at: Time.utc(2026, 11, 1, 0, 0, 0))

    expect(touched("quiet")).to eq([Time.utc(2026, 8, 6, 5, 57, 0), "git"])
  end

  it "uses the commit time, not the author time" do
    init_repo(@repo)
    write_change(@repo, "rebased")
    git(@repo, "add", "-A")
    git(@repo, "commit", "-q", "-m", "x", env: {
      "GIT_AUTHOR_DATE" => "2026-01-01T00:00:00Z", "GIT_COMMITTER_DATE" => "2026-09-01T00:00:00Z"
    })
    expect(touched("rebased").first).to eq(Time.utc(2026, 9, 1))
  end

  it "gives now when the change folder has uncommitted edits" do
    init_repo(@repo)
    path = write_change(@repo, "busy")
    commit_all(@repo, at: Time.utc(2026, 8, 6))
    File.write(path, "- [x] 1.1 something\n")

    expect(touched("busy")).to eq([now, "git"])
  end

  it "gives now when a new untracked file sits in a committed change folder" do
    init_repo(@repo)
    write_change(@repo, "busy")
    commit_all(@repo, at: Time.utc(2026, 8, 6))
    write_change(@repo, "busy", "design.md", "# Design\n")

    expect(touched("busy")).to eq([now, "git"])
  end

  it "ignores uncommitted edits in other change folders" do
    init_repo(@repo)
    write_change(@repo, "quiet")
    other = write_change(@repo, "other")
    commit_all(@repo, at: Time.utc(2026, 8, 6))
    File.write(other, "edited\n")

    expect(touched("quiet")).to eq([Time.utc(2026, 8, 6), "git"])
  end

  it "falls back to the newest file mtime for a never-committed folder" do
    init_repo(@repo)
    write_change(@repo, "committed")
    commit_all(@repo, at: Time.utc(2026, 8, 6))
    tasks = write_change(@repo, "fresh")
    design = write_change(@repo, "fresh", "specs/x/spec.md", "spec\n")
    File.utime(Time.utc(2026, 10, 1), Time.utc(2026, 10, 1), tasks)
    File.utime(Time.utc(2026, 10, 3), Time.utc(2026, 10, 3), design)

    expect(touched("fresh")).to eq([Time.utc(2026, 10, 3), "mtime"])
  end

  it "falls back to mtime in a repo that is not a git repo" do
    tasks = write_change(@repo, "plain")
    File.utime(Time.utc(2026, 9, 9), Time.utc(2026, 9, 9), tasks)

    expect(touched("plain")).to eq([Time.utc(2026, 9, 9), "mtime"])
  end

  it "does not rewrite the git index while checking for edits" do
    init_repo(@repo)
    path = write_change(@repo, "busy")
    commit_all(@repo, at: Time.utc(2026, 8, 6))
    FileUtils.touch(path, mtime: Time.now + 60) # stale stat data makes plain `git status` refresh the index
    index = File.join(@repo, ".git", "index")
    before = [File.mtime(index), File.binread(index)]

    touched("busy")

    expect([File.mtime(index), File.binread(index)]).to eq(before)
  end

  it "never runs a program named in the repo's own core.fsmonitor setting" do
    init_repo(@repo)
    write_change(@repo, "quiet")
    commit_all(@repo, at: Time.utc(2026, 8, 6))
    marker = File.join(@repo, "fsmonitor-ran")
    hook = File.join(@repo, "hook.sh")
    File.write(hook, "#!/bin/sh\ntouch #{marker}\n")
    File.chmod(0o755, hook)
    git(@repo, "config", "core.fsmonitor", hook)

    touched("quiet")

    expect(File).not_to exist(marker)
  end

  it "never runs a gpg.program the repo's own config names for showing signatures" do
    init_repo(@repo)
    write_change(@repo, "quiet")
    commit_all(@repo, at: Time.utc(2026, 8, 6))
    # Rewrite HEAD as a commit that carries a (fake) signature, so showing
    # signatures would make git call gpg.program.
    tree = git(@repo, "rev-parse", "HEAD^{tree}").strip
    stamp = "Spec <spec@example.invalid> #{Time.utc(2026, 8, 6).to_i} +0000"
    raw = "tree #{tree}\nauthor #{stamp}\ncommitter #{stamp}\n" \
          "gpgsig -----BEGIN PGP SIGNATURE-----\n \n -----END PGP SIGNATURE-----\n\nsigned\n"
    signed = Open3.capture2("git", "hash-object", "-t", "commit", "-w", "--stdin", stdin_data: raw, chdir: @repo).first.strip
    git(@repo, "update-ref", "HEAD", signed)
    marker = File.join(@repo, "gpg-ran")
    fake_gpg = File.join(@repo, "gpg.sh")
    File.write(fake_gpg, "#!/bin/sh\ntouch #{marker}\nexit 1\n")
    File.chmod(0o755, fake_gpg)
    git(@repo, "config", "log.showSignature", "true")
    git(@repo, "config", "gpg.program", fake_gpg)

    touched("quiet")

    expect(File).not_to exist(marker)
  end

  it "treats a path inside a .git folder as not a git work tree" do
    init_repo(@repo)
    write_change(@repo, "quiet")
    commit_all(@repo, at: Time.utc(2026, 8, 6))
    inside = File.join(@repo, ".git")
    tasks = write_change(inside, "odd")
    File.utime(Time.utc(2026, 9, 9), Time.utc(2026, 9, 9), tasks)

    expect(clock.last_touched(inside, "odd")).to eq([Time.utc(2026, 9, 9), "mtime"])
  end

  it "never runs a clean filter the repo's own config defines, and still sees the edit" do
    init_repo(@repo)
    tasks = write_change(@repo, "busy")
    File.write(File.join(@repo, ".gitattributes"), "* filter=planted\n")
    commit_all(@repo, at: Time.utc(2026, 8, 6))
    marker = File.join(@repo, "filter-ran")
    filter = File.join(@repo, "filter.sh")
    File.write(filter, "#!/bin/sh\ntouch #{marker}\ncat\n")
    File.chmod(0o755, filter)
    git(@repo, "config", "filter.planted.clean", filter)
    File.write(tasks, "- [x] 1.1 something\n")

    result = touched("busy")

    expect(File).not_to exist(marker)
    expect(result).to eq([now, "git"])
  end
end
