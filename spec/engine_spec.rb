# frozen_string_literal: true

RSpec.describe Sloplint::Engine do
  # Engine.scan relies on Regexp.last_match staying bound to the CURRENT match
  # across the body of the to_enum(:scan, pattern).each block -- including
  # after `matched.scan(rule.count_group)` runs, which clobbers $~ in the same
  # frame unless the code already captured MatchData into a local first. A
  # refactor that reads Regexp.last_match lazily instead would silently
  # corrupt line/column/excerpt on every count_group note while leaving
  # `count` itself correct -- the trap that let a prior version of this bug
  # ship unnoticed. This test catches that class of regression directly, by
  # requiring the reported position to actually point at the reported
  # excerpt, rather than trusting a fixed line/column fixture that happens to
  # sit at the very start of a one-line document.
  it "reports positions that point at the reported excerpt, not a stale match" do
    doc = <<~MD
      # Notes

      The report was blunt. No fluff, no filler, no jargon.

      She didn't flinch, didn't blink, didn't look away.
    MD

    notes = Sloplint::Engine.scan(doc).select(&:count)
    expect(notes.size).to eq(2)

    notes.each do |note|
      offset = doc.lines[0, note.line - 1].sum(&:length) + (note.column - 1)
      first_word = note.excerpt.split.first
      expect(doc[offset, first_word.length]).to eq(first_word)
    end

    expect(notes.map { |n| [n.line, n.column, n.count] }).to eq(
      [[3, 23, 3], [5, 5, 3]]
    )
  end

  # exactly-the's optional "that's/this is/it's" prefix used to leave a bare
  # \s* free to absorb the space before "exactly" even when no prefix
  # matched, so the reported column pointed at whitespace instead of the
  # word. Pin the fix: mid-sentence, no prefix, column lands on "exactly".
  it "does not include a leading space in a match with no matched prefix" do
    notes = Sloplint::Engine.scan("We proved exactly the point we needed.")
    note = notes.find { |n| n.rule == "exactly-the" }
    expect(note.excerpt).to start_with("exactly")
    expect(note.column).to eq(11)
  end

  describe ".context_for" do
    def context(text, pattern)
      Sloplint::Engine.context_for(text, pattern.match(text))
    end

    it "surrounds a short match with the words either side" do
      text = "The report landed on a Tuesday and it was blunt — no hedging, no flattery, nothing held back at all."
      expect(context(text, /—/)).to eq("…landed on a Tuesday and it was blunt [—] no hedging, no flattery, nothing held…")
    end

    it "opens at a word boundary rather than mid-word" do
      # The 40-char window starts inside "Tuesday"; the partial word is dropped
      # along with its trailing space, so the ellipsis butts against "landed".
      text = "The report landed on a Tuesday and it was blunt — no hedging."
      expect(context(text, /—/)).to start_with("…landed on")
    end

    it "omits the leading ellipsis for a match at the very start" do
      expect(context("— then the sentence carries on for a while yet.", /—/))
        .to eq("[—] then the sentence carries on for a…")
    end

    it "omits the trailing ellipsis for a match at the very end" do
      expect(context("The sentence trails off into a dash —", /—/))
        .to eq("The sentence trails off into a dash [—]")
    end

    it "returns a long match alone, without padding it further" do
      # em-dash-overuse can span a whole paragraph. Bolting 80 more characters
      # onto an already-long match makes the worst case worse, not clearer.
      text = "She did not flinch, did not blink, did not look away, and did not say a word."
      expect(context(text, /did not flinch.*did not say a word/))
        .to eq("[did not flinch, did not blink, did not look away, and did not say a word]")
    end

    it "collapses a match that wraps across a source line" do
      expect(context("wrapped across\na line — break here.", /—/))
        .to eq("wrapped across a line [—] break here.")
    end

    # scan slices context out of the text as written, not the blanked copy.
    # blank_markdown is length-preserving, so offsets are the same either way --
    # which makes it easy to pass the wrong string and never notice, since
    # line/column stay correct and only the excerpt turns into a run of spaces.
    it "shows real code in the window even when --markdown blanked it" do
      doc = "Run `bundle exec rake` and the vibrant suite goes green in under a minute.\n"
      note = Sloplint::Engine.scan(doc, markdown: true).find { |n| n.rule == "puffery-words" }
      expect(note.context).to include("bundle exec rake")
      expect(note.context).to include("[vibrant]")
    end
  end

  describe ".line_starts_for" do
    # The reference implementation this is checked against: count("\n") in
    # the prefix for the line, position since the last "\n" for the column.
    # This is what line_col used to do directly, per note, before it became
    # a single line_starts table built once and binary-searched -- kept here
    # as ground truth so a future change to the table-building strategy (it
    # already changed once, over a real perf trap -- see git log) can't
    # silently drift from what line/column actually mean.
    def reference_line_col(text, offset)
      prefix = text[0, offset]
      line = prefix.count("\n") + 1
      column = offset - (prefix.rindex("\n") || -1)
      [line, column]
    end

    [
      ["", 0],
      ["abc", 0],
      ["abc", 2],
      ["abc\ndef", 0],
      ["abc\ndef", 3],
      ["abc\ndef", 4],
      ["abc\ndef", 6],
      ["a\n\nb", 3],
      ["abc\n", 4],       # offset at end of text, right after a trailing newline
      ["\n\n\n", 3]       # all-newline document
    ].each do |text, offset|
      it "matches the reference for #{text.inspect} at offset #{offset}" do
        expect(Sloplint::Engine.line_col(text, offset))
          .to eq(reference_line_col(text, offset))
      end
    end

    it "matches the reference across a real multibyte document, sampled" do
      doc = (["The café's façade — nestled — reopened.\n"] * 40).join
      starts = Sloplint::Engine.line_starts_for(doc)
      (0...doc.length).step(7).each do |offset|
        expect(Sloplint::Engine.line_col(doc, offset, line_starts: starts))
          .to eq(reference_line_col(doc, offset))
      end
    end
  end
end
