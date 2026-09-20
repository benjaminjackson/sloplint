# frozen_string_literal: true

require "optparse"
require "json"
require "sloplint/judge"
require "sloplint/judge/backends/jev"

module Sloplint
  module Judge
    # The judge's own executable: judge-only check, compare, rules, explain.
    # Exit codes are sloplint's plus 3 for a backend failure. See docs/JUDGE.md.
    module CLI
      module_function

      def run(argv, out: $stdout, err: $stderr, stdin: $stdin)
        opts = { format: "full", register: Engine::DEFAULT_REGISTER }
        parser = global_parser(opts, out:)
        begin
          parser.order!(argv)
        rescue OptionParser::InvalidOption => e
          argv.unshift("check", *e.args)
        end
        return 0 if opts[:help_shown] || opts[:version_shown]

        command = argv.shift
        command ||= (stdin.tty? ? "help" : "check")
        case command
        when "check"   then cmd_check(argv, opts, out:, err:, stdin:)
        when "compare" then cmd_compare(argv, opts, out:, err:)
        when "rules"   then cmd_rules(argv, out:)
        when "explain" then cmd_explain(argv, out:, err:)
        when "status"  then cmd_status(opts, out:, err:)
        when "key"     then cmd_key(argv, opts, out:, err:, stdin:)
        when "version" then out.puts(VERSION); 0
        when "help"    then out.puts(parser.help); 0
        else cmd_check(argv.unshift(command), opts, out:, err:, stdin:)
        end
      rescue OptionParser::ParseError => e
        err.puts("sloplint-judge: #{e.message}")
        2
      rescue BackendError => e
        err.puts("sloplint-judge: backend failure: #{e.message}")
        3
      end

      # ── check ───────────────────────────────────────────────────────────────
      def cmd_check(argv, opts, out:, err:, stdin:)
        markdown = false
        strict = false
        select = nil
        ignore = nil
        OptionParser.new do |o|
          o.banner = "usage: sloplint-judge check [options] [paths...]  (\"-\" or no paths = stdin)"
          o.on("-o", "--output-format FORMAT", %w[full json], "Output format: 'full' or 'json' (default: full).") { |v| opts[:format] = v }
          o.on("--markdown", "Skip fenced/inline code spans, HTML comments, URLs and Markdown furniture.") { markdown = true }
          o.on("--select IDS", "Only run these rules (comma-separated rule ids or categories).") { |v| select = v.split(",").map(&:strip) }
          o.on("--ignore IDS", "Skip these rules (comma-separated rule ids or categories).") { |v| ignore = v.split(",").map(&:strip) }
          o.on("--strict", "Run sentence rules on every sentence and keep low-confidence notes.") { strict = true }
          o.on("--register TEXT", "Who the reader is.") { |v| opts[:register] = v }
          o.on("--backend NAME", "Which adapter to use.") { |v| opts[:backend] = v }
        # permute!, so a flag written after the path is a flag: `sloplint-judge
        # check draft.md --markdown` reads the way anyone would write it.
        end.permute!(argv)

        unknown = Sloplint::CLI.unknown_rule_refs(select, RULES) + Sloplint::CLI.unknown_rule_refs(ignore, RULES)
        unless unknown.empty?
          err.puts("sloplint-judge: unknown rule or category: #{unknown.join(", ")}")
          err.puts("run `sloplint-judge rules` to list them.")
          return 2
        end
        rules = Sloplint::CLI.select_rules(select, ignore, strict, RULES)

        sources = Sloplint::CLI.read_sources(argv.empty? ? ["-"] : argv, err:, stdin:, name: "sloplint-judge")
        return 2 unless sources

        backend = load_backend(opts[:backend], err:) or return 2
        result = Engine.scan_sources(sources, name: "sloplint-judge", err:, rules:, backend:, markdown:, register: opts[:register], strict:)
        Sloplint::CLI.emit(result.notes, opts[:format], out:, by_path: sources.count { |label, _| label != "-" } > 1, judge: result.usage)
        result.notes.empty? ? 0 : 1
      rescue ArgumentError, Encoding::CompatibilityError => e
        err.puts("sloplint-judge: invalid input: #{e.message}")
        2
      end

      # ── compare A B ─────────────────────────────────────────────────────────
      def cmd_compare(argv, opts, out:, err:)
        drift = false
        OptionParser.new do |o|
          o.banner = "usage: sloplint-judge compare [--drift] A B  (two files)"
          o.on("--drift", "Also ask whether B changes what A says.") { drift = true }
          o.on("--register TEXT", "Who the reader is.") { |v| opts[:register] = v }
          o.on("--backend NAME", "Which adapter to use.") { |v| opts[:backend] = v }
        # permute!, so `compare A B --drift` sees the flag. There is no nested
        # subcommand here whose own flags an option after the files could be.
        end.permute!(argv)
        a, b = argv
        unless argv.size == 2 && File.file?(a) && File.file?(b)
          err.puts("usage: sloplint-judge compare [--drift] A B")
          return 2
        end
        backend = load_backend(opts[:backend], err:) or return 2
        verdict = Compare.run(File.read(a, encoding: Encoding::UTF_8), File.read(b, encoding: Encoding::UTF_8),
                              place: "for #{opts[:register]}", backend:, drift:)
        out.puts(JSON.pretty_generate(verdict.to_h.except(:usage)))
        usage = Engine.with_cost({ "backend" => backend.name }.merge(verdict.usage), backend)
        err.puts("sloplint-judge: #{Engine.usage_line(usage)}")
        0
      end

      # An unknown backend name or a missing key is a usage error (exit 2),
      # not a backend failure (exit 3): nothing was tried.
      def load_backend(name, err:)
        Backend.load(name)
      rescue ArgumentError => e
        err.puts("sloplint-judge: #{e.message}")
        nil
      end

      # ── status / key set ────────────────────────────────────────────────────
      # Could a run happen here? Answered without reading the key: this is the
      # check skill's probe and it runs before anyone has agreed to send text.
      # Exit 0 configured, 2 not, with the message `check` would give.
      def cmd_status(opts, out:, err:)
        klass = Backend.klass(opts[:backend])
        settings = klass.configured!
        source = Secret.present?(klass::KEY) or raise ArgumentError, Secret.missing(klass::KEY)
        out.puts("backend #{Backend.default_name(opts[:backend])} (#{settings}), key from #{source}")
        0
      rescue ArgumentError => e
        err.puts("sloplint-judge: #{e.message}")
        2
      end

      # Stores the key once. The platform tool owns the prompt and the
      # terminal, so the value is never on a command line, in a pipe, in shell
      # history or in this process. A person types this; the skill never does.
      def cmd_key(argv, opts, out:, err:, stdin:)
        key = Backend.klass(opts[:backend])::KEY
        return cmd_key_unset(key, out:, err:) if argv == ["unset"]
        return err.puts("usage: sloplint-judge [--backend NAME] key set|unset") || 2 unless argv == ["set"]

        command = Secret.store_command(key)
        return err.puts("sloplint-judge: no supported key store on this platform; export #{key} instead") || 2 unless command
        return err.puts("sloplint-judge: key set needs a terminal: the keychain tool prompts for the key itself") || 2 unless stdin.tty?

        out.puts("Storing #{key} in the OS keychain under #{Secret::SERVICE}; the keychain tool will prompt for it.")
        out.puts("Replacing the item stored earlier.") if Secret.stored?(key)
        out.puts("Any process running as you can read it back. This keeps the key out of dotfiles and out of the agent's environment, not out of your account.")
        out.flush
        Process.exec(*command)
      rescue ArgumentError => e
        err.puts("sloplint-judge: #{e.message}")
        2
      end

      # Removes the keychain item. Says so when there was none, and says when a
      # key in the environment is still there, because that one it cannot touch.
      def cmd_key_unset(key, out:, err:)
        command = Secret.delete_command(key)
        return err.puts("sloplint-judge: no supported key store on this platform") || 2 unless command
        return err.puts("sloplint-judge: no #{key} item in the keychain") || 2 unless Secret.stored?(key)

        removed = system(*command, out: File::NULL, err: File::NULL)
        return err.puts("sloplint-judge: the keychain tool could not remove the item") || 2 unless removed

        out.puts("Removed #{key} from the OS keychain (#{Secret::SERVICE}).")
        out.puts("It is still set in this shell's environment; unset it there too.") unless ENV[key].to_s.empty?
        0
      end

      # ── rules / explain ─────────────────────────────────────────────────────
      def cmd_rules(argv, out:)
        as_json = false
        OptionParser.new { |o| o.on("--json") { as_json = true } }.order!(argv)
        Sloplint::CLI.render_rules(RULES, json: as_json, out:)
        0
      end

      def cmd_explain(argv, out:, err:)
        id = argv.shift
        rule = RULES.find { |r| r.id == id }
        unless rule
          err.puts(id ? "sloplint-judge: no such rule: #{id}" : "usage: sloplint-judge explain RULE_ID")
          return 2
        end
        levels = rule.question["criteria"].each_with_index.map do |c, i|
          "  #{i}#{i == rule.flag[:level] ? " (flags)" : ""}: #{c["what"]}"
        end
        out.puts(<<~TXT)
          #{rule.id}  (#{rule.category}, #{rule.severity}, #{rule.confidence} confidence, per #{rule.unit})

          #{rule.message}

          Asks: #{format(rule.question["instructions"], register: Engine::DEFAULT_REGISTER)}
          #{levels.join("\n")}

          Why: #{rule.rationale}
          Fix: #{rule.suggestion}

          Flags:    #{Sloplint::CLI.fixture_list(rule.examples_bad)}
          Does not: #{Sloplint::CLI.fixture_list(rule.examples_ok)}
        TXT
        0
      end

      def global_parser(opts, out:)
        OptionParser.new do |o|
          o.banner = <<~BANNER
            sloplint-judge — rules that ask a System One model what a regex cannot.

            # Recommended for agents (both linters, one document). The judge sends the text to
            # api.typesafe.ai, so ask the person before running it. Check first, ask, then run:
            sloplint-judge status                            # exit 0 = a key is set up (reads no key), 2 = not
            sloplint check --judge --markdown -o json FILE
            # exit 0 = clean, 1 = notes found, 2 = usage error or not configured, 3 = the model could not be reached (nothing checked)
            # output: {"notes": [...], "judge": {"backend","requests","input_tokens","output_tokens","cost_usd"}}

            usage: sloplint-judge [-o full|json] [--register TEXT] [--backend NAME] [command] [args]

            commands:
              check         scan paths (or stdin) with the judge's rules only [default]
              compare A B   which of two passages a plain-prose editor keeps (--drift for rewrites)
              rules         list the judge's rule catalog (add --json)
              explain ID    print one rule's question, levels, rationale and fixtures
              status        say whether a run could happen here, and where the key is, without reading it
              key set       store the backend's key in the OS keychain (the keychain tool prompts for it)
              key unset     remove it from the OS keychain
              version       print the sloplint-judge version

            global options:
          BANNER
          o.on("-o", "--output-format FORMAT", %w[full json]) { |v| opts[:format] = v }
          o.on("--register TEXT", "Who the reader is (default: #{Engine::DEFAULT_REGISTER}).") { |v| opts[:register] = v }
          o.on("--backend NAME", "Which adapter to use (default: $SLOPLINT_JUDGE_BACKEND or jev).") { |v| opts[:backend] = v }
          o.on("-h", "--help", "Show this help, including the agent recipe above.") { out.puts(o.help); opts[:help_shown] = true }
          o.on("-v", "--version", "Print the sloplint-judge version.") { out.puts(VERSION); opts[:version_shown] = true }
        end
      end
    end
  end
end
