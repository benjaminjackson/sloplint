# Changelog

All notable changes to this project are documented here. Format loosely
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### New rules

- `and-nothing-else` (rhetorical-tic, warning) flags a sentence that closes on
  ", and nothing else", ", nothing more", ", nothing further" or ", and no
  more". A model told to return one thing and nothing else carries the phrasing
  into the prose it writes afterwards, where the exclusion repeats what the
  sentence already said.
- `nothing-else-frag` (rhetorical-tic, warning) flags the same exclusion built
  as a fragment: "Return the JSON. Nothing else."
- `honestly`, `honest-x` and `most-honest-x` (rhetorical-tic, warning) answer
  the "honest" habit the way `cleanly`, `clean-x` and `cleanest-x` answer the
  "clean" one. `honestly` takes the manner adverb closing on a full stop or
  comma ("these two rows compare honestly"); `honest-x` takes the adjective in
  front of the writer's own construction ("an honest comparison", "the honest
  framing"); `most-honest-x` takes the self-ranking superlative.

  `honestly` is anchored on position alone, so a dialogue tag ("said Isabel
  honestly") and the sentence-final hedge of casual speech ("it's beyond boring
  honestly") both match. Both are rare: twice in 3.65M words of public-domain
  prose and ten times in 6.07M words of pre-2022 Hacker News. The two noun
  rules flag nothing in either corpus; "an honest answer" and "an honest
  assessment" are left out because on Hacker News they mean a person telling
  the truth, not a writer praising their own framing.

  Both rules are wide on purpose. There is no verb list and no imperative
  requirement, so the only narrowing is structural, and English has always used
  this tail: the pair flags three times in 1.92M words of public-domain prose
  and twice in 461k words of pre-2022 Hacker News, and `and-nothing-else` flags
  every refrain in "The Raven". Expect to dismiss it on fiction and on quoted
  verse.

## [0.5.0] - 2026-08-27

The catalog grows from 49 rules to 50, and `check` becomes the default
command.

### Changed

- A first argument that is not a command name is now taken as a path, so
  `sloplint draft.md` and `sloplint -` scan instead of failing with
  `unknown command`. A mistyped command fails as a missing file, still exit 2.

### New rules

- `trailing-significance-participle` (`structure`, `warning`): the participle
  clause hung off the end of a sentence to say what a fact means, "the sign
  carries both names, showcasing the range of travellers it draws". An event
  cannot showcase anything, so the claim belongs to a narrator who never
  appears in the text.

  The verb list is closed and narrow: `highlighting`, `showcasing`,
  `reinforcing`, `shaping`, `enhancing`, `cementing`, `solidifying`,
  `embodying`, `fostering`, `facilitating`, `signalling`. Verbs humans write
  in the same position -- `driving`, `representing`, `reflecting`, `marking`,
  `contributing`, `illustrating`, `demonstrating`, `emphasising`, `echoing`,
  `affirming` -- stay out, because they usually take a person as the subject
  and a regex cannot see the subject. `underscoring` is left to
  `underscores-highlights`.

  Two guards drop gerund lists: a preceding -ing word means the match is a
  middle list item, and a following comma, "and" or "or" means it is not the
  last item. "signalling to" is the physical gesture and does not flag.

## [0.4.0] - 2026-08-26

The catalog grows from 29 rules to 49. Every new rule was probed against
pre-2022 Hacker News comments or Project Gutenberg texts before shipping,
and each narrowing is pinned by an `examples_ok` fixture.

### New rules

- `worth-saying-plainly` (`rhetorical-tic`, `warning`): the self-rating
  opener, "Worth saying plainly, ...". Needs all three slots -- evaluative
  adjective, speech verb, manner adverb -- at a sentence or paragraph start.
- `hold-onto-that` (`rhetorical-tic`, `warning`): the sentence-initial
  reader directive "Hold onto that" / "Hold on to this".
- `cleanly` (`rhetorical-tic`, `warning`): the bare manner adverb, "splits
  cleanly into", "maps cleanly onto".
- `clean-count` (`rhetorical-tic`, `warning`): a number plus "clean" plus a
  partition noun, "two clean buckets".
- `cleanest-x` (`rhetorical-tic`, `warning`): the superlative used to rank
  one's own claim, "the cleanest framing is".
- `clean-x` (`rhetorical-tic`, `info`): "clean" in front of an idea as
  praise, "a clean abstraction".
- `earns-its-place` (`rhetorical-tic`, `warning`): "earns its place" and
  "earns its keep", the metaphor of a sentence or feature paying rent.
- `does-a-lot-of-work` (`rhetorical-tic`, `warning`): the remark that points
  at a word and rates its load, "that qualifier does a lot of work here".
- `failure-mode-here` (`rhetorical-tic`, `warning`): "the failure mode here
  is", the engineering term borrowed for an argument or a person. The
  deictic "here" is the whole narrowing.
- `thats-the-tension` (`rhetorical-tic`, `warning`): the sentence-initial
  closer "That's the tension." and "That's the bet:".
- `right-up-until` (`rhetorical-tic`, `warning`): "right up until it
  doesn't". The intensifier is the narrowing -- the plain "until it doesn't"
  is an old human idiom and stays clean.
- `two-things-true` (`rhetorical-tic`, `warning`): "two things can be true",
  the concession that names neither half.
- `notice-what-there` (`rhetorical-tic`, `warning`): the self-referential
  attention cue, "Notice what that argument did there", "Read that again".
- `notice-what` (`rhetorical-tic`, `info`): the bare sentence-initial
  "Notice what ...", the quiet half of the pair above.
- `none-of-this-is-to-say` (`rhetorical-tic`, `warning`): the sweeping
  concession that retracts an argument nobody made.
- `if-im-being-honest` (`rhetorical-tic`, `info`): the candor preamble.
  Plain "to be honest" and "I'll be honest" stay clean.
- `genuinely` (`rhetorical-tic`, `info`, off by default): every
  "genuinely". No allowlist separates the intensifier from the contrastive
  use, so the rule runs only when named in `--select`, beside
  `rule-of-three`.
- `question-isnt` (`structure`, `info`): the corrective frame in
  interrogative dress, "The question isn't whether X, it's whether Y".
  Requires the resolving clause.
- `and-thats-fine` (`rhetorical-tic`, `info`): the permission-granting
  closer. The match must open and close a sentence.
- `less-about-more-about` (`structure`, `info`): the comparative
  reframe, "It's less about X and more about Y". Both halves required.

### Changed rules

- `sit-with-that` broadened to any object. Two branches: the deictic object
  needs no anchor, any other object needs the sentence-initial imperative.
- `the-punchline-is` widened to take "the honest answer is" and "the honest
  version is".
- `worth-naming` and `worth-saying-plainly` widened together and stopped
  double-flagging. Both take more verbs; `worth-naming` now yields the
  adverb-bearing form to `worth-saying-plainly`.

### Docs

- `docs/SPEC.md` credits Wikipedia's "Signs of AI writing" and slopwash.com's
  anti-slop ruleset, next to proselint, vale and write-good.
- The SPEC rule catalog had drifted ten rules behind the code. It is resynced,
  and `spec/rules_spec.rb` now asserts every rule id appears in `docs/SPEC.md`,
  the same way it already asserts the README counts.

## [0.3.0] - 2026-08-02

- New rule `load-bearing` (`rhetorical-tic`, `warning`): "load-bearing" used
  as a borrowed metaphor for anything important, outside its literal
  construction sense (a wall, a column, a beam). Guards on both sides —
  a building noun right after it, or the predicate form ("the wall is
  load-bearing") — leave the construction sense clean.
- New rule `is-is` (`rhetorical-tic`, `warning`): the doubled copula, "what it
  is is a mistake" / "the thing is, is that...". No anchor needed -- the bare
  pattern scored 0 hits across ~1.9M words of public-domain and modern prose.
- `exactly-the` replaced by the broader `exact-exactly` (`rhetorical-tic`,
  now `info`): flags "exact/exactly" generally, not just the fixed "exactly
  the point/kind/problem/…" phrase shape, with an allowlist for the places
  it's doing real work (numbers, times, same/opposite/way/etc.). Severity
  drops to `info` because a common word will still slip through on cases
  the allowlist hasn't seen yet.
- `thats-not-nothing` replaced by the broader `not-nothing`
  (`rhetorical-tic`, `warning`): catches the "is not nothing" litotes
  regardless of subject ("Fifty basis points is not nothing"), not only
  the demonstrative-subject form ("that's not nothing"). Personal-subject
  litotes ("he was not nothing to her") and the "there is not nothing"
  philosophy frame are allowlisted as legitimate human use.
- `underscores-highlights` broadened (`puffery`, still `info`): "underscores
  the need for", "underscored how fragile", and "underscoring the urgency"
  now match, not only the fixed "underscores/highlights/emphasizes its/the/
  their importance/significance" phrase. The character-noun sense
  ("a leading underscore", snake_case) stays excluded.

## [0.2.0] - 2026-07-28

- `is-real-and-not` and `worth-naming` move from `warning` to `info`. Both
  patterns match on surface form alone and can't tell the AI cadence from an
  unrelated sentence that happens to share it: "is real, and/but/not" fires on
  any predicate-adjective sentence regardless of what follows the conjunction
  ("my debt to my senses is real and constant" -- Emerson), and "worth naming"
  collapses the AI meta-signpost with the plain sense of a thing worth
  mentioning ("the only thing worth naming to do that" -- Emerson). Probed
  against a 1.06M-word corpus (Austen, Melville, Madison, Thoreau, Emerson);
  the other 19 rules still at `warning` were probed too and held up clean.
- `puffery-words`' bare `nestled` matched the literal verb as often as the
  puffery sense -- a head nestled against a shoulder, a kitten nestled into a
  blanket. It now requires a following in/among/between, the shape the
  travel-brochure cliché actually takes ("nestled in the hills").
- New rule `not-x-but-y` (`structure`, `info`): the bare corrective "is not A
  but B" with no escalation word, comma before "but" or none. Ships at `info`
  because the line between a corrective and an ordinary concession is
  syntactic, and a pattern can only approximate it — a concession with an
  elided subject ("was not perfect but got us there") still gets through.
- New rule `no-x-no-y-frag` (`rhetorical-tic`, `info`): the "no X, no Y"
  cadence built from sentence fragments ("No fluff. No filler.") rather than
  commas. `info`, not `warning`, because two short "no" sentences in a row is
  also just writing.
- `not-just-x-but-y` now also catches "not because A, but because B" and the
  escalation words `merely`, `simply`, and `solely` alongside `just`/`only`.
  It keeps `warning`: the escalation word is a deliberate authorial move.
- Both `not-…-but-…` rules now stop at a paragraph break, so an unpunctuated
  heading or list item no longer joins up with the next paragraph's "But …".
- `no-x-no-y-frag` links must begin a sentence, so an ordinary sentence can no
  longer donate its tail to a chain ("There was no bread. No milk either." is
  one sentence and one fragment, not a chain), and the link separator is
  capped at two spaces so a code span blanked by `--markdown` cannot weld two
  distant fragments together.
- `sloplint explain` no longer breaks its aligned fixture block when a fixture
  contains a newline; those are escaped as `\n`.
- Notes carry a new `context` field: the match bracketed inside ~40 characters
  of surrounding prose. Human output shows it in place of the bare match, which
  told you nothing when the match was a single word or a lone em dash. `excerpt`
  is unchanged and still the bare match.
- New rule `em-dash` (`structure`, `info`): flags every em dash, not just
  paragraphs dense with them.
- `em-dash-overuse` (3+ em dashes in one paragraph) is now `warning`, up from
  `info`.

## [0.1.0] - 2026-07-24

First public release.

- 24-rule catalog across four categories: rhetorical-tic, puffery, structure,
  hedging. See `sloplint rules` or `README.md` for the full list.
- `check`, `rules`, `explain`, `version` commands; JSON and human-readable
  output; `--select`/`--ignore` by rule id or category; `--markdown` to skip
  fenced code, inline code, and URLs before scanning.
- Exit codes: `0` clean, `1` notes found, `2` bad arguments or invalid input
  (including invalid UTF-8 and unknown `--select`/`--ignore` ids).
- Zero runtime dependencies; requires Ruby >= 3.3.
- `-v`/`--version` print the version and exit 0. optparse auto-registers its
  own `--version` switch on any parser that doesn't define one, and that
  default printed "version unknown" to the real stdout and hard-exited,
  bypassing the `out:`/return-a-code contract every other path honors --
  caught by hand-testing the freshly built gem before this release shipped.
- Rationale text (`sloplint explain`) across six rules no longer narrates the
  rule's own implementation -- pattern scoping, anchoring, tuning history,
  corpus-driven thresholds. It states why the construct reads as AI writing
  and nothing else.

Rules narrowed against a corpus of real human prose (the Federalist Papers,
Moby-Dick, Walden) before release:

- `not-just-x-but-y` anchored on a preceding copula so it no longer flags
  ordinary correlative conjunctions ("not only... but...").
- `puffery-words` dropped the bare adjective "profound" and narrowed "in the
  heart of" to require a place object, both unguarded false-positive sources.
- `em-dash-overuse`, `thats-how-x`, and `announced-takeaway` scoped to real
  paragraphs (blank-line boundaries) instead of source lines, so hit counts
  no longer swing on Markdown line-wrapping.
- `clause-triad-then` removed: went 0-for-40 on its own description against
  the human corpus, and no reliable narrowing was found.
- `no-x-no-y`'s rationale corrected to match what the pattern actually does
  (fires at two items; the frequency gap between human and model prose is
  the justification, not an item-count claim the pattern didn't enforce).
