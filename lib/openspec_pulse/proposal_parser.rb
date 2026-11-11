# frozen_string_literal: true

module OpenspecPulse
  # Reads a change's purpose and Jira task from the Why section of its
  # proposal.md (spec: change-status).
  module ProposalParser
    Proposal = Data.define(:purpose, :jira_key)
    NONE = Proposal.new(purpose: nil, jira_key: nil)

    WHY = /^## Why[ \t]*$/
    NEXT_HEADING = /^## /
    LIST_ITEM = /\A\s*- /
    SENTENCE_END = /(?<=[.!?])\s+/
    TRACKING = /\A(?:Work area:|Jira:|No Jira)/
    JIRA = "Jira:"
    KEY = /\b[A-Z][A-Z0-9]+-\d+\b/

    module_function

    # A purpose is a description, not a status: a proposal that is missing or
    # cannot be read gives nothing, never an error that would hide the
    # change's own status.
    def read_file(path)
      return NONE unless File.exist?(path)

      read(File.read(path, encoding: "UTF-8").scrub)
    rescue SystemCallError, IOError
      NONE
    end

    def purpose_from_file(path) = read_file(path).purpose
    def purpose(text) = read(text).purpose

    def read(text)
      section = why_section(text)
      return NONE unless section

      paragraphs = section.split(/\n[ \t]*\n/).map { paragraph(it) }
      texts = paragraphs.map(&:first).reject(&:empty?)
      jira = paragraphs.filter_map(&:last).first
      Proposal.new(purpose: texts.empty? ? nil : texts.join("\n\n"), jira_key: jira_key(jira))
    end

    def why_section(text)
      start = text.match(WHY)
      return nil unless start

      rest = text[start.end(0)..]
      stop = rest.match(NEXT_HEADING)
      stop ? rest[...stop.begin(0)] : rest
    end

    # A paragraph's plain text, and its opening "Jira:" sentence if it has one.
    def paragraph(text)
      lines = text.lines.map(&:strip).reject(&:empty?)
      return [plain(lines.join("\n")), nil] if lines.all? { LIST_ITEM.match?(it) }

      tracking, rest = split_tracking(lines.join(" "))
      [plain(rest.join(" ")), tracking.find { it.start_with?(JIRA) }]
    end

    # The "Work area:", "Jira:" and "No Jira" sentences that open a paragraph
    # are tracking, not reason; the same words later on stay in the text.
    def split_tracking(text)
      sentences = text.split(SENTENCE_END)
      tracking = sentences.take_while { TRACKING.match?(it) }
      [tracking, sentences.drop(tracking.size)]
    end

    # The first key after "Jira:" is the task; an epic comes later, if at all.
    def jira_key(sentence)
      sentence&.delete_prefix(JIRA)&.gsub("**", "")&.[](KEY)
    end

    def plain(text) = text.delete("`").gsub("**", "")
  end
end
