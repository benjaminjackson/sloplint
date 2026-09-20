# frozen_string_literal: true

require_relative "rules"

module Sloplint
  # One match = one Note. See docs/SPEC.md "Note".
  Note = Data.define(
    :path, :line, :column, :severity, :confidence, :rule, :category,
    :message, :excerpt, :context, :count, :rationale, :suggestion
  )

  module Engine
    CONTEXT_CHARS = 40

    module_function

    # text: the source. rules: which Rule objects to run. markdown: blank code, HTML comments and URLs first.
    # path: label carried into each Note (e.g. filename or "-" for stdin).
    def scan(text, rules: RULES, markdown: false, path: "-")
      source = text
      text = blank_markdown(text) if markdown
      line_starts = line_starts_for(text)
      notes = []
      rules.each do |rule|
        text.to_enum(:scan, rule.pattern).each do
          m = Regexp.last_match
          matched = m[0]
          next if rule.skip.any? { |re| matched.match?(re) }

          count = rule.count_group ? matched.scan(rule.count_group).size : nil
          line, column = line_col(text, m.begin(0), line_starts:)
          message = count ? rule.message % { count: count } : rule.message
          notes << Note.new(
            path: path, line: line, column: column,
            severity: rule.severity, confidence: rule.confidence,
            rule: rule.id, category: rule.category,
            message: message, excerpt: matched.gsub(/\s+/, " ").strip,
            context: context_for(source, m),
            count: count, rationale: rule.rationale, suggestion: rule.suggestion
          )
        end
      end
      notes.sort_by { |n| [n.line, n.column] }
    end

    # The match plus ~CONTEXT_CHARS either side, bracketed, whitespace collapsed.
    # A bare `excerpt` is useless for a rule whose match is one character -- see
    # em-dash, where the note said only "—" and you had to open the file and
    # count to the column to learn anything.
    #
    # Truncated ends get an ellipsis and are trimmed back to a word boundary so
    # the window doesn't open mid-word. A match already CONTEXT_CHARS long
    # carries its own context; padding it just makes an em-dash-overuse span
    # (which can run a whole paragraph) longer for no gain, so those return the
    # match alone.
    #
    # source is the PRE-blanking text. blank_markdown replaces each non-newline
    # char with one space, so offsets are identical either way, but a window
    # over blanked text shows code and URLs as a run of spaces. Offsets here are
    # character offsets (MatchData#begin), matching the char-based line_starts_for.
    def context_for(source, match)
      context_window(source, match.begin(0), match.end(0))
    end

    # The same window for any span [b, e) of source, so a tool that locates a
    # sentence rather than a regex match (the judge) draws its context the
    # way sloplint does.
    def context_window(source, b, e)
      span = source[b...e]
      return "[#{span.gsub(/\s+/, " ").strip}]" if span.length >= CONTEXT_CHARS

      pre  = source[[b - CONTEXT_CHARS, 0].max...b]
      post = source[e, CONTEXT_CHARS].to_s
      pre  = "…#{pre.sub(/\A\S*\s+/, "")}" if b > CONTEXT_CHARS
      post = "#{post.sub(/\s+\S*\z/, "")}…" if e + CONTEXT_CHARS < source.length
      "#{pre}[#{span}]#{post}".gsub(/\s+/, " ").strip
    end

    # 1-indexed line and column for a char offset into text. Binary-searches a
    # precomputed line_starts table (see line_starts_for) so a scan with many
    # notes doesn't re-walk the prefix from offset 0 for every single one --
    # the previous version did text[0, offset] per note, which is O(n) per
    # call and O(n * notes) overall, quadratic on a large file with many hits.
    # line_starts is optional so this stays callable standalone.
    def line_col(text, offset, line_starts: nil)
      line_starts ||= line_starts_for(text)
      idx = (line_starts.bsearch_index { |s| s > offset } || line_starts.length) - 1
      [idx + 1, offset - line_starts[idx] + 1]
    end

    # Char offset where each line begins, index 0 = line 1. Computed once per
    # scan and shared across every note instead of recomputed per note.
    #
    # Built via each_line + line.length, not repeated String#index(pat, pos)
    # calls -- on non-ASCII-only text (e.g. curly quotes, em dashes), index
    # with a start position is not O(1)-amortized per call in CRuby, and a
    # few thousand newlines turned this quadratic: 7.4s on a 1.2MB UTF-8
    # file that each_line does in 0.004s.
    def line_starts_for(text)
      starts = [0]
      text.each_line { |line| starts << starts.last + line.length }
      starts.pop unless text.empty? || text.end_with?("\n")
      starts
    end

    # Replace fenced code, HTML comments, inline code, and URLs with same-length
    # whitespace so line/column stay correct. Newlines are preserved. One pass
    # with one alternation, so whichever construct opens first is the one that
    # gets consumed: a `<!--` quoted inside backticks is inline code, and a
    # backtick inside a comment is part of the comment.
    MARKDOWN_NOISE = /(?<block>```.*?```|<!--.*?-->)|(?<inline>`[^`\n]*`|https?:\/\/\S+)/m

    def blank_markdown(text)
      text.gsub(MARKDOWN_NOISE) { |s| s.gsub(/[^\n]/, " ") }
    end
  end
end
