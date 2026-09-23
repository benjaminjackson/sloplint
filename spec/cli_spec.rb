# frozen_string_literal: true

require "stringio"
require "tempfile"
require "English"
require "rbconfig"

RSpec.describe Sloplint::CLI do
  def run(argv, stdin_text: "")
    out = StringIO.new
    err = StringIO.new
    stdin = StringIO.new(stdin_text)
    def stdin.tty? = false
    code = described_class.run(argv, out:, err:, stdin:)
    [code, out.string, err.string]
  end

  describe "exit codes" do
    it "returns 0 when there are no notes" do
      code, = run(["check", "-"], stdin_text: "The meeting is at noon.")
      expect(code).to eq(0)
    end

    it "returns 1 when notes are found" do
      code, = run(["check", "-"], stdin_text: "That's the whole point.")
      expect(code).to eq(1)
    end

    # Taken and dropped, these two read as a judge run nobody asked for: the
    # regex rules run, the reader named on the command line is never used,
    # and the output says nothing about either.
    it "returns 2 for a flag that only means something with --judge" do
      [["--register", "a lawyer"], ["--backend", "jev"]].each do |flag, value|
        code, out, err = run(["check", flag, value, "-"], stdin_text: "The meeting is at noon.")
        expect([code, out]).to eq([2, ""])
        expect(err).to include("#{flag} needs --judge")
      end
    end

    it "returns 2 on an unknown command, which reads as a missing file" do
      code, _out, err = run(["frobnicate"])
      expect(code).to eq(2)
      expect(err).to include("no such file: frobnicate")
    end

    it "treats a bare \"-\" as `check -`" do
      code, out, = run(["-"], stdin_text: "That's the whole point.")
      expect(code).to eq(1)
      expect(out).to include("thats-the-whole")
    end

    it "treats a bare path as `check PATH`" do
      Tempfile.create(["doc", ".md"]) do |f|
        f.write("That's the whole point.")
        f.flush
        code, out, = run([f.path])
        expect(code).to eq(1)
        expect(out).to include("thats-the-whole")
      end
    end

    it "returns 2 on a missing file" do
      code, = run(["check", "/no/such/file.md"])
      expect(code).to eq(2)
    end

    it "returns 2 on a bad output format" do
      code, = run(["-o", "yaml", "check", "-"], stdin_text: "hi")
      expect(code).to eq(2)
    end

    it "returns 2 on empty stdin rather than calling a scan of nothing clean" do
      code, out, err = run(["check", "-"], stdin_text: "")
      expect(code).to eq(2)
      expect(out).to be_empty
      expect(err).to include("empty input")
      expect(err).to include("stdin")
    end

    it "returns 2 on whitespace-only stdin" do
      code, _out, err = run(["check", "-"], stdin_text: "  \n\t\n")
      expect(code).to eq(2)
      expect(err).to include("empty input")
    end

    it "returns 2 on an empty named file, naming it" do
      Tempfile.create(["doc", ".md"]) do |f|
        f.close
        code, _out, err = run(["check", f.path])
        expect(code).to eq(2)
        expect(err).to include(f.path)
      end
    end

    it "still returns 0 for a file that is only a fenced code block under --markdown" do
      # The empty check reads the raw text, before --markdown blanks code and
      # URLs. This file arrived; it just has no prose in it.
      Tempfile.create(["doc", ".md"]) do |f|
        f.write("```ruby\nputs \"that's the whole point\"\n```\n")
        f.close
        code, = run(["check", "--markdown", f.path])
        expect(code).to eq(0)
      end
    end

    it "scans an em dash under a locale-less environment" do
      # Cowork's sandbox sets no LANG, so Ruby's default external encoding is
      # US-ASCII and every read of ordinary prose used to die on the first
      # non-ASCII character. Spawned rather than called in-process: nothing
      # short of a real environment reproduces it.
      Tempfile.create(["doc", ".md"]) do |f|
        f.write("A sentence — with an em dash.\n")
        f.close
        exe = File.expand_path("../exe/sloplint", __dir__)
        out = IO.popen({ "LC_ALL" => "C", "LANG" => "C" },
                       [RbConfig.ruby, exe, "check", "-o", "json", f.path], &:read)
        expect($CHILD_STATUS.exitstatus).to eq(1)
        expect(out).to include("em-dash")
      end
    end

    it "returns 2 on invalid UTF-8 input, not the 'notes found' code" do
      bad_bytes = "That is the whole point. \xFF\xFE bad bytes\n"
      code, _out, err = run(["check", "-"], stdin_text: bad_bytes)
      expect(code).to eq(2)
      expect(err).to include("invalid")
    end

    it "returns 2 on an unknown --select id instead of silently matching nothing" do
      code, out, err = run(["check", "--select", "no-such-rule", "-"], stdin_text: "hi")
      expect(code).to eq(2)
      expect(out).to be_empty
      expect(err).to include("no-such-rule")
    end

    it "returns 2 on an unknown --ignore id" do
      code, _out, err = run(["check", "--ignore", "no-such-rule", "-"], stdin_text: "hi")
      expect(code).to eq(2)
      expect(err).to include("no-such-rule")
    end
  end

  describe "stdin" do
    it "reads stdin when no paths are given" do
      code, out = run(["check"], stdin_text: "You already know the answer.")
      expect(code).to eq(1)
      expect(out).to include("you-already-know")
    end
  end

  describe "full output" do
    it "prints the rule's rationale on a 'why:' line, without needing a separate explain call" do
      _, out = run(["check", "-"], stdin_text: "That's the whole point.")
      rule = Sloplint::RULES.find { |r| r.id == "thats-the-whole" }
      expect(out).to include("why: #{rule.rationale}")
    end
  end

  describe "-o json" do
    it "emits a parseable array matching the note schema" do
      _, out = run(["-o", "json", "check", "-"], stdin_text: "No fluff, no filler, no jargon.")
      data = JSON.parse(out)
      expect(data).to be_an(Array)
      note = data.first
      expect(note.keys).to include("path", "line", "column", "severity", "confidence", "rule", "category", "message", "excerpt", "context", "rationale", "suggestion")
      expect(note["rule"]).to eq("no-x-no-y")
      expect(note["count"]).to eq(3)
      expect(note["line"]).to eq(1)
      expect(note["column"]).to eq(1)
    end

    it "omits count when the rule does not count" do
      _, out = run(["-o", "json", "check", "-"], stdin_text: "That's the whole point.")
      note = JSON.parse(out).first
      expect(note).not_to have_key("count")
    end

    it "carries the rule's rationale" do
      _, out = run(["-o", "json", "check", "-"], stdin_text: "That's the whole point.")
      note = JSON.parse(out).first
      rule = Sloplint::RULES.find { |r| r.id == "thats-the-whole" }
      expect(note["rationale"]).to eq(rule.rationale)
    end

    # severity and confidence are two separate axes now: what the construct
    # costs the prose, and how likely the match is a false positive. An agent
    # needs both on the note to weigh a flag.
    it "carries the rule's confidence alongside its severity" do
      _, out = run(["-o", "json", "check", "-"], stdin_text: "That's the whole point.")
      note = JSON.parse(out).first
      rule = Sloplint::RULES.find { |r| r.id == "thats-the-whole" }
      expect(note["severity"]).to eq(rule.severity)
      expect(note["confidence"]).to eq(rule.confidence)
    end

    describe "multiple files" do
      # by_path grouping in cmd_check only kicks in when more than one
      # non-"-" path is given -- a single-file check still returns a flat
      # array, and this is the one place that distinction is tested.
      def write_temp(basename, content)
        file = Tempfile.create([basename, ".md"])
        file.write(content)
        file.close
        file.path
      end

      it "groups notes by path, keyed by each file's own path" do
        a = write_temp("a", "That's the whole point.")
        b = write_temp("b", "You already know it.")

        _, out = run(["-o", "json", "check", a, b])
        data = JSON.parse(out)

        expect(data.keys).to contain_exactly(a, b)
        expect(data[a].map { |n| n["rule"] }).to eq(["thats-the-whole"])
        expect(data[b].map { |n| n["rule"] }).to eq(["you-already-know"])
      ensure
        File.unlink(a, b)
      end

      it "returns a flat array, not grouped, for a single file" do
        a = write_temp("a", "That's the whole point.")

        _, out = run(["-o", "json", "check", a])
        data = JSON.parse(out)

        expect(data).to be_an(Array)
        expect(data.first["rule"]).to eq("thats-the-whole")
      ensure
        File.unlink(a)
      end
    end
  end

  describe "--select / --ignore" do
    it "runs only the selected rule" do
      _, out = run(["-o", "json", "check", "--select", "you-already-know", "-"],
                   stdin_text: "You already know. That's the whole point.")
      rules = JSON.parse(out).map { |n| n["rule"] }
      expect(rules).to eq(["you-already-know"])
    end

    it "selects by category" do
      _, out = run(["-o", "json", "check", "--select", "false-concession", "-"],
                   stdin_text: "Some critics argue this. That's the whole point.")
      rules = JSON.parse(out).map { |n| n["rule"] }.uniq
      expect(rules).to eq(["vague-attribution"])
    end

    it "ignores a rule" do
      _, out = run(["-o", "json", "check", "--ignore", "thats-the-whole", "-"],
                   stdin_text: "That's the whole point. You already know it.")
      rules = JSON.parse(out).map { |n| n["rule"] }
      expect(rules).not_to include("thats-the-whole")
      expect(rules).to include("you-already-know")
    end

    it "runs off-by-default rules only when selected" do
      text = "It was fast, cheap, and simple."
      _, default_out = run(["-o", "json", "check", "-"], stdin_text: text)
      expect(JSON.parse(default_out).map { |n| n["rule"] }).not_to include("rule-of-three")

      _, selected_out = run(["-o", "json", "check", "--select", "rule-of-three", "-"], stdin_text: text)
      expect(JSON.parse(selected_out).map { |n| n["rule"] }).to include("rule-of-three")
    end

    it "selecting a category runs only that category's default-on rules, not rule-of-three" do
      text = "It was fast, cheap, and simple."
      _, out = run(["-o", "json", "check", "--select", "cadence", "-"], stdin_text: text)
      expect(JSON.parse(out).map { |n| n["rule"] }).not_to include("rule-of-three")
    end

    it "selecting rule-of-three by id runs it even though its category is not fully selected" do
      text = "It was fast, cheap, and simple."
      _, out = run(["-o", "json", "check", "--select", "rule-of-three", "-"], stdin_text: text)
      expect(JSON.parse(out).map { |n| n["rule"] }).to include("rule-of-three")
    end
  end

  describe "--strict" do
    it "runs the off-by-default rules" do
      _, out = run(["-o", "json", "check", "--strict", "-"], stdin_text: "It was fast, cheap, and simple.")
      expect(JSON.parse(out).map { |n| n["rule"] }).to include("rule-of-three")
    end

    it "still honours --ignore" do
      _, out = run(["-o", "json", "check", "--strict", "--ignore", "rule-of-three", "-"],
                   stdin_text: "It was fast, cheap, and simple.")
      expect(JSON.parse(out).map { |n| n["rule"] }).not_to include("rule-of-three")
    end

    it "with --select and a category, includes the category's off-by-default rules too" do
      _, out = run(["-o", "json", "check", "--strict", "--select", "cadence", "-"],
                   stdin_text: "It was fast, cheap, and simple.")
      expect(JSON.parse(out).map { |n| n["rule"] }).to include("rule-of-three")
    end
  end

  describe "check options before the command word" do
    it "accepts --strict without `check`, since check is the default" do
      _, out = run(["-o", "json", "--strict", "-"], stdin_text: "It was fast, cheap, and simple.")
      expect(JSON.parse(out).map { |n| n["rule"] }).to include("rule-of-three")
    end

    it "accepts --markdown with a value-taking option after it" do
      text = "<!--\nIt isn't a budget, it's a ceiling.\n-->\nIt was fast, cheap, and simple."
      code, out = run(["--markdown", "--select", "rule-of-three", "-o", "json", "-"], stdin_text: text)
      expect(code).to eq(1)
      expect(JSON.parse(out).map { |n| n["rule"] }).to eq(["rule-of-three"])
    end

    it "still rejects an option nobody knows" do
      code, _, err = run(["--bogus", "-"], stdin_text: "Fine.")
      expect(code).to eq(2)
      expect(err).to include("invalid option: --bogus")
    end
  end

  describe "--markdown" do
    it "skips HTML comments" do
      text = "Fine sentence.\n\n<!--\nIt isn't a budget, it's a ceiling.\n-->\n\nAnother fine sentence."
      code, out = run(["check", "--markdown", "-"], stdin_text: text)
      expect(code).to eq(0)
      expect(out).not_to include("isnt-x-its-y")
    end

    it "skips fenced and inline code" do
      text = "Here is code:\n\n```\nThat's the whole point.\n```\n\nUse `you already know` as a var."
      code, out = run(["check", "--markdown", "-"], stdin_text: text)
      expect(code).to eq(0)
      expect(out).to be_empty
    end

    it "still flags prose outside code" do
      text = "That's the whole point.\n\n```\nsit with that\n```"
      code, out = run(["check", "--markdown", "-"], stdin_text: text)
      expect(code).to eq(1)
      expect(out).to include("thats-the-whole")
      expect(out).not_to include("sit-with-that")
    end
  end

  describe "rules / explain / version" do
    it "lists the catalog" do
      code, out = run(["rules"])
      expect(code).to eq(0)
      expect(out).to include("no-x-no-y")
      expect(out).to include("[off by default]")
    end

    it "dumps the catalog as json" do
      _, out = run(["rules", "--json"])
      data = JSON.parse(out)
      expect(data.map { |r| r["id"] }).to include("rich-tapestry")
    end

    it "carries each rule's rationale in the json catalog" do
      _, out = run(["rules", "--json"])
      data = JSON.parse(out)
      rule = Sloplint::RULES.find { |r| r.id == "rich-tapestry" }
      expect(data.find { |r| r["id"] == "rich-tapestry" }["rationale"]).to eq(rule.rationale)
    end

    # The catalog used to carry a boolean saying whether a rule ran by default.
    # Confidence replaces it: "low" is what keeps a rule out of the default run.
    it "reports confidence in the json catalog, and nothing else about the default run" do
      _, out = run(["rules", "--json"])
      entry = JSON.parse(out).find { |r| r["id"] == "rule-of-three" }
      expect(entry["confidence"]).to eq("low")
      expect(entry.keys).to contain_exactly("id", "category", "severity", "confidence",
                                            "message", "rationale", "suggestion")
    end

    it "shows a confidence column in the text listing" do
      _, out = run(["rules"])
      expect(out).to match(/^rule-of-three\s+cadence\s+info\s+low\s+/)
      expect(out).to match(/^rich-tapestry\s+puffery\s+error\s+high\s+/)
    end

    it "names the confidence when it explains a rule" do
      _, out = run(["explain", "rule-of-three"])
      expect(out).to include("(cadence, info, low confidence, off by default)")
    end

    it "explains a rule" do
      code, out = run(["explain", "no-x-no-y"])
      expect(code).to eq(0)
      expect(out).to include("Why:")
      expect(out).to include("No fluff, no filler, no jargon.")
    end

    it "errors on an unknown rule id" do
      code, = run(["explain", "no-such-rule"])
      expect(code).to eq(2)
    end

    it "prints the version" do
      code, out = run(["version"])
      expect(code).to eq(0)
      expect(out.strip).to eq(Sloplint::VERSION)
    end

    # -h/--help used to write to the real $stdout via bare `puts` and call
    # Kernel#exit directly, bypassing the out:/return-a-code contract every
    # other path honors -- untestable through this run() seam, which is
    # exactly how it shipped unnoticed. Now it writes to the injected `out:`
    # and returns 0 like everything else.
    it "-h writes to the injected out stream and returns 0, not exit" do
      code, out = run(["-h"])
      expect(code).to eq(0)
      expect(out).to include("Recommended for agents")
    end

    it "--help tells an agent to run status and ask before --judge, or how to install the judge" do
      _, out = run(["--help"])
      expect(out).to include("sloplint-judge status").and include("ask")
      allow($LOAD_PATH).to receive(:resolve_feature_path).and_return(nil)
      allow(Gem::Specification).to receive(:find_all_by_name).and_call_original
      # Installed as a gem, the judge is off the load path until RubyGems
      # activates it. That is installed, and the recipe must say so.
      judge_gem = ->(requirement) { Gem::Specification.new("sloplint-judge", "9.9.9") { |g| g.add_dependency("sloplint", requirement) } }
      allow(Gem::Specification).to receive(:find_all_by_name).with("sloplint-judge").and_return([judge_gem.call(Sloplint::VERSION)])
      _, out = run(["--help"])
      expect(out).to include("sloplint-judge status")
      # A gem that asks for another sloplint cannot be required beside this
      # one, so the recipe must not send the agent to --judge.
      allow(Gem::Specification).to receive(:find_all_by_name).with("sloplint-judge").and_return([judge_gem.call("= 0.0.1")])
      _, out = run(["--help"])
      expect(out).to include("not installed here")
      expect(out).not_to include("sloplint-judge status")
      allow(Gem::Specification).to receive(:find_all_by_name).with("sloplint-judge").and_return([])
      _, out = run(["--help"])
      expect(out).to include("not installed here").and include("gem install sloplint-judge")
      expect(out).not_to include("sloplint-judge status")
    end

    # The recipe asks RubyGems whether the judge is installed, which scans
    # every installed gem. A check has no use for it.
    it "builds the help banner only when help is asked for" do
      expect(Sloplint::CLI).not_to receive(:judge_recipe)
      run(["check", "-"], stdin_text: "Plain prose here.\n")
    end

    it "--help behaves the same as -h" do
      code, out = run(["--help"])
      expect(code).to eq(0)
      expect(out).to include("Recommended for agents")
    end

    it "--help lists count among the note keys" do
      _, out = run(["--help"])
      expect(out).to include("count")
    end

    # optparse auto-registers a built-in "--version" switch (Officious) on any
    # parser unless one is explicitly defined; that default prints its own
    # "version unknown" text to the real $stdout and calls Kernel#exit,
    # bypassing our out:/return-a-code contract entirely -- so it shipped
    # broken and untested, same shape as the -h/--help bug above.
    it "-v/--version prints the version and returns 0, not exit" do
      code, out = run(["-v"])
      expect(code).to eq(0)
      expect(out.strip).to eq(Sloplint::VERSION)

      code, out = run(["--version"])
      expect(code).to eq(0)
      expect(out.strip).to eq(Sloplint::VERSION)
    end
  end

  # README.md quotes a sample note and a sample check run. Nothing regenerates
  # either one, so a change to a rule's rationale or to the human-readable
  # output format goes stale in the README the moment it ships. Pin both.
  describe "the README examples" do
    readme = File.read(File.expand_path("../README.md", __dir__), encoding: "UTF-8")

    it "quotes the current no-x-no-y rationale in its sample JSON note" do
      json_block = readme[/^## The note\n.*?```json\n(\{.*?\})\n```/m, 1]
      note = JSON.parse(json_block)
      rule = Sloplint::RULES.find { |r| r.id == "no-x-no-y" }
      expect(note["rationale"]).to eq(rule.rationale)
    end

    it "shows the real output for its sample check run" do
      match = readme.match(/```\n\$ printf '(.*?)' \| sloplint check -\n(.*?)```/m)
      raise "sample check block not found in README" unless match

      input = match[1].gsub('\n', "\n")
      expected_output = match[2]

      code, out = run(["check", "-"], stdin_text: input)
      expect(code).to eq(1)
      expect(out).to eq(expected_output)
    end
  end

  describe "slop fixture integration" do
    it "flags a known set of rules" do
      fixture = File.join(__dir__, "fixtures", "slop.md")
      code, out = run(["-o", "json", "check", "--markdown", fixture])
      expect(code).to eq(1)
      rules = JSON.parse(out).map { |n| n["rule"] }.uniq
      expect(rules).to include(
        "puffery-words", "rich-tapestry", "vital-role",
        "no-x-no-y", "thats-the-whole", "you-already-know",
        "vague-attribution", "not-just-x-but-y"
      )
    end
  end
end
