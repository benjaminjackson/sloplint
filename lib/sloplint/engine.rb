# frozen_string_literal: true

require_relative "rules"

module Sloplint
  # One match = one Note. See docs/SPEC.md "Note".
  Note = Data.define(
    :path, :line, :column, :severity, :rule, :category,
    :message, :excerpt, :count, :suggestion
  )

  module Engine
    module_function

    # text: the source. rules: which Rule objects to run. markdown: blank code/URLs first.
    # path: label carried into each Note (e.g. filename or "-" for stdin).
    def scan(text, rules: RULES, markdown: false, path: "-")
      text = blank_markdown(text) if markdown
      notes = []
      rules.each do |rule|
        text.to_enum(:scan, rule.pattern).each do
          m = Regexp.last_match
          matched = m[0]
          next if rule.skip.any? { |re| matched.match?(re) }

          count = rule.count_group ? matched.scan(rule.count_group).size : nil
          line, column = line_col(text, m.begin(0))
          message = count ? rule.message % { count: count } : rule.message
          notes << Note.new(
            path: path, line: line, column: column,
            severity: rule.severity, rule: rule.id, category: rule.category,
            message: message, excerpt: matched.gsub(/\s+/, " ").strip,
            count: count, suggestion: rule.suggestion
          )
        end
      end
      notes.sort_by { |n| [n.line, n.column] }
    end

    # 1-indexed line and column for a byte/char offset into text.
    def line_col(text, offset)
      prefix = text[0, offset]
      line = prefix.count("\n") + 1
      column = offset - (prefix.rindex("\n") || -1)
      [line, column]
    end

    # Replace fenced code, inline code, and URLs with same-length whitespace so
    # line/column stay correct. Newlines are preserved.
    def blank_markdown(text)
      blank = lambda { |s| s.gsub(/[^\n]/, " ") }
      text
        .gsub(/```.*?```/m) { |s| blank.call(s) }   # fenced code
        .gsub(/`[^`\n]*`/) { |s| blank.call(s) }    # inline code
        .gsub(%r{https?://\S+}) { |s| blank.call(s) } # bare URLs
    end
  end
end
