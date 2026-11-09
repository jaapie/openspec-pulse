# frozen_string_literal: true

require "open3"

module OpenspecPulse
  # The one place external commands (openspec, git, notify-send) are run.
  class CommandRunner
    Result = Data.define(:stdout, :stderr, :exitstatus, :missing) do
      def success? = !missing && exitstatus.zero?
      def missing? = missing
    end

    def run(*command, chdir: Dir.pwd, env: {})
      stdout, stderr, status = Open3.capture3(env, *command, chdir:)
      Result.new(stdout:, stderr:, exitstatus: status.exitstatus || 1, missing: false)
    rescue Errno::ENOENT
      Result.new(stdout: "", stderr: "#{command.first}: command not found", exitstatus: 127, missing: true)
    end
  end
end
