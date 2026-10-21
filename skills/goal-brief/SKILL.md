---
name: goal-brief
description: Write a GOAL.md for a goal or unattended run. It holds the goal, a completion rule, a checklist and a pre-flight audit of external systems, context sources and exit checks, each mapped to a CLI command or skill or marked missing. Use when the operator asks for a goal brief, a GOAL.md, or a pre-flight audit before a goal, loop or overnight run.
---

# Goal brief

Same steps in Codex and Claude Code. The template is `references/GOAL-template.md`, next to this file. Every GOAL.md this skill writes has the template's headings in the template's order, in both harnesses.

The pre-flight audit answers one question before the run starts: what does the agent need so that it never has to stop and ask to be unblocked? It lists every external system, every context source and every exit check, and maps each one to a command or skill. Anything not wired is marked missing.

## 1. Inputs

1. The goal: one sentence or a short brief from the operator. If there is no goal, ask for one and stop.
2. The target repository: the path the operator names. If none is named, use the current folder when it is a Git repository. Otherwise ask and stop.
3. The output path: the path the operator names. If none is named, `GOAL.md` at the repository root.

## 2. Safety rules

1. Write exactly one file: the output path. Create no other file or folder anywhere, including notes and scratch files.
2. If the output path already exists, or its folder does not exist, ask the operator and stop. If the write is refused, do not retry another way. Report the refusal and stop.
3. Read only. Do not build, test, install, format or run project scripts. Do not run anything that uses the network.
4. Never commit. Do not run `git add`, `git commit`, `git stash`, `git checkout` or any other command that changes the repository.
5. Use only file reads, file listings and text searches, plus these commands: `git -C <repository> log -n 10`, `git -C <repository> --no-optional-locks status --short`, and `command -v <tool>` to see whether a tool is installed.
6. Do not open credentials: no `.env` files, keys, tokens or auth files.

## 3. Read the repository

1. Read these when present, in this order: `AGENTS.md`, `CLAUDE.md`, `README.md`, `PRD.md`, `PLAN.md`, engineering or architecture documents, the build manifest and its scripts (for example `package.json`, `go.mod`, `Makefile`), the `scripts/` folder, and the test folders.
2. Read the last 10 commits and the working tree state with the two git commands above.
3. Find what the goal touches: the files likely to change, the documents that own the requirements, and the checks the repository already defines.

## 4. Write the checklist

1. Each box is one requirement that a check can prove. Write it so that a reader can tell pass from fail.
2. Use three groups, numbered from 01 in each: `REQ` for behaviour a user sees, `TEST` for checks, `DONE` for finish conditions.
3. Include at least these `DONE` items: every checked box names its evidence; the repository's own full check passes; an agent that did not write the change reviews it.

## 5. Write the pre-flight audit

1. External systems: everything outside the repository the run touches, such as package registries, remote Git hosts, browsers, devices, deploy targets, other local services and the operator. If there is none, write one row with System `None found` and Mapped to `not needed`.
2. Context sources: every document, folder or note store the agent must know, each reachable by one command or skill. Include the operator's notes outside the repository when they matter.
3. Exit checks: every check that proves a checklist item, with the items it proves. Every `REQ` and `TEST` item appears in at least one exit check row.
4. The "Mapped to" cell holds exactly one of these:
   1. a CLI command in backticks, such as `npm test`. It counts only when `command -v` finds the tool and the repository defines or documents the command.
   2. `skill: <name>`. It counts only when that skill folder exists in this harness's skills folder (`~/.claude/skills` or `~/.codex/skills`).
   3. `missing: <what would wire it>`.
5. Number rows E1, E2 for external systems, C1, C2 for context sources and X1, X2 for exit checks.
6. The first line under "Pre-flight audit" is "Ready for an unattended run: yes." only when no row says missing. Otherwise write "Ready for an unattended run: no. Missing: " and the row numbers.

## 6. Fill and write the file

1. Copy the template. Replace every placeholder in angle brackets.
2. Keep every heading line exactly as the template writes it. In the title, replace `<repository folder name>` with the folder name exactly as it appears on disk, for example `my-app`, never "My App".
3. Add no heading, remove none and reorder none. No other line may start with `#`. Use no code blocks.
4. Write the file once, to the output path.
5. Compare `grep '^#'` of the new file with `grep '^#'` of the template. Every line after the first must match exactly. Fix the file if one does not.

## 7. Writing rules

1. Plain English. Short sentences, one idea each. Explain a technical term in plain words the first time.
2. No em dashes. Number every list and every table row.
3. Exact facts: paths, commit hashes, dates, command names and counts. Write "not checked" instead of guessing.

## 8. Reply

1. Give the output path and the ready line.
2. List each missing row with one line on what would wire it.
3. Say that nothing was committed and no other file was written.
4. Last line: "Next step: the operator reviews GOAL.md and wires the missing rows."
