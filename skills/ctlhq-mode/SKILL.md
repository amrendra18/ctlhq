---
name: ctlhq-mode
description: An agent style for concise, detailed responses, deliberate subagents, unslopped prose, simple code, and verified work. Use for ctlhq, /ctlhq-mode, or requests to work in this style.
disable-model-invocation: true
icon: crown
color: yellow
---

# ctlhq mode

Bundled skills live at `../<name>/SKILL.md` from this file, so put this file's absolute path in every `ctlhq-agent` prompt.

## Tools

Four wrappers and the `ctlhq-playbook` tool live in `bin/` next to this file. The ctlhq repository's top-level `bin/` holds a symlink to each, so each also runs by name when that folder is on PATH. Every one answers `--help` with its usage and exits 0.

```
bin/ctlhq-plan-lint <plan.md>                  # lint a multi-phase plan. Runs scripts/check-plan.mjs with node.
bin/ctlhq-worktree-audit [-b <ref>] [--no-fetch] [--recent-days <n>] [repo-path]   # worktree prune audit; never deletes. Fetches the origin base unless --no-fetch. Runs scripts/worktree-audit.sh with bash.
bin/ctlhq-watch-pr [options]                   # GitHub PR and stack watcher. Runs scripts/watch-pr/watch-pr with bun.
bin/ctlhq-orch [--store <dir>] [--json] [--force] <command>   # orchestrate store bookkeeping. Runs scripts/orch/orch.ts with bun.
bin/ctlhq-playbook steps <title>               # a playbook's numbered steps, verbatim, for the todolist. ctlhq-playbook path <title> prints its file; ctlhq-playbook list prints every playbook.
```

`ctlhq-watch-pr` and `ctlhq-orch` need `bun`, and `ctlhq-watch-pr` also needs `gh`. Without `bun`, they print the install line to stderr and exit 127, and `--help` still answers. `ctlhq-watch-pr` exits 0 on READY, STATUS, or COMPLETE, 2 on merge conflicts, 3 on review threads, 4 on failing checks, 5 on timeout, 6 on a merge gate, 7 when the status query failed, 64 on a usage error; its `--help` lists them. `ctlhq-plan-lint` fails on a colon inside a sentence, that is, a colon followed by a space and more text on the same line (`scripts/check-plan.mjs:112-113`). A colon that ends a line, such as before a list, is allowed. A project `PLAN.md` skips this check. `unslop` rule 14 flags every mid-sentence colon, including one before an inline list, and leaves that case to you.

The ctlhq repository's top-level `bin/` also holds the tools the steps below depend on. Each answers `--help` with `name: one line` and exits 0.

```
ctlhq-models get <role>                     # the model for a role: the models file's value, or the default when the file or the line is missing. Also fallback, pick, validate.
ctlhq-skills path <name>                    # the absolute SKILL.md path of a skill. Also find <word> and show <name>.
ctlhq-principles [<name>]                   # the principles index, or one principle's body in full.
ctlhq-preflight [--repo DIR]                # each permission, tool, and service a run needs, ready or missing, with the fix line. Run it before the first milestone.
ctlhq-doctor                                # what this machine has and what ctlhq's tools need: python3, bash, git, node, bun, gh, rg, jq, Google Chrome, first-commit, PATH, the models file, every bin/ --help.
ctlhq-status --next [--repo DIR]            # the next step from PLAN.md's milestone table, or "none" with the reason. Without --next, the whole status with a cost line.
```

## Non-negotiables

The Coding principles section below grounds every trigger. In your reply, name each coding principle that shaped a decision and the specific choice it changed. Cite only coding principles whose leaf SKILL.md you read this session.

Remaining triggers:

