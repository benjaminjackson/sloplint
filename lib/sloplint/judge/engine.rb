# frozen_string_literal: true

require "sloplint/engine"
require "sloplint/split"
require_relative "rules"
require_relative "backend"

module Sloplint
  module Judge
    # Runs judge rules over a document and returns sloplint Notes. See
    # docs/JUDGE.md "Rule catalog" for the triage order and "Note" for how the
    # confidence on each note is derived.
    module Engine
      DEFAULT_REGISTER = "an engineer on the team reading a design document"
      RANK = { "high" => 0, "medium" => 1, "low" => 2 }.freeze
      MIN_SENTENCES = 3

      Result = Data.define(:notes, :usage)

      module_function

      # Scan several [label, text] sources and sum the usage. Writes one line
      # to err naming the backend, the request count and whatever tokens the
      # backend reported; the same numbers go into the JSON output under
      # "judge". Returns a Result.
      def scan_sources(sources, name:, err:, backend: Backend.load, **kwargs)
        usage = Hash.new(0)
        notes = sources.flat_map do |label, text|
          result = scan(text, backend:, path: label, **kwargs)
          result.usage.each { |k, v| usage[k] += v }
          result.notes
        end
        usage = with_cost({ "backend" => backend.name, "requests" => usage.delete("requests") || 0 }.merge(usage), backend)
        err.puts("#{name} #{usage_line(usage)}")
        Result.new(notes:, usage:)
      end

      # The dollar line, last, when the backend prices its own tokens. Both
      # the commands that print a usage line end with the same number.
      def with_cost(usage, backend)
        usage["cost_usd"] = backend.cost_usd(usage).round(6) if backend.respond_to?(:cost_usd)
        usage
      end

      # "jev-latest, 4 requests, 5200 input_tokens, 252 output_tokens, $0.000218"
      def usage_line(usage)
        usage.map do |k, v|
          case k
          when "backend" then v
          when "cost_usd" then format("$%.6f", v)
          else "#{v} #{k}"
          end
        end.join(", ")
      end

      # text: the source. rules: judge Rules to run. backend: answers `ask`.
      # markdown: blank code, HTML comments and URLs, and drop furniture.
      # strict: run sentence rules on every sentence and keep low notes.
      def scan(text, rules: RULES, backend: Backend.load, markdown: false, path: "-",
               register: DEFAULT_REGISTER, strict: false,
               concurrency: ENV.fetch("SLOPLINT_JUDGE_CONCURRENCY", "8").to_i)
        para_rules, sent_rules = rules.partition { |r| r.unit == :paragraph }
        paragraphs = Split.paragraphs(text, markdown:)
        line_starts = Sloplint::Engine.line_starts_for(text)
        usage = Hash.new(0)
        notes = []
        flagged = []

        unless para_rules.empty?
          eligible = strict ? paragraphs : paragraphs.select { |p| p.sentences.size >= MIN_SENTENCES }
          questions = questions_for(para_rules, register)
          answered = in_parallel(eligible, concurrency) do |p|
            backend.ask({ "register" => register, "paragraph" => p.text, "sentence_count" => p.sentences.size }, questions)
          end
          eligible.zip(answered).each do |p, answers|
            add_usage(usage, answers)
            para_rules.each do |rule|
              note = note_for(rule, answer_for(answers, rule), unit_for(rule, p), text, path, line_starts, strict)
              next unless note

              notes << note
              flagged << p
            end
          end
        end

        # Sentence rules run where a paragraph rule fired, and in the short
        # paragraphs no paragraph rule looked at. With no paragraph rule to
        # triage by, or under --strict, they run everywhere. Either way no
        # paragraph goes unexamined: a clean exit on a document nothing looked
        # at would be a lie.
        unless sent_rules.empty?
          targets = strict || para_rules.empty? ? paragraphs : (paragraphs - eligible + flagged.uniq).sort_by(&:offset)
          jobs = targets.flat_map { |p| p.sentences.each_index.map { |i| [p, i] } }
          questions = questions_for(sent_rules, register)
          answered = in_parallel(jobs, concurrency) do |(p, i)|
            backend.ask({ "register" => register, "paragraph" => { "sentences" => p.sentences.map(&:text) },
                          "target_index" => i, "target" => p.sentences[i].text }, questions)
          end
          jobs.zip(answered).each do |(p, i), answers|
            add_usage(usage, answers)
            sent_rules.each do |rule|
              note = note_for(rule, answer_for(answers, rule), p.sentences[i], text, path, line_starts, strict)
              notes << note if note
            end
          end
        end

        Result.new(notes: notes.sort_by { |n| [n.line, n.column] }, usage: usage)
      end

      def questions_for(rules, register)
        rules.to_h do |r|
          q = r.question.merge("instructions" => format(r.question["instructions"], register: register))
          [r.id, q]
        end
      end

      # The sentence a paragraph rule points at, or the paragraph itself.
      def unit_for(rule, paragraph)
        case rule.excerpt
        when :first then paragraph.sentences.first
        when :last then paragraph.sentences.last
        else paragraph
        end
      end

      def flagged?(rule, answer) = answer.top == rule.flag[:level]

      # A backend that answers some questions and not others is a failed
      # request, not a clean one.
      def answer_for(answers, rule) = answers.fetch(rule.id) { raise BackendError, "no answer for #{rule.id}" }

      # Model confidence to a band. Provisional -- see docs/JUDGE.md "Note".
      def band(confidence)
        if confidence >= 0.7 then "high"
        elsif confidence >= 0.5 then "medium"
        else "low"
        end
      end

      def note_for(rule, answer, unit, text, path, line_starts, strict)
        return nil unless flagged?(rule, answer)

        # The rule's confidence is a ceiling on what gets reported, not a
        # reason to drop the note: a low-ceiling rule only runs when the user
        # named it. What a default run drops is a low-confidence answer.
        model = band(answer.confidence)
        return nil if model == "low" && !strict

        conf = [rule.confidence, model].max_by { |c| RANK[c] }

        line, column = Sloplint::Engine.line_col(text, unit.offset, line_starts:)
        Note.new(
          path: path, line: line, column: column, severity: rule.severity, confidence: conf,
          rule: rule.id, category: rule.category, message: rule.message,
          excerpt: unit.text, context: Sloplint::Engine.context_window(text, unit.offset, unit.offset + unit.length),
          count: nil, rationale: rule.rationale, suggestion: rule.suggestion
        )
      end

      # Every answer in one request carries the same usage; count it once,
      # and count the request.
      def add_usage(usage, answers)
        usage["requests"] += 1
        first = answers.values.first
        first&.usage&.each { |k, v| usage[k] += v.to_i }
      end

      # Map items through the block on up to `concurrency` threads, keeping
      # order. Items are dealt out round-robin, so 9 items over 8 threads is
      # 2 + 1 + 1 ... and not 8 + 1: slicing into equal chunks leaves a
      # thread with one item and the rest with a full chunk each. Thread#value
      # re-raises whatever a thread raised.
      # ponytail: a static deal, so one slow request delays the rest of its
      # thread's items; a queue if requests stop being uniform.
      def in_parallel(items, concurrency)
        return items.map { |i| yield i } if concurrency <= 1 || items.size <= 1

        n = [concurrency, items.size].min
        out = Array.new(items.size)
        items.each_with_index.group_by { |_, i| i % n }
             .map { |_, deal| Thread.new { Thread.current.report_on_exception = false; deal.each { |item, i| out[i] = yield item } } }
             .each(&:value)
        out
      end
    end
  end
end
