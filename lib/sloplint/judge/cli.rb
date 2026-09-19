# frozen_string_literal: true

require "optparse"
require "json"
require "sloplint/judge"

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
          o.on("-o", "--output-format FORMAT", %w[full json]) { |v| opts[:format] = v }
          o.on("--markdown", "Skip fenced/inline code spans, HTML comments, URLs and Markdown furniture.") { markdown = true }
          o.on("--select IDS", "Only run these rules (comma-separated rule ids or categories).") { |v| select = v.split(",").map(&:strip) }
          o.on("--ignore IDS", "Skip these rules (comma-separated rule ids or categories).") { |v| ignore = v.split(",").map(&:strip) }
          o.on("--strict", "Run sentence rules on every sentence and keep low-confidence notes.") { strict = true }
          o.on("--register TEXT", "Who the reader is.") { |v| opts[:register] = v }
          o.on("--backend NAME", "Which adapter to use.") { |v| opts[:backend] = v }
        end.order!(argv)

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
        end.order!(argv)
        a, b = argv
        unless a && b && File.file?(a) && File.file?(b)
          err.puts("usage: sloplint-judge compare [--drift] A B")
          return 2
        end
        backend = load_backend(opts[:backend], err:) or return 2
        verdict = Compare.run(File.read(a, encoding: Encoding::UTF_8), File.read(b, encoding: Encoding::UTF_8),
                              place: "for #{opts[:register]}", backend:, drift:)
        out.puts(JSON.pretty_generate(verdict.to_h.except(:usage)))
        err.puts("sloplint-judge: #{backend.name}, #{verdict.usage.map { |k, v| "#{v} #{k}" }.join(", ")}") unless verdict.usage.empty?
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

            # Recommended for agents (both linters, one array):
            sloplint check --judge --markdown -o json FILE
            # exit 0 = clean, 1 = notes found, 2 = usage error, 3 = the model could not be reached

            usage: sloplint-judge [-o full|json] [--register TEXT] [--backend NAME] [command] [args]

            commands:
              check         scan paths (or stdin) with the judge's rules only [default]
              compare A B   which of two passages a plain-prose editor keeps (--drift for rewrites)
              rules         list the judge's rule catalog (add --json)
              explain ID    print one rule's question, levels, rationale and fixtures
              version       print the sloplint-judge version

            global options:
          BANNER
          o.on("-o", "--output-format FORMAT", %w[full json]) { |v| opts[:format] = v }
          o.on("--register TEXT", "Who the reader is (default: #{Engine::DEFAULT_REGISTER}).") { |v| opts[:register] = v }
          o.on("--backend NAME", "Which adapter to use (default: $SLOPLINT_JUDGE_BACKEND or jev).") { |v| opts[:backend] = v }
          o.on("-h", "--help") { out.puts(o.help); opts[:help_shown] = true }
          o.on("-v", "--version") { out.puts(VERSION); opts[:version_shown] = true }
        end
      end
    end
  end
end
