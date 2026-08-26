# sloplint — spec

A CLI that scans prose for the tells of AI-generated "slop" and reports them as
linting notes. Think `proselint`, but narrowly aimed at the rhetorical tics and
puffery that mark LLM writing.

Primary consumer is an **agent** (Claude Code and friends) that runs sloplint,
reads the JSON, and rewrites the flagged text. Humans are the secondary
consumer. Every design choice below favors machine-readability and a help text
an agent can act on without guessing.

## The one test for every rule

A pattern earns a place in the catalog only if it **shows up constantly in AI
writing and rarely in careful human writing.** That's the whole filter.

If a thoughtful human writer does it all the time too — passive voice, weak
adverbs, comma splices, wordiness — it belongs in proselint or write-good, not
here. sloplint is not a general prose linter and never tries to be. It hunts
the specific fingerprints of a language model: the cadences, the puffery, the
reflexive both-sidesing that a person almost never produces but an LLM produces
by the paragraph.

Two payoffs from holding this line: a low false-positive rate (so an agent can
trust a flag instead of second-guessing it), and no overlap with tools that
already do general prose well. When a rule is borderline, ask the test again and
cut it if the answer is soft.

## Provenance: what may be committed

Finding rules means reading a great deal of other people's writing: slop in the
wild to spot a tell, careful human prose to check a candidate against. Reading it
is fine. Committing it is not. A regex carries nothing of the text it came from,
so the source never needs to enter the repository.

- **No corpus is committed**, on either side. Collection notes stay out of the
  repo.
- **`examples_bad` are written, not lifted.** When a real sentence is the only
  illustration on hand, rewrite it until it carries the pattern without carrying
  the original wording.
- **`examples_ok` may quote real prose, public domain only**, with the source
  named in a comment. The Moby-Dick and Federalist No. 44 fixtures are the model.
  A common idiom or a title is not a quotation and needs no such treatment.
- **`rationale:` states frequencies, not quotations.** "24 hits in 1.02M words"
  is the form.
- **A reference corpus of human prose must be public domain.** Copyrighted text
  can't be redistributed, so a corpus built from it can't live in the repo, and
  neither can the false-positive check that depends on it.

This repository is MIT-licensed, so anything committed is redistributable by
anyone. Writing the fixtures ourselves also means nobody's prose gets held up as
a specimen of slop, which is reason enough on its own.

## Prior art we're borrowing from

