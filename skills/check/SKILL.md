---
name: check
description: Checks a piece of writing for the phrases and rhythms that make it read as AI-written. Use when the user asks to check for AI writing, scan for slop, lint this draft, asks "does this read as AI-written", or says sloplint. Runs a scanner; reports only what the scanner returns.
---

# Check writing with sloplint

## Run the scanner, or say you could not

You must actually run the sloplint command and report only what it returns. If it does not run — no shell here, no Ruby installed, any reason at all — say plainly that sloplint could not run and why, and stop there. Never assess the prose yourself, and never present your own judgment as sloplint's findings. Getting no answer is a fine outcome. A made-up one is not: the person then believes a linter cleared their draft when nothing checked it.

## Get the text

If they name a file, use it.

If the prose is in the conversation — pasted in, or drafted with you — write it verbatim to a temporary file with the Write tool and scan that path. Never put the prose inline in a shell command. An unquoted heredoc eats `$` and backticks, so `$50,000` becomes `,000`, and an em dash is something sloplint checks for, so mangled punctuation produces findings that are wrong in both directions with nothing on the page to reveal it.

Ask which file only when there is no prose anywhere to work from.

## Decide whether the judge runs

The regex scanner runs on this machine and nothing leaves it. The judge is the exception: it asks a model the questions a regex cannot, and to do that it sends the text, paragraph by paragraph, to TypeSafe's API at api.typesafe.ai. It costs about a tenth of a cent per thousand words. The person decides whether that happens, not the presence of a key.

First find out whether the judge is even possible here. This command reads no key and prints none; it only says whether one exists, in the environment or the OS keychain:

```bash
ruby "${CLAUDE_PLUGIN_ROOT}/exe/sloplint-judge" status >/dev/null 2>&1 && echo judge-available || echo judge-unavailable
```

- **Unavailable.** Run the plain check. Do not ask, do not mention the judge unless they asked for it, and say in the report that only the regex rules ran. If they ask how to set the judge up, tell them to run `sloplint-judge key set` in their own terminal and paste the key when it prompts. Never run that command yourself, and never ask for the key in the conversation.
- **Available, and they already said so.** If the request itself asks for the judge, the model, Jev, TypeSafe, or says to send it, or they said yes earlier in this conversation, run with `--judge`. Ask once per conversation, not once per file.
- **Available, and they said to stay offline.** "Offline", "without the judge", "don't send it anywhere": run the plain check and say the judge was skipped on request.
- **Available, and nothing was said.** Ask before running anything, in one question: sloplint can also run the judge, which sends the text to TypeSafe's API (api.typesafe.ai, about a tenth of a cent per thousand words) and catches the vague, restated and already-known sentences a regex cannot. Do that, or stay offline? Use AskUserQuestion where it exists. No answer, or no way to ask, means offline.

## Run it

With the judge:

```bash
ruby "${CLAUDE_PLUGIN_ROOT}/exe/sloplint" check --judge --markdown -o json PATH
```

The JSON is then an object: the notes under `notes` (the usual array, or keyed by path for several files) and what it spent under `judge` (backend, requests, token counts, cost). If it exits `2` with a message naming the sloplint-judge gem or `TYPESAFE_API_KEY`, the judge is not installed or not configured after all; run the plain check and say so.

Without the judge:

```bash
ruby "${CLAUDE_PLUGIN_ROOT}/exe/sloplint" check --markdown -o json PATH
```

When the judge did run, end the report with one line that says so: the text was sent to api.typesafe.ai, which backend answered, how many requests, how many tokens, and the cost, all from the `judge` object.

If it aborts with a message about needing Ruby 3.3, try each of these and use the first that reports 3.3 or later:

```
/opt/homebrew/opt/ruby/bin/ruby
/usr/local/opt/ruby/bin/ruby
$(rbenv which ruby)
$(asdf which ruby)
```

If none works, do not quote the error. Say that this needs a piece of software called Ruby and the copy on this Mac is too old, then offer to install it if Homebrew is present. An offer they can accept beats a command they cannot type.

## Read the result

- `0` — nothing flagged.
- `1` — notes found, on stdout as JSON.
- `3` — with `--judge`, the model could not be reached. Nothing was checked, not even the regex rules, so do not report a clean draft. Say the judge backend failed, quote its one-line reason, and offer to run the plain check.
- `2` — a usage or argument error, on stderr. Two common causes worth translating: the input was empty, meaning nothing reached the scanner and nothing was checked; or the file is not plain text or Markdown. A `.docx` is a zip archive and will fail here — say so in plain words and offer to read the document and scan its text instead.

## Report it

On `0`, name what was scanned and how much of it: "Checked your memo, 412 words — nothing flagged." A bare "looks clean" hides the case where the text arrived truncated or the wrong file got scanned.

On `1`, present the notes in document order, the order the JSON already gives you. Do not group them by rule: grouping scatters one paragraph's three problems across three sections, so the reader can never fix a paragraph in one pass. For each note, quote the `context` field — the match bracketed inside about 40 characters either side — then give one plain sentence from `suggestion`.

Do not print the rule id, the category, the severity word, or the `line:column` unless asked. They have no line 12; their document has pages. Offer that you can explain any one of them, and use `explain RULE_ID` when they take you up on it.

## Two standing rules

Never paste a scanned sentence into this repository. `CLAUDE.md` forbids real prose in the fixtures.

`sloplint rules` lists the whole catalog if someone asks what it checks for.
