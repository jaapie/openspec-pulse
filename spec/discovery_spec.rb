# frozen_string_literal: true

require "openspec_pulse/discovery"

RSpec.describe OpenspecPulse::Discovery do
  around do |example|
    Dir.mktmpdir { |dir| @root = File.realpath(dir); example.run }
  end

  def repo_at(relative)
    FileUtils.mkdir_p(File.join(@root, relative, "openspec", "changes"))
    File.join(@root, relative)
  end

  def discover(scan: [@root], repos: [])
    described_class.new(scan:, repos:, home: "/home/nobody").repos
  end

  def found_paths(**kw) = discover(**kw).map(&:path)

  describe "scan roots" do
    it "finds a repo under a scan root" do
      api = repo_at("dev/acme-api")
      expect(found_paths).to eq([api])
    end

    it "finds nested OpenSpec roots in their own right" do
      work = repo_at("work")
      mail = repo_at("work/mail/config")
      expect(found_paths).to contain_exactly(work, mail)
    end

    it "skips node_modules, .git and vendor" do
      repo_at("app/node_modules/pkg")
      repo_at("app/.git/odd")
      repo_at("app/vendor/gem")
      expect(found_paths).to eq([])
    end

    it "finds a repo 5 levels down but not 6" do
      five = repo_at("a/b/c/d/e")
      repo_at("a/b/c/d/e2/f")
      expect(found_paths).to eq([five])
    end

    it "does not descend into openspec/ itself" do
      repo = repo_at("tool")
      FileUtils.mkdir_p(File.join(repo, "openspec/changes/archive/x/openspec/changes"))
      expect(found_paths).to eq([repo])
    end
  end

  describe "explicit repos" do
    it "adds an explicit repo outside any scan root" do
      Dir.mktmpdir do |other|
        tool = File.join(File.realpath(other), "elsewhere/tool")
        FileUtils.mkdir_p(File.join(tool, "openspec/changes"))
        expect(found_paths(scan: [], repos: [tool])).to eq([tool])
      end
    end

    it "reports an explicit repo without openspec/changes/ with an error" do
      plain = File.join(@root, "plain")
      FileUtils.mkdir_p(plain)
      repo = discover(scan: [], repos: [plain]).first
      expect(repo.path).to eq(plain)
      expect(repo.error).to match(%r{openspec/changes})
    end

    it "reports an explicit repo that does not exist with an error" do
      missing = File.join(@root, "gone")
      repo = discover(scan: [], repos: [missing]).first
      expect(repo.error).to match(/does not exist/)
    end
  end

  describe "de-duplication" do
    it "lists a repo found by a scan root and in repos once" do
      api = repo_at("dev/acme-api")
      expect(found_paths(repos: [api])).to eq([api])
    end

    it "compares by real path, so a symlinked copy counts once" do
      api = repo_at("dev/acme-api")
      link = File.join(@root, "api-link")
      File.symlink(api, link)
      expect(found_paths(repos: [link])).to eq([api])
    end

    it "still finds a repo reached only through a symlink under a scan root" do
      Dir.mktmpdir do |other|
        elsewhere = File.join(File.realpath(other), "mounted")
        FileUtils.mkdir_p(File.join(elsewhere, "openspec/changes"))
        File.symlink(elsewhere, File.join(@root, "mounted-link"))
        expect(found_paths).to eq([File.join(@root, "mounted-link")])
      end
    end

    it "lists a repo found by two overlapping scan roots once" do
      api = repo_at("dev/acme-api")
      expect(found_paths(scan: [@root, File.join(@root, "dev")])).to eq([api])
    end
  end

  describe "display names" do
    it "names a scanned repo by its path relative to the scan root" do
      repo_at("work/mail/config")
      expect(discover.map(&:name)).to eq(["work/mail/config"])
    end

    it "names a scan root that is itself a repo by its folder name" do
      FileUtils.mkdir_p(File.join(@root, "openspec/changes"))
      expect(discover.map(&:name)).to eq([File.basename(@root)])
    end

    it "names an explicit repo by its folder name" do
      Dir.mktmpdir do |other|
        tool = File.join(File.realpath(other), "elsewhere/tool")
        FileUtils.mkdir_p(File.join(tool, "openspec/changes"))
        expect(discover(scan: [], repos: [tool]).map(&:name)).to eq(["tool"])
      end
    end
  end

  describe "missing scan root" do
    it "is reported as an error entry naming the root as written" do
      repos = described_class.new(scan: ["/home/nobody/nope"], repos: [], home: "/home/nobody").repos
      expect(repos.size).to eq(1)
      expect(repos.first.name).to eq("~/nope")
      expect(repos.first.error).to match(%r{~/nope})
    end
  end
end
