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

## Run it

```bash
ruby "${CLAUDE_PLUGIN_ROOT}/exe/sloplint" check --markdown -o json PATH
```

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
- `2` — a usage or argument error, on stderr. Two common causes worth translating: the input was empty, meaning nothing reached the scanner and nothing was checked; or the file is not plain text or Markdown. A `.docx` is a zip archive and will fail here — say so in plain words and offer to read the document and scan its text instead.

## Report it

On `0`, name what was scanned and how much of it: "Checked your memo, 412 words — nothing flagged." A bare "looks clean" hides the case where the text arrived truncated or the wrong file got scanned.

On `1`, present the notes in document order, the order the JSON already gives you. Do not group them by rule: grouping scatters one paragraph's three problems across three sections, so the reader can never fix a paragraph in one pass. For each note, quote the `context` field — the match bracketed inside about 40 characters either side — then give one plain sentence from `suggestion`.

Do not print the rule id, the category, the severity word, or the `line:column` unless asked. They have no line 12; their document has pages. Offer that you can explain any one of them, and use `explain RULE_ID` when they take you up on it.

## Two standing rules

Never paste a scanned sentence into this repository. `CLAUDE.md` forbids real prose in the fixtures.

`sloplint rules` lists the whole catalog if someone asks what it checks for.
