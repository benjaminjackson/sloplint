# frozen_string_literal: true

module Sloplint
  # A rule is data, not code. See docs/SPEC.md "Rule model".
  #
  # count_group: a Regexp scanned over the matched text to tally items; when set,
  #   the Note carries `count` and the message may interpolate %{count}.
  # skip: Regexps that, if they match the matched text, drop the note (exclusions).
  # default_on: false keeps a noisy rule out of the default run (still selectable).
  Rule = Data.define(
    :id, :category, :severity, :pattern, :message, :suggestion,
    :examples_bad, :examples_ok, :count_group, :skip, :rationale, :default_on
  ) do
    def initialize(count_group: nil, skip: [], rationale: nil, default_on: true, **rest)
      super
    end
  end

  RULES = [
    # ── rhetorical-tic ────────────────────────────────────────────────────
    Rule.new(
      id: "no-x-no-y",
      category: "rhetorical-tic",
      severity: "warning",
      pattern: /\bno\s+[\w'-]+,\s+no\s+[\w'-]+(?:,?\s+(?:and\s+)?no\s+[\w'-]+)*/i,
      message: '"No X, no Y" chain (%{count} items) reads as AI cadence.',
      suggestion: "Cut the chain or make it one plain sentence.",
      count_group: /\bno\b/i,
      examples_bad: ["No fluff, no filler, no jargon."],
      examples_ok: ["No parking on Sundays."],
      rationale: "LLMs love asyndetic negation triplets. A careful writer rarely stacks three."
    ),
    Rule.new(
      id: "thats-the-whole",
      category: "rhetorical-tic",
      severity: "warning",
      pattern: /\b(?:that|this)(?:'s| is)\s+the\s+whole\s+(?:point|game|thing|deal|story|ballgame|ball\s+game)\b/i,
      message: '"That\'s the whole point/game/…" is a stock LLM closer.',
      suggestion: "Say the point directly instead of announcing it.",
      examples_bad: ["That's the whole point."],
      examples_ok: ["This is the whole cake."],
      rationale: "The 'that's the whole X' flourish is a model tic for landing a paragraph."
    ),
    Rule.new(
      id: "did-not-x-did-not-y",
      category: "rhetorical-tic",
      severity: "warning",
      pattern: /\b(?:did\s+not|didn't)\s+[\w'-]+(?:,?\s+(?:and\s+)?(?:did\s+not|didn't)\s+[\w'-]+)+/i,
      message: '"did not X, did not Y" chain (%{count} items) reads as AI cadence.',
      suggestion: "Cut the chain or make it one plain sentence.",
      count_group: /\b(?:did\s+not|didn't)\b/i,
      examples_bad: ["She didn't flinch, didn't blink, didn't look away."],
      examples_ok: ["He didn't know the answer."],
      rationale: "Repeated negated-verb parallelism is a signature model cadence."
    ),
    Rule.new(
      id: "dont-verb-it",
      category: "rhetorical-tic",
      severity: "warning",
      pattern: /\b(?:don't|do\s+not)\s+(\w+)\s+it\b[^.!?]*[.!?]\s*\1\s+it\b/i,
      message: '"Don\'t X it. X it Y." reframing is a stock LLM move.',
      suggestion: "Drop the fake reframe and state the claim once.",
      examples_bad: ["Don't call it luck. Call it preparation."],
      examples_ok: ["Don't do it now."],
      rationale: "The negate-then-rename couplet almost never occurs in unforced human prose."
    ),
    Rule.new(
      id: "sit-with-that",
      category: "rhetorical-tic",
      severity: "warning",
      pattern: /\bsit\s+with\s+(?:that|this|it|the\s+\w+)\b/i,
      message: '"Sit with that/the discomfort" is therapized LLM filler.',
      suggestion: "Cut it, or say what you actually want the reader to do.",
      examples_bad: ["Just sit with that for a moment."],
      examples_ok: ["Sit with your family at dinner."],
      rationale: "The 'sit with X' imperative is a model comfort tic, rare in real argument."
    ),
    Rule.new(
      id: "you-already-know",
      category: "rhetorical-tic",
      severity: "warning",
      pattern: /\byou\s+already\s+know\b/i,
      message: '"You already know…" is a stock LLM rhetorical setup.',
      suggestion: "Just make the point; don't tell the reader they know it.",
      examples_bad: ["You already know how this ends."],
      examples_ok: ["Did you already send the report?"],
      rationale: "Second-person 'you already know' framing is a model tic, seldom used sincerely."
    ),
    Rule.new(
      id: "is-the-entire",
      category: "rhetorical-tic",
      severity: "warning",
      pattern: /\bis\s+the\s+entire\s+(?:point|game|thing|business\s+model|deal|story)\b/i,
      message: '"X is the entire point/game/…" is an LLM emphasis tic.',
      suggestion: "State the point plainly without the superlative frame.",
      examples_bad: ["The narrow focus is the entire point."],
      examples_ok: ["She read the entire book in a day."],
      rationale: "'is the entire X' overstates for effect the way models routinely do."
    ),
    Rule.new(
      id: "the-entire-is",
      category: "rhetorical-tic",
      severity: "warning",
      pattern: /\bthe\s+entire\s+(?:point|game|thing|business\s+model|deal|story)\s+is\b/i,
      message: '"The entire point/game/… is" is an LLM emphasis tic.',
      suggestion: "State the point plainly without the superlative frame.",
      examples_bad: ["The entire point is to save time."],
      examples_ok: ["The entire team is here today."],
      rationale: "The flipped 'the entire X is' opener carries the same model overstatement."
    ),
    Rule.new(
      id: "is-real-and-not",
      category: "rhetorical-tic",
      severity: "warning",
      pattern: /\bis\s+real,?\s+(?:and|but|not)\b/i,
      message: '"The X is real, and…" is a stock LLM concession move.',
      suggestion: "Drop the 'is real, and' scaffolding; assert the point directly.",
      skip: [/real estate/i, /real time/i, /real-time/i],
      examples_bad: ["The risk is real, and it is growing."],
      examples_ok: ["This is real leather."],
      rationale: "'X is real, and/but/not' is a model both-sidesing cadence."
    ),
    Rule.new(
      id: "the-punchline-is",
      category: "rhetorical-tic",
      severity: "warning",
      pattern: /\bthe\s+punchline\s*(?:is\b|[:?])/i,
      message: '"The punchline is…" is a stock LLM reveal.',
      suggestion: "Deliver the point without announcing a punchline.",
      examples_bad: ["The punchline is that nobody noticed."],
      examples_ok: ["The punchline landed perfectly."],
      rationale: "Announcing 'the punchline' is a model framing device, rare in real prose."
    ),
    Rule.new(
      id: "worth-naming",
      category: "rhetorical-tic",
      severity: "warning",
      pattern: /\bworth\s+naming\b/i,
      message: '"Worth naming…" is a stock LLM signposting phrase.',
      suggestion: "Just name the thing; skip the meta-announcement.",
      skip: [/naming names/i],
      examples_bad: ["One tension is worth naming here."],
      examples_ok: ["It's worth reading twice."],
      rationale: "'worth naming' is a model signpost that a human would simply skip."
    ),
    Rule.new(
      id: "thats-not-nothing",
      category: "rhetorical-tic",
      severity: "warning",
      pattern: /\b(?:that|this|it|which)(?:'s| is)\s+not\s+nothing\b/i,
      message: '"…that\'s not nothing" is a stock LLM understatement.',
      suggestion: "State the magnitude directly instead of the litotes.",
      examples_bad: ["We cut latency in half, and that's not nothing."],
      examples_ok: ["That is not enough to matter."],
      rationale: "The 'not nothing' litotes is a recognizable model closer."
    ),

    Rule.new(
      id: "exactly-the",
      category: "rhetorical-tic",
      severity: "warning",
      pattern: /\b(?:that's|this is|it's)?\s*exactly\s+the\s+(?:point|kind|type|sort|problem|question|issue|opposite|reason|thing|tension)\b/i,
      message: '"exactly the point/kind/problem/…" is an overused LLM emphasis tic.',
      suggestion: "Drop 'exactly the'; state the point without the intensifier.",
      examples_bad: ["That's exactly the point."],
      examples_ok: ["She folded it exactly the way he showed her."],
      rationale: "'exactly the X' is a model intensifier that a careful writer rarely leans on."
    ),
    Rule.new(
      id: "thats-how-x",
      category: "rhetorical-tic",
      severity: "warning",
      pattern: /(?:\A|[.!?]\s+|\n\s*\n)\s*(?:that|this)(?:'s| is)\s+how\b/i,
      message: '"That\'s how…" opening a sentence is a stock LLM aphorism closer.',
      suggestion: "Cut the closer, or replace it with the concrete result you mean.",
      examples_bad: ["That's how a review system compounds instead of drifting."],
      examples_ok: [
        "I never learned that's how the engine works.", "And that's how I met your mother.",
        # A mid-sentence use that happens to fall right after a hard-wrapped
        # line break must not read as a paragraph-opening kicker.
        "things are the way they are because\nthat is how things have to be."
      ],
      rationale: "Models end paragraphs by generalizing the point into a maxim; 'That's how X' " \
                 "is the usual hinge. Mid-sentence uses are ordinary, so only the kicker " \
                 "position is flagged — a real paragraph break (blank line), not just a line " \
                 "break, since hard-wrapped source would otherwise flag mid-sentence text that " \
                 "happens to land at the start of a line."
    ),
    Rule.new(
      id: "announced-takeaway",
      category: "rhetorical-tic",
      severity: "warning",
      pattern: /(?:\A|[.!?]\s+|\n\s*\n)\s*(?:here'?s\s+)?the\s+(?:loop|pattern|trick|lesson|takeaway|playbook|framing|insight|kicker)\b[^.!?\n]{0,60}:/i,
      message: "Colon-led takeaway label announces the lesson before making it.",
      suggestion: "Give the observation first; let the reader decide it's the takeaway.",
      examples_bad: ["The loop I'd copy: file the incident, then fix the reviewer."],
      examples_ok: [
        "The pattern repeated all week.", "The move: bishop takes rook.",
        # Mid-sentence, hard-wrapped: the label lands after a line break that
        # isn't a paragraph break, and must not read as a kicker.
        "We noticed something worth naming here, and\nthe pattern: it only ever happened on Fridays."
      ],
      rationale: "Labelling a claim as the portable lesson does the persuading that the claim " \
                 "should be doing — a model habit borrowed from thought-leader prose. Anchored " \
                 "on a real paragraph break (blank line), not a line break, for the same reason " \
                 "as thats-how-x."
    ),

    # ── puffery ───────────────────────────────────────────────────────────
    Rule.new(
      id: "puffery-words",
      category: "puffery",
      severity: "warning",
      pattern: /\b(?:boasts\s+a\b|vibrant|nestled|
                  in\s+the\s+heart\s+of\s+(?:the\s+\w+|downtown\b|(?-i:[A-Z])\w+)|
                  groundbreaking|renowned|diverse\s+array|breathtaking|
                  natural\s+beauty|indelible\s+mark|deeply\s+rooted|
                  stands\s+as\s+a\s+testament|rich\s+(?:history|cultural|heritage))/ix,
      message: "Wikipedia-style puffery word/phrase — a common AI tell.",
      suggestion: "Replace with a concrete, specific detail or cut it.",
      examples_bad: [
        "The vibrant city, nestled in the heart of the valley.",
        "A boutique hotel in the heart of Paris."
      ],
      examples_ok: [
        "The city sits at the north end of the valley.",
        # Moby-Dick: "in the heart of" used as spatial/emphatic idiom, not a
        # place-description cliché — the narrow trigger requires a definite
        # or proper noun object, which this lacks.
        "You cannot sit motionless in the heart of these perils.",
        "helpless Ahab, even in the heart of such a whirlpool as that"
      ],
      rationale: "Travel-brochure adjectives and phrases that models reach for and careful " \
                 "writers avoid. Dropped 'profound' from this list: bare adjective, no reliable " \
                 "way to separate sincere use ('a profound silence') from puffery without more " \
                 "context than a regex has. 'in the heart of' is narrowed to require a place " \
                 "object, since unguarded it fires on ordinary spatial idiom."
    ),
    Rule.new(
      id: "stands-serves-as",
      category: "puffery",
      severity: "info",
      pattern: /\b(?:stands|serves)\s+as\b|\bis\s+a\s+(?:testament|reminder)\s+to\b/i,
      message: '"stands/serves as", "is a testament/reminder to" is puffed AI framing.',
      suggestion: "Say what it does, not what it 'stands as'.",
      examples_bad: ["The bridge stands as a symbol of the era."],
      examples_ok: ["He stands at the door."],
      rationale: "The 'stands/serves as' construction inflates significance the way models do."
    ),
    Rule.new(
      id: "vital-role",
      category: "puffery",
      severity: "warning",
      pattern: /\bplays?\s+a\s+(?:vital|crucial|pivotal|significant|key|central)\s+role\b/i,
      message: '"plays a vital/crucial/… role" is a stock AI puffery phrase.',
      suggestion: "State the specific role or effect instead.",
      examples_bad: ["Sleep plays a vital role in recovery."],
      examples_ok: ["She plays a role in the new play."],
      rationale: "'plays a X role' is filler significance, a hallmark of model prose."
    ),
    Rule.new(
      id: "underscores-highlights",
      category: "puffery",
      severity: "info",
      pattern: /\b(?:underscores|highlights|emphasizes)\s+(?:its|the|their)\s+(?:importance|significance)\b/i,
      message: '"underscores/highlights its importance" is stock AI framing.',
      suggestion: "Show why it matters rather than asserting that it does.",
      examples_bad: ["This underscores its importance to the field."],
      examples_ok: ["She highlights the key line in yellow."],
      rationale: "The 'underscores its importance' move asserts significance without earning it."
    ),
    Rule.new(
      id: "rich-tapestry",
      category: "puffery",
      severity: "warning",
      pattern: /\brich\s+tapestry\b|\btapestry\s+of\b/i,
      message: '"rich tapestry"/"tapestry of" is a signature AI cliché.',
      suggestion: "Cut the metaphor; name the actual things.",
      examples_bad: ["A rich tapestry of cultures and traditions."],
      examples_ok: ["She wove a tapestry by hand."],
      rationale: "'tapestry of' is one of the most reliable single-phrase model tells."
    ),

    # ── structure ─────────────────────────────────────────────────────────
    Rule.new(
      id: "not-just-x-but-y",
      category: "structure",
      severity: "warning",
      pattern: /(?:\bis|\bare|\bwas|\bwere|\bisn['’]t|\baren['’]t|\bwasn['’]t|\bweren['’]t|
                  \bit['’]s|\bthat['’]s|\bthis\s+is|\bthese\s+are|\bthose\s+are)
                 \s+not\s+(?:just|only)\b[^.!?]*?\bbut\b(?:\s+also\b)?/ix,
      message: '"X is not just A, but B" is a stock AI escalation structure.',
      suggestion: "Make the claim once; drop the 'not just… but' frame.",
      examples_bad: [
        "It's not just fast, but genuinely reliable.",
        "This is not just a tool, but a partner in your workflow."
      ],
      examples_ok: [
        "He is not tired.",
        # Federalist No. 44: a real correlative conjunction joining two verb
        # phrases, not a copula predicating two things of one subject.
        "This power ought not only to be established, but ought to be established.",
        "Not only that, but they looked embarrassed.",
        "not just to acquire users, but to build something people love."
      ],
      rationale: "'X is not just A, but B' predicates two things of the same subject through a " \
                 "copula, which is the specific shape models overuse. 'not only… but' joining " \
                 "two verb phrases or clauses without a preceding copula is ordinary correlative " \
                 "conjunction and common in formal human prose; anchoring on the copula is what " \
                 "keeps this rule off that construction."
    ),
    Rule.new(
      id: "rule-of-three",
      category: "structure",
      severity: "info",
      default_on: false,
      pattern: /\b[\w'-]+,\s+[\w'-]+,\s+(?:and\s+)?[\w'-]+[.!?]/,
      message: "Three parallel comma items closing a sentence (heuristic; high false-positive).",
      suggestion: "Fine in moderation; watch for the AI habit of ending on triplets.",
      examples_bad: ["It was fast, cheap, and simple."],
      examples_ok: ["We met on Tuesday afternoon."],
      rationale: "Rule-of-three endings are a model habit, but humans use them too — off by default."
    ),
    Rule.new(
      id: "clause-triad-then",
      category: "structure",
      severity: "info",
      pattern: /[^,.!?\n]{5,60},\s+[^,.!?\n]{5,60},\s+then\s+[^.!?\n]{5,}/i,
      message: "Three-beat clause chain hinged on 'then' — an AI process-recipe cadence.",
      suggestion: "Real procedures have an ugly step. Name it, or cut to the two that matter.",
      examples_bad: ["Take the PR that caused it, update the reviewer to catch that class, " \
                     "then add the PR to the eval set."],
      examples_ok: ["I packed a bag, locked the door, and then drove north."],
      rationale: "Models describe processes as three evenly-weighted parallel clauses with no " \
                 "step harder than the others, which is how you can tell nobody ran it."
    ),
    Rule.new(
      id: "em-dash-overuse",
      category: "structure",
      severity: "info",
      pattern: /—(?:[^\n]|\n(?!\s*\n))*—(?:[^\n]|\n(?!\s*\n))*—/,
      message: "Three or more em dashes in one paragraph — an AI punctuation tell.",
      suggestion: "Recast with commas, parentheses, or separate sentences.",
      examples_bad: [
        "It was — I think — the best — no, the only — option.",
        # Hard-wrapped Markdown: the same paragraph, split across lines. The
        # tell is per-paragraph, not per-line, so this must still flag.
        "It was — I think — the best decision\nwe made all year — though nobody\nbelieved it at the time."
      ],
      examples_ok: [
        "It was — I think — a fine option.",
        # Two separate paragraphs, two dashes each -- never three within one
        # paragraph, even though the raw text has four dashes total.
        "It was — I think — a fine choice.\n\nAnother option — entirely separate — came up too."
      ],
      rationale: "Heavy em-dash interjection is a strong model tell; two is fine, three signals " \
                 "slop. Scoped to a paragraph (stops at a blank line), not a source line, so " \
                 "hard-wrapped Markdown doesn't dodge the rule and soft-wrapped Markdown doesn't " \
                 "over-trigger it -- the earlier line-scoped version swung 30x on wrapping alone."
    ),

    # ── hedging ───────────────────────────────────────────────────────────
    Rule.new(
      id: "vague-attribution",
      category: "hedging",
      severity: "warning",
      pattern: /\bsome\s+(?:critics|experts|observers|scholars|analysts)\s+(?:argue|say|believe|contend|maintain)\b|\bit\s+is\s+widely\s+(?:regarded|considered|seen|believed|acknowledged)\b|\bmany\s+would\s+argue\b/i,
      message: "Vague attribution ('some critics argue', 'it is widely…') — an AI hedging tell.",
      suggestion: "Name the source, or drop the appeal to unnamed authority.",
      examples_bad: ["Some critics argue the plan is deeply flawed."],
      examples_ok: ["Some people left the meeting early."],
      rationale: "Anonymous-authority hedging is a model habit for sounding balanced without a source."
    )
  ].freeze
end
