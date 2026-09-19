# sloplint-judge — spec

A second gem in this repository, with sloplint's shape and a different kind of rule. sloplint's rules are regexes: offline, milliseconds, every note traceable to a pattern. sloplint-judge's rules are questions put to a System One model, one that answers typed questions about a piece of text with calibrated probabilities and never writes prose. A rule here is still data. What changes is that the "pattern" is a question the model can answer and a regex cannot: does this paragraph end by restating itself, does this sentence tell the stated reader anything new, does it name a thing a reader could look up.

Everything else is sloplint's, used directly rather than copied: the note object, the paragraph break, the markdown blanker, the exit codes, the fixture discipline, the provenance rules. The judge depends on the sloplint gem. sloplint knows the judge by name and nothing more: `sloplint check --judge` tries to load it and says how to install it if that fails. The dependency points one way. This is the shape dspy.rb uses for its provider gems, and it is the whole plugin system: a lazy `require` behind one flag.

This document is the contract. Phase one is what the spike settled and what ships first. Phase two lists the open items with the test each one must pass before it is built.

## What it is and is not

sloplint-judge is not a detector. The spike asked the model whether a careful editor would suspect a language model wrote a sentence, and the answer was wrong in the same direction every time: edited human prose scored as the most machine-written set and current model prose as the least. Detection stays with sloplint, which separates the same sets tenfold with no network call. No rule in this catalog asks who wrote the text.

What the model can do is judge one quality of one unit of prose, in a way that spreads real human writing across levels for reasons a reader can name, and that ranks model prose below human prose in the registers tested. That is what the rules are built on.

## Terms

- **System One model.** A model that answers typed questions about a state object with probabilities and never writes text. Jev, from TypeSafe, is the first one. The adapter section says how another is plugged in.
- **noul.** A yes-or-no question answered with a probability.
- **choice.** One option from a fixed set, with a probability per option.
- **score.** An ordered set of levels, each described as a situation with examples, with a probability per level.
- **unit.** What a rule looks at: a paragraph or a sentence.
- **register.** Who the reader is, stated in words. Every question carries it, because the same sentence is news to one reader and filler to another.

## The one test for every rule

sloplint's bar, restated for questions: a rule ships only if the thing it flags ranks current model prose below human prose in every register it has been run on, and a reader shown a flagged unit can name why it was flagged. The first half is measured with the calibration script below. The second half is the fixtures: each rule's `examples_bad` must be sentences or paragraphs where a person would agree the flag is fair.

A dimension that separates the two sides in one register and reverses in another does not ship. Two the spike found that way, `redundancy` and `order`, are in the graveyard at the end of the catalog with the numbers that killed them.

## Packaging: two gems, one repository, one plugin

```
sloplint.gemspec              lib/sloplint/**  minus lib/sloplint/judge*   exe/sloplint
sloplint-judge.gemspec        lib/sloplint/judge.rb  lib/sloplint/judge/**   exe/sloplint-judge
                              add_dependency "sloplint", "~> 0.8"
```

The core gemspec's file glob rejects `lib/sloplint/judge*` and `exe/sloplint-judge`, so a plain `gem install sloplint` ships no judge code and no broken executable. The judge gemspec globs only its own tree and `docs/JUDGE.md`. Each gem has its own version file and its own CHANGELOG section, and `gem build` runs twice in CI.

The Claude Code plugin does not change shape. One marketplace entry, one `plugin.json`, plugin root at repository root, so both executables reach `lib/` with `require_relative` and the plugin cache has everything. A second marketplace entry pointing at the same root is a two-line change if anyone ever wants sloplint without the judge; a subdirectory plugin was ruled out because the plugin cache copies only that subdirectory, and the judge needs sloplint's code, not just its output.

Consequences for sloplint's own spec, applied in the same commit that adds the gemspec: the line "no plugin system (YAGNI)" goes, replaced by a sentence describing the lazy require; the offline promise reads "offline, unless `--judge`"; and exit 3 joins the contract for that flag only.

