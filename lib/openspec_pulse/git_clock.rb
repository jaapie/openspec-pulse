# frozen_string_literal: true

require "find"

module OpenspecPulse
  # Works out when a change was last touched (spec: change-status).
  # Read-only: nothing here writes to the repo or its index.
  class GitClock
    GIT_ENV = { "GIT_OPTIONAL_LOCKS" => "0" }.freeze

    def initialize(runner:, now: -> { Time.now })
      @runner = runner
      @now = now
    end

    # Returns [time, source], where source is "git" or "mtime".
    def last_touched(repo, name)
      folder = File.join("openspec", "changes", name)
      committed = git_repo?(repo) && last_commit_time(repo, folder)
      return [newest_mtime(File.join(repo, folder)), "mtime"] unless committed
      return [@now.call, "git"] if dirty?(repo, folder)

      [committed, "git"]
    end

    private

    # This runs unattended in every repo found, and a repo's own .git/config can
    # name programs for git to run: core.fsmonitor (git status) and gpg.program
    # via log.showSignature (git log). Both are switched off, and a planted bare
    # repository is never picked up implicitly.
    HARDENING = ["-c", "core.fsmonitor=false", "-c", "log.showSignature=false",
                 "-c", "safe.bareRepository=explicit"].freeze

    def git(repo, *args) = @runner.run("git", *HARDENING, *args, chdir: repo, env: GIT_ENV)

    def git_repo?(repo) = git(repo, "rev-parse", "--is-inside-work-tree").success?

    def last_commit_time(repo, folder)
      result = git(repo, "log", "-1", "--format=%ct", "--", "#{folder}/")
      stamp = result.stdout.strip
      result.success? && !stamp.empty? ? Time.at(Integer(stamp)).utc : nil
    end

    # Uncommitted work in the folder, found without git reading any file's
    # contents: `git status` compares contents through whatever clean filter the
    # repo's config defines, and a repo can name any program there. Staged
    # changes come from the index, new files from the file list, and edits from
    # comparing the size and mtime git recorded with the file on disk.
    def dirty?(repo, folder)
      staged?(repo, folder) || untracked?(repo, folder) || edited?(repo, folder)
    end

    def staged?(repo, folder)
      git(repo, "diff-index", "--cached", "--quiet", "HEAD", "--", "#{folder}/").exitstatus == 1
    end

    def untracked?(repo, folder)
      !git(repo, "ls-files", "--others", "--exclude-standard", "--", "#{folder}/").stdout.strip.empty?
    end

    # A file counts as edited when it's gone, its size or mtime (to the
    # nanosecond) differs from what git recorded, or it was modified no earlier
    # than the index was written. Git reads contents in that last, "racy" case;
    # this can't, so it errs towards "edited", which only means "touched now".
    def edited?(repo, folder)
      index_time = index_mtime(repo)
      recorded_stats(repo, folder).any? do |path, mtime, size|
        full = File.join(repo, path)
        next true unless File.exist?(full)

        stat = File.lstat(full)
        disk = [stat.mtime.to_i, stat.mtime.nsec]
        disk != mtime || stat.size != size || (index_time && (stat.mtime <=> index_time) >= 0)
      end
    end

    def index_mtime(repo)
      dir = git(repo, "rev-parse", "--git-dir").stdout.strip
      index = File.expand_path("index", File.expand_path(dir, repo))
      File.exist?(index) ? File.mtime(index) : nil
    end

    # [path, [mtime seconds, nanoseconds], size] for each file git tracks in the folder, from
    # `git ls-files --debug`: a path line, then indented stat lines.
    def recorded_stats(repo, folder)
      entries = []
      git(repo, "ls-files", "--debug", "--", "#{folder}/").stdout.each_line(chomp: true) do |line|
        if !line.start_with?(" ")
          entries << [line, nil, nil]
        elsif (m = line.match(/\A\s+mtime: (\d+):(\d+)/))
          entries.last[1] = [m[1].to_i, m[2].to_i]
        elsif (m = line.match(/\A\s+size: (\d+)/))
          entries.last[2] = m[1].to_i
        end
      end
      entries
    end

    def newest_mtime(folder)
      Find.find(folder).select { File.file?(it) }.map { File.mtime(it) }.max&.utc ||
        File.mtime(folder).utc
    end
  end
end
