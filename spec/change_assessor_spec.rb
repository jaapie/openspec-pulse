# frozen_string_literal: true

require "openspec_pulse/change_assessor"
require "openspec_pulse/tasks_parser"

RSpec.describe OpenspecPulse::ChangeAssessor do
  let(:now) { Time.utc(2026, 11, 5, 12, 0, 0) }
  let(:assessor) { described_class.new(stale_after_days: 14, now:) }

  def tasks(done, total)
    list = Array.new(total) { |i| OpenspecPulse::TasksParser::Task.new(id: nil, text: "t#{i}", done: i < done, indent: 0) }
    OpenspecPulse::TasksParser::Result.new(
      groups: [OpenspecPulse::TasksParser::Group.new(title: "", tasks: list)], tasks_file: true
    )
  end

  def assess(done: 29, total: 39, days_ago: 0, hours: 0, openspec: nil)
    openspec ||= { "completedTasks" => done, "totalTasks" => total, "status" => "in-progress" }
    assessor.assess(tasks: tasks(done, total), openspec:, last_touched: now - (days_ago * 86_400) - (hours * 3600))
  end

  describe "days_quiet" do
    it "is whole days, rounded down" do
      expect(assess(days_ago: 91, hours: 3).days_quiet).to eq(91)
    end

    it "is never negative when last touched is in the future" do
      expect(assess(days_ago: -1).days_quiet).to eq(0)
    end
  end

  describe "kind" do
    it "is in_progress when some tasks are done" do
      expect(assess(done: 29, total: 39).kind).to eq("in_progress")
    end

    it "is not_started when no tasks are done" do
      expect(assess(done: 0, total: 37).kind).to eq("not_started")
    end

    it "is not_started when there are no tasks" do
      expect(assess(done: 0, total: 0).kind).to eq("not_started")
    end

    it "is complete when every task is done" do
      expect(assess(done: 14, total: 14).kind).to eq("complete")
    end

    it "is complete when OpenSpec says status complete" do
      openspec = { "completedTasks" => 3, "totalTasks" => 4, "status" => "complete" }
      expect(assess(done: 3, total: 4, openspec:).kind).to eq("complete")
    end
  end

  describe "stale" do
    it "is true for in_progress at the threshold" do
      expect(assess(done: 1, total: 2, days_ago: 14).stale).to be(true)
    end

    it "is false for in_progress under the threshold" do
      expect(assess(done: 1, total: 2, days_ago: 13, hours: 23).stale).to be(false)
    end

    it "is false for not_started however quiet" do
      expect(assess(done: 0, total: 2, days_ago: 200).stale).to be(false)
    end

    it "is false for complete however quiet" do
      expect(assess(done: 2, total: 2, days_ago: 200).stale).to be(false)
    end
  end

  it "counts ready as the tasks not done" do
    expect(assess(done: 29, total: 39).ready).to eq(10)
  end

  describe "count mismatch" do
    it "is false when the parsed counts match OpenSpec's" do
      result = assess(done: 29, total: 39)
      expect(result.count_mismatch).to be(false)
    end

    it "is true with both sets of counts when they differ, using parsed counts" do
      openspec = { "completedTasks" => 5, "totalTasks" => 19, "status" => "in-progress" }
      result = assess(done: 5, total: 20, openspec:)
      expect(result.count_mismatch).to be(true)
      expect([result.done, result.total]).to eq([5, 20])
      expect([result.openspec_done, result.openspec_total]).to eq([5, 19])
      expect(result.ready).to eq(15)
    end
  end
end