## CLI surface

Two ways in, one engine.

```
sloplint check --judge [check options] [paths...]
```

sloplint's own `check`, with `require "sloplint/judge"` attempted when the flag is set. On `LoadError` it prints "install the sloplint-judge gem" and exits 2. Otherwise the regex notes and the judge notes for each path are merged by line and emitted as one array. The other `check` options apply to both linters: `--markdown` blanks once and both scan the same text; `--select` and `--ignore` take ids and categories from either catalog; `--strict` runs sloplint's low-confidence rules and the judge's sentence rules everywhere and keeps its low-confidence notes. This is about ten lines in `cli.rb` and none in `engine.rb`. The regex engine never sees a judge rule.

```
sloplint-judge [GLOBAL] <command> [ARGS]

commands:
  check          scan paths (or stdin) and report judge notes only   [default command]
  compare A B    which of two passages a plain-prose editor keeps
  rules          list the judge's rule catalog (human or --json)
  explain ID     print one rule's question, levels, examples, and rationale
  version        print version

global options:
  -o, --output-format  full | json   (default: full)
  --backend NAME       which adapter to use (default: from SLOPLINT_JUDGE_BACKEND, else jev)
  --register TEXT      who the reader is (default: "an engineer on the team reading a design document")

check options:
  paths ...            files to scan; "-" or no paths reads stdin
  --markdown           skip fenced/inline code spans, HTML comments, and URLs
  --select IDS         only run these rules (comma-separated ids or categories)
  --ignore IDS         skip these rules
  --strict             run every rule on every unit, and keep low-confidence notes

compare options:
  --drift              also ask whether B changes what A says (sentence rewrites)
```

The judge's own executable exists for `compare`, `rules` and `explain`, which have no home in sloplint's CLI, and for running the judge alone. Its `check` takes paths the way sloplint's does, so `sloplint-judge draft.md` and `cat draft.md | sloplint-judge --markdown -o json -` both work.

`--register` and `--backend` are the two flags sloplint does not have, and `sloplint check --judge` accepts both. Every rule's question is written against a reader, and the default is the reader the tool is usually pointed at. The value is prose, not a code, so `--register "a newcomer reading the README"` works without a table to look it up in.

## Exit codes

sloplint's three, plus one.

| code | meaning |
|------|---------|
| 0    | ran, **no notes** |
| 1    | ran, **notes found** |
| 2    | bad arguments / usage error, empty input, or judge gem not installed |
| 3    | backend failure: no key, network down, malformed answer |

Exit 3 writes nothing to stdout, from either executable. Under `sloplint check --judge` that means the regex notes are withheld too: a caller that asked for both and got one would read it as a clean judge run, which is the one lie the exit codes exist to prevent. A caller that wants sloplint's notes regardless runs plain `sloplint check` and `sloplint-judge check` as two commands.

## Note (the diagnostic object)

Identical to sloplint's, field for field. One flagged unit = one Note. JSON output is an array of these, or an object keyed by path when several files are scanned.

```json
{
  "path": "draft.md",
  "line": 40,
  "column": 1,
  "severity": "warning",
  "confidence": "high",
  "rule": "wrap-up",
  "category": "paragraph",
  "message": "Paragraph ends by restating itself.",
  "excerpt": "Together, these factors make the migration worth the cost.",
  "context": "…rollback took four minutes. [Together, these factors make the migration worth the cost.]",
  "rationale": "A paragraph that closes on a summary of itself tells the reader nothing they did not have one sentence earlier. Human prose in this register closes on a fact or a consequence; model prose closes on a moral.",
  "suggestion": "Cut the last sentence, or end on the number."
}
```

The differences are in where the values come from, not in the shape.

