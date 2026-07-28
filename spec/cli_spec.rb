# frozen_string_literal: true

require "stringio"
require "tempfile"

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

    it "returns 2 on an unknown command" do
      code, = run(["frobnicate"])
      expect(code).to eq(2)
    end

    it "returns 2 on a missing file" do
      code, = run(["check", "/no/such/file.md"])
      expect(code).to eq(2)
    end

    it "returns 2 on a bad output format" do
      code, = run(["-o", "yaml", "check", "-"], stdin_text: "hi")
      expect(code).to eq(2)
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

  describe "-o json" do
    it "emits a parseable array matching the note schema" do
      _, out = run(["-o", "json", "check", "-"], stdin_text: "No fluff, no filler, no jargon.")
      data = JSON.parse(out)
      expect(data).to be_an(Array)
      note = data.first
      expect(note.keys).to include("path", "line", "column", "severity", "rule", "category", "message", "excerpt", "context", "suggestion")
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
      _, out = run(["-o", "json", "check", "--select", "hedging", "-"],
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
  end

  describe "--markdown" do
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

    it "--help behaves the same as -h" do
      code, out = run(["--help"])
      expect(code).to eq(0)
      expect(out).to include("Recommended for agents")
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
