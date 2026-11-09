# frozen_string_literal: true

require "date"
require "fileutils"
require_relative "../openspec_pulse"

module OpenspecPulse
  class StateError < Error; end

  # Local state kept outside any repo: the nudge setting and the date of
  # the last digest, one small file each under $XDG_STATE_HOME/openspec-pulse.
  class State
    attr_reader :dir

    def self.dir(env = ENV)
      base = env["XDG_STATE_HOME"]
      base = File.join(env.fetch("HOME"), ".local", "state") if base.nil? || base.empty?
      File.join(base, "openspec-pulse")
    end

    def initialize(dir: self.class.dir)
      @dir = dir
    end

    def nudges? = read("nudges") != "off"

    def nudges=(on)
      write("nudges", on ? "on" : "off")
    end

    def last_digest
      text = read("last_digest")
      text && Date.iso8601(text)
    rescue Date::Error
      nil
    end

    def last_digest=(date)
      write("last_digest", date.iso8601)
    end

    private

    def read(name)
      path = File.join(dir, name)
      File.exist?(path) ? File.read(path).strip : nil
    end

    def write(name, value)
      path = File.join(dir, name)
      FileUtils.mkdir_p(dir)
      File.write(path, "#{value}\n")
    rescue SystemCallError => e
      raise StateError, "Could not save #{path}: #{e.message.split(" @ ").first}"
    end
  end
end