- `severity` is fixed per rule, as in sloplint: what the construct costs the prose.
- `confidence` is per note, not per rule, because the model returns one with every answer. At or above 0.7 is `high`. Between 0.5 and 0.7 is `medium`. Below 0.5 is `low`, and a low note is dropped from the default run the way a low-confidence sloplint rule is; `--strict` keeps it. The bands come from the spike: across 1,058 pairs, no answer at or above 0.7 flipped when the order of the passages was swapped, and below 0.5 one answer in nine did.
- `line`, `column`, `excerpt` and `context` point at the unit. For a paragraph rule the excerpt is the sentence the rule is about (the last sentence for `wrap-up`, the first for `throat-clearing`, the whole paragraph for `particulars`) so that the note lands where the fix goes.
- `count` is never present. No rule counts.
- The raw probability vector is not on the note. A consumer that wants it runs `explain` for the levels and `check -o json --strict` for every note, or uses the calibration script, which reports probabilities directly. Keeping the note shape identical to sloplint's is worth more than one extra field.

## Rule model

A rule is data. `rules.rb` holds an array of `Rule` objects built with `Data.define`:

```ruby
Rule = Data.define(
  :id, :category, :unit, :severity, :question, :flag, :message, :suggestion,
  :examples_bad, :examples_ok, :rationale
)

RULES = [
  Rule.new(
    id:       "wrap-up",
    category: "paragraph",
    unit:     :paragraph,                  # :paragraph or :sentence
    severity: "warning",                   # error, warning, info -- cost to the prose
    question: {
      type: "score",
      instructions: "How does this paragraph end, for %{register}?",
      criteria: [                          # ordered low to high; high is what the editor prefers
        { what: "It closes by restating what the paragraph already said, or by drawing a moral from it.",
          examples: ["In short, the migration paid for itself.", "This shows why careful planning matters."] },
        { what: "It closes on a transition, a question, or a promise of what comes next.",
          examples: ["The next section covers the rollback.", "Whether that holds under load is another matter."] },
        { what: "It closes on a fact, a number, or a consequence the reader did not have yet.",
          examples: ["Rollback took four minutes.", "Two of the three replicas never received the write."] }
      ]
    },
    flag:     { level: 0 },                # most likely level is 0 -> note
    message:  "Paragraph ends by restating itself.",
    suggestion: "Cut the last sentence, or end on the number.",
    examples_bad: ["..."],                 # paragraphs the rule must flag
    examples_ok:  ["..."],                 # paragraphs it must not
    rationale: "..."
  ),
  # ...
]
```

`question` is the System One question, verbatim in the shape the adapter sends. `%{register}` is interpolated from `--register`. `flag` says which answer makes a note: `{ level: 0 }` for a score, `{ yes: true }` for a noul. There is no threshold on the probability itself, only on the most likely answer and the model's confidence, because a threshold is a number nobody can defend and the confidence gate already does the job.

The engine never grows a branch for a rule. If a rule needs logic, the question is wrong, not the engine. That is sloplint's rule and it holds harder here: a question the model cannot answer from the text in front of it is a question that should not be asked.

### Fixtures are live

