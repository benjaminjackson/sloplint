# Changelog

All notable changes to this project are documented here. Format loosely
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.6.0] - 2026-09-08

The catalog grows from 50 rules to 75, and sloplint ships as a Claude Code
plugin as well as a gem.

### Added

- sloplint now ships as a Claude Code plugin as well as a gem. Add the
  marketplace `benjaminjackson/sloplint` and install `sloplint`; the plugin
  carries the Ruby source with it, so nothing is installed from a package
  index and it works where `gem install` cannot reach the network — Claude
  Cowork above all. The plugin adds one skill, `/sloplint:check`, which runs
  the scanner and reports what it returns. The skill refuses to assess prose
  on its own when the scanner cannot run, because a review with no scan
  behind it reads exactly like one with a scan behind it.
- `not-by-x-but-by-y`: the corrective frame on a repeated preposition, "not
  by luck, but by design". The copula rules cannot see it because nothing
  anchors "not" but a verb or a dash, so the anchor is the preposition, which
  must repeat after "but". Ships at `info`: Thoreau and Melville write it too.

### Fixed

- `check` now reads files and stdin as UTF-8 whatever the locale says. A
  sandbox with no `LANG` set — Claude Cowork's, among others — leaves Ruby's
  default external encoding at US-ASCII, and the first em dash in a draft then
  failed the whole scan with `invalid input: invalid byte sequence in
  US-ASCII`. Prose is the only input sloplint takes, so UTF-8 is the
  assumption rather than the locale's guess. Genuinely invalid UTF-8 is still
  exit 2.

### Changed

