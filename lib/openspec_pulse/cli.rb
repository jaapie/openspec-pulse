# frozen_string_literal: true

require "shellwords"
require "thor"
require_relative "../openspec_pulse"
require_relative "config"
require_relative "discovery"
require_relative "command_runner"
require_relative "report"
require_relative "state"
require_relative "digest"

module OpenspecPulse
  class CLI < Thor
    def self.exit_on_failure? = true

    desc "version", "Print the version"
    def version
      puts VERSION
    end

    desc "status", "Show every active OpenSpec change, stalest first"
    option :json, type: :boolean, default: false, desc: "Print JSON for the Omarchy plugin"
    def status
      report = build_report
      puts(options[:json] ? report.to_json : report.to_table)
    end

    desc "notify", "Send the daily digest of stale changes, at most once a day"
    option :force, type: :boolean, default: false, desc: "Send now, ignoring the daily limit and the nudge setting"
    def notify
      outcome = Digest.new(build_report).deliver(
        state: State.new, runner: CommandRunner.new, today: Date.today, force: options[:force],
        icon: File.join(ROOT, "assets", "icon.png"), see_more: see_more_command
      )
      puts NOTIFY_MESSAGES.fetch(outcome)
    rescue Error => e
      raise Thor::Error, e.message
    end

    NOTIFY_MESSAGES = {
      sent: "Digest sent.",
      nothing_to_report: "Nothing stale or ready to archive, no digest sent.",
      nudges_off: "Nudges are off, no digest sent.",
      already_sent: "Digest already sent today."
    }.freeze

    desc "nudges [on|off]", "Show, or turn on or off, the daily digest notification"
    def nudges(setting = nil)
      state = State.new
      case setting
      when nil then puts(state.nudges? ? "on" : "off")
      when "on", "off" then state.nudges = (setting == "on")
      else raise Thor::Error, "nudges takes on or off, not #{setting.inspect}"
      end
    rescue Error => e
      raise Thor::Error, e.message
    end

    private

    ROOT = File.expand_path("../..", __dir__)

    # See more (and a click on the card) opens the plugin's panel on the focused
    # monitor: `shell summon` picks that monitor's copy of the widget, where the
    # widget's own IPC target reaches only one copy. summon answers "ok" or
    # "unknown" (exit 0 either way), so anything but "ok" falls back to a
    # floating terminal with the status table. Decided at
    # click time, so enabling the plugin later just works. The shell runs it
    # without mise's PATH, so the fallback sets the shims first.
    def see_more_command
      shims = File.join(Dir.home, ".local", "share", "mise", "shims")
      path = "PATH=#{shims}:/usr/share/omarchy/bin:/usr/bin:/bin"
      fallback = ["omarchy-launch-floating-terminal-with-presentation", "env", path,
                  File.join(ROOT, "bin", "openspec-pulse"), "status"]
      script = %([ "$(omarchy-shell shell summon io.github.jaapie.openspec-pulse '{}' 2>/dev/null)" = ok ] || exec #{fallback.shelljoin})
      ["sh", "-c", script]
    end

    def build_report
      config = Config.load(Config.path)
      repos = Discovery.new(scan: config.scan, repos: config.repos, home: Dir.home).repos
      Report.build(repos:, runner: CommandRunner.new, stale_after_days: config.stale_after_days,
                   now: Time.now, nudges: State.new.nudges?)
    rescue Error => e
      raise Thor::Error, e.message
    end
  end
end
