# frozen_string_literal: true

require "open3"

# Builds throwaway git repos with backdated commits for staleness specs.
module GitRepoHelper
  IDENTITY = {
    "GIT_AUTHOR_NAME" => "Spec", "GIT_AUTHOR_EMAIL" => "spec@example.invalid",
    "GIT_COMMITTER_NAME" => "Spec", "GIT_COMMITTER_EMAIL" => "spec@example.invalid",
    "GIT_CONFIG_GLOBAL" => "/dev/null", "GIT_CONFIG_NOSYSTEM" => "1"
  }.freeze

  def git(dir, *args, env: {})
    out, err, status = Open3.capture3(IDENTITY.merge(env), "git", *args, chdir: dir)
    raise "git #{args.join(' ')} failed: #{err}" unless status.success?

    out
  end

  def init_repo(dir)
    git(dir, "init", "-q", "-b", "main")
    dir
  end

  def write_change(repo, name, file = "tasks.md", text = "- [ ] 1.1 something\n")
    path = File.join(repo, "openspec", "changes", name, file)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
    path
  end

  def commit_all(repo, at:, message: "change")
    stamp = at.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
    git(repo, "add", "-A")
    git(repo, "commit", "-q", "-m", message, env: { "GIT_AUTHOR_DATE" => stamp, "GIT_COMMITTER_DATE" => stamp })
  end
end

RSpec.configure { |config| config.include GitRepoHelper }
