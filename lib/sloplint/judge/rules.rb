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
            { "what" => "Defines a term the reader owns, or explains something every reader of this kind already knows, or tells the reader, in the second person, about their own past actions or their own past words — something they know because they did it or said it, however specific.",
              "examples" => ["A cache stores data so it can be served faster later.", "An RFC is a document published by the IETF.", "You led the payments migration and then ran the platform team for two years.", "You said yourself the on-call load is the main reason to move."] },
            { "what" => "States something the reader could have guessed from the sentences before it, or a general truth that needed no saying.",
              "examples" => ["Outages are bad for customers.", "Consensus is important in standards work."] },
            { "what" => "Tells the reader a fact, number, decision, or reason they did not have before reading it.",
              "examples" => ["The renewal API changed on August 27 to require a new header.", "The chair may proceed when the objection is heard but not sustained."] }
          ]
        },
        flag: { level: 0 },
        message: "Explains what this reader already knows.",
        suggestion: "Cut it, or replace it with the fact this reader does not have.",
        examples_bad: ["A database index is a data structure that speeds up lookups on a column.", "Unit tests are small programs that check that a piece of code behaves as expected.", "You led the payments migration and then ran the platform team for two years.", "You said yourself the on-call load is the main reason to move."],
        examples_ok: ["The composite index on (tenant_id, created_at) cut the dashboard query from 900 ms to 40 ms.", "The flaky test was reading the clock; pinning it to a fixed time fixed 30 of the 31 failures.", "You will need a staging account before Monday.", "Rotate the on-call key before Friday's handoff."],
        rationale: "A sentence that defines a term the reader owns is written for a reader who is not there. Model prose explains; human prose in these registers assumes. The same goes for reading a reader's own past back to them: a fact is not news just because it is specific, if the reader is the one who lived it."
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
        id: "positive-form", category: "sentence", unit: :sentence, severity: "info", confidence: "low",
        question: {
          "type" => "score",
          "instructions" => "Does `target` make its claim by saying what is, or by saying what is not, for %{register}? Judge the claim the sentence makes, not every negative word in it.",
          "criteria" => [
            { "what" => "The claim is carried by a negative. The sentence says what something is not in place of what it is. Or it corrects with not, rather than, instead of, or isn't X, it's Y, anywhere in the sentence, including a trailing or subordinate clause (because it is A rather than B; which is A, not B). Or it makes nothing, nobody, none or no X its subject, or nothing or nobody its object. Or its verb performs an absence: it gives an act to something that nobody did (publishes no figure, shows no incident, lists no changes, records nothing, offers no support), where the absence could be stated as a property of the thing. Or it denies something so that the next sentence can give the positive. Or it tells the reader what not to do. The reader has to work out what is true from what is denied.",
              "examples" => ["The retry queue is a buffer, not a store.", "Nothing about the schema changes.", "The vendor publishes no uptime figure.", "The audit shows no finding for the payments service.", "Do not mention the cutover date in the release note.", "The problem isn't the index, it's that the query scans every partition.", "Two services write to the table, which is by design rather than an oversight."] },
            { "what" => "The claim is carried by a positive statement: the sentence says what is, has or does. It has no negative, or its negative sits outside the claim: in a condition (unless, if not), a bound (no more than, zero rows), a fixed name (non-blocking, NOT NULL, 404 Not Found), or a requirement keyword in a standard (MUST NOT). Or the sentence says in so many words that it states an assumption or a decision (we assume, we chose) and names the option it rules out. Or the sentence states an absence as a property of the thing, with has no, there is no or without (the batch API has no SLA; the export ships without a schema file). Or it denies a behavior the reader would expect, stated on its own, not set against another option in the same sentence (does not retry, will not overwrite). Or it is a courtesy line that releases the reader from an action (no need to reply). Or the sentence reports someone's words in quotation marks: a quoted denial belongs to the speaker, not the writer, whatever it says.",
              "examples" => ["The retry queue keeps each message for seven days.", "We assume the export runs nightly rather than hourly.", "The client gives up after no more than three attempts.", "If the token is not set, the CLI reads it from the keychain.", "The vendor's API has no published uptime figure.", "The CLI does not overwrite an existing config file.", "No need to RSVP if you already signed up.","\"The fix is not ready,\" the lead said."] }
          ]
        },
        flag: { level: 0 },
        message: "Says what isn't where it could say what is.",
        suggestion: "Say what is there instead, or state the absence as a property of the thing (has no, without).",
        examples_bad: [
          "The sidecar is a proxy, not a cache.",
          "The changelog lists no breaking changes for 4.0.",
          "The worker retries the failed chunk, not the whole upload.",
          "Nobody on the platform team owns the deploy script.",
          "Don't page the database team for replica lag."
        ],
        examples_ok: [
          "We assume the importer runs once a day rather than on every upload.",
          "We chose Postgres rather than DynamoDB because the reports need joins.",
          "If the lock is not released within 30 seconds, the worker exits.",
          "Each upload holds no more than 200 files.",
          "The email column is declared NOT NULL and indexed.",
          "A client MUST NOT reuse a nonce within the same session.",
          "\"We are not shipping on Friday,\" the release manager said.",
          "The batch endpoint has no rate limit.",
          "The client does not retry a failed upload.",
          "No need to reply if this doesn't apply to you."
        ],
        rationale: "A sentence that says what a thing is not makes the reader work out what it is, and a model reaches for the denial because it sounds decisive without having to know the positive fact. The corrective (a buffer, not a store) sets up a contrast nobody raised. A sentence whose subject is nothing or nobody, or an instruction about what not to do, names the gap and leaves the reader to fill it. The regex rules not-x-but-y, isnt-x-its-y and not-nothing see a few fixed frames of this; this rule reads where the negative sits, so a negative inside a condition, a bound, a fixed name, a standard's MUST NOT or quoted speech passes, and so does a stated assumption or decision that names the option it rules out. mirrored-opposites flags opposite words that make two claims read as one; this is any claim made by denial. Off by default: reference documentation states limits as negatives on purpose (not supported, not encrypted, cannot be used with), and most of what the rule flags there is a limit the reader needs."
      ),
      Rule.new(
        id: "name-the-thing", category: "sentence", unit: :sentence, severity: "info", confidence: "low",
        question: {
          "type" => "score",
          "instructions" => "Does `target` call things by their names, or does it make %{register} map a pointer back to a name?",
          "criteria" => [
            { "what" => "Refers to something by anything other than its name when a name exists or is available. It picks a thing out by position, order or number in a list (the former, the latter, the first one, the second one, the last of three, the fourth item, the third alert), even when the list was just named; or it uses a stand-in noun or a figure for a named thing (the engine for a named service, the seat for a named role); or it rests its point on an allusion to a divide it never names (which side, which end or which slot someone is on, where someone stood when a system changed) or on the document pointing at itself ('this entire writeup', 'this entire proposal') standing in for a point it never states. The reader has to map the pointer back to a name. One pointer is enough: a sentence full of names still flags if one clause in it points instead of naming, such as an \"only the latter\" after a semicolon or a trailing \"which is this entire writeup\" after a list of facts.",
              "examples" => ["We tried Kafka and SQS, and the latter needed no cluster to run.", "Both jobs read the same table; only the former writes to it.", "The third alert on that dashboard is the only one worth waking up for.", "We run the ledgerd service in two regions, and the engine is the thing that pages us.", "Hiring managers care where you stood when the monolith was split.", "The March outage, which is this entire proposal in a single afternoon."] },
            { "what" => "Names what it means. A position word is fine only when the position is the thing's own name (step 4 of the runbook, the second retry, Q3, the first argument). A which-clause that asks about named things (which region, which port, which of the two replicas) is fine. An ordinary pronoun (it, they, this, these) pointing back to something named in the same or the previous sentence, or at a code sample or list beside it, is fine.",
              "examples" => ["SQS needed no cluster to run.", "Step 4 of the runbook restarts the consumer.", "The second retry waits thirty seconds.", "Which region you deploy to decides the latency floor.", "The on-call engineer decides which of the two replicas to promote.", "The ingest worker reads from the events queue. It restarts every night.", "You can stub a method like this:"] }
          ]
        },
        flag: { level: 0 },
        message: "Sentence points at something instead of naming it.",
        suggestion: "Write the name: the service, the option, the role or the point itself.",
        examples_bad: [
          "Whether you trust the new alerting depends on where you stood when the old scheduler went away.",
          "We load-tested Envoy and HAProxy last month, and the latter held 40,000 connections without tuning.",
          "Payments run on a Rust service called tallyd, and the engine has not been patched since June."
        ],
        examples_ok: [
          "Step 4 of the runbook drains the queue before the consumer restarts.",
          "Which availability zone the replica lands in decides whether it survives a zone outage.",
          "Register the retry hook in the initializer like this:",
          "The ingest worker reads from the events queue, and it restarts every night at 02:00 UTC."
        ],
        rationale: "The latter, the second one, the engine, where you stood when the old scheduler went away, this entire writeup: each makes the reader map a pointer back to a name the writer had and did not write. Naming the thing costs a word or two and saves the reader the lookup, even when the list was named one clause earlier. A position that is the thing's own name (step 4, the second retry, Q3) is a name, and a pronoun pointing at something just named is ordinary grammar; both pass. The-x-is-not-the-x catches the repeated-noun case; this is the general one."
      ),
      Rule.new(
        id: "stand-in-verb", category: "sentence", unit: :sentence, severity: "info", confidence: "low",
        question: {
          "type" => "score",
          "instructions" => "Does `target` say what someone does with a plain verb, or does it dress the act in a figure of holding, carrying or keeping that %{register} has to translate back?",
          "criteria" => [
            { "what" => "The main verb phrase is a figure of holding, carrying or keeping whose object is something that cannot be held, such as a history, the context on a system, a mandate or a story (holds the history of a job, carries the context on a service, keeps the story of a decision), standing in for a plain verb such as knows, wrote, decides, runs or has hired. It is still a figure when the subject is a negative or a group (nobody holds, two people carry).",
              "examples" => ["Only Marco still carries the context on the ingest scheduler.", "Nobody left on the team holds the history of the billing schema."] },
            { "what" => "The verbs are plain, or a verb of holding or carrying is used in its literal or ordinary technical sense (holds a lock, carries a header, owns the service, keeps a copy, gives up after three retries). A sentence whose only oddity is somewhere other than its main verb, such as a negative subject or a vague noun, passes here.",
              "examples" => ["The worker holds a row lock until the transfer commits.", "Each request carries the tenant ID in a header.", "Nobody on the team has reviewed the migration yet.", "Marco knows how the ingest scheduler picks its batch size."] }
          ]
        },
        flag: { level: 0 },
        message: "Sentence dresses a plain verb in a figure of holding or carrying.",
        suggestion: "Write the plain verb: knows, wrote, decides, runs.",
        examples_bad: [
          "Priya carries the context on the billing reconciler, so page her first.",
          "Two people on the support rotation hold the story of how the refund flow got its retry cap.",
          "No one on the platform team keeps the story of why the cache TTL is ninety seconds."
        ],
        examples_ok: [
          "The worker holds a row lock on the ledger table until the transfer commits.",
          "Each request carries the tenant ID in the X-Tenant header.",
          "The platform team owns the deploy script and reviews every change to it.",
          "Nobody on the platform team has read the new runbook yet."
        ],
        rationale: "'Holds the history of the job' says knows or wrote in a figure, and the reader has to take the figure apart to find the act: who knows what, who wrote it, who decides. The figure sounds weightier than the plain verb and says less, since it never commits to which act it means. A verb of holding or carrying in its literal or technical sense (holds a lock, carries a header) is the plain verb and passes. name-the-thing catches the same move made with a noun."
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
        rationale: "A sentence that reaches for a general rule about how things always go tells the reader nothing about this case, whatever specific sentences sit next to it. Medium because the question turns on the sentence's shape, a turned phrase that could stand alone, not on a fixed list of words, and a plain general statement of fact ('adding a volatile-default column rewrites the table') has to be told apart from an aphorism with the same short, declarative build."
      ),
      Rule.new(
        id: "dressed-pair", category: "sentence", unit: :sentence, severity: "info", confidence: "low",
        question: {
          "type" => "score",
          "instructions" => "Does `target` state its facts plainly, or does it dress them up as a matched pair? Judge only the words of `target`; earlier sentences are context.",
          "criteria" => [
            { "what" => "Dresses a plain fact up as a pair. Either the second clause gives a second subject the first clause's verb and adds little beyond a tie back to the first (X deploys and Y deploys with it, A restarts and B restarts on its own), so the fact reads as a parallel when the plain version is one clause; or it sums up two things set out in earlier sentences as both, those two things or the two, and then gives that sum a verdict (is the real work, is the whole point, is what matters).",
              "examples" => ["The release goes out and the on-call week goes out with it.", "The API falls over and the status page falls over right behind it.", "One team writes the schema and the other reads it, and keeping those two things in step is the whole job."] },
            { "what" => "States its facts plainly. A pair whose halves carry different facts (reads go to the replica, writes go to the primary), a choice between two named options (either team can own it), a both that says what is true of two named things, even more than once, with no verdict on the pair, a pairing of groups with roles the paragraph already defined, or no pair at all.",
              "examples" => ["The on-call engineer ships with each release.", "Either the web team or the mobile team can take the bug.", "Staging and production both run the same image, and both restart at midnight.", "Teams that own a database get the pager; teams that only read from one get the digest.", "The alert posted to a Slack channel nobody read."] }
          ]
        },
        flag: { level: 0 },
        message: "Sentence dresses a plain fact up as a matched pair.",
        suggestion: "Say it once: what the second thing does, or what the two things are and what follows.",
        examples_bad: [
          "The schema changes, and the client changes right along with it, and the question every migration still leaves open is who finds out first.",
          "A cache stores what the database returns. A queue holds what the writer sends. This service does both, and keeping those two things apart is the whole trick."
        ],
        examples_ok: [
          "Reads go to the replica and writes go to the primary.",
          "Either the database team or the platform team can own the failover runbook.",
          "We run Postgres for orders and Redis for sessions. Both sit behind the same VPC and both are backed up nightly.",
          "Contractors get read access. Employees get write access."
        ],
        rationale: "Two ways of saying one fact as if it were two. The first echoes a verb: 'the release goes out and the on-call week goes out with it' is 'the on-call engineer ships with the release' set to a rhythm. The second sums up a pair as 'both' or 'those two things' and hands the sum a verdict, 'is the whole job', which names neither thing and tells the reader nothing the two sentences before it did not. A pair whose halves carry different facts, a plain 'both', and a pairing of groups with roles the paragraph defined are the facts themselves and pass. matched-shape flags pairs built to a rhythm in general; name-the-thing flags a pair pointed at by position or figure; this is the pair restated instead of named."
      ),
      Rule.new(
        id: "device-before-claim", category: "sentence", unit: :sentence, severity: "info", confidence: "medium",
        question: {
          "type" => "score",
          "instructions" => "Look at `target` inside its paragraph. Does it make its claim through a device - opposites or a matched pair set against each other, a noun repeated to pose a riddle, singling out one item's place in a list or order as the one that matters, the sentence that finally tells %{register} what the specifics before it add up to, a coined figure, or a maxim that generalizes or restates the paragraph's point - or does it state the claim plainly, as one more fact among the others?",
          "criteria" => [
            { "what" => "The sentence is a device: opposites or a matched pair set against each other (everyone and nobody, always and never, the frontend ships one thing and the backend ships another); a noun or phrase repeated to pose a riddle; singling out one item's position in a list or order, the second one, the last one, the fourth item, as the one that actually matters; the payoff sentence that tells the reader what a run of specifics before it adds up to; a coined figure; or a maxim, a general rule stated as if it simply follows, that sums up or restates the point the paragraph was already making. It reads as a turn or a landing, not as one more fact.",
              "examples" => ["The retry logic is identical everywhere it runs and documented nowhere.", "The frontend team ships the button and the backend team owns the endpoint, and neither one works without the other.", "The third name on the escalation list is the one who actually picks up.", "A deploy that never gets rolled back was never really tested."] },
            { "what" => "The sentence states its claim directly, as one more fact in the paragraph, with no matched pair, no riddle, no singled-out position, no payoff over a run of specifics, and no maxim.",
              "examples" => ["Nobody has documented the retry logic.", "The frontend team ships the button and the backend team ships the endpoint; both went out this morning.", "The third name on the escalation list is the database team's manager.", "This deploy has never been tested under real failure."] }
          ]
        },
        flag: { level: 0 },
        message: "Sentence makes its claim through a device.",
        suggestion: "Check whether the device carries anything a plain statement of the claim would not.",
        examples_bad: [
          "The cache holds the last hour of queries once it's warm. A cold instance rebuilds that from scratch on every request. The service is fast for the cache that's warm and slow for the one that's cold.",
          "We wrote a rollback plan before the migration ran. It covers every table we're touching. A migration that needs a rollback plan already knows it might fail.",
          "The build failed twice this morning. Nobody could find a code change that explained it. Here's what actually broke the build: a comment.",
          "The incident review named five follow-up tasks. Three were closed within a week without much discussion. The fourth one is the only task that would have prevented the outage.",
          "Every cache in the fleet shares one eviction policy. The eviction policy that keeps memory free is the same eviction policy that evicts the entry you needed two seconds later."
        ],
        examples_ok: [
          "The cache holds the last hour of queries once it's warm. A cold instance takes about four seconds to rebuild that on its first request.",
          "We wrote a rollback plan before the migration ran because the migration might fail. It covers every table we're touching.",
          "The build failed twice this morning. A stray comment in the config file caused both failures.",
          "The deploy at 09:40 tripled error rates on the billing endpoint. The Redis connection pool was maxed at 20 for six minutes. We rolled back to the previous build and error rates returned to normal within two minutes.",
          "The incident review named five follow-up tasks, including a rewrite of the retry budget. The retry-budget rewrite would have prevented the outage. The other four tasks were closed within a week.",
          "Every cache in the fleet shares one eviction policy. It frees memory by evicting the least recently used entry, even when that entry is needed again a few seconds later."
        ],
        rationale: "A sentence can make its claim by mirroring opposites against each other, posing a riddle with a repeated noun, holding an answer back until a run of specifics resolves into it, coining a figure, or drawing a maxim that restates what the paragraph already showed. mirrored-opposites and the-x-is-not-the-x in the regex catalog each catch one syntactic shape of this; this rule reads the sentence's role in the paragraph instead, so a form neither regex expects is still caught. It only says a device is present, not whether the device earns its place: a figure that explains how something works or a real tradeoff dressed as a mirror is still flagged, and it is for the reader to decide whether cutting it loses anything."
      )
    ].freeze
  end
end
