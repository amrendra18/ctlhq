---
name: reflect
description: Spawn three parallel review subagents over the active transcript, surface learnings, and route each to a concrete edit on an existing skill. Use when the user says reflect.
disable-model-invocation: true
---

# Reflect

Mine the current conversation for durable learnings, then route them into skill edits.

Invoke when the user says "reflect" or "/reflect". Skip when the conversation is trivial, off-topic, or already covered by an existing skill the parent followed correctly. One-offs are not learnings.

## 1. Locate the active transcript

Before fanning out, find this conversation's transcript in the host's transcript folder for this workspace (Claude Code: `~/.claude/projects/<workspace-slug>/`; Codex: `~/.codex/sessions/`, filed by date, where `ctlhq-transcripts list --host codex` keeps only this workspace's sessions). Do not glob across other workspaces' folders (`~/.claude/projects/*/`), and do not read Codex sessions from other workspaces. That crosses workspace boundaries and reads private chats from unrelated projects.

```bash
ctlhq-transcripts current --match "<a phrase from the conversation's opening user prompt>"
```

In Codex, add `--host codex`. It prints the newest transcript of this workspace whose opening user prompt contains the phrase. If none matches, pass a tight digest of the session instead.

## 2. Spawn three reviewers in parallel

One message, three subagent tool calls (`Agent` in Claude Code, `spawn_agent` in Codex), each a general-purpose subagent with full tool access (`subagent_type: "general-purpose"` in Claude Code). Reviewers need MCP access to look up the tickets, chat threads, and observability traces the transcript references, and a read-only subagent type can lack MCP tools.

Each reviewer and the synthesizer name a role. Run `ctlhq-models get <role>` and set `model` to what it prints. Leave `model` unset when it prints `auto` or `inherit-parent`. If the subagent tool rejects that model, run `ctlhq-models fallback <role> <rejected-model>`, use what it prints, and say so. If the host also rejects that, follow its `next:` line (a rerun with `--valid`). A line marked `(operator, changes <file>)` is the operator's action: never run it mid-task; report it to the operator. Pick each subagent's reasoning level and fast or standard speed for the job, per the Subagents section of the **ctlhq-mode** skill.

| # | Lens | Role | Default `model` | Prompt template |
|---|---|---|---|---|
| 1 | Judgment | `reflect-judgment-divergent-synthesizer` | its `models.example.toml` starting value | `references/judgment-reviewer.md` |
| 2 | Tooling | `reflect-tooling` | its `models.example.toml` starting value | `references/tooling-reviewer.md` |
| 3 | Divergent | `reflect-judgment-divergent-synthesizer` | its `models.example.toml` starting value | `references/divergent-reviewer.md` |

Pass each template verbatim, substituting the transcript path or digest where marked. Reviewers return findings in the subagent tool's response body.

## 3. Synthesize

One subagent tool call, a general-purpose subagent with full tool access, `model` from `ctlhq-models get reflect-judgment-divergent-synthesizer`. It spot-verifies citations through MCP, and a read-only subagent type can lack MCP tools. Pass `references/synthesizer.md` verbatim, with each reviewer's full output inlined where marked. It returns an Accepted / Rejected / Backlog list.

## 4. Structural enforcement check

Move any Accepted item that a lint rule, script, metadata flag, or runtime check would enforce more reliably to Backlog. See the **encode-lessons-in-structure** principle skill.

## 5. Apply

Present the synthesizer's full Accepted / Rejected / Backlog output and wait for explicit approval before applying any Accepted edit. The user picks the subset and may redirect routings. Skill changes affect every future agent in the org. Do not auto-apply.

File each Backlog item to your team's devex or backlog tracker without waiting. Only the Accepted list waits for approval.

Follow each approved row's Routing exactly:

- Trivial existing-skill edit (a one-line bullet, a tightened sentence, a stale fact corrected): the parent does it directly.
- Substantive existing-skill edit (a new section, a new pattern table, more than ~10 lines): hand to the host's `skill-creator` skill (Codex ships it; on Claude Code, install it with `/plugin install skill-creator@claude-plugins-official`) and run its draft / test / iterate loop.
- `tune description: <skill path>` (the skill exists but didn't trigger when it should have): hand to `skill-creator` and run its description-optimization loop.
- `new skill via skill-creator: <kebab-name>`: hand creation to `skill-creator`. Do not invent the shape ad hoc.

If your environment ships a SKILL.md validator, run it on every touched skill before declaring done.

## 6. Summarize for the user

Short list, no preamble:

- Edits applied: `<skill path>`. What changed, one line each.
- New skills created: `<skill path>`. One line each (rare).
- Backlog filed to the devex tracker: `<issue title>` (`<tags>`). One line each.
- Dropped: one line per rejected finding + reason from the synthesizer.
