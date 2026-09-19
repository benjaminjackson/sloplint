# frozen_string_literal: true

require_relative "rules"

module Sloplint
  # Splits a document into paragraphs and sentences, keeping each one's offset
  # into the original text so a note can land on the file as written.
  #
  # The regex engine does not use this. It exists for the judge and for any
  # other tool that asks questions about a paragraph or a sentence rather than
  # matching a pattern across the whole text. See docs/JUDGE.md "Splitting".
  module Split
    Sentence = Data.define(:offset, :text)
    Paragraph = Data.define(:offset, :text, :sentences)

    # Furniture: a block that is not prose, whatever a regex would think.
    # Headings, list items, table rows, block quotes, horizontal rules,
    # reference-style link definitions and a lone image or link line.
    FURNITURE = /\A[ \t]*(?:\#{1,6}[ \t]|[-*+][ \t]|\d+[.)][ \t]|\||>|[-*_]{3,}[ \t]*\z|\[[^\]]+\]:[ \t]|!\[)/

    # Abbreviations whose trailing period does not end a sentence.
    ABBREV = /\b(?:e\.g|i\.e|vs|etc|cf|Fig|No|Dr|Mr|Mrs|Ms|St|Inc|Ltd|Sec|Ch|Vol)\.\z/i

    # A sentence ends at .!? (with an optional closing quote or bracket)
    # followed by whitespace and a capital, digit, or opening quote/bracket.
    BOUNDARY = /(?<=[.!?]|[.!?]["'”’)\]])\s+(?=["'“‘(\[A-Z0-9])/

    module_function

    # text: the source. markdown: blank code, HTML comments and URLs first,
    # and drop furniture blocks. Returns Paragraphs in document order.
    def paragraphs(text, markdown: false)
      scan = markdown ? Engine.blank_markdown(text) : text
      out = []
      pos = 0
      scan.split(PARA_BREAK).each do |block|
        start = scan.index(block, pos)
        pos = start + block.length
        lead = block[/\A\s*/].length
        body = block.strip
        next if body.empty?
        next if markdown && body.lines.any? { |l| l.match?(FURNITURE) }

        sents = sentences(body, base: start + lead)
        out << Paragraph.new(offset: start + lead, text: body, sentences: sents) unless sents.empty?
      end
      out
    end

    # Sentences of one paragraph, offsets relative to the original text when
    # base is the paragraph's own offset. Hard-wrapped lines are one paragraph,
    # so the text is matched as written and only collapsed for the caller.
    def sentences(body, base: 0)
      parts = []
      buf_start = nil
      buf = +""
      pos = 0
      pieces = body.split(BOUNDARY)
      pieces.each do |piece|
        at = body.index(piece, pos)
        pos = at + piece.length
        buf_start ||= at
        buf << (buf.empty? ? piece : "#{body[(buf_start + buf.length)...at]}#{piece}")
        next if buf.match?(ABBREV)

        parts << Sentence.new(offset: base + buf_start, text: buf.gsub(/\s+/, " ").strip)
        buf = +""
        buf_start = nil
      end
      parts << Sentence.new(offset: base + buf_start, text: buf.gsub(/\s+/, " ").strip) unless buf.empty?
      parts
    end
  end
end
