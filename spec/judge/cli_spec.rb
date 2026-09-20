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
    doc = JSON.parse(out)
    expect(doc["judge"]).to include("backend" => "fake", "requests" => be > 0, "input_tokens" => be > 0)
    expect(err).to include("judge fake, #{doc["judge"]["requests"]} requests, #{doc["judge"]["input_tokens"]} input_tokens")
    notes = doc["notes"]
    expect(notes.first["rule"]).to eq("thats-the-whole")
    expect(notes.map { |n| n["rule"] }).to include("wrap-up", "no-news")
    positions = notes.map { |n| [n["line"], n["column"]] }
    expect(positions).to eq(positions.sort)
    expect(err).to include("judge fake")
  end

  it "writes the judge wrapper under --judge even when no judge rule ran" do
    code, out, err = run(Sloplint::CLI, ["check", "--judge", "--select", "em-dash", "-o", "json", "-"], stdin_text: text)
    expect(code).to eq(0)
    doc = JSON.parse(out)
    expect(doc["notes"]).to eq([])
    expect(doc["judge"]).to eq("backend" => "fake", "requests" => 0)
    expect(err).to include("judge fake, 0 requests")
  end

  it "accepts judge ids in --select and --ignore only with --judge" do
    code, out, = run(Sloplint::CLI, ["check", "--judge", "--select", "wrap-up", "-o", "json", "-"], stdin_text: text)
    expect(code).to eq(1)
    expect(JSON.parse(out)["notes"].map { |n| n["rule"] }).to eq(["wrap-up"])
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

  it "exits 2 with an install hint when the judge gem is not there" do
    missing = LoadError.new("cannot load such file -- sloplint/judge")
    missing.instance_variable_set(:@path, "sloplint/judge")
    allow(Sloplint::CLI).to receive(:require).and_raise(missing)
    code, out, err = run(Sloplint::CLI, ["check", "--judge", "-"], stdin_text: text)
    expect([code, out]).to eq([2, ""])
    expect(err).to include("gem install sloplint-judge")
  end

  it "exits 2, not 3, when the backend is not configured or not known" do
    allow(Sloplint::Judge::Backend).to receive(:load).and_raise(ArgumentError, "TYPESAFE_API_KEY is not set")
    code, out, err = run(Sloplint::CLI, ["check", "--judge", "-"], stdin_text: text)
    expect([code, out]).to eq([2, ""])
    expect(err).to include("TYPESAFE_API_KEY is not set")
  end

  it "--help leads with status, the ask, and the output shape" do
    code, out, = run(Sloplint::Judge::CLI, ["--help"])
    expect(code).to eq(0)
    expect(out).to include("sloplint-judge status").and include("ask the person").and include('"judge"')
  end

  it "status answers from the key's presence, never its value, and exits 2 when there is none" do
    allow(Sloplint::Judge::Secret).to receive(:present?).with("TYPESAFE_API_KEY").and_return("keychain")
    expect(Sloplint::Judge::Secret).not_to receive(:fetch)
    code, out, err = run(Sloplint::Judge::CLI, ["status"])
    expect([code, err]).to eq([0, ""])
    expect(out).to match(/\Abackend jev \(model .+\), key from keychain\n\z/)

    allow(Sloplint::Judge::Secret).to receive(:present?).and_return(nil)
    code, out, err = run(Sloplint::Judge::CLI, ["status"])
    expect([code, out]).to eq([2, ""])
    expect(err).to include("run `sloplint-judge key set`")
  end

  it "status and the key commands follow the selected backend's KEY, so two backends are two items" do
    other = Class.new do
      const_set(:KEY, "OTHER_API_KEY")
      def self.configured! = "model other-1"
    end
    stub_const("Sloplint::Judge::Backends::Other", other)
    stub_const("Sloplint::Judge::Backend::TABLE", { "jev" => "Jev", "other" => "Other" })
    expect(Sloplint::Judge::Secret).to receive(:present?).with("OTHER_API_KEY").and_return("keychain")
    code, out, = run(Sloplint::Judge::CLI, ["--backend", "other", "status"])
    expect([code, out]).to eq([0, "backend other (model other-1), key from keychain\n"])

    expect(Sloplint::Judge::Secret).to receive(:present?).with("OTHER_API_KEY").and_return(nil)
    code, _, err = run(Sloplint::Judge::CLI, ["--backend", "other", "status"])
    expect([code, err]).to eq([2, "sloplint-judge: OTHER_API_KEY is not set and no sloplint-judge item for it is in the keychain; run `sloplint-judge key set`\n"])

    expect(Sloplint::Judge::Secret).to receive(:delete_command).with("OTHER_API_KEY").and_return(["/bin/true"])
    expect(Sloplint::Judge::Secret).to receive(:stored?).with("OTHER_API_KEY").and_return(false)
    code, _, err = run(Sloplint::Judge::CLI, ["--backend", "other", "key", "unset"])
    expect([code, err]).to eq([2, "sloplint-judge: no OTHER_API_KEY item in the keychain\n"])

    code, _, err = run(Sloplint::Judge::CLI, ["--backend", "nope", "key", "set"])
    expect(code).to eq(2)
    expect(err).to include("unknown backend: nope")
  end

  it "status exits 2 on an http endpoint, like check would" do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("SYSTEMONE_URL", anything).and_return("http://x")
    code, _, err = run(Sloplint::Judge::CLI, ["status"])
    expect(code).to eq(2)
    expect(err).to include("must be https")
  end

  it "key set refuses without a terminal, before touching the keychain tool" do
    allow(Sloplint::Judge::Secret).to receive(:store_command).and_return(["/usr/bin/security", "add-generic-password", "-w"])
    expect(Process).not_to receive(:exec)
    code, _, err = run(Sloplint::Judge::CLI, ["key", "set"])
    expect(code).to eq(2)
    expect(err).to include("needs a terminal")
  end

  it "key set hands the terminal to the keychain tool, which prompts for the value itself" do
    allow(Sloplint::Judge::Secret).to receive(:store_command).and_return(["/usr/bin/security", "add-generic-password", "-w"])
    tty = StringIO.new
    def tty.tty? = true
    allow(Sloplint::Judge::Secret).to receive(:stored?).and_return(true)
    expect(Process).to receive(:exec).with("/usr/bin/security", "add-generic-password", "-w")
    out = StringIO.new
    Sloplint::Judge::CLI.run(["key", "set"], out:, err: StringIO.new, stdin: tty)
    expect(out.string).to include("Replacing the item stored earlier").and include("Any process running as you can read it back")

    code, _, err = run(Sloplint::Judge::CLI, ["key"])
    expect([code, err]).to eq([2, "usage: sloplint-judge [--backend NAME] key set|unset\n"])
  end

  it "key unset says when there is no item, and runs nothing" do
    allow(Sloplint::Judge::Secret).to receive(:delete_command).and_return(["/usr/bin/security", "delete-generic-password"])
    allow(Sloplint::Judge::Secret).to receive(:stored?).and_return(false)
    expect(Sloplint::Judge::CLI).not_to receive(:system)
    code, _, err = run(Sloplint::Judge::CLI, ["key", "unset"])
    expect([code, err]).to eq([2, "sloplint-judge: no TYPESAFE_API_KEY item in the keychain\n"])
  end

  it "key unset removes the item" do
    allow(Sloplint::Judge::Secret).to receive(:delete_command).and_return(["/usr/bin/security", "delete-generic-password"])
    allow(Sloplint::Judge::Secret).to receive(:stored?).and_return(true)
    expect(Sloplint::Judge::CLI).to receive(:system).with("/usr/bin/security", "delete-generic-password", out: File::NULL, err: File::NULL).and_return(true)
    code, out, = run(Sloplint::Judge::CLI, ["key", "unset"])
    expect(code).to eq(0)
    expect(out).to include("Removed TYPESAFE_API_KEY")
  end

  it "keeps the files in argv order when merging judge notes" do
    a = Tempfile.new("a"); a.write(text); a.close
    b = Tempfile.new("b"); b.write(text); b.close
    _, out, = run(Sloplint::CLI, ["check", "--judge", "-o", "json", b.path, a.path])
    expect(JSON.parse(out)["notes"].keys).to eq([b.path, a.path])
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
      doc = JSON.parse(out)
      expect(doc["notes"].map { |n| n["rule"] }).not_to include("thats-the-whole")
      expect(doc["judge"]["backend"]).to eq("fake")
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

    it "reads a flag written after the two files, and refuses a third file" do
      a = Tempfile.new("a"); a.write("Old."); a.close
      b = Tempfile.new("b"); b.write("New."); b.close
      backend = FakeBackend.new { |_s, _n, q| q["type"] == "choice" ? [{ "A" => 0.2, "B" => 0.8 }, 0.9] : [0.1, 0.9] }
      allow(Sloplint::Judge::Backend).to receive(:load).and_return(backend)
      code, out, = run(Sloplint::Judge::CLI, ["compare", a.path, b.path, "--drift"])
      expect(code).to eq(0)
      expect(JSON.parse(out)["drift"]).not_to be_nil
      code, _, err = run(Sloplint::Judge::CLI, ["compare", a.path, b.path, a.path])
      expect(code).to eq(2)
      expect(err).to include("usage: sloplint-judge compare")
    end

    it "compares two files, mapping the answer back through the random swap" do
      backend = FakeBackend.new { |state, _n, q| q["type"] == "choice" ? [{ "A" => 0.2, "B" => 0.8 }, 0.9] : [0.1, 0.9] }
      allow(Sloplint::Judge::Backend).to receive(:load).and_return(backend)
      a = Tempfile.new("a"); a.write("Old."); a.close
      b = Tempfile.new("b"); b.write("New."); b.close
      code, out, err = run(Sloplint::Judge::CLI, ["compare", "--drift", a.path, b.path])
      expect(code).to eq(0)
      v = JSON.parse(out)
      expect(v.keys).to eq(%w[keep p_keep_b keep_confidence drift drift_confidence])
      expect(err).to include("fake, 100 input_tokens")
      sent = backend.calls.first.first
      expect(v["keep"]).to eq(sent["B"] == "New." ? "B" : "A")
    end
  end
end
