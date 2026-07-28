# Changelog

All notable changes to this project are documented here. Format loosely
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

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
