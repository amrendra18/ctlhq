# Word the prompt

A prompt states the intent and the check for done. The playbook supplies the steps, so a few plain sentences beat a spec.

## Put in

- The goal. Say what is wrong or what the user wants.
- The done check. It can pass or fail. "Make it better" and a duration are not checks.
- The proof to show. Ask for the real command output, a video of the flow, the stored value, or a before and after number.
- What the user already knows. A symptom, a repro step, a log, or a link saves the agent a search.
- The real constraints. "repro first", "don't change any code yet", "zero behavior change", and "let me review before proceeding" each change what the agent does.

## Leave out

- The how. Say what to achieve, and leave the agent room to find a better way.
- A list of skills or steps. A hand-written order drops or reorders steps the playbook keeps. Name a skill only to override one choice.
- The user's theory of the cause, until the agent restates the problem. A stated guess narrows the search.

## Load the context first

- For a noisy report, ask the agent to restate the underlying issue in its own words and in plain English before it does anything else. A misreading shows up before any code exists.
- In a fresh chat, `/recall` earlier work on the topic. Old chats hold context that the new agent lacks.
- Before a change to unfamiliar code, ask `/how` for the mechanics and `/why` for the reasons. An agent with no traced model fixes the symptom at the first plausible spot.
- Ask `/teach` to make the case for a choice, as in "convince me it fixes the cause and not the symptom". A case is easier to check than a summary.

## Design before the plan

- Never take the first design. Ask for prototypes of a few options, with screenshots or videos for UI, and pick from the evidence.
- Let prototypes answer the open questions. Don't review an abstract plan adversarially, because reviewers invent risks that never happen.
- For a shared package or API, ask for the README or a tutorial first, then work back to the code. The doc becomes the target the agent checks itself against.
- Ask for the plan only after the design is settled. Each step of the plan ends in a check.

## How much design work

Most changes need none. `/ctlhq-mode` already applies this ladder, so name a skill only for more or less scrutiny than its default.

- A small, finished change the user is unsure about gets `/interrogate` alone.
- A change that crosses function boundaries or moves ownership gets `/architect`, which runs `/best-of-n` itself.
- A standalone choice where independent attempts help, such as a name, a format, or an algorithm, gets `/best-of-n`.
- A coverage matrix, a set of parallel checks, or a race with declared arms gets `/swarm`.
- An open question that running something can answer, such as a layout, a timing, or an approach, gets a prototype.
- A contested design that is expensive to reverse gets `/architect`, then `/interrogate` before shipping.
- Work that spans several PRs gets a plan, written after the design settles.

## Follow up short

- "do it", "continue", and "keep going until done" are whole prompts once the chat holds the task.
- Start with "new task" when the subject changes. Otherwise the mode treats the message as the next step.

## Before stepping away

Leave a loop running only once it has earned it. All four hold:

1. The user has done the task once, or watched an agent do it, and knows what good looks like.
2. The agent has the user's own tools and signals, such as a verification skill, the profiler, and the logs.
3. Every step proves its work and can stop the run when the work misses the bar.
4. Repeated failures from earlier transcripts are now tools, skills, or checks.

Until then, the user runs it while watching. The overnight prompt holds these parts:

- "im going to bed" or "im stepping away". It is a session override, so the agent stops asking.
- Done as checks every iteration can run. A duration such as "work on this for 4 hours" is not a check.
- A fresh worktree off a named base, so the run collides with nothing else.
- Pre-answers to what the agent would stop for, such as "don't ask me before committing".
- A decision log to audit later.
- An exit, such as "if you're truly stuck after a few hours, stop and write up why".
- The wake command. In Claude Code, `/loop` with the done predicate re-checks it on events or a heartbeat. Codex has no `/loop`; `/goal <done predicate>` keeps the session working until it meets the goal or hits a blocker.

`/ctlhq-mode` routes such a run through `/figure-it-out`, which plans the phases and wires in the decision log. Subagents stop when the Mac sleeps, so keep it plugged in and awake, for example with `caffeinate -i` in a spare terminal. To stop on purpose, the user says "pause" or that they are going offline; the Pause safely playbook commits a checkpoint and writes a resume note. "keep going" never pauses.

## The morning audit

- Ask `/show-me-your-work summarize what you did last night`.
- The trail holds one row per decision, with the time, phase, decision, reason, evidence pointer, and result. It sits in `decisions.tsv`, or in `.audit/<task-slug>.tsv` when several runs share a folder. It stays local unless the user wants a committed record.
- A reviewer on another model family reads the trail and the transcript first. The reply ends with an Attention section.
- Read the Attention section first, then only the rows it points at. The user audits decisions, not the whole night.

## Steer in one line

- Restate the goal: "i said the goal is to repro. i did not ask for a fix yet."
- Name the principle: "apply prove it works. show me the real output, not the build log."
- A principle name works because the agent already read the rule. Its reply names the decision the rule changed.

## Setup choices

- At the end of `/ctlhq-setup`, the agent offers once to generate a verification skill with `/verify-setup` when the project has none. Recommend yes, especially to a new user. An agent that can check its own work keeps going until the check passes. Without one, it hands every result back to the user to check by hand.
- To spend fewer tokens, rerun `/ctlhq-setup` with a smaller budget or cheaper models, set a role to `auto` or `inherit-parent`, or shorten a panel list (one subagent per entry). A strong model in the main chat with cheaper, faster models in the code roles is a good split.
- Save `/ctlhq-mode` for work that needs rigor. A small, obvious edit does not.

## Pitfalls

- Looping before the loop can check its own work. Get a verification skill working first, or the loop only makes unchecked work faster.
- Trusting an unvetted number. A warm cache or a skipped code path can fake a speedup. Run `/benchmark-checklist` first.
- Correcting the same mistake by hand. A chat correction helps one run. `/mistake-proof` fixes the repository so no later run repeats it.
- Using `/best-of-n` for coverage. `/best-of-n` repeats one brief and grafts the best parts. `/swarm` splits slices or race arms and returns one report.
- Accepting every review comment. Bots and people file real catches and noise in one list. `/interrogate` sorts findings into act-on and dismissed, with reasons.
- Treating `auto` as a model name. `auto` and `inherit-parent` both mean the subagent runs on the parent chat's model.
- Reporting success from a green build. A build proves it compiles. Ask for the real command, flow, stored value, or profile.
- Writing a `SKILL.md` freehand. Use the Authoring or modifying a skill playbook, so validation and review happen.
