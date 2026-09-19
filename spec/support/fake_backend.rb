# frozen_string_literal: true

require_relative "../../lib/sloplint/judge"

# A backend that answers from a script, so the judge's engine, CLI and note
# assembly can be tested with no key and no network. `answer_for` is called
# with (state, question name, question) and returns [probabilities, confidence].
class FakeBackend
  attr_reader :calls

  def initialize(&answer_for)
    @answer_for = answer_for || ->(_state, _name, q) { [Array.new(q["criteria"].size) { |i| i.zero? ? 0.9 : 0.1 / (q["criteria"].size - 1) }, 0.9] }
    @calls = []
  end

  def name = "fake"

  def ask(state, questions)
    @calls << [state, questions]
    questions.to_h do |qname, q|
      probs, conf = @answer_for.call(state, qname, q)
      [qname, Sloplint::Judge::Answer.new(type: q["type"], probabilities: probs, confidence: conf, usage: { "input_tokens" => 100 })]
    end
  end
end

# Score answer helper: the given level wins with the given confidence.
def level(idx, size: 3, confidence: 0.9)
  [Array.new(size) { |i| i == idx ? 0.8 : 0.2 / (size - 1) }, confidence]
end
