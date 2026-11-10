---
name: maintain-formal-verification-skill
description: "Bring project verification back in line with code changes and distinguish model drift from code defects. Use for /maintain-formal-verification-skill or is the model still true to the code. Also use after merges or refactors touched verified code without rechecking it."
disable-model-invocation: true
---

# Maintain a formal verification skill

A formal check verifies a property, meaning a rule about the behavior it describes.
After code changes, an old check can still return a green result while describing code that no longer exists.
That result can look like a proof and mislead the reader.
Use this upkeep loop for checks created by `/create-formal-verification-skill` or other project-local verification skills covering named code.
The project-local skill handles changes made while using it.
This skill handles skipped checks after merges, refactors, and accumulated edits.
The sync commit is the commit where the verification last matched the code.

## Outcomes

Give every check its applicable outcome.

1. **in sync** means changes since the last sync do not alter the verified behavior, and the check holds.
2. **updated** means the verification now describes changed code, and the check holds.
3. **bug** means the verification describes current code and that code breaks the property. This is a code finding rather than model drift.
4. **blocked** means the check cannot run or cannot be brought back in line. State the exact reason.

A check can be both updated and bug when the corrected verification describes code that breaks the property.

## Edit scope

1. Edit verification models, harnesses, properties, and their skill only.
2. Keep deliberate broken code variants in isolated scratch copies. Preserve unrelated work and restore the deliberate changes afterward.
3. Change product code only when the user asks. Never weaken a property or model to hide a failure in current code.
4. Report that failure with its real-code replay evidence.

## Prepare Java and TLC

TLA+ is a language for describing steps. TLC checks those models.
For TLA+ checks, obtain the pinned tool paths before running the existing verification.

```sh
formal_tools_env=$(ctlhq-formal-tools env) || exit
eval "$formal_tools_env"
export JAVA TLA2TOOLS
```

1. If `ctlhq-formal-tools` is missing or its env command fails, report the prerequisite and mark that check blocked.
2. Show `ctlhq-formal-tools install` as the explicit setup command. Never install Java or TLC automatically.
3. In Codex, request escalation for the exact first TLC command before running it. The sandbox can block TLC's local listener.
4. Request escalation for an exact project-skill write into a read-only folder before writing there. Keep sandbox rules unchanged.

## Maintenance pass

1. **Find the checks.** Search project skills by their behavior, rather than expecting a fixed verification-skill name.
   Read each relevant skill, or the one the user named.
   Collect each property's coverage, dependencies, bounds, assumptions, run command, and last sync commit.
   If no verification skill exists, stop and point to `/create-formal-verification-skill`.
   If no sync commit exists, use the last commit that changed the verification files and disclose that fallback.
2. **Run the existing checks.** Run each check once before changing it and record its result.
   A green result says the old description holds. It does not establish that the description still matches current code.
   A failure can mean drift or a code defect. Decide which after the update and rerun.
3. **Read every covered change.** Diff covered files from the sync commit to the current commit and read each commit message.
   Follow functions that moved, split, or changed names. Find new writers of state that an existing check guards.
   Classify every change using these four cases.

   | # | Case | Required evidence or action |
   | --- | --- | --- |
   | 1 | No effect | Confirm against the model or harness that formatting, comments, or uncovered paths change no verified behavior. Commit messages alone are insufficient. |
   | 2 | Verification no longer matches | Update changed boundaries between indivisible steps, branches, guards, state paths, or value ranges from current code. |
   | 3 | Promise changed intentionally | Cite the supporting documentation, test, changelog, or commit message before changing the property. |
   | 4 | Promise might fail | Treat the result as a bug candidate when code changed without evidence of an intended promise change. |

4. **Update from current code.** Link every changed verification step to a file and line a reviewer can open.
   Preserve the code's indivisible boundaries. Write the update before rerunning; never shape it merely to obtain a green result.
   Change a property only for an intended promise change. Record its old wording, new wording, and supporting evidence.
   Keep the bounds unless the code change makes them wrong. Disclose every reduced bound.
   Keep a tool that detects changes to covered code. Prefer function hashes with an explicit dependency list and stated limits.
   Explain what uncovered callers, constants, defaults, imports, or dependencies can escape those hashes.
   You may use whole-file hashes. Measure their review cost from Git history and state it.
5. **Rerun and judge each result.** A check that still holds can have lost its ability to catch a break.
   Break the guarded behavior in an isolated copy of the new real code, using a removed guard or reordered step.
   Each modeled property must fail in both the model check and its matching real-code replay test.
   For code-level verification, require the verifier and real-code test to catch the broken variant.
   A source-hash refusal alone proves only drift detection. Keep evidence of the intended rule failure and replay assertion, then restore the scratch changes.
   For a failing current-code check, replay its path against real code one step at a time.
   If a step cannot occur, fix the verification and explain the modeling error.
   If every step can occur and the replay reproduces the failure, report a code bug.
   Name its introducing commit, describe the path in the code's words, and give the harm one sentence.
   Include a cheap test or reproduction in the report as evidence when feasible. Keep it outside a product-code commit.
6. **Update the verify skill.** Refresh coverage, dependencies, commands, bounds, assumptions, drift detection, and the sync commit.
   Set the sync commit to the commit whose code you checked. Keep the prior sync commit for a blocked check and explain why.
   Follow the updated skill once as the next agent would to confirm that its steps run.
   Use actual project-relative paths and no placeholders or machine-specific tool paths.
   Refer to `ctlhq-formal-tools` by name for Java and TLC setup.
   For TLA+ checks, require the generated skill to explain each failing path from TLC's output in plain words.
   Use short steps and the code's names.

## Report

For each check, give these results.

1. Name the outcome and the commits you read.
2. Explain each verification change and its evidence. Distinguish changed code shape from an intentionally changed promise.
3. Give the rerun result and the broken real-code variant that showed the updated check can still catch a defect.
4. Describe every bug through its real-code steps, harm, and introducing commit.
5. List remaining coverage gaps, including new code that should have coverage.
6. Separate model drift from reproduced code defects. If an old green result becomes a failure after updating, identify the stale description explicitly.
7. Separate original-code defects from deliberate broken test inputs in every summary. Keep zero original-code defects visible when applicable.
8. Explain what the model adds beyond replay tests, including additional event orders explored, and its maintenance cost.

Keep verification updates in a separate change from any product fix.
