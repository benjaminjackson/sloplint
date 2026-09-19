# frozen_string_literal: true

require_relative "rules"
require_relative "engine"

module Sloplint
  # Splits a document into paragraphs and sentences, keeping each one's offset
  # and length in the original text so a note can land on the file as written.
  #
  # The regex engine does not use this. It exists for the judge and for any
  # other tool that asks questions about a paragraph or a sentence rather than
  # matching a pattern across the whole text. See docs/JUDGE.md "Splitting".
  module Split
    Sentence = Data.define(:offset, :length, :text)
    Paragraph = Data.define(:offset, :length, :text, :sentences)

    # Furniture: a line that is not prose, whatever a regex would think.
    # Headings, list items, table rows, block quotes, horizontal rules,
    # reference-style link definitions and a lone image or link line.
    FURNITURE = /\A[ \t]*(?:\#{1,6}[ \t]|[-*+][ \t]|\d+[.)][ \t]|\||>|[-*_]{3,}[ \t]*\z|\[[^\]]+\]:[ \t]|!\[)/

    # Abbreviations whose trailing period does not end a sentence. Case
    # matters: "No." is an abbreviation, "no." is the end of a sentence.
    ABBREV = /\b(?:e\.g|i\.e|vs|etc|cf|Fig|No|Dr|Mr|Mrs|Ms|St|Inc|Ltd|Sec|Ch|Vol)\.\z/

    # A sentence ends at .!? (with an optional closing quote or bracket)
    # followed by whitespace and a capital, digit, or opening quote/bracket.
    BOUNDARY = /(?<=[.!?]|[.!?]["'”’)\]])\s+(?=["'“‘(\[A-Z0-9])/

    module_function

    # text: the source. markdown: blank code, HTML comments and URLs before
    # splitting, and blank furniture lines so they neither count as prose nor
    # take the prose around them with them. Splitting happens on the blanked
    # copy; the texts returned are cut from the original at the same offsets,
    # so an excerpt is always a string that is in the file. Blanking is
    # character for character, so the offsets agree.
    def paragraphs(text, markdown: false)
      scan = markdown ? blank_furniture(Engine.blank_markdown(text)) : text
      out = []
      at = 0
      # Split keeping the separators, and walk the offsets arithmetically:
      # String#index with a start position rescans from 0 on non-ASCII text.
      scan.split(/(#{PARA_BREAK})/).each do |block|
        start = at
        at += block.length
        next if block.match?(/\A#{PARA_BREAK}\z/)

        lead = block[/\A\s*/].length
        body = block.strip
        next if body.empty?

        offset = start + lead
        sents = sentences(body, base: offset, source: text)
        # A one-sentence block ending in a colon is the lead-in to whatever
        # follows (a code block, a list), not a paragraph.
        next if markdown && sents.size == 1 && body.end_with?(":")

        out << Paragraph.new(offset:, length: body.length, text: squash(text[offset, body.length]), sentences: sents) unless sents.empty?
      end
      out
    end

    # Sentences of one paragraph. base is the paragraph's offset in source;
    # each sentence's text is cut from source (or from body when there is no
    # source) and its whitespace collapsed, so hard-wrapped lines read as one.
    def sentences(body, base: 0, source: nil)
      source ||= body
      parts = []
      buf_start = nil
      pos = 0
      body.split(/(#{BOUNDARY})/).each do |piece|
        at = pos
        pos = at + piece.length
        next if piece.match?(/\A\s+\z/)

        buf_start ||= at
        next if body[buf_start...pos].match?(ABBREV)

        parts << Sentence.new(offset: base + buf_start, length: pos - buf_start, text: squash(source[base + buf_start, pos - buf_start]))
        buf_start = nil
      end
      parts << Sentence.new(offset: base + buf_start, length: pos - buf_start, text: squash(source[base + buf_start, pos - buf_start])) if buf_start
      parts
    end

    def squash(s) = s.gsub(/\s+/, " ").strip

    # Blank furniture lines to same-length spaces, and the indented lines that
    # continue a blanked one: a wrapped bullet is one bullet, and its second
    # line is not a sentence of its own.
    def blank_furniture(scan)
      dropped = false
      scan.gsub(/^.*$/) do |l|
        dropped = l.match?(FURNITURE) || (dropped && l.match?(/\A(?:[ ]{2,}|\t)\S/))
        dropped ? " " * l.length : l
      end
    end
  end
end
