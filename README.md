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
$ echo "A rich tapestry of vibrant cultures. That's exactly the point." | sloplint check -
-:1:3: warning rich-tapestry  "rich tapestry"/"tapestry of" is a signature AI cliché.
    excerpt: rich tapestry
    fix: Cut the metaphor; name the actual things.

-:1:20: warning puffery-words  Wikipedia-style puffery word/phrase — a common AI tell.
    excerpt: vibrant
    fix: Replace with a concrete, specific detail or cut it.

-:1:38: warning exactly-the  "exactly the point/kind/problem/…" is an overused LLM emphasis tic.
    excerpt: That's exactly the point
    fix: Drop 'exactly the'; state the point without the intensifier.
```

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

Why: LLMs love asyndetic negation triplets. A careful writer rarely stacks three.
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
  "count": 3,
  "suggestion": "Cut the chain or make it one plain sentence."
}
```

`line` and `column` are 1-indexed and point at the start of the match. `count` appears only when the rule tallies items (a "no X, no Y" chain, a "did not, did not" chain). `suggestion` is a short fix hint.

## Exit codes

Three codes carry the contract. A crash exits nonzero on its own.

| code | meaning |
|------|---------|
| 0    | ran, no notes |
| 1    | ran, notes found |
| 2    | bad arguments or usage error |

An unknown id or category in `--select`/`--ignore` is a usage error (exit 2, naming the id) rather than a silent no-op, so a typo can't masquerade as a clean scan.

## The rule catalog

25 rules across four categories. `sloplint rules` prints them; `sloplint rules --json` gives an agent the enumerable form.

- **rhetorical-tic** (15) the cadence patterns: `no-x-no-y`, `thats-the-whole`, `thats-how-x`, `announced-takeaway`, `exactly-the`, `you-already-know`, `sit-with-that`, `thats-not-nothing`, and more.
- **puffery** (5) Wikipedia's "signs of AI writing": `puffery-words` (vibrant, nestled, groundbreaking, in the heart of), `rich-tapestry`, `vital-role`, `stands-serves-as`, `underscores-highlights`.
- **structure** (4) `not-just-x-but-y`, `em-dash` (any em dash), `em-dash-overuse` (three or more in one paragraph), and `rule-of-three`.
- **hedging** (1) `vague-attribution`: "some critics argue," "it is widely regarded."

Severity is `warning` for strong tells, `info` for weak or contextual ones. No rule currently ships at `error`; the tier is reserved for a pattern with essentially zero false-positive risk, and none has earned that yet.

One rule ships **off by default**: `rule-of-three` flags three parallel comma items closing a sentence, which humans do all the time, so it false-positives. It runs only when you name it: `sloplint check --select rule-of-three -`.

### Markdown handling

`--markdown` replaces fenced code, inline code, and URLs with same-length whitespace before scanning, so line and column stay correct. Without it, sloplint treats the whole file as prose and will flag text inside your code fences. Pass `--markdown` whenever the input is Markdown.

## Adding a rule

Rules are data, not code. Each is a `Data.define` object in `lib/sloplint/rules.rb` with a regex, a message, a suggestion, and one bad and one ok fixture:

```ruby
Rule.new(
  id:           "no-x-no-y",
  category:     "rhetorical-tic",
  severity:     "warning",
  pattern:      /\bno\s+[\w'-]+,\s+no\s+[\w'-]+(?:,?\s+(?:and\s+)?no\s+[\w'-]+)*/i,
  message:      '"No X, no Y" chain (%{count} items) reads as AI cadence.',
  suggestion:   "Cut the chain or make it one plain sentence.",
  count_group:  /\bno\b/i,                     # optional: a regex tallied over the match
  skip:         [/real estate/i],              # optional: drop the note if these match
  examples_bad: ["No fluff, no filler, no jargon."],
  examples_ok:  ["No parking on Sundays."],
  rationale:    "Asyndetic negation chains are a signature model cadence, rare in human prose."
)
```

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
