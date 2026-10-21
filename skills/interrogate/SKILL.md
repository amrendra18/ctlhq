---
name: interrogate
description: "Use for \"interrogate\", \"adversarial review\", \"multi-model review\", \"challenge this\", \"stress test this code\", \"find blind spots\", or \"tear this apart\". Multiple LLM reviewers challenge changes from independent angles."
disable-model-invocation: true
---

# Interrogate

Spawn one reviewer per configured model to adversarially review code changes. The adversarial signal comes from model diversity, not assigned personas. The deliverable is a synthesized verdict. Do NOT auto-apply changes.

## Step 1, Scope

Identify what to review from context:

- If the user points at specific files or a diff, use that.
- If on a feature branch, run `git diff main...HEAD` (or the appropriate base branch) for the full changeset.
- If the user's message references recent work, gather the relevant files.

Package the diff or file contents with any surrounding context files the reviewers need to understand the code.

## Step 2, Intent

Before spawning reviewers, state the intent in one clear paragraph from the user's message, commit messages, the PR description if one exists, and the code. If you're unsure about the intent, ask the user before proceeding.

## Step 3, Spawn Reviewers

Launch all reviewers in a single message with the subagent tool (`Agent` in Claude Code, `spawn_agent` in Codex), one per entry that `ctlhq-models get interrogate-reviewers` prints, labeled Reviewer A, B, and so on to match the entry count.

| # | Subagent | Default model |
|---|----------|---------------|
| 1 | Reviewer A | first `interrogate-reviewers` starting value |
| 2 | Reviewer B | second `interrogate-reviewers` starting value |

Each reviewer is a read-only subagent with `model` set to its entry from `get`. In Claude Code, use `subagent_type: "Plan"`, a built-in type without Edit, Write, and NotebookEdit that reads whole files. The built-in `Explore` type reads excerpts, and its own description rules out code review. In Codex, use `spawn_agent`. Tell every reviewer it is read-only in both hosts, because Codex has no read-only subagent type and `Plan` still has Bash. Omit `model` for an `auto` or `inherit-parent` entry, so that reviewer runs on the parent model. Reviewers are set up per the **blind-review** skill's section 1 (what a reviewer receives and never receives).

If the subagent tool rejects a configured entry, run `ctlhq-models fallback interrogate-reviewers <rejected-model>`, run that reviewer on what it prints, and say so. If it rejects a table default, rerun the command with `--valid` set to the valid names from its error message (keep the reasoning tier when you can), and open a separate PR to update the default starting values in `skills/ctlhq-setup/models.example.toml`. Do not block the review on the model-name issue. Never treat an alias entry as a rejected model or apply either fallback to it.

Read `references/reviewer-prompt.md` and fill in the same template for every reviewer with the stated intent, the diff or file contents, the rubric from `references/rubric.md`, and the code-quality lens from `references/code-quality-review.md`. Pick each subagent's reasoning level and fast or standard speed for the job, per the Subagents section of the **ctlhq-mode** skill.

## Step 4, Synthesize

As results come back, build a unified picture. Parse every reviewer's findings. Merge findings that describe the same issue differently, and note which models raised each one. Findings two or more models raised independently are the highest signal. Read a lone model's finding, but weight it accordingly. Note disagreements. If one model flags something and another explicitly says the opposite, that is context for the verdict.

## Step 5, Lead Judgment

You are the lead reviewer, a pragmatic senior engineer, not a neutral aggregator. Read `references/lead-judgment.md` for the full framework. Put every finding in one of four buckets, with the model(s) that raised it and a one-line rationale.

- **Act on**. Real issues affecting correctness, security, or maintainability given the actual goals. They would block a real PR.
- **Consider**. Legitimate, but you're not sure they outweigh the cost of addressing them now. Worth the user's attention.
- **Noted**. Technically valid but not actionable. Context-dependent, premature optimization, or low-impact at this stage.
- **Dismissed**. Wrong, nitpicky, or missing context, with a brief reason.

## Output Format

### Intent
> [The stated intent paragraph from Step 2]

### Reviewers
- Reviewer [label]: [model name], [N findings] (one bullet per reviewer)

### Act On
[Each: description, which models raised it, why it matters.]

### Consider
[Each: description, which models raised it, the tradeoff.]

### Noted
[Brief list.]

### Dismissed
[Each with a brief rationale.]

### Agreement Map
[Where models agreed and diverged, and what that pattern tells us.]