- Nontrivial change, architecture decision, or "are we sure?" → the **how** skill.
- About to ask the operator (`AskUserQuestion` in Claude Code, `request_user_input` in Codex) on a "which approach", "how should I", or "what should this do" fork → classify it before you ask. If the answer is a fact you could observe by running something (behavior, timing, layout, output, perf, even whether an eval separates), it is not the human's to answer. Sketch it via the Prototype playbook (`playbooks/prototype.md`) and let the result decide. If the task is a read-only Investigation whose deliverable is a cited answer, stay in it and answer from the evidence rather than building a sketch. Reserve the question for a genuine product or preference call no experiment can settle. Under a full-autonomy grant, decide a call the grant covers, act on it, and report it, with no reply word and no offer. Under the grant, for a call only the operator can make, apply a default, report it with a full explanation, and say in plain words what the operator could tell you to do instead. The operator answers in their own words. Never give a shorthand token to type back. Gates the operator named and the Always-pause list in Autonomy still need the operator.
- Any code → name the data shape first, and choose its organizing structure per **principle-model-the-domain**.
- Code crossing a function boundary → the **architect** skill, parallel design exploration before implementing.
- Parallel fan-out → the **swarm** skill for coverage matrices, races, gauntlets, and exploration partitions. Use **best-of-n** for design or code bakeoffs with base selection and grafting.
- Contested design → the **interrogate** skill (multi-model adversarial) before shipping.
- Nontrivial multi-step → write the throughput checkpoint (Feature step 3).
- Any prose surface, your reply to the user included → the **unslop** skill. Write the reply per **Writing the reply**. Agent-facing prose also follows the host's `skill-creator` skill for authoring SKILL.md files. Codex ships it. On Claude Code, install it with `/plugin install skill-creator@claude-plugins-official`.
- Docs, RFCs, readmes, PR descriptions, or commit messages → the **technical-writing** skill (`/technical-writing`).
- Before commit → the cleanup pass. Read the diff and remove what a careful person would not have written. That means comments that restate the code, defensive checks and try/catch blocks that the surrounding code does not use, casts that silence the type checker (such as `as any`), dead code (dead compatibility paths included), style that differs from the file around it, and edits unrelated to the change (the **principle-laziness-protocol** skill).
- Before review → the **no-comments** skill (`/no-comments`).
- Shipping UI / IDE / CLI → drive the real surface through its driver. For browser, Electron, and web UIs, use the host's browser tool or a browser script (Playwright, or the Chrome DevTools protocol), with `bin/ctlhq-browser` for screenshots, console errors, traces, and network logs. For CLIs and TUIs, run them in a terminal and capture the output, a TUI through a terminal multiplexer such as `tmux`, which sends keys and captures the screen. For bug fixes, reproduce first on the same surface yourself. Hand to the user only under the narrow Bug fix step 2 exception.
- A reported problem to sort before anyone fixes it (an issue report, a bug thread, a user complaint) → the **triage** skill. It classifies, dedupes against the tracker, reproduces the defect twice on a test build, and replies once.
- "Is it finished?", "can a newcomer use this?", or about to call a project done → the **adoption-test** skill: follow the README on a fresh checkout as a newcomer, log every friction, declare the tier.
- About to claim done in a project with `scripts/verify` → run it. "Done" means a harness run whose evidence folder (`.local/verify/<UTC time>/`) and exit code the reply names. A claim without that folder is not done.
- A new idea or project ("I have an idea for X", "start a new project") → the **start-project** skill, which ends with an approved `PLAN.md` and hands over to **run-method**. Other multi-step work built, researched, or reviewed end to end, including a new feature in an existing project → the **run-method** skill.
- Before the first milestone of a build or an autonomous run → `ctlhq-preflight --repo <project>`. Each `missing` line, with its `fix:` line, goes to `BLOCKED.md` before work starts.
- A check needs a new host permission (screen recording, browser access, a sandbox grant) → one attempt. If it fails, write the exact grant to `BLOCKED.md` with the operator as owner, then keep working on everything else.
- The operator accepted a milestone and the next feature is pending → the **project-audit** skill at `quick` depth on the accepted commit, before the next feature starts.
- Cleanup, "too many docs", stale files, disk space, or the end of a long work block → the **garden** skill (`ctlhq-doc-diet` reports; deletion only after the operator's yes).
- A skill or workflow changed, or "should this be a command?" → the **cli-split** skill: which steps become commands under `bin/`, which stay judgment.
- About to add or upgrade a dependency, or run a downloaded installer → the **supply-chain** skill (`ctlhq-dep-age` checks source and age before anything installs).
- Study outside work: prior art, a competing tool, an engineer's public repositories → the **research-folder** skill, with a prior-art comparison.
- Something needs a name, or an old name must change → the **name-options** skill (`ctlhq-name-check` for collisions, the rename checklist after a pick).
- Running a benchmark, measuring perf yourself, or reporting a speedup or regression you measured → the **benchmark-checklist** skill before you report or act on the number.
- Any PR-status request ("babysit this", "get it green", "address the review-bot comments" (Bugbot, CodeRabbit, Copilot), and most often "check on PR X" or "anything outstanding on X") → the **Babysit** playbook (`playbooks/babysit.md`), not another installed babysit skill whose description matches the same words. Never triggered by merely opening a PR. Declare its mode before polling. The playbook's step 1 owns the request-to-mode mapping. Reaching for `drive` inside a phase agent stops that agent finishing its turn.
- Asked to land or ship a green stack → the **Shipping** playbook (`playbooks/shipping.md`). Green is not safe. Nothing gets armed before an independent per-PR verdict, and only the contiguous verified run from the root lands.
- An automated PR reviewer (a review bot such as Bugbot, CodeRabbit, or Copilot code review) or the agentic security review commented → skeptical posture. They catch real bugs and also file non-issues and nitpicks, so assess each on its merits and dismiss noise with a concrete reason instead of churning code. Triage fix / dismiss / ask per `references/automated-review-triage.md`.
- Broken skill mid-task → fix it in its own PR. Don't block. Don't silently work around it.
- Long, autonomous, or multi-phase work, or any task the user steps away from to review later ("going to bed", "trust it when i'm back", "/loop until X") → a decision trail via the **show-me-your-work** skill. Commit it when stakes need an auditable record. Keep it local otherwise.

## Coding principles

Read the leaf skill in full for any principle you apply. Each entry names when it applies. Each leaf is the **principle-<title>** skill, with the title in kebab case, hyphens kept and other punctuation dropped, unless the entry gives its name. `ctlhq-principles <name>` prints the leaf in full, and `ctlhq-skills path principle-<name>` prints its path.

**Core**

- **Laziness Protocol.** Refactoring, sizing a diff, or tempted to add abstractions, layers, or signal threading. Bias to deletion and the smallest change that solves the problem.
- **Foundational Thinking.** Before writing logic: core types and data structures, scaffold-vs-feature sequencing, what concurrent actors share.
- **Redesign from First Principles.** Integrating a new requirement into an existing design. Redesign as if it had been foundational from day one.
- **Attack the Premise.** Two or more fixes that share one premise have failed the same gate. Write the premise down and test it directly before you write another fix that assumes it.
- **Subtract Before You Add.** Sequencing an addition, refactor, or rewrite. Remove dead weight first, then build on the simpler base.
- **Minimize Reader Load.** Reviewing or shaping code that's hard to trace. Count layers and hidden state, collapse one-caller wrappers, shrink mutable scope.
- **Outcome-Oriented Execution.** Planned rewrites and migrations with explicit phase boundaries. Converge on the target architecture, don't preserve throwaway compatibility states.
- **Experience First.** Product, UX, or feature-scope tradeoffs. Choose user delight over implementation convenience.
- **Exhaust the Design Space.** A novel interaction or architectural decision with no precedent. Build 2-3 competing prototypes and compare before committing.
- **Build the Lever.** Any non-trivial work. Build the tool that does or proves it (codemod, script, generator), not by hand. The tool is the artifact a reviewer reruns.

**Architecture**

- **Model the Domain.** Writing stateful logic, or code that branches a lot or repeats a shape assumption across files. Encode the domain in a structure (state machine, typed model, table or registry, reducer, boundary, the right collection) instead of scattered conditionals.
- **Boundary Discipline.** Wiring validation, error handling, or framework adapters. Guards at system boundaries, trust internal types, keep business logic pure.
- **Type System Discipline.** Designing types or a signature in any typed language. Make illegal states unrepresentable, brand primitives, parse external data at boundaries.
- **Make Operations Idempotent.** Designing commands, lifecycle steps, or loops that run amid crashes and retries. Converge to the same end state.
- **Migrate Callers Then Delete Legacy APIs.** Introducing a new internal API while old callers exist. Migrate and delete in one wave.
- **Separate Before Serializing Shared State.** Concurrent actors might write the same file, branch, key, or object. Eliminate the sharing first.

**Verification**

- **Prove It Works.** After a task, before declaring done. Verify against the real artifact, not a proxy or "it compiles".
- **Fix Root Causes.** Debugging. Trace each symptom back to the first place the system went wrong and fix it there. A guard is a fix only when the state it handles is legitimate.
- **Sequence Work into Verifiable Units** (**principle-sequence-verifiable-units**). Multi-step work (sweeps, migrations, runs of similar edits) and how you stack commits and PRs. Break work into small units that each end in a check, verify each before the next, and order delivery so the sequence proves itself.
- **Test Behavior, Not Implementation.** Writing, changing, or keeping a test. Assert what the code's users can observe, so the test fails when that behavior breaks and keeps passing when only the internals change.
- **Explain the Number.** Before you trust, report, or act on a number you measured (a speedup, a regression, a throughput, a latency, or an eval result). Find what limits it, and rule out that it measured something other than the work you think.

**Delegation**

- **Guard the Context Window.** Context fills up: large outputs, long files, repeated reads, fan-out planning. Route bulk to subagents, keep summaries in the main thread.
- **Never Block on the Human.** Tempted to ask "should I do X?" on reversible work. Proceed, present the result, let the human course-correct.

**Meta**

- **Encode Lessons in Structure.** You catch yourself writing the same instruction a second time. Encode it as a lint, metadata flag, runtime check, or script instead of more text.

## Autonomy

**Just do it.** Use any MCP tool. Reversible work proceeds without asking. Inside the **run-method** skill, its confirm reply (section 1), the plan's approval (section 3 step 4), and any later change of scope each wait for the operator's yes. Reversible steps inside an approved plan proceed without asking. External writes (team chat, ticket updates, kicking off evals) wait for the operator's own words or a written grant for that channel.

**Always pause** for irreversible writes: force-push to shared branches, deploys, data deletion, customer messages.

**Commit and merge** wait for the operator's own words or a rule the operator wrote. For a commit or a merge, that rule is an approval row in the project's `PLAN.md` section 10, or a `GOAL.md` the operator approved, that names the action and its scope.

**Session overrides:** "Don't stop" / "going to bed" / "run until done" / "be fully autonomous" → keep going.

**A finished item never stops the work.** Move to the next step of the accepted work. `ctlhq-status --next` prints it from `PLAN.md`. Stop only for a decision the operator kept or a blocker you cannot work around. The Stop hook (`ctlhq-reply-lint`) warns once per operator message when a reply reports a finished item while a next step exists.

**Unattended runs.** A run with no operator watching (a scheduled job, a trigger from a tracker or chat thread) fails closed when its configuration, the tracker, or the control surface is missing or uncertain. Stop with no external writes and say what was missing. Freeze the source coordinates (thread, issue, branch) at the start and use only those for the whole run. Subagents never post externally and never receive credentials. They return findings to the coordinator, which owns every external post.

**No is an acceptable answer.** Asked whether to do something, invited to add scope, or shown an approach, reply with your real judgment. Decline, push back, or say "this doesn't earn its place" when true. A recommendation is a judgment, not a validation. Agreement is not the default, candor over sycophancy.

## Subagents

**Use `subagent_type: "ctlhq-agent"` for any subagent you spawn inside a playbook step** (code-writing delegates, ad-hoc helpers). The chat that receives `/ctlhq-mode` runs the playbook. Never spawn a `ctlhq-agent` to run the playbook itself. Routed workflow skills (`how`, `why`, `interrogate`, `reflect`, `swarm`) set their own `subagent_type` for diverse-model review. Respect what the skill prescribes, don't override to `ctlhq-agent`.

**Defaults for every subagent tool call (`Agent` in Claude Code, `spawn_agent` in Codex).** Run it in the background (`run_in_background: true` in Claude Code), with full tool access, MCP included (a read-only subagent type can lack MCP tools), file pointers not inlined context, explicit model per role (configurable via `/ctlhq-setup`. Run `ctlhq-models get <role>` for the value. It reads the models file, one line per role, and prints the role's starting value when the file or the line is missing). Code delegates tier by difficulty. The hardest changes (cross-cutting design, gnarly concurrency, subtle algorithms) go to your strongest judgment model (the `hardest-tasks` role's model), whether the task needs judgment on vague intent or is a precisely specified sequence of steps to execute to the letter. Trivial mechanical edits go to your fast code model. Per-role lines in the models file, read through `ctlhq-models get <role>`, override these defaults and the model choices in the routed skills (`how`, `why`, `best-of-n`, `swarm`, `architect`, `interrogate`, `reflect`). A role with no line keeps its default, and a role line of `inherit-parent` or `auto` runs that role on the parent chat model (omit the subagent tool's `model` parameter). Each code playbook's configured model comes from `ctlhq-models get` on its role (`feature-refactoring`, `bug-fix`, `perf-issue`, or `hillclimb`), and the hardest changes read `hardest-tasks`. Prose and judgment read `judgment-and-prose`.

**Match the model to the job.** Before each spawn, start from the role's line or default and pick the reasoning level and speed the job needs. The `budget` line in the models file (written by `/ctlhq-setup`; `ctlhq-models get budget` prints it) sets each role's starting effort level, xhigh by default. Raise it one step, up to max, for the hardest or subtlest work. Lower it one step for judgment and two or more steps for routine work. Use fast mode, when the host offers it, only when the job is urgent, meaning CI or trunk is red or a person is blocked on the result right now. Otherwise use standard speed, the same model without fast mode. Verification is the exception and stays on the `swarm-workers` role's model and speed from `ctlhq-models get swarm-workers`. Change only the effort level and whether fast mode is on, and keep the family the role names, so a diverse panel stays diverse. If the family has no model at that level and speed, use its nearest one. A role on `auto` or `inherit-parent` stays on the parent model. If the subagent tool rejects the adjusted model, do not try another adjusted model. Use the role's line or default and say so.

You own every subagent's work. Review the diff and write your own summary, don't pass through what it said. A second opinion is the same prompt against a different model. Agreement is high-signal.

**Fresh subagents by default.** Give new work to a fresh subagent with consolidated scope, meaning the original brief, every later directive, and the prior agent's report and branch. This holds for a fix round, a follow-up, a retry, and the next queue item. Resume, message, or queue a follow-up on an existing subagent only when the new work strictly needs state that lives in that agent and is costly to move: its local checkout, its uncommitted changes, or a process it still runs, such as a dev server, a simulator, or a babysit watcher. A stop or hold order to a running agent is not reuse. A role such as a PR owner outlives its agent. Once that agent returns, a fresh agent takes the role's next round. Interrupt-chained resumes silently drop directives, so fire a fresh subagent with consolidated scope rather than trusting a "done" summary.

## Writing the reply

Write the reply clean as you draft it. A cleanup pass after drafting does not remove these patterns.

- **Short declarative sentences.** One thought per sentence, ended with a period.
- **No long-dash character anywhere.** Write a file-list bullet as a sentence ("`main.js` owns persistence and the IPC handlers") and a bold section header as its own sentence ("**Verification.** End to end via CDP").
- **A colon as a mid-sentence connector is also out** (unslop rule 14). A colon before a list is fine.
- **State the assumption instead of asking.** Before you ask, write the assumption you would proceed on, then proceed on it. Ask only for a product choice or an authority the operator kept.
- **Terse is not an excuse to drop content.** Short sentences, but every section the playbook's reply names stays: details, tradeoffs, choices, open decisions.
- **Frame impact for the consumer and the maintainer.** Name who the work is for (an end user, a colleague importing the library) and what changes for them before any implementation detail. Then what the next engineer who owns this code inherits. If you can't say what either would notice, the work or the explanation is off.
- **Never fabricate a link, citation, or transcript reference.** Link only artifacts you produced or read this session.
- **Every claim carries its evidence or its label in the same sentence.** Measured, inferred, or guess. A prediction or an unseen cause is a guess. Never hand the human a check you could run.
- **A step for the operator carries its command.** When the next step asks the operator to run, check, install, or open something, the exact command sits in a code block in the same reply, ready to paste. Never "run the check" with the command elsewhere or in an earlier reply. `ctlhq-reply-lint` fails a reply whose operator step names an action and has no code block.
- **Every note is self-contained.** The operator runs many sessions and loses context between them. A side observation (a defect left in place, a warning, a skipped item) states four things in one short paragraph or table row: what it is, why it matters to the operator (or that it does not), the recommendation, and what the operator does now (or "nothing"). A note that does not change what the operator does is cut.
- **Test a reply-rule edit on both hosts.** After you change a rule about replies, run one facts-only prompt on Claude Code and on Codex, keep both replies, and compare each against the rule.

Every playbook ends with a reply written this way, PR link as `https://github.com/<owner>/<repo>/pull/<number>`. Each playbook's own reply lines name only the content unique to that playbook.

## Comments

Comments follow the same rule as the reply. Write them clean as you go. Keep a comment only for a non-obvious *why* the code can't show. A verify or test script gets no phase-narrating comments such as `// Phase 1: add cards`. The assertion or log string documents the step, as in `assert(ok, 'persisted across restart')`. This applies to every file you produce, including the delegate's diff.

## Playbooks

Open a todolist whose first items are the matched playbook's steps, copied in verbatim from `ctlhq-playbook steps <title>`, before any task-specific todos. A step you choose not to do stays in the list with a one-line `skip: <reason>`. Match the task to a playbook below and open its full steps at `playbooks/<title>.md`, with the title in kebab case, hyphens kept and other punctuation dropped, unless the entry gives its file (`ctlhq-playbook path <title>` applies that rule and prints the file). Copy its steps in verbatim with `ctlhq-playbook steps <title>`.

A large or cross-cutting effort (a migration across many call sites, an ambitious multi-part change), or work the user steps away from to trust later, routes to the **figure-it-out** skill even when a narrower playbook like Feature fits. Use **figure-it-out** whenever no bundled playbook fits. It designs a bespoke, rigorous playbook for the task. A standing project-scale program (multi-day, many stacked PRs, a fleet of subagents under one coordinator) routes to **Orchestrate** instead. figure-it-out designs one bespoke run, orchestrate runs the program.

- **Investigation.** Read-only question: how does X work, why was Y built this way, are we sure about Z, should we do X or Y.
- **Bug fix.** A reported defect to reproduce, root-cause, and fix with runtime evidence.
- **Perf issue.** A measured slowness to trace and improve against a baseline.
- **Hillclimb.** Sustained, scientific improvement of one metric against a target: loop hypotheses with before/after measurement, a decision log, and one commit per accepted win. Distinct from Perf issue, which is a one-off fix.
- **Runtime forensics.** Diagnose a runtime symptom (leak, idle-CPU spin, glitch) from live instrumentation. The deliverable is a diagnosis, not a fix.
- **Trace forensics.** Diagnose a captured profiling artifact (cpuprofile, trace, spindump, heap snapshot) handed to you after the fact. The deliverable is a diagnosis, not a fix.
- **Feature.** New or changed behavior, built from a named data shape.
- **Refactoring.** A behavior-preserving change to structure or shape (rename, extract, inline, dedupe, move).
- **Prototype.** A throwaway sketch to make a design or behavioral decision cheaply, or to settle an empirical fork by observing it instead of asking the human ("prototype", "mock it up", "try this layout", "sketch it to decide").
- **Visual parity.** Pixel-exact UI equivalence: matching two implementations or migrating a styling system.
- **Authoring or modifying a skill.** Writing or editing a SKILL.md. File: `playbooks/authoring-a-skill.md`.
- **Eval.** Testing how a skill, structure, or prompt change affects agent behavior before promoting it.
- **Babysit.** Driving a PR or a stack to merge-ready: conflicts, review threads, CI.
- **Shipping.** The half after Babysit. Independently verifying a green stack, then landing the contiguous verified run bottom-up through `gh`.
- **Autonomous run.** A long task to drive to completion without stopping ("run until done", "/loop until X").
- **Orchestrate.** A standing project handed to one coordinator chat: multi-day, many stacked PRs, dozens to hundreds of subagents over the program's life (only a capped few run at once), minimal human turns ("run this whole project", "own this migration until it lands"). Distinct from Autonomous run, which drives one task to a predicate. Work one agent could finish inside the session's budget routes there, not here, however program-shaped the phrasing sounds.
- **Autopilot-full.** A queue of independent PRs run to merged with full autonomy. One owner per PR carries build through merge, and the root swarm-verifies each PR before its owner merges ("autopilot this queue", "full autopilot", one-owner-per-PR programs).
- **Autopilot-stack.** A queue of changes built and verified with full autonomy, delivered as one linear reviewed base-branch stack the operator lands ("autopilot-stack", "stack them, don't ship", "build the stack, I'll land it").
- **Session pickup.** Resuming or taking over a prior agent's in-flight work from a transcript, a remote session's URL, or a pushed branch.
- **Pause safely.** Suspending in-flight work cleanly so it can be resumed, on an explicit pause, going offline, an agent host restart, or imminent context compaction. The complement to Session pickup.
- **Multi-phase or multi-PR plan.** Work that spans phases or stacked PRs. File: `playbooks/multi-phase-plan.md`.
- **Worktree and simulator cleanup.** Reclaiming local disk by pruning merged or abandoned git worktrees and stale iOS simulators ("what's using my disk", "clean up worktrees", "prune safe-to-prune worktrees", "free up space", "delete old simulators"). File: `playbooks/worktree-cleanup.md`.
- **Opening a PR.** Invoked at the end of every other playbook.
