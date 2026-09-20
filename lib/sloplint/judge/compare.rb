# frozen_string_literal: true

require_relative "backend"

module Sloplint
  module Judge
    # The pairwise judge: which of two passages a plain-prose editor keeps,
    # and optionally whether B changed what A says. See docs/JUDGE.md "compare".
    module Compare
      KEEP = "A careful editor who wants prose that is plain, specific and economical, and who distrusts polish " \
             "for its own sake, must run exactly one of A and B %{place}. Which does the editor run?"
      DRIFT = "Does B state any fact, claim or qualification that A does not, or drop any that A states? " \
              "Answer yes if the meaning differs in any way a careful reader would notice, no if only the wording differs."

      # The acceptance rule for a rewrite (keep B, drift at or under 0.5, the
      # lower confidence at or above 0.7) belongs to the phase-two loop; this
      # reports the inputs and applies nothing. See docs/JUDGE.md "compare".
      Verdict = Data.define(:keep, :p_keep_b, :keep_confidence, :drift, :drift_confidence, :usage)

      module_function

      # a, b: the passages. place: the register as a venue. drift: also ask
      # whether B changes what A says. The order sent is randomised because
      # the judge has a position bias; the answer is mapped back.
      def run(a, b, place:, backend: Backend.load, drift: false, swap: rand < 0.5)
        first, second = swap ? [b, a] : [a, b]
        questions = {
          "keep" => { "type" => "choice", "instructions" => format(KEEP, place: place),
                      "criteria" => { "A" => "The editor runs passage A.", "B" => "The editor runs passage B." } }
        }
        questions["drift"] = { "type" => "noul", "instructions" => DRIFT } if drift
        answers = backend.ask({ "A" => first, "B" => second }, questions)
        keep = answers["keep"] or raise BackendError, "the backend answered no keep question"
        p_b = probability(keep, swap ? "A" : "B")
        d = answers["drift"]
        Verdict.new(keep: p_b >= 0.5 ? "B" : "A", p_keep_b: p_b, keep_confidence: keep.confidence,
                    drift: d&.probabilities, drift_confidence: d&.confidence, usage: keep.usage)
      end

      # The keep answer is a choice between the options named A and B. An
      # answer keyed any other way is a malformed body, which ends `compare`
      # with exit 3 like any other backend failure, not with a backtrace.
      def probability(keep, option)
        probs = keep.probabilities
        raise BackendError, "the keep answer is #{probs.class}, not a probability for A and one for B" unless probs.is_a?(Hash)

        probs.fetch(option) { raise BackendError, "the keep answer has no probability for #{option}" }
      end
    end
  end
end
