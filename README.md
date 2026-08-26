# sloplint

A dependency-free CLI that scans prose for the tells of AI-generated **slop** and reports them as linting notes. Think `proselint`, but aimed narrowly at the rhetorical tics and puffery that mark LLM writing: the "no X, no Y" chains, the "rich tapestry of," the "some critics argue" hedging. It writes JSON an agent can act on and human text a person can read.

The primary reader is an agent (Claude Code and friends) that runs sloplint, reads the JSON, and rewrites what it flags. Humans are the secondary reader, and everything is built to keep the false-positive rate low enough that a flag is worth trusting.

## What it catches, and what it doesn't

A pattern earns a place in the catalog only if it shows up constantly in AI writing and rarely in careful human writing. Passive voice, weak adverbs, wordiness, clichés a person reaches for too: those belong in `proselint` or `write-good`, not here. sloplint is not a general prose linter and never tries to be. It hunts the specific fingerprints of a language model, so an agent can act on a flag instead of second-guessing it.

## Installation

Requires **Ruby 3.3+** and nothing else. The runtime is standard library only (`optparse`, `json`, native regex).

```bash
gem install sloplint
```

Or build from source:

```bash
git clone https://github.com/benjaminjackson/sloplint
cd sloplint
gem build sloplint.gemspec
gem install ./sloplint-*.gem
```

Either way, that puts a `sloplint` executable on your path.

## Quick start

The recipe sloplint is built around, and the one an agent should use:

```bash
cat draft.md | sloplint check --markdown -o json -
```

`--markdown` blanks out code and URLs first, `-o json` emits the machine-readable form, and `-` reads stdin. Exit 0 means clean, 1 means notes found, anything higher is an error. A bare `sloplint` with piped stdin is the same as `sloplint check -`.

The human-readable form drops `-o json`:

```
$ printf 'The report is a rich tapestry of vibrant detail.\nThat is exactly the point I keep making about it.\n' | sloplint check -
-:1:17: warning rich-tapestry  "rich tapestry"/"tapestry of" is a signature AI cliché.
    excerpt: The report is a [rich tapestry] of vibrant detail. That is exactly the…
    why: 'tapestry of' is one of the most reliable single-phrase model tells.
    fix: Cut the metaphor; name the actual things.

-:1:34: warning puffery-words  Wikipedia-style puffery word/phrase — a common AI tell.
    excerpt: The report is a rich tapestry of [vibrant] detail. That is exactly the point I…
    why: Travel-brochure adjectives and phrases that models reach for and careful writers avoid.
    fix: Replace with a concrete, specific detail or cut it.

-:2:9: info exact-exactly  "exact/exactly" is reflexive emphasis unless it names something checkable.
    excerpt: …tapestry of vibrant detail. That is [exactly] the point I keep making about it.
    why: Models reach for 'exact/exactly' as filler emphasis on a claim with nothing to check; it earns its place only next to a number, a name, or a stated identity.
    fix: Cut it, or replace with the number, name, or match it's supposed to be precise about.
```

The brackets mark the match; the rest is there so you can see what you're fixing without opening the file — including *why*, so an agent doesn't have to run `explain` separately to decide whether a flag is worth acting on.

## Commands

```
sloplint [-o full|json] <command> [args]

check        scan paths (or stdin) for AI-slop tells and report notes [default]
rules        list the rule catalog (add --json for the machine-readable form)
explain ID   print one rule's message, rationale, and a bad/ok example
version      print the sloplint version
```

`check` takes files as arguments, or `-` (or nothing) to read stdin, and these options:

- `--markdown` skips fenced code, inline code, and URLs before scanning. Off by default so it never silently eats prose.
- `--select IDS` runs only these rules. Accepts comma-separated rule ids or category names.
- `--ignore IDS` skips these rules. Same id-or-category form.

`explain` is the command an agent calls to decide whether a flag is worth acting on:

```
$ sloplint explain no-x-no-y
no-x-no-y  (rhetorical-tic, warning)

"No X, no Y" chain (%{count} items) reads as AI cadence.

Why: Asyndetic negation chains are a signature model cadence, near-absent from human prose at any length -- 24 hits in 1.02M words across Austen, Melville, Madison, Thoreau, and Emerson combined. A careful writer occasionally stacks two (and, rarely, more), but a model reaches for the pattern constantly.
Fix: Cut the chain or make it one plain sentence.

Flags:    No fluff, no filler, no jargon.
Does not: No parking on Sundays.
```

## The note

One match is one note. JSON output is an array of these, or an object keyed by path when more than one file is scanned. The schema is the contract:

```json
{
  "path": "draft.md",
  "line": 12,
  "column": 5,
  "severity": "warning",
  "rule": "no-x-no-y",
  "category": "rhetorical-tic",
  "message": "\"No X, no Y\" chain (3 items) reads as AI cadence.",
  "excerpt": "No fluff, no filler, no jargon",
  "context": "The report was blunt. [No fluff, no filler, no jargon]. Nothing held back at all.",
  "count": 3,
  "rationale": "Asyndetic negation chains are a signature model cadence, near-absent from human prose at any length -- 24 hits in 1.02M words across Austen, Melville, Madison, Thoreau, and Emerson combined. A careful writer occasionally stacks two (and, rarely, more), but a model reaches for the pattern constantly.",
  "suggestion": "Cut the chain or make it one plain sentence."
}
```

