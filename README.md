# sloplint

A dependency-free CLI that scans prose for the tells of AI-generated **slop** and reports them as notes. Think `proselint`, but aimed narrowly at the tics and puffery that mark LLM writing: the `no X, no Y` chains, the `rich tapestry of`, the `some critics argue` hedging. It writes JSON an agent can act on and text a person can read.

The primary reader is an agent (Claude Code and friends) that runs sloplint, reads the JSON, and rewrites what it flags. A human is the secondary reader, and I keep the false-positive rate low enough that a note is worth trusting.

## Quick start

The one recipe to learn, and the one an agent should use:

```bash
cat draft.md | sloplint check --markdown -o json -
```

`--markdown` blanks out code, HTML comments, and URLs first, `-o json` gives the JSON output, and `-` reads stdin.

Exit 0 means clean, 1 means notes found, anything higher is an error. `check` is the default command, so `sloplint draft.md`, `sloplint -`, and a bare `sloplint` with piped stdin all scan.

One flag more, `--judge`, adds a second catalog of rules that ask a model what no pattern can match. [The judge](#the-judge-the-tells-a-regex-cannot-reach) sets that up, and it is the only part of sloplint that sends your text anywhere.

The human output drops `-o json`:

```
$ printf 'The report is a rich tapestry of vibrant detail.\nThat is exactly the point I keep making about it.\n' | sloplint check -
-:1:17: error rich-tapestry  "rich tapestry"/"tapestry of" is a signature AI cliché.
    excerpt: The report is a [rich tapestry] of vibrant detail. That is exactly the…
    why: 'tapestry of' is one of the most reliable single-phrase model tells.
    fix: Cut the metaphor; name the actual things.

-:1:34: error puffery-words  Wikipedia-style puffery word/phrase — a common AI tell.
    excerpt: The report is a rich tapestry of [vibrant] detail. That is exactly the point I…
    why: Travel-brochure adjectives and phrases that models reach for and careful writers avoid.
    fix: Replace with a concrete, specific detail or cut it.

-:2:1: info exact-exactly  "exact/exactly" is reflexive emphasis unless it names something checkable.
    excerpt: …is a rich tapestry of vibrant detail. [That is exactly] the point I keep making about it.
    why: Models reach for 'exact/exactly' as filler emphasis on a claim with nothing to check; it earns its place only next to a number, a name, or a stated identity.
    fix: Cut it, or replace with the number, name, or match it's supposed to be precise about.
```

The brackets mark the match; the rest lets you see what you're fixing without opening the file, *why* included, so an agent has the rationale without a second command.

## Installation

Requires **Ruby 3.3+** and nothing else: it runs on the standard library alone (`optparse`, `json`, native regex). The Ruby that macOS ships at `/usr/bin/ruby` is 2.6 and too old; `brew install ruby` gets you a current one.

### In Claude Cowork or the Claude desktop app

Open **Customize → Plugins → Add marketplace** and paste exactly this:

```
benjaminjackson/sloplint
```

Then install **sloplint** from the list.

Paste those two words and nothing else: no `https://` on the front, no slash on the end. The full URL `https://github.com/benjaminjackson/sloplint` works too, but a URL copied from a page you were browsing usually carries a `/tree/main` or a tracking parameter on the end, and anything after the repository name fails.

This way needs no package manager at all, which is why it works in Cowork, where `gem install` cannot reach the internet. The plugin carries its own source and runs it in place.

New rules reach you when you click **Update** on the marketplace; nothing updates on its own.

Now ask Claude to check a draft, or run `/sloplint:check`.

### In Claude Code

```
/plugin marketplace add benjaminjackson/sloplint
/plugin install sloplint@sloplint
```

### In a terminal

```bash
gem install sloplint              # the regex rules, offline and free
gem install sloplint-judge        # optional, the judge rules behind --judge
```

Or build from source:

```bash
git clone https://github.com/benjaminjackson/sloplint
cd sloplint
gem build sloplint.gemspec
gem install ./sloplint-*.gem
```

Either way you get a `sloplint` executable on your path.

### In a Ruby project

```ruby
gem "sloplint"
gem "sloplint-judge"   # optional, the judge rules
```

That gives you `bundle exec sloplint check ...` and a library. The engine is a plain method over a string, so one call scans what a model wrote before it reaches a user:

```ruby
require "sloplint"

notes = Sloplint::Engine.scan(draft, markdown: true)
notes.map(&:to_h)   # the same hashes -o json prints
```

`Sloplint::Judge::Engine.scan(draft, markdown: true)` runs the judge rules. In a request path they cost what the regex rules do not: a network call to TypeSafe, a second or two per document, and money per run. The regex rules cost none of that, so reach for them inline and keep the judge rules for a background job, a review step or a test. If all you want is the command, `require: false` in a `:development` group keeps both out of the app.

## What it catches, and what it doesn't

A pattern earns a place in the catalog only if it shows up constantly in AI writing and rarely in careful human writing. Passive voice, weak adverbs, wordiness, clichés a person reaches for too: they belong in `proselint` or `write-good`, not here. sloplint hunts the tells of a language model, so an agent can act on a note instead of second-guessing it.

## Commands

```
sloplint [-o full|json] [command] [args]

check        scan paths (or stdin) for AI-slop tells and report notes [default]
             anything that is not a command name is taken as a path: `sloplint draft.md`
rules        list the rule catalog (add --json for the machine-readable form)
explain ID   print one rule's message, rationale, and a bad/ok example
version      print the sloplint version
```

`check` takes paths; `-`, or nothing, reads stdin. The options:

- `--markdown` replaces fenced code, inline code, HTML comments, and URLs with same-length whitespace before scanning, so line and column stay correct. Without it, sloplint treats the file as prose and flags text inside your code fences. Off by default, so it never silently eats prose.
- `--select IDS` runs only these rules. Comma-separated rule ids or category names.
- `--ignore IDS` skips these rules. Same id-or-category form.
- `--strict` runs every rule, including the low-confidence ones that are off by default. `--ignore` still applies.
- `--judge` also runs the judge rules, which need the `sloplint-judge` gem and a key: see [The judge](#the-judge-the-tells-a-regex-cannot-reach).

An agent calls `explain` to decide whether a note is worth acting on:

```
$ sloplint explain no-x-no-y
no-x-no-y  (cadence, warning, high confidence)

"No X, no Y" chain (%{count} items) reads as AI cadence.

Why: Asyndetic negation chains are a signature model cadence, near-absent from human prose at any length. A careful writer occasionally stacks two (and, rarely, more), but a model reaches for the pattern constantly.
Fix: Cut the chain or make it one plain sentence.

Flags:    No fluff, no filler, no jargon.
Does not: No parking on Sundays.
```

## The judge: the tells a regex cannot reach

Everything above is sloplint's 83 **regex rules**: patterns matched against the text, offline, in milliseconds, for nothing. Some tells have no pattern to match. A paragraph that names nothing a reader could check, a sentence that tells its reader what they already know: catching those takes something that can read.

That is the judge, a second catalog of 14 **judge rules** which are questions put to a model rather than patterns. It ships as a companion gem, it turns on with `--judge`, and it needs an API key. Both catalogs write the same notes into the same JSON, so whatever already reads sloplint's output reads the judge's without a change.

### Install it and get a key

`gem install sloplint-judge` adds the rules; they need a key for TypeSafe's API, which the regex rules never do. Jev, the model the judge asks, is in early access behind a waitlist: sign up at [typesafe.ai](https://typesafe.ai), and once you are through, issue a key at [console.typesafe.ai](https://console.typesafe.ai/settings/keys). TypeSafe meters input tokens only, $42 per billion, so a 2,000-word document costs well under a cent.

Put the key in one of two places. The keychain, which `key set` writes and the judge reads by default:

```bash
sloplint-judge key set     # the keychain tool prompts, with echo off
```

Or the environment, which beats the keychain:

```bash
export TYPESAFE_API_KEY=...
```

The keychain is for a workstation. On a server, use the environment, or whatever secret manager fills the environment.

`sloplint-judge status` says whether it found a key and where, without printing it, and `key unset` removes the keychain item. [docs/JUDGE.md](docs/JUDGE.md#where-the-key-lives) has the rest, including what the keychain protects you from and what it doesn't.

A key makes the judge possible; it does not make the judge run. In Claude Code and Cowork the plugin ships with the judge, and the `/sloplint:check` skill asks once per conversation before it runs the judge. It names what leaves the machine and what the run costs, and it stays offline without a yes. On the command line, `--judge` is consent.

### Turn it on

One flag adds the judge rules to the same run:

```bash
cat draft.md | sloplint check --judge --markdown -o json -
```

The notes merge into one array in document order, so nothing downstream has to know which catalog found what. Because the judge costs money, the run says how much: the notes move under a `notes` key and a `judge` key carries the backend, the request count, tokens and dollars. The same figures go to stderr in the human output.

```json
{
  "notes": [ ... ],
  "judge": { "backend": "jev-latest", "requests": 9, "input_tokens": 14200, "output_tokens": 610, "cost_usd": 0.000596 }
}
```

`--judge` is the only flag that sends your text off the machine. Installing the judge gem does not opt you in; without the flag, nothing leaves.

### Options, failures, and the second executable

`--judge` adds one option of its own:

- `--register TEXT` says who the reader is. The default reader is an engineer on the team reading a design document, and the judge asks every question on that reader's behalf, so a rule like `no-news` flags a sentence *that* reader already knows rather than one anybody would know.

`--strict` does more under `--judge`: on top of the regex rules that are off by default, it runs the judge rules that are off by default, asks the sentence questions of every sentence rather than only the flagged paragraphs, and keeps answers the model was unsure of.

Without the gem, `--judge` exits 2 and names the install command. Without a key, it exits 2 and names the variable to set. If the model cannot be reached, or answers in a shape the judge does not understand, it exits 3 and writes nothing, not even the regex notes, so a partial run can never pass as a clean one.

The judge gem also puts a `sloplint-judge` executable on your path, for running the judge rules alone, managing the key, and comparing two passages:

```
sloplint-judge [-o full|json] [--register TEXT] [--backend NAME] [command] [args]

check         scan paths (or stdin) with the judge's rules only [default]
compare A B   which of two passages a plain-prose editor keeps (--drift for rewrites)
rules         list the judge's rule catalog (add --json)
explain ID    print one rule's question, levels, rationale and fixtures
status        say whether a run could happen here, and where the key is, without reading it
key set       store the backend's key in the OS keychain (the keychain tool prompts for it)
key unset     remove it from the OS keychain
version       print the sloplint-judge version
```

The backend, the model name, the endpoint and the concurrency all come from the environment. [docs/JUDGE.md](docs/JUDGE.md) has the table of variables, the design, the calibration that decides which rules ship, and how to add a backend.

## The note

One match is one note. JSON output is an array of notes, or an object keyed by path when you scan more than one file. Under `--judge` it moves beneath a `notes` key, beside a `judge` key with the backend name, request count and token counts (see [`--judge`](#--judge)). The schema is the contract:

```json
{
  "path": "draft.md",
  "line": 12,
  "column": 5,
  "severity": "warning",
  "confidence": "high",
  "rule": "no-x-no-y",
  "category": "cadence",
  "message": "\"No X, no Y\" chain (3 items) reads as AI cadence.",
  "excerpt": "No fluff, no filler, no jargon",
  "context": "The report was blunt. [No fluff, no filler, no jargon]. Nothing held back at all.",
  "count": 3,
  "rationale": "Asyndetic negation chains are a signature model cadence, near-absent from human prose at any length. A careful writer occasionally stacks two (and, rarely, more), but a model reaches for the pattern constantly.",
  "suggestion": "Cut the chain or make it one plain sentence."
}
```

`severity` and `confidence` are the two ratings [the catalog](#the-rule-catalog) explains. `line` and `column` are 1-indexed and point at the start of the match. `excerpt` is the bare match; `context` is the same match bracketed inside about 40 characters of surrounding prose, useful when the match is a single word or a lone em dash. A match already 40 characters long carries its own context, so `context` returns it alone. `count` appears only when the rule tallies items (a `no X, no Y` chain, a `did not, did not` chain). `rationale` is why the pattern is a tell, the same text `sloplint explain` prints. `suggestion` is a one-line fix.

## Exit codes

The exit code is the contract. A crash exits nonzero outside these four.

| code | meaning |
|------|---------|
| 0    | ran, no notes |
| 1    | ran, notes found |
| 2    | bad arguments or usage error |
| 3    | `--judge` only: the model could not be reached, no notes written |

An unknown id or category in `--select`/`--ignore` is a usage error (exit 2, naming the id) rather than a silent no-op, so a typo can't masquerade as a clean scan. Empty or whitespace-only input is exit 2 for the same reason: a pipe that delivered nothing must not read as a clean draft. That applies only when every source is empty; one empty file among several is deliberate, and sloplint scans the rest.

## The rule catalog

The [judge rules](#the-judge-rules) follow these.

83 rules across nine categories, each named for the rhetorical move the construct makes. `sloplint rules` prints them; `sloplint rules --json` gives an agent the enumerable form.

- **self-rating** (16) the writer grades their own prose or claim: `clean-x`, `clean-count`, `cleanest-x`, `cleanly`, `honest-x`, `most-honest-x`, `honestly` (the honesty family, built the same way as the four `clean` rules), `worth-naming`, `worth-saying-plainly`, `earns-its-place`, `does-a-lot-of-work`, `exact-exactly`, `genuinely` (off by default), `the-punchline-is`, `announced-takeaway`, `cataphoric-teaser` (`Here's what nobody tells you`, `the part most people get wrong`).
- **closer** (12) closes by restating or announcing the point: `thats-the-whole`, `is-the-whole-x` (the same closer on any subject: `Consistency is the real test.`, at `medium` confidence), `is-the-entire`, `the-entire-is`, `thats-how-x`, `thats-the-tension`, `right-up-until`, `and-nothing-else` (the trailing `…, and nothing else`), `nothing-else-frag`, `bare-equative` (`The lesson is the handoff.`, at `medium` confidence), `trailing-restatement` (the `…, which means …` tail that says the sentence again, off by default), `and-what-it-should` (the elliptical tail: `…, and what it should.`).
- **cadence** (19) rhythm: repetition, parallelism, and the long-then-short kicker: `no-x-no-y`, `no-x-no-y-frag`, `did-not-x-did-not-y`, `one-x-one-y` (`one reviewer, one queue, one deadline`), `from-x-to-y-chain` (`from guessing to measuring, from hoping to knowing`), `same-determiner-chain` (any other repeated determiner, at `medium` confidence), `real-x-real-y`, `epistrophe` (off by default), `phrase-echo` (off by default), `is-is` (doubled copula), `the-x-is-the-x` (`the problem with A is the problem with B`), `the-x-is-not-the-x` (any noun split in two by a negated copula: `the job you applied for is not the job you will do`, at `medium` confidence), `rule-of-three` (off by default), `everyone-nobody` (the comma-spliced antithesis: `Everyone wants the dashboard, nobody maintains it.`), `short-run` (three sentences of thirty characters or fewer in a row, at `medium` confidence), `mic-drop-closer` (the short quantifier-led sentence that ends a paragraph after a long one, at `medium` confidence), `bare-auxiliary-closer` (the same shape, but the closer's verb is elided down to a bare auxiliary: `The agent did.`, at `medium` confidence), `np-fragment-and` (the verbless `A named owner and a quarterly review.`, at `medium` confidence), `punch-sentence` (the verbless beat of three words or fewer between two long sentences, `Not anymore.`, at `medium` confidence).
- **puffery** (8) inflates the subject: `puffery-words` (`vibrant`, `nestled`, `groundbreaking`, `in the heart of`), `rich-tapestry`, `vital-role`, `stands-serves-as`, `underscores-highlights`, `impact-noun-vague` (`a significant impact`, `make an impact`), `trailing-significance-participle` (the `…, showcasing its importance` clause), `abstract-lives-in` (`the value sits in the follow-up`, at `medium` confidence).
- **false-correction** (8) corrects a reading nobody offered: `not-just-x-but-y`, `not-x-but-y` (the bare corrective), `not-by-x-but-by-y` (`not by luck, but by design`), `isnt-x-its-y` (the same corrective split across two clauses: `It isn't the tool. It's the habit.`), `question-isnt` (the corrective frame in interrogative dress), `less-about-more-about`, `actually-not-x`, `dont-verb-it`.
- **false-concession** (7) performs balance or candour and gives nothing up: `two-things-true`, `none-of-this-is-to-say`, `is-real-and-not`, `not-nothing`, `vague-attribution` (`some critics argue`, `it is widely regarded`), `if-im-being-honest` (the candor preamble, from slopwash.com's `false intimacy`), `and-thats-fine`.
- **reader-address** (6) instructs or flatters the reader: `you-already-know`, `sit-with-that`, `hold-onto-that`, `notice-what`, `notice-what-there`, `quip-question` (the verbless `No invite?`, at `medium` confidence).
- **borrowed-metaphor** (5) an engineering term applied to an argument: `load-bearing`, `failure-mode-here`, `intersection-of`, `impact-verb` (`the outage impacted four thousand accounts`), `impact-noun-bare` (`the impact of X`, at `medium` confidence because research prose uses it straight).
- **punctuation** (2) the mark itself: `em-dash` (any em dash), `em-dash-overuse` (three or more in one paragraph).

Every rule carries two ratings. **Severity** is what the tell costs the prose: `error` when the sentence is worse for it in any register (`rich-tapestry`, `puffery-words`, `vague-attribution`), `warning` when it dates the draft as model output but the sentence still says something, `info` when it is harmless but worth knowing about (`em-dash`). **Confidence** is how likely the match is a true hit: `high` when the pattern almost never misfires, `medium` when ordinary prose produces the same shape often enough that an agent should read the rationale before acting, `low` when the pattern cannot separate the tell from ordinary use.

The two move independently: `rich-tapestry`, `thats-the-whole` and `cleanest-x` are `error` wherever they appear, whatever my confidence in the match.

Some tells come in a confident form and an ambiguous one, and those ship as a pair rather than as one rule stretched over both. `no-x-no-y` wants the comma chain a writer clearly wrote; `no-x-no-y-frag` takes the same cadence built from sentence fragments, which ordinary prose also produces, so it ships at `medium` confidence. Same with `not-just-x-but-y` and `not-x-but-y`, and with `notice-what-there` and `notice-what`. The quiet half still deserves a note, since an agent that reads the rationale can judge for itself, but it should not carry the same weight as the half I'm sure about. `and-nothing-else` and `nothing-else-frag` are also a pair, and both sit at `high`. The fragment half carries a capital letter and a whole-sentence requirement which the comma half lacks, so it is the narrower of the two rather than the quieter one.

The `low` rules are **off by default**, because each one matches a shape ordinary prose produces on its own:

- `rule-of-three` flags a comma series of single words closing a sentence, which writers of every kind produce constantly. The narrowing is that the last two items must be single words, so three phrases do not match, but a series of three words is still often an ordinary list, and no regex sees the difference.
- `genuinely` flags every occurrence of the word. As an intensifier it rates the writer's sincerity, but it still does real work when it draws a contrast, and nothing in the sentence separates the two.
- `epistrophe` flags two clauses ending on the same phrase: a named figure careful writers use on purpose, and one ordinary prose produces by reusing a phrase.
- `trailing-restatement` flags the "…, which means …" tail and the participles that hang a result off the sentence ("…, making it easier"). The connective is visible and the restatement is not, so a real consequence trips it too.
- `phrase-echo` flags a three-word phrase that comes back within a few hundred words. A term of art comes back because it must, and the pattern cannot tell one from a phrase the writer coined.

They run when you name them (`sloplint check --select rule-of-three -`), or when you pass `--strict`. Naming a category in `--select` turns on that category's other rules only; naming a rule's id runs it regardless. `--strict` on its own runs the whole catalog, but alongside `--select` it only widens the named categories to include their low-confidence rules. `sloplint rules --json` lists every rule's `severity`, `confidence` and `rationale`, so an agent can tell which rules are off by default without reading this file.

### The judge rules

Fourteen rules in two categories. They run only under `--judge`, because each one costs a request to a model; `sloplint-judge rules` lists them and `sloplint-judge explain ID` prints the question it asks the model, the answer that flags, and the fixtures. The bar differs from the regex catalog's: a judge rule ships when a reader, shown the flagged unit, agrees it should go, whoever wrote it. Severity comes from how sharply the rule separates model prose from human prose. So `throat-clearing` is `info`, not gone: human abstracts open by announcing the paper, and the announcement is dead weight either way.

- **paragraph** (6): `particulars`, names nothing a reader could check; `wrap-up`, ends on a summary, a moral or a hope; `throat-clearing`, opens by announcing its topic; `self-narration`, signposts the document instead of advancing it; `promotional`, praises its subject and measures nothing; `same-weight`, states its guesses as flatly as its measurements.
- **sentence** (8): `stock-figure`, a stock figure of speech; `no-news`, explains what the reader you declared already knows; `names-nothing`, carries no specific noun; `ends-on-verdict`, ends by grading the fact it just stated; `trailing-gloss`, ends on an -ing clause drawing its own moral; `unnamed-authority`, hands a claim to experts, studies or "many people"; `stated-stakes`, says something matters without saying why; `matched-shape`, a pair or triple built to a rhythm rather than to content.

`same-weight`, `stated-stakes` and `matched-shape` are off by default; name them in `--select` or pass `--strict`.

Each note's `confidence` is the lower of two numbers: the rule's ceiling, and the model's confidence in that answer. The judge drops a note the model was unsure of unless you pass `--strict`, the same way sloplint drops its low-confidence rules.

## Adding a rule

Rules are data, not code. Each is a `Rule.new` entry in `lib/sloplint/rules.rb`:

```ruby
Rule.new(
  id:           "rule-id",
  category:     "cadence",                     # one of the nine in the catalog above
  severity:     "warning",                     # what it costs the prose: error, warning, info
  confidence:   "high",                        # false-positive risk: high, medium, low
  pattern:      /.../i,
  message:      "What the reader sees. %{count} interpolates the tally.",
  suggestion:   "One short fix hint.",
  count_group:  /.../i,                        # optional: a regex tallied over the match
  skip:         [/.../i],                      # optional: drop the note if these match
  examples_bad: ["A sentence the rule must flag."],
  examples_ok:  ["A sentence it must leave alone."],
  rationale:    "Why this is a tell, and what it costs when it's wrong."
)
```

Write the `rationale` for the agent. `sloplint explain` prints it, and an agent reads it to decide whether a note is worth acting on, so say what the pattern catches and where it's weak.

Adding a rule is one entry plus its fixtures. `rules_spec.rb` runs every rule against its fixtures: each `examples_bad` must produce a note, each `examples_ok` none. A rule without fixtures, or one whose regex is too greedy, fails the suite.

## Development

There is no `Gemfile`; install `rspec` and `rake` yourself (`gem install rspec rake`), then:

```bash
rake spec        # or: rspec
```

`cli_spec.rb` covers exit codes, stdin, JSON schema, `--select` and `--ignore`. It also checks that `--markdown` skips code. A slop fixture in `spec/fixtures/` doubles as an integration check.

See [`docs/SPEC.md`](docs/SPEC.md) for the design, including why sloplint is a fresh tool rather than a proselint extension.

## Author

Benjamin Jackson ([@benjaminjackson](https://github.com/benjaminjackson))

## License

MIT
