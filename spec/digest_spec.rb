# frozen_string_literal: true

require "date"
require "openspec_pulse/digest"
require "openspec_pulse/report"
require "openspec_pulse/state"

RSpec.describe OpenspecPulse::Digest do
  def change(name, kind:, days:, stale: false, ready: 1)
    OpenspecPulse::Report::Change.new(
      repo: "r", repo_path: "/r", name:, path: "/r/openspec/changes/#{name}", last_touched: Time.now,
      touched_source: "git", days_quiet: days, kind:, openspec_status: "in-progress", stale:,
      done: 1, total: 1 + ready, ready:, openspec_done: 1, openspec_total: 1 + ready,
      count_mismatch: false, tasks_file: true, error: nil, groups: []
    )
  end

  def stale(name, days, ready = 1) = change(name, kind: "in_progress", days:, stale: true, ready:)
  def complete(name) = change(name, kind: "complete", days: 30, ready: 0)

  # Report lists changes already sorted; the digest relies on that order.
  def report(*changes) = Struct.new(:changes).new(OpenspecPulse::Report.sort(changes))

  describe "content (7.3)" do
    def message(*changes) = described_class.new(report(*changes)).message

    it "states both counts in one sentence" do
      stale_ones = (1..6).map { stale("s#{it}", 20 + it) }
      expect(message(*stale_ones, complete("x"), complete("y")))
        .to eq("You have 6 stale OpenSpec changes, and 2 changes ready to archive.")
    end

    it "leaves out the archive part when nothing is complete" do
      expect(message(stale("a", 30), stale("b", 20))).to eq("You have 2 stale OpenSpec changes.")
    end

    it "leaves out the stale part when nothing is stale" do
      expect(message(complete("x"), complete("y"))).to eq("You have 2 OpenSpec changes ready to archive.")
    end

    it "uses the singular for one of each" do
      expect(message(stale("a", 30), complete("x")))
        .to eq("You have 1 stale OpenSpec change, and 1 change ready to archive.")
      expect(message(stale("a", 30))).to eq("You have 1 stale OpenSpec change.")
      expect(message(complete("x"))).to eq("You have 1 OpenSpec change ready to archive.")
    end

    it "does not count in-progress changes that are not stale" do
      fresh = change("fresh", kind: "in_progress", days: 2)
      expect(message(stale("a", 30), fresh)).to eq("You have 1 stale OpenSpec change.")
    end

    it "is worth sending when only changes ready to archive exist" do
      expect(described_class.new(report(complete("x")))).to be_worth_sending
    end

    it "is not worth sending with nothing stale and nothing complete" do
      expect(described_class.new(report(change("new", kind: "not_started", days: 99)))).not_to be_worth_sending
    end
  end

  describe "sending (7.4)" do
    around do |example|
      Dir.mktmpdir { |dir| @dir = dir; example.run }
    end

    let(:state) { OpenspecPulse::State.new(dir: @dir) }
    let(:runner) { FakeRunner.new.on("omarchy-notification-send") }
    let(:see_more) { %w[omarchy-launch-floating-terminal-with-presentation env PATH=/shims:/usr/bin /repo/bin/openspec-pulse status] }
    let(:today) { Date.new(2026, 11, 6) }
    let(:stale_report) { report(stale("fix-stuck-firewall-registrations", 91, 10), complete("x")) }

    def deliver(rep = stale_report, force: false, on: today)
      described_class.new(rep).deliver(state:, runner:, today: on, force:, icon: "/repo/assets/icon.png", see_more:)
    end

    def sends = runner.calls.select { it[:command].first == "omarchy-notification-send" }

    it "sends once and records today's date" do
      expect(deliver).to eq(:sent)
      expect(sends.size).to eq(1)
      expect(sends.first[:command]).to eq([
        "omarchy-notification-send", "--app-name", "openspec-pulse", "-u", "normal",
        "--image", "/repo/assets/icon.png",
        "You have 1 stale OpenSpec change, and 1 change ready to archive.",
        "--action", "See more", *see_more
      ])
      expect(state.last_digest).to eq(today)
    end

    it "does not send a second time the same day" do
      deliver
      expect(deliver).to eq(:already_sent)
      expect(sends.size).to eq(1)
    end

    it "sends again the next day" do
      deliver
      expect(deliver(on: today + 1)).to eq(:sent)
      expect(state.last_digest).to eq(today + 1)
    end

    it "sends when only changes ready to archive exist" do
      expect(deliver(report(complete("x")))).to eq(:sent)
    end

    it "sends nothing when nothing is stale or ready to archive" do
      expect(deliver(report(change("new", kind: "not_started", days: 99)))).to eq(:nothing_to_report)
      expect(sends).to be_empty
      expect(state.last_digest).to be_nil
    end

    it "sends nothing with nudges off and leaves the date alone" do
      state.last_digest = today - 3
      state.nudges = false
      expect(deliver).to eq(:nudges_off)
      expect(sends).to be_empty
      expect(state.last_digest).to eq(today - 3)
    end

    it "sends after nudges are turned back on" do
      state.nudges = false
      deliver
      state.nudges = true
      expect(deliver).to eq(:sent)
    end

    it "sends with --force even when already sent today, without recording" do
      state.last_digest = today
      expect(deliver(force: true)).to eq(:sent)
      expect(sends.size).to eq(1)
    end

    it "sends with --force while nudges are off" do
      state.nudges = false
      expect(deliver(force: true)).to eq(:sent)
    end

    it "does not record the date for a forced send" do
      deliver(force: true)
      expect(state.last_digest).to be_nil
    end

    it "raises and does not record the date when omarchy-notification-send is missing" do
      runner.on("omarchy-notification-send", stderr: "command not found", exitstatus: 127, missing: true)
      expect { deliver }.to raise_error(OpenspecPulse::NotifyError, /omarchy-notification-send was not found/)
      expect(state.last_digest).to be_nil
    end

    it "raises and does not record the date when omarchy-notification-send fails" do
      runner.on("omarchy-notification-send", stderr: "no bus", exitstatus: 1)
      expect { deliver }.to raise_error(OpenspecPulse::NotifyError, /no bus/)
      expect(state.last_digest).to be_nil
    end
  end
end
