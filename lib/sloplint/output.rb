# frozen_string_literal: true

require "json"

module Sloplint
  module Output
    module_function

    # proselint-style "full" text: one note per line, with excerpt + suggestion.
    def format_human(notes)
      return "" if notes.empty?

      notes.map do |n|
        head = "#{n.path}:#{n.line}:#{n.column}: #{n.severity} #{n.rule}  #{n.message}"
        excerpt = "    excerpt: #{n.context}"
        why = "    why: #{n.rationale}"
        fix = "    fix: #{n.suggestion}"
        [head, excerpt, why, fix].join("\n")
      end.join("\n\n")
    end

    # JSON: an array of notes, or an object keyed by path when >1 file was scanned.
    def format_json(notes, by_path: false)
      if by_path
        grouped = notes.group_by(&:path).transform_values { |ns| ns.map { |n| note_hash(n) } }
        JSON.pretty_generate(grouped)
      else
        JSON.pretty_generate(notes.map { |n| note_hash(n) })
      end
    end

    def note_hash(note)
      h = note.to_h
      h.delete(:count) if h[:count].nil?
      h
    end
  end
end
