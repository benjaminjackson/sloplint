# sloplint

A dependency-free CLI that scans prose for the tells of AI-generated **slop** and reports them as linting notes. Think `proselint`, but aimed narrowly at the rhetorical tics and puffery that mark LLM writing: the "no X, no Y" chains, the "rich tapestry of," the "some critics argue" hedging. It writes JSON an agent can act on and human text a person can read.

The primary reader is an agent (Claude Code and friends) that runs sloplint, reads the JSON, and rewrites what it flags. Humans are the secondary reader, and everything is built to keep the false-positive rate low enough that a flag is worth trusting.

The catalog comes in two halves. Most of it is regexes, which run offline in milliseconds and cost nothing. The rest are the tells no regex can reach (a paragraph that names nothing checkable, a sentence that tells its reader what they already know), and those are questions put to a model, one flag away: `sloplint check --judge`. They live in a companion gem, `sloplint-judge`, and they need an API key. Either half writes the same notes into the same JSON. [docs/JUDGE.md](docs/JUDGE.md) is the judge's own manual.

## What it catches, and what it doesn't

A pattern earns a place in the catalog only if it shows up constantly in AI writing and rarely in careful human writing. Passive voice, weak adverbs, wordiness, clichés a person reaches for too: those belong in `proselint` or `write-good`, not here. sloplint is not a general prose linter and never tries to be. It hunts the specific fingerprints of a language model, so an agent can act on a flag instead of second-guessing it.

## Installation

Requires **Ruby 3.3+** and nothing else. The runtime is standard library only (`optparse`, `json`, native regex). The Ruby that macOS ships at `/usr/bin/ruby` is 2.6 and too old; `brew install ruby` gets you a current one.

### In Claude Cowork or the Claude desktop app

Open **Customize → Plugins → Add marketplace** and paste exactly this:

```
benjaminjackson/sloplint
```

Not the web address of the page you are reading — just those two words with the slash, and no slash on the end. `https://github.com/benjaminjackson/sloplint` works too, but a link copied from a page you were browsing usually has more on the end of it and will fail. Then install **sloplint** from the list.

Installing this way needs no package install of any kind, which is why it works in Cowork, where `gem install` cannot reach the internet. Claude Code carries the source along with the plugin and runs it in place.

New rules reach you when you click **Update** on the marketplace. Nothing updates on its own.

Once it is installed, ask Claude to check a draft, or run `/sloplint:check`.

### In Claude Code

```
/plugin marketplace add benjaminjackson/sloplint
/plugin install sloplint@sloplint
```

### In a terminal

```bash
gem install sloplint              # the regex catalog, offline and free
gem install sloplint-judge        # optional, adds the model rules behind --judge
```

Or build from source:

```bash
git clone https://github.com/benjaminjackson/sloplint
cd sloplint
gem build sloplint.gemspec
gem install ./sloplint-*.gem
```

Either way, that puts a `sloplint` executable on your path.

### In a Ruby project

```ruby
gem "sloplint"
gem "sloplint-judge"   # optional, adds the model rules
```

That gives you `bundle exec sloplint check ...` and a library. The engine is a plain method over a string, so scanning what a model wrote before it reaches a user is one call:

```ruby
require "sloplint"

notes = Sloplint::Engine.scan(draft, markdown: true)
notes.map(&:to_h)   # the same hashes -o json prints
```

`Sloplint::Judge::Engine.scan(draft, markdown: true)` is the judge's half, and it is a different proposition in a request path: it is a network call to TypeSafe, it takes a second or two per document, and it costs money per run. The regex half is neither, so it is the one to reach for inline; put the judge in a background job, a review step or a test. If all you want is the command, `require: false` in a `:development` group keeps both out of the app.

### The judge's key

The model rules need a key for TypeSafe's API, and the regex rules never do. Jev is in early access behind a waitlist: sign up at [typesafe.ai](https://typesafe.ai), and once you are through, issue a key at [console.typesafe.ai](https://console.typesafe.ai/settings/keys). It is metered on input tokens only, $42 per billion, so a 2,000-word document costs well under a cent.

