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

  it "writes the judge wrapper under --judge even when no judge rule ran, and reads no key" do
    # Nothing is asked, so nothing is built: a machine with no key runs this.
    expect(Sloplint::Judge::Backend).not_to receive(:load)
    code, out, err = run(Sloplint::CLI, ["check", "--judge", "--select", "em-dash", "-o", "json", "-"], stdin_text: text)
    expect(code).to eq(0)
    doc = JSON.parse(out)
    expect(doc["notes"]).to eq([])
    # The same identifier a run reports, which is the model: the field does
    # not change meaning because no question was asked. The same keys too,
    # cost_usd among them, so a reader of the JSON finds the price where a
    # real run puts it and does not have to tell the two shapes apart.
    expect(doc["judge"]).to eq("backend" => "jev-latest", "requests" => 0, "cost_usd" => 0.0)
    expect(err).to include("judge jev-latest, 0 requests, $0.000000")
  end

  it "names the model from SYSTEMONE_MODEL when no judge rule ran, as a run would" do
    saved = ENV["SYSTEMONE_MODEL"]
    ENV["SYSTEMONE_MODEL"] = "jev-2"
    code, out, = run(Sloplint::CLI, ["check", "--judge", "--select", "em-dash", "-o", "json", "-"], stdin_text: text)
    expect(code).to eq(0)
    expect(JSON.parse(out)["judge"]).to eq("backend" => "jev-2", "requests" => 0, "cost_usd" => 0.0)
  ensure
    ENV["SYSTEMONE_MODEL"] = saved
  end

  it "exits 2 on an unknown --backend even when no judge rule ran" do
    code, _, err = run(Sloplint::CLI, ["check", "--judge", "--backend", "nope", "--select", "em-dash", "-"], stdin_text: text)
    expect(code).to eq(2)
    expect(err).to include("unknown backend: nope")
  end

  # The same decision in `sloplint-judge check`: nothing to ask is settled
  # before a backend exists, because building one reads the key.
  it "asks nothing and builds no backend when the selection holds no rule" do
    expect(Sloplint::Judge::Backend).not_to receive(:load)
    args = ["check", "--select", "wrap-up", "--ignore", "wrap-up", "-o", "json", "-"]
    code, out, err = run(Sloplint::Judge::CLI, args, stdin_text: text)
    expect(code).to eq(0)
    doc = JSON.parse(out)
    expect(doc["notes"]).to eq([])
    expect(doc["judge"]).to eq("backend" => "jev-latest", "requests" => 0, "cost_usd" => 0.0)
    expect(err).to include("sloplint-judge jev-latest, 0 requests, $0.000000")
    # And an unknown backend is still a usage error on that path.
    code, _, err = run(Sloplint::Judge::CLI, ["check", "--backend", "nope", "--select", "wrap-up", "--ignore", "wrap-up", "-"], stdin_text: text)
    expect(code).to eq(2)
    expect(err).to include("unknown backend: nope")
  end

  it "reads a flag written after the path" do
    file = Tempfile.new(["draft", ".md"]); file.write(text); file.close
    code, out, = run(Sloplint::CLI, ["check", file.path, "--judge", "-o", "json"])
    expect(code).to eq(1)
    expect(JSON.parse(out)["judge"]).to include("backend" => "fake")
    code, _, err = run(Sloplint::Judge::CLI, ["check", file.path, "--markdown"])
    expect(code).to eq(1)
    expect(err).not_to include("no such file")
  end

  it "accepts judge ids in --select and --ignore only with --judge" do
    code, out, = run(Sloplint::CLI, ["check", "--judge", "--select", "wrap-up", "-o", "json", "-"], stdin_text: text)
    expect(code).to eq(1)
    expect(JSON.parse(out)["notes"].map { |n| n["rule"] }).to eq(["wrap-up"])
    code, _, err = run(Sloplint::CLI, ["check", "--select", "wrap-up", "-"], stdin_text: text)
    expect(code).to eq(2)
    expect(err).to include("unknown rule or category: wrap-up")
    # Without --judge the judge's catalog is not in play, so one list is the
    # right list.
    expect(err).to include("run `sloplint rules` to list them")
    # With it, a mistyped judge id is in neither list the other hint names:
    # `sloplint rules` never prints the judge's rules.
    code, _, err = run(Sloplint::CLI, ["check", "--judge", "--select", "wrap-upp", "-"], stdin_text: text)
    expect(code).to eq(2)
    expect(err).to include("run `sloplint rules` and `sloplint-judge rules` to list them")
  end

  # A missing key is known before a word is read, and a scan of every file
  # that is then thrown away to print that message is work nobody asked for.
  it "does not run the regex scan when the judge cannot be built" do
    allow(Sloplint::Judge::Backend).to receive(:load).and_raise(ArgumentError, "TYPESAFE_API_KEY is not set")
    expect(Sloplint::Engine).not_to receive(:scan)
    code, out, err = run(Sloplint::CLI, ["check", "--judge", "-"], stdin_text: text)
    expect([code, out]).to eq([2, ""])
    expect(err).to include("TYPESAFE_API_KEY is not set")
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

  # An installed judge that asks for another sloplint: RubyGems refuses to
  # activate it, and the reader gets the install hint, not a backtrace.
  it "exits 2 with the same hint when the installed judge conflicts with this sloplint" do
    conflict = Gem::ConflictError.new(Gem::Specification.new("sloplint-judge", "9.9.9"), [])
    allow(Sloplint::CLI).to receive(:require).and_raise(conflict)
    code, out, err = run(Sloplint::CLI, ["check", "--judge", "-"], stdin_text: text)
    expect([code, out]).to eq([2, ""])
    expect(err).to include("gem install sloplint-judge")
  end

  # No version of the installed judge fits this sloplint. RubyGems raises a
  # Gem::LoadError with no path, like the conflict above, and the reader gets
  # the same hint `--help` gives: the judge is not installed here.
  it "exits 2 with the same hint when no installed judge fits this sloplint" do
    [Gem::MissingSpecVersionError.new("sloplint-judge", Gem::Requirement.new("~> 0.9"), [Gem::Specification.new("sloplint-judge", "9.9.9")]),
     Gem::MissingSpecError.new("sloplint-judge", Gem::Requirement.new("~> 0.9"))].each do |error|
      allow(Sloplint::CLI).to receive(:require).and_raise(error)
      code, out, err = run(Sloplint::CLI, ["check", "--judge", "-"], stdin_text: text)
      expect([code, out]).to eq([2, ""])
      expect(err).to include("gem install sloplint-judge")
    end
  end

  # An ArgumentError raised while the run is under way is a bug in this code,
  # not a file with bad bytes in it. Reported as invalid input, the reader
  # goes looking through a file that is fine, and the requests are paid for
  # either way.
  it "does not call a failure during the run invalid input" do
    backend = Class.new do
      def name = "fake"
      def ask(*) = raise(ArgumentError, "a stray % in an instruction")
    end.new
    allow(Sloplint::Judge::Backend).to receive(:load).and_return(backend)
    expect { run(Sloplint::Judge::CLI, ["check", "-"], stdin_text: text) }
      .to raise_error(ArgumentError, /stray %/)
    expect { run(Sloplint::CLI, ["check", "--judge", "-"], stdin_text: text) }
      .to raise_error(ArgumentError, /stray %/)
  end

  # A document the judge never asked a question about is not a clean
  # document. Exit 0 would say the judge read it and found nothing.
  it "exits 2 when no prose reached the judge" do
    backend = FakeBackend.new
    allow(Sloplint::Judge::Backend).to receive(:load).and_return(backend)
    furniture = "# A heading\n\n- A bullet\n- Another bullet\n\n| a | b |\n| - | - |\n\n```\ncode()\n```\n"
    code, out, err = run(Sloplint::Judge::CLI, ["check", "--markdown", "-"], stdin_text: furniture)
    expect(code).to eq(2)
    expect(out).to eq("")
    expect(err).to include("nothing examined in stdin").and include("Markdown furniture")
    expect(backend.calls).to be_empty
    # The same document without --markdown is prose, and the judge reads it.
    code, = run(Sloplint::Judge::CLI, ["check", "-"], stdin_text: furniture)
    expect(code).not_to eq(2)
    expect(backend.calls).not_to be_empty
  end

  it "exits 2, not 3, when the backend is not configured or not known" do
    allow(Sloplint::Judge::Backend).to receive(:load).and_raise(ArgumentError, "TYPESAFE_API_KEY is not set")
    code, out, err = run(Sloplint::CLI, ["check", "--judge", "-"], stdin_text: text)
    expect([code, out]).to eq([2, ""])
    expect(err).to include("TYPESAFE_API_KEY is not set")
  end

  # Backend.klass requires the adapter when a command needs one, so the
  # commands that need none must not drag an HTTP stack in behind them. In a
  # fresh process, because this one has loaded the adapter long ago.
  it "prints the rules without loading an HTTP stack" do
    script = <<~RUBY
      require "stringio"
      require "sloplint/judge/cli"
      Sloplint::Judge::CLI.run(["rules"], out: StringIO.new)
      puts $LOADED_FEATURES.grep(%r{/(net/http|openssl)}).size
    RUBY
    out = IO.popen([RbConfig.ruby, "-I#{File.expand_path("../../lib", __dir__)}", "-e", script], &:read)
    expect(out.strip).to eq("0")
  end

  it "--help leads with status, the ask, and the output shape" do
    code, out, = run(Sloplint::Judge::CLI, ["--help"])
    expect(code).to eq(0)
    expect(out).to include("sloplint-judge status").and include("ask the person").and include('"judge"')
  end

  # --strict multiplies the paid requests. The help says so on both paths,
  # because the person choosing the flag is the one paying. Both `check`
  # parsers answer -h themselves, on the out they were given and with a
  # return code; OptionParser's own -h prints on the real stdout and ends the
  # process, which here would end the spec run.
  it "says what --strict turns on and what it costs, in both check parsers" do
    # The whole entry, however many lines it is wrapped over: the flag line
    # and every line after it that does not start another flag.
    entry = lambda do |help|
      lines = help.lines.drop_while { |l| !l.include?("--strict") }
      lines.take_while.with_index { |l, i| i.zero? || !l.match?(/\A\s*-/) }.join(" ").gsub(/\s+/, " ")
    end
    code, out, = run(Sloplint::Judge::CLI, ["check", "--help"])
    expect(code).to eq(0)
    # Three things, not two: the rules that are off by default are part of
    # what the flag turns on, and the cost is what the person pays for it.
    expect(entry.call(out)).to include("off by default").and include("every sentence").and include("three times the requests")
    code, out, = run(Sloplint::CLI, ["check", "--help"])
    expect(code).to eq(0)
    expect(entry.call(out)).to include("off by default").and include("with --judge").and include("three times the requests")
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

    # The same read `check` does. Left to the backend, a file that is not
    # valid UTF-8 was a JSON error inside the request, after the key had
    # already been sent.
    it "refuses a file that is not valid UTF-8, before it pays for a request" do
      backend = FakeBackend.new
      allow(Sloplint::Judge::Backend).to receive(:load).and_return(backend)
      a = Tempfile.new("a"); a.binmode; a.write("Caf\xE9 is open.".b); a.close
      b = Tempfile.new("b"); b.write("New."); b.close
      code, _, err = run(Sloplint::Judge::CLI, ["compare", a.path, b.path])
      expect(code).to eq(2)
      expect(err).to include("invalid input").and include("not valid UTF-8")
      expect(backend.calls).to be_empty
    end

    # The verdict is printed and paid for by the time the usage line is
    # built, so a count that is not a number must not take the command down
    # with it -- the same guard a scan applies.
    it "steps over a usage count that is not a number" do
      priced = Class.new(FakeBackend) do
        def cost_usd(usage) = usage.fetch("input_tokens", 0) * 0.001
      end
      backend = priced.new(usage: { "input_tokens" => "3", "trace" => { "id" => "x" } }) do |_s, _n, q|
        q["type"] == "choice" ? [{ "A" => 0.2, "B" => 0.8 }, 0.9] : [0.1, 0.9]
      end
      allow(Sloplint::Judge::Backend).to receive(:load).and_return(backend)
      a = Tempfile.new("a"); a.write("Old."); a.close
      b = Tempfile.new("b"); b.write("New."); b.close
      code, out, err = run(Sloplint::Judge::CLI, ["compare", a.path, b.path])
      expect(code).to eq(0)
      expect(JSON.parse(out)["keep"]).not_to be_nil
      expect(err).to include("fake").and include("$0.000000")
      expect(err).not_to include("trace")
    end
  end

  it "compare -h prints its help to the given out and returns 0" do
    out = StringIO.new
    code = Sloplint::Judge::CLI.run(%w[compare -h], out: out, err: StringIO.new, stdin: StringIO.new)
    expect(code).to eq(0)
    expect(out.string).to include("usage: sloplint-judge compare")
  end

end
