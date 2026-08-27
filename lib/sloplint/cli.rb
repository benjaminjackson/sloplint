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
  # Exit codes: 0 ran/no notes, 1 ran/notes found, 2 bad arguments.
  module CLI
    module_function

    def run(argv, out: $stdout, err: $stderr, stdin: $stdin)
      opts = { format: "full" }
      parser = global_parser(opts, out:)
      # Split global options from the subcommand and its args.
      parser.order!(argv)
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
      select = nil
      ignore = nil
      p = OptionParser.new do |o|
        o.banner = "usage: sloplint check [options] [paths...]  (\"-\" or no paths = stdin)"
        o.on("-o", "--output-format FORMAT", %w[full json],
             "Output format: 'full' or 'json' (may also be given before the command).") { |v| opts[:format] = v }
        o.on("--markdown", "Skip fenced/inline code spans and URLs before scanning.") { markdown = true }
        o.on("--select IDS", "Only run these rules (comma-separated rule ids or category names).") { |v| select = v.split(",").map(&:strip) }
        o.on("--ignore IDS", "Skip these rules (comma-separated rule ids or category names).") { |v| ignore = v.split(",").map(&:strip) }
      end
      p.order!(argv)

      unknown = unknown_rule_refs(select) + unknown_rule_refs(ignore)
      unless unknown.empty?
        err.puts("sloplint: unknown rule or category: #{unknown.join(", ")}")
        err.puts("run `sloplint rules` to list them.")
        return 2
      end

      rules = select_rules(select, ignore)
      paths = argv.empty? ? ["-"] : argv
      by_path = paths.reject { |x| x == "-" }.size > 1

      all_notes = []
      paths.each do |path|
        text =
          if path == "-"
            stdin.read
          else
            unless File.file?(path)
              err.puts("sloplint: no such file: #{path}")
              return 2
            end
            File.read(path)
          end
        label = path == "-" ? "-" : path
        all_notes.concat(Engine.scan(text, rules:, markdown:, path: label))
      end

      case opts[:format]
      when "json"
        out.puts(Output.format_json(all_notes, by_path:))
      else
        text = Output.format_human(all_notes)
        out.puts(text) unless text.empty?
      end

      all_notes.empty? ? 0 : 1
    rescue ArgumentError => e
      err.puts("sloplint: invalid input: #{e.message}")
      2
    end

    # ── rules ───────────────────────────────────────────────────────────────
    def cmd_rules(argv, out:)
      as_json = false
      OptionParser.new do |o|
        o.banner = "usage: sloplint rules [--json]"
        o.on("--json", "Emit the catalog as JSON for machine enumeration.") { as_json = true }
      end.order!(argv)

      if as_json
        payload = RULES.map do |r|
          { id: r.id, category: r.category, severity: r.severity,
            message: r.message, suggestion: r.suggestion, default_on: r.default_on }
        end
        out.puts(JSON.pretty_generate(payload))
      else
        RULES.each do |r|
          off = r.default_on ? "" : " [off by default]"
          out.puts("#{r.id.ljust(24)} #{r.category.ljust(14)} #{r.severity.ljust(8)} #{r.message}#{off}")
        end
      end
      0
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
        #{rule.id}  (#{rule.category}, #{rule.severity}#{rule.default_on ? "" : ", off by default"})

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
    def unknown_rule_refs(refs)
      return [] unless refs

      known = RULES.flat_map { |r| [r.id, r.category] }.uniq
      refs - known
    end

    # --select/--ignore accept rule ids or category names. Default set excludes
    # default_on:false rules unless they are explicitly selected.
    def select_rules(select, ignore)
      rules = if select
        RULES.select { |r| select.include?(r.id) || select.include?(r.category) }
      else
        RULES.select(&:default_on)
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
          # exit 0 = clean, 1 = notes found, >1 = error
          # each note: {path,line,column,severity,rule,category,message,excerpt,context,rationale,suggestion}

          usage: sloplint [-o full|json] [command] [args]

          commands:
            check        scan paths (or stdin) for AI-slop tells and report notes [default]
                         a first argument that is not a command name is taken as a path
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
