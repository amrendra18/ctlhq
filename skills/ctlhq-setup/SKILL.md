---
name: ctlhq-setup
description: Configure which models ctlhq uses per role and at what reasoning budget. Detects your available models and writes the models file (`~/.ctlhq/models.toml`) that overrides the skill defaults. Use for /ctlhq-setup, "configure ctlhq models", "ctlhq budget", or changing ctlhq's model choices.
---

# Setup ctlhq

Write `~/.ctlhq/models.toml`, the models file that sets ctlhq's model per role. Every skill names a role (`judgment-and-prose`, `swarm-workers`, and the others that `bin/ctlhq-models show` lists) and reads the model for that role from this file, falling back to the default when the file or the line is absent.

## Tool

`bin/ctlhq-models` (in this skill's folder, or `ctlhq-models` when the ctlhq `bin/` folder is on PATH) reads and writes the models file. Drive it instead of editing the file by hand, so the shape stays valid and every role line keeps its comment. `bin/ctlhq-models --help` lists every command, flag, rule, and exit code; act on each `fix` and `next` line it prints. A line marked `(operator, changes <file>)` changes the models file: in this skill, run it only where a step below says to, after the confirmation that step requires. `bin/ctlhq-doctor` reports what this machine has and what ctlhq needs.

## Steps

### 1. Detect available models

Enumerate the model names you can pass to the subagent tool (`Agent` in Claude Code, `spawn_agent` in Codex) in this session. That is the dependable source. In Claude Code the subagent tool accepts `sonnet`, `opus`, `haiku`, and `fable`; `bin/ctlhq-models known-values` prints that list. In Codex the names differ. If the host also exposes a models API or CLI that lists the user's entitled models, prefer it for completeness. If you cannot detect any, ask the user to paste the names they have access to. Never write a real model name you have not confirmed is available. The aliases `inherit-parent` and `auto` are always valid even though they are not detected names.

### 2. Load current state

The default role-to-model mapping is the `default` column of `bin/ctlhq-models show`. If `~/.ctlhq/models.toml` already exists, run `bin/ctlhq-models validate` and then `bin/ctlhq-models show`, and treat the `budget` line and the role values as the current choices. Otherwise start from those defaults (`show` prints them and says the file is missing). `validate` reports a line from a retired role, such as `how-critics`, with a `fix` line (`bin/ctlhq-models prune`). Run that command and note each dropped line for step 3.

### 3. Budget, map, and confirm

**(a) Ask for a budget.** Prefer asking the operator through the host's question tool (`AskUserQuestion` in Claude Code, `request_user_input` in Codex) over free text. Offer these four options with these exact labels, and name the current budget when the models file records one. With no models file, say that `large` matches the skill defaults.

- `unlimited (max reasoning)`
- `large (xhigh reasoning)`
- `medium (high reasoning)`
- `small (medium reasoning)`

**(b) Apply it.** Build the working table from the skill defaults, and on a re-run keep any role you changed by family, list, or alias (`inherit-parent`, `auto`). `unlimited`, `large`, `medium`, and `small` set the effort level of every real model, panel entries included, to `max`, `xhigh`, `high`, or `medium`; `bin/ctlhq-models budget <label>` records the label and prints the effort level it maps to. In Claude Code the model names (`sonnet`, `opus`, `haiku`, `fable`) carry no effort of their own; the host passes the effort level as a separate parameter when a subagent is spawned, so the `budget` line alone carries the choice and the role values stay as they are. When a role value carries the effort as a token in its name (for example `my-model-xhigh`), run `bin/ctlhq-models budget <label> --rewrite-names` instead. If a rewritten name is not a detected name, use the same family's detected name with the highest effort at or below the target, else mark the role as needing a choice. `inherit-parent` and `auto` do not change. So, with effort-token names, `unlimited` turns an `xhigh` name into its `max` variant (`my-model-xhigh` becomes `my-model-max`). A family that tops out at `xhigh` stays at `xhigh` under `unlimited`, with fast mode kept when the host offers it. `large` keeps `xhigh` names as they are. `small` turns them into their `medium` variants, fast mode kept when the host offers it.

**(c) Show the roles and confirm.** Run `bin/ctlhq-models show` and show every role with its model, marking any real model name not in the detected set as needing a choice (`bin/ctlhq-models validate --allow <detected names>` lists them). Also list each line step 2 dropped. Ask whether to accept as-is or change specific roles, offering the detected models plus `inherit-parent` and `auto` (both mean: this role runs on the parent chat model) as the options. Prefer asking the operator over free text. For panel roles (`best-of-n-runners`, `architect-runners`, `interrogate-reviewers`) the value is a list, and one subagent runs per entry, alias entries included, so the list length sets the count. `best-of-n-cross-judge-pool` is also a list, but best-of-n selects one value from it whose model family differs from the parent's when possible. `swarm-workers` is the default model for every worker unless a race or comparison assigns another model per arm.

**(d) The role map.** Four roles split the work between building and planning. `builders` (default `opus`) writes code. `planners-and-reviewers` (default `fable`) writes deep-dive plans and reviews. The main agent moderates: it briefs, reviews, and commits, runs on the session's own model, and has no role line. Each of the two roles has a `-limit-fallback` role: the model to use when the role's model hits its usage limit. `planners-and-reviewers-limit-fallback` defaults to `opus`. `builders-limit-fallback` defaults to `inherit-parent`, which here means the main agent does the build work itself (step 8). These four lines carry a role-map comment. Show these four roles with the other roles and confirm them the same way. The `[codex]` table at the end of the models file holds the Codex values, such as `planners-and-reviewers = "gpt-6-astra"`. In Codex, every `ctlhq-models` call adds `--host codex`.

### 4. Validate

Every real model name written must be in the detected set. `inherit-parent` and `auto` always pass. Run `bin/ctlhq-models validate --allow <detected names, comma-separated>`. If a chosen real model name is not available, stop and ask again, offering the name its `fix` line proposes.

### 5. Write the models file

Write `~/.ctlhq/models.toml` with a `budget` line holding the chosen label (the comment on that line maps each label to its target effort) and one line per role, using the same role keys ctlhq-mode uses. Overwrite the whole file so re-runs stay idempotent: `bin/ctlhq-models init --budget <label> --force` rewrites it from the defaults, then one `bin/ctlhq-models set <role> <value>` per role whose confirmed value differs from the default, the values kept from an earlier run included (`a,b` for a list role). The tool keeps the comment on every role line. `models.example.toml` next to this skill holds the shape. `bin/ctlhq-models show` prints each role with its default.

### 6. Confirm

Tell the user the models file was written and that it applies to new sessions. Re-running this skill updates it. `bin/ctlhq-models show` prints what was written.

### 7. Offer a verification skill (optional)

Check whether the project has a way to drive the real app for proof (a `verify-*` skill, or an existing harness). If not, offer once: "want a project-local verification skill, so agents can drive the app the way a user does and prove changes work? I can generate one with /verify-setup." On yes, invoke `/verify-setup` (resolves wherever ctlhq is installed: workspace, user, or the ctlhq repository). On no, move on without pushing.

### 8. When a model hits its usage limit

The host refuses a spawn because the role's model reached its usage limit. This differs from `fallback` above, which handles a model name the host does not accept.

1. Run `bin/ctlhq-models get <role>-limit-fallback` (for example `get planners-and-reviewers-limit-fallback`) and spawn on what it prints. Say so in the status line.
2. When it prints `inherit-parent` for `builders`, pause the subagents. The main agent does the build work itself, still through the review and commit sequence.
3. Write "subagents paused: <role> model hit its usage limit at <time>" as a list entry in the project's `BLOCKED.md`, with the role and the model.
4. Resume subagents only when the operator says so in their own words. Then remove the paused line from `BLOCKED.md`.
