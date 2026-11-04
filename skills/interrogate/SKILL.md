---
name: interrogate
description: "Use for \"interrogate\", \"adversarial review\", \"multi-model review\", \"challenge this\", \"stress test this code\", \"find blind spots\", or \"tear this apart\". Adversaries try to break a change or design, and only findings proven by a run survive."
disable-model-invocation: true
---

# Interrogate

Adversaries try to break a change or a design. A finding survives only when a run proves it. Report the findings. Do not apply fixes.

## Frame

The scope is what the user names. Otherwise it is the branch diff from its merge base with the base branch, through the working tree. State the intent with the **in-your-own-words** skill, from the user's message, the commits, and the PR description. Ask the user when the intent is unclear.

## Fan out

Run Phase A steps 3 and 4 and Phase B of the **best-of-n** skill, with four changes. Use the `interrogate-reviewers` role in place of `best-of-n-runners` in its `ctlhq-models get` and `ctlhq-models fallback` commands. Write the scope's uncommitted changes, new files included, to a patch file. From the repository root, run these lines, which record new files in a temporary copy of the Git index and leave the real index as it was:

```bash
set -e
patch="$(mktemp)"
index="$(mktemp)"
cp "$(git rev-parse --git-path index)" "$index"
GIT_INDEX_FILE="$index" git add --intent-to-add .
GIT_INDEX_FILE="$index" git diff --binary HEAD >"$patch"
rm -f "$index"
printf '%s\n' "$patch"
```

Tell each adversary to `git apply` the patch file in its own worktree before it starts. After Verify, remove the patch file and each adversary worktree with `git worktree remove --force <path>`. Keep a worktree that a kept finding's command needs, and name it in the output. Spawn each adversary with `subagent_type: "general-purpose"` in Claude Code, or with `spawn_agent` in Codex. In place of the best-of-n task and rationale, give each adversary the scope, the intent, and this brief, and never the author's report, your suspicions, or the fix history (the **commit-review** skill's section 1):

> Break this change. Prove each finding with a run against the real code, such as a failing test, a repro script, or command output that shows the wrong behavior. For a design or plan, run a prototype or probe the current tree. Keep repros in your own worktree. Every run uses a throwaway home folder, with no push, no write to the real home folder, and no call to a paid or external service. Report each finding with a title, the exact command, the output it printed, and the output the intent requires. Leave out anything you did not run. That covers style, naming, structure, and risks that need a future change to matter. No findings is a valid result.

## Verify

Verify each finding per best-of-n Phase F by rerunning its command, under the same limits as the adversaries. Keep a finding when the output shows the failure and the failure breaks the intent. Drop the rest. Merge findings that share a root cause.

Skip best-of-n Phases C, D, and E. Adversaries find different failures, so the verdict keeps every verified finding, not one adversary's list.

## Output

- **Intent.** The restatement.
- **Findings.** For each verified finding, the command, its output, how it breaks the intent, and the adversaries that found it. Say "no verified findings" when none survive.
- **Dropped.** For each adversary, the count of dropped findings and why.
