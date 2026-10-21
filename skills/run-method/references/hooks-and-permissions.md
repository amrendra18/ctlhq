# Hooks and permissions, per harness

Claude Code facts were checked against its docs (hooks, permissions, settings, skills, sub-agents). Codex facts were checked against the Codex command-line tool, version 0.163.0 (its hook schemas and settings names). Each Codex section says what that check did not cover. Nothing here is applied until the operator says so; agents never edit their own permissions.

## 1. Claude Code (`~/.claude/settings.json`)

### 1.1 SessionStart on every start, resume and compaction

```json
"SessionStart": [
  {"matcher": "startup|resume|compact", "hooks": [
    {"type": "command", "command": "sh -c 'test -f BLOCKED.md && { echo \"== BLOCKED.md\"; cat BLOCKED.md; }; true'", "timeout": 3}
  ]}
]
```

Why: after a context reset an agent re-answers old questions and can reuse a stale approval. Printing `BLOCKED.md` on resume and compact puts the blockers back first; the agent then reads the README's "Open decisions" section and `PLAN.md` status, as the rule in ctlhq's `home/AGENTS.md` asks (the shared rules file; `ctlhq-install --agents-md` installs it as `~/.codex/AGENTS.md`). (From the Claude Code docs: matchers are `startup`, `resume`, `clear`, `compact`, `fork`; an entry with no matcher runs on all five.)

### 1.2 Stop hook: reply shape (advisory, exit 2 once)

`bin/ctlhq-reply-lint --hook` takes the last assistant text and exits 2 with its findings when the reply has no "Next step" line, runs over 400 words outside code blocks (600 with a table or list), or breaks another reply rule its `--help` lists. It exits 0 when `stop_hook_active` is true, so it fires at most once per reply.

```json
"Stop": [{"hooks": [{"type": "command", "command": "\"<repo-root>/bin/ctlhq-reply-lint\" --hook", "timeout": 5}]}]
```

Why: without the hook, few final replies end with a "Next step" line (`measure-sessions.md` shows how to count them). (From the Claude Code docs: the Stop hook receives `session_id`, `transcript_path`, `stop_hook_active` and `last_assistant_message`; exit 2 blocks the stop and Claude receives the stderr text. The tool uses `last_assistant_message`; the transcript format is internal and may change.)

### 1.3 Deny list for host-dangerous commands (global)

```json
"permissions": {"deny": [
  "Bash(pkill:*)", "Bash(killall:*)", "Bash(launchctl:*)", "Bash(open:*)",
  "Bash(git push:*)", "Bash(git config:*)", "Bash(git init:*)"
]}
```

Why: without this list a subagent can put a file in the real login keychain or `pkill` processes by name, a cleanup can stop a local service the operator relies on, and git config can change without asking. Raw pushes and `git init` stay with the operator. Deny `git push` and `git init` in the permission rules, and let agents push only through `ctlhq-push`.

### 1.4 Per-repository allow rules (`<repo>/.claude/settings.local.json`, personal, not committed)

```json
{"permissions": {"allow": [
  "Bash(git -C /Users/<you>/projects/<repo> add:*)",
  "Bash(git -C /Users/<you>/projects/<repo> commit -F .local/commit-:*)",
  "Bash(git add:*)",
  "Bash(git commit -F .local/commit-:*)"
]}}
```

Written by the bootstrap block (section 3) at repository creation. Rules match the command text as written, so the plain `git add:*` and `git commit -F .local/commit-:*` forms are enough inside a per-repository file; the `-C` forms are for a rule kept at the workspace level. Why: without it, `git add` and `git commit` are blocked in the middle of a build, and a rule added by hand mid-build tends to cover commit only.

### 1.5 Skills to install for parity with Codex

Give both harnesses the same skills, `run-method` and `blind-review` included. `bin/ctlhq-install` links every skill into `~/.claude/skills/` and `~/.codex/skills/`, except a skill that a layer's `docs/install.tsv` sends to other hosts; `bin/ctlhq-install --check` shows any skill one harness is missing.

## 2. Codex (`~/.codex/hooks.json`, `~/.codex/config.toml`)

### 2.1 SessionStart on resume too

Add the `BLOCKED.md` command from 1.1 as a second SessionStart hook without a matcher. Keep any SessionStart hook already there. Codex sends the same start sources as Claude Code (`startup`, `resume`, `clear`, `compact`, `fork`), so a hook without a matcher runs on all five. Codex runs a new hook only after the operator trusts it once, when Codex asks to review hooks.

### 2.2 Wait hooks fire only in the main thread

Codex has a `SubagentStop` hook, and it runs when any worker thread stops. A wait hook on `SubagentStop` that tells worker threads to "keep the requesting turn active" makes every worker poll; workers have polled for more than a day this way. Scope the hook to the thread that owns the wait, or remove `SubagentStop` and let the main thread wait.

### 2.3 Sandbox allowances per repository family

In `~/.codex/config.toml`, one `[sandbox_workspace_write]` block per family with `writable_roots` for the state folder and `.local/` caches, and the SSH agent socket for signing. Why: without them, builds hit repeated sandbox blocks, commit signing fails, and local services the agent asks through cannot be reached from the sandbox. Codex 0.163.0 has a `network.allow_unix_sockets` setting for sockets; the check did not cover where it goes in `config.toml`. When the socket cannot be allowed, the operator runs the signing step.

## 3. The bootstrap block (operator, once per new repository)

Before handing the block over, the agent writes the literal commit into `REV`: the commit of first-commit's latest tag. In a clone of first-commit, `git -C <first-commit clone> describe --tags --abbrev=0 main` names the tag, and `git -C <first-commit clone> rev-parse '<tag>^{commit}'` gives its commit. first-commit setup creates the Git repository, so the block has no `git init`.

```sh
(
  set -e
  cd /path/to/repo
  REV=<the 40-character commit of the latest first-commit tag>
  first-commit setup --dry-run --revision "$REV" --transport ssh --trust-self
  first-commit setup --revision "$REV" --transport ssh --trust-self
  first-commit doctor
  mkdir -p .local/briefs .local/reviews .claude
  cat > .claude/settings.local.json <<'JSON'
{"permissions":{"allow":["Bash(git add:*)","Bash(git commit -F .local/commit-:*)"]}}
JSON
)
```

Then the agent runs the preflight in `PROMPT.md` section 2 and writes `BLOCKED.md` for anything still missing.
