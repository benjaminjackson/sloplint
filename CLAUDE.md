# sloplint

Rules are data, not code — `Rule.new` entries in `lib/sloplint/rules.rb`. The
engine never grows a branch for a rule; if a tell needs logic, that's a signal
the regex is wrong, not that the engine needs a feature.

## Docs mirror the catalog

`README.md` quotes the catalog size and a per-category breakdown, and
`docs/SPEC.md` lists every rule by id. Nothing regenerates either one, so
adding or removing a rule stales both. `spec/rules_spec.rb` asserts both
against `RULES` — the counts for the README, the ids for the SPEC — so update
them in the same commit. The same goes for any other doc that restates what's
in the catalog.

## New rules ship narrowed

Every rule needs `examples_bad` and `examples_ok`; the spec runs them as
fixtures. Before shipping one, probe the pattern against ordinary human prose
and find the false positives — they're always there. Then narrow the regex and
pin each narrowing with an `examples_ok` fixture, so a later tweak can't
quietly widen it back. A rule that has never been probed isn't finished.

Some tells can't be regexes. The give-away is often an absence — a claim of
experience with no incident behind it — and a pattern can't see what isn't
there. Leave those out rather than approximating them into noise.

Fixtures are ours to write. `examples_bad` are synthetic; never paste a real
sentence found in the wild, however perfect a specimen it is. `examples_ok` may
quote public-domain prose with the source named in a comment. No collected
corpus belongs in the repo, on either side. See "Provenance" in `docs/SPEC.md`.

## Probe against real prose, not just fixtures

`examples_bad` and `examples_ok` are pins, not evidence. They only ever say
that the pattern still does what you already knew it did. Before a rule ships,
run it over a body of real human writing — hundreds of thousands of words, not
a handful of sentences — and read every hit. A rule that has only met its own
fixtures has not been probed, whatever the commit message says.

Match the reading to where the tool actually gets pointed. Forum comments and
19th-century novels are both real prose and neither one is a design doc, an
incident report or reference documentation, which is the register an agent
runs this on. A probe that finds nothing may only mean the corpus could not
contain the thing: 25 Gutenberg texts said `cleanly` was safe because Victorian
novels have no builds, and the same period read as an engineering manual has
it on the first page.

Three things that keep turning up, worth checking by name:

- **Narrow on structure, not on a list.** A deictic, a locative, a possessive,
  a determiner frame, a copula — these held up against a register they had
  never seen. Noun lists and allow-lists broke, every time, and each entry
  added to fix one false positive silenced the tell sitting behind it. If a
  narrowing is a list that keeps growing, the pattern is the wrong shape:
  match the tell as a closed set of frames rather than matching a common word
  and subtracting the exceptions.
- **A document is not a stream of sentences.** Bullets, lettered and numbered
  enumerations, form-field labels, citation lines, table entries, headings and
  transcribed speech all read as prose to a regex, and a rule that counts
  sentences will count them. `Phone q. Fax r. e-mail s.` is one form row;
  `Natl. Inst. Stand. Technol.` is one citation; `o Shop was not clean.` is a
  bullet. If a rule spans a sentence boundary, make it see the furniture so it
  can refuse it.
- **Time the scan on a real document.** Fixtures are short, so a pattern that
  backtracks catastrophically passes the whole suite in milliseconds and then
  hangs on the first PDF-extracted page it meets. Anything with a repeated
  group over an alternation wants an atomic group `(?>...)` or an upper bound.
  Scan a megabyte before shipping.

None of the reading is committed — see "Provenance" in `docs/SPEC.md`. What the
commit message carries is the numbers and the register: how much was read, what
kind of writing it was, how many hits, and how many survived reading them.

## Rationale stays lean

`rationale:` tells the reader why a construct reads as AI-written. Probing is
process, not payload — the corpus size, source list, and search mechanics that
justified a pattern belong in the commit message, not the shipped text. Cite a
number only when it's doing real work for the reader (why a rule sits at
`info`, why a narrowing exists); never as backup evidence for a call that's
already obvious on its face.

Tests: `rspec`. There's no Gemfile; run it directly.
