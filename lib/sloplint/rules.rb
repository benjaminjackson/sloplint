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

  # A paragraph break: a newline, a line holding nothing but spaces (a
  # non-breaking space among them, since the editors that emit curly
  # apostrophes emit those), and another newline.
  PARA_BREAK = /\r?\n[ \t\u00A0]*\r?\n/

  # A gap that may hard-wrap but never crosses a paragraph break. A
  # non-breaking space is a gap too. thats-the-whole, is-the-whole-x and
  # WHOLE_CLOSERS share it.
  WRAP_GAP = /(?:[ \t\u00A0]|(?!#{PARA_BREAK})\r?\n)/

  # The nouns "that's the whole N" closes on. thats-the-whole owns the
  # demonstrative form and is-the-whole-x yields it, so both patterns
  # interpolate this one fragment and the lists cannot drift. "value" and
  # "fix" must end the sentence or the paragraph, or run into one of the
  # words a closer trails off on (a preposition, a pronoun, a determiner,
  # "right", "though", "now"), because "value chain", "value-add" and
  # "fix list" name things. The older nouns compound too ("game plan") and
  # ship as
  # they always have; only the two new ones were probed for it. The list
  # of tails is an allowlist and stays one: a blocklist of compound heads
  # would widen every time a new compound turned up. A hyphen or an
  # apostrophe ends the closer only after a gap, since with no gap it is
  # part of the compound; an opening delimiter after a gap (an emphasis
  # marker, a backtick, a quote, a bracket) is not an end either, since it
  # opens the next word ("value *chain*", "fix `list`"). Under --markdown
  # a code span is blanked to spaces and the tail after it reads as the
  # closer's; that is the blanking's cost, not this one's. A numbered list
  # item on the next line ends the closer like a bullet does. Prepositions
  # stay tails although "value at risk" and "value for money" name things;
  # a tail list is not the place to enumerate compounds. The
  # gap may hard-wrap but never crosses a paragraph break, so
  # "value\nchain" is still the compound, and a heading, which ends at a
  # blank line, still ends on the noun. The character classes are
  # Unicode-aware, so a non-breaking space is a space and an accented
  # letter is a letter.
  WHOLE_CLOSERS = /point|game|thing|deal|story|ballgame|ball#{WRAP_GAP}+game|(?:value|fix)(?=[^[:word:][:space:]'’-]|#{WRAP_GAP}+(?:[^[:word:][:space:]*_`"'‘“(\[{~]|\d+[.)][ \t])|#{WRAP_GAP}*(?:\z|#{PARA_BREAK}|(?:of|to|for|in|on|at|with|here|there|behind|right|though|now|anyway|really|from|over|after|and|but|so|as|that|which|if|when|because|since|unless|until|once|while|where|i|we|you|he|she|it|they|the|a|an|this|these|those|every|any|my|our|your|his|her|their|its)\b))/i

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
      # The nouns are WHOLE_CLOSERS. "value" and "fix" are the closers agents
      # write in technical prose ("That's the whole fix"), where the
      # contraction keeps them out of is-the-whole-x, which sees only "is".
      # Either apostrophe counts; editors emit the curly one.
      pattern: /\b(?:that|this)(?:['’]s|#{WRAP_GAP}+is)#{WRAP_GAP}+the#{WRAP_GAP}+whole#{WRAP_GAP}+(?:#{WHOLE_CLOSERS})\b/i,
      message: '"That\'s the whole point/game/…" is a stock LLM closer.',
      suggestion: "Say the point directly instead of announcing it.",
      examples_bad: [
        "That's the whole point.",
        "That's the whole value of a typed error.",
        "That's the whole fix; the cache was already right.",
        "That’s the whole value here.",
        "That's the whole fix right there.",
        "That's the whole fix that was needed.",
        "That's the whole fix the reviewer asked for.",
        # A blank line holding only a non-breaking space is still blank.
        "## That's the whole fix\n\u00A0\nApply it.",
        # A dash or a bullet after a gap ends the closer; only a glued
        # hyphen joins a compound.
        "That's the whole fix -- the cache was already right.",
        "- Cache key was stale.\n- That's the whole fix\n- Tests pass.",
        "2. That's the whole fix\n3. Tests pass.",
        # A heading ends on the noun with no full stop.
        "## That's the whole fix\n\nApply it and rerun the suite."
      ],
      examples_ok: [
        "This is the whole cake.",
        # An unlisted noun stays clean, however closer-shaped the sentence.
        "That's the whole history of the case.",
        # "value" and "fix" running on into a compound name a thing.
        "That's the whole value chain, end to end.",
        "That's the whole value\nchain, end to end.",
        # The gap is a non-breaking space.
        "That's the whole value\u00A0chain, end to end.",
        "That's the whole value *chain*, end to end.",
        "That's the whole fix `list` for the release.",
        "That's the whole fix (list) for the release.",
        "That's the whole value-add of the consultant.",
        "That's the whole value's worth.",
        "That's the whole fix list for the release.",
        # A paragraph break is not a gap, inside the two-word noun or
        # before any noun.
        "That's the whole ball\n\ngame.",
        "That's the whole\n\npoint."
      ],
      rationale: "The 'that's the whole X' flourish is a model tic for landing a paragraph."
    ),
    Rule.new(
      id: "is-the-whole-x",
      category: "rhetorical-tic",
      severity: "info",
      # The generic form of thats-the-whole: a subject, then "is the whole /
      # real / actual / entire N" with N from a closed abstract list. "That
      # periodicity is the whole tell.", "Consistency is the real test." The
      # match opens on the subject's last word, so the note points at the
      # sentence and not at a space. Two older rules own two exact shapes,
      # and those are yielded so nothing is reported twice: "that/this is
      # the whole N" for every N in WHOLE_CLOSERS to thats-the-whole (the
      # lookahead interpolates the same fragment), and "is the entire
      # point/game/thing/deal/story" to is-the-entire; every
      # other subject and noun flags here, so "This is the real test." is
      # not lost. A question is not a closer, so an interrogative subject
      # (what, which, who, where, when, how) is out. "only" is left out
      # because "is the only thing" is ordinary speech; "deal", "thing" and
      # "cost" because "the real deal", "the real thing" and "the whole cost"
      # are idioms or quantities. The noun may not run on into a compound
      # ("problem-solver"). Gaps may cross a hard-wrapped newline but never
      # a paragraph break. Ships at info because "the real question" and
      # "the whole point" are also how people talk.
      pattern: /(?<![\w'’-])
                (?!(?:that|this)#{WRAP_GAP}+(?:is)#{WRAP_GAP}+(?:the)#{WRAP_GAP}+(?:whole)#{WRAP_GAP}+(?:#{WHOLE_CLOSERS})(?![\w'’-]))
                (?!(?:what|which|who|where|when|how)(?![\w'’-]))
                [\w'’-]+#{WRAP_GAP}+(?:is)#{WRAP_GAP}+(?:the)#{WRAP_GAP}+
                (?:(?:whole|real|actual)#{WRAP_GAP}+(?:tell|point|game|story|trick|question|problem|issue|lesson|job|work|move|test|signal|difference|answer|risk|goal|reason|pattern|insight|takeaway|shift|bet|win|catch|gap|bottleneck|value|skill|challenge|fix)
                  |entire #{WRAP_GAP}+(?!(?:point|game|thing|deal|story)(?![\w'’-]))(?:tell|point|game|story|trick|question|problem|issue|lesson|job|work|move|test|signal|difference|answer|risk|goal|reason|pattern|insight|takeaway|shift|bet|win|catch|gap|bottleneck|value|skill|challenge|fix))(?![\w'’-])/ix,
      message: '"… is the whole/real N" is a stock LLM closer.',
      suggestion: "Say the point directly instead of ranking it.",
      examples_bad: [
        "That periodicity is the whole tell.",
        "Consistency is the real test.",
        "Getting the handoff right is the actual work.",
        # Not thats-the-whole's nouns, so not yielded.
        "This is the real test.",
        "That is the actual problem.",
        # "entire" with a noun is-the-entire does not own.
        "Timing is the entire tell.",
        # A hard-wrapped closer survives one newline.
        "Consistency\nis the real test."
      ],
      examples_ok: [
        # Left to thats-the-whole, an old noun and a widened one.
        "That is the whole point.",
        "That is the whole fix.",
        # Left to is-the-entire.
        "Timing is the entire game.",
        # "only" is ordinary speech.
        "Sleep is the only thing that helps.",
        "The real question was never asked.",
        # Idioms and quantities.
        "Clojure is the real deal, and so is the REPL.",
        "The 1962 recording is the real thing.",
        "The remaining balance is the whole cost of the repair.",
        # A compound with a listed noun.
        "She is the real problem-solver on the team.",
        # A question is not a closer.
        "What is the real difference between the two plans?",
        "Nobody knows what is the actual cost of storage.",
        # A paragraph break is not a gap.
        "Consistency\n\nis the real test."
      ],
      rationale: "Ranking a claim as 'the whole point' or 'the real test' is how a model " \
                 "lands a paragraph without adding to it. People say it too, so one is a " \
                 "question; several in a draft should be read as a warning."
    ),
    Rule.new(
      id: "bare-equative",
      category: "rhetorical-tic",
      severity: "info",
      # A sentence that opens on an abstract head noun and equates it with
      # something: "The tell here is the periodicity.", "The problem is not
      # the tool.", "The lesson is the handoff." The head noun list is closed
      # and holds only nouns that cannot name an object, the same list
      # the-x-is-the-x uses: "the key is the brass thing on the hook" and
      # "the cost is the price of the ticket" are definitions that tell the
      # reader something. The sentence must start on "The", at a sentence
      # start or after a list marker, and the copula ("is", "is not",
      # "isn't") must be followed by "the" and a lowercase word, so a
      # predicate adjective ("The problem is real"), an indefinite ("The
      # answer is a mess"), a pointing complement ("the same", "the one",
      # "the first"), and a proper noun ("the Slack thread") are all out.
      # Gaps may cross a hard-wrapped newline but never a paragraph break.
      # Ships at info: "The problem is the cost" is how people write too, at
      # about four per million words on Hacker News; it is the density that
      # tells.
      pattern: /(?:^|(?<=[.!?])[ \t]{1,2})(?:[-*+•][ \t]+|\d+[.)][ \t]+)?\KThe(?:[ \t]|\r?\n(?!\s*\n))+
                (?:tell|point|question|problem|issue|lesson|difference|trick|move|risk|goal|reason|pattern|insight|takeaway|shift|bet|catch|gap|bottleneck|failure|mistake|secret|magic|challenge|tension|trap)(?:[ \t]|\r?\n(?!\s*\n))+
                (?:here(?:[ \t]|\r?\n(?!\s*\n))+)?is(?:n['’]t|(?:[ \t]|\r?\n(?!\s*\n))+not)?(?:[ \t]|\r?\n(?!\s*\n))+ the(?:[ \t]|\r?\n(?!\s*\n))+(?!(?:one|same|only|first|last|best|worst|next|other|latter|former)\b)(?-i:(?=[a-z]))/x,
      message: '"The X is the Y." is the AI definitional equative.',
      suggestion: "Say what the thing does or why it matters, instead of what it equals.",
      examples_bad: [
        "The tell here is the periodicity.",
        "The lesson is the handoff, not the tool.",
        "The problem is not the tool. It is the habit.",
        "The problem isn't the handoff.",
        # The pair's usual habitat.
        "- The point is the cadence.",
        # A hard-wrapped equative survives one newline.
        "The problem is the\ncost."
      ],
      examples_ok: [
        "The problem is real.",
        "The answer is a mess of caveats.",
        # Not at a sentence start.
        "We think the problem is the handoff.",
        # Concrete heads are definitions.
        "The key is the brass thing on the hook.",
        "The cost is the price of the ticket plus tax.",
        # Pointing complements.
        "The story is the one she told last week.",
        "The reason is the same: space.",
        "The point is the first item on the list.",
        # A proper noun.
        "The tell is the Slack thread.",
        # A paragraph break is not a gap.
        "The problem is the\n\ncost."
      ],
      rationale: "Opening on an abstract noun and equating it with a second noun phrase " \
                 "states a diagnosis as a definition, which sounds settled and explains " \
                 "nothing. People write the shape too, so one is a question; several in " \
                 "a draft should be read as a warning."
    ),
    Rule.new(
      id: "epistrophe",
      category: "rhetorical-tic",
      severity: "info",
      default_on: false,
      # Two clauses that end on the same two-word phrase, the second closing
      # the sentence: "built for one desk, and almost no job is done at one
      # desk." Two backreferences catch the repeat, one per word, so the
      # phrase may be hard-wrapped at either occurrence. The phrase may not
      # open on an article, since "in the report, and … in the report" is
      # ordinary; its second word must be four letters or more; and the
      # second clause is five to sixty characters with no internal
      # punctuation, opening on a word, with whitespace runs capped at two
      # spaces (or a hard wrap with a small indent), so a code span or URL
      # blanked by --markdown cannot weld a false repeat. Off by default:
      # this is a named figure that Emerson and Marcus Aurelius use on
      # purpose, and on Hacker News most hits are ordinary phrase reuse
      # ("what we said, not what the minutes say we said"), so the rate is
      # above what an info rule should carry. Select it when a draft is
      # suspected of leaning on it.
      pattern: /\b((?!the\b|a\b|an\b)[\w'’-]+)(?:[ \t]|\r?\n(?!\s*\n)[ \t]{0,4})+([\w'’-]{4,}),(?:[ \t]{1,2}|\r?\n(?!\s*\n)[ \t]{0,4})(?:(?:and|but)(?:[ \t]|\r?\n(?!\s*\n)[ \t]{0,4})+)?
                (?=\w)(?:[^.,;:!?\n\s]|(?<![ \t])[ \t]{1,2}(?![ \t])|\r?\n(?!\s*\n)[ \t]{0,4}){5,60}?\b\1(?:[ \t]|\r?\n(?!\s*\n)[ \t]{0,4})+\2[.!?]/ix,
      message: "Two clauses ending on the same phrase (epistrophe) read as AI cadence.",
      suggestion: "Vary the second ending, or cut the repeat.",
      examples_bad: [
        "The tool was built for one desk, and almost no job is done at one desk.",
        "They wanted a shared file, but nobody would maintain a shared file.",
        # A hard-wrapped repeat survives one newline, in either clause.
        "The tool was built for one desk, and almost no job\nis done at one desk.",
        "The tool was built for one\ndesk, and almost no job is done at one desk."
      ],
      examples_ok: [
        "The tool was built for one desk, and almost no job is done alone.",
        # A repeat across a sentence boundary is two sentences.
        "They wanted a shared file. Nobody would maintain a shared file.",
        # An article-led phrase is ordinary repetition.
        "It was in the report, and the numbers were in the report.",
        # The second word must be four letters or more.
        "I like the blue one, and she likes the blue one.",
        # The second clause is at most sixty characters.
        "The tool was built for one desk, and almost no job anywhere in the whole company across all of its many offices is done at one desk.",
        # No internal punctuation in the second clause.
        "The tool was built for one desk, and, as it happens, no job is done at one desk.",
        # Blanked text cannot make the second clause.
        "It was tuned for one desk, and                                   on one desk."
      ],
      rationale: "Ending consecutive clauses on the same phrase is a figure of emphasis, " \
                 "and a model reaches for it whenever it wants a sentence to land. People " \
                 "use it too, and much of what the pattern catches is plain phrase reuse, " \
                 "which is why the rule is off by default; when selected, several in a " \
                 "draft should be read as a warning."
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
      id: "from-x-to-y-chain",
      category: "rhetorical-tic",
      severity: "warning",
      # Two or more "from X to Y" spans in a row, comma-separated: "from
      # private notes to shared files, from personal memory to team context".
      # Each span is "from", one to three words, "to", one to three words; the
      # comma between spans is the evidence of authored parallelism, as in
      # no-x-no-y, so a chain never crosses a sentence boundary. Every operand
      # must open with a letter, so a list of ranges ("from 1990 to 1995, from
      # 1997 to 2001", "from 9 to 5") is not a chain. The last span is bounded
      # too: its Y must run into punctuation, a conjunction or preposition, a
      # wh-word, or the end of the text, so the excerpt never carries the
      # opening of the next clause.
      #
      # Two human shapes share the surface and are skipped. The relay, where
      # each span starts where the last one ended ("from the egg to the worm,
      # from the worm to the fly"), traces a sequence: the second "from"
      # repeating the first "to" drops the note. The reduplication, "from
      # hummock to hummock, from root to root", describes motion: a span whose
      # two ends are the same words drops it. Both backreferences must close
      # on a whole operand, so "work-life" is not a relay of "work" and "code
      # review" is not a reduplication of "code".
      #
      # A list of concrete mappings ("from MySQL to Postgres, from Redis to
      # Memcached") has the same surface and flags. That is an accepted cost:
      # the shape is one hit in 2.4M words of Hacker News, and the note says
      # what to check.
      pattern: /\bfrom\s+(?=[a-z])(?:[\w'-]+\s+){1,3}to\s+(?=[a-z])(?:[\w'-]+\s+){0,2}[\w'-]+
                (?:,\s+(?:and\s+)?from\s+(?=[a-z])(?:[\w'-]+\s+){1,3}to\s+(?=[a-z])(?:[\w'-]+\s+){0,2}[\w'-]+)+
                (?=[^\w\s'-]|\s+(?:and|or|but|in|on|at|by|with|within|over|across|as|when|while|which|that|so|because|what|how|why|who)\b|\s*\z)/ix,
      message: '"from X to Y, from X to Y" chain (%{count} spans) reads as AI cadence.',
      suggestion: "Keep one span, or name the things instead of sweeping across them.",
      # Span heads only, so a "from" inside an operand is not a span.
      count_group: /(?:\A|,\s+(?:and\s+)?)from\b/i,
      skip: [
        # The relay: "to the worm, from the worm".
        /\bto\s+(?:[\w'-]+\s+){0,2}([\w'-]+),\s+(?:and\s+)?from\s+(?:[\w'-]+\s+){0,2}\1(?![\w'-])/i,
        # The reduplication: "from hummock to hummock".
        /\bfrom\s+(?:the\s+)?((?:[\w'-]+\s+){0,2}[\w'-]+)\s+to\s+(?:the\s+)?\1(?=,|\s*\z)/i
      ],
      examples_bad: [
        "The change is the move from scattered notes to one shared file, from habit to written rules, from solo effort to a team that can carry it.",
        "We went from guessing to measuring, from hoping to knowing.",
        "The plan takes them from the pilot to the rollout, and from the memo to the audit.",
        # The last span may run into a clause, as long as a joining word starts it.
        "We went from guessing to measuring, from hoping to knowing in a single quarter.",
        # Not a relay: "work-life" is not "work".
        "We went from rest to work, from work-life balance to burnout.",
        # Not a reduplication: "code review" is not "code".
        "We moved from code to code review, from guessing to measuring.",
        # A "from" inside an operand is not a span head.
        "The shift from revenue from ads to revenue from subscriptions, from hoping to knowing."
      ],
      examples_ok: [
        "The train runs from Boston to New York.",
        # Pride and Prejudice (Austen, public domain): the relay.
        "it jumps from admiration to love, from love to matrimony, in a moment.",
        # Walden (Thoreau, public domain): the reduplication.
        "jumping from hummock to hummock, from willow root to willow root, when the wild river valley",
        # A span longer than three words on either side is a clause, not an item.
        "He drove from the coast to the mountains in a day, and from there the road was easy.",
        # Two spans in separate sentences never chain.
        "She moved from Ohio to Maine. From there she wrote to him weekly.",
        # Ranges are not spans.
        "He served on the board from 1990 to 1995, from 1997 to 2001, and from 2005 to 2009.",
        "We are open from 9 to 5, from Monday to Friday."
      ],
      rationale: "Stacked 'from X to Y' spans are a model's way of gesturing at a whole " \
                 "transformation without describing any of it; each span names two poles and " \
                 "nothing between them. Human prose stacks the phrase for a sequence (each span " \
                 "picking up where the last ended) or for motion (the same word at both ends), " \
                 "and both of those are skipped. What remains is rare in careful writing; a list " \
                 "of concrete mappings (tools migrated, units converted) shares the shape and is " \
                 "the case to check before acting."
    ),
    Rule.new(
      id: "one-x-one-y",
      category: "rhetorical-tic",
      severity: "warning",
      # Three or more "one X" items in a comma chain that stands on its own:
      # "One owner, one repository, one weekly prune." or, after a colon,
      # "the setup is narrow: one reviewer, one queue, one deadline". The
      # determiner is the cadence; the comma is the evidence of authored
      # parallelism, as in no-x-no-y.
      #
      # The chain must open a sentence or follow a colon, semicolon or dash.
      # That is the narrowing that separates the drumbeat from counting: "the
      # flat has one bedroom, one bathroom, one balcony" and "add one egg, one
      # onion, one carrot" hang off a verb, and there the word is doing
      # arithmetic. Each item is "one" plus one or two letter-led words (never
      # "and"/"or"), so an enumeration over numbers is not a chain; the
      # Oxford comma is optional after the first link; a gap may cross a
      # hard-wrapped newline but never a paragraph break; and the last item
      # must run into punctuation, a joining word, or the end of the text, so
      # the excerpt never carries the opening of the next clause. The
      # distributive "one for you, one for me, one for the pot" is skipped at
      # any length, and a pair never flags: two is distribution, three is a
      # drumbeat.
      #
      # Verse keeps the shape on purpose ("One face, one voice, one habit, and
      # two persons"), and that is an accepted cost.
      pattern: /(?:^|(?<=[.!?:;—–])[ \t]{1,2})\K
                one[ \t]+(?=[a-z])[\w'’-]+(?:[ \t]+(?!and\b|or\b)(?=[a-z])[\w'’-]+)?
                ,(?:[ \t]|\r?\n(?!\s*\n))+(?:and(?:[ \t]|\r?\n(?!\s*\n))+)?
                one[ \t]+(?=[a-z])[\w'’-]+(?:[ \t]+(?!and\b|or\b)(?=[a-z])[\w'’-]+)?
                (?:(?:,(?:[ \t]|\r?\n(?!\s*\n))+(?:and(?:[ \t]|\r?\n(?!\s*\n))+)?|(?:[ \t]|\r?\n(?!\s*\n))+and(?:[ \t]|\r?\n(?!\s*\n))+)
                   one[ \t]+(?=[a-z])[\w'’-]+(?:[ \t]+(?!and\b|or\b)(?=[a-z])[\w'’-]+)?)+
                (?=[^\w\s'’-]|\s+(?:and|or|but|in|on|at|by|with|for|to|of|from|per|each|that|which|who|when|where|so|because|is|are|was|were)\b|\s*\z)/ix,
      message: '"one X, one Y, one Z" chain (%{count} items) reads as AI cadence.',
      suggestion: "Cut the chain or make it one plain sentence.",
      # Item heads only, so a "one" inside an item is not an item.
      count_group: /(?:\A|,\s+(?:and\s+)?|\s+and\s+)one\b/i,
      # The distributive frame, at any length.
      skip: [/(?:\bone\s+for\b[\s\S]*?){3}/i],
      examples_bad: [
        "The setup is deliberately narrow: one reviewer, one queue, one deadline.",
        "One owner, one repository, one weekly prune.",
        # No Oxford comma.
        "One name, one number and one date.",
        # A curly apostrophe is a word character here.
        "One team’s lead, one owner, one date.",
        # A hard-wrapped chain survives one newline.
        "One owner, one repository,\none weekly prune."
      ],
      examples_ok: [
        "One for you, one for me.",
        "One for you, one for me, one for the pot.",
        "We keep three bins: one for 2019, one for 2020, one for 2021.",
        "One of them left, and the other one stayed.",
        # After a verb the word is counting.
        "The flat has one bedroom, one bathroom, one balcony.",
        "Add one egg, one onion, one carrot and simmer for an hour.",
        "The season ended with one win, one loss, one draw.",
        # Essays: First Series (Emerson, public domain): not at a clause start.
        "Not for nothing one face, one character, one fact, makes much impression on him",
        # Items in separate sentences never chain.
        "One person wrote it in the morning. One person read it after lunch. One person filed it at the end of the day.",
        # A paragraph break ends the chain.
        "He carried one bag, one coat,\n\nOne question remained unanswered."
      ],
      rationale: "A drumbeat of 'one' items is a model's way of making a setup sound " \
                 "spare and inevitable; the word does no counting, it sets a rhythm. " \
                 "The chain has to stand on its own, at a sentence start or after a " \
                 "colon, because after a verb the word is counting and the shape is " \
                 "ordinary. Careful writers distribute in pairs and rarely stack three."
    ),
    Rule.new(
      id: "and-what-it-should",
      category: "rhetorical-tic",
      severity: "warning",
      # The elliptical tail: "List what the assistant knows about the client,
      # and what it should." The second "what" clause borrows its verb from the
      # first and ends on a bare modal or a negated auxiliary, so the sentence
      # closes on a contrast it never states. The comma, the conjunction, and
      # the full stop right after the modal are all required; "and what it
      # should do" is a complete clause and does not flag. The affirmative
      # copula and do-verb ("and what he does.", "and what it is.") are left
      # out: those are complete clauses with a main verb, not ellipsis. A
      # question mark is left out too, because an interrogative licenses the
      # ellipsis ("what does it cover, and what doesn't it?"). Gaps may cross
      # a hard-wrapped newline but never a paragraph break.
      pattern: /,(?:[ \t]|\r?\n(?!\s*\n))+(?:and|but|or)(?:[ \t]|\r?\n(?!\s*\n))+what(?:[ \t]|\r?\n(?!\s*\n))+(?:it|they|you|we|he|she|one|i)(?:[ \t]|\r?\n(?!\s*\n))+
                (?:(?:should|could|would|must|can|will|might|may)(?:(?:[ \t]|\r?\n(?!\s*\n))+not|n['’]t)?
                  |cannot|(?:does|did|is|was|has|have|had|are|were)(?:(?:[ \t]|\r?\n(?!\s*\n))+not|n['’]t))[.!]/ix,
      message: '"…, and what it should." is the AI elliptical tail.',
      suggestion: "Finish the clause, or cut it.",
      examples_bad: [
        "List what the assistant knows about the client, and what it should.",
        "List what the tool does, and what it doesn't.",
        "List what the tool does, and what it does not.",
        "Say what the team decided, but what it couldn't.",
        "List what I know about the client, and what I should.",
        "List what we cover, and what we haven't.",
        # A hard-wrapped tail survives one newline.
        "List what the model knows about the client,\nand what it should."
      ],
      examples_ok: [
        "List what the assistant knows about the client, and what it should know.",
        "He asked what it was, and what it should be called.",
        "Nobody knew what it cost or what it should.",
        "She wrote down what she saw. And what she should have seen, she added later.",
        # A main verb is a complete clause.
        "It is not what he says, but what he does.",
        "They knew what he did, and what he was.",
        # A question licenses the ellipsis.
        "Who decides what the policy covers, and what it doesn't?",
        # A paragraph break is not a comma.
        "List what the assistant knows,\n\nand what it should."
      ],
      rationale: "Ending on a bare modal makes the reader supply the verb and the " \
                 "contrast, which reads as poise in a model and as an unfinished sentence " \
                 "in a person. Careful writers finish the clause."
    ),
    Rule.new(
      id: "abstract-lives-in",
      category: "rhetorical-tic",
      severity: "info",
      # An abstraction given an address: "the craft that lives between the two
      # desks", "its context lives in a folder nobody else can open", "the
      # value sits in the follow-up". The subject list is closed and abstract,
      # so a person, a dog, or a house living or sitting somewhere never
      # matches, and a capitalised subject is skipped, so the messenger app
      # Signal sitting in the middle of a relay is not the figure (at the cost
      # of a sentence-initial "Context lives in", which is rare).
      #
      # Two prepositions are left out. "with" marks responsibility ("the
      # decision sits with the board"), and "at" marks a quantity ("the value
      # sits at ten million"); "at the intersection of" belongs to
      # intersection-of. Two verbs are left out too: "lies in" ("the problem
      # lies in the assumption") and "resides in" are ordinary English for
      # where a fault or an authority is, at any register.
      #
      # Ships at info. The same shape states where information literally is
      # ("the knowledge lives in our heads", "the instructions live in the
      # README"), and a sample of pre-2022 Hacker News biased toward the
      # construction turns up a few of those per million words, all human.
      # One flag is a question; a draft that keeps giving ideas addresses
      # should be read as a warning.
      pattern: /\b(?:work|context|knowledge|answer|value|truth|problem|risk|decision|instructions?|memory|leverage|power|magic|difference|opportunity|insight|advantage|gap|signal|nuance|meaning|tension|friction|complexity|craft|skill|expertise)(?:[ \t]|\r?\n(?!\s*\n))+
                (?:that(?:[ \t]|\r?\n(?!\s*\n))+|which(?:[ \t]|\r?\n(?!\s*\n))+)?(?:lives?|lived|sits?|sat)(?:[ \t]|\r?\n(?!\s*\n))+(?:in|between|inside|outside|beneath|behind|under|underneath)\b/ix,
      message: "An abstraction that lives/sits somewhere is an AI figure.",
      suggestion: "Say who does the work, or where the thing actually is.",
      # A capitalised subject is a proper noun.
      skip: [/\A[A-Z]/],
      examples_bad: [
        "The craft that lives between the two desks is where the handoff fails.",
        "Its context lives in a folder nobody else can open.",
        "The real value sits in the follow-up, not the meeting."
      ],
      examples_ok: [
        "She lives in Boston and sits between us at dinner.",
        # Responsibility, not location.
        "The decision sits with the board.",
        "The risk lives with the buyer once the goods ship.",
        # A quantity, not a location.
        "The value sits at ten million dollars a life.",
        # "on" is not in the list.
        "The knowledge lived on a server in the basement.",
        # An intervening noun breaks the figure.
        "The knowledge base lived in the basement.",
        # A proper noun.
        "Signal sits in the middle of the relay.",
        # "lies in" is ordinary English for where a fault is.
        "The problem lies in the assumption.",
        "He put the answer in the margin and sat between the two of them."
      ],
      rationale: "Giving an idea a location ('the value sits in', 'the work lives " \
                 "between') lets a writer sound precise about where something is without " \
                 "saying who does it or what it is. Models reach for it constantly, but " \
                 "people use the same shape to say where information literally is, so " \
                 "one flag is a question; a draft that keeps giving ideas addresses should " \
                 "be read as a warning."
    ),
    Rule.new(
      id: "the-x-is-the-x",
      category: "rhetorical-tic",
      severity: "warning",
      # The repeated-head equative: "the reason it holds up is the reason the
      # other half happens", "the problem with A is the problem with B". The
      # same abstract head noun sits on both sides of the copula, caught by a
      # backreference, so the sentence equates two things by declaring them
      # the same kind of thing.
      #
      # The noun list is closed and holds only heads that cannot name a
      # specific object: reason, problem, question, lesson and their kin.
      # "key", "cost", "value", "unit", "fix" and the like are out, because
      # "the key to the front door is the key on the red fob" is an identity
      # statement that tells the reader something. The clause between the
      # two heads is capped at fifty characters and may not hold a comma,
      # semicolon or colon, so the two heads sit in one clause and an earlier
      # "the cost was low, but shipping is the cost" never pairs; it may
      # cross a hard-wrapped newline. The second head must be followed by a
      # preposition, determiner, quantifier, pronoun, plural noun, or
      # punctuation, so a compound ("the answer key") is not a repeat. The
      # bare form ("the reason is the reason we came") and the contracted
      # negation ("isn't the reason") both count. The sentence-initial
      # capital is not required, so "and the reason … is the reason …"
      # flags too.
      pattern: /\bthe\s+(reason|problem|question|lesson|difference|trick|move|goal|tell|pattern|insight|takeaway|shift|bet|catch|bottleneck|issue|game|cause|failure|magic|challenge|tension|irony|paradox|trap)\b
                (?:[^.!?;:,\n]|\r?\n(?!\s*\n)){1,50}?\bis(?:n['’]t|\s+not)?\s+the\s+\1
                (?=[,.;:!?]|\s+(?:of|for|with|in|on|to|at|behind|about|that|which|why|here|there|the|a|an|this|these|those|my|our|your|their|its|his|her|it|they|we|you|i|he|she|every|each|most|many|some|any|no|nobody|everyone|people|[a-z]+s)\b)/ix,
      message: '"The X … is the X …" equates by repeating the head noun.',
      suggestion: "Say what the second thing is, not that it is the same kind of thing.",
      examples_bad: [
        "The reason it holds up is the reason the other half happens.",
        "The problem with the tool is the problem with the team.",
        "In practice the question for them is not the question for us.",
        "The problem with the tool isn't the problem with the team.",
        # The bare form.
        "The reason is the reason we came.",
        # A quantifier or a plural noun may follow the second head.
        "The reason people stay is the reason people leave.",
        "The problem with onboarding is the problem every team has.",
        "The lesson from the outage is the lesson most teams skip.",
        # A hard-wrapped clause survives one newline.
        "The reason\nit holds is the reason it fails."
      ],
      examples_ok: [
        "Rain is the reason we stayed home.",
        "Its cost is the reason we came late.",
        # Across a sentence boundary is two sentences.
        "The reason is simple. It is the reason we left.",
        # A compound noun is not a repeated head.
        "The answer to the first question is the answer key, not a guess.",
        # A semicolon or a comma is a boundary: the heads must share a clause.
        "Process is the issue; community process is the issue we can fix.",
        "The cost was low, but shipping is the cost we forgot.",
        "The reason was never clear, but timing is the reason it failed.",
        # Concrete heads are identity statements, not tautologies.
        "The key to the front door is the key on the red fob.",
        "The cost of shipping is the cost of the box plus postage."
      ],
      rationale: "Repeating the head noun across the copula asserts an identity between " \
                 "two things while naming neither; it sounds like a diagnosis and " \
                 "delivers a tautology. Careful writers say what the second thing is."
    ),
    Rule.new(
      id: "same-determiner-chain",
      category: "rhetorical-tic",
      severity: "info",
      # The quiet cousin of one-x-one-y and no-x-no-y: three or more items in
      # a comma chain that all open on the same determiner or quantifier,
      # caught with a backreference: "every faculty, every thought, every
      # emotion", "your inbox, your calendar, your task list", "more work,
      # more meetings, more email". "one" and "no" are left to their own
      # rules. The narrative possessives (my, his, her, their, its) are left
      # out: "his fame, his position, his life" is every novelist's, and it
      # doubled the human rate. Ships at info because this is a rhetorical
      # device humans own too, Emerson above all; a model uses it the way it
      # uses the others, as a default cadence, and several in one draft is
      # the tell. The Oxford comma is optional after the first link, a gap may
      # cross a hard-wrapped newline but never a paragraph break, and the last
      # item must run into punctuation, a joining word, a modal or common
      # verb, or the end of the text. A verb or adverb the list does not know
      # can still be swallowed as the last item's second word ("every deploy
      # today"); the count is right and the over-reach is one word. The
      # letter-led guards are case-sensitive on purpose: under /i they would
      # let "New York, New Jersey, New Hampshire" through as a chain.
      pattern: /\b(every|each|your|our|more|less|fewer|same|any|another|zero|new|real|true)[ \t]+(?-i:(?=[a-z]))[\w'’-]+(?:[ \t]+(?!and\b|or\b)(?-i:(?=[a-z]))[\w'’-]+)?
                ,(?:[ \t]|\r?\n(?!\s*\n))+(?:and(?:[ \t]|\r?\n(?!\s*\n))+)?
                \1[ \t]+(?-i:(?=[a-z]))[\w'’-]+(?:[ \t]+(?!and\b|or\b)(?-i:(?=[a-z]))[\w'’-]+)?
                (?:(?:,(?:[ \t]|\r?\n(?!\s*\n))+(?:and(?:[ \t]|\r?\n(?!\s*\n))+)?|(?:[ \t]|\r?\n(?!\s*\n))+and(?:[ \t]|\r?\n(?!\s*\n))+)
                   \1[ \t]+(?-i:(?=[a-z]))[\w'’-]+(?:[ \t]+(?!and\b|or\b)(?-i:(?=[a-z]))[\w'’-]+)?)+
                (?=[^\w\s'’-]|\s+(?:and|or|but|in|on|at|by|with|for|to|of|from|per|than|that|which|who|when|where|so|because|is|are|was|were|will|would|can|could|should|must|may|might|has|have|had|do|does|did|all|every|each|need|needs|make|makes|bring|brings|matter|matters|today|now|then|here|there)\b|\s*\z)/ix,
      message: 'Repeated-determiner chain (%{count} items) reads as AI cadence.',
      suggestion: "Cut the chain or make it one plain sentence.",
      count_group: /(?:\A|,\s+(?:and\s+)?|\s+and\s+)(?:every|each|your|our|more|less|fewer|same|any|another|zero|new|real|true)\b/i,
      examples_bad: [
        "It touches every file, every branch, every deploy.",
        "You get more work, more meetings, and more email.",
        "Your inbox, your calendar, your task list.",
        # No Oxford comma.
        "It touches every file, every branch and every deploy.",
        # A chain as the subject of a clause.
        "Every test, every lint, every build must pass.",
        "You get more work, more meetings, and more email every day.",
        # A hard-wrapped chain survives one newline.
        "Every file, every branch,\nevery deploy."
      ],
      examples_ok: [
        "Every file and every branch was checked.",
        # Two items is a pair, not a chain.
        "Every file, every branch.",
        # The determiner must repeat; a mixed list is a list.
        "Every file, each branch, and some deploys.",
        "We bought more bread, some milk, and a dozen eggs.",
        # A paragraph break ends the chain.
        "Every file, every branch,\n\nEvery deploy was checked twice.",
        # Narrative possessives are left out.
        "His coat, his hat, his gloves.",
        # Proper nouns are not a chain.
        "We visited New York, New Jersey, and New Hampshire."
      ],
      rationale: "A comma chain of items opening on the same determiner is a drumbeat, " \
                 "and a model falls into it as a default cadence. It is also a device " \
                 "careful writers use on purpose, so one is a question, not a verdict; " \
                 "when a draft carries several, read the family as a warning."
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
      severity: "info",
      # The bare adverb was the whole rule, and the engineering idioms were
      # flagged on purpose. Technical prose says that was the wrong call: a
      # patch that applies cleanly, a build that compiles cleanly and a gear
      # leg that separates cleanly are all checkable facts with a visible
      # failure state, which is the opposite of rating a fit you haven't
      # shown. The original probe -- 25 Gutenberg texts, no modern manner
      # adverb found -- could not have caught this, because Victorian novels
      # have no builds; the same corpus read as engineering ("clearly and
      # cleanly drawn in pencil", Machine Drawing and Design, 1890) has it.
      #
      # What is left is the partition frame: something divided into parts, or
      # mapped onto another scheme, and rated before the reader sees the
      # parts. The clause-final form ("the objection breaks down cleanly, and
      # neither half survives") is the same tell and is left out.
      #
      # The frame is not the sense, and this rule ships at info because of it.
      # "The argument splits cleanly into two parts" and "the gear retracted
      # cleanly into the well" are one pattern apart only in their subject,
      # and a regex cannot see the subject -- the same limit that keeps the
      # animacy verbs out of trailing-significance-participle. The preposition
      # buys the common physical cases ("separated cleanly from", "cleanly
      # compiled", "cleanly drawn") and nothing more, so a flag here is a
      # question for the agent reading it, not a verdict.
      pattern: /\bcleanly\s+(?:in(?:to|\s+(?:two|three|half))|onto)\b/i,
      message: '"Cleanly" rates the fit instead of showing it.',
      suggestion: "Cut the adverb, or say what actually lined up.",
      examples_bad: [
        "The argument splits cleanly into two parts.",
        "The new taxonomy maps cleanly onto the old one.",
        "The objection divides cleanly in half, and neither side survives."
      ],
      examples_ok: [
        "The branch merged without conflicts.",
        "She wiped the counter clean.",
        "The build finished with no warnings.",
        # The engineering idiom the rule used to flag on purpose. A patch that
        # applies cleanly either did or did not; there is nothing being rated.
        "The patch applies cleanly to main.",
        # Wording follows NTSB AAR-14/01 and NASA SEL-84-101 (US government
        # works) and An Introduction to Machine Drawing and Design (1890).
        "The main landing gear separated cleanly from the airplane.",
        "The code should be cleanly compiled beforehand.",
        "Your answers should be clearly and cleanly drawn in pencil."
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
      # The allow-list was a list of specific nouns, and technical prose showed
      # that the real division is not lexical but grammatical: "exact" in front
      # of a quantity an instrument could read is doing work ("the exact
      # diameter of the finished rim", "the exact blade pitch angle"), and so
      # is "exactly" in front of a fact someone went and determined ("could not
      # be determined exactly when", "reamed exactly to the right size"). The
      # tell is the bare intensifier on a claim with nothing behind it.
      #
      # So the allow-list now carries the measurement nouns as a class, and a
      # second branch clears "exactly" before an interrogative or a
      # to-phrase. What is left is the reflexive emphasis the rule was written
      # for: "exactly the point", "exactly right", "exactly why".
      pattern: /\bexact(?:ly)?\b
                (?!\s*(?:
                     # Tier one, unchanged: the original allow-list, matched
                     # tight so no modifier can reach past it.
                     (?:the\s+)?
                     (?:same|opposite|science|change|replica|cop(?:y|ies)|
                        location|coordinates|way)\b
                   |[$\d]|noon\b|midnight\b|o'?\s*clock\b
                     # Tier two: a quantity an instrument reads. These take a
                     # modifier window ("the exact blade pitch angle"), which
                     # tier one must not, or the window reaches the clichés
                     # ("exactly the wrong time", "exactly the right words").
                   |(?:the\s+|a\s+|an\s+)?(?:[\w-]+\s+){0,2}
                     (?:diameter|radius|circumference|size|dimensions?|
                        length|width|height|depth|thickness|gauge|
                        weight|mass|volume|density|
                        angle|pitch|bearing|heading|azimuth|
                        temperature|pressure|voltage|frequency|wavelength|
                        speed|velocity|altitude|elevation|
                        position|coordinates|distance|clearance|tolerance|
                        quantity|match(?:es)?|duplicate)\b
                     # "exactly when the fire began", "exactly how far it fell"
                   |when\b|where\b|how\s+(?:much|many|far|long|fast|deep)\b
                     # "rolled exactly to weight", "reamed exactly to size"
                   |to\s+(?:the\s+)?
                     (?:right|correct|nearest|specified|required|
                        weight|size|scale|length|gauge|tolerance)\b))/ix,
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
        "She has exacting standards for her students.",
        # A measured quantity and a determined fact, pinning the two branches
        # added above. Wording follows "Turning and Boring" (1919, public
        # domain by date) and NTSB AAR-04/01 (US government work).
        "The soft jaws are bored to the exact diameter of the finished rim.",
        "Investigators could not determine the exact blade pitch angle.",
        "The bore is finished with a reamer to exactly the right size and taper.",
        "It could not be determined exactly when the fire began."
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
      id: "intersection-of",
      category: "rhetorical-tic",
      severity: "warning",
      # "at" is not load-bearing -- "explores the intersection of art and
      # technology" is the same move -- so the anchor is "the intersection of"
      # and the two guards carry the whole burden of separating the literal
      # senses. A street corner names its streets, and a street name is
      # Capitalized-then-lowercase ("Elm", "Broadway", "Highway 12"), so the
      # positive lookahead demands the next word be lowercase or an all-caps
      # acronym -- "AI", "UX", "HCI" are the metaphor's favourite operands and
      # no street is spelled that way. Geometry and set arithmetic name their
      # operands ("the two curves", "the ranges", "both key sets"), so the
      # negative lookahead drops a literal noun found within two words of
      # "of". Two words, not three, keeps "art and city streets" from reaching
      # "streets" and silencing a real hit. No /i on the whole pattern: it
      # would make [a-z] match capitals and undo the first guard, so the
      # case-insensitive parts are inline (?i:...) groups instead.
      #
      # Three additions after the rule met accident reports and reference
      # documentation, where every hit was literal and each broke a guard.
      # Airfield surfaces (runway, taxiway, apron) are as literal as a street
      # and are written lowercase, so the first guard was actively admitting
      # them. A matrix cell is the same literal sense as a set intersection,
      # so rows and columns join the geometry list. And the all-caps
      # allowance, added for "AI"/"UX"/"HCI" on the premise that no street is
      # spelled that way, was admitting American route designators. The
      # trailing (?!-\d) on that branch drops a route number ("US-27A"), and
      # one more lookahead drops a quadrant plus a house number ("NE 140th
      # Court"). Street-type nouns are deliberately NOT added to the literal
      # list: "court", "drive" and "place" are ordinary abstract nouns, and
      # the two-word window would reach them as the second operand and
      # silence "the intersection of memory and place".
      pattern: /\b[Tt]he\s+intersection\s+of\b
                (?!\s+(?:[\w-]+\s+){0,2}
                     (?i:sets?|lines?|curves?|planes?|circles?|spheres?|axes|
                         rays?|segments?|arcs?|orbits?|streets?|avenues?|
                         roads?|highways?|routes?|tracks?|corridors?|paths?|
                         boulevards?|lanes?|arrays?|lists?|ranges?|
                         collections?|keys?|vectors?|matrices|polygons?|
                         rectangles?|intervals?|data|datasets?|
                         runways?|taxiways?|taxilanes?|aprons?|
                         rows?|columns?|cells?)\b)
                (?!\s+[A-Z]{1,3}\s+\d)
                (?=\s+(?:[a-z]|[A-Z]{2,}\b(?!-\d)))/x,
      message: '"the intersection of X and Y" outside streets or geometry is borrowed positioning.',
      suggestion: "Say what the work does, or name the two things it takes from each.",
      examples_bad: [
        "Her work sits at the intersection of art and technology.",
        "Her book explores the intersection of art and technology.",
        "We operate at the intersection of AI and healthcare.",
        "The product lives at the intersection of design and engineering.",
        "At the intersection of policy and practice, nothing moves quickly.",
        "The intersection of grief and comedy is where this essay lands.",
        "The role sits at the intersection of the marketing and product teams."
      ],
      examples_ok: [
        "The accident happened at the intersection of Elm Street and Oak Avenue.",
        "Turn left at the intersection of Main and Fifth.",
        "The bus stops at the intersection of Broadway and 42nd Street.",
        "A hydrant stands at the intersection of Elm and Willow.",
        "The house sits at the intersection of Highway 12 and County Road 8.",
        "The intersection of Elm and Willow was closed for repaving.",
        "The solution lies at the intersection of the two curves.",
        "Draw a point at the intersection of the lines.",
        "The point at the intersection of two circles is equidistant.",
        "He stood at the intersection of five streets and could not choose.",
        "The village grew up at the intersection of several old roads.",
        "Snow piled up at the intersection of the roads below.",
        "Compute the intersection of the two arrays.",
        "The query returns the intersection of both key sets.",
        "The intersection of the ranges is empty.",
        # Airfield surfaces, route designators and matrix cells, each pinning
        # one of the three guards added above. Wording follows NTSB AAR-16/02,
        # AAR-14/01 and HAR-17/02 and the NASA Software Safety Guidebook
        # (NASA-GB-8719.13) -- US government works, public domain.
        "The airplane crossed the intersection of runway 13 with runway 4.",
        "Firefighters gathered near the intersection of taxiway N and taxiway F.",
        "The crash occurred at the intersection of US-27A and NE 140th Court.",
        "Traffic was heaviest at the intersection of NE 140th Court.",
        "The square at the intersection of a row and a column contains a code."
      ],
      rationale: "A street corner and a set diagram are the phrase's literal homes. Everywhere " \
                 "else it claims a position without doing the work of one: the writer sits " \
                 "between two fields and says nothing about either. Models open bios and " \
                 "pitches with it because it sounds like a thesis while committing to nothing."
    ),
    Rule.new(
      id: "impact-verb",
      category: "rhetorical-tic",
      severity: "warning",
      # "impact" and "impacts" are also nouns, so they only count as verbs
      # behind an auxiliary or a subject pronoun. One optional pronoun may sit
      # between the auxiliary and the verb ("does this impact the date");
      # allowing a determiner in that slot instead would swallow "will the
      # impact be permanent", so the copula lookahead below backs it up.
      # "impacted"/"impacting" are verbal on their own except for the medical
      # and soil sense: the forward lookahead catches the attributive form
      # ("an impacted wisdom tooth"), but the predicate form ("the tooth was
      # impacted") needs the noun and copula pulled into the match, because
      # skip: only ever sees matched text, never surrounding context. Same
      # reason load-bearing does it, and a lookbehind that wide trips the
      # Onigmo bug documented there. The trailing (?!-) is load-bearing too:
      # every other guard is spelled with \s+, so "will impact-test the
      # housing" walks straight past them.
      #
      # Accident reports found two holes. "to impact" was in the auxiliary
      # list as an infinitive marker, so it also matched the preposition in
      # "4 seconds prior to impact" and "time to impact"; that branch now
      # stands on its own and requires a following object. And "impacted" in
      # those reports is usually one object hitting another -- an airplane
      # impacts terrain, debris impacts a wing -- which is the collision noun
      # the rule already excludes, just on the other side of the verb, so the
      # struck-object list mirrors it.
      pattern: /\b(?:
                  (?:will|would|can|could|may|might|shall|should|must|does|
                     do|did|doesn't|don't|didn't|won't|helps?|helped)\s+
                  (?:(?:it|this|that|they|we|you)\s+)?
                  impacts?
                | to\s+impacts?
                  (?=\s+(?!and\b|or\b|but\b|in\b|on\b|at\b|of\b|for\b|from\b|
                            with\b|during\b|after\b|before\b|than\b)\w)
                | (?:it|this|that|which|he|she)\s+impacts
                | (?:they|we|you)\s+impact
                | (?:(?:tooth|teeth|molars?|bowels?|colon|fractures?|soils?)\s+
                     (?:is|are|was|were)\s+)?
                  impact(?:ed|ing)
                )\b
                (?!-)
                (?!\s+(?:be|been|is|are|was|were|of|on|has|have|had)\b)
                (?!\s+(?:tooth|teeth|molars?|wisdom|canines?|bowels?|colon|
                         stool|feces|fecal|fractures?|soils?|snow|ice|sediment|
                         gravel|earwax|cerumen)\b)
                (?!\s+(?:the\s+|a\s+|an\s+)?(?:[\w-]+\s+)?
                        (?:terrain|ground|seabed|seawall|treetops|trees?|
                           grove|thicket|hillside|embankment|berm|
                           escarpment|ridgeline|cliff|
                           runway|taxiway|apron|tarmac|guardrail|
                           fuselage|nacelle|airframe|empennage|rotor|
                           windshield|bulkhead|revetment|abutment|
                           wing|wingtip|stabilizer|landing\s+gear)\b)
                (?!\s+(?:statements?|assessments?|reports?|studies|study|
                         analys[ie]s|evaluations?|factors?|ratings?|scores?|
                         investing|investors?|funds?|bonds?|craters?|
                         wrench(?:es)?|drivers?|sockets?|printers?|sprinklers?|
                         resistan(?:t|ce)|tested|testing|velocit(?:y|ies)|
                         forces?|energy|load(?:s|ing)?|zones?|points?|players?|
                         sites?|angles?|damage|absorbers?)\b)/ix,
      skip: [/\A(?:tooth|teeth|molars?|bowels?|colon|fractures?|soils?)\s+
                (?:is|are|was|were)\s+impacted/ix],
      message: '"impact" as a verb hides which way something moved and by how much.',
      suggestion: 'Name the verb: cut, delayed, doubled, broke, raised. Or use "affected".',
      examples_bad: [
        "The outage impacted about four thousand accounts.",
        "Changing the default will impact every downstream job.",
        "How does this impact the release date?",
        "Rising rates impacted our hiring plan.",
        "The migration impacted performance across the board.",
        "This impacts every downstream job.",
        "The new policy is impacting our margins."
      ],
      examples_ok: [
        "The impact crushed the front bumper.",
        "The crater marks the point of impact.",
        "Torque the bolts with an impact wrench.",
        "The meteor impact left a ring of debris.",
        "The parachute reduces impact force on landing.",
        "The county filed an environmental impact statement.",
        "The fund runs an impact investing strategy.",
        "The journal reports a five-year impact factor.",
        "He bought an impact driver for the deck job.",
        "She is an impact player off the bench.",
        "She had an impacted wisdom tooth removed.",
        "The tooth was impacted and had to come out.",
        "The soil was impacted by years of heavy machinery.",
        "An impacted fracture heals without displacement.",
        "Will the impact be permanent?",
        "Consultants will impact-test the housing next week.",
        # One object striking another, and the preposition that was reading as
        # an infinitive. Wording follows NTSB AAR-06/03 and AAR-14/01 and the
        # Columbia Accident Investigation Board report -- US government works.
        "The airplane impacted terrain about 300 feet north of the threshold.",
        "The foam debris impacted the left wing shortly after separation.",
        "The stick shaker activated 4 seconds prior to impact.",
        "The chart plots time to impact in seconds."
      ],
      rationale: "As a verb, 'impact' reports that something changed while withholding the " \
                 "direction and the size. The specific verb -- slowed, doubled, broke -- " \
                 "carries what the sentence is missing, and 'affected' covers the rest. " \
                 "Models reach for it because it sounds consequential at no cost."
    ),
    Rule.new(
      id: "impact-noun-vague",
      category: "puffery",
      severity: "warning",
      # Only the puffed shapes: an intensity adjective, or make/have plus an
      # article. "the impact of X" is left to impact-noun-bare, which sits at
      # info because it is the standard word in research prose. "positive" and
      # "negative" stay out of the adjective list on purpose -- they name a
      # direction, which is more than the intensity words do. "statistically"
      # is pulled into the match as an optional leading word so skip: can see
      # it; a statistically significant impact is a finding, not puffery, and
      # skip: never sees text outside the matched span.
      pattern: /\b(?:statistically\s+)?
                (?:
                  (?:significant|real|meaningful|lasting|massive|huge|profound|
                     big|major|tremendous|enormous|outsized|considerable|
                     substantial|genuine|tangible|immense|incredible|
                     remarkable)\s+
                | (?:mak(?:e|es|ing)|made|hav(?:e|es|ing)|has|had)\s+
                  (?:a|an|real|some)\s+
                )
                impacts?\b(?!-)
                (?!\s+(?:statements?|assessments?|reports?|studies|study|
                         analys[ie]s|evaluations?|factors?|ratings?|scores?|
                         investing|investors?|funds?|bonds?|craters?|
                         wrench(?:es)?|drivers?|sockets?|printers?|sprinklers?|
                         resistan(?:t|ce)|tested|testing|velocit(?:y|ies)|
                         forces?|energy|load(?:s|ing)?|zones?|points?|players?|
                         sites?|angles?|damage|absorbers?)\b)/ix,
      skip: [/\Astatistically\s/i],
      message: '"significant/real/big impact" and "make an impact" inflate a claim without stating it.',
      suggestion: "Say what changed and by how much, or cut the sentence.",
      examples_bad: [
        "The change had a significant impact on conversion.",
        "This will have real impact for the team.",
        "The rewrite made a big impact on load times.",
        "The launch had a profound impact on morale.",
        "We want to make an impact this quarter."
      ],
      examples_ok: [
        "The study found a statistically significant impact on mortality.",
        "The impact crushed the front bumper.",
        "The helmet failed at high-impact loading.",
        "Impact-resistant polycarbonate replaced the glass.",
        "The blast impact zone extended two hundred metres.",
        "That impact rating exceeds the standard.",
        "Is this impact reversible?"
      ],
      rationale: "The adjective does the work the sentence should have done: 'significant' and " \
                 "'real' assert that a change mattered without naming it or sizing it. " \
                 "'Make an impact' is the same move with the noun left bare."
    ),
    Rule.new(
      id: "impact-noun-bare",
      category: "rhetorical-tic",
      severity: "info",
      # Two shapes, each needing its own anchor: a measuring verb in front, or
      # "of" behind. That is what keeps the collision sense clear without a
      # list of collision verbs -- "the impact crushed the front bumper" has
      # neither anchor, and "the point of impact" runs the other way round.
      # The verb stems end in \w*, not \w+: with \w+ the rule misses the bare
      # imperative "Consider the impact before you merge".
      pattern: /\b(?:
                  (?:measur|assess|consider|understand|understood|evaluat|
                     gaug|weigh|quantif|track|examin|explor|maximi[sz])\w*\s+
                  (?:the|its|their|our|this|that)\s+impacts?
                | the\s+impacts?\s+of
                )\b(?!-)
                (?!\s+(?:statements?|assessments?|reports?|studies|study|
                         analys[ie]s|evaluations?|factors?|ratings?|scores?|
                         investing|investors?|funds?|bonds?|craters?|
                         wrench(?:es)?|drivers?|sockets?|printers?|sprinklers?|
                         resistan(?:t|ce)|tested|testing|velocit(?:y|ies)|
                         forces?|energy|load(?:s|ing)?|zones?|points?|players?|
                         sites?|angles?|damage|absorbers?)\b)/ix,
      message: '"the impact of X" defers naming what actually changed.',
      suggestion: "Name the change itself, or the number that shows it.",
      examples_bad: [
        "We measured the impact of the new onboarding flow.",
        "Consider the impact before you merge.",
        "The team is still assessing the impact.",
        "The impact of the change is hard to quantify."
      ],
      examples_ok: [
        "The impact crushed the front bumper.",
        "The crater marks the point of impact.",
        "The meteor impact left a ring of debris.",
        "Crews measured the impact crater at dawn.",
        "The panel reviewed the impact assessment before the vote.",
        "Torque the bolts with an impact wrench.",
        "Will the impact be permanent?"
      ],
      rationale: "This one sits at info because 'the impact of X on Y' is the ordinary word in " \
                 "research and policy writing, not a tell. Elsewhere it postpones the sentence: " \
                 "the writer announces that an effect exists and stops before naming it."
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
    Rule.new(
      id: "failure-mode-here",
      category: "rhetorical-tic",
      severity: "warning",
      # "here" is the whole narrowing, and it is doing a lot -- the bare "the
      # failure mode is" is ordinary engineering writing about real systems,
      # where the phrase means what it says. The deictic is what marks the
      # borrowed sense: an argument, a draft or a person named as a mechanism
      # with a characteristic way of breaking.
      pattern: /\bthe\s+failure\s+mode\s+here\s+is\b/i,
      message: '"The failure mode here is…" borrows an engineering term for an argument.',
      suggestion: "Say what goes wrong and when, without the mechanism framing.",
      examples_bad: [
        "The failure mode here is that nobody reads past the first paragraph.",
        "It reads well enough. The failure mode here is trusting the summary.",
        "The failure mode here is social, not technical."
      ],
      examples_ok: [
        "The failure mode is a stuck relay.",
        "We documented every failure mode in the valve assembly.",
        "The common failure mode here was corrosion."
      ],
      rationale: "The phrase treats a piece of writing or a person as a mechanism with a " \
                 "characteristic breakage, which sounds diagnostic and commits to nothing: " \
                 "no conditions, no frequency, nothing to check. In its home discipline the " \
                 "term earns its precision from a part that actually fails."
    ),
    Rule.new(
      id: "thats-the-tension",
      category: "rhetorical-tic",
      severity: "warning",
      # Sentence-initial, only two nouns, and the noun must end the clause.
      #
      # "tradeoff" and "catch" were tried and cut: both are ordinary English
      # in this exact frame, and the anchor removes only 60% of their volume,
      # which is not enough. The surviving pair names a state of the argument
      # rather than a thing in the world, which is what makes it the tic.
      #
      # The clause-final guard is what separates the closer from an ordinary
      # sentence that happens to start the same way -- "This is the bet we
      # placed in March" keeps going, and so is not the move.
      pattern: /(?:\A|[.!?]\s+|\n\s*\n)\s*(?:and\s+|so\s+|but\s+)?
                 (?:that|this)(?:'s|’s|\s+is)\s+the\s+(?:tension|bet)
                 \s*(?:[.!?:;—]|\z)/ix,
      message: '"That\'s the tension/bet." names the shape instead of the thing.',
      suggestion: "State the two things pulling against each other.",
      examples_bad: [
        "That's the tension.",
        "Both readings are defensible. That's the tension.",
        "So that's the bet: cheaper now, slower later."
      ],
      examples_ok: [
        "That's the trade-off.",
        "The rope went slack and that's the tension gone.",
        "This is the bet we placed in March."
      ],
      rationale: "The sentence labels the argument's shape and stops, which reads as a " \
                 "conclusion while resolving nothing -- the reader is told a tension exists " \
                 "but not what pulls against what. It is the closer half of the same move as " \
                 "'that's the whole point', with the noun swapped for a state of play."
    ),
    Rule.new(
      id: "right-up-until",
      category: "rhetorical-tic",
      severity: "warning",
      # The intensifier is the tell, not the reversal. "It works until it
      # doesn't" is an old human idiom and stays clean; stacking "right up"
      # in front of it is the model's version, and the two together are two
      # orders of magnitude rarer than either half.
      pattern: /\bright\s+up\s+until\s+it\s+(?:doesn'?t|isn'?t|stops|breaks)\b/i,
      message: '"Right up until it doesn\'t" is a stock reversal closer.',
      suggestion: "Name the point where it stops working.",
      examples_bad: [
        "The approach works, right up until it doesn't.",
        "The cache stays warm right up until it isn't.",
        "It scales fine right up until it breaks."
      ],
      examples_ok: [
        "It works until it doesn't.",
        "She stayed right up until the end.",
        "The pattern held right up until Tuesday."
      ],
      rationale: "The closer promises a reversal and withholds it: the reader is told the " \
                 "thing fails without being told when, why, or how far in. The bare idiom " \
                 "does the same, which is why only the intensified stack is flagged -- a " \
                 "writer who reaches for the longer form is reaching for the cadence."
    ),
    Rule.new(
      id: "two-things-true",
      category: "rhetorical-tic",
      severity: "warning",
      # Closed phrase, no anchor needed. The optional "both" and the optional
      # "at once" tail are the two ways the sentence is padded; the count word
      # is fixed at two, because "three things can be true" is someone
      # actually counting.
      pattern: /\b(?:two|both)\s+things\s+(?:can\s+(?:both\s+)?be|are)\s+true\b/i,
      message: '"Two things can be true" concedes the shape without conceding anything.',
      suggestion: "Say which two, and which one you think weighs more.",
      examples_bad: [
        "Two things can be true at once.",
        "Both things can be true here.",
        "Two things are true, and the second is the awkward one."
      ],
      examples_ok: [
        "Three things can be true at the same time.",
        "Two things went wrong that morning.",
        "Both statements are true and the report says so."
      ],
      rationale: "The sentence performs even-handedness and supplies none: it asserts that a " \
                 "contradiction is only apparent without naming either half or saying which " \
                 "one carries more weight. A writer who has held both claims at once can say " \
                 "what they are."
    ),
    Rule.new(
      id: "notice-what-there",
      category: "rhetorical-tic",
      severity: "warning",
      # The self-referential half of the attention cue: the sentence points
      # at the writing rather than at anything in the world. Two frames, both
      # sentence-initial -- "notice what X did there" and the bare "read that
      # again". The bare imperative without the "there" frame is the quieter
      # half and lives in notice-what, at info.
      pattern: /(?:\A|[.!?]\s+|\n\s*\n)\s*
                (?:notice\s+what\b[^.!?\n]{0,40}\b(?:did|does|just\s+did)\s+there\b
                  |read\s+that\s+again\b)/ix,
      message: '"Notice what it did there" points at the writing, not the world.',
      suggestion: "Make the point; the reader saw the same sentence you did.",
      examples_bad: [
        "Notice what that argument did there.",
        "The claim moved while nobody was looking. Notice what the second clause does there.",
        "Read that again."
      ],
      examples_ok: [
        "Notice what happens when the cache is cold.",
        "I did not notice what he did there.",
        "You should read that again before signing."
      ],
      rationale: "The cue asks the reader to admire a move the sentence has just made, which " \
                 "puts the writing in the frame instead of the subject, and it grades the " \
                 "move before the reader has judged it. Where a human writes it, they are " \
                 "usually pointing at something outside the text -- a chart, a screen, a list."
    ),
    Rule.new(
      id: "notice-what",
      category: "rhetorical-tic",
      severity: "info",
      # The ambiguous half of the pair, and it ships at info because the
      # sentence-initial imperative is also how people point at something
      # real: "Notice what happens around Q3", "Notice what is not on the
      # list". The lookahead hands the self-referential frame to
      # notice-what-there so one span never draws two notes.
      #
      # "how" is left out. "Notice how" draws ten times the volume and half
      # of it is the imperative -- that is ordinary argument, not a tell.
      pattern: /(?:\A|[.!?]\s+|\n\s*\n)\s*notice\s+what\b
                (?![^.!?\n]{0,40}\b(?:did|does|just\s+did)\s+there\b)/ix,
      message: '"Notice what…" tells the reader to look instead of showing them.',
      suggestion: "Point at the thing itself, or cut the instruction.",
      examples_bad: [
        "Notice what the second paragraph leaves out.",
        "The numbers were flat all year. Notice what the summary claims instead.",
        "Notice what nobody is willing to say."
      ],
      examples_ok: [
        "Notice how the cache warms on the second request.",
        "I did not notice what he said.",
        "You will notice what is missing soon enough."
      ],
      rationale: "The imperative directs attention without carrying any, so the reader is " \
                 "told to look before being given anything to look at. Human writers use the " \
                 "same sentence to point at something outside the text -- a chart, a screen, " \
                 "a list -- which is why this is the quiet half of the pair. Treat a flag " \
                 "here as a question: is there anything to see?"
    ),
    Rule.new(
      id: "none-of-this-is-to-say",
      category: "rhetorical-tic",
      severity: "warning",
      # Only the "none of" form. Every neighbouring phrasing is ordinary
      # English by an order of magnitude -- "which is not to say", "this is
      # not to say", "that's not to say" -- and admitting any of them would
      # sink the rule. The sweeping subject is the tell: not this sentence
      # but everything above it.
      pattern: /\bnone\s+of\s+(?:this|that|the\s+above)\s+is\s+to\s+say\b/i,
      message: '"None of this is to say…" retracts an argument nobody made.',
      suggestion: "State the limit of the claim, or drop the disclaimer.",
      examples_bad: [
        "None of this is to say the approach is wrong.",
        "None of that is to say the numbers are wrong.",
        "The evidence points one way. None of the above is to say it is settled."
      ],
      examples_ok: [
        "That's not to say it was easy.",
        "Which is not to say the report was wrong.",
        "None of this means the project failed."
      ],
      rationale: "The sentence guards against a reading the text never invited, which lets " \
                 "the writer sound careful without giving anything up. The sweeping subject " \
                 "is what separates it from the ordinary hedge: it disclaims everything " \
                 "above it at once, so it can be written without knowing what that was."
    ),
    Rule.new(
      id: "if-im-being-honest",
      category: "rhetorical-tic",
      severity: "info",
      # The "being honest" frame only. Plain "to be honest" and "I'll be
      # honest" are how people talk and are excluded. info, not warning:
      # writers really do say this out loud.
      pattern: /\bif\s+(?:I['’]?m|I\s+am|we['’]?re|we\s+are)\s+(?:being\s+)?honest\b
                |\bhonestly,\s+the\s+(?:answer|truth)\b/ix,
      message: '"If I\'m being honest…" buys candor without spending anything.',
      suggestion: "Delete the preamble and say the honest thing.",
      examples_bad: [
        "If I'm being honest, the design never worked.",
        "If we're being honest, nobody read the report.",
        "Honestly, the answer is that we guessed."
      ],
      examples_ok: [
        "To be honest, I liked the first draft better.",
        "I'll be honest, the meeting ran long.",
        "Honestly, I forgot the deadline."
      ],
      rationale: "The preamble implies the surrounding text was less than honest, and it " \
                 "promises a confession that the sentence after it rarely delivers. It " \
                 "costs the writer nothing and reads as intimacy the reader did not earn."
    ),
    Rule.new(
      id: "honestly",
      category: "rhetorical-tic",
      severity: "warning",
      # The manner adverb, the way "cleanly" is the manner adverb: hung on a
      # subject that cannot be honest. Two guards, no verb list.
      #
      # Terminal position does most of the work. The adverb must close on a
      # full stop, comma, semicolon or exclamation mark, which is what keeps
      # the ordinary intensifier out -- "I honestly think", "I honestly don't
      # know" have the word mid-clause and never match. Sentence-initial
      # "Honestly," needs no guard of its own: a full stop cannot match \w+,
      # so the sentence before it can never donate its last word.
      #
      # The guard list covers the slot immediately before the adverb, which is
      # where the discourse marker lives. "And honestly," and "Quite honestly,"
      # are how people write, and both die there.
      #
      # There is no animacy test, because no regex sees animacy. "She answered
      # honestly." matches, and so does the sentence-final hedge people write
      # in casual comments ("it's beyond boring honestly"). Both are the known
      # cost of anchoring on position alone; see rationale for the rate.
      pattern: /\b(?!(?:and|but|or|nor|yet|so|then|though|although|because|if
                     |quite|more|most|very|really|pretty|fairly|too|also|just
                     |only|now|again|well|i|we|you|he|she|they|it)\b)
                \w+\b[ \t]+honestly[ \t]*(?=[.,;!])/ix,
      message: '"Honestly" in the manner slot claims good faith the reader cannot check.',
      suggestion: "Cut the adverb, or show the thing that makes it honest.",
      examples_bad: [
        "These two rows compare honestly.",
        "The numbers add up honestly.",
        "The taxonomy maps honestly, which is what the table is for.",
        "The benchmark reports honestly, which is the whole point.",
        "It reads honestly; that is what carries the piece."
      ],
      examples_ok: [
        # Mid-clause: the ordinary intensifier, and the terminal guard drops it.
        "I honestly do not know.",
        "She honestly believes it will work.",
        # The discourse marker, which the guard list drops.
        "And honestly, I forgot the deadline.",
        "Quite honestly, the meeting ran long.",
        "But honestly, nobody minded."
      ],
      rationale: "The adverb rates the good faith of the writing instead of showing anything " \
                 "the reader can check, and a table or a benchmark has no good faith to rate. " \
                 "Position is the only anchor, so ordinary English gets caught too: a dialogue " \
                 "tag (\"said Isabel honestly\") and the sentence-final hedge of casual speech " \
                 "(\"it's beyond boring honestly\"). Both are rare -- twice in 3.65M words of " \
                 "public-domain prose, ten times in 6.07M words of pre-2022 Hacker News."
    ),
    Rule.new(
      id: "honest-x",
      category: "rhetorical-tic",
      severity: "warning",
      # The noun list is short on purpose, and the words left out are the
      # point. "An honest answer", "an honest assessment" and "an honest
      # account" are ordinary English about people -- six hits between them in
      # 6.07M words of Hacker News, every one of them a person being truthful
      # rather than a writer praising their own framing -- so they are out.
      # "man", "mistake", "living", "work" and "opinion" never went in.
      #
      # What ships is the set that only ever appears in front of the writer's
      # own construction, and none of it appears in 9.7M words of either
      # corpus. "most" and "more" are excluded from the modifier slot so the
      # superlative belongs to most-honest-x alone.
      pattern: /\b(?:an|the|one|this|that)[ \t]+(?:(?!most\b|more\b)\w+[ \t]+)?
                honest[ \t]+(?:\w+[ \t]+)?
                (?:comparison|framing|formulation|accounting|abstraction|mapping
                  |through-line)\b/ix,
      message: '"An honest comparison / the honest framing" praises the writing, not the thing.',
      suggestion: "Cut the adjective and make the comparison; the reader decides if it is honest.",
      examples_bad: [
        "That gives us an honest comparison of the two.",
        "The honest framing is that nobody knew.",
        "This is an honest accounting of what the delay cost.",
        "What we want is an honest mapping from one schema to the other."
      ],
      examples_ok: [
        # The idioms, which is where "honest" lives in ordinary prose.
        "He was an honest man.",
        "It was an honest mistake.",
        "She made an honest living.",
        "That is an honest day's work.",
        # A person being truthful, which is not a claim about the writing.
        "How could you expect an honest answer to a question like that?",
        # The superlative belongs to most-honest-x.
        "The most honest framing is that we guessed."
      ],
      rationale: "\"Honest\" in front of a framing or a comparison is the writer approving " \
                 "their own work, the same move \"clean\" makes one shelf over. The reader " \
                 "cannot check it and it costs nothing to assert. The narrow noun list is what " \
                 "separates it from the ordinary sense: the shipped pattern flags nothing in " \
                 "3.65M words of public-domain prose or 6.07M words of pre-2022 Hacker News."
    ),
    Rule.new(
      id: "most-honest-x",
      category: "rhetorical-tic",
      severity: "warning",
      # The superlative frame carries the tell on its own, so this noun list is
      # wider than honest-x's -- "the most honest assessment" is self-ranking
      # in a way "an honest assessment" is not. The list still has to keep out
      # the ordinary superlative about a person, which is what "the most honest
      # politician" is, so no human nouns go in. Nothing in either corpus
      # matches. "way to" gets its own branch, mirroring cleanest-x.
      pattern: /\bmost[ \t]+honest[ \t]+(?:(?!way\b)\w+[ \t]+){0,2}
                (?:comparison|framing|formulation|accounting|assessment|appraisal
                  |reading|account|answer|version|summary|take|signal|abstraction
                  |mapping|through-line)\b
               |\bmost[ \t]+honest[ \t]+way[ \t]+to[ \t]+
                (?:say|put|frame|state|describe|phrase|think[ \t]+about)\b/ix,
      message: '"The most honest framing…" ranks your own claim for the reader.',
      suggestion: "Drop the ranking and make the claim; the reader grades it.",
      examples_bad: [
        "The most honest framing is that we guessed.",
        "That is the most honest way to put it.",
        "The most honest reading of the data is duller than the headline.",
        "This is the most honest summary anyone offered."
      ],
      examples_ok: [
        # The ordinary superlative, about a person.
        "He is the most honest person I know.",
        "She is the most honest politician in the state.",
        # "way to" outside the speech verbs.
        "This is the most honest way to earn a living."
      ],
      rationale: "Self-ranking: the writer tells the reader which of their own claims is the " \
                 "candid one, which is the reader's job. The superlative also implies the rest " \
                 "of the piece was less honest, and the sentence after it never says which part."
    ),
    Rule.new(
      id: "genuinely",
      category: "rhetorical-tic",
      severity: "info",
      # Off by default. There is no narrowing here: the word is ordinary
      # English at every frequency we measured, and the difference between
      # the tell and the real use is whether a contrast exists in the
      # surrounding argument, which no regex can see. Selectable when a
      # writer wants every occurrence listed back to them.
      default_on: false,
      pattern: /\bgenuinely\b/i,
      message: '"Genuinely" asserts sincerity instead of earning it (heuristic; high false-positive).',
      suggestion: "Cut the adverb. If the sentence needs it, the claim is doing the work.",
      examples_bad: [
        "This is a genuinely hard problem.",
        "The result was genuinely surprising.",
        "It's genuinely useful, and that's rare."
      ],
      examples_ok: [
        "The signature was authentic.",
        "She was pleased with the outcome.",
        "The offer turned out to be real."
      ],
      rationale: "As an intensifier the word rates the writer's sincerity rather than the " \
                 "thing described, and it can be dropped from most sentences without loss. " \
                 "It still does real work when it draws a contrast -- genuinely free against " \
                 "nominally free -- and nothing in the sentence marks which use is which, " \
                 "which is why this one runs only when you ask for it."
    ),
    Rule.new(
      id: "and-thats-fine",
      category: "rhetorical-tic",
      severity: "info",
      # Three narrowings, and the rule needs all of them. "and" is required:
      # bare "that's fine" is a reply people write constantly. The match must
      # open a sentence and close it, so the concessive clause -- "and that's
      # fine, but the cost is real" -- never matches.
      pattern: /(?:\A|[.!?]\s+|\n\s*\n)\s*and\s+that['’]?s\s+(?:fine|okay|ok)\s*[.!]/i,
      message: '"And that\'s fine." grants permission nobody asked for.',
      suggestion: "Cut the closer, or say who objected and why they're wrong.",
      examples_bad: [
        "The essay is short. And that's fine.",
        "Nobody reads the appendix. And that's okay.",
        "It only handles one case. And that's fine!"
      ],
      examples_ok: [
        "That's fine. Ship it whenever.",
        "The tests are slow and that's fine for now.",
        "And that's fine, but the cost is real."
      ],
      rationale: "The closer concedes an objection instead of answering it, and the objection " \
                 "was never raised. It reads as reassurance addressed to nobody, and the " \
                 "paragraph is the same without it."
    ),
    Rule.new(
      id: "and-nothing-else",
      category: "rhetorical-tic",
      severity: "warning",
      # This rule is deliberately wide, and the cost is known. There is no verb
      # list and no imperative requirement, so the only narrowing is structural
      # -- which means the pattern cannot tell a leaked instruction from the
      # ordinary English construction it borrows. "Darkness there, and nothing
      # more!" matches, and so does any sentence built the same way. That is a
      # recall-over-precision choice, not an oversight; see rationale.
      #
      # Three structural guards, each pinned by an examples_ok fixture. The
      # tail must CLOSE the sentence, so "nothing more than a rumour" and
      # "nothing else could explain it" never match. A comma must introduce
      # it, which keeps "there was nothing more to say" out. And the bare
      # "no more" branch additionally requires "and": a large share of the
      # ordinary-prose hits are the amount sense ("two years, no more",
      # "no less, no more"), and requiring the conjunction drops them without
      # losing the closer the rule is after.
      #
      # A closing quote or bracket may sit between the tail and the period so
      # a quoted sentence still matches. "?" is not accepted as the terminal
      # mark -- "and nothing more?" asks a question, a different act. Token
      # gaps cross a hard-wrapped line but never a paragraph break.
      pattern: /,(?:[ \t]|\r?\n(?![ \t]*\r?\n))+
                (?:(?:and(?:[ \t]|\r?\n(?![ \t]*\r?\n))+)?
                   nothing(?:[ \t]|\r?\n(?![ \t]*\r?\n))+(?:else|more|further)
                  |and(?:[ \t]|\r?\n(?![ \t]*\r?\n))+no(?:[ \t]|\r?\n(?![ \t]*\r?\n))+more)
                [ \t]*(?=["'”’)\]]*[.!])/ix,
      message: "Trailing \"and nothing else\" restates what the sentence already said.",
      suggestion: "Cut the tail. If the exclusion is the point, say what was excluded.",
      examples_bad: [
        "Return the JSON, and nothing else.",
        "The endpoint gives back the id, and nothing more.",
        "Reply with the number, nothing else.",
        "Print the filename, nothing further.",
        "Hand over the receipt, and no more."
      ],
      examples_ok: [
        # The tail does not close the sentence.
        "It was nothing more than a rumour.",
        "The delay was down to the weather, and nothing else could explain it.",
        # No comma introduces it.
        "There was nothing more to say after that.",
        "Nothing else matters once the deadline passes.",
        # The amount sense, which is why bare "no more" needs the conjunction.
        "The lease runs two years, no more.",
        "He asked for a fair share, no more.",
        # A question is a different act.
        "Is there anything else, or nothing more?"
      ],
      rationale: "A model told to return one thing and nothing else carries the phrasing into " \
                 "the prose it writes afterwards, where the exclusion adds nothing -- the " \
                 "sentence already named what it covers. The catch is that English has always " \
                 "used this tail, so the rule fires on careful writing too: twice in 1.92M " \
                 "words of public-domain prose, once in 461k words of pre-2022 Hacker News, and " \
                 "on every refrain in \"The Raven\". Expect to dismiss it on fiction and on " \
                 "quoted verse."
    ),
    Rule.new(
      id: "nothing-else-frag",
      category: "rhetorical-tic",
      severity: "warning",
      # The same exclusion as its own sentence: "Return the JSON. Nothing
      # else." Built on the no-x-no-y-frag template -- the fragment must start
      # at a sentence boundary and the separator is at most two spaces or one
      # hard-wrapped newline, so a blanked code span under --markdown cannot
      # weld two distant sentences together, and a paragraph break stops it.
      #
      # Two guards past that. The fragment must open with a capital letter,
      # and the preceding mark cannot be a semicolon: both keep out the
      # continuation sense
      # ("keep pulling; nothing more"), which is one clause, not a closer.
      # And the fragment must be the whole sentence -- "Nothing else mattered."
      # has a verb and never matches. "No more." is left out entirely; as a
      # standalone sentence it is ordinary speech, and no-x-no-y-frag already
      # takes the chained form.
      pattern: /(?<=[.!?])(?:[ \t]{1,2}|\r?\n(?!\s*\n)[ \t]*)\K
                (?:And[ \t]+nothing|Nothing)[ \t]+(?:else|more|further)[ \t]*[.!]/x,
      message: "\"Nothing else.\" as a closer restates what the sentence already said.",
      suggestion: "Cut the fragment, or fold the exclusion into the sentence before it.",
      examples_bad: [
        "Return the JSON. Nothing else.",
        "Give me the number. Nothing more.",
        "Answer with the file name. And nothing else.",
        "Print the total. Nothing further."
      ],
      examples_ok: [
        # A verb follows, so the fragment is a sentence about something.
        "The tests passed. Nothing else mattered that afternoon.",
        # The continuation sense: one clause, joined by a semicolon.
        "Keep pulling; nothing more.",
        # A paragraph break is not a sentence separator.
        "The kiln runs hot.\n\nNothing more.",
        # Moby-Dick (public domain): the lower-case continuation the capital
        # letter guard is there to exclude.
        "and so on; nothing more."
      ],
      rationale: "The fragment form of the same leaked instruction, and it reads the same way: " \
                 "a second sentence that only says the first one was complete. It ships at " \
                 "warning rather than info because the capital letter and the whole-sentence " \
                 "requirement keep it off the continuation sense, which is where ordinary prose " \
                 "puts the phrase: one hit in 1.92M words of public-domain prose and one in " \
                 "461k words of pre-2022 Hacker News."
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
      id: "isnt-x-its-y",
      category: "structure",
      severity: "info",
      # The corrective with the conjunction dropped: one clause rejects a
      # description, the next supplies the replacement through a second copula
      # ("It isn't the tool. It's the habit."). Every copula tense is covered,
      # and the two clauses may be joined by a period, semicolon, comma, or dash.
      #
      # The narrowing sits in the two complement slots, and it is lexical class
      # rather than vocabulary: neither slot may open with a pronoun, a
      # possessive, a preposition ("about" excepted, since "not about X, it's
      # about Y" is the same move), a degree word, or one of the predicate
      # adjectives that make the second clause a comment instead of a
      # replacement ("It isn't ready. It's close."). The article is matched
      # atomically so the guard cannot be skipped by backtracking past it. Those
      # guards cut a loose version from 19 hits to 4 over 889k words of
      # 19th-century fiction.
      #
      # What survives is the reason for info. An adjective outside the list
      # still slips through, and some hits are the same shape written by a
      # person -- "was not the wife; it was the children" is Conan Doyle. A flag
      # here says the sentence has the frame, not that a model wrote it.
      pattern: /(?:\b(?:is|are|was|were)\s+not
                  |\b(?:is|are|was|were)n['’]t
                  |\b(?:it|that|this|there)['’]s\s+not
                  |\b(?:they|these|those|we|you)['’]re\s+not)
                 (?:[ \t]|\r?\n(?!\s*\n))+
                 (?>(?:a\s+|an\s+|the\s+)?)
                 (?!so\b|just\b|only\b|merely\b|simply\b|solely\b|even\b|yet\b|quite\b|very\b
                   |too\b|all\b|always\b|never\b|often\b|also\b|enough\b|really\b|actually\b
                   |entirely\b|ready\b|close\b|done\b|easy\b|hard\b|clear\b|simple\b
                   |possible\b|likely\b|true\b|false\b|fine\b|good\b|bad\b|better\b|worse\b
                   |obvious\b|important\b|different\b|not\b|no\b|nothing\b|there\b|here\b
                   |what\b|who\b|how\b|why\b|when\b|where\b|because\b|i\b|me\b|he\b|him\b
                   |she\b|her\b|it\b|we\b|us\b|you\b|they\b|them\b|that\b|this\b|these\b
                   |those\b|his\b|their\b|its\b|my\b|your\b|our\b|in\b|on\b|at\b|of\b|to\b
                   |for\b|from\b|with\b|as\b|by\b|toward\b|towards\b|into\b|over\b|under\b
                   |through\b|against\b|upon\b|within\b|without\b)
                 [\w'’-]+
                 [^.!?;\n]{0,40}?
                 (?:[.!?;]|[ \t]*[—–]|,)
                 (?:[ \t]|\r?\n(?!\s*\n))+
                 (?:it|this|that|these|those|they)
                 (?:['’]s|['’]re|\s+is|\s+are|\s+was|\s+were)
                 (?:[ \t]|\r?\n(?!\s*\n))+
                 (?>(?:a\s+|an\s+|the\s+)?)
                 (?!so\b|just\b|only\b|merely\b|simply\b|solely\b|even\b|yet\b|quite\b|very\b
                   |too\b|all\b|always\b|never\b|often\b|also\b|enough\b|really\b|actually\b
                   |entirely\b|ready\b|close\b|done\b|easy\b|hard\b|clear\b|simple\b
                   |possible\b|likely\b|true\b|false\b|fine\b|good\b|bad\b|better\b|worse\b
                   |obvious\b|important\b|different\b|not\b|no\b|nothing\b|there\b|here\b
                   |what\b|who\b|how\b|why\b|when\b|where\b|because\b|i\b|me\b|he\b|him\b
                   |she\b|her\b|it\b|we\b|us\b|you\b|they\b|them\b|that\b|this\b|these\b
                   |those\b|his\b|their\b|its\b|my\b|your\b|our\b|in\b|on\b|at\b|of\b|to\b
                   |for\b|from\b|with\b|as\b|by\b|toward\b|towards\b|into\b|over\b|under\b
                   |through\b|against\b|upon\b|within\b|without\b)
                 [\w'’-]+/ix,
      message: '"isn\'t X, it\'s Y" corrects a description nobody offered.',
      suggestion: "State the second half on its own; drop the rejected one.",
      examples_bad: [
        "It isn't the tool. It's the habit.",
        "This wasn't a setback, it was a setup for the next release.",
        "The delay wasn't the network. It was the retry loop.",
        "Those aren't the metrics, they're the vanity numbers.",
        "This isn't failure. It's iteration.",
        "They're not customers; they are partners.",
        "These weren't accidents. They were choices."
      ],
      examples_ok: [
        # Predicate adjectives on both sides: a comment, not a replacement.
        "It isn't ready. It's close.",
        # Escalation word: that shape belongs to not-just-x-but-y.
        "It isn't only the cost. It is the delay too.",
        # The second clause needs a pronoun subject and a copula.
        "It wasn't the alarm that woke me. The dog did.",
        # The two clauses must be adjacent.
        "It isn't the heat. Everyone says so, and they have said so for years. It's the humidity.",
        # Prepositional complements are ordinary contrast.
        "The message was not to him; it was to the clerk.",
        # Pronoun complement.
        "It was not me who called; it was the neighbour.",
        # The guard holds after the article, which is matched atomically.
        "The fire was not out; it was the only light left.",
        # A paragraph break ends the frame.
        "The plan was not the problem.\n\nIt was the schedule."
      ],
      rationale: "The frame rejects a description nobody proposed, then supplies the true " \
                 "one, so the sentence sounds like a correction while correcting nobody. It " \
                 "is 'not A but B' with the conjunction dropped and the second half promoted " \
                 "to its own clause, which is the form models reach for most. Ordinary prose " \
                 "contrasts two things this way too, so the rule ships at info: it reports " \
                 "the shape, not a verdict."
    ),
    Rule.new(
      id: "not-by-x-but-by-y",
      category: "structure",
      severity: "info",
      # The corrective built on a repeated preposition: "not by A, but by B",
      # "not from A but from B". The copula rules above cannot see it because
      # nothing precedes "not" but the verb or a dash, so the anchor here is
      # the preposition itself, which must repeat after "but". That repetition
      # is the whole narrowing: a different preposition on the B side is a
      # concession or an afterthought, not a correction.
      #
      # A is capped at six words and B may not open with a pronoun. Neither
      # guard removes a false positive -- every corpus hit is the real shape
      # -- they only keep the match from running across a sentence.
      pattern: /\bnot(?:[ \t]|\r?\n(?!\s*\n))+
                 (?<prep>by|for|from|with|about|in|on|at|to|of|through|because(?:[ \t]|\r?\n(?!\s*\n))+of|out(?:[ \t]|\r?\n(?!\s*\n))+of)
                 (?:[ \t]|\r?\n(?!\s*\n))+
                 (?:[\w'’-]+(?:[ \t]|\r?\n(?!\s*\n))+){0,5}[\w'’-]+
                 ,?(?:[ \t]|\r?\n(?!\s*\n))+but(?:[ \t]|\r?\n(?!\s*\n))+
                 (?:rather(?:[ \t]|\r?\n(?!\s*\n))+)?
                 \k<prep>(?:[ \t]|\r?\n(?!\s*\n))+
                 (?!that\b|this\b|it\b|him\b|her\b|them\b|me\b|us\b|you\b|which\b|whom\b|what\b)
                 (?:a\s+|an\s+|the\s+)?[\w'’-]+/ix,
      message: '"not by A, but by B" is the corrective frame on a repeated preposition.',
      suggestion: "Say what it was by; drop the 'not by… but by' frame.",
      examples_bad: [
        "We won not by luck but by preparation.",
        "The gain came not from the model, but from the data.",
        "Judge it not on the demo but on the deployment.",
        "Revenue grew this quarter — not by a rounding error, but by a margin that survives any cut of the data."
      ],
      examples_ok: [
        # The preposition changes: a contrast, not a correction.
        "He came not for the money but with an apology.",
        # B-side pronoun.
        "She wrote not to him but to them.",
        # A capped at six words.
        "The deal closed not in the long slow grind of the seventh week, but in an afternoon.",
        # "not only" belongs to the escalation rules, and the B preposition here would not repeat anyway.
        "It was not only for the money.",
        # A paragraph break ends the frame.
        "We won not by luck\n\nBut by then it hardly mattered."
      ],
      rationale: "The 'not A but B' corrective with the copula swapped for a repeated " \
                 "preposition, which is how a model corrects a claim about means or " \
                 "cause ('not by luck, but by design'). People write it too -- Thoreau " \
                 "and Melville both lean on it -- so the rule ships at info. It reports " \
                 "the shape; a human reader decides whether it earned its place."
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
      id: "everyone-nobody",
      category: "structure",
      severity: "warning",
      # The comma-spliced antithesis on quantifier subjects: "Everyone wants
      # the dashboard, nobody maintains it." One clause opens on
      # everyone/everybody, the other on nobody/no one/none or "one N"
      # ("everyone may pitch, one editor decides"), joined by a bare comma, and
      # the second clause closes the sentence. The comma splice is the
      # evidence: with "and" or "but" it is an ordinary sentence, and with a
      # period it is two. The first subject must open a clause (one or two
      # spaces after a stop, as elsewhere in the catalog), the two subjects
      # must differ in polarity, so the anaphoric "nobody is on my side,
      # nobody takes part with me" is not a hinge, and each clause is at most
      # eighty characters with no newline, so a hinge never crosses a
      # paragraph break and the comma gap is at most two spaces.
      #
      # The "one N" and "none" subjects need guards, because the comma slot
      # also holds phrases that are not clauses. "one of them", "one by one",
      # "one per ticket", and a measure ("one hour before the talk") are out;
      # so is a capitalised "One" mid-sentence, a proper noun, which the
      # case-sensitive lookahead catches under /i. "none of which" is a
      # relative clause and "none louder than" a comparative, and both are
      # out.
      pattern: /(?:^|(?<=[.!?:;])[ \t]{1,2})\K
                (?:(?:everyone|everybody)[ \t]+[^,.;:!?\n]{2,80},[ \t]{1,2}
                     (?:nobody|no[ \t]+one|none(?![ \t]+(?:of|more|less|so)\b|[ \t]+\w+er\b)
                       |one[ \t]+(?!of\b|by\b|per\b|(?:hour|minute|second|day|week|month|year|dollar|cent|mile|foot|inch|pound|kilo|metre|meter)s?\b)(?-i:(?=[a-z]))[\w'’-]+)
                  |(?:nobody|no[ \t]+one)[ \t]+[^,.;:!?\n]{2,80},[ \t]{1,2}
                     (?:everyone|everybody|one[ \t]+(?!of\b|by\b|per\b|(?:hour|minute|second|day|week|month|year|dollar|cent|mile|foot|inch|pound|kilo|metre|meter)s?\b)(?-i:(?=[a-z]))[\w'’-]+))
                [ \t]+[^,.;:!?\n]{2,80}[.;!?]/ix,
      message: '"Everyone X, nobody Y." is the AI antithesis hinge.',
      suggestion: "Say which one is the problem, in its own sentence.",
      examples_bad: [
        "Everyone wants the dashboard, nobody maintains it.",
        "Run it like a newsroom desk: everyone may pitch, one editor decides.",
        "Nobody owns the file, everyone edits it.",
        "Everyone wanted the job, none applied.",
        # Two spaces after the stop still open a clause.
        "Ship it.  Everyone wants the dashboard, nobody maintains it.",
        # Clauses may run to eighty characters.
        "Everyone talks about observability in the abstract, nobody wants to own the pager rotation."
      ],
      examples_ok: [
        # A conjunction makes it a sentence, not a hinge.
        "Everyone left early, and nobody noticed.",
        # Pride and Prejudice (Austen, public domain): the same subject twice is
        # anaphora, not antithesis.
        "Nobody is on my side, nobody takes part with me;",
        # The second clause must close the sentence.
        "Everyone who came, nobody excepted, signed the book.",
        # A period is two sentences.
        "Everyone wants the dashboard. Nobody maintains it.",
        # "one of", "one by one", "one per", a measure, and a proper noun are
        # not a second subject.
        "Everyone signed up, one of them dropped out later.",
        "Nobody moved for a moment, one by one they stood up.",
        "Everybody got a ticket, one per person at the gate.",
        "Everyone arrived by noon, one hour before the talk.",
        "Nobody stirred in the hall, One Direction played on the radio.",
        # A relative clause and a comparative are not a second subject.
        "Everyone brought a dish, none of which we actually ate.",
        "Everyone in the room laughed, none louder than the author himself.",
        # A clause over eighty characters is a sentence of its own.
        "Everyone who has ever tried to keep a dashboard alive through two reorganisations and a migration knows the cost, nobody maintains it.",
        # A paragraph break is not a comma.
        "Everyone wants the dashboard,\n\nnobody maintains it."
      ],
      rationale: "The everyone/nobody hinge states a whole diagnosis as a balanced pair of " \
                 "clauses, and the balance is what makes it sound settled. Models reach for " \
                 "it to close a setup; careful writers join the clauses with a conjunction " \
                 "or give the problem its own sentence."
    ),
    Rule.new(
      id: "np-fragment-and",
      category: "structure",
      severity: "info",
      # A whole sentence that is two noun phrases and an "and": "A named owner
      # and a quarterly review." It is the fix half of a model's
      # problem-then-fix pair, with the verb left for the reader to supply.
      # The sentence must open on A/An/One at a sentence start or after a
      # list marker (the pair's usual habitat is a bulleted list), the second
      # phrase must open on a/an/one, each phrase is one to three words, and
      # nothing else may be in the sentence. No auxiliary or modal may appear
      # anywhere in it, contractions included, so "A man and a woman were
      # there." and "A man and a woman aren't here." never match.
      #
      # Ships at info, and this is why: a lexical verb is invisible to the
      # pattern, so "A car and a truck collided." has the same shape and
      # flags. The corpora say that sentence is rare (one hit in 1.25M words
      # of public-domain prose, most of it narrative), but it is a complete
      # sentence, and nothing a regex can see separates it from the fragment.
      pattern: /(?:^|(?<=[.!?])[ \t]{1,2})(?:[-*+•][ \t]+|\d+[.)][ \t]+)?\K(?:A|An|One)(?:[ \t]|\r?\n(?!\s*\n))+
                (?:(?!(?:(?:is|are|was|were|be|been|being|am|has|have|had|having|does|do|did|can|could|will|would|shall|should|must|may|might|ought|ain)(?![\w'’-])|\w+n['’]t(?![\w'’-])))[\w'’-]+(?:[ \t]|\r?\n(?!\s*\n))+){0,2}(?!(?:(?:is|are|was|were|be|been|being|am|has|have|had|having|does|do|did|can|could|will|would|shall|should|must|may|might|ought|ain)(?![\w'’-])|\w+n['’]t(?![\w'’-])))[\w'’-]+,?(?:[ \t]|\r?\n(?!\s*\n))+and(?:[ \t]|\r?\n(?!\s*\n))+(?:a|an|one)(?:[ \t]|\r?\n(?!\s*\n))+
                (?:(?!(?:(?:is|are|was|were|be|been|being|am|has|have|had|having|does|do|did|can|could|will|would|shall|should|must|may|might|ought|ain)(?![\w'’-])|\w+n['’]t(?![\w'’-])))[\w'’-]+(?:(?:[ \t]|\r?\n(?!\s*\n))+|(?=\.))){1,3}\.(?=\s|\z)/x,
      message: '"A X and a Y." as a whole sentence is an AI fragment.',
      suggestion: "Give the sentence a verb, or fold it into the one before.",
      examples_bad: [
        "Nobody checked it after launch. A named owner and a quarterly review.",
        "One merger and a version-controlled folder.",
        "An owner and a deadline.",
        # The pair's usual habitat.
        "- A named owner and a quarterly review.",
        "1. A named owner and a quarterly review.",
        # A comma before "and" is still the pair.
        "A named owner, and a quarterly review."
      ],
      examples_ok: [
        "A man and a woman were waiting at the door.",
        "A dog and a cat can share a house.",
        # Contractions and the rarer auxiliaries are auxiliaries too.
        "A man and a woman aren't here.",
        "A boy and a girl shall meet.",
        "A boy and a girl ought to know.",
        # Not at a sentence start.
        "We hired a designer and an engineer.",
        # More than three words on a side is a clause, not a label.
        "A long walk down to the river and a swim before breakfast.",
        # Only "and" between two phrases; a list is not the pair.
        "A hammer, a saw, and a level."
      ],
      rationale: "Two noun phrases and an 'and', standing as a sentence, is how a model " \
                 "hands over a fix without committing to a verb: the reader supplies " \
                 "'you need' or 'add'. A short sentence with a plain verb ('A car and a " \
                 "truck collided.') has the same shape and cannot be told apart, which is " \
                 "why this is a question rather than a verdict; a draft full of them, " \
                 "especially as list items, should be read as a warning."
    ),
    Rule.new(
      id: "quip-question",
      category: "structure",
      severity: "info",
      # The verbless question that opens a pitch: "No invite?", "New to the
      # tool?", "Still stuck?", "Ready to start?". It must start a sentence,
      # open on one of a short list of words, run one to four more words, and
      # end on the question mark, with no auxiliary or contraction anywhere,
      # so a real question ("Not what you expected?" flags, "Is it new?" does
      # not) stays out. "Need" and "Want" are not on the list: "Need help?"
      # is a question with its verb elided, not a verbless one. Gaps may
      # cross a hard-wrapped newline but never a paragraph break. Ships at
      # info: dialogue and forum replies ask the same shape of a person, and
      # one is a question, not a verdict.
      pattern: /(?:^|(?<=[.!?])[ \t]{1,2})\K(?:No|New|Still|Not|Already|Ready|Curious|Unsure|Stuck|Tired|Confused|Worried)(?:[ \t]|\r?\n(?!\s*\n))+
                (?:(?!(?:is|are|was|were|has|have|had|do|does|did|can|could|will|would|should|must|may|might|am|[\w]+n['’]t)\b)[\w'’-]+(?:[ \t]|\r?\n(?!\s*\n))+){0,3}(?!(?:is|are|was|were|has|have|had|do|does|did|can|could|will|would|should|must|may|might|am|[\w]+n['’]t)\b)[\w'’-]+[ \t]*\?/x,
      message: "A verbless opening question is a marketing-copy tell.",
      suggestion: "Ask it as a sentence, or state what follows without the setup.",
      examples_bad: [
        "No invite? Start a team of your own.",
        "New to the tool? Read the guide first.",
        "Still stuck after that? Ask in the channel.",
        "Ready to start?",
        "Not what you expected?",
        # A hard-wrapped quip survives one newline.
        "Still\nstuck? Ask in the channel."
      ],
      examples_ok: [
        "Is it new?",
        "No, they aren't?",
        "Not sure if it will work?",
        # Not at a sentence start.
        "She asked, Still unsure?",
        # An elided verb is a question, not a quip.
        "Need help?",
        "Want the short version?",
        # Too long to be a quip.
        "Still waiting for the last batch of reviews from the other team?",
        # A paragraph break ends it, and the question mark stays on the line.
        "Not sure\n\nwhat happened here?",
        "Not sure what happened\n?"
      ],
      rationale: "A one-line question with no verb is the hook of a landing page, and a " \
                 "model reaches for it to open any section. People ask the same shape in " \
                 "replies, of a product or a person, so one flag is a question; several " \
                 "in a draft should be read as a warning."
    ),
    Rule.new(
      id: "mic-drop-closer",
      category: "structure",
      severity: "info",
      # The kicker: a sentence of at least sixty characters, then a closer of
      # two to eight words that ends the paragraph and opens on a quantifier
      # or a deictic ("Nothing here needs a new login.", "Most teams end up
      # with two.", "Then find out whether it paid off."). The long sentence
      # must start a sentence itself, so the scan is linear, and \K drops it
      # from the match so the note points at the closer. The closer must be
      # the last thing in the paragraph: a blank line or the end of the text
      # must follow, so the same sentence mid-paragraph, or a bullet followed
      # by another bullet, is just a sentence. Both sentences may cross a
      # hard-wrapped newline. Whitespace inside the long sentence is capped at
      # two spaces a run, so a URL or code span blanked by --markdown cannot
      # manufacture the sixty characters. The gap between the two sentences
      # is one or two spaces, and the closer needs at least two words.
      #
      # Ships at info, and the rationale says why: people end paragraphs this
      # way too, at about 150 per million words on Hacker News. One is
      # nothing. A draft where most paragraphs end this way is the tell, and
      # an agent that sees the flag repeat should read the family as a
      # warning.
      pattern: /(?:^|(?<=[.!?])[ \t]{1,2})(?:[^.!?\n\s]|(?<![ \t])[ \t]{1,2}(?![ \t])|\r?\n(?!\s*\n)[ \t]*){60,}[.!?][ \t]{1,2}\K
                (?:Nothing|Most|None|Everything|Everyone|Nobody|Then|Neither|Both|That|This|It)
                (?:,?(?:[ \t]|\r?\n(?!\s*\n))+[\w'’-]+){1,7}[.!?](?=[ \t]*(?:\r?\n[ \t]*(?:\r?\n|\z)|\z))/x,
      message: "A short quantifier-led closer after a long sentence is the AI kicker.",
      suggestion: "Cut the closer, or move the claim to the front of the paragraph.",
      examples_bad: [
        "Each step can be done in the app, pasted into whichever assistant the company allows, or run the way the team already works. Nothing here needs a new login.",
        "Keep a private notebook for the drafts where taste matters, and a shared one for the work that passes between desks. Most teams end up with two.",
        "Ship the shared notebook to a team that has agreed on the owner, the folder, and the first task it will hold. Then find out whether it paid off.\n\nNext week: the audit.",
        # Both sentences may be hard-wrapped.
        "Each step can be done in the app, pasted into whichever\nassistant the company allows, or run the way the team\nalready works. Nothing here\nneeds a new login.\n"
      ],
      examples_ok: [
        # No long sentence before it.
        "Nothing here needs a new login.",
        # Not the end of the paragraph, wrapped or not.
        "Each step can be done in the app, pasted into whichever assistant the company allows, or run the way the team already works. Nothing here needs a new login. The prompts are in the appendix.",
        "Each step can be done in the app, pasted into whichever assistant the company allows, or run the way the team already works. Nothing here needs a new login.\nThe prompts are in the appendix.",
        # A closer that does not open on the list.
        "Each step can be done in the app, pasted into whichever assistant the company allows, or run the way the team already works. We kept the prompts short.",
        # Too long to be a kicker.
        "Each step can be done in the app, pasted into whichever assistant the company allows, or run the way the team already works. Most of the teams we spoke to ended up using a mix of two of them.",
        # Too short to be a kicker.
        "Each step can be done in the app, pasted into whichever assistant the company allows, or run the way the team already works. Nothing.",
        # More than two spaces is not a sentence gap.
        "Each step can be done in the app, pasted into whichever assistant the company allows, or run the way the team already works.   Nothing here needs a new login.",
        # A bullet followed by another bullet is not a paragraph end.
        "- Each step can be done in the app, pasted into whichever assistant the company allows, or run the way the team already works. It works.\n- We moved the deploy script into the repo so the on-call rota could run it. It works.\n- The rest is in the appendix and needs no change from anyone on the team.\n",
        # Blanked text cannot make the long sentence.
        "See                                                                          here. It works.\n"
      ],
      rationale: "A short sentence after a long one borrows emphasis from the contrast, " \
                 "and a model spends that emphasis at the end of nearly every paragraph, " \
                 "restating the point it has just made. People write the shape too, at " \
                 "about 150 per million words, so one flag means nothing; a draft " \
                 "where the flag repeats paragraph after paragraph should be read as a " \
                 "warning, and the fix is usually to delete the closer outright."
    ),
    Rule.new(
      id: "short-run",
      category: "structure",
      severity: "info",
      # Three consecutive sentences of thirty characters or fewer, each
      # opening on a letter and closing on a full stop, with no quotation
      # mark or digit in any of them: "Nobody used it. A named owner. Then a
      # review." The run must start at a real boundary (the text, a blank
      # line, a line ending on a stop, or a stop and one or two spaces), so
      # the short tail of a hard-wrapped long sentence never opens one; it
      # may cross a hard-wrapped newline but not a paragraph break, and the
      # indent after a newline is at most four spaces, so a URL or code span
      # blanked by --markdown cannot weld two sentences. A list marker may
      # open the run, but consecutive bullets are a list, not staccato.
      #
      # Dialogue is excluded by the boundary: a closing quote after the stop
      # is not a space. A quotation mark inside a sentence is excluded by the
      # class. A sentence with a digit in it is data, a "sentence" ending on
      # a lone capital is an initial ("Alan W."), and a run holding a
      # multi-letter abbreviation ("Prof.", "Dept.") is dropped, since the
      # abbreviation is not a sentence end. Questions and exclamations are
      # left out because a run of them is a different device.
      #
      # Ships at info. A staccato run is a device people use on purpose, at
      # about thirty per million words on Hacker News, so one flag is a
      # question. A draft that keeps doing it is the tell, and an agent that
      # sees the flag repeat should read the family as a warning.
      pattern: /(?:\A|(?<=\n\n)|(?<=[.!?])[ \t]{0,2}\r?\n|(?<=[.!?])[ \t]{1,2})[ \t]{0,4}(?:[-*+•][ \t]+|\d+[.)][ \t]+)?\K
                (?:[A-Za-z][^.!?\n"“”0-9]{3,29}(?<![^A-Za-z][A-Z])\.(?:[ \t]{1,2}|\r?\n(?!\s*\n)[ \t]{0,4})){2}
                [A-Za-z][^.!?\n"“”0-9]{3,29}(?<![^A-Za-z][A-Z])\.(?=\s|\z)/x,
      message: "A run of three short sentences reads as AI staccato.",
      suggestion: "Join two of them, or give one of them a subordinate clause.",
      skip: [/\b(?:Corp|Prof|Dept|Sept|Univ|Assn|approx|misc|cont|Ave|Blvd|Fig|Est|Inc|Ltd|vol|etc|Mrs|Mr|Ms|Dr|St|Jr|Sr|No)\./],
      examples_bad: [
        "Nobody used it. A named owner. Then a review.",
        "The draft sat on one desk. Nobody else saw it. So it never shipped.",
        "Drafts only at first. Widen after a month. Two people sign off.",
        # A hard-wrapped run survives one newline.
        "Nobody used it. A named owner.\nThen a review.",
        # A bullet may hold a run.
        "- Nobody used it. A named owner. Then a review.",
        # An acronym ends a sentence; only a lone initial does not.
        "Nobody used it. We shipped it to QA. Then a review."
      ],
      examples_ok: [
        "Nobody used it. A named owner and a quarterly review that the whole team can see.",
        # Dialogue.
        "\"Go now.\" \"I will.\" \"Then go.\"",
        # A quotation mark inside a sentence.
        "He said \"go\" today. Then a review. So it ended.",
        # A paragraph break ends the run.
        "Nobody used it. A named owner.\n\nThen a review.",
        # Questions and exclamations are a different device.
        "Who owns it? Nobody. Who checks it? Nobody.",
        # Two short sentences are a pair.
        "Ship it. Then find out if it was worth the effort and the wait.",
        # One sentence over thirty characters breaks the run.
        "Nobody used it. A named owner reviewed the draft again. Then a review.",
        # Numbers are data, and an initial is not a sentence end.
        "Hold cash. Expected value: 1000. Expected tax: none.",
        "Alan W. Prosser loves officer Kane. Nobody else does.",
        # An abbreviation is not a sentence end.
        "She wrote to Prof. Ellis at the Dept. Nobody replied to her.",
        # The tail of a hard-wrapped long sentence does not open a run.
        "The build had been red since Tuesday and nobody could say quite why, so we\nbisected it. Then we found the flake. It was a clock skew.",
        # Blanked text after a newline cannot weld two sentences.
        "Nobody used it. A named owner.\n                                  Then a review.",
        # Consecutive bullets are a list.
        "- Fast setup.\n- No config.\n- Free tier.\n"
      ],
      rationale: "Short sentences in a row borrow force from their rhythm, and a model " \
                 "falls into the rhythm whenever it wants to sound decisive. People do it " \
                 "on purpose, about thirty times per million words, so one flag is a " \
                 "question; a draft where the flag repeats should be read as a warning."
    ),
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

    Rule.new(
      id: "question-isnt",
      category: "structure",
      severity: "info",
      # The resolving clause is required, so a plain rhetorical question never
      # matches. "The real question is" is ordinary English and is excluded by
      # the adjacency of "question" to the negated copula.
      pattern: /\bthe\s+question\s+is(?:n['’]?t|\s+not)\s+
                (?:whether|if|how|what|why|who)\b
                [^.!?\n]{0,80}?,\s*(?:it['’]?s|but)\b/ix,
      message: "The question isn't X, it's Y -- a correction of a question nobody asked.",
      suggestion: "Ask the question you mean to ask, and drop the discarded one.",
      examples_bad: [
        "The question isn't whether the model works, it's whether anyone trusts it.",
        "The question is not how fast it runs, but how often it fails.",
        "The question isn't what we build, it's who we build it for."
      ],
      examples_ok: [
        "The real question is whether the funding arrives.",
        "The question is whether the court will hear the appeal.",
        "The question isn't settled."
      ],
      rationale: "This is the corrective frame in interrogative dress: a question is raised " \
                 "only to be swapped for a better one, so the writer scores a point against " \
                 "nobody. The discarded question is usually the reasonable one, and stating " \
                 "the second question alone loses nothing."
    ),
    Rule.new(
      id: "less-about-more-about",
      category: "structure",
      severity: "info",
      # The full frame is required at both ends. Bare "less about" and bare
      # "more about" are ordinary English on their own, and the subject slot
      # is limited to the pronouns so that a sentence with a real subject --
      # "the dispute is less about money" -- stays clean.
      pattern: /\b(?:it['’]?s|it\s+is|this\s+is|that['’]?s|that\s+is)\s+less\s+about\s+
                [^.!?\n]{1,60}?\b(?:(?:and\s+|,\s*)?more\s+about|than\s+about)\b/ix,
      message: "Less about X, more about Y -- a reframe that discards a reading nobody offered.",
      suggestion: "Say what it is about. The discarded half is usually filler.",
      examples_bad: [
        "It's less about the tooling and more about the habit.",
        "This is less about speed, more about consistency.",
        "That's less about money than about trust."
      ],
      examples_ok: [
        "It's less about the tooling than I expected.",
        "Tell me more about the delay.",
        "We care less about speed these days."
      ],
      rationale: "The reframe pairs a rejected description with an accepted one, so the " \
                 "sentence sounds like a correction while correcting nobody. The rejected " \
                 "half is chosen for the contrast, not because a reader proposed it, and " \
                 "the second half stands on its own."
    ),
    Rule.new(
      id: "trailing-significance-participle",
      category: "structure",
      severity: "warning",
      # The verb list is closed and short on purpose. Wikipedia's "signs of AI
      # writing" names eight watch words for this construction; half of them
      # did not survive probing. In 1.85M words of pre-2022 Hacker News and
      # 2.66M words of public-domain prose, "driving" appears in this position
      # 14 times, "representing" 16, "reflecting" 10, "marking" 5 -- all of it
      # ordinary English ("driving the price down", "representing a majority of
      # the voting power"), and all of it the same shape a model produces, so
      # no narrowing separates the two. Those verbs are out. The ones that ship
      # are used in both corpora but never here: "highlighting" appears 17
      # times in the HN sample and not once after a comma. "underscoring" is
      # left out because underscores-highlights already flags it bare.
      #
      # "emphasizing", "echoing" and "affirming" are out for the same reason,
      # found late: the shipped pattern flagged four sentences in the
      # public-domain corpus and all four had a person as the subject. A person
      # can emphasize or echo something; an event cannot. That is the animacy
      # distinction the construction really turns on, and a regex cannot see
      # it, so the verbs that carry a human subject in ordinary prose stay out
      # rather than being approximated. The narrowed list flags nothing in
      # either corpus.
      #
      # "ensuring" is also out, despite scoring 1 hit in each corpus: neither
      # corpus contains software documentation, where "the mutex is held,
      # ensuring no two writers collide" states a real consequence rather than
      # claiming significance.
      #
      # Two guards keep gerund lists out. A preceding -ing word means the match
      # is the second item of a list ("cutting, shaping stone"), and a
      # following comma, "and", or "or" means it is not the last ("cutting,
      # shaping and sanding"). "signaling to" is the physical gesture.
      pattern: /\w+(?<!ing),[ \t]+
                (?:further[ \t]+|thereby[ \t]+|thus[ \t]+|ultimately[ \t]+)?
                (?:highlighting|showcasing|reinforcing|shaping|enhancing|
                   cementing|solidifying|embodying|fostering|facilitating|
                   signall?ing(?![ \t]+to\b))
                (?![ \t]*(?:,|and\b|or\b))
                [ \t]+\S/ix,
      message: "Trailing -ing clause claiming significance -- a stock AI move.",
      suggestion: "Cut the clause, or state the consequence as its own sentence with a subject.",
      examples_bad: [
        "The bridge reopened in March, cementing its place in the city's skyline.",
        "Attendance doubled that year, highlighting the appeal of the new format.",
        "Its sign carries both languages, showcasing the range of visitors it draws.",
        "Trade routes crossed here for centuries, shaping the food people cook.",
        "The grant was renewed, further solidifying the lab's standing.",
        "The team shipped every week, reinforcing the sense that momentum mattered.",
        "The colour was mixed by hand, embodying the care the shop is known for.",
        "The lab was refitted last year, enhancing what the group can measure.",
        "The station sits beside the port, facilitating the movement of goods inland."
      ],
      examples_ok: [
        # The verb in its ordinary position, with a person or document as subject.
        "The report highlights the two findings that changed our minds.",
        "She emphasises the method rather than the results.",
        # Gerund lists: the match is a middle item, not a trailing clause.
        "The work involves cutting, shaping and polishing the stone.",
        "They spent the morning cutting, shaping stone for the wall.",
        "The class covers drawing, shaping, then firing the clay.",
        # The physical gesture, not a claim about meaning.
        "He turned toward the bar, signaling to the waiter.",
        # War and Peace (Maude translation, public domain): a person as the
        # subject, which is the case the verb list cannot distinguish, so
        # "emphasizing", "echoing" and "affirming" are excluded outright.
        "recounted Bitski, emphasizing certain words and opening his eyes",
        "\u201cOu-rou-rou!\u201d yelled the crowd, echoing the crash of the roof",
        # A paragraph break is not a comma.
        "The kiln runs hot\n\nShaping the clay comes first."
      ],
      rationale: "A participle hung off the end of a sentence, with a fact or an event as " \
                 "its subject, asserts what something means without anyone having to say it. " \
                 "An event cannot highlight or showcase anything; the claim belongs to a " \
                 "narrator who never appears. Careful writers put the verb in its own clause " \
                 "with a subject, or leave the significance to the reader."
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
