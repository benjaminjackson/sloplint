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
    # text is the span as the file has it, which is what a note quotes.
    # asked is the same span with what --markdown skips taken out, which is
    # what the model is shown. They are the same string without --markdown.
    Sentence = Data.define(:offset, :length, :text, :asked)
    Paragraph = Data.define(:offset, :length, :text, :asked, :sentences)

    # Furniture: a line that is not prose, whatever a regex would think.
    # Headings, list items, table rows, block quotes, horizontal rules,
    # reference-style link definitions and a lone image or link line.
    FURNITURE = /\A[ \t]*(?:\#{1,6}[ \t]|[-*+][ \t]|\||>|[-*_]{3,}[ \t]*\z|\[[^\]]+\]:[ \t]|!\[)/

    # An ordered-list item, which is furniture too but only sometimes: see
    # ordered_item?.
    ORDERED = /\A[ \t]*(\d+)[.)][ \t]/

    # Abbreviations whose trailing period does not end a sentence. Case
    # matters: "No." is an abbreviation, "no." is the end of a sentence.
    ABBREV = /\b(?:e\.g|i\.e|vs|etc|cf|Fig|No|Dr|Mr|Mrs|Ms|St|Inc|Ltd|Sec|Ch|Vol)\.\z/

    # The other period that does not end a sentence, matched on its shape
    # rather than on a list of words: letters written one at a time with a
    # period after each, which is "U.S.", "U.K.", "e.g.", "i.e." and the rest
    # of them. Two pairs at least, so the last letter of a word is not one:
    # "bigger than AT&T." and "a free upgrade from 512K." still end their
    # sentences. The run is bounded, so a piece is read in one pass.
    #
    # One period of this shape is left alone: a single capital standing as a
    # word. It is an initial in "J. K. Rowling wrote the book.", which is
    # split into three sentences here, and it is a whole sentence in "Service
    # A. Service B handles the rest.", which a design document writes far more
    # often than it names anyone by initial.
    #
    # What the run costs instead: a sentence that really ends in one of these
    # joins the one after it, so "It was in the U.S. It cost $2." is read as
    # one sentence.
    INITIALS = /(?<![[:alpha:]])(?:[[:alpha:]]\.){2,6}\z/

    # A number and a period with nothing else between two boundaries is an
    # enumerator, not a sentence: the "2." of a list item that CommonMark
    # keeps inside the paragraph above it, because a list may interrupt a
    # paragraph only when it starts at 1. The whole piece has to be the
    # number, so a year still closes the sentence it sits in -- "It was
    # rewritten in\n2021. Then it shipped." is two sentences.
    ENUMERATOR = /\A\d+\.\z/

    # The judge's view of Markdown differs from the regex engine's in one
    # way. Fenced code and comments become spaces, as there, but an inline
    # code span or a URL becomes a run of this character, same length: it is
    # a word in its sentence, so "`x` runs fast." starts at the backtick and
    # "Done. `x` runs." is two sentences. Blanked to spaces, the first lost
    # its head and the second merged. It is a private-use codepoint, which
    # ordinary prose cannot contain, so a line of real text is never taken
    # for a blanked one -- a line reading "XXX" used to be.
    INLINE = "\uE000"

    # A sentence ends at .!? (with an optional closing quote or bracket)
    # followed by whitespace and a capital, digit, opening quote/bracket, or
    # a code span, which starts a sentence as any other word does.
    BOUNDARY = /(?<=[.!?]|[.!?]["'”’)\]])\s+(?=["'“‘(\[A-Z0-9#{INLINE}])/

    # The split keeps its separators, so one of the blocks it hands back is
    # the break itself. Both of these are written out here rather than inside
    # the walk, where the interpolation would build the same pattern again for
    # every block of every document.
    BREAK_ONLY = /\A#{PARA_BREAK}\z/
    KEEP_BREAK = /(#{PARA_BREAK})/
    KEEP_BOUNDARY = /(#{BOUNDARY})/

    module_function

    # text: the source. Furniture lines -- headings, bullets, ordered items,
    # table rows, block quotes, horizontal rules and reference lines -- are
    # blanked whether or not markdown is set, because their shape alone says
    # they are not prose. markdown additionally blanks fenced code, HTML
    # comments and URLs before splitting, and the furniture that only shows
    # once a document is read as Markdown: front matter, an indented code
    # block, a lone HTML tag line, and a line that is only a code span or a
    # URL. Splitting happens on the blanked copy; the texts returned are cut
    # from the original at the same offsets, so an excerpt is always a
    # string that is in the file. Blanking is character for character, so
    # the offsets agree.
    def paragraphs(text, markdown: false)
      scan, asked = blank_furniture(markdown ? blank(text) : text, markdown ? blank_blocks(text) : text, markdown:)
      # A document with nothing to leave out is asked about as written, and
      # then every text is cut once instead of twice.
      asked = text if asked == text
      written = Cursor.new(text)
      shown = asked.equal?(text) ? nil : Cursor.new(asked)
      out = []
      at = 0
      # Split keeping the separators, and walk the offsets arithmetically:
      # String#index with a start position rescans from 0 on non-ASCII text.
      scan.split(KEEP_BREAK).each do |block|
        start = at
        at += block.length
        next if block.match?(BREAK_ONLY)

        # Both ends trimmed by the same measure. String#strip takes a leading
        # NUL off as well as whitespace and /\A\s*/ does not, so a block that
        # starts with one used to put every offset in the paragraph one
        # character early and cut its last character off.
        from_lead = block.lstrip
        lead = block.length - from_lead.length
        body = from_lead.rstrip
        next if body.empty?

        offset = start + lead
        # The paragraph is cut out of the original once, and its sentences are
        # cut out of that: cutting each of them out of the whole document by
        # character offset is what made the walk take the square of the
        # document's size.
        para = written.cut(offset, body.length)
        para_asked = shown ? shown.cut(offset, body.length) : para
        sents = sentences(body, base: offset, text: para, asked: para_asked)
        # A one-sentence block ending in a colon is the lead-in to whatever
        # follows (a code block, a list), not a paragraph.
        next if markdown && sents.size == 1 && body.end_with?(":")

        unless sents.empty?
          flat = squash(para)
          out << Paragraph.new(offset:, length: body.length, text: flat, sentences: sents,
                               asked: para.equal?(para_asked) ? flat : squash(para_asked))
        end
      end
      out
    end

    # Sentences of one paragraph. base is where the paragraph starts in the
    # document, which each sentence's offset is counted from. text is the
    # paragraph as the file has it and asked is the copy the model is shown,
    # both cut at the paragraph's own offsets; a sentence is cut out of them
    # and its whitespace collapsed, so hard-wrapped lines read as one. A
    # caller that hands over a bare paragraph and neither copy gets the body
    # itself as both.
    def sentences(body, base: 0, text: nil, asked: nil)
      text ||= body
      asked ||= text
      # The same cursors as a paragraph is cut with, for the same reason: a
      # document whose sentences all sit in one paragraph is one long string
      # to cut them out of.
      written = Cursor.new(text)
      shown = asked.equal?(text) ? nil : Cursor.new(asked)
      cut = lambda do |at, length|
        flat = squash(written.cut(at, length))
        Sentence.new(offset: base + at, length:, text: flat,
                     asked: shown ? squash(shown.cut(at, length)) : flat)
      end
      parts = []
      buf_start = nil
      pos = 0
      body.split(KEEP_BOUNDARY).each do |piece|
        at = pos
        pos = at + piece.length
        next if piece.match?(/\A\s+\z/)

        buf_start ||= at
        # The abbreviation ends where the piece does, and a piece ends at a
        # .!? that a boundary follows, so it is always inside this piece: the
        # whole buffer never has to be cut out of the body to see it.
        next if piece.match?(ABBREV) || piece.match?(INITIALS) || piece.match?(ENUMERATOR)

        parts << cut.call(buf_start, pos - buf_start)
        buf_start = nil
      end
      parts << cut.call(buf_start, pos - buf_start) if buf_start
      parts
    end

    def squash(s) = s.gsub(/\s+/, " ").strip

    def blank(text)
      text.gsub(Engine::MARKDOWN_NOISE) do |s|
        Regexp.last_match[:inline] ? INLINE * s.length : s.gsub(/[^\n]/, " ")
      end
    end

    # The copy the model is shown: fenced code and HTML comments go, because
    # --markdown says they do, and a code span or URL stays as written,
    # because it is a word of its sentence and the model has to read it.
    def blank_blocks(text)
      text.gsub(Engine::MARKDOWN_NOISE) do |s|
        Regexp.last_match[:inline] ? s : s.gsub(/[^\n]/, " ")
      end
    end

    # Blank furniture lines to same-length spaces, and the indented lines that
    # continue a blanked one: a wrapped bullet is one bullet, and its second
    # line is not a sentence of its own. A line that is only code spans or
    # URLs (a command on a line of its own, a bare link) is furniture too.
    LONE_INLINE = /\A[ \t]*#{INLINE}[ \t#{INLINE}]*\z/
    # The same line with sentence punctuation after it. A URL stops before
    # that punctuation now, so the full stop on a bare link line is written
    # there rather than part of the link.
    LONE_INLINE_ENDED = /\A[ \t]*#{INLINE}[ \t#{INLINE}]*[.,;:!?)\]]+\z/

    # A bullet. FURNITURE matches one too, among everything else it matches;
    # this is here because a bullet and an ordered item are the only two
    # kinds of furniture a continuation line can belong to.
    BULLET = /\A[ \t]*[-*+][ \t]/
    # The second line of a list item, indented under the first.
    CONTINUED = /\A(?:[ ]{2,}|\t)\S/
    # An indented code block: four spaces or a tab. Two spaces are still
    # prose, so an indented paragraph under a heading is kept, which is what
    # CommonMark says as well -- a code block starts at four.
    CODE_INDENT = /\A(?:[ ]{4}|\t)/
    # A line that is one HTML tag, opening or closing, matched on that shape
    # rather than on a list of element names: <details>, <div>, <br/> and
    # whatever else a document drops into Markdown all look the same from
    # here. A sentence that names a tag in running text does not look like
    # this: "<p> is the tag for a paragraph." has words after the ">".
    HTML_LINE = %r{\A[ \t]{0,3}</?[A-Za-z][^\n]*>[ \t]*\z}
    # The --- that opens YAML front matter. FURNITURE reads it as a
    # horizontal rule wherever it appears; front matter is the block it
    # opens, and only on the first line of the file.
    FRONT = /\A---[ \t]*\z/

    # How many lines of YAML front matter the document opens with: the ---
    # on the first line, everything to the next --- line, and that line. Zero
    # for a document that does not open with one, so a --- between two
    # paragraphs stays the horizontal rule it is.
    def front_matter(lines)
      return 0 unless lines.first&.chomp&.match?(FRONT)

      close = lines.drop(1).index { |l| l.chomp.match?(FRONT) } or return 0

      close + 2
    end

    # Both copies at once, line by line: the furniture is decided on the
    # splitter's copy, where a code span is a placeholder, and the same lines
    # are blanked in the copy the model is shown. Every line keeps its own
    # length and its line ending, so an offset means the same thing in the
    # original and in both copies. The line ending is taken off before the
    # tests run: on a CRLF file it would otherwise sit between the line and
    # the \z that a horizontal rule or a bare link ends at, and neither would
    # be recognised as furniture. markdown: false still drops a line whose
    # shape alone marks it as furniture -- FURNITURE, a list item, a list
    # item's continuation -- but leaves front matter, an indented code
    # block, a lone HTML tag line and a lone code-span-or-URL line alone,
    # because those only read as furniture once the document is read as
    # Markdown.
    def blank_furniture(scan, shown, markdown: true)
      lines = scan.each_line.to_a
      front = markdown ? front_matter(lines) : 0
      item = false
      prose = false
      code = false
      opens = true
      pairs = lines.zip(shown.each_line.to_a).each_with_index.map do |(whole, also), i|
        l = whole.chomp
        ending = whole[l.length..]
        blank = l.strip.empty?
        # Only a list item runs on to the next line. An indented line under a
        # heading, a table row, a horizontal rule or a link definition is an
        # indented paragraph, and chaining from those dropped the prose along
        # with the furniture above it.
        listed = l.match?(BULLET) || ordered_item?(l, prose)
        indented = l.match?(CODE_INDENT)
        # An indented code block opens where a paragraph cannot be running
        # already -- the first line, or after a blank or furniture line --
        # and where the indent is not a list item's second line. It then runs
        # for as long as the indent holds.
        code = markdown && ((code && (indented || blank)) || (indented && !item && opens))
        dropped = i < front || code || listed || l.match?(FURNITURE) || (markdown && l.match?(HTML_LINE)) ||
                  (markdown && lone_inline?(l, prose)) || (item && l.match?(CONTINUED))
        item = listed || (item && l.match?(CONTINUED))
        prose = !dropped && !blank
        opens = blank || dropped
        dropped ? ["#{" " * l.length}#{ending}"] * 2 : [whole, also]
      end
      [pairs.map(&:first).join, pairs.map(&:last).join]
    end

    # A line that is only code spans or URLs is furniture: a command on a
    # line of its own, a bare link. With sentence punctuation after it, only
    # where no sentence can have been running already -- after a line of
    # prose it is the wrapped tail of that sentence, and "Run it with\n`make
    # test`." is one sentence that would otherwise lose its object.
    def lone_inline?(line, after_prose)
      return true if line.match?(LONE_INLINE)

      !after_prose && line.match?(LONE_INLINE_ENDED)
    end

    # CommonMark lets an ordered list interrupt a paragraph only when it
    # starts at 1. So a hard-wrapped prose line that begins with a year --
    # "The library was released in\n2019. It was rewritten in\n2021." -- is
    # prose, not two list items, and the sentences on it stay in view.
    def ordered_item?(line, after_prose)
      m = ORDERED.match(line) or return false
      !after_prose || m[1] == "1"
    end

    # Cutting a span out of a string by character offset walks the string from
    # its start, because a character is not a fixed number of bytes, so cutting
    # every paragraph of a document out of it one at a time takes the square of
    # the document's size. The spans are asked for in the order they appear, so
    # a cursor holds the byte offset of the last character cut at and answers
    # each one in the length of the span itself: byteslice takes a byte offset,
    # and a byte offset costs nothing to reach.
    class Cursor
      def initialize(text)
        @text = text
        @char = 0
        @byte = 0
      end

      # The span of length characters at character offset at. A cursor only
      # goes forward: asked to go back it would answer with the wrong span,
      # and a note would quote a string that is not in the file.
      def cut(at, length)
        raise ArgumentError, "a cursor at #{@char} was asked for #{at}" if at < @char

        advance(at - @char)
        advance(length)
      end

      private

      def advance(count)
        return "" unless count.positive?

        s = window(count)
        @char += s.length
        @byte += s.bytesize
        s
      end

      # A character is at most four bytes in UTF-8, so four bytes per character
      # is a window wide enough to hold the ones asked for. Any other encoding
      # widens it until it is, or until the string ends. A character split by
      # the far edge of the window is past the count asked for, so it is never
      # one of the ones returned.
      def window(count)
        width = count * 4
        loop do
          s = @text.byteslice(@byte, width)
          return s[0, count] if s.length >= count || s.bytesize < width

          width *= 2
        end
      end
    end
  end
end
