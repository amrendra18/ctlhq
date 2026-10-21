---
name: start-project
description: Start a new project from an idea and its goals. Offer name options for the operator to pick, challenge the goals with numbered questions, build a clickable mock-up when the product has a screen, and write a PLAN.md that ctlhq-plan-lint accepts, then ask for approval and hand over to run-method. Use when the operator brings a new idea or asks to start a new project.
---

# Start a project

From an idea to an approved `PLAN.md`. The build itself then runs with the `run-method` skill. Tools named here live in this repository's `bin/`. Paths such as `skills/name-options/SKILL.md` are relative to this repository (the folder that holds this `skills/` directory), wherever the session starts.

This skill needs first-commit, a separate tool that creates the project's Git repository and installs its Git hooks (sections 3 and 5). Get it from `https://github.com/amrendra18/first-commit`.

## 1. Name (first reply)

Skip this step when the operator named the folder.

1. Read `skills/name-options/SKILL.md` and follow its steps 2 to 5 (it cannot be invoked as a skill). Offer 5 to 10 names. The operator picks by number.

## 2. Challenge (same first reply)

1. Restate the goals and use cases as a numbered list, in the operator's own words where they fit.
2. Spawn a fresh reviewer on the model `ctlhq-models get planners-and-reviewers` prints (in Codex, add `--host codex`; the `blind-review` skill, section 4, says how to spawn it there). Give it only the operator's idea and the inputs the idea names, never your own questions. It returns numbered questions with recommendations and a list of push-backs. Save its brief to a temporary file before spawning, and copy the brief and its report to `.local/briefs/` and `.local/reviews/` once the folder exists. While it works, write your own list.
3. Merge both lists: drop duplicates, keep each point that would change the product or the plan, order by impact, and name each disagreement between the two lists with your recommendation.
4. For each unclear, conflicting, missing, or weak point, ask one numbered yes-or-no question with a recommendation. Cover the user journeys, edge cases (empty, large, error, first run), platform, and what is out of scope. For a product with a screen, ask whether it ships an app or site icon.
5. Where you disagree with the ask, say so and give the reason. The goal is a plan the operator will not need to change later.
6. Wait for the operator's answers. Record each one in `PLAN.md` section 8 "Decisions" once the file exists: the date, the question, and the answer in the operator's words.

## 3. Create the folder

1. Create `~/projects/<picked name>` (the folder `ctlhq-name-check` scanned), or the folder the operator names. Agents do not run `git init`; first-commit setup in the operator's block (`run-method` section 4) creates the repository. Until then, write the files below in the folder.
2. Copy `skills/run-method/references/PLAN-template.md` from this repository to `PLAN.md`.

## 4. Mock-up and icon (when the product has a screen)

1. Run the `design-options` skill in screens mode. When the operator's answer in section 8 says the product ships an app or site icon, also run its icon mode.
2. Continue only after the operator accepts the mock-up in their own words. Record the acceptance in section 8, quoting the operator.

## 5. Write the plan

1. What and why: run `project-foundation` in Create mode. For a personal project use its Single file mode (`README.md` plus `AGENTS.md`), so `PRD.md`, `ENGINEERING_PLAN.md`, and `ENGINEERING_PRINCIPLES.md` are not created. Copy what, why, how, "Complete, in plain words", and "Not part of complete" into `PLAN.md`.
2. The harness: plan `verify-setup` as milestone 0, the harness plus one real user journey driven on the real surface. Its `scripts/verify` row opens "Repeated jobs".
3. Repeated jobs: one row per job this project runs more than once, with its command and the check that proves it done.
4. Workstreams and waves: give every writable file and shared resource one owner. Rows in one wave run in parallel.
5. Hooks: first-commit guards every commit and push. When `first-commit` is not on `PATH`, copy the install block from first-commit `README.md` section "First run" into the operator's block. `first-commit setup --dry-run`, `setup`, and `doctor` follow there, pinned to the commit of first-commit's latest tag (`skills/run-method/references/hooks-and-permissions.md` section 3). Setup leaves a `*.first-commit-proposal.md` beside each document this step wrote; merge it into that document and delete it.
6. Run `ctlhq-plan-lint PLAN.md` and fix every line it prints until it exits 0.
7. Run the `blind-review` skill on `PLAN.md` with the `planners-and-reviewers` model. Fix its findings, rerun `ctlhq-plan-lint`, and only then show the plan to the operator.

## 6. Approve and hand over

1. The reply gives the `PLAN.md` path, one "not touched" line, the open questions from section 9 as numbered yes-or-no questions, and then `run-method` section 3 step 4's approval question.
2. On the yes, record the section 10 row with "commit: pending first-commit setup", and give the operator `run-method` section 4's block.
3. When the operator reports the setup done, commit `PLAN.md` alone with `ctlhq-commit`, fill the hash into the ledger row, and continue with `run-method` section 5, milestone 0.

## Bookkeeping files

The project's bookkeeping files are fixed, and no others are created:

1. `README.md` (with "Open decisions"), `AGENTS.md`, `PLAN.md` (plan, milestones, decisions in section 8, approvals ledger in section 10), `BLOCKED.md`.
2. `mock/index.html` for a product with a screen, kept as the design reference. The harness never drives it.
3. `scripts/verify`, `verify/features/`, `scripts/hand-journey`, and first-commit's config files.
4. `PROMPT.md`, `REPORT.md`, and `GOAL.md` only for a hand-off or an unattended run.
5. Working notes (briefs, reviews, verify evidence, gate results, audit reports, commit receipts, mock screenshots) go under `.local/`. A checklist, method, journal, or audit file goes into `PLAN.md` or `.local/`, never into a new top-level file.