- `thats-the-whole` now takes `value` and `fix` after "that's the whole",
  alongside `point`, `game`, `thing`, `deal` and `story`. The contracted
  closer is the one an agent writes in technical prose ("That's the whole
  value of the `info` tier", "That's the whole fix"), and `is-the-whole-x`
  sees only the uncontracted "is", so the sentence slipped both rules. The
  uncontracted "That is the whole fix." moves with it, from `info` under
  `is-the-whole-x` to `warning`. The two new nouns must end the sentence or
  the paragraph, or run into one of the words a closer trails off on, so
  `thats-the-whole` leaves "value chain", "value-add" and "fix list" alone
  however the line wraps (`is-the-whole-x` still reads the uncontracted
  "That is the whole value chain" at `info`, as it did), and a curly
  apostrophe now counts as a contraction. Both rules interpolate one `WHOLE_CLOSERS`
  fragment, so the lists cannot drift, and a spec walks every noun through
  every form the two wrappers treat differently. Neither noun appears after
  "that's the whole" in 1.55M words of public-domain prose.

- Empty or whitespace-only input
 is now exit 2 with `empty input: nothing to
  check in ...`, instead of exit 0. Reporting a scan of nothing as a clean
  scan is the same trap a mistyped rule id sets, and gets the same answer. The
  text is tested before `--markdown` blanks code and URLs, so a file holding
  only a fenced code block still exits 0; and only an all-empty set of sources
  is an error, so one empty file among several named ones is left alone.

- The executable moved from `bin/sloplint` to `exe/sloplint`. claude.ai
  rejects a plugin with a top-level `bin/` directory, which would block
  organization distribution. `gem install sloplint` is unaffected.

- `exe/sloplint` now checks `RUBY_VERSION` before loading anything and aborts
  with an explanation, rather than raising `NoMethodError` from `Data.define`.
  The Ruby macOS ships at `/usr/bin/ruby` is 2.6 and hits this.

### New rules

- `from-x-to-y-chain` (rhetorical-tic, warning) flags two or more
  comma-separated "from X to Y" spans in a row: "from guessing to measuring,
  from hoping to knowing". Each span names two poles and nothing between
  them, and stacking them sweeps across a change without describing it. Two
  human shapes are skipped: the relay, where each span starts where the last
  ended ("from the egg to the worm, from the worm to the fly"), and the
  reduplication, where a span has the same word at both ends ("from hummock
  to hummock"). Operands must open with a letter, so a list of ranges ("from
  1990 to 1995, from 1997 to 2001") is not a chain. With those out it flags once in 2.4M words of pre-2022
  Hacker News (a geographic sweep) and once in 1.25M words of public-domain
  prose (Joyce).

- `one-x-one-y` (rhetorical-tic, warning) flags three or more "one X" items
  in a comma chain that stands on its own: "One owner, one repository, one
  weekly prune." The word does no counting; it sets a rhythm. The chain must
  open a sentence or follow a colon, because after a verb ("the flat has one
  bedroom, one bathroom, one balcony") the word is counting. Items are
  letter-led, so an enumeration over numbers is out; the distributive "one
  for you, one for me, one for the pot" is skipped at any length. Nothing in
  2.4M words of pre-2022 Hacker News or 1.25M words of public-domain prose.

- `everyone-nobody` (structure, warning) flags the comma-spliced antithesis
  on quantifier subjects: "Everyone wants the dashboard, nobody maintains
  it." The
  balance is what makes the diagnosis sound settled. The comma splice is
  required (with "and" it is a sentence, with a period it is two), the two
  subjects must differ in polarity, and the second clause must close the
  sentence. Nothing in 2.4M words of pre-2022 Hacker News or 1.25M words of
  public-domain prose.

- `and-what-it-should` (rhetorical-tic, warning) flags the elliptical tail:
  "List what the assistant knows about the client, and what it should." The
  second clause borrows its verb from the first and closes on a bare modal
  or a negated auxiliary, so the sentence ends on a contrast it never
  states. The comma, the conjunction, and the full stop right after the
  modal are all required; the affirmative copula and do-verb ("and what he
  does.") are complete clauses and stay out, and so does a question.
  Nothing in 2.4M words of pre-2022 Hacker News or 1.25M words of
  public-domain prose.

- `abstract-lives-in` (rhetorical-tic, info) flags an abstraction given an
  address: "the craft that lives between the two desks", "its context lives
  in a folder nobody else can open", "the value sits in the follow-up". The
  subject list is closed and abstract, so people and dogs living and sitting
  places never match, and a capitalised subject is a proper noun. "with" is
  left out of the prepositions because "the decision sits with the board" is
  ordinary English for who is responsible, "at" because "the value sits at
  ten million" is a quantity, and "lies in" because "the problem lies in
  the assumption" is where a fault is. It ships at info because the same
  shape says where information literally is ("the knowledge lives in our
  heads"), and a sample of pre-2022 Hacker News biased toward the
  construction turns up a few of those per million words, all human. A
  draft that keeps giving ideas addresses should be read as a warning.

- `np-fragment-and` (structure, info) flags a whole sentence made of two
  noun phrases and an "and": "A named owner and a quarterly review." It is
  the fix half of a model's problem-then-fix pair with the verb left out,
  and its usual habitat is a bulleted list, so a list marker may open it.
  Each phrase is one to three words, and no auxiliary or modal may appear,
  contractions included. It ships at info because a lexical verb is
  invisible to the pattern: "A car and a truck collided." has the same
  shape and flags. That sentence is rare in the corpora (nothing in 2.4M
  words of pre-2022 Hacker News, once in 1.25M words of public-domain
  prose), but it is a sentence, so one flag is a question; a draft full of
  them should be read as a warning.

- `the-x-is-the-x` (rhetorical-tic, warning) flags the repeated-head
  equative: "the reason it holds up is the reason the other half happens",
  "the problem with the tool is the problem with the team". A backreference
  catches the same abstract head noun on both sides of the copula, so the
  sentence equates two things while naming neither. The head list holds
  only nouns that cannot name an object, since "the key to the front door
  is the key on the red fob" is an identity statement; the two heads must
  share a clause, so an earlier "the cost was low, but shipping is the
  cost" never pairs; and the second head must be followed by a preposition,
  determiner, quantifier, pronoun, plural noun or punctuation, so "the
  answer key" is not a repeat. Once in 2.4M words of pre-2022 Hacker News;
  nothing in 1.25M words of public-domain prose.

- `same-determiner-chain` (rhetorical-tic, info) is the quiet cousin of
  `one-x-one-y`: three or more comma-separated items opening on the same
  determiner or quantifier, "every file, every branch, every deploy", caught
  with a backreference. The narrative possessives (my, his, her, their, its)
  are left out, since "his fame, his position, his life" is every
  novelist's. It ships at info because the device is one humans use on
  purpose: about 8 per million words of pre-2022 Hacker News and 14 per
  million
  in public-domain prose. One is a question; several in a draft should be
  read as a warning.

- `quip-question` (structure, info) flags the verbless question that opens
  a pitch: "No invite?", "New to the tool?", "Still stuck?". It must start a
  sentence, open on one of a short list of words, and close on the question
  mark within four more words with no auxiliary or contraction, so a real
  question stays out; "Need" and "Want" are left off the list because "Need
  help?" is a question with its verb elided. Ships at info: about six per
  million words of pre-2022 Hacker News, all of them replies asking the
  same shape of a person; nothing in public-domain prose outside Joyce's
  dialogue. Several in a draft should be read as a warning.

- `is-the-whole-x` (rhetorical-tic, info) is `thats-the-whole` on any
  subject: "That periodicity is the whole tell.", "Consistency is the real
  test." It yields only the exact sentences the two older rules own
  ("that/this is the whole point/game/thing/deal/story" and "is the entire
  point/game/thing/deal/story"), so nothing is reported twice and "This is
  the real test." is not lost. An interrogative subject is out, since a
  question is not a closer; "only", "deal", "thing" and "cost" are left out
  because "is the only thing", "the real deal", "the real thing" and "the
  whole cost" are ordinary speech. Ships at info: about three per million words of
  pre-2022 Hacker News, nothing in public-domain prose. Several in a draft
  should be read as a warning.

- `bare-equative` (rhetorical-tic, info) flags a sentence that opens on an
  abstract head noun and equates it with a definite noun phrase: "The tell
  here is the periodicity.", "The lesson is the handoff." The head list is
  the one `the-x-is-the-x` uses, so "The key is the brass thing on the hook"
  is a definition and stays out; the copula (including "isn't") must be
  followed by "the" and a lowercase word, so "The problem is real", "The
  answer is a mess", "the same", "the first" and "the Slack thread" are all
  out; a list marker may open it. Ships at info: about four per million
  words of pre-2022 Hacker News, nothing in public-domain prose. Several in
  a draft should be read as a warning.

- `mic-drop-closer` (structure, info) flags the kicker: a sentence of sixty
  or more characters, then a two-to-eight-word closer that ends the
  paragraph and opens on a quantifier or deictic, "Nothing here needs a new
  login.", "Most teams end up with two." A blank line or the end of the
  text must follow the closer, so a bullet followed by another bullet is
  not one; both sentences may be hard-wrapped; and whitespace runs in the
  long sentence are capped, so a URL blanked by `--markdown` cannot make it.
  Ships at info because people end paragraphs this way too, at about 150
  per million words of pre-2022 Hacker News (a comment ends on a verdict);
  one flag means nothing. A draft where it repeats paragraph after
  paragraph is the tell, and the rationale tells the agent to read that as
  a warning.

- `short-run` (structure, info) flags three consecutive sentences of thirty
  characters or fewer, each closing on a full stop with no quotation mark:
  "Nobody used it. A named owner. Then a review." The run must start at a
  real sentence boundary, so the short tail of a hard-wrapped sentence never
  opens one; dialogue is out by the boundary, sentences with digits as data,
  initials and abbreviations as not sentence ends, consecutive bullets as a
  list, and questions and exclamations by design. Ships at info: a staccato
  run is a device people use on purpose, at about thirty per million words
  of pre-2022 Hacker News. A draft that keeps doing it is the tell, and the
  rationale tells the agent to read that as a warning.

- `epistrophe` (rhetorical-tic, info, off by default) flags two clauses
  that end on the same two-word phrase, the second closing the sentence:
  "built for one desk, and almost no job is done at one desk." Two
  backreferences catch the repeat, so the phrase may be hard-wrapped; an
  article-led phrase, a short second word, a long or punctuated second
  clause, and a clause made of blanked Markdown are all out. It is off by
  default like `rule-of-three`: the figure is one Emerson and Marcus
  Aurelius use on purpose, and on pre-2022 Hacker News most of the 42 hits
  per million words are plain phrase reuse. Select it when a draft is
  suspected of leaning on it; several then should be read as a warning.

- `intersection-of` (rhetorical-tic, warning) flags "the intersection of X and
  Y" used as positioning: a writer placed between two fields, saying nothing
  about either. "at" is not required, so "explores the intersection of art and
  technology" flags the same as "sits at the intersection of". Two guards keep
  the literal senses out. A street corner names capitalised streets ("Elm",
  "Broadway", "Highway 12"), so the word after "of" must be lowercase or an
  all-caps acronym; "AI", "UX" and "HCI" are the metaphor's usual operands and
  no street is spelled that way. Geometry and set arithmetic name their operands,
  so a literal noun ("curves", "lines", "arrays", "ranges", "roads") within two
  words of "of" drops the note.

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
