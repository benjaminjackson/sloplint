# frozen_string_literal: true

require "benchmark"
require_relative "../../lib/sloplint/split"

RSpec.describe Sloplint::Split do
  it "splits paragraphs on blank lines and sentences on terminal punctuation" do
    text = "One thing. Another thing here.\n\nSecond para.\n"
    paras = described_class.paragraphs(text)
    expect(paras.map { |p| p.sentences.map(&:text) }).to eq([["One thing.", "Another thing here."], ["Second para."]])
  end

  it "keeps offsets into the original text, across hard wraps" do
    text = "# Title\n\nFirst sentence\nwraps here. Second one.\n"
    paras = described_class.paragraphs(text, markdown: true)
    expect(paras.size).to eq(1)
    s = paras.first.sentences
    expect(text[s[0].offset, 5]).to eq("First")
    expect(text[s[1].offset, 6]).to eq("Second")
    expect(s[0].text).to eq("First sentence wraps here.")
  end

  it "does not split on abbreviations" do
    sents = described_class.sentences("See Fig. 3 for the e.g. case. Then stop.")
    expect(sents.map(&:text)).to eq(["See Fig. 3 for the e.g. case.", "Then stop."])
    expect(described_class.sentences("The answer was no. We moved on. Then it broke.").size).to eq(3)
  end

  it "does not split on letters written one at a time" do
    expect(described_class.sentences("The U.S. Army bought 400 copies. It cost $2.").map(&:text))
      .to eq(["The U.S. Army bought 400 copies.", "It cost $2."])
    # The cost of that, written down: a sentence that really ends in one of
    # these takes the next one with it.
    expect(described_class.sentences("It was in the U.S. It cost $2.").map(&:text))
      .to eq(["It was in the U.S. It cost $2."])
  end

  # A single capital before a period is left alone, and that is a choice: a
  # design document writes "Service A." as a whole sentence far more often
  # than it names anyone by initial, so the name is what loses.
  it "splits after a single capital, initial or not" do
    expect(described_class.sentences("Service A. Service B handles the rest.").map(&:text))
      .to eq(["Service A.", "Service B handles the rest."])
    expect(described_class.sentences("J. K. Rowling wrote the book.").map(&:text))
      .to eq(["J.", "K.", "Rowling wrote the book."])
  end

  # Two pairs at least, so the last letter of a word is not a run of them.
  it "still ends a sentence after a word that happens to end in a capital" do
    expect(described_class.sentences("It is bigger than AT&T. Consolidation followed.").size).to eq(2)
    expect(described_class.sentences("The free upgrade was from 512K. The cable firm paid.").size).to eq(2)
    expect(described_class.sentences("She left Liberty-X. Each of them stayed.").size).to eq(2)
  end

  it "keeps an inline code span as a word of its sentence under --markdown" do
    text = "`sloplint check` scans the file. Then it prints notes. `x` runs next. Done here.\n"
    sents = described_class.paragraphs(text, markdown: true).first.sentences
    expect(sents.map(&:text)).to eq(["`sloplint check` scans the file.", "Then it prints notes.", "`x` runs next.", "Done here."])
    expect(sents.first.offset).to eq(0)
    # A URL is a word too, and a line that is only a command or a bare link is furniture.
    text = "`make test`\n\nhttps://example.com/a\n\nSee https://example.com for more. Fine.\n"
    expect(described_class.paragraphs(text, markdown: true).map { |p| p.sentences.map(&:text) })
      .to eq([["See https://example.com for more.", "Fine."]])
  end

  it "drops furniture whether or not --markdown is set" do
    text = "- a bullet line.\n\n| a | table |\n\n> quoted.\n\nProse here. More prose.\n"
    expect(described_class.paragraphs(text, markdown: true).map(&:text)).to eq(["Prose here. More prose."])
    expect(described_class.paragraphs(text).map(&:text)).to eq(["Prose here. More prose."])
  end

  it "drops a heading and a blockquoted template line with no markdown: argument" do
    text = "## How the rollout works\n\n> Hi [name], welcome aboard.\n\n> Best,\n> The team\n"
    expect(described_class.paragraphs(text)).to eq([])
  end

  it "keeps the prose around a tight-bound list and drops only the list lines" do
    text = "One fact. Two facts. Three facts.\n- ticket OPS-412\n- owner: ops\nAfter the list. Still prose.\n"
    paras = described_class.paragraphs(text, markdown: true)
    expect(paras.map(&:text)).to eq(["One fact. Two facts. Three facts.", "After the list. Still prose."])
    expect(text[paras.last.offset, paras.last.length]).to eq("After the list. Still prose.")
  end

  it "blanks a wrapped bullet whole, and a one-line lead-in ending in a colon" do
    text = "- Long sentences appeared often. A rule asks\n  for full sentences, so that is fine.\n- Short one.\n\nRun it like this:\n\nProse here. More prose. And more.\n"
    expect(described_class.paragraphs(text, markdown: true).map(&:text)).to eq(["Prose here. More prose. And more."])
  end

  it "cuts sentence text from the original, so an excerpt is always in the file" do
    text = "Run `bundle exec rspec` to start. See https://example.com/x for more.\n"
    sents = described_class.paragraphs(text, markdown: true).first.sentences
    expect(sents.map(&:text)).to eq(["Run `bundle exec rspec` to start.", "See https://example.com/x for more."])
    sents.each { |s| expect(text[s.offset, s.length]).to eq(s.text) }
  end

  it "walks offsets without rescanning, so non-ASCII text stays linear" do
    para = "The “quoted” claim held. It held again. And again.\n\n"
    small = 3.times.map { Benchmark.realtime { described_class.paragraphs(para * 500) } }.min
    large = 3.times.map { Benchmark.realtime { described_class.paragraphs(para * 4000) } }.min
    expect(large).to be < small * 16
  end

  # Cutting a sentence out of the paragraph it is in, rather than out of the
  # whole document, is only linear while the paragraphs are short. A page of
  # text with no blank line in it is one paragraph.
  it "stays linear inside one paragraph that is the whole document" do
    line = "The “quoted” claim held up. "
    small = 3.times.map { Benchmark.realtime { described_class.paragraphs(line * 2_000) } }.min
    large = 3.times.map { Benchmark.realtime { described_class.paragraphs(line * 16_000) } }.min
    expect(large).to be < small * 16
  end

  # The URL pattern used to take \S+, which swallowed the period that ended
  # the sentence, and then two sentences were blanked into one unit.
  it "leaves the sentence its closing punctuation when a URL ends it" do
    text = "See https://example.com. Then do X. Then Y.\n"
    sents = described_class.paragraphs(text, markdown: true).first.sentences
    expect(sents.map(&:text)).to eq(["See https://example.com.", "Then do X.", "Then Y."])
    sents.each { |s| expect(text[s.offset, s.length]).to eq(s.text) }
    # And a line that is one bare link is still furniture with a full stop
    # after it, now that the full stop is no longer part of the link.
    expect(described_class.paragraphs("https://example.com.\n\nAlpha here. Beta here.\n", markdown: true).map(&:text))
      .to eq(["Alpha here. Beta here."])
  end

  # A code span on a line of its own is a command, and furniture. The same
  # line under a line of prose is the wrapped tail of that sentence, and
  # dropping it takes the sentence's object with it.
  it "gives a wrapped code span back to the sentence it ends" do
    text = "Run it with\n`make test`.\nThen commit the result. And push it.\n"
    paras = described_class.paragraphs(text, markdown: true)
    expect(paras.map(&:text)).to eq(["Run it with `make test`. Then commit the result. And push it."])
    expect(paras.first.sentences.map(&:text))
      .to eq(["Run it with `make test`.", "Then commit the result.", "And push it."])
    # With no prose above it, the same line is a command again.
    expect(described_class.paragraphs("`make test`.\n\nAlpha here. Beta here.\n", markdown: true).map(&:text))
      .to eq(["Alpha here. Beta here."])
  end

  # String#strip takes a leading NUL off as well as whitespace, and the lead
  # count did not, so every offset in the paragraph was one character early
  # and its last character was cut off.
  it "counts the same characters off both ends of a block" do
    text = "\u0000Alpha here. Beta here.\n"
    para = described_class.paragraphs(text).first
    expect(para.text).to eq("Alpha here. Beta here.")
    expect(text[para.offset, para.length]).to eq(para.text)
    para.sentences.each { |s| expect(text[s.offset, s.length]).to eq(s.text) }
  end

  # Written out once, not built again for every block of every document.
  it "holds its interpolated patterns as constants" do
    expect(described_class::BREAK_ONLY).to eq(/\A#{Sloplint::PARA_BREAK}\z/)
    expect(described_class::KEEP_BREAK).to eq(/(#{Sloplint::PARA_BREAK})/)
    expect(described_class::KEEP_BOUNDARY).to eq(/(#{described_class::BOUNDARY})/)
  end

  # The document this tool is pointed at explains Markdown, so it quotes a
  # fence inside a code span. That used to open a block mid-sentence, and
  # from there every fence in the file paired with the wrong one: real prose
  # went blank and a code block came back as prose.
  it "does not lose a paragraph to a fence quoted inside a sentence" do
    text = "It blanks fenced code (```` ``` ````) and inline code first. A second sentence here.\n\n" \
           "A paragraph after it. It has three sentences. Here is the third.\n\n" \
           "```\ncode(). More code. Third call.\n```\n"
    paras = described_class.paragraphs(text, markdown: true)
    expect(paras.size).to eq(2)
    expect(paras.first.text).to end_with("A second sentence here.")
    expect(paras.last.text).to eq("A paragraph after it. It has three sentences. Here is the third.")
  end

  # The file that found this, read as the judge reads it.
  it "keeps the code block of docs/SPEC.md out of what the judge is asked" do
    spec = File.read(File.expand_path("../../docs/SPEC.md", __dir__), encoding: "UTF-8")
    paras = described_class.paragraphs(spec, markdown: true)
    expect(paras.map(&:text)).to all(satisfy { |t| !t.include?("cat FILE") && !t.include?("Recommended for agents") })
    expect(paras.map(&:text)).to include(a_string_starting_with("This is a first-class requirement"))
  end

  # Only a list item runs on to an indented second line. Chaining from every
  # furniture line took an indented paragraph under a heading with it, and
  # the judge was then asked nothing about that paragraph.
  it "keeps an indented paragraph under a heading, a table or a rule" do
    %W[#\ A\ heading |\ a\ |\ b\ | ---].each do |furniture|
      text = "#{furniture}\n  Indented prose here. Second one. Third one here.\n"
      expect(described_class.paragraphs(text, markdown: true).map(&:text))
        .to eq(["Indented prose here. Second one. Third one here."])
    end
    # And on a CRLF file, where the line still ends in a carriage return.
    text = "# A heading\r\n  Indented prose here. Second one. Third one here.\r\n"
    expect(described_class.paragraphs(text, markdown: true).map(&:text))
      .to eq(["Indented prose here. Second one. Third one here."])
  end

  it "still drops a bullet or an ordered item that wraps onto a second line" do
    text = "- A bullet that wraps\n  onto a second line. And a third.\n\nPlain prose here. More of it.\n"
    expect(described_class.paragraphs(text, markdown: true).map(&:text)).to eq(["Plain prose here. More of it."])
    text = "1. First item here. More of it.\n   A wrapped line of the item.\n\nPlain prose after. More.\n"
    expect(described_class.paragraphs(text, markdown: true).map(&:text)).to eq(["Plain prose after. More."])
  end

  # CommonMark keeps this line in the paragraph above it, because an ordered
  # list may interrupt a paragraph only when it starts at 1. The number is
  # then furniture inside the prose, not a sentence of its own.
  it "does not read an enumerator as a sentence" do
    text = "Here is the list that follows.\n2. Second item after prose. Another one here.\n"
    expect(described_class.paragraphs(text).first.sentences.map(&:text))
      .to eq(["Here is the list that follows.", "2. Second item after prose.", "Another one here."])
    # A year is not an enumerator: it ends the sentence it is the last word of.
    expect(described_class.sentences("It was rewritten in\n2021. Then it shipped.").map(&:text))
      .to eq(["It was rewritten in 2021.", "Then it shipped."])
  end

  it "keeps a wrapped line that starts with a year, as CommonMark does" do
    text = "The library was released in\n2019. It was rewritten in\n2021. Adoption grew after that.\n"
    paras = described_class.paragraphs(text, markdown: true)
    expect(paras.map { |p| p.sentences.map(&:text) })
      .to eq([["The library was released in 2019.", "It was rewritten in 2021.", "Adoption grew after that."]])
  end

  it "drops an ordered list after a blank line, or one that starts at 1 after prose" do
    text = "Intro here.\n\n2. second item\n3. third item\n\nProse again.\n"
    expect(described_class.paragraphs(text, markdown: true).map(&:text)).to eq(["Intro here.", "Prose again."])
    text = "Do this first.\n1. wash it\n2. dry it\nDone now.\n"
    expect(described_class.paragraphs(text, markdown: true).map(&:text)).to eq(["Do this first.", "Done now."])
  end

  it "sees the furniture on a CRLF file, where the line still ends in a carriage return" do
    text = "---\r\n\r\nAlpha is here.\r\n"
    expect(described_class.paragraphs(text, markdown: true).map(&:text)).to eq(["Alpha is here."])
    text = "https://example.com/a\r\n\r\nAlpha is here.\r\n"
    expect(described_class.paragraphs(text, markdown: true).map(&:text)).to eq(["Alpha is here."])
  end

  # The placeholder used to be the letter X, so a line of real text reading
  # "XXX" was taken for a blanked code span and never examined.
  it "keeps a line of capital letters that only looks like a blanked code span" do
    text = "XXX\n\nAlpha is here. Beta is here.\n"
    expect(described_class.paragraphs(text, markdown: true).map(&:text)).to eq(["XXX", "Alpha is here. Beta is here."])
  end

  it "keeps an HTML comment out of what the model is asked, and in what a note quotes" do
    text = "Alpha is here. <!-- TODO fix --> Beta is `code` here. See https://x.y/z now.\n"
    para = described_class.paragraphs(text, markdown: true).first
    expect(para.asked).to eq("Alpha is here. Beta is `code` here. See https://x.y/z now.")
    expect(para.text).to eq(text.strip)
    expect(text[para.offset, para.length]).to eq(para.text)
    expect(para.sentences.map(&:asked)).to eq(["Alpha is here.", "Beta is `code` here.", "See https://x.y/z now."])
    expect(para.sentences.map { |s| text[s.offset, s.length] }).to eq(para.sentences.map(&:text))
  end

  it "asks about the file as written when there is no --markdown" do
    text = "Alpha is here. <!-- TODO fix --> Beta is here.\n"
    para = described_class.paragraphs(text).first
    expect(para.asked).to eq(para.text)
    expect(described_class.sentences("One thing. Another thing.").map(&:asked)).to eq(["One thing.", "Another thing."])
  end

  it "blanks code under --markdown so a fenced block is not a paragraph" do
    text = "Prose.\n\n```\nnot. prose. here.\n```\n\nMore prose.\n"
    expect(described_class.paragraphs(text, markdown: true).map(&:text)).to eq(["Prose.", "More prose."])
  end

  # Under --markdown a code block, an HTML block and front matter are not
  # prose. Reaching the judge, each one is a paid request and a possible
  # note on a line nobody wrote as a sentence.
  it "drops an indented code block, and keeps a two-space indent as prose" do
    text = "Here is the intro. It runs on.\n\n    code = 1\n    more = 2\n\nAfter the block. More after.\n"
    expect(described_class.paragraphs(text, markdown: true).map(&:text))
      .to eq(["Here is the intro. It runs on.", "After the block. More after."])
    # Four spaces is a code block, two is an indented paragraph, which is
    # what CommonMark says and what the indented prose under a heading
    # relies on.
    text = "# Heading\n  Indented prose after heading. Second one.\n"
    expect(described_class.paragraphs(text, markdown: true).map(&:text))
      .to eq(["Indented prose after heading. Second one."])
  end

  it "drops a line that is one HTML tag, and keeps a sentence that names one" do
    text = "<details>\n<summary>Click</summary>\n\nProse here. More prose.\n\n</details>\n"
    expect(described_class.paragraphs(text, markdown: true).map(&:text)).to eq(["Prose here. More prose."])
    # The shape is a line that is nothing but a tag. A sentence about a tag
    # has words after the ">", so it stays prose.
    text = "<p> is the tag for a paragraph. It wraps running text.\n"
    expect(described_class.paragraphs(text, markdown: true).map(&:text))
      .to eq(["<p> is the tag for a paragraph. It wraps running text."])
  end

  it "drops YAML front matter, and keeps a horizontal rule between paragraphs" do
    text = "---\ntitle: My Doc\nauthor: Someone\n---\n\nProse here. More prose.\n"
    expect(described_class.paragraphs(text, markdown: true).map(&:text)).to eq(["Prose here. More prose."])
    # Only at the very start of the file. A --- further down is the
    # horizontal rule it has always been, and it separates two paragraphs
    # rather than swallowing one.
    text = "A paragraph here. Second one.\n\n---\n\nAnother paragraph. Second one.\n"
    expect(described_class.paragraphs(text, markdown: true).map(&:text))
      .to eq(["A paragraph here. Second one.", "Another paragraph. Second one."])
    # An opening --- that never closes is not front matter either.
    text = "---\nProse here. More prose. Third one.\n"
    expect(described_class.paragraphs(text, markdown: true).map(&:text)).to eq(["Prose here. More prose. Third one."])
  end

  it "drops a setext title underlined in \"=\", title line included, with no --markdown" do
    text = "Title Here\n===\n\nProse here. More prose.\n"
    expect(described_class.paragraphs(text).map(&:text)).to eq(["Prose here. More prose."])
  end

  it "drops a setext title with a short \"--\" underline as well as a \"---\" one" do
    text = "Section Here\n--\n\nProse here. More prose.\n"
    expect(described_class.paragraphs(text).map(&:text)).to eq(["Prose here. More prose."])
    text = "Section Here\n---\n\nProse here. More prose.\n"
    expect(described_class.paragraphs(text).map(&:text)).to eq(["Prose here. More prose."])
  end

  it "keeps a --- divider between two paragraphs as the horizontal rule it is, not a setext underline" do
    text = "A paragraph here. Second one.\n\n---\n\nAnother paragraph. Second one.\n"
    expect(described_class.paragraphs(text).map(&:text))
      .to eq(["A paragraph here. Second one.", "Another paragraph. Second one."])
  end
end