Then put the key in one of two places. The keychain, which is what `key set` writes and what the judge reads by default:

```bash
sloplint-judge key set     # the keychain tool prompts, with echo off
```

Or the environment, which takes precedence over the keychain:

```bash
export TYPESAFE_API_KEY=...
```

The keychain is for a workstation. On a server it is the environment, or whatever secret manager fills it.

`sloplint-judge status` says whether a key was found and where, without printing it, and `key unset` removes the keychain item. [docs/JUDGE.md](docs/JUDGE.md#where-the-key-lives) has the rest, including what the keychain does and does not protect you from.

A key makes the judge possible; it does not make it run. In Claude Code and Cowork the plugin already carries the judge, and the `/sloplint:check` skill asks once per conversation before using it, naming what leaves the machine and what it costs. It stays offline without a yes. On the command line, typing `--judge` is the consent.

## Quick start

The recipe sloplint is built around, and the one an agent should use:

```bash
cat draft.md | sloplint check --markdown -o json -
```

`--markdown` blanks out code, HTML comments, and URLs first, `-o json` emits the machine-readable form, and `-` reads stdin. Exit 0 means clean, 1 means notes found, anything higher is an error. `check` is the default command, so `sloplint draft.md`, `sloplint -`, and a bare `sloplint` with piped stdin all scan.

With the gem and a key in place ([above](#the-judges-key)), one flag adds the model rules to the same run:

```bash
cat draft.md | sloplint check --judge --markdown -o json -
```

The notes merge into one array in document order, so nothing downstream has to know which half found what. Because the judge spent money, the run says how much: the notes move under a `notes` key and a `judge` key carries the backend, the request count, the tokens and the dollars. The same figures go to stderr in the human formats.

```json
{
  "notes": [ ... ],
  "judge": { "backend": "jev-latest", "requests": 9, "input_tokens": 14200, "output_tokens": 610, "cost_usd": 0.000596 }
}
```

`--judge` is also the one thing here that sends your text anywhere. Without it, sloplint never leaves the machine, whether or not the judge gem is installed.

The human-readable form drops `-o json`:

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

The brackets mark the match; the rest is there so you can see what you're fixing without opening the file — including *why*, so an agent doesn't have to run `explain` separately to decide whether a flag is worth acting on.

## Commands

```
sloplint [-o full|json] [command] [args]

check        scan paths (or stdin) for AI-slop tells and report notes [default]
             anything that is not a command name is taken as a path: `sloplint draft.md`
rules        list the rule catalog (add --json for the machine-readable form)
explain ID   print one rule's message, rationale, and a bad/ok example
version      print the sloplint version
```

`check` takes files as arguments, or `-` (or nothing) to read stdin, and these options:

- `--markdown` skips fenced code, inline code, HTML comments, and URLs before scanning. Off by default so it never silently eats prose.
- `--select IDS` runs only these rules. Accepts comma-separated rule ids or category names.
- `--ignore IDS` skips these rules. Same id-or-category form.
- `--strict` runs every rule, including the five that are off by default. `--ignore` still applies on top.

`explain` is the command an agent calls to decide whether a flag is worth acting on:

```
$ sloplint explain no-x-no-y
no-x-no-y  (cadence, warning, high confidence)

"No X, no Y" chain (%{count} items) reads as AI cadence.

Why: Asyndetic negation chains are a signature model cadence, near-absent from human prose at any length. A careful writer occasionally stacks two (and, rarely, more), but a model reaches for the pattern constantly.
Fix: Cut the chain or make it one plain sentence.

Flags:    No fluff, no filler, no jargon.
Does not: No parking on Sundays.
```

### `--judge`

`sloplint check --judge` runs the model rules alongside the regexes. It takes one more option of its own:

- `--register TEXT` says who the reader is. The default is an engineer on the team reading a design document, and every question is asked on that reader's behalf, so a rule like `no-news` flags a sentence *that* reader already knows rather than one anybody would.

`--strict` does a little more under `--judge`: on top of the regex rules that are off by default, it runs the judge's own three, asks the sentence questions of every sentence rather than only the flagged paragraphs, and keeps the answers the model was not sure about.

Without the gem, `--judge` exits 2 and names the install command. Without a key, exit 2 and the variable to set. If the model cannot be reached, or answers in a shape the judge does not understand, exit 3 and *no* notes are written, the regex ones included, so a partial run can never pass as a clean one.

The judge gem also puts a `sloplint-judge` executable on your path, for running the model rules on their own, managing the key, and `compare`, which asks which of two passages a plain-prose editor would keep:

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

The backend, the model name, the endpoint and the concurrency all come from the environment, and [docs/JUDGE.md](docs/JUDGE.md) has that table, the design, the calibration that decides which rules ship, and how to add a backend.

## The note

One match is one note. JSON output is an array of these, or an object keyed by path when more than one file is scanned. Under `--judge` that array or object sits under a `notes` key next to a `judge` key with the backend name, request count and token counts (see [`--judge`](#--judge)). The schema is the contract:

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

`severity` is what the construct costs the prose; `confidence` is how likely the match is a false positive. The two are separate, so a cheap tell we are sure about and an expensive one we are guessing at no longer collapse into the same word. `line` and `column` are 1-indexed and point at the start of the match. `excerpt` is the bare match; `context` is the same match bracketed inside about 40 characters of surrounding prose, which is what you want when the match is a single word or a lone em dash. A match already 40 characters long carries its own context, so `context` returns it alone rather than padding it further. `count` appears only when the rule tallies items (a "no X, no Y" chain, a "did not, did not" chain). `rationale` is why the pattern is a tell — the same text `sloplint explain` prints — so an agent deciding whether a flag is worth acting on doesn't have to run `explain` separately to find out. `suggestion` is a short fix hint.

## Exit codes

Four codes carry the contract. A crash exits nonzero on its own.

| code | meaning |
|------|---------|
| 0    | ran, no notes |
| 1    | ran, notes found |
| 2    | bad arguments or usage error |
| 3    | `--judge` only: the model could not be reached, no notes written |

An unknown id or category in `--select`/`--ignore` is a usage error (exit 2, naming the id) rather than a silent no-op, so a typo can't masquerade as a clean scan. Input that is empty or only whitespace is exit 2 for the same reason: a pipe that delivered nothing must not read as a clean draft. Only when every source is empty — one empty file among several named ones is taken as deliberate.

## The rule catalog

Two halves: the regexes below, and the [fourteen the model judges](#the-rules-the-model-judges) at the end of this section.

82 rules across nine categories, each named for the rhetorical move the construct makes. `sloplint rules` prints them; `sloplint rules --json` gives an agent the enumerable form.

- **self-rating** (16) the writer grades their own prose or claim: `clean-x`, `clean-count`, `cleanest-x`, `cleanly`, `honest-x`, `most-honest-x`, `honestly` (the honesty family, built the same way as the four `clean` rules), `worth-naming`, `worth-saying-plainly`, `earns-its-place`, `does-a-lot-of-work`, `exact-exactly`, `genuinely` (off by default), `the-punchline-is`, `announced-takeaway`, `cataphoric-teaser` ("Here's what nobody tells you", "the part most people get wrong").
- **closer** (12) closes by restating or announcing the point: `thats-the-whole`, `is-the-whole-x` (the same closer on any subject: "Consistency is the real test.", at `medium` confidence), `is-the-entire`, `the-entire-is`, `thats-how-x`, `thats-the-tension`, `right-up-until`, `and-nothing-else` (the trailing "…, and nothing else"), `nothing-else-frag`, `bare-equative` ("The lesson is the handoff.", at `medium` confidence), `trailing-restatement` (the "…, which means …" tail that says the sentence again, off by default), `and-what-it-should` (the elliptical tail: "…, and what it should.").
- **cadence** (18) rhythm: repetition, parallelism, and the long-then-short kicker: `no-x-no-y`, `no-x-no-y-frag`, `did-not-x-did-not-y`, `one-x-one-y` ("one reviewer, one queue, one deadline"), `from-x-to-y-chain` ("from guessing to measuring, from hoping to knowing"), `same-determiner-chain` (any other repeated determiner, at `medium` confidence), `real-x-real-y`, `epistrophe` (off by default), `phrase-echo` (off by default), `is-is` (doubled copula), `the-x-is-the-x` ("the problem with A is the problem with B"), `rule-of-three` (off by default), `everyone-nobody` (the comma-spliced antithesis: "Everyone wants the dashboard, nobody maintains it."), `short-run` (three sentences of thirty characters or fewer in a row, at `medium` confidence), `mic-drop-closer` (the short quantifier-led sentence that ends a paragraph after a long one, at `medium` confidence), `bare-auxiliary-closer` (the same shape, but the closer's verb is elided down to a bare auxiliary: "The agent did.", at `medium` confidence), `np-fragment-and` (the verbless "A named owner and a quarterly review.", at `medium` confidence), `punch-sentence` (the verbless beat of three words or fewer between two long sentences, "Not anymore.", at `medium` confidence).
- **puffery** (8) inflates the subject: `puffery-words` (vibrant, nestled, groundbreaking, in the heart of), `rich-tapestry`, `vital-role`, `stands-serves-as`, `underscores-highlights`, `impact-noun-vague` ("a significant impact", "make an impact"), `trailing-significance-participle` (the "…, showcasing its importance" clause), `abstract-lives-in` ("the value sits in the follow-up", at `medium` confidence).
- **false-correction** (8) corrects a reading nobody offered: `not-just-x-but-y`, `not-x-but-y` (the bare corrective), `not-by-x-but-by-y` ("not by luck, but by design"), `isnt-x-its-y` (the same corrective split across two clauses: "It isn't the tool. It's the habit."), `question-isnt` (the corrective frame in interrogative dress), `less-about-more-about`, `actually-not-x`, `dont-verb-it`.
- **false-concession** (7) performs balance or candour and gives nothing up: `two-things-true`, `none-of-this-is-to-say`, `is-real-and-not`, `not-nothing`, `vague-attribution` ("some critics argue", "it is widely regarded"), `if-im-being-honest` (the candor preamble, from slopwash.com's "false intimacy"), `and-thats-fine`.
- **reader-address** (6) instructs or flatters the reader: `you-already-know`, `sit-with-that`, `hold-onto-that`, `notice-what`, `notice-what-there`, `quip-question` (the verbless "No invite?", at `medium` confidence).
- **borrowed-metaphor** (5) an engineering term applied to an argument: `load-bearing`, `failure-mode-here`, `intersection-of`, `impact-verb` ("the outage impacted four thousand accounts"), `impact-noun-bare` ("the impact of X", at `medium` confidence because research prose uses it straight).
- **punctuation** (2) the mark itself: `em-dash` (any em dash), `em-dash-overuse` (three or more in one paragraph).

Every rule carries two ratings, and they answer different questions. **Severity** is what the construct costs the prose: `error` when the sentence is worse for it in any register (`rich-tapestry`, `puffery-words`, `vague-attribution`), `warning` when it dates the draft as model output but the sentence still says something, `info` when it is mostly harmless and worth knowing (`em-dash`). **Confidence** is how likely the match is a false positive: `high` when almost every hit is the real tell, `medium` when ordinary prose produces the same shape often enough that an agent should read the rationale first, `low` when the pattern cannot tell the tell from the ordinary use at all.

The two used to be one word, so a cheap tell we were sure about and an expensive one we were guessing at both came out as `warning`. They no longer do. `error` is in use: the puffery family, the tautology closers, and the self-ranking superlatives all cost the sentence something wherever they appear, however sure or unsure we are of the match.

Some tells come in a confident form and an ambiguous one, and those ship as a pair rather than as one rule stretched over both. `no-x-no-y` wants the comma chain a writer clearly authored; `no-x-no-y-frag` takes the same cadence built from sentence fragments, which ordinary prose also produces, so it ships at `medium` confidence. Same with `not-just-x-but-y` and `not-x-but-y`, and with `notice-what-there` and `notice-what`. The quiet half is still worth flagging — an agent that reads the rationale can judge — but it should not carry the same weight as the half we're sure about. `and-nothing-else` and `nothing-else-frag` are a pair of the same shape and both sit at `high`, because the fragment half carries a capital letter and a whole-sentence requirement that the comma half has no equivalent of, so it is the narrower of the two rather than the quieter one.

The five `low` rules are the ones that run **off by default**. They run when you name them — `sloplint check --select rule-of-three -` — or when you pass `--strict`, which runs the whole catalog when you give it no `--select`. `rule-of-three` flags three single words in a comma series closing a sentence, which humans do all the time; the closing two items must be single words, so a triad of phrases does not match, because a regex cannot tell one from an ordinary list. `genuinely` flags every occurrence of the word; as an intensifier it rates the writer's sincerity, but it still does real work when it draws a contrast, and nothing in the sentence separates the two. `epistrophe` flags two clauses ending on the same phrase, a named figure that careful writers use on purpose and that, on Hacker News, is mostly plain phrase reuse. `trailing-restatement` flags the "…, which means …" tail and the participles that hang a result off the sentence ("…, making it easier"); the connective is visible and the restatement is not, so a real consequence flags the same way. `phrase-echo` flags a three-word phrase that comes back within a few hundred words; a term of art comes back because it must, and the pattern cannot tell one from a phrase the writer coined. Naming a category in `--select` only turns on that category's non-low rules; naming the rule's own id runs it regardless. `--strict` on its own runs the whole catalog, but alongside `--select` it only widens the named categories to include their low-confidence members. `sloplint rules --json` lists every rule's `severity`, `confidence` and `rationale`, so an agent can tell which rules are off by default without reading this file.

### The rules the model judges

Fourteen rules in two categories. They run only under `--judge`; `sloplint-judge rules` lists them and `sloplint-judge explain ID` prints the question the model is asked, the answer that flags, and the fixtures. The bar is a little different from the regex catalog's: a judge rule ships when a reader shown the flagged unit agrees it should go, whoever wrote it, and how sharply it separates model prose from human prose sets its severity. So `throat-clearing` is `info`, not gone: human abstracts open by announcing the paper, and it is dead weight either way.

- **paragraph** (6): `particulars`, a paragraph that names nothing a reader could check; `wrap-up`, a paragraph that ends on a summary, a moral or a hope; `throat-clearing`, a paragraph that opens by announcing its topic; `self-narration`, a paragraph that signposts the document instead of saying something; `promotional`, a paragraph that praises its subject and measures nothing; `same-weight`, a paragraph that states its guesses and opinions as flatly as its measurements. `same-weight` is off by default; name it in `--select` or pass `--strict`.
- **sentence** (8): `stock-figure`, a stock figure of speech; `no-news`, a sentence that explains what the stated reader already knows; `names-nothing`, a sentence with no specific noun in it; `ends-on-verdict`, a sentence that ends by grading the fact it just stated; `trailing-gloss`, a sentence that ends on an -ing clause drawing its own moral; `unnamed-authority`, a claim handed to experts, studies or many; `stated-stakes`, a sentence that says something matters and not why; `matched-shape`, a pair or triple built to a rhythm rather than to the content. `stated-stakes` and `matched-shape` are off by default; name them in `--select` or pass `--strict`.

Each note's `confidence` is the lower of the rule's own ceiling and how sure the model was of that answer. A note the model was unsure about is dropped unless you pass `--strict`, the same way sloplint drops its low-confidence rules.

### Markdown handling

`--markdown` replaces fenced code, inline code, HTML comments, and URLs with same-length whitespace before scanning, so line and column stay correct. Without it, sloplint treats the whole file as prose and will flag text inside your code fences. Pass `--markdown` whenever the input is Markdown.

## Adding a rule

Rules are data, not code. Each is a `Data.define` object in `lib/sloplint/rules.rb` with a regex, a message, a suggestion, and one bad and one ok fixture:

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
