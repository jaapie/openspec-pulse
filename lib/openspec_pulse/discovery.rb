# frozen_string_literal: true

require "find"

module OpenspecPulse
  class Discovery
    Repo = Data.define(:path, :name, :error)

    MAX_DEPTH = 5
    PRUNED = %w[node_modules .git vendor openspec].freeze

    def initialize(scan:, repos:, home:)
      @scan = scan
      @explicit = repos
      @home = home
    end

    def repos
      candidates = @scan.flat_map { |root| scan_root(root) } + @explicit.map { |path| explicit_repo(path) }
      dedupe(candidates)
    end

    private

    def scan_root(root)
      unless File.directory?(root)
        shown = display(root)
        return [Repo.new(path: root, name: shown, error: "Scan root #{shown} does not exist")]
      end

      found = []
      Find.find(root) do |path|
        next unless File.directory?(path)

        relative = path == root ? "" : path.delete_prefix("#{root}/")
        depth = relative.empty? ? 0 : relative.count("/") + 1
        Find.prune if depth > MAX_DEPTH || (depth.positive? && PRUNED.include?(File.basename(path)))
        name = relative.empty? ? File.basename(path) : relative
        found << Repo.new(path:, name:, error: nil) if openspec_root?(path)
      end
      found
    end

    def explicit_repo(path)
      name = File.basename(path)
      error =
        if !File.directory?(path) then "Repo #{display(path)} does not exist"
        elsif !openspec_root?(path) then "Repo #{display(path)} has no openspec/changes/ folder"
        end
      Repo.new(path:, name:, error:)
    end

    # One entry per repo, compared by real path. When a repo turns up by more
    # than one path (a symlink under a scan root, say), its real path wins,
    # whichever the walk met first; the entry keeps its first position.
    def dedupe(candidates)
      chosen = {}
      candidates.each do |repo|
        key = identity(repo)
        current = chosen[key]
        chosen[key] = repo if current.nil? || (!real?(current) && real?(repo))
      end
      candidates.map { |repo| identity(repo) }.uniq.map { |key| chosen[key] }
    end

    def real?(repo) = identity(repo) == repo.path

    def identity(repo)
      File.realpath(repo.path)
    rescue SystemCallError
      repo.path
    end

    def display(path)
      return "~" if path == @home

      path.start_with?("#{@home}/") ? "~/#{path.delete_prefix("#{@home}/")}" : path
    end

    def openspec_root?(path) = File.directory?(File.join(path, "openspec", "changes"))
  end
end
