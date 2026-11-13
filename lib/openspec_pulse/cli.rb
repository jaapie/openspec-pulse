# frozen_string_literal: true

require "optparse"
require "shellwords"
require_relative "../openspec_pulse"
require_relative "config"
require_relative "discovery"
require_relative "command_runner"
require_relative "report"
require_relative "state"
require_relative "digest"

module OpenspecPulse
  # Input the CLI doesn't understand: an unknown command or option, or an
  # argument a command doesn't take.
  class UsageError < Error; end

  # Reads the command line with the standard library only, so the CLI runs
  # without any gems. COMMANDS drives both dispatch and help.
  class CLI
    Option = Data.define(:flag, :description)
    Command = Data.define(:name, :usage, :summary, :options, :max_args)

    COMMANDS = [
      Command.new(name: "status", usage: "status [--json]", summary: "Show every active OpenSpec change, stalest first",
                  options: [Option.new(flag: "--json", description: "Print JSON for the Omarchy plugin")], max_args: 0),
      Command.new(name: "notify", usage: "notify [--force]", summary: "Send the daily digest of stale changes, at most once a day",
                  options: [Option.new(flag: "--force", description: "Send now, ignoring the daily limit and the nudge setting")],
                  max_args: 0),
      Command.new(name: "nudges", usage: "nudges [on|off]", summary: "Show, or turn on or off, the daily digest notification",
                  options: [], max_args: 1),
      Command.new(name: "version", usage: "version", summary: "Print the version", options: [], max_args: 0),
      Command.new(name: "help", usage: "help [command]", summary: "Describe the commands, or one command", options: [], max_args: 1)
    ].to_h { [it.name, it] }.freeze

    NOTIFY_MESSAGES = {
      sent: "Digest sent.",
      nothing_to_report: "Nothing stale or ready to archive, no digest sent.",
      nudges_off: "Nudges are off, no digest sent.",
      already_sent: "Digest already sent today."
    }.freeze

    ROOT = File.expand_path("../..", __dir__)

    # Runs the command line and returns the exit status.
    def self.start(argv, out: $stdout, err: $stderr) = new(out:, err:).run(argv)

    def initialize(out:, err:)
      @out = out
      @err = err
    end

    def run(argv)
      name, *rest = argv
      command = command(name || "help")
      options, args = parse(command, rest)
      return help(command.name) if options[:help]

      check_arg_count(command, args)
      send(:"run_#{command.name}", options, args)
      0
    rescue Error => e
      @err.puts(e.message)
      1
    end

    private

    def command(name)
      COMMANDS.fetch(name) { raise UsageError, %(Unknown command "#{name}". Run openspec-pulse help to see the commands.) }
    end

    def check_arg_count(command, args)
      return if args.size <= command.max_args

      allowed = command.max_args.zero? ? "no arguments" : "one argument at most"
      raise UsageError, "#{command.name} takes #{allowed}. Run openspec-pulse help #{command.name} for its usage."
    end

    def parse(command, args)
      options = {}
      parser = OptionParser.new
      parser.require_exact = true
      command.options.each { |o| parser.on(o.flag) { options[o.flag.delete_prefix("--").to_sym] = true } }
      parser.on("-h", "--help") { options[:help] = true }
      [options, parser.parse(args)]
    rescue OptionParser::ParseError => e
      raise UsageError, %(Unknown option "#{e.args.first}" for #{command.name}. Run openspec-pulse help #{command.name} for its options.)
    end

    def run_status(options, _args)
      report = build_report
      @out.puts(options[:json] ? report.to_json : report.to_table)
    end

    def run_notify(options, _args)
      outcome = Digest.new(build_report).deliver(
        state: State.new, runner: CommandRunner.new, today: Date.today, force: options.fetch(:force, false),
        see_more: see_more_command
      )
      @out.puts NOTIFY_MESSAGES.fetch(outcome)
    end

    def run_nudges(_options, args)
      state = State.new
      case (setting = args.first)
      when nil then @out.puts(state.nudges? ? "on" : "off")
      when "on", "off" then state.nudges = (setting == "on")
      else raise UsageError, "nudges takes on or off, not #{setting.inspect}"
      end
    end

    def run_version(_options, _args) = @out.puts(VERSION)

    def run_help(_options, args) = help(args.first)

    def help(name)
      @out.puts(name && name != "help" ? command_help(command(name)) : overview)
      0
    end

    def overview
      width = COMMANDS.values.map { it.usage.size }.max
      lines = COMMANDS.values.map { "  #{it.usage.ljust(width)}  #{it.summary}" }
      ["Usage: openspec-pulse <command> [options]", "", "Commands:", *lines].join("\n")
    end

    def command_help(command)
      lines = ["Usage: openspec-pulse #{command.usage}", "", command.summary]
      unless command.options.empty?
        width = command.options.map { it.flag.size }.max
        lines += ["", "Options:", *command.options.map { "  #{it.flag.ljust(width)}  #{it.description}" }]
      end
      lines.join("\n")
    end

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
                   now: Time.now, nudges: State.new.nudges?, jira_url: config.jira_url)
    end
  end
end
