# frozen_string_literal: true

module OpenspecPulse
  # Reads a change's purpose from the Why section of its proposal.md
  # (spec: change-status).
  module ProposalParser
    WHY = /^## Why[ \t]*$/
    NEXT_HEADING = /^## /
    LIST_ITEM = /\A\s*- /
    SENTENCE_END = /(?<=[.!?])\s+/
    TRACKING = /\A(?:Work area:|Jira:|No Jira)/

    module_function

    # A purpose is a description, not a status: a proposal that is missing or
    # cannot be read gives nil, never an error that would hide the change's own
    # status.
    def purpose_from_file(path)
      return nil unless File.exist?(path)

      purpose(File.read(path, encoding: "UTF-8").scrub)
    rescue SystemCallError, IOError
      nil
    end

    def purpose(text)
      section = why_section(text)
      return nil unless section

      paragraphs = section.split(/\n[ \t]*\n/).map { paragraph(it) }.reject(&:empty?)
      paragraphs.empty? ? nil : paragraphs.join("\n\n")
    end

    def why_section(text)
      start = text.match(WHY)
      return nil unless start

      rest = text[start.end(0)..]
      stop = rest.match(NEXT_HEADING)
      stop ? rest[...stop.begin(0)] : rest
    end

    def paragraph(text)
      lines = text.lines.map(&:strip).reject(&:empty?)
      list = lines.all? { LIST_ITEM.match?(it) }
      plain = list ? lines.join("\n") : without_tracking(lines.join(" "))
      plain.delete("`").gsub("**", "")
    end

    # Drops the "Work area:", "Jira:" and "No Jira" sentences that open a
    # paragraph; the same words later on are part of the reason, so they stay.
    def without_tracking(text)
      text.split(SENTENCE_END).drop_while { TRACKING.match?(it) }.join(" ")
    end
  end
end
