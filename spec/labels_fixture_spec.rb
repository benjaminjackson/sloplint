# frozen_string_literal: true

require "json"

RSpec.describe "spec/fixtures/labels.jsonl" do
  let(:path) { File.expand_path("fixtures/labels.jsonl", __dir__) }
  let(:rows) { File.foreach(path).map { |l| JSON.parse(l) } }

  it "has 64 rows" do
    expect(rows.size).to eq(64)
  end

  it "splits by family and slop the way the real set does" do
    counts = rows.group_by { |r| [r["family"], r["slop"]] }.transform_values(&:size)
    expect(counts).to eq(
      ["maxim", true] => 7, ["maxim", false] => 2,
      ["mirror", true] => 4, ["mirror", false] => 2,
      ["negation", true] => 28, ["negation", false] => 1,
      ["plain", false] => 16,
      ["position", true] => 4
    )
  end

  it "splits negation by shape the way the real set does" do
    shapes = rows.select { |r| r["family"] == "negation" }.group_by { |r| r["shape"] }.transform_values(&:size)
    expect(shapes).to eq(
      "corrective" => 15, "negated-setup" => 3, "negative-subject" => 4,
      "absolute-negative" => 5, "negative-instruction" => 2
    )
  end

  it "carries the required fields on every row" do
    rows.each do |r|
      %w[sentence paragraph slop family kind].each { |f| expect(r).to have_key(f), "#{f} on #{r["sentence"]}" }
    end
  end

  it "sets shape only on negation rows" do
    rows.each do |r|
      if r["family"] == "negation"
        expect(r).to have_key("shape"), r["sentence"]
      else
        expect(r).not_to have_key("shape"), r["sentence"]
      end
    end
  end

  it "leaves out source and note" do
    rows.each { |r| expect(r.keys & %w[source note]).to be_empty, r["sentence"] }
  end

  it "quotes each sentence verbatim inside its paragraph" do
    rows.each { |r| expect(r["paragraph"]).to include(r["sentence"]), r["sentence"] }
  end

  it "never mentions careers, coaching, hiring or job search" do
    text = File.read(path)
    expect(text).not_to match(/career|coach|hiring|job search/i)
  end

  it "never names the private project" do
    expect(`git grep -il offtrail`.strip).to eq("")
  end

  # A row that shares six lowercase words in a row with a real paragraph is a
  # copied detail, whatever changed around it -- see CLAUDE.md "Fixtures are
  # ours to write". Only runs when the gitignored real set is checked out.
  it "shares no run of 6 words with a real paragraph" do
    real_path = File.expand_path("../.corpus/labels/real.jsonl", __dir__)
    skip "no #{real_path}; the .corpus symlink is not set up here" unless File.exist?(real_path)

    runs = lambda do |text|
      words = text.downcase.scan(/[a-z']+/)
      words.each_cons(6).map { |w| w.join(" ") }.to_set
    end
    real_runs = File.foreach(real_path).flat_map { |l| runs.call(JSON.parse(l)["paragraph"]).to_a }.to_set
    rows.each { |r| expect(runs.call(r["paragraph"]) & real_runs).to be_empty, r["sentence"] }
  end
end
