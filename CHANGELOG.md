# Changelog

All notable changes to this project are documented here. Format loosely
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
