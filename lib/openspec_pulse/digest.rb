# frozen_string_literal: true

require_relative "../openspec_pulse"

module OpenspecPulse
  class NotifyError < Error; end

  # The once-a-day desktop notification (spec: stale-digest). It states the
  # counts only; the plugin's panel holds the details.
  class Digest
    def initialize(report)
      @stale = report.changes.count(&:stale)
      @complete = report.changes.count { it.kind == "complete" && !it.error }
    end

    def worth_sending? = @stale.positive? || @complete.positive?

    def message
      parts = []
      parts << "#{@stale} stale OpenSpec #{plural(@stale, 'change')}" if @stale.positive?
      if @complete.positive?
        noun = @stale.positive? ? plural(@complete, "change") : "OpenSpec #{plural(@complete, 'change')}"
        parts << "#{@complete} #{noun} ready to archive"
      end
      "You have #{parts.join(', and ')}."
    end

    # Returns :sent, :nothing_to_report, :nudges_off or :already_sent.
    # A forced send ignores the daily limit and the nudge setting, and doesn't record the date.
    # see_more is the argv the shell runs when the card or its See more button
    # is clicked.
    def deliver(state:, runner:, today:, see_more:, force: false)
      return :nothing_to_report unless worth_sending?

      unless force
        return :nudges_off unless state.nudges?
        return :already_sent if state.last_digest == today
      end

      send_notification(runner, see_more:)
      state.last_digest = today unless force
      :sent
    end

    # The bar badge's Nerd Font task list. The shell draws a glyph in the
    # theme's text colour, so it suits light and dark cards alike.
    GLYPH = "\u{f4a0}"

    private

    def plural(count, word) = count == 1 ? word : "#{word}s"

    # omarchy notification send, not notify-send: the shell runs the action
    # itself, so nothing has to wait for the click. Clicking the card runs the
    # first action, so See more covers both.
    def send_notification(runner, see_more:)
      result = runner.run("omarchy-notification-send", "--app-name", "openspec-pulse", "-u", "normal",
                          "-g", GLYPH, message, "--action", "See more", *see_more)
      return if result.success?

      reason = if result.missing? then "omarchy-notification-send was not found on PATH"
               else "omarchy notification send failed (exit #{result.exitstatus})"
               end
      raise NotifyError, "#{reason}: #{result.stderr.strip}"
    end
  end
end
