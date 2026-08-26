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
      # Comma chains only: "no fluff, no filler, no jargon". The comma is the
      # evidence -- it makes the parallelism deliberate. Fragment chains split
      # by sentence punctuation are a separate, quieter rule (no-x-no-y-frag),
      # because periods are not an authorial choice the way commas are.
      pattern: /\bno\s+[\w'-]+,\s+no\s+[\w'-]+(?:,?\s+(?:and\s+)?no\s+[\w'-]+)*/i,
      message: '"No X, no Y" chain (%{count} items) reads as AI cadence.',
      suggestion: "Cut the chain or make it one plain sentence.",
      count_group: /\bno\b/i,
      examples_bad: ["No fluff, no filler, no jargon."],
      examples_ok: ["No parking on Sundays."],
      rationale: "Asyndetic negation chains are a signature model cadence, near-absent from " \
                 "human prose at any length. A careful writer occasionally stacks two (and, " \
                 "rarely, more), but a model reaches for the pattern constantly."
    ),
    Rule.new(
      id: "no-x-no-y-frag",
      category: "rhetorical-tic",
      severity: "info",
      # The same cadence built from sentence fragments: "No fluff. No filler."
      # Ships at info, not warning, because the shape is genuinely ambiguous --
      # two short "no" sentences in a row is also just writing ("No one moved.
      # No one spoke."). The agent reading the flag decides; see rationale.
      #
      # Two structural guards keep it from reporting chains that are not in the
      # text at all. A link must START a sentence, so an ordinary sentence
      # cannot donate its tail ("There was no bread." + "No milk either." is
      # one sentence and one fragment, not a chain). And the separator is at
      # most two spaces, so a blanked-out code span or URL under --markdown
      # cannot silently weld two distant fragments together. Links may cross a
      # hard-wrapped newline (\r\n included) but never a paragraph break.
      pattern: /(?:^|(?<=[.;!?])[ \t]{1,2})\K
                no[ \t]+[\w'-]+(?:[ \t]+[\w'-]+)?[ \t]*[.;!]
                (?:(?:[ \t]{1,2}|\r?\n(?!\s*\n)[ \t]*)
                   (?:and[ \t]+)?no[ \t]+[\w'-]+(?:[ \t]+[\w'-]+)?[ \t]*[.;!])+/ix,
      message: '"No X. No Y." fragment chain (%{count} items) reads as AI cadence.',
      suggestion: "Cut the chain or make it one plain sentence.",
      count_group: /\bno\b/i,
      examples_bad: [
        "No fluff. No filler. No jargon.",
        "No fees; no contracts; no hidden charges.",
        # Hard-wrapped Markdown: the chain survives one newline.
        "No fluff.\nNo filler."
      ],
      examples_ok: [
        "No parking on Sundays.",
        # A link must start a sentence, so this donates no tail.
        "There was no bread. No milk either.",
        "Say no more. No worries.",
        # Two fragments split by a paragraph break never chain.
        "No answer.\n\nNo one was home when we finally arrived."
      ],
      rationale: "The fragment form of the same cadence, and the weaker signal of the two: the " \
                 "comma chain is one authored sentence, while this is just short sentences in " \
                 "sequence, which human prose also does. It's rare in careful writing, but a " \
                 "deliberate staccato run ('No one moved. No one spoke.') has the identical " \
                 "shape and is not a tell. Treat a flag here as a question, not a verdict."
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
      # Two branches. The deictic object is the tic anywhere in a sentence, so
      # "sit with that/this/it" needs no anchor. Anything else needs the
      # sentence-initial imperative, which is where the tic lives and where the
      # ordinary companion sense ("come and sit with me") mostly is not.
      # Widened from that|this|it|the+word, which both missed the bare abstract
      # object ("sit with uncertainty") and flagged "sit with the baby".
      pattern: /\bsit\s+with\s+(?:that|this|it)\b
                |(?:\A|[.!?]\s+|\n\s*\n)\s*(?:but\s+|and\s+|now\s+|so\s+|just\s+)?
                 sit\s+with\s+\S/ix,
      message: '"Sit with that/the discomfort" is therapized LLM filler.',
      suggestion: "Cut it, or say what you actually want the reader to do.",
      examples_bad: [
        "Just sit with that for a moment.",
        "Sit with uncertainty for a while.",
        "Sit with the discomfort before you answer.",
        "The numbers were worse than that. Sit with what they imply."
      ],
      examples_ok: [
        "They sit with their families at dinner.",
        "Come and sit with me on the porch.",
        "I sat with the baby until she slept."
      ],
      rationale: "The 'sit with X' imperative is a model comfort tic, rare in real argument. " \
                 "The object does not matter: the tic is telling the reader to dwell instead " \
                 "of giving them something to dwell on. The sentence-initial imperative does " \
                 "flag the plain companion sense (\"Sit with the baby while I run out\"), " \
                 "which is accepted -- hence warning, not error."
    ),
    Rule.new(
      id: "hold-onto-that",
      category: "rhetorical-tic",
      severity: "warning",
      # Sentence-initial imperative only. Past tense and subordinate clauses
      # ("she held on to that letter", "if you hold onto that phrase") are a
      # different construction, not the tell. Everything AFTER that/this is
      # unconstrained on purpose, which does flag the concrete-object
      # imperative ("Hold on to that rope") -- accepted, hence warning.
      pattern: /(?:\A|[.!?]\s+|\n\s*\n)\s*(?:but\s+|and\s+|now\s+|so\s+)?hold\s+(?:on\s+to|onto)\s+(?:that|this)\b/i,
      message: '"Hold onto that…" is a stock LLM attention cue.',
      suggestion: "Cut it; if the detail matters, use it where it matters.",
      examples_bad: [
        "Hold onto that second half, because it does more work than the first.",
        "Hold on to that for a moment.",
        "The table looked fine. Now hold onto this last figure; it changes everything."
      ],
      examples_ok: [
        "Hold that thought while I check the log.",
        "If you hold onto that phrase too long, the sentence sags.",
        "She held on to that letter for years."
      ],
      rationale: "The imperative parks a fragment against a payoff the writer has promised " \
                 "but not delivered. It fits in front of any sentence in any document, and " \
                 "real argument uses the detail again where it matters instead of asking " \
                 "the reader to carry it."
    ),
    Rule.new(
      id: "cleanly",
      category: "rhetorical-tic",
      severity: "warning",
      # No verb list. The engineering idioms -- a patch applies cleanly, a
      # branch merges cleanly, a build compiles cleanly -- are the same move
      # and get flagged too, on purpose. The word survives in a 19th-century
      # adjective sense ("cleanly dressed", "a cleanly laid table") that the
      # rule also catches, which costs nothing: nobody writes that today.
      pattern: /\bcleanly\b/i,
      message: '"Cleanly" rates the fit instead of showing it.',
      suggestion: "Cut the adverb, or say what actually lined up.",
      examples_bad: [
        "The argument splits cleanly into two parts.",
        "The patch applies cleanly to main.",
        "The new taxonomy maps cleanly onto the old one.",
        "The objection breaks down cleanly, and neither half survives."
      ],
      examples_ok: [
        "The branch merged without conflicts.",
        "She wiped the counter clean.",
        "The build finished with no warnings."
      ],
      rationale: "The adverb rates the join instead of showing it, and it rates before the " \
                 "reader has anything to check. Real material resists -- the leftover case, " \
                 "the item in both buckets. A writer who has met the leftovers names them."
    ),
    Rule.new(
      id: "clean-count",
      category: "rhetorical-tic",
      severity: "warning",
      # Needs a partition noun. The bare count reaches the laundry: Ulysses
      # has "four clean strokes", Jane Eyre "two clean tuckers".
      pattern: /\b(?:two|three|four|five|six|seven|2|3|4|5|6|7)\s+
                 (?:very\s+|fairly\s+|reasonably\s+|pretty\s+)?clean\s+(?:\w+\s+)?
                 (?:parts|halves|pieces|buckets|categories|groups|chunks|sections|layers
                   |camps|cases|classes|clusters|splits|steps|stages|phases|tiers|bands
                   |lanes|axes|dimensions|questions|claims|ideas|moves|jobs|roles)\b/ix,
      message: '"Two clean parts" claims a tidier division than it shows.',
      suggestion: "Name the parts and let the reader see whether they hold.",
      examples_bad: [
        "That leaves two clean buckets for the rest of the work.",
        "The job falls into three clean stages.",
        "You end up with two clean categories and a remainder nobody mentions."
      ],
      examples_ok: [
        "She wore two clean shirts that week.",
        "He cut it in four clean strokes.",
        "The kitchen had three clean plates left."
      ],
      rationale: "The count and the adjective do the same work twice: the number says the " \
                 "division is settled, the adjective says it was easy. Neither is evidence, " \
                 "and prose that has met the awkward third case rarely offers both."
    ),
    Rule.new(
      id: "cleanest-x",
      category: "rhetorical-tic",
      severity: "warning",
      # Noun list only. "The cleanest way to install the driver" and "the
      # cleanest cut of meat" are ordinary English, so "way" is admitted only
      # in front of a speech verb, and the concrete-capable nouns (cut, line,
      # version, split) are left out entirely.
      pattern: /\bcleanest\s+(?:\w+\s+){0,2}
                 (?:framing|formulation|statement|account|argument|idea|definition|summary
                   |reading|take|point|story|explanation|distinction|comparison|mapping
                   |abstraction)\b
                |\bcleanest\s+way\s+to\s+(?:say|put|frame|state|describe|phrase|express
                   |think\s+about)\b/ix,
      message: '"The cleanest framing/way to put it…" ranks your own claim for the reader.',
      suggestion: "Drop the ranking and make the claim; the reader grades it.",
      examples_bad: [
        "The cleanest framing is that nobody was in charge.",
        "That is the cleanest way to put it.",
        "The cleanest organizing idea here is scarcity."
      ],
      examples_ok: [
        "This is the cleanest way to install the driver.",
        "She picked the cleanest room in the house.",
        "The cleanest energy source is still hydro."
      ],
      rationale: "Self-ranking: the writer tells the reader which of their own claims is " \
                 "the good one, which is the reader's job and costs nothing to assert."
    ),
    Rule.new(
      id: "clean-x",
      category: "rhetorical-tic",
      severity: "info",
      # The quiet half of cleanest-x, at info because the positive degree is
      # where ordinary usage lives. "A clean separation of concerns" is
      # standard engineering English, so "separation" stays out of the list;
      # "break" is admitted only in "clean break between", never bare, because
      # "make a clean break with the past" is an idiom and not a tell.
      pattern: /\b(?:a|the|one)\s+(?:\w+\s+)?clean\s+(?:\w+\s+)?
                 (?:abstraction|distinction|framing|formulation|mapping|through-line
                   |story|answer|argument|split|divide)\b
                |\bclean\s+(?:line|break|split)\s+between\b/ix,
      message: '"A clean abstraction / clean framing" praises the idea instead of showing it.',
      suggestion: "Cut the adjective; if it is tidy, the reader will see that.",
      examples_bad: [
        "That gives us a clean abstraction over the queue.",
        "The clean framing is that both sides were guessing.",
        "There is a clean line between advice and instruction."
      ],
      examples_ok: [
        "The design has a clean separation of concerns.",
        "He made a clean break with the past.",
        "They ran a clean campaign.",
        "The report gives a clean bill of health."
      ],
      rationale: "'Clean' in front of an idea is evaluation, not description -- it says the " \
                 "writer approves, and nothing about the idea. It ships at info because the " \
                 "same words carry a plain sense a regex cannot separate from the tic."
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
      severity: "info",
      pattern: /\bis\s+real,?\s+(?:and|but|not)\b/i,
      message: '"The X is real, and…" is a stock LLM concession move.',
      suggestion: "Drop the 'is real, and' scaffolding; assert the point directly.",
      # No skip: for "real estate"/"real time" -- with a word between "real"
      # and the conjunction ("is real estate, and"), the pattern's ,?\s+
      # never reaches the conjunction in the first place, so those compound
      # nouns can't produce a false positive here to begin with. A skip: for
      # them was here before and never fired; confirmed by testing every
      # phrasing it could plausibly have been guarding against.
      examples_bad: ["The risk is real, and it is growing."],
      examples_ok: ["This is real leather.", "This is real estate, and it is expensive."],
      rationale: "The pattern requires nothing about what follows the conjunction, so it fires " \
                 "on any 'is real' sentence that happens to continue with and/but/not, concession " \
                 "or not. Emerson's 'my debt to my senses is real and constant' is two predicate " \
                 "adjectives, not a both-sidesing move -- the AI cadence and the plain sentence " \
                 "are three words apart and identical on the surface. An agent reading the flag " \
                 "has the rest of the sentence to judge; the pattern alone doesn't."
    ),
    Rule.new(
      id: "the-punchline-is",
      category: "rhetorical-tic",
      severity: "warning",
      # Same reveal, three nouns. "honest answer" and "honest version" join
      # "punchline" because they do the identical job: rate the sentence as
      # the candid one before the reader gets it. "short version" was tried
      # and left out -- people really do offer a short version, and both the
      # "is" and the colon form of it are ordinary writing.
      pattern: /\bthe\s+(?:punchline|honest\s+(?:answer|version))\s*(?:is\b|[:?])/i,
      message: '"The punchline/honest answer is…" is a stock LLM reveal.',
      suggestion: "Deliver the point without announcing it first.",
      examples_bad: [
        "The punchline is that nobody noticed.",
        "The honest answer is that we never checked.",
        "The honest version: the deadline was never real."
      ],
      examples_ok: [
        "The punchline landed perfectly.",
        "The short version is that the cache was cold.",
        "She gave the honest answer without being asked."
      ],
      rationale: "Announcing 'the punchline', or grading your own next sentence as the honest " \
                 "one, is a model framing device, rare in real prose. The honest-answer form " \
                 "carries a second claim on top: that the sentences around it were less so."
    ),
    Rule.new(
      id: "worth-naming",
      category: "rhetorical-tic",
      severity: "info",
      # Widened to optionally include a trailing "names" so the "naming
      # names" idiom is part of the matched text -- skip: checks the matched
      # text itself, and the tighter /\bworth\s+naming\b/ never captured
      # enough of "worth naming names" for the skip to ever reach it.
      #
      # The trailing lookahead hands the adverb-bearing form to
      # worth-saying-plainly, which is the same construction with a manner
      # adverb on the end and reports it at warning. Without it both rules
      # fire on one span. Cost: a mid-sentence "worth naming plainly", which
      # the other rule's sentence anchor won't reach, now goes unflagged.
      pattern: /\bworth\s+(?:naming(?:\s+names)?|flagging|separating|spelling\s+(?:it\s+)?out)\b
                (?!\s+(?:plainly|clearly|bluntly|directly|simply|outright|flatly|straight
                        |up\s+front|out\s+loud)\b)/ix,
      message: '"Worth naming/flagging…" is a stock LLM signposting phrase.',
      suggestion: "Just name the thing; skip the meta-announcement.",
      skip: [/naming names/i],
      examples_bad: [
        "One tension is worth naming here.",
        "Two failures are worth flagging before we move on.",
        "The two cases are worth separating."
      ],
      # The adverb-bearing form ("worth naming plainly") can't sit here: it
      # belongs to worth-saying-plainly, which flags it, and the cross-rule
      # check requires an ok-fixture to be clean against the whole catalog.
      # The "worth-* pair" example in rules_spec.rb pins that hand-off.
      examples_ok: ["It's worth reading twice.", "It's worth naming names in this report."],
      rationale: "'worth naming', and its siblings 'worth flagging' and 'worth separating', " \
                 "collapse two senses a regex can't tell apart: the AI " \
                 "meta-signpost announcing a point is coming ('One tension is worth naming " \
                 "here') and the plain sense of a thing worth calling or mentioning, which " \
                 "careful writers use too -- Emerson's 'the only thing worth naming to do that' " \
                 "is the latter, not the former. A flag here means the phrase is present, not " \
                 "which sense it's in."
    ),
    Rule.new(
      id: "worth-saying-plainly",
      category: "rhetorical-tic",
      severity: "warning",
      # Two branches, both sentence-initial.
      #
      # First: evaluative adjective + speech verb + manner adverb, all three
      # required. Any two occur in ordinary prose ("worth saying yes to",
      # "said plainly that"); the full stack is the signpost.
      #
      # Second: the bare imperative with the adjective dropped ("Put plainly,"
      # / "Said bluntly,"). It runs a shorter adverb list than the first
      # branch, because the explainer openers are ordinary human writing and
      # would swamp it -- "simply put" and "put simply" are common, so
      # "simply", "clearly", "directly", "straight" and "up front" are all
      # left out of this branch. "To put it bluntly" is likewise safe: the
      # anchor puts "To" where the verb has to be, so it never matches.
      pattern: /(?:\A|[.!?]\s+|\n\s*\n)\s*
                (?:(?:it'?s\s+|that'?s\s+)?
                   (?:worth|better|best|easier|simpler|fairer|clearer)\s+
                   (?:saying|stating|putting|naming|flagging|separating|said|stated|put
                     |spelling\s+(?:it\s+)?out)\s+
                   (?:it\s+|this\s+|that\s+)?
                   (?:plainly|clearly|bluntly|directly|simply|outright|flatly|straight
                     |up\s+front|out\s+loud)
                  |(?:put|said|stated)\s+(?:it\s+|this\s+|that\s+)?
                   (?:plainly|bluntly|flatly|outright))\b/ix,
      message: '"Worth saying plainly…" rates the sentence before the reader can.',
      suggestion: "Say the thing; if it lands plainly, the reader will notice.",
      examples_bad: [
        "Worth saying plainly, the ceiling is set by the first report.",
        "It's worth stating clearly: the data never arrived.",
        "The batch failed. Worth putting it bluntly, we lost a week.",
        "Put plainly, the ceiling is set by the first report.",
        "The review ran long. Said bluntly, nobody had read the draft."
      ],
      examples_ok: [
        "It's worth reading twice.", "The contract is worth saying yes to.",
        "She said plainly that the plan had failed.",
        "He put it bluntly and everyone understood.",
        # The explainer openers the bare branch deliberately leaves alone.
        "Put simply, gravity pulls things down.",
        "Simply put, the cache was never warm.",
        "To put it bluntly, we lost a week.",
        "He stated clearly that the plan had failed.",
        # Hard-wrapped mid-sentence: a line break is not a paragraph break.
        "the argument started long before that and\nworth saying plainly is not how it opened."
      ],
      rationale: "The sentence is about the sentence: an unsourced claim that what follows " \
                 "deserves attention, made before the reader has anything to weigh it " \
                 "against. It is also subjectless -- worth it to whom? -- and fits in front " \
                 "of any claim in any document, which is why it says nothing about this one."
    ),
    Rule.new(
      id: "not-nothing",
      category: "rhetorical-tic",
      severity: "warning",
      # Two branches: spelled-out copula with an optional captured subject, and
      # the contracted "X's not nothing". The optional subject + skip: is the
      # load-bearing idiom -- skip: only sees matched text, so the personal
      # subjects a human litotes takes (I/he/she/we/you/they) must be inside
      # the match to be dropped there. The contracted branch captures the word
      # before 's for the same reason ("she's not nothing" must reach the
      # skip). "there" is guarded too: "there is/there's not nothing" is the
      # philosophy frame or dialect, not the closer. "not for nothing" and
      # "something and not nothing" never match at all -- the copula must sit
      # adjacent to "not nothing". Token gaps cross a hard-wrapped line but
      # never a paragraph break, so a paragraph ending "...was not" cannot weld
      # onto one starting "Nothing ...".
      pattern: /\b(?:(?:i|he|she|we|you|they|there)(?:[ \t]|\r?\n(?![ \t]*\r?\n))+)?
                 (?:am|is|are|was|were)(?:[ \t]|\r?\n(?![ \t]*\r?\n))+
                 not(?:[ \t]|\r?\n(?![ \t]*\r?\n))+nothing\b
                |\b[\w-]+['’]s(?:[ \t]|\r?\n(?![ \t]*\r?\n))+
                 not(?:[ \t]|\r?\n(?![ \t]*\r?\n))+nothing\b/ix,
      skip: [/\A(?:i|he|she|we|you|they|there)\b/i],
      message: '"…is not nothing" is a stock LLM understatement.',
      suggestion: "State the magnitude directly instead of the litotes.",
      examples_bad: [
        "We cut latency in half, and that's not nothing.",
        "Fifty basis points is not nothing.",
        "Three years of runway is not nothing.",
        "A million users is not nothing.",
        "The margin was not nothing.",
        # Hard-wrapped Markdown: same paragraph, still the tell.
        "The gain was not\nnothing, the report said."
      ],
      examples_ok: [
        "That is not enough to matter.",
        # Personal-subject litotes is a human literary move, not the closer
        # tic -- spelled out and contracted.
        "She told him he was not nothing to her.",
        "She's not nothing to me, whatever they say.",
        # "not for nothing": the intervening word breaks adjacency.
        "It was not for nothing that he trained all winter.",
        # The philosophy frame, both shapes it takes.
        "Why is there something and not nothing?",
        "There is not nothing; being persists.",
        # Dialect double negative, not the litotes.
        "There's not nothing we can do.",
        # A paragraph break never welds a match.
        "The answer was not\n\nNothing prepared us for it."
      ],
      rationale: "The 'not nothing' litotes is a recognizable model closer; the subject " \
                 "varies ('that's not nothing', 'fifty basis points is not nothing') but " \
                 "the move is the same. Personal subjects are carved out: 'he was not " \
                 "nothing to her' is a human literary litotes, not the closer."
    ),

    Rule.new(
      id: "exact-exactly",
      category: "rhetorical-tic",
      severity: "info",
      pattern: /\bexact(?:ly)?\b(?!\s*(?:(?:the\s+)?(?:same|opposite|science|change|replica|copy|location|coordinates|way)\b|[$\d]|noon\b|midnight\b|o'?\s*clock\b))/i,
      message: '"exact/exactly" is reflexive emphasis unless it names something checkable.',
      suggestion: "Cut it, or replace with the number, name, or match it's supposed to be precise about.",
      examples_bad: [
        "That's exactly the point.", "We proved exactly the point we needed.",
        "This is exactly the kind of thing we warned about.",
        "That's the exact problem with the old system.",
        "That's exactly right.", "I know exactly why this happened."
      ],
      examples_ok: [
        "She folded it exactly the way he showed her.",
        "The bill came to exactly $42.",
        "We agreed on the exact same design.",
        "It's not an exact science.",
        "Please bring exact change for the bus.",
        "The museum built an exact replica of the ship.",
        "This is an exact copy of the original.",
        "He wanted the exact opposite of what she suggested.",
        "Rescue teams pinpointed the exact location of the wreck.",
        "GPS gave us the exact coordinates of the site.",
        "The train left at exactly noon.",
        "They agreed to meet at exactly midnight.",
        "The meeting starts at exactly 3 o'clock.",
        "She has exacting standards for her students."
      ],
      rationale: "Models reach for 'exact/exactly' as filler emphasis on a claim with nothing to " \
                 "check; it earns its place only next to a number, a name, or a stated identity."
    ),
    Rule.new(
      id: "load-bearing",
      category: "rhetorical-tic",
      severity: "warning",
      # Two guards, both structural, over the same noun list so they can't
      # drift apart. Forward: a physical building part right after it is the
      # literal sense, checked with a negative lookahead. Backward: the
      # predicate form ("the wall is load-bearing") is literal too, but a
      # fixed-width lookbehind covering this many noun x tense combinations
      # trips a real Ruby/Onigmo lookbehind bug on some inputs (RegexpError
      # at match time, not compile time -- reproduced on em-dash's own
      # fixtures). Pulling the noun+copula into the pattern itself as an
      # optional leading group sidesteps lookbehind entirely: when present,
      # it's captured as part of the match, and skip: (which only ever sees
      # matched text, never surrounding context) drops it there instead.
      pattern: /\b(?:(?:wall|column|beam|post|pillar|joist|stud|masonry|partition|
                        structure|frame|footing|foundation|member)s?\s+
                     (?:is|are|was|were)\s+)?
                load[-\s]?bearing\b
                (?!\s+(?:wall|column|beam|post|pillar|joist|stud|masonry|partition|
                         structure|frame|footing|foundation|member)s?\b)/ix,
      skip: [/\A(?:wall|column|beam|post|pillar|joist|stud|masonry|partition|
                   structure|frame|footing|foundation|member)s?\s+
                (?:is|are|was|were)\s+load/ix],
      message: '"load-bearing" outside construction is a borrowed metaphor.',
      suggestion: "Say what the thing holds up, or what breaks without it.",
      examples_bad: [
        "That comma is load-bearing.",
        "The load-bearing assumption is that users read the docs.",
        "Half the argument rests on one load-bearing word.",
        "This paragraph is the load-bearing part of the essay.",
        "Trust was the load-bearing element of the whole deal.",
        "The qualifier is doing load bearing work here."
      ],
      examples_ok: [
        "They knocked out a load-bearing wall during the remodel.",
        "The inspector flagged a cracked load-bearing column.",
        "Steel load-bearing beams replaced the old timber.",
        "The load-bearing masonry dates to 1890.",
        "Those columns are load-bearing.",
        "The interior wall is load-bearing, so it stays.",
        "The beam is load-bearing.",
        "That stud was load-bearing, so removing it needed a header beam.",
        "Those joists were load-bearing, engineers confirmed after inspection.",
        "The masonry was load-bearing in the original 1890 structure."
      ],
      rationale: "'Load-bearing' is a construction term for a wall or column that holds up the " \
                 "structure. Models borrow it as a metaphor for anything important, which just " \
                 "restates the sentence's importance without saying what actually holds it up."
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
                 "is the usual hinge. Mid-sentence uses are ordinary phrasing, not the tell."
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
        "We noticed something odd about the failures, and\nthe pattern: it only ever happened on Fridays."
      ],
      rationale: "Labelling a claim as the portable lesson does the persuading that the claim " \
                 "should be doing — a model habit borrowed from thought-leader prose."
    ),
    Rule.new(
      id: "is-is",
      category: "rhetorical-tic",
      severity: "warning",
      # No anchor needed -- the doubled copula alone scored 0 across ~1.9M words.
      # The comma is allowed because "What it is, is a mystery" grates the same
      # way. Sentence and clause punctuation still block the weld ("what it is.
      # Is that…", "here's what it is: is anyone…"), and \b on both ends keeps
      # the pattern out of "his island". \s+ needs no paragraph-break guard: a
      # false match would need a paragraph that begins with "is ".
      pattern: /\bis,?\s+is\b/i,
      message: 'Doubled copula ("is is" / "is, is") — spoken cadence on the page.',
      suggestion: "Drop the cleft and say it straight, or delete the second 'is'.",
      examples_bad: [
        "What this really is is a bet on distribution.",
        "What it is is a rounding error with a press release.",
        "What it is, is a failure of nerve.",
        "The thing is, is that nobody checked the logs."
      ],
      examples_ok: [
        # Walden: the cleft with a single copula, which is ordinary English.
        "We have heard of this virtue, but we know not what it is.",
        # Sentence and clause punctuation can't be welded across.
        "I know what it is. Is that a problem?",
        "Here's what it is: is anyone actually reading this?",
        # Both \b anchors matter -- "his island" contains the literal string "is is".
        "He sailed to his island at dawn."
      ],
      rationale: "Three things produce a doubled copula and all three read as unedited. The " \
                 "wh-cleft ('what it is is a mistake') is grammatical -- 'what it is' is the " \
                 "subject and the second 'is' is the verb -- and it is the model's version, a " \
                 "frame that stages a definition instead of asserting one, the same move as " \
                 "'the punchline is'. The NP form ('the thing is, is that') is the true double " \
                 "copula and a spoken disfluency. The third is a typo."
    ),

    Rule.new(
      id: "earns-its-place",
      category: "rhetorical-tic",
      severity: "warning",
      # The possessive is the narrowing. "earned a place on the team" and
      # "earn a place in the final" are ordinary; "earns its place" is the
      # metaphor, a thing paying for the room it takes up.
      pattern: /\b(?:earns?|earned|earning)\s+(?:its|their|his|her)\s+(?:place|keep)\b/i,
      message: '"Earns its place/keep" prices the thing instead of showing it.',
      suggestion: "Say what it does; the reader decides whether it was worth the room.",
      examples_bad: [
        "Every paragraph here earns its place.",
        "The third example earns its keep and the other two do not.",
        "That flag earned its place in the interface."
      ],
      examples_ok: [
        "She earned a place on the team that year.",
        "He earned enough to keep the lights on.",
        "The tenant paid the rent on time."
      ],
      rationale: "The phrase grades the material against an unstated budget the reader never " \
                 "saw, and it grades before showing the work, so there is nothing to check it " \
                 "against. It belongs to the same borrowed-load family as 'load-bearing': " \
                 "a building metaphor applied to a sentence."
    ),
    Rule.new(
      id: "does-a-lot-of-work",
      category: "rhetorical-tic",
      severity: "warning",
      # Two arms, both narrowed away from the ordinary sense.
      #
      # "a lot of work" needs a locative ("here", "in that sentence") because
      # the bare phrase is just a statement about effort -- she does a lot of
      # work for the shelter. The locative is what turns it into a remark
      # about a word on the page.
      #
      # "the heavy lifting" is left out entirely and only "a lot of heavy
      # lifting" is admitted: "the GPU does the heavy lifting" is ordinary
      # technical English and far commoner than the prose-criticism sense.
      pattern: /\b(?:does|do|doing|did)\s+a\s+lot\s+of\s+
                 (?:heavy\s+lifting\b|work\s+(?:here|in\s+th(?:at|is))\b)/ix,
      message: '"Does a lot of work here" grades the word instead of reading it.',
      suggestion: "Say what the word is doing, or what it hides.",
      examples_bad: [
        "That qualifier does a lot of work here.",
        "The word \"mostly\" is doing a lot of heavy lifting.",
        "\"Reasonable\" does a lot of work in that sentence."
      ],
      examples_ok: [
        "The GPU does the heavy lifting.",
        "She does a lot of work for the shelter.",
        "They did the heavy lifting on the migration."
      ],
      rationale: "The remark points at a word and rates its load without saying what the load " \
                 "is, so the reader learns that something is being smuggled but never what. " \
                 "It is the same borrowed-load metaphor as 'load-bearing', one step further " \
                 "from the building."
    ),
    # ── puffery ───────────────────────────────────────────────────────────
    Rule.new(
      id: "puffery-words",
      category: "puffery",
      severity: "warning",
      # "nestled" alone is the literal verb as often as the puffery sense --
      # a head nestling against a shoulder, a kitten nestling into a blanket
      # -- so it requires a following in/among/between, the same shape the
      # travel-brochure cliché actually takes ("nestled in the hills").
      pattern: /\b(?:boasts\s+a\b|vibrant|nestled\b(?:\s+\S+){0,2}?\s+(?:in|among|between)\b|
                  in\s+the\s+heart\s+of\s+(?:the\s+\w+|downtown\b|(?-i:[A-Z])\w+)|
                  groundbreaking|renowned|diverse\s+array|breathtaking|
                  natural\s+beauty|indelible\s+mark|deeply\s+rooted|
                  stands\s+as\s+a\s+testament|rich\s+(?:history|cultural|heritage))/ix,
      message: "Wikipedia-style puffery word/phrase — a common AI tell.",
      suggestion: "Replace with a concrete, specific detail or cut it.",
      examples_bad: [
        "The vibrant city, nestled in the heart of the valley.",
        "A boutique hotel in the heart of Paris.",
        "A cottage nestled snugly among the pines."
      ],
      examples_ok: [
        "The city sits at the north end of the valley.",
        # Moby-Dick: "in the heart of" used as spatial/emphatic idiom, not a
        # place-description cliché — the narrow trigger requires a definite
        # or proper noun object, which this lacks.
        "You cannot sit motionless in the heart of these perils.",
        "helpless Ahab, even in the heart of such a whirlpool as that",
        # Austen, Emma: "nestled" as the physical verb, not the scene-setting
        # adjective -- no following in/among/between, so the narrowed trigger
        # leaves it alone.
        "He had nestled down his head most conveniently.",
        "The kitten nestled into the blanket."
      ],
      rationale: "Travel-brochure adjectives and phrases that models reach for and careful " \
                 "writers avoid."
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
      # "underscored/underscoring" are unambiguously the verb and flag bare.
      # "underscore/underscores" is also the character noun (a leading
      # underscore, snake_case docs), so those forms require a following
      # determiner/wh-word -- the frame the emphasis verb takes, which the
      # noun never precedes. That guard also skips bare-noun objects
      # ("underscores concerns about"), an accepted miss: widening the frame
      # to catch them readmits the noun sense. Token gaps cross a
      # hard-wrapped line but never a paragraph break. highlights/emphasizes
      # stay narrowed to the importance/significance frame -- both verbs are
      # too common in ordinary prose to match broadly.
      pattern: /\bunderscor(?:ed|ing)\b
               |\bunderscores?(?:[ \t]|\r?\n(?![ \t]*\r?\n))+
                 (?:a|an|the|its|his|her|their|our|your|my|this|that|these|those|what|why|how|just)\b
               |\b(?:highlights|emphasizes)\s+(?:its|the|their)\s+(?:importance|significance)\b/ix,
      message: '"underscores" as emphasis (or "highlights/emphasizes its importance") is stock AI framing.',
      suggestion: "Show why it matters rather than asserting that it does.",
      examples_bad: [
        "This underscores its importance to the field.",
        "The delay underscores the need for better tooling.",
        "The outage underscored how fragile the pipeline was.",
        "Underscoring the urgency, the board met twice.",
        "The results underscore a deeper problem with the method.",
        "The report underscores just how far behind we are.",
        "It underscores that the market has moved on.",
        "The essay highlights its importance at length.",
        "This emphasizes the significance of early testing."
      ],
      examples_ok: [
        "Replace each space with an underscore.",
        "Variable names use underscores instead of dashes.",
        "The underscore character separates words in snake case.",
        "Prefix private methods with a leading underscore.",
        "Ruby numeric literals accept underscores for readability.",
        "Two underscores mark a dunder method in Python.",
        "She highlights the key line in yellow.",
        "The paper emphasizes the method, not the results.",
        # A paragraph break never welds the noun onto the next sentence.
        "Numbers accept underscores\n\nThe next section covers floats."
      ],
      rationale: "Models reach for 'underscore' as an all-purpose emphasis verb -- findings " \
                 "underscore, outages underscore -- asserting significance without earning it. " \
                 "Sincere journalistic and academic use exists, hence info: a flag means the " \
                 "move is present, not that it's slop. The character noun never takes the " \
                 "verb's frame and stays out."
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
      # Two branches, both anchored on an explicit escalation word. (1) The
      # copula escalation: "is not just/only/merely/simply/solely A … but B".
      # (2) "not because A, but because B". The escalation word is what makes
      # these safe to ship at warning -- it is a deliberate authorial move, not
      # a shape ordinary prose falls into. The bare corrective without it
      # ("is not A but B") is a separate, quieter rule: not-x-but-y.
      #
      # Interior spans stop at a paragraph break so a heading or list item
      # cannot join up with the next paragraph's "But …".
      pattern: /(?:\bis|\bare|\bwas|\bwere|\bisn['’]t|\baren['’]t|\bwasn['’]t|\bweren['’]t|
                  \bit['’]s|\bthat['’]s|\bthis\s+is|\bthese\s+are|\bthose\s+are)
                 \s+not\s+(?:just|only|merely|simply|solely)\b
                 (?:[^.!?\n]|\n(?!\s*\n))*?\bbut\b(?:\s+also\b)?
                |
                \bnot\s+because\b(?:[^.!?;\n]|\n(?!\s*\n)){1,60}?\bbut\s+because\b/ix,
      message: '"not just A, but B" is a stock AI escalation structure.',
      suggestion: "Make the claim once; drop the 'not just… but' frame.",
      examples_bad: [
        "It's not just fast, but genuinely reliable.",
        "This is not just a tool, but a partner in your workflow.",
        "It is not merely fast but reliable.",
        "The issue is not solely technical but cultural.",
        "She stayed not because it was easy, but because it was hers."
      ],
      examples_ok: [
        "He is not tired.",
        # Federalist No. 44: a real correlative conjunction joining two verb
        # phrases, not a copula predicating two things of one subject.
        "This power ought not only to be established, but ought to be established.",
        "Not only that, but they looked embarrassed.",
        "not just to acquire users, but to build something people love.",
        # A paragraph break ends the span; the next paragraph's "but" is not B.
        "He left not because of the noise\n\nbut because of the smell."
      ],
      rationale: "'X is not just A, but B' predicates two things of the same subject through a " \
                 "copula, which is the specific shape models overuse. Correlative 'not only… " \
                 "but' joining two verb phrases or clauses, without a preceding copula, is " \
                 "ordinary and common in formal human prose; requiring the escalation word " \
                 "keeps those out. The same logic covers 'not because A, but because B': the " \
                 "escalation word is what marks it deliberate."
    ),
    Rule.new(
      id: "not-x-but-y",
      category: "structure",
      severity: "info",
      # The bare corrective: "is not A but B", no escalation word, comma or no
      # comma. Ships at info because the line between a corrective ("not an
      # accident but a strategy") and an ordinary concession ("not warm but the
      # fire helped") is syntactic, and a regex cannot see syntax. What is here
      # is a set of cheap narrowings that cut the worst of the noise: A is
      # capped at one word after an optional article, "so" is excluded to spare
      # the archaic "not so deep but that", degree words ("quite", "very") are
      # excluded because they open concessives, and B may not be a pronoun,
      # possessive, demonstrative, auxiliary, or quantifier.
      #
      # Those guards are a filter, not a decision procedure. They still let
      # through a concession whose second clause opens with a noun phrase
      # ("was not warm but the fire helped") or a bare lexical verb ("was not
      # perfect but got us there"), because neither is distinguishable from the
      # corrective by surface form. That is the cost of the rule and the reason
      # it is info: the agent reading the flag has the context to judge, and
      # should. Do not chase these by growing the B-list -- every word added
      # silently narrows recall with nothing pinning it.
      pattern: /(?:\bis|\bare|\bwas|\bwere|\bisn['’]t|\baren['’]t|\bwasn['’]t|\bweren['’]t|
                  \bit['’]s|\bthat['’]s|\bthis\s+is|\bthese\s+are|\bthose\s+are)
                 \s+not\s+
                 (?!so\b|just\b|only\b|merely\b|simply\b|solely\b|even\b|yet\b|quite\b|very\b
                   |too\b|all\b|always\b|enough\b)
                 (?:a\s+|an\s+|the\s+)?[\w'’-]+
                 ,?(?:[ \t]|\r?\n(?!\s*\n))+but(?:[ \t]|\r?\n(?!\s*\n))+
                 (?:rather(?:[ \t]|\r?\n(?!\s*\n))+)?
                 (?!also\b|that\b|this\b|these\b|those\b|they\b|it\b|he\b|she\b|we\b|you\b|i\b
                   |his\b|her\b|their\b|its\b|my\b|your\b|our\b|there\b|then\b|still\b|now\b
                   |is\b|was\b|are\b|were\b|has\b|had\b|have\b|will\b|would\b|could\b|should\b
                   |may\b|might\b|must\b|can\b|to\b|as\b|if\b|when\b|because\b|not\b|no\b|never\b
                   |nor\b|neither\b|every\w*\b|nobody\b|none\b|some\b|somebody\b|someone\b
                   |anyone\b|anybody\b|anything\b|nothing\b|many\b|most\b|few\b)
                 (?:a\s+|an\s+|the\s+)?[\w'’-]+/ix,
      message: '"not A but B" is the bare AI corrective frame.',
      suggestion: "Make the claim once; drop the 'not… but' frame.",
      examples_bad: [
        "The delay was not an accident but a strategy.",
        "The delay was not an accident, but a strategy.",
        "The problem is not misconduct but tone.",
        "It's not a bug but a feature.",
        "That's not an accident but a strategy."
      ],
      examples_ok: [
        # Comma concessive with a pronoun subject: a contrast, not a correction.
        "He was not handsome, but he was kind.",
        # B-side pronoun: concession that continues the sentence.
        "The results are not conclusive but they point in the right direction.",
        # Archaic "not so X but that", common in 19th-century prose.
        "The stream is not so deep but that we may ford it.",
        # A capped at one word: multi-word predicates stay unflagged.
        "The evening was not particularly warm but everyone stayed late.",
        # B-side possessive, with the comma allowed.
        "The house was not large, but its garden ran clear to the river.",
        # Bare "every" on the B side, not just "everyone"/"everything".
        "It is not a bug but every case differs.",
        # A paragraph break ends the frame.
        "The result was not final\n\nBut the team moved on anyway."
      ],
      rationale: "The bare 'is not A but B' corrective is the 'not just… but' move with the " \
                 "escalation word dropped, and models reach for it constantly. It is the " \
                 "noisiest rule in the catalog by design: a loose version scored 174 hits " \
                 "before narrowing, cut to 15 here -- but not all 15 are correctives. Some " \
                 "are concessions with an elided subject (Walden's " \
                 "'It was not lonely, but made all the earth lonely beneath it'), which no " \
                 "surface pattern can tell apart from the real thing. Hence info: a flag here " \
                 "means 'this has the shape', not 'this is slop'."
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
    # clause-triad-then was cut. The pattern (comma-clause, comma-clause,
    # "then" clause) had no way to require the clauses actually be parallel
    # process steps -- against a 1M-word human corpus it went 0-for-40 on its
    # own description, catching ordinary conditionals ("when A, and B, then
    # C") and unrelated comma-separated fragments instead. A skip for leading
    # if/when/once didn't hold up either: real conditionals don't reliably
    # announce themselves at the match boundary ("but, when he does speak,
    # then...", elliptical legal "shall... then..."). It was also the most
    # expensive rule in the catalog at 65% of scan time on 1MB. Per
    # CLAUDE.md: some tells can't be regexes; this was one.
    Rule.new(
      id: "em-dash",
      category: "structure",
      severity: "info",
      pattern: /—/,
      message: "Em dash — an AI punctuation tell.",
      suggestion: "Recast with a comma, parentheses, or a separate sentence.",
      examples_bad: [
        "It was — surprisingly — the best option.",
        "The fix is simple — do less."
      ],
      examples_ok: [
        # Hyphen in a compound modifier -- not the U+2014 this rule targets.
        "The state-of-the-art model shipped on time.",
        # En dash (U+2013) in a range: a different character entirely.
        "See pages 12–18 for the full account."
      ],
      rationale: "Models reach for the em dash by default; humans use it too, but far less " \
                 "often."
    ),
    Rule.new(
      id: "em-dash-overuse",
      category: "structure",
      severity: "warning",
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
      rationale: "Three or more em dashes packed into one paragraph is a denser interjection " \
                 "habit than most human writing settles into."
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
