# Audit Report Contract

Produce one concise report backed by the five reviewer records. The report must let a user decide what to fix, what to leave alone, and what remains unknown.

The report has the 11 sections below, under `## <n>. <name>` headings. `bin/ctlhq-audit-report check REPORT.md` checks the mechanical parts (the headings, the findings index, the routes, and section 11) and prints the round verdict. Run it before delivering the report, and fix every problem it prints.

## 1. Audit frame

State:

- Scope and selected depth
- Current commit and comparison base when available
- Working-tree state and whether uncommitted files were included
- Product documents and repository instructions used
- Checks run, checks skipped, and why
- Material evidence limits
- The round number, the grant, and the bar from section 11

## 2. Executive result

Summarize the product's current fitness, the most important risk, the largest simplification opportunity, and the next recommended action. Do not use a numeric score unless the caller supplied an accepted scoring system. The lens scorecard in section 10 is this skill's accepted scoring system; keep its numbers in section 10.

## 3. Product and system map

Give a compact map of users, supported interfaces, critical journeys, main components, state owners, and external boundaries. Include enough context to understand the findings. Name the map's source: the project guide with its manifest `sourceCommit`, or `bin/ctlhq-repo-map` output with its commit. Guide errors found during the audit are findings in section 4.

## 4. Findings

Order findings by severity, then confidence and user impact. Use stable finding IDs such as `PA-001`. A finding carried from an earlier round keeps its ID.

Section 4 opens with the findings index, one row per finding (a header with no rows when there are none):

| # | ID | Title | Severity | Fix kind | Route |
|---|---|---|---|---|---|
| 1 | PA-001 | Saving on a full disk drops edits and shows "Saved" | high | change | fix |

The row above is an illustration of the shape, not evidence.

Then each finding gets a `### PA-001: <title>` block. Every finding contains:

- **Title:** One concrete problem
- **Lens:** Owning reviewer contract
- **Severity:** Critical, high, medium, or low
- **Confidence:** High, medium, or low
- **Evidence:** Exact files, symbols, commands, behavior, or measurements
- **Impact:** Affected user, data, system, or maintenance outcome
- **Trigger:** A realistic use case, stress case, failure, or abuse path
- **Reason:** The violated requirement, risk boundary, or unnecessary cost
- **Recommendation:** The smallest complete correction
- **Validation:** How to prove the correction and prevent regression

Fix kind and route live in the index only. Keep uncertainty in the finding. Do not inflate severity to compensate for weak evidence.

### Severity

The scale is fixed, so grading does not move between rounds. Each level has one example (illustrations, not evidence):

| # | Level | Meaning | Example |
|---|---|---|---|
| 1 | Critical | Credible immediate risk of severe data exposure, destructive loss, system compromise, or complete failure of the core product with no safe recovery. | The pre-push secret scan skips the first push of a new branch, so a committed API token reaches the public remote. |
| 2 | High | A core journey, major trust boundary, or important recovery path can fail with serious user or operational impact. | Saving a project on a full disk drops the edits, and the app still shows "Saved". |
| 3 | Medium | A supported case is incomplete, fragile, needlessly costly, or likely to cause a material maintenance or scaling problem. | The import command fails on a path with a space, and the README lists such paths as supported. |
| 4 | Low | A bounded issue has real value to fix but limited current impact. | The help text names a renamed flag; the command still accepts the new flag. |

Grading rules:

1. Grade the user or system outcome. A pattern found in many places is one finding with its places listed, graded once.
2. A style, naming, or comment problem is low, unless it hides a wrong result. Then grade the wrong result.
3. A finding carried from an earlier round keeps its severity unless its evidence changed. A regrade says what changed.
4. When two levels fit, choose the level whose meaning and example match the evidence, and say why in **Reason**.

### Fix kind

| # | Kind | Meaning |
|---|---|---|
| 1 | remove | Deletes code, files, dependencies, or text. Behavior narrows to what was intended. |
| 2 | change | Corrects existing behavior or text. It adds no check, scan, mode, option, or rule. |
| 3 | add | Adds behavior (a check, scan, mode, option, rule, or dependency). |

An `add` fix is a feature, so it opens a milestone in the plan instead of an audit fix: a `PLAN.md` milestone row with its own "Done when" and State `planned`.

### Route

| # | Route | Meaning |
|---|---|---|
| 1 | fix | The agent fixes it in this round. Only a `remove` or `change` fix that is reversible and crosses no privacy or security boundary. |
| 2 | milestone | An `add` fix inside the accepted scope. It becomes a plan milestone. Only an `add` fix is routed here. |
| 3 | decision | The fix needs kept authority (a new permission, a delete that Git cannot undo, an external write, or a product choice). It is a numbered decision in section 8. |
| 4 | record | A low finding kept for later. Only low findings may be recorded. |

