# frozen_string_literal: true

require "benchmark"

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

  it "drops furniture under --markdown and keeps it otherwise" do
    text = "- a bullet line.\n\n| a | table |\n\n> quoted.\n\nProse here. More prose.\n"
    expect(described_class.paragraphs(text, markdown: true).map(&:text)).to eq(["Prose here. More prose."])
    expect(described_class.paragraphs(text).size).to eq(4)
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
    small = Benchmark.realtime { described_class.paragraphs(para * 500) }
    large = Benchmark.realtime { described_class.paragraphs(para * 4000) }
    expect(large).to be < small * 30
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

  it "blanks code under --markdown so a fenced block is not a paragraph" do
    text = "Prose.\n\n```\nnot. prose. here.\n```\n\nMore prose.\n"
    expect(described_class.paragraphs(text, markdown: true).map(&:text)).to eq(["Prose.", "More prose."])
  end
end
