---
name: create-formal-verification-skill
description: "Generate a project-local verification skill for code where bugs cause high harm and tests reach few cases. Use for /create-formal-verification-skill, model-check this race, or prove this invariant. Also use for concurrency, retries, state machines, parsers, or unsafe code needing checks beyond tests."
disable-model-invocation: true
---

# Create a formal verification skill

A test checks cases someone chose to write.
Formal verification checks every case within a stated scope.
That scope can cover every event order in a model, every input within a bound, or every input.
Choose the area where that extra coverage matters most and verify one property, meaning a rule that must hold.
Leave a project-local skill that lets the next agent check changes against that property.
Write for an agent reading the skill during a change, without knowledge of this work.
The user must understand and act on the result without learning the verification language.

## Choose the target from the code

1. Answer from the codebase. Ask the user only for facts you cannot observe.
2. Start with the area or bug the user named.
3. For an ordering problem, read the existing inventory or use [find-state-machines](../find-state-machines/SKILL.md) on that area first.
   Confirm that the inventory matches current code.
4. Choose the strongest promise whose failure harms users and whose risky cases existing tests seldom reach.
5. Judge strength from code and evidence. An easy target alone does not justify verification.

## Let the question choose the tool

1. Choose the lowest-cost tool that answers the question.
   A model checker tries allowed event orders within a stated model.
   A proof assistant checks mathematical arguments. A solver-backed verifier checks whether code can break a stated rule.
2. Use a small design model for event-order questions. TLA+, a language for describing steps, is the default for those questions in any language.
3. Prefer verification of the actual code for memory safety, overflow, and data-structure rules across inputs.
4. If no verifier supports the language, say so and test real code with generated inputs. A hand model cannot replace that input check.
5. A property that must hold at every size can require a proof when a bounded check cannot answer it.
6. Prefer tools the project's developers can install and run. Explain the choice to the user.

## Prepare Java and TLC

TLC is the TLA+ model checker.
For a TLA+ check, obtain the pinned tool paths with these commands.

```sh
formal_tools_env=$(ctlhq-formal-tools env) || exit
eval "$formal_tools_env"
export JAVA TLA2TOOLS
```

1. If `ctlhq-formal-tools` is missing or its env command fails, stop and report the missing prerequisite.
2. Show `ctlhq-formal-tools install` as the explicit setup command. Never install Java or TLC automatically.
3. In Codex, request escalation for the exact first TLC command before running it. The sandbox can block TLC's local listener.
4. Request escalation for an exact project-skill write into a read-only folder before writing there. Keep sandbox rules unchanged.

## Verification rules

1. **Follow the code.** Link every model or proof step to a file and line a reviewer can open. Use the project's names.
   One indivisible model step must match one indivisible code step. Show boundaries around asynchronous work and separate writes.
2. **Show each rule failing.** Make a deliberate broken variant of real code, such as a removed guard or a reordered step.
   Use an isolated scratch copy and preserve unrelated work.
   Each modeled rule must fail in both the model check and a matching real-code replay test.
   For code-level verification, require the verifier and real-code test to catch the broken variant.
   Record the intended rule failure and replay assertion. A source-hash refusal alone proves only drift detection.
3. **Keep findings.** Report a current-code failure with its failing path in the code's words.
   Never weaken the property or model to obtain a green result. Change product code only when the user asks.
4. **State the scope.** Give bounds, assumptions, coverage, and omissions. A successful check proves the stated model or bound, rather than the whole system.
5. **Make results readable.** Give the rule and its harm one plain sentence each. Explain a failing path as short steps in the code's words.
6. **Keep reruns cheap.** Provide one command and reproducible tool versions. Keep the run short enough for every relevant change.
7. **Track code changes.** Record covered files, functions, dependencies, and the commit where the verification last matched them.
   Add a tool that detects changes to that coverage. Prefer hashes of covered functions with an explicit dependency list.
   State what those hashes can miss, including changed callers, defaults, constants, imports, or dependencies outside the list.
   You may use whole-file hashes. Measure their review cost from the project's Git history and state the result.

## Generate the verify skill

1. Add front matter naming the area and when to use the skill. A skill without front matter cannot register.
2. Explain how to recognize a covered change, run the check, distinguish a real bug from a modeling error, and update intended behavior.
3. Include coverage, assumptions, bounds, commands, dependencies, drift detection limits, and the sync commit.
   The sync commit is the commit where the verification last matched the code.
   Include each real-code replay command and the intended failure for each deliberate variant.
4. Advance that commit only after confirming that the verification describes the new code.
5. Use the project's actual commands, relative paths, and names. Leave no placeholders or machine-specific paths.
6. For a TLA+ model, require the generated skill to explain each failing path from TLC's output in plain words.
   Use short steps and the code's names.
7. Refer to `ctlhq-formal-tools` by name for Java and TLC setup. Include no local tool-installation path.

## Prove it before you hand off

1. Follow the generated skill once as the next agent would, using a scratch copy with a broken real-code variant.
2. Require the intended rule failure and matching replay failure for each modeled rule. A draft that only rejects a changed hash is insufficient.
3. Restore the deliberate changes and rerun. The result must return to its baseline, including any original-code findings still present.
4. If a step does not run or misses the break, repair the skill or verification. Keep the chosen broken variant as the test input.
5. Treat a generated skill that has never run as a draft.

## Hand off

1. Report what you checked, the tool and its reason, bounds, findings, rerun command, and omissions in plain words.
2. Separate defects reproduced in original code from deliberate broken test inputs in every summary. Keep zero original-code defects visible when applicable.
3. Explain what the model proves beyond the replay tests, including additional event orders explored, and the maintenance cost.
4. Suggest a second target only when its value is close to the chosen target.
5. Point to `/maintain-formal-verification-skill` when later changes skipped rechecking the verification.
