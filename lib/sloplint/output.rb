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
    # judge: when the judge ran, its backend name and usage; the notes then
    # sit under "notes" and the usage under "judge", so a caller who asked for
    # the model's opinion also gets what it cost.
    def format_json(notes, by_path: false, judge: nil)
      payload = if by_path
        notes.group_by(&:path).transform_values { |ns| ns.map { |n| note_hash(n) } }
      else
        notes.map { |n| note_hash(n) }
      end
      payload = { "notes" => payload, "judge" => judge } if judge
      JSON.pretty_generate(payload)
    end

    def note_hash(note)
      h = note.to_h
      h.delete(:count) if h[:count].nil?
      h
    end
  end
end
