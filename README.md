# sloplint

A dependency-free CLI that scans prose for the tells of AI-generated **slop** and reports them as linting notes. Think `proselint`, but aimed narrowly at the rhetorical tics and puffery that mark LLM writing: the "no X, no Y" chains, the "rich tapestry of," the "some critics argue" hedging. It writes JSON an agent can act on and human text a person can read.

The primary reader is an agent (Claude Code and friends) that runs sloplint, reads the JSON, and rewrites what it flags. Humans are the secondary reader, and everything is built to keep the false-positive rate low enough that a flag is worth trusting.

For the tells a regex cannot see, there is a second gem, [sloplint-judge](#sloplint-judge), whose rules are questions put to a model and whose notes come back in the same JSON. It is optional, it needs an API key, and it is the only part of sloplint that sends your text anywhere.

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

`--markdown` blanks out code, HTML comments, and URLs first, `-o json` emits the machine-readable form, and `-` reads stdin. Exit 0 means clean, 1 means notes found, anything higher is an error. `check` is the default command, so `sloplint draft.md`, `sloplint -`, and a bare `sloplint` with piped stdin all scan.

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

`sloplint check --judge` adds the rules of [sloplint-judge](#sloplint-judge) to the run, questions put to a model rather than regexes, and merges the notes into the same array in document order. It needs the sloplint-judge gem and an API key; the section below covers both.

## The note

One match is one note. JSON output is an array of these, or an object keyed by path when more than one file is scanned. Under `--judge` that array or object sits under a `notes` key next to a `judge` key with the backend name, request count and token counts (see [sloplint-judge](#sloplint-judge)). The schema is the contract:

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

Three codes carry the contract. A crash exits nonzero on its own.

| code | meaning |
|------|---------|
| 0    | ran, no notes |
| 1    | ran, notes found |
| 2    | bad arguments or usage error |
| 3    | `--judge` only: the model could not be reached, no notes written |

An unknown id or category in `--select`/`--ignore` is a usage error (exit 2, naming the id) rather than a silent no-op, so a typo can't masquerade as a clean scan. Input that is empty or only whitespace is exit 2 for the same reason: a pipe that delivered nothing must not read as a clean draft. Only when every source is empty — one empty file among several named ones is taken as deliberate.

## sloplint-judge

A second gem in this repository, for the tells a regex cannot see. Its rules are questions put to a System One model (Jev, from TypeSafe) about one paragraph or one sentence at a time: does this paragraph end by restating itself, does this sentence tell the stated reader anything they did not know, does it name anything a reader could check. The answers come back as sloplint notes, same fields, same JSON, same exit codes, so anything that already reads sloplint's output reads the judge's without change.

One thing is different from the rest of sloplint: the judge sends your text to an API. sloplint on its own never leaves the machine. Every paragraph the judge examines goes to `api.typesafe.ai` over HTTPS, and nothing goes anywhere until you set a key, so the plain `sloplint check` stays offline whether or not the judge is installed.

### Install

```bash
gem install sloplint sloplint-judge
sloplint-judge key set        # stores your TypeSafe API key in the OS keychain; it prompts for it
```

`key set` hands your terminal to the keychain tool (`security` on macOS, `secret-tool` from libsecret on Linux), which asks for the key with echo off, so the key is never on a command line, in shell history or in a dotfile. Setting `TYPESAFE_API_KEY` in the environment works too and takes precedence. One thing the keychain does not do: it keeps the key out of the agent's environment, not out of your account, since any process running as you can read the item back. `sloplint-judge status` says whether a key was found and where, without printing it, and `sloplint-judge key unset` removes the item.

Requires Ruby 3.3+ and sloplint 0.9 or later. The judge is not a plugin of its own: the Claude Code plugin at the root of this repository already carries it, and the `/sloplint:check` skill asks before it runs the judge. A key in the environment makes the judge possible; it does not make it run. The skill puts the question once per conversation, says what leaves the machine and what it costs, and stays offline unless the answer is yes or the request already asked for the judge.

### Run

The one command to know, and the one an agent should use:

```bash
sloplint check --judge --markdown -o json draft.md
```

That runs both catalogs and merges the notes in document order. Because the judge spent money, the JSON says how much: the notes sit under `notes` and a `judge` object carries the backend, the number of requests, the token counts the backend reported and the cost in dollars. The same figures go to stderr in one line for the human formats.

```json
{
  "notes": [ ... ],
  "judge": { "backend": "jev-latest", "requests": 9, "input_tokens": 14200, "output_tokens": 610, "cost_usd": 0.000596 }
}
```

Without the sloplint-judge gem it exits 2 and says to install it. Without a key it exits 2 and says which variable to set. If the model cannot be reached, or answers in a shape the judge does not understand, it exits 3 and writes no notes at all, the regex ones included, so a partial run can never pass as a clean one.

The gem also puts a `sloplint-judge` executable on your path for the judge on its own:

```
sloplint-judge [-o full|json] [--register TEXT] [--backend NAME] [command] [args]

check         scan paths (or stdin) with the judge's rules only [default]
compare A B   which of two passages a plain-prose editor keeps (--drift for rewrites)
rules         list the judge's rule catalog (add --json)
explain ID    print one rule's question, levels, rationale and fixtures
version       print the sloplint-judge version
```

`check` takes `--markdown`, `--select`, `--ignore` and `--strict` with the same meanings as sloplint's. `--strict` also runs the sentence rules on every sentence, rather than only in the paragraphs a paragraph rule flagged or skipped as too short, and keeps the notes the model was not confident about. `--register TEXT` says who the reader is; the default is an engineer on the team reading a design document, and every question is asked on that reader's behalf, so a rule such as `no-news` flags a sentence that reader already knows rather than one anybody would.

### The rules

Ten rules in two categories. `sloplint-judge rules` lists them and `sloplint-judge explain ID` prints the question the model is asked, the answer that flags, and the fixtures. The bar is a little different from the regex catalog's: a judge rule ships when a reader shown the flagged unit agrees it should go, whoever wrote it, and how sharply it separates model prose from human prose sets its severity. So `throat-clearing` is `info`, not gone: human abstracts open by announcing the paper, and it is dead weight either way.

- **paragraph** (4): `particulars`, a paragraph that names nothing a reader could check; `wrap-up`, a paragraph that ends on a summary, a moral or a hope; `throat-clearing`, a paragraph that opens by announcing its topic; `same-weight`, a paragraph that states its guesses and opinions as flatly as its measurements. `same-weight` is off by default; name it in `--select` or pass `--strict`.
- **sentence** (6): `stock-figure`, a stock figure of speech; `no-news`, a sentence that explains what the stated reader already knows; `names-nothing`, a sentence with no specific noun in it; `ends-on-verdict`, a sentence that ends by grading the fact it just stated; `trailing-gloss`, a sentence that ends on an -ing clause drawing its own moral; `matched-shape`, a pair or triple built to a rhythm rather than to the content. `matched-shape` is off by default; name it in `--select` or pass `--strict`.

Each note's `confidence` is the lower of the rule's own ceiling and how sure the model was of that answer. A note the model was unsure about is dropped unless you pass `--strict`, the same way sloplint drops its low-confidence rules.

### Cost and configuration

One request per paragraph carries the paragraph questions, and one request per examined sentence carries the sentence questions, about eight in parallel. A 2,000-word document runs in a few seconds. Every run reports requests, tokens and cost, in the JSON under `judge` and on stderr. Jev returns token counts and no price, so the dollar figure is computed from TypeSafe's public price: $42 per billion input tokens, and output tokens are free. At that rate a 2,000-word document costs well under a cent.

Configuration is from the environment, plus the OS keychain for the key:

| variable | default | meaning |
|---|---|---|
| `TYPESAFE_API_KEY` | none, required | bearer key sent with every request; from the environment, else the keychain item `key set` wrote |
| `SYSTEMONE_MODEL` | `jev-latest` | model name |
| `SYSTEMONE_URL` | `https://api.typesafe.ai/v1/systemone` | endpoint; must be `https` on a `typesafe.ai` host |
| `SLOPLINT_JUDGE_BACKEND` | `jev` | which adapter to use |
| `SLOPLINT_JUDGE_CONCURRENCY` | `8` | parallel requests |

The design, the calibration that decides which rules ship, and how to add a backend are in [docs/JUDGE.md](docs/JUDGE.md).

## The rule catalog

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
