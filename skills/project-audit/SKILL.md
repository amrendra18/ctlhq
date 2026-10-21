---
name: project-audit
description: Review a whole software repository or a PR or commit range through product, user experience, security, reliability, architecture, scalability, repository hygiene, test-evidence, and code craft (style, naming, static checks, comments) lenses. Use for a fresh-eye, adversarial, simplification, readiness, or thorough repository audit, and for the audit-and-fix rounds that follow when the caller's grant covers fixes. Do not use for a narrow code review whose question and files are already defined.
---

# Project Audit

Produce an evidence-based audit before proposing implementation work. Find material gaps, needless complexity, and the smallest safe improvement set. Preserve accepted product intent and distinguish facts from inference.

## Tool

`bin/ctlhq-repo-map` (a symlink to `skills/project-audit/bin/ctlhq-repo-map`) builds the starting map when the repository has no project guide. It is read-only. `ctlhq-repo-map --help` lists its seven sections and exit codes. Its section 7 holds the verification harness facts for workflow step 3. Choosing which entry points and tests matter stays with the lead reviewer.

`bin/ctlhq-audit-report check REPORT.md` refuses a report that breaks the report contract and prints the round verdict. It is read-only; `--help` lists the rules.

## Required choices

Determine the review scope first:

- Review the whole current repository when the caller gives no narrower scope.
- Review the named PR, branch, commit, or range when the caller names one. Include surrounding code when it is needed to judge the change correctly.

Require the caller to choose `quick`, `standard`, or `deep`. There is no default depth. If depth is missing, ask one short question and wait before auditing.

The first deliverable is a report. Until the report is delivered, the audit makes no edits, removals, installs, or external changes. Read-only inspection and existing safe repository checks are part of the audit. What happens after the report depends on the work grant. A work grant is an approval row in `PLAN.md` section 10, or an approved `GOAL.md`, that covers fixes.

## Read the audit contracts

Read all three references before starting:

- [Depth and evidence](references/depth-and-evidence.md) defines the work required at each depth and the rules for independent reviewers.
- [Reviewer contracts](references/reviewer-contracts.md) defines the five review lenses and their complete topic ownership.
- [Report contract](references/report-contract.md) defines findings, severity, confidence, the test portfolio, the final coverage ledger, and the lens scorecard with its scoring rule.

Repository instructions and accepted product documents remain authoritative. Read them before judging the implementation. Treat missing, contradictory, or stale product documents as evidence to report, not permission to invent a different product.

## Lead reviewer workflow

1. Record the scope, chosen depth, current commit, working-tree state, and any comparison base. Preserve unrelated user changes.
2. Find the starting map before the lenses run. Look for a project guide (the project-guide skill's output): `docs/project-guide/manifest.json`, or any tracked `manifest.json` that holds a `guideRoot` key. When a guide exists, run its checker (`python3 <project-guide skill>/scripts/check_guide.py .`, read-only) and use the guide as the starting map. Compare its claims with the code; every place the guide is wrong or stale becomes a finding, owned by the lens whose topic it misstates. When no guide exists, run `bin/ctlhq-repo-map` and use its sections as the starting map.
3. Build a shared evidence pack from repository instructions, product documents, user journeys, tracked files, entry points, dependencies, tests, automation, deployment material, and safe check results. Include the verification harness facts from `bin/ctlhq-repo-map` section 7, run even when a project guide exists: whether `scripts/verify` exists, whether `verify/features/` holds a feature map, and the newest `.local/verify/` evidence folder with its age in days. A missing harness or a missing map is a finding, owned by the Tests and Evidence lens.
4. Run five independent review lenses: Product and User Experience; Security and Reliability; Architecture, Scalability, and Repository Hygiene; Tests and Evidence; Code Craft.
5. When subagents are available, assign one lens to each independent reviewer for `standard` and `deep` audits. Schedule reviewers in waves when capacity is lower. Give them the scope, depth, repository evidence, and their contract. Do not seed them with suspected findings or another reviewer's conclusions. Reviewers are set up per the **blind-review** skill's section 1 (what a reviewer receives and never receives).
6. For `quick`, cover all five lenses. Subagents are optional. Keep the passes separate even when one agent performs them.
7. Verify every material finding against current repository evidence. A `critical` or `high` finding needs a second check by the lead or a reviewer who did not originate it.
8. Merge findings that share one cause. Resolve disagreement using evidence and record important uncertainty.
9. Deliver one report that follows the report contract, including the lens scorecard (one numbered row per lens: score out of 10, why, and path to 10). Score with the rule in the report contract so two runs on the same findings agree. Run `bin/ctlhq-audit-report check` on it first and fix every problem it prints.

The lead owns orchestration and synthesis. The five reviewers own independent analysis. The lead may run shared tests once and give every reviewer the results, which avoids duplicate work and unsafe concurrent commands.

## After the report

1. Without a work grant, the audit ends at the report. Section 11 says `Grant: none`.
2. With a work grant, the agent fixes every finding routed `fix`, without asking.
3. An `add` fix opens a milestone row in `PLAN.md` (State `planned`, its own "Done when"). The agent goes ahead with it when it is inside the accepted scope.
4. A finding whose fix needs kept authority becomes a numbered decision for the operator, with one recommendation. Kept authority is a new permission, a delete that Git cannot undo, an external write, or a product choice. The agent keeps fixing the rest while the decision waits.
5. The fixes go through the project's gate. The commit follows the project's commit rule; a builder hands the fixed tree back instead of committing. Then the next round starts.

## Rounds and stop

1. Write the stop rule in the round 1 report, before round 1 starts. When the work grant covers fixes and a `PLAN.md` exists, copy it there too. The default bar is 0 high and 0 medium; critical counts as high.
2. Each round is a fresh audit of the fixed commit, graded with the fixed severity scale in the report contract.
3. Low findings are recorded and fixed when cheap. Low findings never keep the loop running.
4. Refuse "0 findings of any severity" as a bar: fresh reviewers probe deeper each round, so new low findings keep appearing.
5. The verdict from `bin/ctlhq-audit-report check` decides the next step. On `bar met` the loop ends. On `continue` the agent fixes, then runs the next round.
6. On `stop and go to the operator`, the high plus medium count failed to fall 2 rounds in a row (it stayed the same or rose). The agent stops the loop and sends the operator the counts per round, with the findings that did not go away.

## Finding rules

A finding must include concrete evidence, affected user or system behavior, a realistic trigger or stress case, a focused recommendation, a verification method, severity, and confidence.

- Tie product suggestions to accepted users, goals, journeys, or a demonstrated risk. Put unsupported product ideas under open questions.
- Label projections about scale, performance, or abuse as inference unless measurements prove them.
- Do not call code or a file dead from text search alone. Check entry points, imports, dynamic discovery, packaging, configuration, supported platforms, migrations, public interfaces, tests, and relevant history.
- Do not call tests duplicates because their text looks similar. Compare the behavior, risk, boundary, and failure signal they protect.
- Prefer a smaller set of high-confidence findings over a long cleanup wish list.
- Record important areas that were checked and had no finding. Record anything that could not be verified.

## Safety and stopping conditions

Use the repository's existing checks when they are safe and fit the chosen depth. Ask before adding dependencies, using network services, touching production or real user data, changing the host, or running a command with material side effects.

Stop and report the limit when required evidence is unavailable or a safe check cannot run. Lack of evidence is not proof that an area is safe.