With `Grant: none` (section 11), the route is the proposed next step, and nothing is fixed.

### Confidence

- **High:** Reproduced or directly proved by current behavior and repository evidence.
- **Medium:** Strong code or design evidence exists, but a runtime condition or external assumption was not reproduced.
- **Low:** Plausible concern with incomplete evidence. Usually place it under open questions unless the potential impact justifies a finding.

## 5. Simplification and removal plan

Group duplicate code, dead content, unnecessary files, excess layers, and avoidable dependencies. For every removal candidate, give the proof checked, canonical replacement, prerequisites, risk, and verification.

Order work so later removals depend on already-proved behavior rather than deleting several safeguards at once.

## 6. Test and evidence portfolio

Include the behavior-to-evidence matrix from the Tests and Evidence reviewer. Separate actions into:

- Tests to keep
- Tests to combine
- Tests to replace
- Tests to remove
- Missing tests to add

Each combine, replace, or remove action must state which remaining evidence protects the behavior.

## 7. Coverage ledger

Show that every required topic was considered. A coverage group is each bold named bullet under `Required coverage` in the five reviewer contracts. Use `finding`, `checked`, `sampled`, `not verified`, or `not applicable`. Give a short evidence note for each status.

Include every required coverage group from all five reviewer contracts. `Checked` means the evidence required by the chosen depth was inspected and no material finding was confirmed. `Sampled` is allowed only for a quick audit and means partial evidence found no confirmed issue. `Not applicable` needs a reason. Never turn `not verified` into `checked` or `sampled` because time ran out.

## 8. Open questions and limits

List missing evidence, blocked checks, disputed findings, external assumptions, and decisions that need the caller. Separate them from confirmed findings.

Number each decision, and name the finding IDs it covers. Each decision says what changes for the operator's result in one sentence, gives the options and one recommendation, and asks yes or no.

## 9. Ordered action plan

Recommend the smallest safe sequence. Put user harm, security, data integrity, and recovery before cleanup. Put evidence needed for safe deletion before the deletion. State which steps can be done independently. Group the steps by route: the fixes for this round, the milestones to open, and the decisions to wait for.

## 10. Lens scorecard

Give one short table, one row per lens, five rows in the lens order of the reviewer contracts:

| # | Lens | Score | Why | Path to 10 |
|---|---|---|---|---|
| 1 | Product and User Experience | 6/10 | 1 high (PA-002), 1 medium (PA-005), 0 not verified; capped at 6 by the high | PA-005 (small), PA-002 (medium) |

The row above is an illustration of the shape, not evidence.

Score each lens with this rule, so two runs on the same findings give the same number:

1. Start at 10.
2. Subtract for each confirmed finding the lens owns: critical 4, high 2, medium 1, low 0.5. A merged finding counts once, in its owning lens. Open questions do not count.
3. Subtract 1 for each of the lens's coverage groups marked `not verified` in the coverage ledger.
4. Cap the score at 3 when the lens has a critical finding, and at 6 when it has a high finding.
5. Round down to a whole number. The lowest score is 0.

"Why" gives the counts behind the score in one line: severity counts with finding IDs, and the `not verified` count. "Path to 10" lists the smallest set of changes that brings the score back to 10: the finding IDs to fix and the checks to run for `not verified` groups. Order it by effort, smallest first, and label each item small (one file or one command), medium (several files in one component), or large (several components, or it needs a caller decision). A lens at 10 writes "none needed".

## 11. Rounds and stop

Give the grant, the bar, one row per round so far, and the verdict:

```
Grant: fixes (PLAN.md section 10, row 12)
Bar: 0 high, 0 medium. Critical counts as high.

| # | Commit | Critical | High | Medium | Low | Serious |
|---|---|---|---|---|---|---|
| 1 | 647fa53 | 0 | 2 | 12 | 21 | 14 |

Verdict: continue
```

The block above is an illustration of the shape, not evidence.

1. `Grant: none` marks a read-only request. Its verdict is `report only` whatever the counts, and it needs no Bar line. `Grant: fixes (...)` names the approval row in `PLAN.md` section 10 or the approved `GOAL.md`.
2. The bar names high and medium only. A bar that counts low findings, or "0 findings", is refused. Critical must reach 0.
3. A one-off audit has one row.

After the report, follow "After the report" and "Rounds and stop" in the skill.
