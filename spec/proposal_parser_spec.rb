# frozen_string_literal: true

require "openspec_pulse/proposal_parser"

RSpec.describe OpenspecPulse::ProposalParser do
  def purpose(text) = described_class.purpose(text)

  describe "the Why section" do
    it "takes only the Why section, up to the next ## heading" do
      text = <<~MD
        # Proposal

        ## Why

        The nightly export misses refunds.

        ## What Changes

        - Export refunds too.
      MD
      expect(purpose(text)).to eq("The nightly export misses refunds.")
    end

    it "runs to the end of the file when no heading follows" do
      expect(purpose("## Why\n\nThe nightly export misses refunds.\n")).to eq("The nightly export misses refunds.")
    end

    it "joins the lines of a paragraph and keeps paragraph breaks" do
      text = <<~MD
        ## Why

        The acme-api limiter is off,
        so one noisy client can starve the rest.

        Turning it on needs a token bucket.
      MD
      expect(purpose(text)).to eq(
        "The acme-api limiter is off, so one noisy client can starve the rest.\n\n" \
        "Turning it on needs a token bucket."
      )
    end

    it "keeps the lines of a list paragraph" do
      text = <<~MD
        ## Why

        Two things go wrong:

        - exports miss refunds
        - totals drift
      MD
      expect(purpose(text)).to eq("Two things go wrong:\n\n- exports miss refunds\n- totals drift")
    end

    it "removes backticks and bold markers" do
      expect(purpose("## Why\n\nThe `acme-api` limiter is **off**.\n")).to eq("The acme-api limiter is off.")
    end

    it "gives nil when there is no Why section" do
      expect(purpose("# Proposal\n\n## What Changes\n\n- Something.\n")).to be_nil
    end

    it "gives nil when the Why section is empty" do
      expect(purpose("## Why\n\n## What Changes\n")).to be_nil
    end
  end

  describe "tracking sentences" do
    def why(*paragraphs) = "## Why\n\n#{paragraphs.join("\n\n")}\n"

    it "drops a paragraph that is only a Jira line" do
      text = why("Jira: ABC-12 (under epic ABC-1).", "Refunds vanish from the export.")
      expect(purpose(text)).to eq("Refunds vanish from the export.")
    end

    it "drops a Work area sentence and keeps the rest of its paragraph" do
      text = why("Work area: billing/. The nightly export misses refunds.")
      expect(purpose(text)).to eq("The nightly export misses refunds.")
    end

    it "drops several tracking sentences at the start of a paragraph" do
      text = why("Work area: `billing/` (exports). Jira: ABC-7 (no epic). Refunds vanish from the export.")
      expect(purpose(text)).to eq("Refunds vanish from the export.")
    end

    it "keeps tracking words later in a paragraph" do
      text = why("Refunds vanish. Jira: ABC-7 tracks the fix.")
      expect(purpose(text)).to eq("Refunds vanish. Jira: ABC-7 tracks the fix.")
    end

    it "drops tracking sentences at the start of later paragraphs too" do
      text = why("Refunds vanish.", "No Jira ticket yet. Totals drift as well.")
      expect(purpose(text)).to eq("Refunds vanish.\n\nTotals drift as well.")
    end

    it "gives nil when only tracking sentences are left" do
      expect(purpose(why("No Jira."))).to be_nil
    end
  end

  describe ".purpose_from_file" do
    around do |example|
      Dir.mktmpdir { |dir| @dir = dir; example.run }
    end

    def write(bytes)
      File.join(@dir, "proposal.md").tap { File.binwrite(it, bytes) }
    end

    it "reads the purpose from a file" do
      path = write("## Why\n\nRefunds vanish from the export.\n")
      expect(described_class.purpose_from_file(path)).to eq("Refunds vanish from the export.")
    end

    it "gives nil for a missing file" do
      expect(described_class.purpose_from_file(File.join(@dir, "proposal.md"))).to be_nil
    end

    it "gives nil for a file with no Why section" do
      expect(described_class.purpose_from_file(write("# Proposal\n"))).to be_nil
    end

    it "copes with invalid UTF-8 bytes" do
      path = write("## Why\n\nRefunds \xFF vanish.\n".b)
      expect(described_class.purpose_from_file(path)).to eq("Refunds � vanish.")
    end

    it "gives nil for a file it cannot read" do
      skip "root can read any file" if Process.uid.zero?

      path = write("## Why\n\nRefunds vanish.\n")
      File.chmod(0o000, path)
      expect(described_class.purpose_from_file(path)).to be_nil
    ensure
      File.chmod(0o644, path) if path
    end
  end
end
