# frozen_string_literal: true

module Sloplint
  module Judge
    # A rule is data. See docs/JUDGE.md "Rule model".
    #
    # unit: :paragraph or :sentence, what the question is about.
    # severity: what the construct costs the prose -- "error", "warning", "info".
    # confidence: a ceiling on the note's confidence, and how likely a flag is a
    #   false positive, as in sloplint. A "low" rule stays out of the default run.
    # question: the System One question, verbatim in the shape the adapter sends.
    #   %{register} in the instructions is filled from --register.
    # flag: which answer makes a note. { level: 0 } for a score, { yes: true } for a noul.
    # excerpt: which sentence of a paragraph the note points at -- :first, :last or :all.
    Rule = Data.define(
      :id, :category, :unit, :severity, :confidence, :question, :flag, :excerpt,
      :message, :suggestion, :examples_bad, :examples_ok, :rationale
    ) do
      def initialize(excerpt: :all, **rest) = super
    end

    # Levels run low to high; high is what a careful editor prefers. Each level
    # is a situation with examples, because the model judges each one on its
    # own against the text and a degree ("somewhat concrete") gives it nothing
    # to match.
    RULES = [
      # ── paragraph ───────────────────────────────────────────────────────────
      Rule.new(
        id: "particulars", category: "paragraph", unit: :paragraph, severity: "warning", confidence: "high",
        question: {
          "type" => "score",
          "instructions" => "Across the whole paragraph, how much can %{register} point to or look up?",
          "criteria" => [
            { "what" => "The paragraph names nothing specific: no person, place, number, date, title, product or quoted words; it could be about many different things.",
              "examples" => ["Effective collaboration is essential for any team. When people communicate openly, problems are solved faster and outcomes improve. Leaders should foster an environment where everyone feels heard."] },
            { "what" => "A few particulars, in a paragraph that is otherwise general.",
              "examples" => ["Most teams struggle with handoffs. At one company the fix was a shared checklist, and it helped. The lesson is that small process changes matter."] },
            { "what" => "Particulars throughout: most sentences carry a name, number, date, place or quotation.",
              "examples" => ["The checkout API returned 503 for 47 minutes on March 3. The TLS certificate for api.example.com had expired at 09:14. The renewal job had been failing since February 11 and posting to a Slack channel nobody read."] }
          ]
        },
        flag: { level: 0 }, excerpt: :all,
        message: "Paragraph names nothing a reader could check.",
        suggestion: "Put in the name, the number, the date or the quote the paragraph is really about.",
        examples_bad: [
          "Good documentation is important for any project. It helps new contributors get up to speed and reduces the burden on maintainers. Teams that invest in it tend to see better outcomes over time.",
          "Modern systems face many challenges around reliability. A thoughtful approach to monitoring and alerting can make a significant difference. Organisations should treat this as a priority rather than an afterthought."
        ],
        examples_ok: [
          "The deploy at 14:02 on Tuesday doubled p99 latency on the search endpoint. Grafana showed the connection pool pinned at 40 for eleven minutes. We rolled back to build 4187 and latency returned to 120 ms.",
          "RFC 2119 defines MUST, SHOULD and MAY. Section 6 of this draft uses all three. A reviewer on the list asked whether SHOULD in 6.2 was meant as MUST."
        ],
        rationale: "A paragraph with nothing in it a reader could check reads as written from outside the subject. Model prose in the registers this tool is for carries fewer particulars than human prose on the same topic, because the model has no incident, no ticket and no date to draw on. The judgment is about what the paragraph names, not whether what it names is true."
      ),
      Rule.new(
        id: "wrap-up", category: "paragraph", unit: :paragraph, severity: "warning", confidence: "high",
        question: {
          "type" => "score",
          "instructions" => "How does the paragraph end, for %{register}?",
          "criteria" => [
            { "what" => "The last sentence restates what the paragraph already said, sums it up, or draws a general moral from it; it tells the reader nothing new.",
              "examples" => ["...Together, these factors make it a place worth visiting.", "...Ultimately, the decision reflects a broader shift in priorities."] },
            { "what" => "The last sentence adds a small qualification or a transition to what comes next.",
              "examples" => ["...Whether that holds in winter is another question.", "...The second problem is harder."] },
            { "what" => "The last sentence states a new fact, a particular, a number, a quote or a concrete consequence.",
              "examples" => ["...The fine was $2,400.", "...He was arrested at the airport on Tuesday."] }
          ]
        },
        flag: { level: 0 }, excerpt: :last,
        message: "Paragraph ends by restating itself.",
        suggestion: "Cut the last sentence, or end on the fact.",
        examples_bad: [
          "The migration moved 40 tables in two weekends. Two of them needed manual fixes for timezone columns. The rollback plan was tested once on staging. Overall, careful planning made the migration a success.",
          "The parser rejects any line over 4,096 bytes. Longer lines come from the log shipper concatenating retries. We capped retries at three. In the end, understanding the root cause was what mattered most."
        ],
        examples_ok: [
          "The migration moved 40 tables in two weekends. Two of them needed manual fixes for timezone columns. The rollback plan was tested once on staging. Rollback took four minutes.",
          "The parser rejects any line over 4,096 bytes. Longer lines come from the log shipper concatenating retries. We capped retries at three and the rejections stopped on the 14th."
        ],
        rationale: "A paragraph that closes on a summary of itself tells the reader nothing they did not have one sentence earlier. Human prose in the registers this tool is for closes on a fact or a consequence; model prose closes on a moral. The strongest single signal in the catalog."
      ),
      Rule.new(
        id: "throat-clearing", category: "paragraph", unit: :paragraph, severity: "info", confidence: "high",
        question: {
          "type" => "score",
          "instructions" => "How does the paragraph begin, for %{register}?",
          "criteria" => [
            { "what" => "The first sentence announces the topic in general terms or states something every reader already knows before anything particular is said.",
              "examples" => ["Cooking is an important part of daily life for many people.", "In today's fast-paced world, technology plays a vital role."] },
            { "what" => "The first sentence frames the topic but with a particular in it.",
              "examples" => ["Most recipes for risotto call for constant stirring."] },
            { "what" => "The first sentence goes straight to a particular: a person, an event, a number, a step, a claim someone could dispute.",
              "examples" => ["Sania Mirza won the Hyderabad Open on Sunday.", "Add the rice and stir for one minute."] }
          ]
        },
        flag: { level: 0 }, excerpt: :first,
        message: "Paragraph opens by announcing its topic.",
        suggestion: "Start with the first particular the paragraph gets to.",
        examples_bad: [
          "Caching is a widely used technique in software systems. Our service caches search results for 30 seconds. The hit rate on Tuesday was 91 percent. Misses go to Postgres.",
          "Incident response is a critical part of running any production service. The pager fired at 03:12. The on-call engineer restarted the queue consumer at 03:20. Backlog cleared by 03:41."
        ],
        examples_ok: [
          "Our service caches search results for 30 seconds. The hit rate on Tuesday was 91 percent. Misses go to Postgres, which held at 400 queries a second.",
          "The pager fired at 03:12. The on-call engineer restarted the queue consumer at 03:20. Backlog cleared by 03:41."
        ],
        rationale: "An opening sentence that tells the reader the topic matters, before saying anything about it, is a warm-up the writer needed and the reader did not. The weakest of the three paragraph rules, hence info."
      ),

      # ── sentence ────────────────────────────────────────────────────────────
      Rule.new(
        id: "stock-figure", category: "sentence", unit: :sentence, severity: "warning", confidence: "high",
        question: {
          "type" => "score",
          "instructions" => "Does `target` use figurative language, and if so, is the figure specific to this situation or a stock phrase?",
          "criteria" => [
            { "what" => "Uses a stock figure or idiom anyone could use about anything: shouting into the void, double-edged sword, low-hanging fruit, moving the needle, a journey, a landscape, unlock, navigate.",
              "examples" => ["The alert was shouting into an empty room.", "This unlocks a whole new landscape of possibilities."] },
            { "what" => "Uses a figure that could only have been made for this situation and that tells the reader something literal words would not.",
              "examples" => ["The renewal script was a smoke detector with the battery pulled.", "The RFC hums rather than votes."] },
            { "what" => "Uses no figurative language. Every word is literal.",
              "examples" => ["The certificate expired at 09:14 and the load balancer rejected every handshake.", "Nobody read the channel."] }
          ]
        },
        flag: { level: 0 },
        message: "Stock figure of speech.",
        suggestion: "Say the literal thing, or make a figure that only fits this case.",
        examples_bad: ["Migrating the auth service turned out to be a double-edged sword.", "We picked the low-hanging fruit first and moved the needle on latency."],
        examples_ok: ["Migrating the auth service cut login time by half and broke password reset for a day.", "The retry loop kept redialing a number the kernel had already disconnected."],
        rationale: "A figure anyone could use about anything tells the reader nothing about this case. Model prose reaches for the stock figure where human prose in these registers says the literal thing or makes a figure to fit."
      ),
      Rule.new(
        id: "no-news", category: "sentence", unit: :sentence, severity: "warning", confidence: "high",
        question: {
          "type" => "score",
          "instructions" => "Does `target` tell %{register} something they did not already know?",
          "criteria" => [
            { "what" => "Defines a term the reader owns, or explains something every reader of this kind already knows.",
              "examples" => ["A cache stores data so it can be served faster later.", "An RFC is a document published by the IETF."] },
            { "what" => "States something the reader could have guessed from the sentences before it, or a general truth that needed no saying.",
              "examples" => ["Outages are bad for customers.", "Consensus is important in standards work."] },
            { "what" => "Tells the reader a fact, number, decision, or reason they did not have before reading it.",
              "examples" => ["The renewal API changed on August 27 to require a new header.", "The chair may proceed when the objection is heard but not sustained."] }
          ]
        },
        flag: { level: 0 },
        message: "Explains what this reader already knows.",
        suggestion: "Cut it, or replace it with the fact this reader does not have.",
        examples_bad: ["A database index is a data structure that speeds up lookups on a column.", "Unit tests are small programs that check that a piece of code behaves as expected."],
        examples_ok: ["The composite index on (tenant_id, created_at) cut the dashboard query from 900 ms to 40 ms.", "The flaky test was reading the clock; pinning it to a fixed time fixed 30 of the 31 failures."],
        rationale: "A sentence that defines a term the reader owns is written for a reader who is not there. Model prose explains; human prose in these registers assumes. Never reversed in any register tested."
      ),
      Rule.new(
        id: "names-nothing", category: "sentence", unit: :sentence, severity: "warning", confidence: "high",
        question: {
          "type" => "score",
          "instructions" => "How concrete is `target`? Judge only what its nouns and verbs name.",
          "criteria" => [
            { "what" => "Names no specific thing. Its nouns are categories or abstractions such as process, factor, framework, aspect, solution, approach, value, experience, and its claim could be made about many different situations.",
              "examples" => ["This approach provides significant value across a range of use cases.", "It is important to consider the various factors involved in the process."] },
            { "what" => "Names the kind of thing it is about but not which one. A reader knows the topic but could not point to, count, or look up the thing.",
              "examples" => ["The service caches responses to reduce load on the database.", "Some users reported slow page loads after the update."] },
            { "what" => "Names a specific thing a reader could point to, count, look up, or check: a named system, a number, a date, a person, a quoted line, a particular event.",
              "examples" => ["The checkout API returned 503 for 47 minutes on March 3 after the TLS certificate for api.example.com expired.", "RFC 2119 defines MUST, SHOULD and MAY for use in standards text."] }
          ]
        },
        flag: { level: 0 },
        message: "Sentence names nothing specific.",
        suggestion: "Name the system, the number, the person or the event.",
        examples_bad: ["This approach delivers meaningful improvements across a variety of scenarios.", "Several factors contributed to the overall outcome of the initiative."],
        examples_ok: ["The search endpoint returned 503 for 47 minutes on March 3.", "Section 4.2 of RFC 7230 says a proxy MUST NOT forward a hop-by-hop header."],
        rationale: "A sentence whose nouns are all categories could be about anything, and reads as written by someone who was not there. Reverses in forum comments against current models, where a comment is allowed to name nothing; comments are outside the registers this tool is for."
      ),
      Rule.new(
        id: "ends-on-verdict", category: "sentence", unit: :sentence, severity: "info", confidence: "high",
        question: {
          "type" => "score",
          "instructions" => "How does `target` end? Look at its last clause and last word.",
          "criteria" => [
            { "what" => "Ends on a clause that evaluates, sums up, or draws a moral from what the sentence just said: a verdict, a flourish, or a restating tail such as which matters, making it clear, and that is the point.",
              "examples" => ["The alert fired but nobody saw it, which is the real lesson here.", "We shipped the fix in an hour, a clean, well-bounded failure with a clean, well-bounded fix."] },
            { "what" => "Trails off on a qualifier, an afterthought, or a weak word: a preposition, a pronoun, an adverb like though or however, or a parenthetical.",
              "examples" => ["The cache helped, at least somewhat, I think.", "It worked, though."] },
            { "what" => "Ends on the word or fact that carries the sentence.",
              "examples" => ["The certificate expired.", "The renewal script had been failing for three weeks."] }
          ]
        },
        flag: { level: 0 },
        message: "Sentence ends on a verdict about itself.",
        suggestion: "End on the fact. Cut the tail that grades it.",
        examples_bad: ["The queue drained in six minutes, which shows how much the right architecture matters.", "We rotated the key before the deadline, a small win that speaks to the team's discipline."],
        examples_ok: ["The queue drained in six minutes.", "We rotated the key at 16:40, twenty minutes before the deadline."],
        rationale: "A tail that tells the reader what to think of the fact just stated is the writer grading their own sentence. Human prose in these registers ends on the fact."
      ),
      Rule.new(
        id: "matched-shape", category: "sentence", unit: :sentence, severity: "info", confidence: "medium",
        question: {
          "type" => "score",
          "instructions" => "Is the shape of `target` chosen by its content or by a template? Look for matched pairs and triples.",
          "criteria" => [
            { "what" => "Built as a matched pair or triple whose parts are interchangeable or exist to complete the pattern: not A but B, no X no Y no Z, X and Y and Z where the items are near-synonyms or one is padding.",
              "examples" => ["It's not about speed, it's about trust.", "No hype, no jargon, no fluff.", "It was simple, elegant, and clean."] },
            { "what" => "Has a pair or list, but each item is a distinct thing the content needed and the order or count could not change without losing information.",
              "examples" => ["The migration dropped the column in production but not in staging.", "Frame Relay, AAL5 ATM and Ethernet over L2TPv3 all share this property."] },
            { "what" => "Has no matched structure. It states one thing in whatever shape the thing required.",
              "examples" => ["The alert posted to a Slack channel nobody read.", "Rough consensus lets a chair proceed over a small objection."] }
          ]
        },
        flag: { level: 0 },
        message: "Matched pair or triple shaped the content.",
        suggestion: "Keep the items the content needs and drop the one that completes the pattern.",
        examples_bad: ["The new pipeline is faster, simpler, and cleaner.", "It's not about the tooling, it's about the culture."],
        examples_ok: ["The new pipeline runs in four minutes instead of eleven.", "The migration dropped the column in production but not in staging."],
        rationale: "A pair or triple whose items are interchangeable was built to a rhythm, not to the content. This is a habit of one model family more than of the field, which is why the rule's confidence is medium: it separates strongly against current Claude models and barely against 2023 models."
      )
    ].freeze
  end
end
