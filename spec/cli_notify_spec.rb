# frozen_string_literal: true

require "open3"
require "shellwords"

RSpec.describe "bin/openspec-pulse notify" do
  around do |example|
    Dir.mktmpdir { |dir| @dir = File.realpath(dir); example.run }
  end

  # A stale change end to end: a git repo whose change folder was last committed 91 days ago.
  before do
    skip "openspec is not on PATH" unless system("command -v openspec >/dev/null")
    repo = init_repo(FileUtils.mkdir_p(File.join(@dir, "scan/tool")).first)
    write_change(repo, "quiet", "tasks.md", "- [x] 1.1 done\n- [ ] 1.2 open\n")
    commit_all(repo, at: Time.now - (91 * 86_400))
    FileUtils.mkdir_p(File.join(@dir, "config/openspec-pulse"))
    File.write(File.join(@dir, "config/openspec-pulse/config.yml"), "scan:\n  - #{@dir}/scan\n")
    FileUtils.mkdir_p(File.join(@dir, "fakebin"))
  end

  def fake_notify_send(script)
    path = File.join(@dir, "fakebin/omarchy-notification-send")
    File.write(path, "#!/bin/sh\n#{script}\n")
    File.chmod(0o755, path)
  end

  def run_cli(*args)
    env = { "XDG_CONFIG_HOME" => File.join(@dir, "config"), "XDG_STATE_HOME" => File.join(@dir, "state"),
            "PATH" => "#{File.join(@dir, 'fakebin')}:#{ENV.fetch('PATH')}" }
    Open3.capture3(env, File.expand_path("../bin/openspec-pulse", __dir__), "notify", *args, chdir: @dir)
  end

  let(:last_digest) { File.join(@dir, "state/openspec-pulse/last_digest") }

  it "sends the digest through omarchy-notification-send and records the date" do
    fake_notify_send(%(printf '%s\\n' "$@" > "#{@dir}/sent"))
    out, err, status = run_cli
    expect(status).to be_success, err
    expect(out).to include("Digest sent")
    sent = File.read(File.join(@dir, "sent")).lines.map(&:chomp)
    expect(sent).to include("You have 1 stale OpenSpec change.", "See more")
    # The bar's task-list glyph, drawn in the theme's text colour on light and dark cards.
    expect(sent[sent.index("-g") + 1]).to eq("\u{f4a0}")
    expect(sent).not_to include("--image")
    action = sent[(sent.index("See more") + 1)..]
    expect(action.first(2)).to eq(["sh", "-c"])
    script = action[2]
    # The panel if the plugin is there, else the floating status terminal.
    # summon opens the copy on the focused monitor; it answers "ok" or "unknown".
    expect(script).to start_with(%([ "$(omarchy-shell shell summon io.github.jaapie.openspec-pulse '{}' 2>/dev/null)" = ok ] || exec ))
    fallback = Shellwords.split(script.split(" || exec ", 2).last)
    expect(fallback.first).to eq("omarchy-launch-floating-terminal-with-presentation")
    expect(fallback).to include(start_with("PATH=#{Dir.home}/.local/share/mise/shims:"))
    expect(fallback.last(2)).to eq([File.expand_path("../bin/openspec-pulse", __dir__), "status"])
    expect(File.read(last_digest).strip).to eq(Date.today.iso8601)
  end

  it "exits non-zero and records nothing when the notification fails" do
    fake_notify_send("echo 'no bus' >&2; exit 1")
    _out, err, status = run_cli
    expect(status).not_to be_success
    expect(err).to include("omarchy notification send failed", "no bus")
    expect(File.exist?(last_digest)).to be(false)
  end
end
