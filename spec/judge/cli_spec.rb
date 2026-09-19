# frozen_string_literal: true

require "stringio"
require "tempfile"
require_relative "../support/fake_backend"
require_relative "../../lib/sloplint/judge/cli"

RSpec.describe "the --judge flag and the sloplint-judge executable" do
  def run(mod, argv, stdin_text: "")
    out = StringIO.new
    err = StringIO.new
    stdin = StringIO.new(stdin_text)
    def stdin.tty? = false
    [mod.run(argv, out:, err:, stdin:), out.string, err.string]
  end

  let(:text) { "That's the whole point.\n\nFirst fact here. Second fact here. In short, facts matter.\n" }

  # Swap the backend table's loader for the fake, so the CLI path is exercised
  # end to end with no network.
  before do
    fake = FakeBackend.new { |state, _n, q| state["paragraph"].to_s.include?("In short") || state.key?("target") ? level(0) : level(q["criteria"].size - 1) }
    allow(Sloplint::Judge::Backend).to receive(:load).and_return(fake)
  end

  it "merges regex and judge notes in document order under sloplint check --judge" do
    code, out, err = run(Sloplint::CLI, ["check", "--judge", "-o", "json", "-"], stdin_text: text)
    expect(code).to eq(1)
    notes = JSON.parse(out)
    expect(notes.first["rule"]).to eq("thats-the-whole")
    expect(notes.map { |n| n["rule"] }).to include("wrap-up", "no-news")
    positions = notes.map { |n| [n["line"], n["column"]] }
    expect(positions).to eq(positions.sort)
    expect(err).to include("judge fake")
  end

  it "accepts judge ids in --select and --ignore only with --judge" do
    code, out, = run(Sloplint::CLI, ["check", "--judge", "--select", "wrap-up", "-o", "json", "-"], stdin_text: text)
    expect(code).to eq(1)
    expect(JSON.parse(out).map { |n| n["rule"] }).to eq(["wrap-up"])
    code, _, err = run(Sloplint::CLI, ["check", "--select", "wrap-up", "-"], stdin_text: text)
    expect(code).to eq(2)
    expect(err).to include("unknown rule or category: wrap-up")
  end

  it "exits 3 and writes no notes when the backend fails under --judge" do
    broken = Class.new do
      def name = "broken"
      def ask(*) = raise(Sloplint::Judge::BackendError, "no key")
    end.new
    allow(Sloplint::Judge::Backend).to receive(:load).and_return(broken)
    code, out, err = run(Sloplint::CLI, ["check", "--judge", "-"], stdin_text: text)
    expect(code).to eq(3)
    expect(out).to eq("")
    expect(err).to include("judge backend failure: no key")
  end

  it "still runs plain check with no judge code involved" do
    code, out, = run(Sloplint::CLI, ["check", "-o", "json", "-"], stdin_text: text)
    expect(code).to eq(1)
    rules = JSON.parse(out).map { |n| n["rule"] }
    expect(rules).to include("thats-the-whole")
    expect(rules & Sloplint::Judge::RULES.map(&:id)).to be_empty
  end

  describe "sloplint-judge" do
    it "checks with judge rules only" do
      code, out, = run(Sloplint::Judge::CLI, ["check", "-o", "json", "-"], stdin_text: text)
      expect(code).to eq(1)
      expect(JSON.parse(out).map { |n| n["rule"] }).not_to include("thats-the-whole")
    end

    it "lists and explains its rules" do
      code, out, = run(Sloplint::Judge::CLI, ["rules"])
      expect(code).to eq(0)
      expect(out.lines.size).to eq(Sloplint::Judge::RULES.size)
      code, out, = run(Sloplint::Judge::CLI, ["explain", "wrap-up"])
      expect(code).to eq(0)
      expect(out).to include("Asks:").and include("(flags)")
    end

    it "exits 2 on a mistyped rule and 3 on a backend failure" do
      code, _, err = run(Sloplint::Judge::CLI, ["check", "--select", "nope", "-"], stdin_text: text)
      expect(code).to eq(2)
      expect(err).to include("unknown rule")
      broken = Class.new do
        def name = "broken"
        def ask(*) = raise(Sloplint::Judge::BackendError, "down")
      end.new
      allow(Sloplint::Judge::Backend).to receive(:load).and_return(broken)
      expect(run(Sloplint::Judge::CLI, ["check", "-"], stdin_text: text).first).to eq(3)
    end

    it "compares two files, mapping the answer back through the random swap" do
      backend = FakeBackend.new { |state, _n, q| q["type"] == "choice" ? [{ "A" => 0.2, "B" => 0.8 }, 0.9] : [0.1, 0.9] }
      allow(Sloplint::Judge::Backend).to receive(:load).and_return(backend)
      a = Tempfile.new("a"); a.write("Old."); a.close
      b = Tempfile.new("b"); b.write("New."); b.close
      code, out, = run(Sloplint::Judge::CLI, ["compare", "--drift", a.path, b.path])
      expect(code).to eq(0)
      v = JSON.parse(out)
      expect(v.keys).to include("keep", "p_keep_b", "keep_confidence", "drift", "drift_confidence", "accept")
      sent = backend.calls.first.first
      expect(v["keep"]).to eq(sent["B"] == "New." ? "B" : "A")
    end
  end
end
