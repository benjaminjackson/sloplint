# frozen_string_literal: true

require_relative "../engine"
require_relative "../split"
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
              note = note_for(rule, answers.fetch(rule.id), unit_for(rule, p), text, path, line_starts, strict)
              next unless note

              notes << note
              flagged << p
            end
          end
        end

        # Sentence rules run where a paragraph rule fired. With no paragraph rule
        # to triage by, or under --strict, they run everywhere: a silent clean
        # exit on a document nothing examined would be a lie.
        unless sent_rules.empty?
          targets = strict || para_rules.empty? ? paragraphs : flagged.uniq
          jobs = targets.flat_map { |p| p.sentences.each_index.map { |i| [p, i] } }
          questions = questions_for(sent_rules, register)
          answered = in_parallel(jobs, concurrency) do |(p, i)|
            backend.ask({ "register" => register, "paragraph" => { "sentences" => p.sentences.map(&:text) },
                          "target_index" => i, "target" => p.sentences[i].text }, questions)
          end
          jobs.zip(answered).each do |(p, i), answers|
            add_usage(usage, answers)
            sent_rules.each do |rule|
              note = note_for(rule, answers.fetch(rule.id), p.sentences[i], text, path, line_starts, strict)
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

      def flagged?(rule, answer)
        f = rule.flag
        f.key?(:level) ? answer.top == f[:level] : answer.top == f[:yes]
      end

      # Model confidence to a band. Provisional -- see docs/JUDGE.md "Note".
      def band(confidence)
        if confidence >= 0.7 then "high"
        elsif confidence >= 0.5 then "medium"
        else "low"
        end
      end

      def note_for(rule, answer, unit, text, path, line_starts, strict)
        return nil unless flagged?(rule, answer)

        conf = [rule.confidence, band(answer.confidence)].max_by { |c| RANK[c] }
        return nil if conf == "low" && !strict

        line, column = Sloplint::Engine.line_col(text, unit.offset, line_starts:)
        Note.new(
          path: path, line: line, column: column, severity: rule.severity, confidence: conf,
          rule: rule.id, category: rule.category, message: rule.message,
          excerpt: unit.text, context: Sloplint::Engine.context_window(text, unit.offset, unit.offset + raw_length(text, unit)),
          count: nil, rationale: rule.rationale, suggestion: rule.suggestion
        )
      end

      # Length of the unit as written, before its whitespace was collapsed.
      def raw_length(text, unit)
        pattern = Regexp.new(unit.text.split(" ").map { |w| Regexp.escape(w) }.join('\s+'))
        m = text.match(pattern, unit.offset)
        m ? m.end(0) - unit.offset : unit.text.length
      end

      # Every answer in one request carries the same usage; count it once.
      def add_usage(usage, answers)
        first = answers.values.first
        first&.usage&.each { |k, v| usage[k] += v.to_i }
      end

      # Map items through the block on up to `concurrency` threads, keeping
      # order. The first BackendError stops the run and is re-raised.
      def in_parallel(items, concurrency)
        return items.map { |i| yield i } if concurrency <= 1 || items.size <= 1

        queue = Queue.new
        items.each_with_index { |it, i| queue << [i, it] }
        results = Array.new(items.size)
        error = nil
        Array.new([concurrency, items.size].min) do
          Thread.new do
            until error || queue.empty?
              i, it = queue.pop(true)
              begin
                results[i] = yield it
              rescue BackendError => e
                error = e
              end
            end
          rescue ThreadError
            nil
          end
        end.each(&:join)
        raise error if error

        results
      end
    end
  end
end
