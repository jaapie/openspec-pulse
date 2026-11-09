# frozen_string_literal: true

module OpenspecPulse
  # Per-change judgements: days quiet, kind, stale, ready, count mismatch.
  class ChangeAssessor
    Assessment = Data.define(
      :days_quiet, :kind, :stale, :done, :total, :ready,
      :openspec_done, :openspec_total, :openspec_status, :count_mismatch
    )

    SECONDS_PER_DAY = 86_400

    def initialize(stale_after_days:, now:)
      @stale_after_days = stale_after_days
      @now = now
    end

    def assess(tasks:, openspec:, last_touched:)
      done = tasks.done
      total = tasks.total
      days_quiet = days_quiet(last_touched)
      kind = kind_of(done, total, openspec["status"])
      Assessment.new(
        days_quiet:, kind:, done:, total:,
        stale: kind == "in_progress" && days_quiet >= @stale_after_days,
        ready: total - done,
        openspec_done: openspec["completedTasks"],
        openspec_total: openspec["totalTasks"],
        openspec_status: openspec["status"],
        count_mismatch: [done, total] != [openspec["completedTasks"], openspec["totalTasks"]]
      )
    end

    def days_quiet(last_touched) = [((@now - last_touched) / SECONDS_PER_DAY).floor, 0].max

    private

    def kind_of(done, total, status)
      return "complete" if status == "complete" || (total.positive? && done == total)
      return "not_started" if done.zero?

      "in_progress"
    end
  end
end
