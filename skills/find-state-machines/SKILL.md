---
name: find-state-machines
description: "Find and rank implicit state machines without changing source code. Use for requests to find the implicit state machines, or stateful code with several actors, retries, timeouts, or reloads."
---

# Find state machines

An implicit state machine has states and moves that nobody wrote together as one list.
State can hide in flags, status strings, saved keys, timers, locks, or whether a process is alive.
Moves can hide in branches across files.

## Read without changing behavior

1. Read the project's rules, README, promises, source, and related tests. Start with the area the user named, or inspect the whole project.
2. Record the inspected scope, commit, and existing changes. Follow each state's readers and writers across files and process boundaries.
3. Change no source, tests, configuration, or running services. Do not install tools, make a model, or refactor during this step.
4. Write only the report. Use `.local/state-machines/find.md` in the target project unless the caller names another report path.

## Tie claims to code

1. Give every factual claim a relative file path and current line number. Cite each state holder, move, actor, guard, and related test.
2. Mark an inference as an inference and cite the code behind it. A possible bad combination is a candidate until reproduced.
3. For a missing move, name the inspected entry points and their file and line. Write `not checked` wherever evidence is missing.
4. Reading a test shows its intended coverage. Record whether you ran it, and never describe an unread or unrun case as covered.
5. Keep the inventory within the inspected scope. Name unchecked areas and limits so the report cannot imply a complete proof.

## Report each machine

Give each machine one numbered section with these ten numbered fields.

1. **Name and subsystem.** Name the behavior the user cares about and the part of the project that owns it.
2. **Where state lives.** List every relevant variable, saved key, file, timer, or lock with its file and line.
3. **States.** List the states in the user's words. Include partial, waiting, failed, and finished states where the code allows them.
4. **Moves.** For each move, name the event, starting state, resulting state, guard, and code location. Keep separate writes visible.
5. **Bad combinations.** List values the data can hold that violate the project's promises. Separate guarded combinations from possible defects and unchecked candidates.
6. **Missing moves.** Check reload, sleep, a second actor, timeout, cancel, and failure in the middle separately. Cite handling or the inspected gap.
7. **Actors.** List who can change state concurrently, including processes, tabs, timers, workers, and users. Distinguish actor kinds from simultaneous instances.
8. **Existing tests.** Cite the test file, line, and test name. Say which moves they exercise and which event orders remain unchecked.
9. **Harm and test reach.** State the harm in one sentence. Explain which risky order existing tests seldom reach, or write `not checked`.
10. **Rank.** Rank by harm and how rarely tests reach the risky case. Cite that evidence; use qualitative judgment when nobody measured frequency.

## Choose the next step

1. Mark **order matters** as yes when multiple actors, retries, timeouts, reloads, or crashes can interleave. Cite the competing moves.
2. Recommend a **formal model** only where order matters. Name `create-formal-verification-skill` as the next step, without starting it.
3. Recommend an **explicit state type** for a single actor's linear flow or invalid value combinations. Use [principle-model-the-domain](../principle-model-the-domain/SKILL.md).
4. Recommend **nothing** when the inspected behavior is already clear and adequately checked. State the evidence and remaining limits.
5. Where evidence is missing, recommend nothing for now and name the inspection needed before choosing a change.

End the report with a numbered ranking table.
The actors column gives the actor kinds and count. Say when simultaneous instances have no fixed bound or remain `not checked`.
Each next-step cell names one of the three choices above and its reason.

| # | Machine | Rank | Actors | Order matters | Next step |
| --- | --- | --- | --- | --- | --- |

The report recommends work. It grants no permission to change the project.
