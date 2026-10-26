---
name: run-method
description: Run a build, research or planning ask with one fixed method. Use when the operator asks to build, plan, research, review or finish a project, or says "do it end to end". A new project or idea starts with the start-project skill. Covers confirm, plan with a goal state, the milestone loop with supervised subagents, acceptance and hand-off.
---

# Run method

Same steps in Codex and Claude Code. Templates live in `references/`. Tools named here live in this repository's `bin/`.

This skill needs first-commit, a separate tool that creates the project's Git repository and installs its Git hooks (section 4). Get it from `https://github.com/amrendra18/first-commit`.

## 1. Confirm (before any work)

1. Read the named inputs for two to five minutes.
2. A new project or idea: run the `start-project` skill first. It ends with an approved `PLAN.md` and hands over to section 5.
3. Any other ask: reply with the ask as a numbered list, stated defaults the operator can veto, deliverables with paths, and one "not touched" line.
4. Open decisions go last, as numbered yes-or-no questions with one recommendation each. Wait for yes. This confirm reply, the plan's approval (section 3 step 4), and any later change of scope each wait for the operator's yes. Reversible steps inside an approved plan proceed without asking, as the `ctlhq-mode` skill's Autonomy section says. Ask in chat, also when the operator is away; never poll or wait on another channel.

## 2. Research and measure (when the plan needs facts)

1. Every finding carries a source and a confidence label. Say which angles produced nothing and how the gap was filled.
2. For shared tools and libraries, write a caller example with its expected result first. Use **technical-writing** for tutorials. Use that example to guide **architect** when designing interfaces.
3. Before setting any bar, measure on real data with a throwaway prototype. Keep the measurement report.
4. End with numbered decisions, one recommendation each.

## 3. Write done (before the first build)

1. When `PLAN.md` does not exist yet, copy `references/PLAN-template.md` to `PLAN.md`. Fill every section. Milestone 0 is the harness plus one real user journey driven on the real surface. Each "Done when" cell names the verification command and its exit codes. `ctlhq-plan-lint PLAN.md` exits 0.
2. Copy `references/PROMPT-template.md` when another agent, or a later session, will run the build.
3. Check that `AGENTS.md` holds invariants with named tests (a numbered "Invariants" section, each rule ending with "Test:" and the test that enforces it); add the missing ones.
4. Ask one question that names the plan by path: "Is `PLAN.md` the goal state? A yes also approves committing it. yes or no." Never retype the scope in the question; a retyped scope drops steps. On the yes, the main agent commits `PLAN.md` alone with `ctlhq-commit` and records the ledger row in section 10, citing that commit hash. Later approval questions cite `PLAN.md` at its last commit.

## 4. Bootstrap once (operator)

Hand the operator one pasted block with only the one-time setup that needs the operator: first-commit setup (it creates the repository and the hooks) and the permission allow rules for `git add` and `git commit` in that folder (`references/hooks-and-permissions.md`). The operator does no other repository work. Before the first milestone, run `ctlhq-preflight --repo <project>` (add `--need`, `--min-disk`, and `--service` for what the plan uses), then the project checks in `PROMPT.md` section 2. Every `missing` line, with its `fix:` line, and any other failure goes to `BLOCKED.md` before work.

## 5. Loop per milestone

1. Run independent workstreams in parallel, as the plan's "Workstreams and waves" table sets them. At every step, look for more safe parallel work; investigations, plans, and reviews need no wave. Keep dependent work in order. Before builders start, the main agent gives each writable file and shared resource one owner. Shared resources include the main agent's own writes, sessions, ports, and test data. Brief one builder per workstream with the 8-part brief (`references/subagent-templates.md`). Save each brief under `.local/briefs/`. Each builder creates its own worktree of the assigned repository. Before editing, the builder compares `git rev-parse --path-format=absolute --git-common-dir` with the assigned repository's value, and `git rev-parse HEAD` with the assigned full base commit. A mismatch stops the builder.
2. While they work, write the review script and the next brief.
3. The main agent merges the builders' diffs into one integration worktree, resolves conflicts, and runs the full gate on the merged tree. Nothing changes the integration worktree while its checks run. Any later change needs a new check of the updated tree.
4. Review yourself: the script from outside the repository, the code read, one number recomputed, the five questions answered. In a project with a harness (`scripts/verify`), also run it. A milestone is done only with a harness run whose evidence folder (`.local/verify/<UTC time>/`) and exit code the reply names.
5. Spawn a fresh reviewer (`blind-review` skill) on the merged diff. Save its report under `.local/reviews/`.
6. Fix list and re-review. Each review pass inside a round runs the fast gate; the full gate runs once, on the final tree, before the commit sequence. Record the hash in `PLAN.md` section 7. When the milestone opens or closes an open item, update the README's "Open decisions" section in the same commit.
7. After the round, run `ctlhq-worktree-audit --no-fetch -b <integration branch>` and remove each builder worktree in bucket `safe` with an empty DIRTY column (`git worktree remove <path>`).
8. Continue to the next milestone without waiting. Stop only for a refusal you cannot work around; write `BLOCKED.md` and keep working on the rest.

## 6. Accept

1. Give the operator `scripts/hand-journey` (`references/hand-journey-template.sh`): each step prints "want" next to "got".
2. Report: status line, numbers against bars, the hand journey, the last harness run's evidence folder where the project has `scripts/verify`, what is not done. The report is not acceptance.
3. Record the operator's own words and the date in `PLAN.md` section 10 as a ledger row, with the plan's path, its hash, and the exact scope accepted. Cite that row in `PLAN.md` section 3. An acceptance covers only its row's scope; anything else stays open.
4. After each accepted milestone, before the next feature starts, run the `project-audit` skill on the accepted commit, under the plan's "Audit rule" (its "Fix kind" line: a fix that adds behaviour opens a milestone).

## 7. Hand off or end

1. Before the last reply of any work block, check that the README's "Open decisions" section lists every open item with its owner, `PLAN.md` section 7 holds the state and the session id, and `BLOCKED.md` holds every blocker. The next command goes only in the reply's "Next step" line.
2. For another agent: `PLAN.md`, `PROMPT.md`, `AGENTS.md`, the launch sentence, and where it stops (`REPORT.md`).
3. When a reply names a file you wrote, give its absolute path and a gist of at most three lines: what it holds and what the operator does with it. An HTML deliverable gets a clickable `file:///` link to its absolute path.
4. Last line: "Next step: <who> <action>".
