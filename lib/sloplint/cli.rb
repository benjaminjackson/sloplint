# frozen_string_literal: true

require "optparse"
require "json"
require_relative "version"
require_relative "rules"
require_relative "engine"
require_relative "output"

module Sloplint
  # Command-line shell: optparse, subcommands, exit codes. See docs/SPEC.md.
  #
  # Exit codes: 0 ran/no notes, 1 ran/notes found, 2 bad arguments. Empty
  # input is a 2 as well: an unread draft must not report as a clean one.
  module CLI
    module_function

    def run(argv, out: $stdout, err: $stderr, stdin: $stdin)
      opts = { format: "full" }
      parser = global_parser(opts, out:)
      # Split global options from the subcommand and its args.
      begin
        parser.order!(argv)
      rescue OptionParser::InvalidOption => e
        # `check` is the default command, so its options are accepted before
        # any command word: `sloplint --markdown -`. The global parser does not
        # know them, so put the option back and let check's parser judge it.
        argv.unshift("check", *e.args)
      end
      return 0 if opts[:help_shown] || opts[:version_shown]

      command = argv.shift

      # Bare invocation with piped stdin behaves as `check -`.
      command ||= (stdin.tty? ? "help" : "check")

      case command
      when "check"   then cmd_check(argv, opts, out:, err:, stdin:)
      when "rules"   then cmd_rules(argv, out:)
      when "explain" then cmd_explain(argv, out:, err:)
      when "version" then out.puts(VERSION); 0
      when "help"    then out.puts(parser.help); 0
      else
        # Anything else is a path or "-": `sloplint FILE`, `sloplint -`.
        # A mistyped command lands here too, and fails as a missing file.
        cmd_check(argv.unshift(command), opts, out:, err:, stdin:)
      end
    rescue OptionParser::ParseError => e
      err.puts("sloplint: #{e.message}")
      2
    end

    # ── check ───────────────────────────────────────────────────────────────
    def cmd_check(argv, opts, out:, err:, stdin:)
      markdown = false
      strict = false
      select = nil
      ignore = nil
      judge = false
      register = nil
      backend = nil
      p = OptionParser.new do |o|
        o.banner = "usage: sloplint check [options] [paths...]  (\"-\" or no paths = stdin)"
        o.on("-o", "--output-format FORMAT", %w[full json],
             "Output format: 'full' or 'json' (may also be given before the command).") { |v| opts[:format] = v }
        o.on("--markdown", "Skip fenced/inline code spans, HTML comments, and URLs before scanning.") { markdown = true }
        o.on("--select IDS", "Only run these rules (comma-separated rule ids or category names).") { |v| select = v.split(",").map(&:strip) }
        o.on("--ignore IDS", "Skip these rules (comma-separated rule ids or category names).") { |v| ignore = v.split(",").map(&:strip) }
        o.on("--strict", "Run every rule, including the ones that are off by default.") { strict = true }
        o.on("--judge", "Also run sloplint-judge's rules, which ask a model (needs the gem and a key).") { judge = true }
        o.on("--register TEXT", "With --judge: who the reader is.") { |v| register = v }
        o.on("--backend NAME", "With --judge: which model adapter to use.") { |v| backend = v }
      end
      p.order!(argv)

      # The judge is a separate gem that depends on this one. The bare require
      # goes through the load path: exe/sloplint puts this checkout's lib/ at
      # the front, so from the plugin tree the judge files beside this one win,
      # and an installed sloplint-judge gem is found otherwise. Only a missing
      # judge is the install hint; any other LoadError is a real one.
      if judge
        begin
          require "sloplint/judge"
        rescue LoadError => e
          raise unless e.path == "sloplint/judge"

          err.puts("sloplint: --judge needs the sloplint-judge gem: gem install sloplint-judge")
          return 2
        end
      end
      catalog = judge ? RULES + Judge::RULES : RULES

      unknown = unknown_rule_refs(select, catalog) + unknown_rule_refs(ignore, catalog)
      unless unknown.empty?
        err.puts("sloplint: unknown rule or category: #{unknown.join(", ")}")
        err.puts("run `sloplint rules` to list them.")
        return 2
      end

      rules = select_rules(select, ignore, strict, catalog)
      paths = argv.empty? ? ["-"] : argv
      by_path = paths.reject { |x| x == "-" }.size > 1

      sources = read_sources(paths, err:, stdin:)
      return 2 unless sources

      regex_rules, judge_rules = rules.partition { |r| r.is_a?(Rule) }
      all_notes = sources.flat_map do |label, text|
        Engine.scan(text, rules: regex_rules, markdown:, path: label)
      end

      if judge && !judge_rules.empty?
        begin
          judge_backend = Judge::Backend.load(backend)
        rescue ArgumentError => e
          err.puts("sloplint: --judge: #{e.message}")
          return 2
        end
        begin
          judge_notes = Judge::Engine.scan_sources(sources, name: "sloplint: judge", err:, rules: judge_rules, backend: judge_backend,
                                                            markdown:, register: register || Judge::Engine::DEFAULT_REGISTER, strict:)
        # Exit 3 withholds the regex notes too: a caller that asked for both
        # and got one would read it as a clean judge run.
        rescue Judge::BackendError => e
          err.puts("sloplint: judge backend failure: #{e.message}")
          return 3
        end
        order = sources.each_with_index.to_h { |(label, _), i| [label, i] }
        all_notes = (all_notes + judge_notes).sort_by.with_index { |n, i| [order[n.path], n.line, n.column, i] }
      end

      emit(all_notes, opts[:format], out:, by_path:)
      all_notes.empty? ? 0 : 1
    # Invalid UTF-8 reaches this two ways: String#strip in the empty check
    # raises Encoding::CompatibilityError, the engine's regexes raise
    # ArgumentError. Both are the same thing to the reader.
    rescue ArgumentError, Encoding::CompatibilityError => e
      err.puts("sloplint: invalid input: #{e.message}")
      2
    end

    # Read every path (or stdin for "-") as UTF-8. Returns [[label, text], ...]
    # or nil after writing the error, so the caller exits 2.
    def read_sources(paths, err:, stdin:, name: "sloplint")
      sources = []
      paths.each do |path|
        # Read as UTF-8 whatever the locale says. A sandbox with no LANG set
        # leaves Ruby's default external encoding at US-ASCII, and then the
        # first em dash raises "invalid byte sequence in US-ASCII" -- on prose
        # that is perfectly valid UTF-8. Prose is the only input sloplint
        # takes, so UTF-8 is the assumption, not the locale's guess.
        text =
          if path == "-"
            stdin.read.force_encoding(Encoding::UTF_8)
          else
            unless File.file?(path)
              err.puts("#{name}: no such file: #{path}")
              return nil
            end
            File.read(path, encoding: Encoding::UTF_8)
          end
        sources << [path == "-" ? "-" : path, text]
      end

      # Tested on the raw text, before --markdown blanks code and URLs: a file
      # that holds only a fenced code block did arrive, and scanning it clean
      # is right. Nothing arriving at all is the trap -- the same one a
      # mistyped rule id sets, and it exits 2 for the same reason.
      if sources.all? { |_, text| text.strip.empty? }
        names = sources.map { |label, _| label == "-" ? "stdin" : label }
        err.puts("#{name}: empty input: nothing to check in #{names.join(", ")}")
        return nil
      end
      sources
    end

    def emit(notes, format, out:, by_path:)
      if format == "json"
        out.puts(Output.format_json(notes, by_path:))
      else
        text = Output.format_human(notes)
        out.puts(text) unless text.empty?
      end
    end

    # ── rules ───────────────────────────────────────────────────────────────
    def cmd_rules(argv, out:)
      as_json = false
      OptionParser.new do |o|
        o.banner = "usage: sloplint rules [--json]"
        o.on("--json", "Emit the catalog as JSON for machine enumeration.") { as_json = true }
      end.order!(argv)

      render_rules(RULES, json: as_json, out:)
      0
    end

    # The catalog as a table or as JSON. Shared with sloplint-judge, whose
    # rules also carry a unit.
    def render_rules(catalog, json:, out:)
      if json
        payload = catalog.map do |r|
          { id: r.id, category: r.category, severity: r.severity, confidence: r.confidence,
            message: r.message, rationale: r.rationale, suggestion: r.suggestion }
            .merge(r.respond_to?(:unit) ? { unit: r.unit } : {})
        end
        out.puts(JSON.pretty_generate(payload))
      else
        catalog.each do |r|
          off = r.confidence == "low" ? " [off by default]" : ""
          out.puts("#{r.id.ljust(24)} #{r.category.ljust(18)} #{r.severity.ljust(8)} #{r.confidence.ljust(7)} #{r.message}#{off}")
        end
      end
    end

    # ── explain ID ────────────────────────────────────────────────────────
    def cmd_explain(argv, out:, err:)
      id = argv.shift
      unless id
        err.puts("usage: sloplint explain RULE_ID")
        return 2
      end
      rule = RULES.find { |r| r.id == id }
      unless rule
        err.puts("sloplint: no such rule: #{id}")
        err.puts("run `sloplint rules` to list them.")
        return 2
      end
      out.puts(<<~TXT)
        #{rule.id}  (#{rule.category}, #{rule.severity}, #{rule.confidence} confidence#{rule.confidence == "low" ? ", off by default" : ""})

        #{rule.message}

        Why: #{rule.rationale}
        Fix: #{rule.suggestion}

        Flags:    #{fixture_list(rule.examples_bad)}
        Does not: #{fixture_list(rule.examples_ok)}
      TXT
      0
    end

    # One fixture per line, aligned under the label. Fixtures may contain
    # newlines (a chain that survives a hard wrap, one that dies at a paragraph
    # break), so escape them rather than letting a fixture break the block --
    # `explain` is parsed by agents, and a stray newline reads as end-of-list.
    def fixture_list(examples)
      examples.map { |e| e.gsub("\r", '\r').gsub("\n", '\n') }.join("\n          ")
    end

    # ── helpers ─────────────────────────────────────────────────────────────
    # Ids/categories in refs that match no rule in the catalog. nil (no --select
    # or --ignore given) passes through as no unknowns.
    def unknown_rule_refs(refs, catalog = RULES)
      return [] unless refs

      known = catalog.flat_map { |r| [r.id, r.category] }.uniq
      refs - known
    end

    # --select/--ignore accept rule ids or category names. The default set
    # excludes low-confidence rules unless they are explicitly selected. A
    # category ref selects only that category's non-low rules unless --strict
    # is set; naming a rule by its own id still selects it whatever its
    # confidence. catalog is RULES, or RULES plus the judge's under --judge.
    def select_rules(select, ignore, strict = false, catalog = RULES)
      runs_by_default = ->(r) { r.confidence != "low" }
      rules = if select
        catalog.select { |r| select.include?(r.id) || (select.include?(r.category) && (runs_by_default.call(r) || strict)) }
      elsif strict
        catalog
      else
        catalog.select(&runs_by_default)
      end
      if ignore
        rules = rules.reject { |r| ignore.include?(r.id) || ignore.include?(r.category) }
      end
      rules
    end

    def global_parser(opts, out:)
      OptionParser.new do |o|
        o.banner = <<~BANNER
          sloplint — flag the rhetorical tics and puffery that mark AI-generated prose.

          # Recommended for agents:
          cat FILE | sloplint check --markdown -o json -
          # exit 0 = clean, 1 = notes found, >1 = error (empty input is an error)
          # each note: {path,line,column,severity,confidence,rule,category,message,excerpt,context,rationale,suggestion,count}
          # (count is present only for the rules that tally items)

          usage: sloplint [-o full|json] [command] [args]

          commands:
            check        scan paths (or stdin) for AI-slop tells and report notes [default]
                         a first argument that is not a command name is taken as a path
                         --judge adds sloplint-judge's model-backed rules when that gem is installed
            rules        list the rule catalog (add --json for the machine-readable form)
            explain ID   print one rule's message, rationale, and a bad/ok example
            version      print the sloplint version

          global options:
        BANNER
        o.on("-o", "--output-format FORMAT", %w[full json],
             "Output format: 'full' (human-readable text) or 'json' (default: full).") do |v|
          opts[:format] = v
        end
        o.on("-h", "--help", "Show this help, including the copy-paste agent recipe above.") do
          out.puts(o.help)
          opts[:help_shown] = true
        end
        o.on("-v", "--version", "Print the sloplint version.") do
          out.puts(VERSION)
          opts[:version_shown] = true
        end
        o.separator ""
        o.separator "See `sloplint explain <id>` for any rule, or docs/SPEC.md for the JSON contract."
      end
    end
  end
end
