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

  # A paragraph rule asks how a paragraph opens or how it ends, and a
  # paragraph of one or two sentences has no answer to give. --strict used to
  # ask anyway; it now widens the sentence rules and leaves this gate where it
  # is, so the short paragraphs are still read, by the rules that can read
  # them, and the requests that had no answer are not paid for.
  it "skips paragraphs under three sentences, under --strict as well" do
    described_class.scan(text, rules: [para_rule], backend: flag_all)
    expect(flag_all.calls.map { |s, _| s["sentence_count"] }).to eq([3])
    strict = FakeBackend.new
    described_class.scan(text, rules: [para_rule], backend: strict, strict: true)
    expect(strict.calls.map { |s, _| s["sentence_count"] }).to eq([3])
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

  it "caps a note's confidence at the rule's, and still reports it without strict" do
    matched = rules.find { |r| r.id == "matched-shape" }
    # The rule only runs when the user names it, so its low ceiling caps what
    # the note says and does not drop the note.
    expect(described_class.scan(text, rules: [matched], backend: flag_all).notes.map(&:confidence).uniq).to eq(["low"])
    result = described_class.scan(text, rules: [matched], backend: flag_all, strict: true)
    expect(result.notes.map(&:confidence).uniq).to eq(["low"])
    # A low-confidence answer is still dropped outside strict, ceiling or no.
    unsure = FakeBackend.new { |_s, _n, _q| level(0, confidence: 0.4) }
    expect(described_class.scan(text, rules: [matched], backend: unsure).notes).to be_empty
  end

  # --markdown promises to skip HTML comments and fenced code. The note still
  # quotes the file, so the excerpt keeps the comment and the model never
  # sees it.
  it "asks about a paragraph without the comment, and quotes the file in the note" do
    whole = rules.find { |r| r.id == "particulars" }
    text = "First fact here. <!-- TODO drop this --> Second fact here. In short, facts matter.\n"
    result = described_class.scan(text, rules: [whole], backend: flag_all, markdown: true)
    asked = flag_all.calls.first.first
    expect(asked["paragraph"]).to eq("First fact here. Second fact here. In short, facts matter.")
    expect(flag_all.calls.to_s).not_to include("TODO")
    expect(text).to include(result.notes.first.excerpt)
    expect(result.notes.first.excerpt).to include("<!-- TODO drop this -->")
  end

  it "shows a sentence rule the sentence without its comment, and keeps the excerpt as written" do
    text = "Alpha is <!-- x --> here. Beta is here.\n"
    result = described_class.scan(text, rules: [sent_rule], backend: flag_all, markdown: true)
    expect(flag_all.calls.map { |s, _| s["target"] }).to eq(["Alpha is here.", "Beta is here."])
    expect(text).to include(result.notes.first.excerpt)
  end

  it "interpolates the register into every question" do
    described_class.scan(text, rules: [para_rule], backend: flag_all, register: "a home cook")
    expect(flag_all.calls.first.last["wrap-up"]["instructions"]).to include("a home cook")
  end

  it "batches all rules of one unit into one request and sums usage once per request" do
    result = described_class.scan(text, rules: rules.select { |r| r.unit == :paragraph }, backend: flag_all)
    expect(flag_all.calls.size).to eq(1)
    expect(flag_all.calls.first.last.keys).to match_array(rules.select { |r| r.unit == :paragraph }.map(&:id))
    expect(result.usage).to eq("requests" => 1, "input_tokens" => 100)
  end

  # The requests are already paid for by the time usage is summed, so a
  # backend that reports something other than a count under usage must not
  # take the whole scan down with it.
  it "sums the counts in usage and steps over anything that is not one" do
    odd = FakeBackend.new
    allow(odd).to receive(:ask).and_wrap_original do |original, *args|
      original.call(*args).transform_values do |a|
        Sloplint::Judge::Answer.new(type: a.type, probabilities: a.probabilities, confidence: a.confidence,
                                    usage: { "input_tokens" => 100, "cache" => { "read" => 5 }, "note" => "hi" })
      end
    end
    result = described_class.scan(text, rules: [para_rule], backend: odd)
    expect(result.usage).to eq("requests" => 1, "input_tokens" => 100)
  end

  it "reports nothing when nothing flags" do
    expect(described_class.scan(text, rules: rules, backend: flag_none).notes).to be_empty
  end

  # Only a score answer has levels. A choice answer keeps its probabilities
  # in a Hash and a noul answer in a Float, and asking either for the most
  # likely level used to raise NoMethodError from inside a scan.
  it "flags nothing on an answer that has no levels" do
    choice = Sloplint::Judge::Answer.new(type: "choice", probabilities: { "a" => 0.7, "b" => 0.3 }, confidence: 0.9)
    noul = Sloplint::Judge::Answer.new(type: "noul", probabilities: 0.8, confidence: 0.9)
    expect(choice.top).to be_nil
    expect(noul.top).to be_nil
    expect(described_class.flagged?(para_rule, choice)).to be(false)
    expect(described_class.flagged?(para_rule, noul)).to be(false)
  end

  it "refuses a backend name that is not in the table" do
    expect { Sloplint::Judge::Backend.load("nope") }.to raise_error(ArgumentError, /unknown backend: nope/)
    require "sloplint/judge/backends/jev"
    expect { Sloplint::Judge::Backends::Jev.new(url: "http://api.typesafe.ai/v1", key: "k") }.to raise_error(ArgumentError, /must be https/)
    # The key and the document go wherever this points, so only a TypeSafe
    # host is accepted: an injected SYSTEMONE_URL is not a way to run the command.
    expect { Sloplint::Judge::Backends::Jev.new(url: "https://attacker.example/v1", key: "k") }.to raise_error(ArgumentError, /typesafe\.ai host/)
    expect { Sloplint::Judge::Backends::Jev.new(url: "https://typesafe.ai.attacker.example/v1", key: "k") }.to raise_error(ArgumentError, /typesafe\.ai host/)
    expect { Sloplint::Judge::Backends::Jev.new(url: "https://api.typesafe.ai", key: "k") }.to raise_error(ArgumentError, /needs a path/)
    # URI raises URI::InvalidURIError, which no command catches, so the
    # backend turns it into the usage error the other bad settings give.
    expect { Sloplint::Judge::Backends::Jev.new(url: "not a url", key: "k") }.to raise_error(ArgumentError, /is not a URL/)
    expect { Sloplint::Judge::Backends::Jev.configured! }.not_to raise_error
    jev = Sloplint::Judge::Backends::Jev.new(url: "https://staging.typesafe.ai/v1", key: "k")
    expect(jev.name).to eq("jev-latest")
    expect(jev.cost_usd("input_tokens" => 1_000_000_000, "output_tokens" => 5)).to eq(42.0)
    allow(Sloplint::Judge::Secret).to receive(:fetch).and_return(nil)
    expect { Sloplint::Judge::Backends::Jev.new }.to raise_error(ArgumentError, /run `sloplint-judge key set`/)
  end

  # Reading the key means the environment and then a keychain subprocess,
  # which can sit on a dialog nobody can see. A run that is about to be
  # refused for its URL must not pull the secret out of the keychain first.
  it "refuses a bad URL without going near the key" do
    require "sloplint/judge/backends/jev"
    expect(Sloplint::Judge::Secret).not_to receive(:fetch)
    expect { Sloplint::Judge::Backends::Jev.new(url: "https://attacker.example/v1") }
      .to raise_error(ArgumentError, /typesafe\.ai host/)
  end

  # A DNS name is not case-sensitive, and URI hands the host back as it was
  # written, so the pin has to be too.
  it "takes a typesafe.ai host in mixed case, and still refuses another host in mixed case" do
    require "sloplint/judge/backends/jev"
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("SYSTEMONE_URL", anything).and_return("https://API.TypeSafe.ai/v1/systemone")
    expect { Sloplint::Judge::Backends::Jev.configured! }.not_to raise_error
    allow(ENV).to receive(:fetch).with("SYSTEMONE_URL", anything).and_return("https://TypeSafe.ai.Attacker.example/v1")
    expect { Sloplint::Judge::Backends::Jev.configured! }.to raise_error(ArgumentError, /typesafe\.ai host/)
  end

  # The URL is checked but not rewritten, so a SYSTEMONE_URL with a query
  # string must reach the server with that query string on it.
  it "posts to the whole request-URI, query string and all" do
    require "sloplint/judge/backends/jev"
    jev = Sloplint::Judge::Backends::Jev.new(url: "https://api.typesafe.ai/v1/systemone?deployment=eu", key: "k")
    http = instance_double(Net::HTTP)
    allow(http).to receive(:use_ssl=)
    allow(http).to receive(:read_timeout=)
    allow(Net::HTTP).to receive(:new).and_return(http)
    body = JSON.generate("usage" => { "input_tokens" => 7 },
                         "answers" => { "q" => { "probabilities" => { "0" => 0.9, "1" => 0.1 }, "confidence" => 0.8 } })
    sent = nil
    allow(http).to receive(:request) { |req| sent = req; instance_double(Net::HTTPResponse, code: "200", body: body) }
    jev.ask({ "x" => 1 }, { "q" => { "type" => "score", "criteria" => %w[yes no] } })
    expect(sent.path).to eq("/v1/systemone?deployment=eu")
  end

  # Jev may leave out a level whose probability is zero. Sorted keys alone
  # would then shift every level down one and flag the wrong criterion.
  it "gives a score one probability per level, whatever keys come back" do
    answers = { "q" => { "probabilities" => { "0" => 0.1, "2" => 0.9 } } }
    a = jev_answer(answers, "type" => "score", "criteria" => %w[a b c])
    expect(a.probabilities).to eq([0.1, 0.0, 0.9])
    expect(a.top).to eq(2)
    a = jev_answer({ "q" => { "probabilities" => { "1" => 0.1, "2" => 0.9 } } }, "type" => "score", "criteria" => %w[a b c])
    expect(a.probabilities).to eq([0.0, 0.1, 0.9])
  end

  # An evenly split answer names no level. Read as the lowest index it would
  # be level 0, which is the level every rule flags on, so the answer that
  # says least would say the most.
  it "does not flag a score answer whose top level is tied" do
    tied = FakeBackend.new { |_s, _n, _q| [[0.5, 0.5, 0.0], 0.9] }
    expect(described_class.scan(text, rules: [para_rule], backend: tied, strict: true).notes).to eq([])
    # A hair above the other two is still a winner, and still a flag.
    nearly = FakeBackend.new { |_s, _n, _q| [[0.34, 0.33, 0.33], 0.9] }
    expect(described_class.scan(text, rules: [para_rule], backend: nearly, strict: true).notes).not_to be_empty
    all_tied = FakeBackend.new { |_s, _n, _q| [[0.33, 0.33, 0.33], 0.9] }
    expect(described_class.scan(text, rules: [para_rule], backend: all_tied, strict: true).notes).to eq([])
    expect(Sloplint::Judge::Answer.new(type: "score", probabilities: [0.5, 0.5], confidence: 0.9).top).to be_nil
    expect(Sloplint::Judge::Answer.new(type: "score", probabilities: [0.1, 0.9], confidence: 0.9).top).to eq(1)
  end

  it "calls a body Jev could not have sent a backend failure, and a bug in our code a bug" do
    q = { "type" => "score", "criteria" => %w[a b c] }
    expect { jev_answer({ "q" => { "probabilities" => { "3" => 1.0 } } }, q) }
      .to raise_error(Sloplint::Judge::BackendError, /not one of the 3 levels/)
    expect { jev_answer({ "q" => { "probabilities" => [0.1, 0.9] } }, q) }
      .to raise_error(Sloplint::Judge::BackendError, /not a Hash keyed by level/)
    expect { jev_answer({ "q" => nil }, q) }.to raise_error(Sloplint::Judge::BackendError, /not a Hash/)
    expect { jev_answer([], q) }.to raise_error(Sloplint::Judge::BackendError, /not a Hash keyed by question/)
    # No probabilities and no confidence: there is nothing to take a
    # confidence from, which is the body's fault and not a NoMethodError.
    expect { jev_answer({ "q" => { "probabilities" => {} } }, "type" => "choice", "criteria" => { "A" => "a" }) }
      .to raise_error(Sloplint::Judge::BackendError, /no probabilities at all/)
    # A NoMethodError from our own code is not the backend's fault, so it is
    # not dressed up as one.
    broken = Class.new(Sloplint::Judge::Backends::Jev) do
      private

      def normalise(*) = raise(NoMethodError, "oops")
    end
    expect { jev_answer({ "q" => { "probabilities" => { "0" => 1.0 } } }, q, broken) }
      .to raise_error(NoMethodError, "oops")
  end

  # Zero-filling an empty Hash gives every level the same probability, the
  # tie goes to level 0, and level 0 is what a score rule flags on. The
  # empty check in confidence_for does not see this one: a confidence is
  # there, so it never looks at the probabilities.
  it "calls a score answer with no levels at all a malformed body" do
    q = { "type" => "score", "criteria" => %w[a b c] }
    expect { jev_answer({ "q" => { "probabilities" => {}, "confidence" => 0.9 } }, q) }
      .to raise_error(Sloplint::Judge::BackendError, /probabilities for none of the 3 levels/)
  end

  # A confidence is read like any other number Jev sends, so a shape that is
  # not one is the body's fault and not a NoMethodError on our side.
  it "calls a confidence that is not a number a malformed body" do
    q = { "type" => "score", "criteria" => %w[a b] }
    [{}, [], true].each do |shape|
      expect { jev_answer({ "q" => { "probabilities" => { "0" => 1.0 }, "confidence" => shape } }, q) }
        .to raise_error(Sloplint::Judge::BackendError, /is not a probability/)
    end
    # A number written as a string is still a number.
    expect(jev_answer({ "q" => { "probabilities" => { "0" => 1.0 }, "confidence" => "0.75" } }, q).confidence).to eq(0.75)
  end

  # A 200 whose body is not an object at all. Nothing can be read out of it,
  # and reading anyway is a TypeError, which is the class a bug raises.
  it "calls a 200 body that is not a Hash a malformed body" do
    q = { "type" => "score", "criteria" => %w[a b] }
    expect { jev_body("[]", q) }.to raise_error(Sloplint::Judge::BackendError, /the body is Array, not a Hash/)
    expect { jev_body("null", q) }.to raise_error(Sloplint::Judge::BackendError, /the body is NilClass, not a Hash/)
  end

  # Both of these descend from StandardError and not from Net::ProtocolError,
  # so they are named one by one in the rescue list. A proxy that answers
  # with something that is not an HTTP status line raises one of them.
  it "calls an answer that is not HTTP at all a backend failure" do
    [Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError, Net::WriteTimeout].each do |klass|
      http = jev_http
      allow(http).to receive(:request).and_raise(klass, "wrong on the wire")
      expect { jev_ask }.to raise_error(Sloplint::Judge::BackendError, /#{klass}.*wrong on the wire/m)
    end
  end

  # The doubled Net::HTTP every Jev example posts through.
  def jev_http
    require "sloplint/judge/backends/jev"
    http = instance_double(Net::HTTP)
    allow(http).to receive(:use_ssl=)
    allow(http).to receive(:read_timeout=)
    allow(Net::HTTP).to receive(:new).and_return(http)
    http
  end

  def jev_ask(question = { "type" => "score", "criteria" => %w[a b] }, klass = nil)
    (klass || Sloplint::Judge::Backends::Jev).new(url: "https://api.typesafe.ai/v1", key: "k")
                                             .ask({}, { "q" => question }).fetch("q")
  end

  # One Jev request answering with exactly this body.
  def jev_body(body, question, klass = nil)
    allow(jev_http).to receive(:request).and_return(instance_double(Net::HTTPResponse, code: "200", body: body))
    jev_ask(question, klass)
  end

  # One Jev request with this response body, answering one question named "q".
  def jev_answer(answers, question, klass = nil)
    jev_body(JSON.generate("usage" => {}, "answers" => answers), question, klass)
  end

  it "deals work over every thread and still returns results in input order" do
    threads = Queue.new
    out = described_class.in_parallel((1..9).to_a, 8) { |i| threads << Thread.current.object_id; i * 2 }
    expect(out).to eq((1..9).map { |i| i * 2 })
    expect(Array.new(threads.size) { threads.pop }.uniq.size).to eq(8)
  end

  # Every item is a paid request, so a failure ends the run: the threads that
  # were still working stop at their next item instead of draining their deal.
  it "asks for nothing more once one item has failed" do
    asked = Queue.new
    expect do
      described_class.in_parallel((0...20).to_a, 2) do |i|
        asked << i
        raise Sloplint::Judge::BackendError, "down" if i.zero?

        sleep 0.05
      end
    end.to raise_error(Sloplint::Judge::BackendError, "down")
    # The failing item, and the one the other thread was already on.
    expect(asked.size).to be < 5
  end

  # Joining only as far as the first raise leaves the threads dealt after it
  # running, each with a paid request in flight, in a caller that catches the
  # error and carries on.
  it "joins every thread before it raises" do
    before = Thread.list.size
    expect do
      described_class.in_parallel((0...30).to_a, 3) do |i|
        raise Sloplint::Judge::BackendError, "down" if i == 1

        sleep 0.05
      end
    end.to raise_error(Sloplint::Judge::BackendError, "down")
    expect(Thread.list.size).to eq(before)
  end

  it "raises BackendError out of the parallel map" do
    failing = Class.new do
      def name = "broken"
      def ask(*) = raise(Sloplint::Judge::BackendError, "down")
    end.new
    expect { described_class.scan(text, rules: [para_rule], backend: failing) }.to raise_error(Sloplint::Judge::BackendError, "down")
  end
end
