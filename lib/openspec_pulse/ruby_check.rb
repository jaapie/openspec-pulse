# frozen_string_literal: true

# Loaded before anything else, so keep it to syntax any Ruby can read: an
# older Ruby (Arch's 3.4 in /usr/bin, when PATH is wrong) should get this
# message rather than a syntax error from a newer file.
module OpenspecPulse
  module RubyCheck
    NEEDED = "4.0"

    def self.problem(version = RUBY_VERSION)
      return nil if Gem::Version.new(version) >= Gem::Version.new(NEEDED)

      "openspec-pulse needs Ruby #{NEEDED} or later, but this is Ruby #{version}."
    end
  end
end
