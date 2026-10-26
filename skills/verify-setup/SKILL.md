---
name: verify-setup
description: "Generate a project's verification harness (a `scripts/verify` command, a `verify/features/` feature map, and a project-local verification skill) that drives your app the way a user does, in any language, framework, or platform. Use for /verify-setup, \"make a verification skill for this repo\", or when a project has no scripted way to prove UI/CLI/service behavior."
disable-model-invocation: true
---

# Create a verification skill

Every serious project needs a scripted way to drive the real app and prove behavior: launch it, exercise a feature the way a user would, and capture evidence. This skill generates that harness in three parts, tailored to the repo:

1. `scripts/verify`, the one command any agent runs to prove the running product (section 2).
2. `verify/features/`, the feature map, one file per user-facing feature (section 3). It lives in the project, outside any host's skills folder, so Claude Code and Codex both read it.
3. A project-local skill (`verify-<app>/` under the host's skills folder, `.claude/skills/` in Claude Code or `.agents/skills/` in Codex), the agent-facing guide to running and extending the harness.

You write the generator's output for the next agent, not for a human: it will be read cold, mid-task, by an agent that has never seen the app.

## 1. Interview the repo, not the user

Answer these from the codebase and only ask the user what you cannot observe:

- **Surface:** what does a user actually touch? A web UI, a CLI/TUI, a desktop app, an API, a mobile app, a library? A repo can have several; pick the primary one and note the rest.
- **Run:** how does the app start locally? Prefer the repo's own documented dev command (package scripts, Makefile, README quickstart). Note ports, env vars, seed data, auth.
- **Drive:** how can an agent interact with it programmatically? Existing harnesses first (Playwright/Cypress specs, expect scripts, PTY helpers, curl-able endpoints, a debug port). Only then pick a generic recipe: browser/CDP for web and Electron, a tmux/PTY harness for CLI/TUI, plain HTTP for services.
- **Observe:** what evidence can be captured? Screenshots, terminal transcripts, response bodies, logs, exit codes, DB state.
- **Isolate:** can two instances run side by side (ports, data dirs, profiles)? If not, say so in the generated skill: refusing to double-drive a shared instance beats corrupting the user's session.

If the checkout doesn't build or start as-is, fix that first (or report it precisely) before generating; a skill written against a broken base teaches wrong steps. When an irrelevant missing asset blocks startup (a static dir the API never serves, a sample config), the generated skill may create it, clearly marked as verification scaffolding, and remove it in cleanup.

## 2. Generate the command and the skill

Write `scripts/verify` first. It is the harness, and the skill explains it. The contract has five parts.

1. **Usage.** `scripts/verify [fast|full] [--feature NAME]`. `fast` drives every mapped feature once on the primary surface. `full` adds the slower surfaces, such as a second browser or a clean machine. `--help` lists the levels, the feature names, the exit codes, and the map path.
2. **Steps, in this order.** Doctor, launch, drive, measure, evidence, cleanup. Each step matches the skill section of the same name below.
3. **Exit codes.** 0 every selected feature proven. 1 a feature failed. 2 usage error. 3 the doctor found the environment not ready, and nothing was launched.
4. **Evidence folder.** `.local/verify/<UTC time>/`, for example `.local/verify/20261017T142233Z/`. It holds `summary.md`, `summary.json`, `index.html`, `screens/`, `traces/`, and `logs/`. Cleanup never deletes it. Add `.local/` to `.gitignore` when it is missing.
5. **Output.** One line per feature (proven, failed, or skipped, with a reason), then the evidence folder path as the last line. `summary.json` holds the same rows, so a later check can read which features a run covered. The summary names each stand-in (mock) the run used.

Use the shared tools in this repository's `bin/` instead of writing your own. Each answers `--help`.

| # | Need | Tool |
|---|---|---|
| 1 | doctor checks: permissions, `.git` writes, signing key, disk, tools, services up | `ctlhq-preflight --repo . --need TOOL,TOOL --service URL` |
| 2 | start a dev server, wait until it answers, stop only what it started | `ctlhq-serve start`, `health`, `stop` |
| 3 | screenshot at a window size, console errors, network log | `ctlhq-browser screenshot`, `console`, `network` |
| 4 | navigation performance trace, heap snapshot after page load | `ctlhq-browser trace`, `ctlhq-browser heap` |
| 5 | `index.html` with the screenshots that changed since the last run marked | `ctlhq-gallery <evidence folder> --previous <last evidence folder>` |
| 6 | a test machine: start, snapshot, restore, run a command, screenshot | `ctlhq-env up`, `snapshot`, `restore`, `exec`, `screenshot` |

When the repo already has a driver (Playwright specs, an expect script), `scripts/verify` calls it and uses the shared tools for the parts it lacks. Every `ctlhq-browser` command opens a new tab, even with `--attach`. For interaction evidence, wait for the expected state and capture or profile through the driver controlling that session.

Then write `verify-<app>/SKILL.md` in the host's skills folder with YAML frontmatter (`name: verify-<app>` and a `description` that names the app, the surface, and when to reach for it. Without frontmatter the skill never registers) and these sections, each grounded in what the interview actually found (no placeholders left). Each section names the `scripts/verify` step that does the work, so the skill explains the command instead of repeating it:

- **Launch:** the exact command that starts the app for verification, and how to tell it's ready (a log line, a prompt). Launch must reach a usable state from an empty data dir, including any migrations and seed data. Ready means usable, not just that a process answers. A database health check can pass while its init scripts are still running. Include teardown. For a short-lived CLI or TUI there is no server to keep alive: launch means build the binary (or install deps) once, then start each drive in its own isolated PTY or tmux session.
- **Doctor:** one read-only check that answers "is this instance worth driving?" (process up, right version/build, port owned by us, auth valid). An agent runs this first whenever anything looks off. `scripts/verify` runs it first and exits 3 when it fails; `ctlhq-preflight` covers the machine checks.
- **Drive:** the harness recipe with real selectors/commands from this repo, not examples. Prefer stable handles (ARIA labels, data attributes, prompt strings, route paths) over coordinates and tab order.
- **Measure:** how the harness records a performance trace and, where memory matters, a heap snapshot (`ctlhq-browser trace`, `ctlhq-browser heap`, or the platform's profiler), saved under `traces/`. A screenshot cannot answer a speed or memory question.
- **Evidence:** what to capture for a proof. It goes in the run's evidence folder (`screens/`, `traces/`, `logs/`, and the summary files). State the proof standards: exercise the real user path, not internal setters or test-only endpoints; capture the action and the resulting state, not just the final screen; verify side effects (files written, rows inserted, messages sent) alongside what's visible; mocks only where a production boundary already isolates the external system. When the safe path is a dry-run or test mode, verify what it actually skips by observing (files, network, git refs) rather than trusting its name: some dry-runs still touch the network or open a browser.
- **Cleanup:** how to tear down instances the run created. Never kill by process name; kill what you started (`ctlhq-serve stop` stops only the process group it started). Cleanup removes instances and scratch state, never the evidence: proof artifacts survive the teardown, in the run's evidence folder.
- **Helpers:** any script the skill ships is executable and its invocation is shown in the skill body. A helper the reader has to reverse-engineer is not a helper.

## 3. Seed the feature map

Create `verify/features/README.md` in the project plus one file per user-facing feature you can identify (aim for the top 3-5 to start, from routes, commands, menus, or docs). Follow the shape in [`references/feature-map-example/`](references/feature-map-example/), with a README index and one file per feature. The index has one numbered row per feature with its file and the `scripts/verify` journey that drives it, so the map and the command stay in step. Each file answers, from the user's point of view: what the feature is, how to reach it, how to drive it with the harness, and what observable end state proves it works. The four H2s are `Sub-features`, `How to get to it (user POV)`, `Driving it with <harness>`, and `Gotchas`. If the seed data lacks a precondition that a journey needs, the journey reports a failure and the reason goes in that feature's `Gotchas`. Never weaken the journey to make it pass. The map is the repo's maintained verification source; a proof that drives one convenient entry point is incomplete when the map lists others.

## 4. Prove the generated skill before handing it over

Run `scripts/verify fast --feature <one feature>`. It must exit 0 and print the evidence folder. That run follows the skill's own instructions end to end once: doctor, launch, drive ONE mapped feature (one is enough; the map exists so later runs can cover the rest), capture evidence, clean up. Then plant one failure (stop the server mid-run, or point the journey at a missing element). The run must exit 1 and name the feature. After cleanup, confirm the evidence still exists at the named location. A cleanup that eats the proof fails this step. Fix what fails, and run the generated cleanup after every failed iteration too, so broken attempts don't strand processes and ports. A generated skill that was never executed is a draft, not a deliverable. If you proved it in a stand-in for the real target (a container in place of a fresh VM, a local stack in place of a remote one), list every setup step the stand-in did that the target will not. Those steps stay unverified until a run on the real target covers them.

## 5. Offer the maintenance loop

Point the user at `/verify-audit` for keeping the map honest as the app changes. Suggest a cadence only if they ask.
