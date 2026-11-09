# frozen_string_literal: true

require "openspec_pulse/command_runner"

# Canned command results for specs. Unmatched commands fall through to a
# real runner, so specs can mix canned openspec output with real git.
class FakeRunner
  attr_reader :calls

  def initialize(fallback: OpenspecPulse::CommandRunner.new)
    @canned = []
    @fallback = fallback
    @calls = []
  end

  def on(*prefix, chdir: nil, stdout: "", stderr: "", exitstatus: 0, missing: false)
    result = OpenspecPulse::CommandRunner::Result.new(stdout:, stderr:, exitstatus:, missing:)
    @canned.unshift([prefix, chdir, result])
    self
  end

  def run(*command, chdir: Dir.pwd, env: {})
    @calls << { command:, chdir:, env: }
    match = @canned.find do |prefix, dir, _|
      command.first(prefix.size) == prefix && (dir.nil? || dir == chdir)
    end
    match ? match.last : @fallback.run(*command, chdir:, env:)
  end
end