`line` and `column` are 1-indexed and point at the start of the match. `excerpt` is the bare match; `context` is the same match bracketed inside about 40 characters of surrounding prose, which is what you want when the match is a single word or a lone em dash. A match already 40 characters long carries its own context, so `context` returns it alone rather than padding it further. `count` appears only when the rule tallies items (a "no X, no Y" chain, a "did not, did not" chain). `rationale` is why the pattern is a tell — the same text `sloplint explain` prints — so an agent deciding whether an `info` flag is worth acting on doesn't have to run `explain` separately to find out. `suggestion` is a short fix hint.

## Exit codes

Three codes carry the contract. A crash exits nonzero on its own.

| code | meaning |
|------|---------|
| 0    | ran, no notes |
| 1    | ran, notes found |
| 2    | bad arguments or usage error |

An unknown id or category in `--select`/`--ignore` is a usage error (exit 2, naming the id) rather than a silent no-op, so a typo can't masquerade as a clean scan.

## The rule catalog

42 rules across four categories. `sloplint rules` prints them; `sloplint rules --json` gives an agent the enumerable form.

- **rhetorical-tic** (31) the cadence patterns: `no-x-no-y`, `no-x-no-y-frag`, `thats-the-whole`, `thats-how-x`, `announced-takeaway`, `exact-exactly`, `load-bearing`, `you-already-know`, `sit-with-that`, `hold-onto-that`, `cleanly`, `clean-count`, `cleanest-x`, `clean-x`, `not-nothing`, `is-is` (doubled copula), and more.
- **puffery** (5) Wikipedia's "signs of AI writing": `puffery-words` (vibrant, nestled, groundbreaking, in the heart of), `rich-tapestry`, `vital-role`, `stands-serves-as`, `underscores-highlights`.
- **structure** (5) `not-just-x-but-y`, `not-x-but-y` (the bare corrective), `em-dash` (any em dash), `em-dash-overuse` (three or more in one paragraph), and `rule-of-three`.
- **hedging** (1) `vague-attribution`: "some critics argue," "it is widely regarded."

Severity is `warning` for strong tells, `info` for weak or contextual ones. No rule currently ships at `error`; the tier is reserved for a pattern with essentially zero false-positive risk, and none has earned that yet.

Some tells come in a confident form and an ambiguous one, and those ship as a pair rather than as one rule stretched over both. `no-x-no-y` wants the comma chain a writer clearly authored; `no-x-no-y-frag` takes the same cadence built from sentence fragments, which ordinary prose also produces, and ships at `info`. Same with `not-just-x-but-y` and `not-x-but-y`. The quiet half is still worth flagging — an agent that reads the rationale can judge — but it should not carry the same weight as the half we're sure about.

One rule ships **off by default**: `rule-of-three` flags three parallel comma items closing a sentence, which humans do all the time, so it false-positives. It runs only when you name it: `sloplint check --select rule-of-three -`.

### Markdown handling

`--markdown` replaces fenced code, inline code, and URLs with same-length whitespace before scanning, so line and column stay correct. Without it, sloplint treats the whole file as prose and will flag text inside your code fences. Pass `--markdown` whenever the input is Markdown.

## Adding a rule

Rules are data, not code. Each is a `Data.define` object in `lib/sloplint/rules.rb` with a regex, a message, a suggestion, and one bad and one ok fixture:

```ruby
Rule.new(
  id:           "rule-id",
  category:     "rhetorical-tic",              # or puffery, structure, hedging
  severity:     "warning",                     # or info
  pattern:      /.../i,
  message:      "What the reader sees. %{count} interpolates the tally.",
  suggestion:   "One short fix hint.",
  count_group:  /.../i,                        # optional: a regex tallied over the match
  skip:         [/.../i],                      # optional: drop the note if these match
  default_on:   false,                         # optional: runs only when named in --select
  examples_bad: ["A sentence the rule must flag."],
  examples_ok:  ["A sentence it must leave alone."],
  rationale:    "Why this is a tell, and what it costs when it's wrong."
)
```

`rationale` is not decoration. `sloplint explain` prints it, and that is what an agent reads to decide whether a flag is worth acting on — so it should say what the pattern is, how it was probed, and where it's known to be weak.

Adding a rule is one entry plus its fixtures. `rules_spec.rb` iterates the catalog and asserts every `examples_bad` produces at least one note and every `examples_ok` produces none, so a rule without fixtures, or one whose regex is too greedy, fails the suite.

## Development

No `Gemfile` -- install `rspec` and `rake` yourself (`gem install rspec rake`), then:

```bash
rake spec        # or: rspec
```

`rules_spec.rb` checks every rule against its fixtures. `cli_spec.rb` covers exit codes, stdin, JSON schema, `--select` and `--ignore`, and that `--markdown` skips code. A slop fixture in `spec/fixtures/` doubles as an integration check.

See [`docs/SPEC.md`](docs/SPEC.md) for the full design, including why this is a fresh tool rather than a proselint extension.

## Author

Benjamin Jackson ([@benjaminjackson](https://github.com/benjaminjackson))

## License

MIT
