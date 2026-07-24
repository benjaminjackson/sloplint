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
