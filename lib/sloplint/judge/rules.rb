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
    # flag: which answer makes a note. { level: 0 } for a score. The engine reads
    # only :level today; the noul shape in docs/JUDGE.md is what a first noul
    # rule adds back.
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
            { "what" => "The last sentence restates what the paragraph already said, sums it up, draws a general moral from it, or closes on a general hope or forecast that names nothing; it tells the reader nothing new.",
              "examples" => ["...Together, these factors make it a place worth visiting.", "...Ultimately, the decision reflects a broader shift in priorities.", "...Despite these challenges, the project's future looks promising."] },
            { "what" => "The last sentence adds a small qualification or a transition to what comes next.",
              "examples" => ["...Whether that holds in winter is another question.", "...The second problem is harder."] },
            { "what" => "The last sentence states a new fact, a particular, a number, a quote or a concrete consequence.",
              "examples" => ["...The fine was $2,400.", "...He was arrested at the airport on Tuesday."] }
          ]
        },
        flag: { level: 0 }, excerpt: :last,
        message: "Paragraph ends on a summary, a moral or a hope.",
        suggestion: "Cut the last sentence, or end on the fact.",
        examples_bad: [
          "The migration moved 40 tables in two weekends. Two of them needed manual fixes for timezone columns. The rollback plan was tested once on staging. Overall, careful planning made the migration a success.",
          "The parser rejects any line over 4,096 bytes. Longer lines come from the log shipper concatenating retries. We capped retries at three. In the end, understanding the root cause was what mattered most.",
          "The exporter drops any metric with more than 30 labels. Two of the billing dashboards went blank after the cardinality limit landed. The team rewrote both queries against the aggregated series. Despite these setbacks, the future of the metrics platform looks bright."
        ],
        examples_ok: [
          "The migration moved 40 tables in two weekends. Two of them needed manual fixes for timezone columns. The rollback plan was tested once on staging. Rollback took four minutes.",
          "The parser rejects any line over 4,096 bytes. Longer lines come from the log shipper concatenating retries. We capped retries at three and the rejections stopped on the 14th.",
          "The exporter drops any metric with more than 30 labels. Two of the billing dashboards went blank after the cardinality limit landed. The team rewrote both queries against the aggregated series. Despite these setbacks, the replacement exporter ships on October 3."
        ],
        rationale: "A paragraph that closes on a summary of itself tells the reader nothing they did not have one sentence earlier. Human prose in the registers this tool is for closes on a fact or a consequence; model prose closes on a moral."
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
        rationale: "An opening sentence that tells the reader the topic matters, before saying anything about it, is a warm-up the writer needed and the reader did not. Humans do it too, abstracts especially, which is why this is info and not warning; it is dead weight either way."
      ),
      Rule.new(
        id: "same-weight", category: "paragraph", unit: :paragraph, severity: "info", confidence: "low",
        question: {
          "type" => "score",
          "instructions" => "Does this paragraph mark which of its sentences are facts, which are inferences and which are the writer's opinions, for %{register}?",
          "criteria" => [
            { "what" => "It mixes facts, inferences and opinions and marks none of them: a guess or a judgment is stated as flatly as a measurement, with no probably, we think, likely, and no reason or evidence given for it, and every sentence is a conclusion.",
              "examples" => ["The outage was caused by the cache. The cache had been misconfigured for months. Nobody noticed because monitoring was inadequate. This is a systemic failure. The fix is straightforward."] },
            { "what" => "It mixes kinds of claim and marks some: one inference or opinion is flagged as such, the rest are flat.",
              "examples" => ["The outage was probably caused by the cache. The cache had been misconfigured for months. Nobody noticed. This is a systemic failure."] },
            { "what" => "Every inference and opinion is marked as such or comes with its reason or evidence in the paragraph, or the paragraph is only facts, steps or events with no inference or opinion in it.",
              "examples" => ["The cache returned stale entries for 40 minutes; that is in the logs. We think the misconfiguration dates from the March deploy, though nobody has confirmed it.", "Set the flag to false. Restart the worker. Check the queue depth after five minutes."] }
          ]
        },
        flag: { level: 0 }, excerpt: :all,
        message: "Every sentence carries the same weight.",
        suggestion: "Say which claims are measured and which are guesses, and give the judgment its evidence.",
        examples_bad: [
          "The deploy broke checkout. The root cause was the schema change. The schema change was not reviewed properly. Review practices need to improve. Customers were affected for an hour.",
          "The new index made the query fast. The old plan was doing a full scan. Full scans are a sign of a missing index. The team should audit the other tables. This will prevent future incidents."
        ],
        examples_ok: [
          "Checkout returned 500 for 58 minutes; that is in the load balancer logs. The schema change at 14:02 is the likely cause, since the errors start two minutes after it, but we have not reproduced it in staging. If it is the cause, the two other services on the same table are exposed too.",
          "Create the index concurrently so the table stays writable. Watch pg_stat_progress_create_index until it finishes. Then run the dashboard query once and compare the plan."
        ],
        rationale: "A paragraph in which a measurement, an inference and an opinion all arrive as flat conclusions gives the reader no way to weigh any of it. Human prose in these registers marks its guesses and gives its judgments a reason; model prose delivers every sentence at the same certainty. The escape clause for paragraphs that are only facts, steps or events is the fairness narrowing: a reference page is flat by design. Low, so off by default: a design document argues in flat sentences on purpose."
      ),

      Rule.new(
        id: "self-narration", category: "paragraph", unit: :paragraph, severity: "info", confidence: "medium",
        question: {
          "type" => "score",
          "instructions" => "Does this paragraph say something about its subject, or does it signpost the document, for %{register}?",
          "criteria" => [
            { "what" => "Most sentences signpost: they tell the reader what this text will do, is doing or has done, what comes first and next, what a section covers, what the reader should take from it. Not a paragraph whose subject happens to be documents or writing.",
              "examples" => ["This section describes the approach. First we outline the constraints. Next we present the design. Finally we discuss the trade-offs, which the reader should keep in mind."] },
            { "what" => "The paragraph says something about its subject. At most one sentence signposts; the rest carry facts, decisions, rules or events, and a style guide's rules about documents count as its subject.",
              "examples" => ["Two constraints shaped the design. The queue had to survive a region loss, and no message could be delivered twice. The rest of this section is about the second one.", "The queue had to survive a region loss, and no message could be delivered twice. The first ruled out a single Redis. The second ruled out at-least-once delivery without an idempotency key."] }
          ]
        },
        flag: { level: 0 },
        excerpt: :all,
        message: "Paragraph narrates the document instead of saying something.",
        suggestion: "Cut the signposts and start with the first fact.",
        examples_bad: [
          "This document is organised as follows. The first part sets out the background. The second part walks through the proposed change. The final part covers open questions, which we return to at the end.",
          "In this section we explain the migration plan. We begin by describing the current state. We then outline each step in order. We close with the rollback procedure, which readers should review carefully.",
          "The users table has 40 million rows. What follows describes how it moves. The steps are given in the order they run. Each step names the check that must pass before the next one starts, and the reader should note where the rollback points are."
        ],
        examples_ok: [
          "Three things have to move: the users table, the sessions cache and the cron jobs that read both. The table goes first because the cache is rebuilt from it. The cron jobs move last, after a week of both stores running side by side.",
          "The rollback is one command. It repoints the alias at the old index and leaves the new one in place. Nothing is deleted until the alias has sat on the old index for a day."
        ],
        rationale: "A paragraph whose sentences are about the document, what comes first, what a section covers, what the reader should take away, tells the reader nothing about the subject; it is a table of contents in prose. throat-clearing sees only the first sentence; this rule is for the paragraph whose bulk is signposting. Two levels, so the score is the probability of the flag and nothing else, and the one-sentence signpost every section opens with sits on the clean side by name. Abstracts and the introductions to standards signpost by convention, so it starts at info."
      ),

      Rule.new(
        id: "promotional", category: "paragraph", unit: :paragraph, severity: "warning", confidence: "medium",
        question: {
          "type" => "score",
          "instructions" => "How does this paragraph evaluate its subject, for %{register}?",
          "criteria" => [
            { "what" => "Every evaluative word is favorable, nothing is measured against anything, and no drawback, cost or failure appears.",
              "examples" => ["The platform offers a robust and flexible foundation. Teams benefit from its intuitive design and strong community. It continues to evolve to meet modern needs."] },
            { "what" => "Evaluation is absent, or a judgment comes with the measure behind it, or a drawback, cost or failure is in the paragraph.",
              "examples" => ["The platform is robust and flexible. Cold starts are slow, around two seconds, but teams find the design intuitive.", "p99 latency is 120 ms on the benchmark in the repo. Cold starts are two seconds, which rules it out for the webhook path. The maintainers closed 40 of 52 issues filed this year."] }
          ]
        },
        flag: { level: 0 },
        excerpt: :all,
        message: "Paragraph praises its subject and measures nothing.",
        suggestion: "Give the number behind one claim and name one drawback.",
        examples_bad: [
          "The new scheduler is a powerful and elegant addition to the platform. It delivers excellent throughput while remaining simple to operate. Teams across the organisation are already seeing the benefits.",
          "The library provides a clean, modern interface for working with queues. Its thoughtful design makes common tasks effortless. It is a great fit for projects of any size."
        ],
        examples_ok: [
          "The new scheduler moves 12,000 jobs a minute on the staging cluster, up from 4,000. It needs a Redis 7 instance of its own, which is a new cost. Two teams have moved to it; the billing team is waiting on the retry fix.",
          "The library wraps the queue API in about 400 lines. Enqueue, dequeue and ack are one call each. It does not do scheduling or priorities; if you need those, use the vendor's client."
        ],
        rationale: "A paragraph in which every judgment is favorable, none is measured and no cost appears is copy, whatever it is attached to. The regex catalog's puffery-words sees the watch words; this rule sees the paragraph that is positive without any of them. Two levels, so the score is the probability of the flag. A README is allowed to like its project, so the clean side is wide: one measure or one drawback anywhere in the paragraph is enough. Warning because no human paragraph in news or abstracts flagged and model paragraphs did in both; medium because the question has two parts."
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
        rationale: "A sentence that defines a term the reader owns is written for a reader who is not there. Model prose explains; human prose in these registers assumes."
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
        rationale: "A sentence whose nouns are all categories could be about anything, and reads as written by someone who was not there."
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
        id: "trailing-gloss", category: "sentence", unit: :sentence, severity: "info", confidence: "medium",
        question: {
          "type" => "score",
          "instructions" => "Does `target` end on a participial clause, and if so what does the clause do, for %{register}?",
          "criteria" => [
            { "what" => "The sentence ends on a comma and an -ing clause that interprets what came before it, with the event or fact as its subject: something highlights, reflects, underscores, signals or demonstrates a broader point the sentence did not establish.",
              "examples" => ["Latency fell by half after the change, demonstrating the team's commitment to performance.", "The library gained 2,000 stars in a month, reflecting growing interest in local-first tools."] },
            { "what" => "No such clause: the sentence ends on no participial clause, or its trailing clause adds a fact or a consequence, or its subject is a person or thing doing something.",
              "examples" => ["Latency fell by half after the change, freeing enough budget to drop the second replica.", "She left at noon, taking the only key with her.", "The library gained 2,000 stars in a month."] }
          ]
        },
        flag: { level: 0 },
        message: "Sentence ends on an -ing clause that draws its own moral.",
        suggestion: "Cut the clause, or make the point its own sentence with a fact in it.",
        examples_bad: [
          "The queue drained in six minutes, highlighting the value of the new architecture.",
          "Adoption doubled in the second quarter, underscoring the growing importance of developer experience."
        ],
        examples_ok: [
          "The queue drained in six minutes, leaving the consumers idle until the next batch.",
          "Adoption doubled in the second quarter, driving the support backlog past 400 tickets."
        ],
        rationale: "A sentence that ends on a comma and an -ing clause whose subject is the fact just stated, and whose verb interprets it (highlighting, reflecting, underscoring), is the writer tacking a moral onto a fact. The regex catalog's trailing-significance-participle sees only a short list of verbs; the construction turns on what the clause does, which is a reading. Two levels, gloss or not, so the score is the probability of the gloss and nothing else. Medium because the question has two parts, and info because the trailing clause that adds a consequence is fine and the model has to tell the two apart."
      ),
      Rule.new(
        id: "unnamed-authority", category: "sentence", unit: :sentence, severity: "info", confidence: "medium",
        question: {
          "type" => "score",
          "instructions" => "If `target` attributes a claim to someone, who, for %{register}?",
          "criteria" => [
            { "what" => "To an authority the reader could not find and that speaks for nobody in particular: experts, studies, research, observers, analysts, critics, fans, pundits, many, some, it is widely believed.",
              "examples" => ["Experts agree that the migration reduced operational risk.", "Studies show that smaller pull requests get better reviews.", "Many believe the old scheduler was the real bottleneck."] },
            { "what" => "To a named person, body, document or dataset the reader could go to, or to a source that speaks for a body and the register quotes by convention (officials, a spokesperson, the company, a court, police), or to prior work in a register that keeps its citations elsewhere (an abstract's existing methods, previous studies), or the sentence makes the claim in its own voice.",
              "examples" => ["The April postmortem counts three fewer pages a week since the migration.", "A spokesperson for the airline said the flight was cancelled because of crew hours.", "The migration reduced pages from nine a week to six."] }
          ]
        },
        flag: { level: 0 },
        message: "Claim attributed to someone the reader cannot find.",
        suggestion: "Name the source, or say it yourself.",
        examples_bad: [
          "Research suggests that teams with a single on-call rotation recover faster.",
          "Many in the industry expect event-driven designs to dominate within a few years."
        ],
        examples_ok: [
          "The 2024 DORA report puts the median recovery time for teams with one rotation at under an hour.",
          "Officials said the bridge would stay closed until the inspection was complete.",
          "Existing methods segment the vessel tree slice by slice and lose the branching structure between slices."
        ],
        rationale: "A claim handed to experts, studies or many is a claim the reader cannot check and the writer has not owned. The regex catalog's vague-attribution sees three fixed frames; this is the reading of who is being cited, so \"studies show\" and \"research suggests\" and a bare \"many believe\" are caught and a source the register names by convention, officials, a spokesperson, the company, is not. Two levels. Info because news attributes to unnamed officials by convention, and an abstract to prior work, and the rule must let both through."
      ),
      Rule.new(
        id: "stated-stakes", category: "sentence", unit: :sentence, severity: "info", confidence: "low",
        question: {
          "type" => "score",
          "instructions" => "If `target` says something matters, does it say why, for %{register}?",
          "criteria" => [
            { "what" => "It asserts importance, centrality or consequence (crucial, critical, central, vital, essential, key, matters, shapes everything that follows) and gives no fact, number or consequence that shows it.",
              "examples" => ["Getting the retry policy right is critical to the success of the whole system.", "Observability is essential for any modern platform."] },
            { "what" => "It states the consequence and lets the reader weigh it, or points to where the reason is, or the sentence right after it in the paragraph gives the reason, or it makes no importance claim: a rule, a requirement, a fact or a signpost is not a claim of importance, and quoted speech belongs to the speaker, not the writer.",
              "examples" => ["A retry policy without jitter took the payment service down twice in March.", "The retry policy matters more than it looks, for reasons the next section covers.", "Both pieces are required.", "The retry policy is three lines in config/queue.yml.", "\"It is an important period for the club and I am concentrating on that,\" he said."] }
          ]
        },
        flag: { level: 0 },
        message: "Sentence says this matters and not why.",
        suggestion: "Replace the importance claim with the consequence.",
        examples_bad: [
          "Choosing the right serialization format is crucial for the long-term health of the platform.",
          "Documentation plays a vital role in the success of any engineering organisation."
        ],
        examples_ok: [
          "The serialization format is the one thing we cannot change after launch, because every client pins it.",
          "Nobody could find the runbook during the March outage, so the page took 40 minutes to route.",
          "The serialization format matters more than anything else in this design. Every client pins it, so it cannot change after launch.",
          "\"This is a massive game for us and everyone knows what is at stake,\" the captain said."
        ],
        rationale: "A sentence that says a thing is crucial, vital or central and gives nothing to weigh asks the reader to take the stakes on trust. The sentence after it counts: a design document often states the stakes in one sentence and the reason in the next, and the model sees the paragraph. Human prose in these registers states the consequence and lets it carry the weight. ends-on-verdict flags a sentence that ends on a judgment of the fact it just stated; this is the importance claim, wherever it sits and whether or not a fact follows. Two levels."
      ),
      Rule.new(
        id: "matched-shape", category: "sentence", unit: :sentence, severity: "info", confidence: "low",
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
        rationale: "A pair or triple whose items are interchangeable was built to a rhythm, not to the content. Off by default: it separates strongly against current Claude models and barely against 2023 models, which is a tell of one model family, and much of what it flags in documentation is a parallel the writer built on purpose."
      ),
      Rule.new(
        id: "mirrored-opposites", category: "sentence", unit: :sentence, severity: "info", confidence: "low",
        question: {
          "type" => "score",
          "instructions" => "Does `target` set opposite words against each other (everywhere and nowhere, always and never, every and none, loud and silent), and if so, are the opposites comparing one thing or stitching two claims together, for %{register}?",
          "criteria" => [
            { "what" => "Two different claims are joined by opposite words so that they read as a contrast. The opposition is between the words, not between the facts: the second claim said plainly (not, isn't, nobody, not anywhere) would tell the reader exactly as much.",
              "examples" => ["The retry logic is identical everywhere it runs and documented nowhere.", "The dashboard is always open and never checked.", "Every team cites the style guide and none of them has read it."] },
            { "what" => "The opposites compare the same thing across cases the reader needs to tell apart (the same action in two places, the same cost at two stages, before and after), or the sentence has no opposites set against each other.",
              "examples" => ["The job runs every night in staging and never in production.", "The cache is cheap to build and expensive to run.", "Nobody has documented the retry logic.", "The alert posted to a channel nobody read."] }
          ]
        },
        flag: { level: 0 },
        message: "Opposite words make two separate claims read as a contrast.",
        suggestion: "Say the claim that matters plainly and drop the half that only sets it up.",
        examples_bad: [
          "The naming convention is followed in every service and written down in none.",
          "The feature flag is respected by every client and owned by no one."
        ],
        examples_ok: [
          "The migration runs nightly in staging and never in production.",
          "Reads return in two milliseconds; writes can block for a full second.",
          "Nobody wrote the naming convention down."
        ],
        rationale: "Setting everywhere against nowhere, or always against never, makes two unrelated facts sound like one finding. The reader learns nothing from the mirror: 'identical everywhere it runs and documented nowhere' says what 'identical, but not documented' says. Opposites that compare one thing in two cases, a job that runs in staging and not in production, carry the contrast in the facts and are fine. matched-shape flags any pair built to a rhythm; this is the narrower case where the pair is a pair of opposites."
      ),
      Rule.new(
        id: "maxim", category: "sentence", unit: :sentence, severity: "info", confidence: "medium",
        question: {
          "type" => "score",
          "instructions" => "Is `target` a saying: a general rule about how people, teams or systems always behave, where %{register} wants the fact about this case?",
          "criteria" => [
            { "what" => "A saying. It states how things always go for anyone, in a turned phrase that could be lifted out and quoted on its own: every X is Y until Z, nobody does X until Y, you learn X the day Y, X stops being Y the moment Z, the X you Y is the one that Z. It is still a saying when the sentences around it are the example that illustrates it, or when it is about people rather than code.",
              "examples" => ["A cache you never invalidate is a bug you haven't met yet.", "Nobody values a backup until the day they need a restore.", "Every quick fix becomes a permanent one.", "The meeting you skip is the one where they decide."] },
            { "what" => "Not a saying. It states a fact about this system, team or event; or it says in plain words how a particular tool, protocol, data structure or piece of code behaves, which a reader could test; or it is a step, a requirement or a decision.",
              "examples" => ["The queue holds 40,000 messages before the broker starts rejecting writes.", "A TCP connection in TIME_WAIT holds its port for twice the maximum segment lifetime.", "Writes to the ledger must be append-only, so a correction is a new row.", "Priya owns the billing client."] }
          ]
        },
        flag: { level: 0 },
        message: "Sentence states a saying where the fact belongs.",
        suggestion: "Cut the saying and let the fact beside it make the point, or replace it with the fact.",
        examples_bad: [
          "A dashboard nobody looks at is a postmortem waiting to happen.",
          "The rollback you never test is the one that fails when you need it."
        ],
        examples_ok: [
          "The dashboard for queue depth has had no viewers in the last 90 days.",
          "Adding a column with a volatile default rewrites the whole table in Postgres."
        ],
        rationale: "A sentence that reaches for a general rule about how things always go tells the reader nothing about this case, whatever specific sentences sit next to it. The maintainer's standard: refer to the thing as anything other than the thing, and the reader's time is wasted. Medium because the question turns on the sentence's shape, a turned phrase that could stand alone, not on a fixed list of words, and a plain general statement of fact ('adding a volatile-default column rewrites the table') has to be told apart from an aphorism with the same short, declarative build."
      )
    ].freeze
  end
end
