# frozen_string_literal: true

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
  end

  it "drops furniture under --markdown and keeps it otherwise" do
    text = "- a bullet line.\n\n| a | table |\n\n> quoted.\n\nProse here. More prose.\n"
    expect(described_class.paragraphs(text, markdown: true).map(&:text)).to eq(["Prose here. More prose."])
    expect(described_class.paragraphs(text).size).to eq(4)
  end

  it "blanks code under --markdown so a fenced block is not a paragraph" do
    text = "Prose.\n\n```\nnot. prose. here.\n```\n\nMore prose.\n"
    expect(described_class.paragraphs(text, markdown: true).map(&:text)).to eq(["Prose.", "More prose."])
  end
end
