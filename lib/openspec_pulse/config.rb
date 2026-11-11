# frozen_string_literal: true

require "uri"
require "yaml"
require_relative "../openspec_pulse"

module OpenspecPulse
  class ConfigError < Error; end

  class Config
    DEFAULT_STALE_AFTER_DAYS = 14

    attr_reader :path, :scan, :repos, :stale_after_days, :jira_url

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
      unless @stale_after_days.is_a?(Integer) && @stale_after_days.positive?
        raise ConfigError, "In #{path}, stale_after_days must be a positive whole number"
      end

      @jira_url = site_url(data.fetch("jira_url", nil))
    end

    private

    # The Jira site's address, so a task key can link to <site>/browse/<KEY>.
    def site_url(value)
      return nil if value.nil?
      return value.delete_suffix("/") if http_site?(value)

      raise ConfigError, "In #{@path}, jira_url must be an http or https address, such as https://example.atlassian.net"
    end

    def http_site?(value)
      uri = URI.parse(value) if value.is_a?(String)
      uri.is_a?(URI::HTTP) && !uri.host.to_s.empty?
    rescue URI::InvalidURIError
      false
    end

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