- **proselint** — subcommand CLI (`check`, `version`, `dump-config`), `--output-format full|json|compact`, LSP-style diagnostics (line/column/severity/code/message), config file, clean exit codes. We copy this shape.
- **vale** — markup-aware (skips code blocks, knows Markdown). We do a lighter version: optional `--markdown` to skip fenced code and inline code.
- **write-good / alex** — naive regex rules, one module per rule. We keep rules as data, not code, so they're trivial to add.
- **Wikipedia's [Signs of AI writing](https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing)** — the puffery category comes from its "words to watch" boxes, and its habit of grouping tells by the move they make rather than by word is the shape our categories follow.
- **[slopwash.com](https://slopwash.com)'s anti-slop ruleset** — a prompt-shaped catalogue of AI writing tells, and the prompt for the review that produced the current chat-register rules. We take its method, not its inventory: its vocabulary list (delve, tapestry, "nestled in the heart of") is calibrated to 2023–24 model output and didn't survive probing against writing since, so none of it ships. One family did, the false-intimacy preamble behind `if-im-being-honest`.

## Why build fresh instead of extending proselint

proselint is a general prose linter. Extend it and our AI-tell rules land next
to its checks for passive voice, clichés, and date formatting — a user who just
wants "does this read like a bot?" can't get that without running everything and
filtering. The narrow focus is the whole product, and folding into proselint
dilutes it on day one.

The practical cost is worse. Upstreaming our rules puts our release schedule at
the mercy of their review and their view of scope. Forking means maintaining a
whole prose linter to ship what is really a few hundred lines of regex. Both are
bad trades for the size of this thing.

And the part we actually care about — the agent-facing design (`explain` and
`rules` commands, the JSON schema as a fixed contract, the copy-paste recipe in
`--help`) — isn't in proselint. We'd be bolting it onto someone else's CLI (and
proselint is Python; we're Ruby). Writing our own shell is about a day, and
proselint already showed us
what that shell should look like. The hard part was never the CLI; it's the
rules and holding down false positives, and proselint helps with neither.

One additive move, not either-or: once the rules exist as data, we can also
package them as a proselint plugin, so people already using proselint get our
checks without us inheriting their codebase. Cheap, because the rules are
already pure data.

## Language & shape

Ruby 3.3+, **standard library only** (`optparse`, `json`, native regex). No gem
dependencies at runtime.

Rationale: rules are regexes; the whole thing is a scanner plus an output
formatter. A dependency-free `gem install sloplint` is the robust, boring
choice. The name is free on RubyGems (taken on PyPI, so this also sidesteps the
collision). Ships a `sloplint` executable via the gemspec's `bin`.

Package layout (standard gem):

```
sloplint/
  bin/sloplint             # thin shim: require "sloplint/cli"; exit Sloplint::CLI.run(ARGV)
  lib/sloplint.rb          # requires the pieces below
  lib/sloplint/version.rb
  lib/sloplint/cli.rb      # optparse, subcommands, exit codes
  lib/sloplint/rules.rb    # RULES: array of Rule (Data) objects — the catalog
  lib/sloplint/engine.rb   # Engine.scan(text, rules:, config:) -> [Note]
  lib/sloplint/output.rb   # format_human / format_json / format_compact
docs/
  SPEC.md                  # this file
spec/
  rules_spec.rb            # each rule: >=1 positive, >=1 negative fixture
  cli_spec.rb              # exit codes, stdin, output formats
  spec_helper.rb
sloplint.gemspec
.rspec
Rakefile                   # rake spec
```

RSpec is a **development** dependency (in the gemspec's `add_development_
dependency`), so the runtime stays dependency-free.

## CLI surface

```
sloplint [GLOBAL] <command> [ARGS]

commands:
  check       scan paths (or stdin) and report notes   [default command]
  rules       list the rule catalog (human or --json)
  explain ID  print one rule's description, examples, and rationale
  version     print version

global options:
  -o, --output-format  full | json   (default: full)

check options:
  paths ...            files to scan; "-" or no paths reads stdin
  --markdown           skip fenced/inline code spans
  --select IDS         only run these rules (comma-separated ids or categories)
  --ignore IDS         skip these rules
```

Bare `sloplint` with piped stdin behaves as `sloplint check -`. This is the
common agent path: `cat draft.md | sloplint check --markdown -o json -`.

Deliberately left out of v1 (add when a real need shows up, not before):
`compact` output, `--min-severity`, `--max-notes`, color, `-q/--quiet`, and a
`--demo` flag (the slop fixture lives in `spec/` instead).

## Exit codes

Three codes carry the contract. A crash just exits nonzero on its own.

| code | meaning |
|------|---------|
| 0    | ran, **no notes** |
| 1    | ran, **notes found** |
| 2    | bad arguments / usage error |

## Note (the diagnostic object)

One match = one Note. JSON output is an array of these (or an object keyed by
path when multiple files are scanned).

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

- `line`/`column` are 1-indexed, pointing at the start of the match.
- `excerpt` is the bare match, nothing else. It is what `column` points at.
- `context` is the match bracketed inside ~40 characters of surrounding prose,
  whitespace collapsed, with `…` on any end that was cut. It exists because a
  bare `excerpt` says nothing useful when the match is one word or a lone em
  dash. A match already 40 characters long carries its own context, so `context`
  returns it alone rather than padding it out further. The window is sliced from
  the text as written, so `--markdown` still shows real code and URLs here even
  though they were blanked before matching.
- `count` present when the rule counts items (the "badge" in the examples).
- `rationale` is the same text `sloplint explain` prints under `Why:` — why the
  pattern reads as a tell. `check` carries it on every note so an agent acting
  on an `info` flag (or deciding whether to) doesn't have to shell out to
  `explain` first; that's the whole point of the field.
- `suggestion` is a short fix hint; agents may use it, humans see it too.

## Rule model

A rule is data, not a function. `rules.rb` holds an array of `Rule` objects
built with `Data.define` (immutable value objects, Ruby 3.2+):

```ruby
Rule = Data.define(
  :id, :category, :severity, :pattern, :message, :suggestion,
  :examples_bad, :examples_ok, :count_group, :skip
) do
  # sensible defaults for the optional fields
  def initialize(count_group: nil, skip: [], **rest) = super
end

RULES = [
  Rule.new(
    id:          "no-x-no-y",
    category:    "rhetorical-tic",
    severity:    "warning",
    pattern:     /.../i,                       # regex literal; add /m if multiline
    message:     "...",                         # may reference %{count}
    suggestion:  "...",
    examples_bad: ["No fluff, no filler, no jargon."],
    examples_ok:  ["No parking on Sundays."],   # must NOT match; asserted in tests
    count_group:  nil,                          # optional: capture group to tally
    skip:        [/real estate/i, /real time/i] # optional exclusions
  ),
  # ...
]
```

Adding a rule = appending one entry + one bad and one ok fixture. That's the
whole extension story. No new files, no plugin system (YAGNI).

### Why Ruby literals, not JSON/YAML

The rules are data, but they live in a `.rb` array on purpose:

- **YAML** ships with Ruby, but regex in YAML is a string that has to be
  re-parsed and re-escaped — every `\b` doubled, no `/i` flags inline, and the
  good/bad fixtures drift away from the pattern they test.
- **JSON** is stdlib too but worse for regex: same escaping tax, no comments,
  no multiline patterns. Both external formats also need a load-and-validate
  layer that a Ruby array gets for free — a typo is a syntax error at require
  time, not a silent miss.

A Ruby array with real regex literals (`/.../i`) is the nicest place to *author*
regex — flags, comments, and fixtures all in one spot. The usual reason to move
rules to a file (non-devs editing them, third-party rule packs) isn't real yet.
If it becomes real, the migration is cheap precisely because the rules are
already pure data: write one loader, point it at a JSON dir, done.

Categories (for `--select`/`--ignore` by group):

- `rhetorical-tic` — the cadence patterns (the user's list below)
- `puffery` — Wikipedia "words to watch" (boasts, vibrant, nestled, tapestry…)
- `structure` — rule-of-three, "not just X but Y", em dash, em-dash overuse
- `hedging` — vague attribution ("some critics argue", "it is widely regarded")

Severities: `warning` for strong tells, `info` for weak/contextual ones. No
rule ships at `error` yet -- reserved for a pattern with essentially zero
false-positive risk, which none has demonstrated.

## Rule catalog (v1)

### rhetorical-tic (from the request)

| id | catches | notes |
|----|---------|-------|
| `no-x-no-y` | 2+ comma-separated "no …" items in a row | counts items |
| `no-x-no-y-frag` | the same cadence as sentence fragments ("No fluff. No filler.") | counts items; `info` |
| `thats-the-whole` | "that/this is the whole point/game/thing…" | |
| `did-not-x-did-not-y` | 2+ "did not …"/"didn't …" in a row | counts items |
| `dont-verb-it` | "Don't call it X. Call it Y." (negated verb+it, same verb+it) | |
| `sit-with-that` | "sit with that/this/it", "sit with the discomfort" | |
| `hold-onto-that` | sentence-initial "hold onto/on to that/this" | imperative only |
| `cleanly` | "cleanly" anywhere | no verb list; the engineering idiom counts too |
| `clean-count` | "two/three clean parts/buckets/categories…" | needs a partition noun |
| `cleanest-x` | "the cleanest framing/formulation", "cleanest way to put it" | noun list only |
| `clean-x` | "a clean abstraction/distinction/framing", "clean line between" | `info` |
| `you-already-know` | "you already know" (+ the answer / standalone) | |
| `is-the-entire` | "X is the entire point/game/business model" | |
| `the-entire-is` | "the entire point/game/… is" (flip of above) | |
| `is-real-and-not` | "the X is real, and/not…", "is the real … and it" | skip "real estate/time"; `info` |
| `the-punchline-is` | "the punchline is/:/?", "the honest answer/version is" | "short version" left out; ordinary writing |
| `worth-naming` | "worth naming/flagging/separating/spelling out" | skip "naming names"; yields to the rule below when a manner adverb follows; `info` |
| `worth-saying-plainly` | "it's worth saying plainly / better put bluntly…", plus the bare "Put plainly," / "Said bluntly," | sentence-initial; the bare branch drops "simply"/"clearly" so "put simply" and "simply put" stay clean |
| `not-nothing` | copula + "not nothing" litotes, any subject | skip personal/there subjects |
| `exact-exactly` | "exact"/"exactly" | allowlist for the checkable uses; `info` |
| `load-bearing` | "load-bearing" outside its construction sense | skip building nouns either side |
| `thats-how-x` | sentence-initial "that's how…" | |
| `announced-takeaway` | colon-led label: "The pattern/lesson/takeaway…:" | sentence-initial |
| `earns-its-place` | "earns its place/keep" (any possessive) | possessive required; `warning` |
| `does-a-lot-of-work` | "does a lot of work here/in that sentence", "a lot of heavy lifting" | plain "the heavy lifting" excluded |
| `failure-mode-here` | "the failure mode here is" | deictic required; bare "the failure mode is" excluded |
| `thats-the-tension` | sentence-initial "that's the tension/bet" as a closer | noun must end the clause; "tradeoff"/"catch" excluded |
| `right-up-until` | "right up until it doesn't/isn't/stops/breaks" | bare "until it doesn't" excluded |
| `two-things-true` | "two/both things can be/are true" | count fixed at two |
| `notice-what-there` | "notice what X did there", "read that again" | sentence-initial |
| `notice-what` | bare sentence-initial "Notice what…" | yields the "there" frame to the rule above; "how" excluded; `info` |
| `none-of-this-is-to-say` | "none of this/that/the above is to say" | every other "not to say" phrasing excluded |
| `if-im-being-honest` | "if I'm/we're (being) honest", "honestly, the answer/truth" | plain "to be honest" and "I'll be honest" excluded |
| `genuinely` | any "genuinely" | off by default; no narrowing holds |
| `is-is` | doubled copula: "what it is is …", "the thing is, is that …" | comma optional |

### puffery (Wikipedia: Signs of AI writing)

Single flat rule per word-cluster, matched as whole words:

- `puffery-words` — boasts a, vibrant, rich (history/cultural/tapestry), nestled (gated to a following in/among/between, so the literal verb — a head nestled against a shoulder — doesn't count), in the heart of (gated to a place object), groundbreaking, renowned, diverse array, breathtaking, natural beauty, stands as a testament, indelible mark, deeply rooted.
- `stands-serves-as` — "stands as / serves as", "is a testament/reminder to".
- `vital-role` — "plays a (vital/crucial/pivotal/significant/key) role".
- `underscores-highlights` — "underscore(s)" + determiner and "underscored/underscoring" anywhere (the emphasis verb); "highlights/emphasizes its (importance/significance)" stays narrow.
- `rich-tapestry` — "rich tapestry", "tapestry of".

### structure

- `not-just-x-but-y` — copula + "not just/only/merely/simply/solely X … but (also) Y", plus "not because X, but because Y". Requires the escalation word.
- `not-x-but-y` — the bare corrective "is not X but Y" with no escalation word; `info`, because the corrective/concession distinction is syntactic and the pattern can only approximate it.
- `rule-of-three` — three parallel comma items ending a sentence (heuristic; `info` severity, off by default via `--select` since it false-positives).
- `em-dash` — any em dash; `info`.
- `em-dash-overuse` — 3+ em dashes in one paragraph; `warning`.

### hedging

- `vague-attribution` — "some (critics/experts/observers) (argue/say/believe)", "it is widely (regarded/considered/seen)", "many would argue".

## Markdown handling

`--markdown` blanks out fenced code (```` ``` ````), inline code (`` ` ``), and
URLs before scanning, replacing them with same-length whitespace so line/column
stay correct. Off by default (plain-text mode) so it never silently eats prose.

## Agent-first help text

This is a first-class requirement, not an afterthought.

- `sloplint --help` opens with a one-line what-it-does, then a **copy-pasteable
  agent recipe** block:

  ```
  # Recommended for agents:
  cat FILE | sloplint check --markdown -o json -
  # exit 0 = clean, 1 = notes found, >1 = error
  # each note: {path,line,column,severity,rule,category,message,excerpt,context,rationale,suggestion}
  ```

- Every option has a full-sentence help string (no telegraphic fragments).
- `sloplint rules` prints the catalog: id, category, severity, one-line
  description — and with `--json`, the machine version an agent can enumerate.
- `sloplint explain no-x-no-y` prints the rule's message, rationale, a bad
  example and an ok (non-matching) example. Agents call this to decide whether a
  flag is worth acting on.
- JSON output is stable and documented here; the schema is the contract.
- `--help` epilog links to `sloplint explain` and `docs/spec.md`.

## Testing

RSpec (dev dependency), run via `rake spec`.

- Every rule ships `examples_bad` (must produce ≥1 note) and `examples_ok`
  (must produce 0). `rules_spec.rb` iterates the catalog and asserts both — a
  new rule without fixtures fails CI.
- `cli_spec.rb` covers: exit codes (0/1/2), stdin path, `-o json` parses and
  matches the schema, `--select`/`--ignore`, `--markdown` skips code.
- A built-in slop fixture doubles as an integration example (known note count).

## Explicitly out of scope for v1

- Config files (`.sloplintrc`). Add when someone needs per-project rule tuning;
  `--select`/`--ignore` cover the common case first.
- LSP server mode, editor plugins, autofix/rewrite. sloplint *flags*; the agent
  rewrites. Autofix is a separate tool if ever.
- Non-English. Languages other than English are a v2 conversation.
- ML/embedding-based detection. This is a regex linter on purpose — fast,
  explainable, zero-dependency. Statistical detection is a different product.
- Scraped corpora. Platform terms prohibit automated collection, and finding a
  repeated shape needs hundreds of samples rather than millions, so collection
  stays manual. Analysis is offline development work either way; the shipped
  runtime stays regex plus stdlib.
