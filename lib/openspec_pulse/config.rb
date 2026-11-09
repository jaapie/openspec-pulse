# frozen_string_literal: true

require "yaml"
require_relative "../openspec_pulse"

module OpenspecPulse
  class ConfigError < Error; end

  class Config
    DEFAULT_STALE_AFTER_DAYS = 14

    attr_reader :path, :scan, :repos, :stale_after_days

    def self.path(env = ENV)
      base = env["XDG_CONFIG_HOME"]
      base = File.join(env.fetch("HOME"), ".config") if base.nil? || base.empty?
      File.join(base, "openspec-pulse", "config.yml")
    end

    def self.load(path, home: Dir.home)
      raise ConfigError, "No config file at #{path}" unless File.file?(path)

      data = begin
        YAML.safe_load_file(path) || {}
      rescue Psych::Exception => e
        raise ConfigError, "Config file #{path} is not valid YAML: #{e.message}"
      end
      raise ConfigError, "Config file #{path} must be a mapping of settings" unless data.is_a?(Hash)

      new(path:, data:, home:)
    end

    def initialize(path:, data:, home:)
      @path = path
      @home = home
      @scan = path_list(data, "scan")
      @repos = path_list(data, "repos")
      @stale_after_days = data.fetch("stale_after_days", DEFAULT_STALE_AFTER_DAYS)
      return if @stale_after_days.is_a?(Integer) && @stale_after_days.positive?

      raise ConfigError, "In #{path}, stale_after_days must be a positive whole number"
    end

    private

    def path_list(data, key)
      value = data.fetch(key, nil) || []
      unless value.is_a?(Array) && value.all?(String)
        raise ConfigError, "In #{@path}, #{key} must be a list of paths"
      end

      value.map { |p| expand(p) }
    end

    def expand(p)
      return @home if p == "~"

      p.start_with?("~/") ? File.join(@home, p.delete_prefix("~/")) : p
    end
  end
end