`examples_bad` and `examples_ok` are run against the backend by the spec, one request per fixture, and the most likely level must land on the flagged side or off it. This needs a key, so the fixture spec skips itself with a message when none is set. Everything else in the suite (splitting, note assembly, the CLI, exit codes, the adapter's serialisation) runs offline against a fake backend that returns what it is told. A rule with no fixtures does not load.

Fixtures are synthetic, as in sloplint. No sentence read during calibration is pasted into the repository.

## Rule catalog (v1)

Eight rules, two categories. Numbers are the probability that a model paragraph or sentence scores higher than a human one in the same register, from the calibration runs described in the commit that added each rule. Below 0.5 means the rule ranks model prose lower, which is what a rule is for.

### paragraph

Run on every paragraph of three or more sentences. One request per paragraph carries all three questions.

- **particulars** (`warning`). How much of the paragraph is a fact, name, number, step or quote a reader could check: none of it, some of it, most of it. Flags at none. 0.08 to 0.30 across six registers of the RAID corpus against GPT-4, and 0.21 to 0.31 in RFC-register prose against Claude Haiku 4.5, Sonnet 5 and Opus 5. It reverses in forum comments against the two Claude 5 models (0.64 and 0.70), where a comment is allowed to have no particulars; see phase two.
- **wrap-up** (`warning`). How the paragraph ends: restating or moralising, transition, or new fact. Flags at restating. 0.05 in abstracts, 0.22 to 0.39 in RFC-register prose.
- **throat-clearing** (`info`). How the paragraph begins: a general announcement of the topic, a framing sentence, or a particular. Flags at announcement. 0.25 to 0.50, the weakest of the three, hence `info`.

### sentence

Run on every sentence of the paragraphs a paragraph rule flagged, so the expensive questions are asked where the cheap ones found something. `--strict` runs them on every sentence. One request per sentence carries all five questions, with the sentence's paragraph and its index in the state so the model sees the neighbours.

- **stock-figure** (`warning`). The sentence uses a figure of speech that is stock, a figure that is the writer's own, or no figure. Flags at stock.
- **no-news** (`warning`). For the stated reader, the sentence explains what they already know, states what they could have guessed, or tells them something new. Flags at explains-known. Never reversed in any of six registers against GPT-4, 0.24 to 0.49.
- **names-nothing** (`warning`). The sentence names nothing, names a kind of thing, or names a thing a reader could look up. Flags at names-nothing. Never reversed against GPT-4. This is the concreteness dimension from the spike, renamed to say what the flag means.
- **ends-on-verdict** (`info`). The sentence ends on a verdict or moral, trails off on a qualifier, or ends on the fact that carries it. Flags at verdict.
- **matched-shape** (`info`). A matched pair or triple shaped the content, a list the content needed, or no matched structure. Flags at shaped-the-content. Sits near 0.5 against GPT-4 and separates strongly against the Claude 5 models. It is a tell of one model family and its rationale says so.

Each sentence rule reports on its own. There is no combined score and no threshold that combines them.

### Graveyard

Tested, not shipped, kept here so nobody tests them again without new evidence.

- **claim-count**: one claim, two yoked, or none. No separation in any register.
- **commitment**, **stake**: measure whether the writer has a stake. Measure genre, not quality: an abstract has no stake and should not.
- **redundancy**, **order**: flip sign between registers.
- **glue**, **hedge**, **fat**, **owned-claim**, **unresolved**, **paragraph-role**: below the gating bar in the six-register test or never reached it.
- **machine-written**: the guard. Measures abstraction, not authorship, and gets it backwards.

## Splitting

Paragraphs are separated by sloplint's `PARA_BREAK`, and `--markdown` is sloplint's blanker: fenced and inline code, HTML comments and URLs go before splitting. On top of that the judge drops headings, list items, table rows, block quotes and reference lines, because a heading is not a paragraph and a bullet is not a sentence. Sentences are split on terminal punctuation followed by a space and a capital or an opening quote, with a short list of abbreviations that do not end a sentence. This is the splitter the spike used. It lands in the core gem as `Sloplint::Split`, a public module the regex engine does not call, because the reader-test skill needs the same splitter and two consumers make it core's to own. A paragraph with fewer than three sentences is skipped by the paragraph rules and its sentences are never reached by the sentence rules unless `--strict`.

## Backend adapter

The engine depends on one interface and ships one implementation. Everything it knows about the model lives behind it.

```ruby
module Sloplint::Judge
  module Backend
    # state:     Hash, the object the questions are about
    # questions: Hash of name => { type: "noul" | "choice" | "score", instructions: String, criteria: ... }
    # returns:   Hash of name => Answer
    def ask(state, questions); end

    # A short, stable string: "jev-latest".
    def name; end
  end

  Answer = Data.define(:type, :probabilities, :confidence, :usage)
  # probabilities: for noul, a Float; for choice, a Hash keyed by criterion name; for score, an Array low to high.
  # confidence:    Float in 0..1.
  # usage:         Hash, whatever the backend counts, passed through for the stderr trailer; may be empty.
end
```

The engine never reads a backend's raw response. It calls `ask`, receives `Answer`s, and applies each rule's `flag` and the confidence bands to those. A new backend is a class that answers `ask` and `name`, and one line in the backend table.

### What a backend must honour

- **Three question types**, with the answer shapes above. A backend that lacks one refuses the rules that need it, with a message naming them, rather than approximating.
- **Choice criteria are a dictionary**, keyed by option name. Jev returns 422 on an array.
- **Score levels are ordered and described as situations**, each `{what, examples}`, low to high, and the answer vector keeps that order.
- **Several questions per request.** All rules of one unit go in one request. A backend that takes one question per call fans out inside `ask` and reports the summed usage.
- **A confidence per answer.** Without it the bands cannot run. A backend with no native confidence must return one it can defend, for instance the margin between the top two probabilities, and every note's provenance is checked per backend by the calibration script before that backend is trusted.
- **State is opaque to the backend.** The engine puts the register, the paragraph, the sentence index and the passages in the state. A backend serialises it and does not interpret it.

### The Jev adapter

Default backend. `POST https://api.typesafe.ai/v1/systemone` with body `{state, model, questions}`. Questions pass through verbatim, because the rule's question shape is Jev's. Response `answers.<name>.{probabilities, confidence}` and `usage.input_tokens` map onto `Answer` directly.

Configuration is from the environment. There is no configuration file.

| variable | default | meaning |
|---|---|---|
| `SLOPLINT_JUDGE_BACKEND` | `jev` | which adapter class to load |
| `SYSTEMONE_URL` | `https://api.typesafe.ai/v1/systemone` | endpoint |
| `SYSTEMONE_MODEL` | `jev-latest` | model name sent in the body |
| `TYPESAFE_API_KEY` | none, required | bearer key |
| `SLOPLINT_JUDGE_CONCURRENCY` | `8` | parallel requests |

### Adding a backend

1. Write a class under `lib/sloplint/judge/backends/` that answers `ask` and `name`.
2. Add its name to the backend table.
3. Run `script/calibrate` against the RAID paragraph and sentence sets. It reports, per rule and register, the probability that the model unit scores higher than the human one, and the flip rate under passage-order swap at each confidence band. A backend is usable when `no-news` and `names-nothing` sit below 0.5 in every register and the flip rate at or above 0.7 confidence is under 1 percent. If the bands differ, the confidence thresholds are per backend.

## compare

The pairwise judge from the spike, kept as a second command because the rewrite loop in phase two needs it and nothing in `check` provides it. Two passages, A and B, and a choice question:

> A careful editor who wants prose that is plain, specific and economical, and who distrusts polish for its own sake, must run exactly one of A and B *place*. Which does the editor run?

*place* is the register as a venue: "as the opening of the article", "in an engineering design document read by the team". With `--drift`, a noul rides along: does B state any fact, claim or qualification that A does not, or drop any that A states. Order is randomised per call because the judge has a position bias, and the answer is mapped back before it is reported. Output is `{keep: "A"|"B", p_keep_b: Float, drift: Float|null, confidence: Float}`.

The acceptance rule for a rewrite, which the phase-two loop applies and which `compare` only reports: B replaces A only when `p_keep_b >= 0.5` and `drift <= 0.5` and confidence is at or above 0.7. In the spike the judge kept the human passage in 78 to 98 percent of matched pairs across news and abstracts.

## Known failure mode

The judge trades substance for fluency when it cannot read the content. In the RAID abstracts, the human passages it rejected were non-native or dense specialist prose, and the model passages it preferred were smooth, generic and said less. A plain-prose editor who does not know the field picks the paragraph they can follow.

Consequences:

- `check` writes no text, and nothing in phase one does.
- A `no-news` or `names-nothing` note at low confidence is read as "the judge did not understand the claim", and the phase-two rewrite loop applies strict drift to that sentence. A claim the judge cannot read is not one it is allowed to simplify.
- Every rationale says the judgment is about the reader's experience of the prose, not the truth or completeness of the claim.

## Cost and speed

Measured against Jev. Other backends report their own numbers through `script/calibrate`.

| request | input tokens | wall time |
|---|---|---|
| three paragraph rules, one paragraph | ~1,500 | ~500 ms |
| five sentence rules, one sentence | ~2,000 | ~500 ms |
| compare, sentence pair with paragraph context | ~590 | ~500 ms |
| compare, paragraph pair | ~800 | ~500 ms |

A 2,000-word design document with forty paragraphs and a quarter of them flagged runs about 40 paragraph requests and 50 sentence requests: roughly 160,000 input tokens and 6 seconds at eight in parallel. With `--strict` the sentence side runs everywhere and the cost roughly triples. TypeSafe publishes no price, so `check` writes a token count to stderr and does not estimate money.

## Agent-first help text

As in sloplint, `--help` leads with the copy-paste recipe. The `check` skill grows one branch: when a key is present it adds `--judge`, otherwise it runs as today.

```
ruby "${CLAUDE_PLUGIN_ROOT}/exe/sloplint" check --judge --markdown -o json PATH
```

One command, one array, already in document order. The skill presents it as it does now, quoting `context` and one sentence from `suggestion`, and never prints rule ids or severities unless asked. It says when the judge did not run (exit 3) in different words from when it found nothing (exit 0), and it names the backend in the report because two runs with two backends are two different opinions.

## Phase two

Each item ships only when its test passes. The tests are stated now so they cannot be lowered later to fit a result.

- **Rewrite loop.** An agent proposes a rewrite for a flagged sentence; `compare --drift` decides. Test: on 200 sentences from the RAID human side, accepted rewrites must not lower the paragraph's `particulars` level, and a person reading 50 accepted rewrites blind must prefer the rewrite in at least 35.
- **Stability.** Test: the same 300 paragraphs scored twice an hour apart, with the flagged set agreeing in at least 90 percent of paragraphs at or above `high` confidence. Until this passes, no rule moves from `warning` to `error`.
- **Grounding.** Put the source material (the code, the ticket, the log) in the state and add a noul rule per sentence: does the source support the claim. Test: on 100 sentences with hand-labelled support, the rule at `high` confidence must be right in 90 or more, and the failure mode above must not reappear as a preference for sentences that claim less.
- **Register caveat for `particulars` and `names-nothing`.** Both reverse against current Claude models in forum-comment prose. Test: run the six-register set against Claude Opus 5 and Sonnet 5; a rule keeps `warning` in a register only where the model scores higher in under 0.45 of pairs, and drops to `info` there otherwise. Until then the default register is a design document and the README says the comment register is untested.
- **Recorded fixtures.** The live fixture spec is slow and needs a key. Test: a recorded run of every fixture that replays offline and fails when a rule's question text changes, so an edited question cannot ride on a stale recording.
- **Publishing the gem.** Phase one builds `sloplint-judge.gemspec` and runs from the plugin tree; pushing it to rubygems.org waits for stability. Test: `gem install sloplint-judge` on a machine without the repository, then `sloplint check --judge` on a document, reports the token count and the backend name.

## Relationship to reader-test

reader-test is a separate skill: per document, a four-slot reader definition, triage from whole document to section to sentence, and house-rule nouls written for that one document. sloplint-judge is a catalog of rules that hold across documents, run the way sloplint is run. The two share a backend adapter and `Sloplint::Split`, not a job. reader-test asks what one named reader experiences on this page; sloplint-judge asks the questions that have been shown to rank model prose below human prose, and reports where they fire. reader-test's machine-detection question is the guard this spike showed fails backwards and should not be relied on.

## Provenance

Same rules as sloplint, same repository. The spike's corpora (IETF RFCs, Hacker News comments, six documents from three Claude models, RAID) are not committed. Fixtures are synthetic. `script/calibrate` reuses `script/probe-raid fetch` and the ignored `.corpus/` directory, and the numbers a run produces go in the commit message that adds or changes a rule, never in the shipped rationale.
