# frozen_string_literal: true

require "json"
require "time"
require_relative "discovery"
require_relative "tasks_parser"
require_relative "proposal_parser"
require_relative "git_clock"
require_relative "change_assessor"

module OpenspecPulse
  # Reads every repo and assesses every active change (spec: change-status).
  class Report
    RepoStatus = Data.define(:path, :name, :error)

    Change = Data.define(
      :repo, :repo_path, :name, :path, :last_touched, :touched_source, :days_quiet,
      :kind, :openspec_status, :stale, :done, :total, :ready,
      :openspec_done, :openspec_total, :count_mismatch, :tasks_file, :error, :groups, :purpose, :jira
    )

    REQUIRED_FIELDS = { "name" => String, "completedTasks" => Integer, "totalTasks" => Integer }.freeze

    class RepoError < Error; end

    attr_reader :repos, :changes, :generated_at, :stale_after_days, :nudges

    def self.build(repos:, runner:, stale_after_days:, now:, nudges:, jira_url: nil)
      new(runner:, stale_after_days:, now:, nudges:, jira_url:).tap { it.read(repos) }
    end

    # Stale (quietest first), complete, other in progress (quietest first),
    # not started, then changes with errors. Ties by repo, then name.
    def self.sort(changes)
      changes.sort_by do |c|
        rank = if c.error then 4
               elsif c.stale then 0
               elsif c.kind == "complete" then 1
               elsif c.kind == "in_progress" then 2
               else 3
               end
        quiet = [0, 2].include?(rank) ? -c.days_quiet : 0
        [rank, quiet, c.repo, c.name]
      end
    end

    def initialize(runner:, stale_after_days:, now:, nudges:, jira_url: nil)
      @runner = runner
      @jira_url = jira_url
      @stale_after_days = stale_after_days
      @generated_at = now
      @nudges = nudges
      @clock = GitClock.new(runner:, now: -> { now })
      @assessor = ChangeAssessor.new(stale_after_days:, now:)
      @repos = []
      @changes = []
    end

    def read(repos)
      repos.each do |repo|
        if repo.error
          @repos << RepoStatus.new(path: repo.path, name: repo.name, error: repo.error)
          next
        end

        entries = openspec_list(repo)
        @repos << RepoStatus.new(path: repo.path, name: repo.name, error: nil)
        @changes.concat(entries.map { |entry| change(repo, entry) })
      rescue RepoError => e
        @repos << RepoStatus.new(path: repo.path, name: repo.name, error: e.message)
      end
      @changes = self.class.sort(@changes)
    end

    def summary
      ok = changes.reject(&:error)
      {
        changes: changes.size,
        stale: ok.count(&:stale),
        in_progress: ok.count { it.kind == "in_progress" },
        not_started: ok.count { it.kind == "not_started" },
        complete: ok.count { it.kind == "complete" },
        errors: repos.count(&:error) + changes.count(&:error)
      }
    end

    def to_h
      {
        generated_at: generated_at.utc.iso8601,
        stale_after_days:,
        nudges:,
        summary:,
        repos: repos.map(&:to_h),
        changes: changes.map { change_hash(it) }
      }
    end

    def to_json(*) = JSON.generate(to_h)

    def to_table
      rows = changes.map do |c|
        [c.repo, c.name, c.total ? "#{c.done}/#{c.total}" : "-", "#{c.days_quiet}d", marker(c)]
      end
      header = %w[REPO CHANGE DONE QUIET NOTE]
      widths = header.each_index.map { |i| ([header] + rows).map { it[i].to_s.length }.max }
      line = ->(cells) { cells.each_with_index.map { |cell, i| cell.to_s.ljust(widths[i]) }.join("  ").rstrip }

      out = [line.(header), *rows.map(&line)]
      out << "(no active changes)" if rows.empty?
      errors = repos.select(&:error)
      out.concat(["", "Repo errors:", *errors.map { "  #{it.name}: #{it.error}" }]) if errors.any?
      out.join("\n") + "\n"
    end

    private

    def openspec_list(repo)
      result = @runner.run("openspec", "list", "--json", chdir: repo.path)
      raise RepoError, "openspec not found on PATH (#{result.stderr.strip})" if result.missing?
      raise RepoError, "openspec list failed (exit #{result.exitstatus}): #{result.stderr.strip}" unless result.success?

      data = parse_json(result.stdout)
      entries = data.is_a?(Hash) && data["changes"]
      raise RepoError, "openspec list --json has no changes list" unless entries.is_a?(Array)

      entries.each { |entry| check_entry(entry) }
    end

    def parse_json(text)
      JSON.parse(text)
    rescue JSON::ParserError => e
      raise RepoError, "openspec list printed invalid JSON: #{e.message.lines.first&.strip}"
    end

    def check_entry(entry)
      REQUIRED_FIELDS.each do |field, type|
        next if entry.is_a?(Hash) && entry[field].is_a?(type)

        raise RepoError, "openspec list --json entry is missing #{field}: #{entry.inspect[0, 120]}"
      end
    end

    def change(repo, entry)
      name = entry["name"]
      path = File.join(repo.path, "openspec", "changes", name)
      touched, source = @clock.last_touched(repo.path, name)
      proposal = ProposalParser.read_file(File.join(path, "proposal.md"))
      base = { repo: repo.name, repo_path: repo.path, name:, path:,
               last_touched: touched, touched_source: source,
               openspec_status: entry["status"],
               openspec_done: entry["completedTasks"], openspec_total: entry["totalTasks"],
               purpose: proposal.purpose, jira: jira(proposal.jira_key) }

      begin
        tasks = TasksParser.parse_file(File.join(path, "tasks.md"))
      rescue SystemCallError, IOError, ArgumentError, EncodingError => e
        return errored_change(base, "Could not read tasks.md: #{e.message}")
      end

      a = @assessor.assess(tasks:, openspec: entry, last_touched: touched)
      Change.new(**base, days_quiet: a.days_quiet, kind: a.kind, stale: a.stale,
                         done: a.done, total: a.total, ready: a.ready,
                         count_mismatch: a.count_mismatch, tasks_file: tasks.tasks_file,
                         error: nil, groups: tasks.groups)
    end

    def jira(key)
      key && { key:, url: @jira_url && "#{@jira_url}/browse/#{key}" }
    end

    def marker(change)
      notes = []
      notes << "error: #{change.error}" if change.error
      if change.stale then notes << "stale"
      elsif change.kind == "in_progress" then notes << "in progress"
      elsif change.kind == "not_started" then notes << "not started"
      elsif change.kind == "complete" then notes << "ready to archive"
      end
      notes << "openspec says #{change.openspec_done}/#{change.openspec_total}" if change.count_mismatch
      notes.join(", ")
    end

    def change_hash(change)
      change.to_h.merge(
        last_touched: change.last_touched&.utc&.iso8601,
        groups: change.groups.map do |g|
          { title: g.title, done: g.done, total: g.total, tasks: g.tasks.map(&:to_h) }
        end
      )
    end

    def errored_change(base, message)
      Change.new(**base, days_quiet: @assessor.days_quiet(base[:last_touched]), kind: nil, stale: false,
                         done: base[:openspec_done], total: base[:openspec_total], ready: nil,
                         count_mismatch: false, tasks_file: true, error: message, groups: [])
    end
  end
end
