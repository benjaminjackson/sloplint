# frozen_string_literal: true

require_relative "../support/fake_backend"

RSpec.describe Sloplint::Judge::Engine do
  let(:rules) { Sloplint::Judge::RULES }
  let(:para_rule) { rules.find { |r| r.id == "wrap-up" } }
  let(:sent_rule) { rules.find { |r| r.id == "no-news" } }
  let(:text) { "Intro line.\n\nFirst fact here. Second fact here. In short, facts matter.\n\nShort para. Two only.\n" }

  # Everything flags at level 0 with high confidence.
  let(:flag_all) { FakeBackend.new }
  # Nothing flags: the top level always wins.
  let(:flag_none) { FakeBackend.new { |_s, _n, q| level(q["criteria"].size - 1) } }

  it "emits sloplint Notes with the rule's message and a context window" do
    result = described_class.scan(text, rules: [para_rule], backend: flag_all)
    expect(result.notes.size).to eq(1)
    n = result.notes.first
    expect(n).to be_a(Sloplint::Note)
    expect(n.rule).to eq("wrap-up")
    expect(n.excerpt).to eq("In short, facts matter.")
    expect(n.context).to include("[In short, facts matter.]")
    expect([n.line, n.column]).to eq([3, 36])
    expect(n.confidence).to eq("high")
    expect(n.count).to be_nil
  end

  it "skips paragraphs under three sentences unless strict" do
    described_class.scan(text, rules: [para_rule], backend: flag_all)
    expect(flag_all.calls.map { |s, _| s["sentence_count"] }).to eq([3])
    strict = FakeBackend.new
    described_class.scan(text, rules: [para_rule], backend: strict, strict: true)
    expect(strict.calls.map { |s, _| s["sentence_count"] }).to eq([1, 3, 2])
  end

  it "runs sentence rules in flagged paragraphs and in the short ones no paragraph rule saw" do
    long = text + "\nA. B. C. D.\n"
    backend = FakeBackend.new do |state, _n, _q|
      state.key?("target") ? level(0) : (state["paragraph"].include?("In short") ? level(0) : level(2))
    end
    result = described_class.scan(long, rules: [para_rule, sent_rule], backend: backend)
    sentence_calls = backend.calls.select { |s, _| s.key?("target") }
    # 1 + 3 + 2 sentences from the flagged and the short paragraphs; the unflagged four-sentence one is skipped.
    expect(sentence_calls.size).to eq(6)
    expect(sentence_calls.none? { |s, _| s["paragraph"]["sentences"] == %w[A. B. C. D.] }).to be(true)
    expect(result.notes.map(&:rule).tally).to eq("wrap-up" => 1, "no-news" => 6)
  end

  it "runs sentence rules everywhere when the run has no paragraph rule" do
    described_class.scan(text, rules: [sent_rule], backend: flag_all)
    expect(flag_all.calls.size).to eq(6)
  end

  it "does not let a dropped low-confidence paragraph flag open its sentences" do
    one_para = "First fact here. Second fact here. In short, facts matter.\n"
    backend = FakeBackend.new { |state, _n, _q| state.key?("target") ? level(0) : level(0, confidence: 0.3) }
    result = described_class.scan(one_para, rules: [para_rule, sent_rule], backend: backend)
    expect(result.notes).to be_empty
    expect(backend.calls.none? { |s, _| s.key?("target") }).to be(true)
  end

  it "keeps the context window on the sentence under --markdown, with the excerpt as written" do
    md = "Intro.\n\nRun `x` to start. Run `x` to start. In short, run `x`.\n\nRun `x` to start. Done. Fine.\n"
    result = described_class.scan(md, rules: [para_rule], backend: flag_all, markdown: true)
    n = result.notes.first
    expect(n.excerpt).to eq("In short, run `x`.")
    expect(n.context).to eq("…Run `x` to start. Run `x` to start. [In short, run `x`.] Run `x` to start. Done. Fine.")
  end

  it "turns a partial answer set from the backend into a BackendError" do
    partial = Class.new do
      def name = "partial"
      def ask(_state, questions) = questions.keys.first(1).to_h { |k| [k, Sloplint::Judge::Answer.new(type: "score", probabilities: [1.0, 0, 0], confidence: 1.0)] }
    end.new
    expect { described_class.scan(text, rules: rules.select { |r| r.unit == :paragraph }, backend: partial) }
      .to raise_error(Sloplint::Judge::BackendError, /no answer for/)
  end

  it "bands the model's confidence and keeps low notes only under strict" do
    backend = FakeBackend.new { |_s, _n, _q| level(0, confidence: 0.6) }
    expect(described_class.scan(text, rules: [para_rule], backend: backend).notes.first.confidence).to eq("medium")
    low = FakeBackend.new { |_s, _n, _q| level(0, confidence: 0.4) }
    expect(described_class.scan(text, rules: [para_rule], backend: low).notes).to be_empty
    expect(described_class.scan(text, rules: [para_rule], backend: low, strict: true).notes.first.confidence).to eq("low")
  end

  it "caps a note's confidence at the rule's" do
    matched = rules.find { |r| r.id == "matched-shape" }
    expect(described_class.scan(text, rules: [matched], backend: flag_all).notes).to be_empty
    result = described_class.scan(text, rules: [matched], backend: flag_all, strict: true)
    expect(result.notes.map(&:confidence).uniq).to eq(["low"])
  end

  it "interpolates the register into every question" do
    described_class.scan(text, rules: [para_rule], backend: flag_all, register: "a home cook")
    expect(flag_all.calls.first.last["wrap-up"]["instructions"]).to include("a home cook")
  end

  it "batches all rules of one unit into one request and sums usage once per request" do
    result = described_class.scan(text, rules: rules.select { |r| r.unit == :paragraph }, backend: flag_all)
    expect(flag_all.calls.size).to eq(1)
    expect(flag_all.calls.first.last.keys).to contain_exactly("particulars", "wrap-up", "throat-clearing")
    expect(result.usage).to eq("input_tokens" => 100)
  end

  it "reports nothing when nothing flags" do
    expect(described_class.scan(text, rules: rules, backend: flag_none).notes).to be_empty
  end

  it "refuses a backend name that is not in the table" do
    expect { Sloplint::Judge::Backend.load("nope") }.to raise_error(ArgumentError, /unknown backend: nope/)
  end

  it "raises BackendError out of the parallel map" do
    failing = Class.new do
      def name = "broken"
      def ask(*) = raise(Sloplint::Judge::BackendError, "down")
    end.new
    expect { described_class.scan(text, rules: [para_rule], backend: failing) }.to raise_error(Sloplint::Judge::BackendError, "down")
  end
end
