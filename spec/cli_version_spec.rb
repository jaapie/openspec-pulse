# frozen_string_literal: true

require "open3"

RSpec.describe "bin/openspec-pulse version" do
  it "prints the version when run from outside the repo" do
    bin = File.expand_path("../bin/openspec-pulse", __dir__)
    out, _err, status = Open3.capture3(bin, "version", chdir: Dir.tmpdir)
    expect(status).to be_success
    expect(out.strip).to eq(OpenspecPulse::VERSION)
  end
end
