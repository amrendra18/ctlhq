---
name: first-push
description: "Check a local repository before its first push to GitHub, private or public, and on every later push. The command checks every commit for personal data, a README at the tip, and a LICENSE in every commit, and confirms the push target belongs to the GitHub owner named in the settings file (~/.ctlhq/first-push.toml, key github_owner). A finding in an old commit is reported; rewriting history stays the operator's decision. Use before a repository's first push, before making a repository public, or to install the pre-push hook."
disable-model-invocation: true
---

# First push

A push copies the whole history, so every commit must be clean.

## Tool

`bin/ctlhq-first-push` does every check and explains each finding. `--help` lists every option.

## When to run it

1. Before a repository's first push to GitHub.
2. Before a private repository becomes public.

## Modes

1. `bin/ctlhq-first-push` checks the whole history now. Exit 0 means ready, 1 means findings, and 3 means no verdict.
2. `bin/ctlhq-first-push hook install` runs the same check before every `git push`.

## Steps

1. Run `bin/ctlhq-first-push` and read its exit code directly.
2. Follow each `fix:` line, then the `next:` line. Rerun after each change.
3. Ask the operator the three calls the command cannot make. Never quote a private value.
   1. Is the term truly public? If yes, it goes in `public_terms`.
   2. Which license should the repository use?
   3. Should the history be rewritten, or should a fresh repository start?
