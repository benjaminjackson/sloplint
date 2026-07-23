# sloplint

Rules are data, not code — `Rule.new` entries in `lib/sloplint/rules.rb`. The
engine never grows a branch for a rule; if a tell needs logic, that's a signal
the regex is wrong, not that the engine needs a feature.

## Docs mirror the catalog

`README.md` quotes the catalog size and a per-category breakdown, and nothing
regenerates them. Adding or removing a rule stales both. `spec/rules_spec.rb`
asserts them against `RULES`, so update the README in the same commit. The same
goes for any other doc that restates what's in the catalog.

## New rules ship narrowed

Every rule needs `examples_bad` and `examples_ok`; the spec runs them as
fixtures. Before shipping one, probe the pattern against ordinary human prose
and find the false positives — they're always there. Then narrow the regex and
pin each narrowing with an `examples_ok` fixture, so a later tweak can't
quietly widen it back. A rule that has never been probed isn't finished.

Some tells can't be regexes. The give-away is often an absence — a claim of
experience with no incident behind it — and a pattern can't see what isn't
there. Leave those out rather than approximating them into noise.

Tests: `rspec`. There's no Gemfile; run it directly.
