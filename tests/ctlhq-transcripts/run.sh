#!/usr/bin/env bash
# Tests for bin/ctlhq-transcripts against a synthetic fixture. No real transcripts are read.
# Prints "ok <name>" per check and "N checks passed" at the end. Exits 1 when any check fails.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$HERE/../../bin/ctlhq-transcripts"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FIX_HOME="$TMP/home"
WS=/fixture/ws
PASS=0
FAIL=0

ft() { HOME="$FIX_HOME" "$TOOL" "$@"; }
check() {
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then PASS=$((PASS + 1)); echo "ok $name"; else FAIL=$((FAIL + 1)); echo "FAIL $name"; fi
}
eq() { [ "$1" = "$2" ]; }
has() { grep -q -- "$2" <<<"$1"; }
exits() { local want="$1"; shift; "$@" >/dev/null 2>&1; [ "$?" = "$want" ]; }

python3 -I - "$TMP" <<'PY'
import json, os, sys
tmp = sys.argv[1]
proj = os.path.join(tmp, "home", ".claude", "projects")
ws = "/fixture/ws"
S1 = "aaaaaaaa-0000-0000-0000-000000000001"
S2 = "aaaaaaaa-0000-0000-0000-000000000002"

def line(kind, ts, content, sid, side=False, mid=None, **extra):
    o = {"type": kind, "timestamp": ts, "sessionId": sid, "cwd": ws, "isSidechain": side,
         "uuid": "u-" + ts, "parentUuid": None, "userType": "external", "version": "2.1.300",
         "message": {"role": kind, "content": content}}
    if mid:
        o["message"]["id"] = mid
    o.update(extra)
    return o

def write(path, rows, compact=False):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        for r in rows:
            fh.write(json.dumps(r, separators=((",", ":") if compact else None)) + "\n")

def tool_use(name, inp, i):
    return {"type": "tool_use", "id": f"tu-{i}", "name": name, "input": inp}

def tool_result(i):
    return [{"type": "tool_result", "tool_use_id": f"tu-{i}", "content": "ok"}]

s1 = [
    {"type": "last-prompt", "sessionId": S1, "lastPrompt": "noise", "leafUuid": "x"},
    line("user", "2026-10-01T09:59:59.000Z", "<local-command-caveat>Caveat: injected.</local-command-caveat>", S1, isMeta=True),
    line("user", "2026-10-01T10:00:00.000Z", "Please check the fixture skill and report.", S1, promptSource="typed", turnOrigin="human", origin={"kind": "human"}),
    line("assistant", "2026-10-01T10:00:05.000Z", [{"type": "thinking", "thinking": "private", "signature": "s"}, {"type": "text", "text": "I will read it."}], S1, mid="m1"),
    line("assistant", "2026-10-01T10:00:06.000Z", [tool_use("Read", {"file_path": "/fixture/skills/fixture-skill/SKILL.md"}, 1)], S1, mid="m1"),
    line("user", "2026-10-01T10:00:07.000Z", tool_result(1), S1, toolUseResult={}),
    line("assistant", "2026-10-01T10:00:10.000Z", [tool_use("Agent", {"description": "review", "prompt": "Review skills/other-skill/SKILL.md and say what it does.", "subagent_type": "general-purpose"}, 2)], S1, mid="m2"),
    line("user", "2026-10-01T10:00:20.000Z", tool_result(2), S1, toolUseResult={}),
    line("assistant", "2026-10-01T10:00:30.000Z", [tool_use("Bash", {"command": "fixture-tool --help && cat /fixture/notes/a.md 2>/dev/null", "description": "run the tool"}, 3)], S1, mid="m3"),
    line("user", "2026-10-01T10:00:31.000Z", tool_result(3), S1, toolUseResult={}),
    {"type": "attachment", "sessionId": S1, "timestamp": "2026-10-01T10:00:32.000Z", "attachment": {"type": "noise"}, "cwd": ws, "isSidechain": False, "uuid": "a1", "parentUuid": None},
    line("user", "2026-10-01T10:01:00.000Z", "<command-message>loop</command-message>\n<command-name>/loop</command-name>\n<command-args>5m check</command-args>", S1),
    line("assistant", "2026-10-01T10:01:05.000Z", [{"type": "text", "text": "Done."}], S1, mid="m4"),
    line("user", "2026-10-01T10:01:10.000Z", "<task-notification>agent finished</task-notification>", S1, origin={"kind": "task", "producer": "p", "runId": "r"}),
    line("user", "2026-10-01T10:02:00.000Z", "Thanks, also remove the temp file\n<system-reminder>hidden reminder</system-reminder>", S1),
    line("assistant", "2026-10-01T10:02:05.000Z", [{"type": "text", "text": "Removed."}], S1, mid="m5"),
]
write(os.path.join(proj, "-fixture-ws", S1 + ".jsonl"), s1)

s2 = [
    line("user", "2026-10-10T09:00:00.000Z", "Write the zebra notes file.", S2),
    line("assistant", "2026-10-10T09:00:05.000Z", [tool_use("Write", {"file_path": "/fixture/notes/zebra.md", "content": "stripes"}, 1)], S2, mid="n1"),
    line("user", "2026-10-10T09:00:06.000Z", tool_result(1), S2, toolUseResult={}),
    line("assistant", "2026-10-10T09:00:10.000Z", [tool_use("Edit", {"file_path": "/fixture/notes/zebra.md", "old_string": "stripes", "new_string": "black stripes"}, 2)], S2, mid="n2"),
    line("user", "2026-10-10T09:00:11.000Z", tool_result(2), S2, toolUseResult={}),
    line("assistant", "2026-10-10T09:00:15.000Z", [{"type": "text", "text": "Saved."}], S2, mid="n3"),
    line("user", "2026-10-10T09:05:00.000Z", "Great, now stop.", S2),
    line("assistant", "2026-10-10T09:05:05.000Z", [{"type": "text", "text": "Stopped."}], S2, mid="n4"),
]
write(os.path.join(proj, "-fixture-ws", S2 + ".jsonl"), s2)

sub = [
    line("user", "2026-10-01T10:00:11.000Z", "You are a subagent. Read skills/fixture-skill/SKILL.md and report.", S1, side=True, agentId="abc"),
    line("assistant", "2026-10-01T10:00:12.000Z", [tool_use("Read", {"file_path": "/fixture/skills/fixture-skill/SKILL.md"}, 1)], S1, side=True, mid="p1", agentId="abc"),
    line("user", "2026-10-01T10:00:13.000Z", tool_result(1), S1, side=True, agentId="abc"),
    line("assistant", "2026-10-01T10:00:14.000Z", [{"type": "text", "text": "It is a fixture."}], S1, side=True, mid="p2", agentId="abc"),
]
write(os.path.join(proj, "-fixture-ws", S1, "subagents", "agent-abc.jsonl"), sub)
with open(os.path.join(proj, "-fixture-ws", S1, "subagents", "agent-abc.meta.json"), "w") as fh:
    json.dump({"agentType": "general-purpose", "description": "review", "toolUseId": "tu-2"}, fh)

S3 = "bbbbbbbb-0000-0000-0000-000000000003"
other = [
    {**line("user", "2026-10-05T08:00:00.000Z", "hello from the other workspace", S3), "cwd": "/other/ws"},
    {**line("assistant", "2026-10-05T08:00:05.000Z", [{"type": "text", "text": "Hello."}], S3, mid="q1"), "cwd": "/other/ws"},
]
write(os.path.join(proj, "-other-ws", S3 + ".jsonl"), other)

# Codex fixtures: one root session for the fixture workspace, one sub-agent thread.
sess = os.path.join(tmp, "home", ".codex", "sessions", "2026", "10", "16")
C1 = "cccccccc-0000-0000-0000-000000000003"
C2 = "cccccccc-0000-0000-0000-000000000004"

def cx(kind, ts, payload):
    return {"timestamp": ts, "type": kind, "payload": payload}

codex1 = [
    cx("session_meta", "2026-10-16T10:00:00.000Z", {"id": C1, "timestamp": "2026-10-16T10:00:00.000Z", "cwd": ws, "originator": "codex_cli", "cli_version": "0.0", "source": "cli"}),
    cx("event_msg", "2026-10-16T10:00:01.000Z", {"type": "task_started", "turn_id": "t1"}),
    cx("response_item", "2026-10-16T10:00:01.500Z", {"type": "message", "role": "user", "content": [{"type": "input_text", "text": "<environment_context>\n  <cwd>/fixture/ws</cwd>\n</environment_context>"}]}),
    cx("event_msg", "2026-10-16T10:00:02.000Z", {"type": "item_completed", "turn_id": "t1", "item": {"type": "UserMessage", "id": "i1", "content": [{"type": "text", "text": "Codex, list the fixture files.", "text_elements": []}]}}),
    cx("response_item", "2026-10-16T10:00:02.500Z", {"type": "message", "role": "user", "content": [{"type": "input_text", "text": "Codex, list the fixture files."}]}),
    cx("response_item", "2026-10-16T10:00:03.000Z", {"type": "reasoning", "summary": [], "encrypted_content": "zzz"}),
    cx("response_item", "2026-10-16T10:00:04.000Z", {"type": "custom_tool_call", "name": "exec", "call_id": "c1", "input": json.dumps({"cmd": "ls /fixture/ws/skills", "workdir": ws}), "status": "completed"}),
    cx("response_item", "2026-10-16T10:00:05.000Z", {"type": "custom_tool_call_output", "call_id": "c1", "output": "x"}),
    cx("response_item", "2026-10-16T10:00:06.000Z", {"type": "message", "role": "assistant", "phase": "final_answer", "content": [{"type": "output_text", "text": "Two files."}]}),
    cx("event_msg", "2026-10-16T10:00:06.500Z", {"type": "item_completed", "turn_id": "t1", "item": {"type": "AgentMessage", "id": "i2", "phase": "final_answer", "content": [{"type": "Text", "text": "Two files."}]}}),
    cx("event_msg", "2026-10-16T10:00:07.000Z", {"type": "task_complete", "turn_id": "t1"}),
]
write(os.path.join(sess, f"rollout-2026-10-16T10-00-00-{C1}.jsonl"), codex1, compact=True)
codex2 = [
    cx("session_meta", "2026-10-16T10:01:00.000Z", {"id": C2, "timestamp": "2026-10-16T10:01:00.000Z", "cwd": ws, "originator": "codex_cli", "source": "cli", "parent_thread_id": C1}),
    cx("response_item", "2026-10-16T10:01:01.000Z", {"type": "message", "role": "user", "content": [{"type": "input_text", "text": "Sub task: count the files."}]}),
    cx("response_item", "2026-10-16T10:01:02.000Z", {"type": "message", "role": "assistant", "phase": "final_answer", "content": [{"type": "output_text", "text": "Two."}]}),
]
write(os.path.join(sess, f"rollout-2026-10-16T10-01-00-{C2}.jsonl"), codex2, compact=True)

# Skill tool loads (R16): a Claude session and a Codex session outside the fixture workspace.
S4 = "dddddddd-0000-0000-0000-000000000004"
s4 = [
    line("user", "2026-10-12T09:00:00.000Z", "Help me check the plan.", S4),
    line("assistant", "2026-10-12T09:00:01.000Z", [tool_use("Skill", {"skill": "fixture-skill", "args": "check the plan"}, 1)], S4, mid="r1"),
    line("user", "2026-10-12T09:00:02.000Z", tool_result(1), S4, toolUseResult={}),
    line("assistant", "2026-10-12T09:00:03.000Z", [tool_use("Bash", {"command": "cat /fixture/skills/other-skill/SKILL.md"}, 2)], S4, mid="r2"),
    line("user", "2026-10-12T09:00:04.000Z", tool_result(2), S4, toolUseResult={}),
    line("assistant", "2026-10-12T09:00:05.000Z", [tool_use("Skill", {"command": "other-skill"}, 3)], S4, mid="r3"),
    line("user", "2026-10-12T09:00:06.000Z", tool_result(3), S4, toolUseResult={}),
    line("assistant", "2026-10-12T09:00:07.000Z", [tool_use("Skill", {"skill": "plugin-pack:pdf"}, 4)], S4, mid="r4"),
    line("user", "2026-10-12T09:00:08.000Z", tool_result(4), S4, toolUseResult={}),
    line("assistant", "2026-10-12T09:00:09.000Z", [tool_use("Skill", {"skill": "fixture-skill"}, 5), tool_use("Skill", {}, 6)], S4, mid="r5"),
    line("user", "2026-10-12T09:00:10.000Z", tool_result(5), S4, toolUseResult={}),
    line("assistant", "2026-10-12T09:00:11.000Z", [tool_use("Skill", {"command": "fixture-tool"}, 7)], S4, mid="r6"),
    line("user", "2026-10-12T09:00:12.000Z", tool_result(7), S4, toolUseResult={}),
    line("assistant", "2026-10-12T09:00:13.000Z", [{"type": "text", "text": "Done."}], S4, mid="r7"),
]
write(os.path.join(tmp, "routing", S4 + ".jsonl"), s4)
codex3 = [
    cx("session_meta", "2026-10-16T11:00:00.000Z", {"id": "cccccccc-0000-0000-0000-000000000005", "timestamp": "2026-10-16T11:00:00.000Z", "cwd": "/routing/ws", "originator": "codex_cli", "source": "cli"}),
    cx("response_item", "2026-10-16T11:00:01.000Z", {"type": "message", "role": "user", "content": [{"type": "input_text", "text": "Check the plan."}]}),
    cx("response_item", "2026-10-16T11:00:02.000Z", {"type": "custom_tool_call", "name": "exec", "call_id": "c1", "input": json.dumps({"cmd": "sed -n 1,80p /fixture/skills/fixture-skill/SKILL.md"}), "status": "completed"}),
    cx("response_item", "2026-10-16T11:00:03.000Z", {"type": "custom_tool_call_output", "call_id": "c1", "output": "x"}),
    cx("response_item", "2026-10-16T11:00:04.000Z", {"type": "message", "role": "assistant", "phase": "final_answer", "content": [{"type": "output_text", "text": "Read it."}]}),
]
write(os.path.join(tmp, "routing", "rollout-codex-skill.jsonl"), codex3, compact=True)
# SKILL.md paths with ".." segments, as ctlhq-mode's "../<name>/SKILL.md" rule produces them.
S6 = "eeeeeeee-0000-0000-0000-000000000006"
s6 = [
    line("user", "2026-10-12T10:00:00.000Z", "Load the leaf skills.", S6),
    line("assistant", "2026-10-12T10:00:01.000Z", [tool_use("Read", {"file_path": "/fixture/skills/fixture-skill/../other-skill/SKILL.md"}, 1)], S6, mid="u1"),
    line("user", "2026-10-12T10:00:02.000Z", tool_result(1), S6, toolUseResult={}),
    line("assistant", "2026-10-12T10:00:03.000Z", [tool_use("Bash", {"command": "cat skills/other-skill/./../fixture-skill/SKILL.md"}, 2)], S6, mid="u2"),
    line("user", "2026-10-12T10:00:04.000Z", tool_result(2), S6, toolUseResult={}),
    line("assistant", "2026-10-12T10:00:05.000Z", [{"type": "text", "text": "Done."}], S6, mid="u3"),
]
write(os.path.join(tmp, "routing", S6 + ".jsonl"), s6)
# Typed slash commands: Claude Code records /<name> in the user turn as <command-name>, not as a tool call.
S7 = "ffffffff-0000-0000-0000-000000000007"
s7 = [
    line("user", "2026-10-12T11:00:00.000Z", "<command-message>fixture-skill</command-message>\n<command-name>/fixture-skill</command-name>\n<command-args>check the plan</command-args>", S7),
    line("user", "2026-10-12T11:00:00.100Z", [{"type": "text", "text": "Base directory for this skill: /fixture/skills/fixture-skill\n\n# Fixture skill"}], S7, isMeta=True),
    line("assistant", "2026-10-12T11:00:01.000Z", [{"type": "text", "text": "Mentioning <command-name>/other-skill</command-name> in a reply is no load."}], S7, mid="w1"),
    line("user", "2026-10-12T11:00:02.000Z", "<command-message>loop</command-message>\n<command-name>/loop</command-name>\n<command-args>5m check</command-args>", S7),
    line("assistant", "2026-10-12T11:00:03.000Z", [{"type": "text", "text": "Looping."}], S7, mid="w2"),
    line("user", "2026-10-12T11:00:04.000Z", "<command-message>pack:other-skill</command-message>\n<command-name>/pack:other-skill</command-name>", S7),
    line("assistant", "2026-10-12T11:00:05.000Z", [tool_use("Read", {"file_path": "/fixture/skills/fixture-skill/SKILL.md"}, 1)], S7, mid="w3"),
    line("user", "2026-10-12T11:00:06.000Z", tool_result(1), S7, toolUseResult={}),
]
write(os.path.join(tmp, "routing", S7 + ".jsonl"), s7)

# Unsupported inputs and a fixture skills folder.
with open(os.path.join(tmp, "other.jsonl"), "w") as fh:
    fh.write('{"foo": 1}\n')
with open(os.path.join(tmp, "plain.txt"), "w") as fh:
    fh.write("not json\n")
for name in ("fixture-skill", "other-skill"):
    os.makedirs(os.path.join(tmp, "skills", name, "bin"), exist_ok=True)
    with open(os.path.join(tmp, "skills", name, "SKILL.md"), "w") as fh:
        fh.write(f"---\nname: {name}\n---\n")
with open(os.path.join(tmp, "skills", "fixture-skill", "bin", "fixture-tool"), "w") as fh:
    fh.write("#!/bin/sh\necho hi\n")
PY

P="$FIX_HOME/.claude/projects"
S1="$P/-fixture-ws/aaaaaaaa-0000-0000-0000-000000000001.jsonl"
S2="$P/-fixture-ws/aaaaaaaa-0000-0000-0000-000000000002.jsonl"
SUB="$P/-fixture-ws/aaaaaaaa-0000-0000-0000-000000000001/subagents/agent-abc.jsonl"
OTHER="$P/-other-ws/bbbbbbbb-0000-0000-0000-000000000003.jsonl"
CX1="$FIX_HOME/.codex/sessions/2026/10/16/rollout-2026-10-16T10-00-00-cccccccc-0000-0000-0000-000000000003.jsonl"
CX2="$FIX_HOME/.codex/sessions/2026/10/16/rollout-2026-10-16T10-01-00-cccccccc-0000-0000-0000-000000000004.jsonl"
touch -t 202610011002 "$S1"; touch -t 202610011001 "$SUB"; touch -t 202610100905 "$S2"; touch -t 202610050000 "$OTHER"
touch -t 202610161000 "$CX1"; touch -t 202610161001 "$CX2"

# 1. help and usage
check "help exits 0" exits 0 "$TOOL" --help
check "help first line" has "$("$TOOL" --help | head -1)" "^ctlhq-transcripts: "
check "no args exits 2" exits 2 "$TOOL"
check "unknown command exits 2" exits 2 ft bogus
check "bad --since exits 2" exits 2 ft list --workspace "$WS" --since soon

# 2. dir
check "dir prints the slug folder" eq "$(ft dir --workspace "$WS")" "$P/-fixture-ws"
check "dir missing folder exits 1" exits 1 ft dir --workspace /nope/ws

# 3. list
LIST="$(ft list --workspace "$WS")"
check "list exits 0" exits 0 ft list --workspace "$WS"
check "list has 2 rows" eq "$(wc -l <<<"$LIST" | tr -d ' ')" 2
check "list newest first" eq "$(head -1 <<<"$LIST" | cut -f1)" "$S2"
check "list has 8 columns" eq "$(head -1 <<<"$LIST" | awk -F'\t' '{print NF}')" 8
ROW1="$(grep -- "$S1" <<<"$LIST")"
check "list s1 workspace" eq "$(cut -f2 <<<"$ROW1")" "$WS"
check "list s1 started" eq "$(cut -f3 <<<"$ROW1")" "2026-10-01T09:59:59Z"
check "list s1 ended" eq "$(cut -f4 <<<"$ROW1")" "2026-10-01T10:02:05Z"
check "list s1 turns 8" eq "$(cut -f5 <<<"$ROW1")" 8
check "list s1 operator_turns 3" eq "$(cut -f6 <<<"$ROW1")" 3
check "list s1 bytes" eq "$(cut -f7 <<<"$ROW1")" "$(stat -f %z "$S1")"
check "list s1 first prompt" eq "$(cut -f8 <<<"$ROW1")" "Please check the fixture skill and report."
check "list s2 operator_turns 2" eq "$(grep -- "$S2" <<<"$LIST" | cut -f6)" 2
check "list --json parses to 2" eq "$(ft list --workspace "$WS" --json | python3 -I -c 'import json,sys; d=json.load(sys.stdin); print(len(d), d[0]["session_id"])')" "2 aaaaaaaa-0000-0000-0000-000000000002"
check "list --grep zebra one row" eq "$(ft list --workspace "$WS" --grep zebra | wc -l | tr -d ' ')" 1
check "list --grep all words" eq "$(ft list --workspace "$WS" --grep zebra stop | cut -f1)" "$S2"
check "list --grep miss exits 1" exits 1 ft list --workspace "$WS" --grep nothing-here-at-all
check "list --since ISO keeps newer" eq "$(ft list --workspace "$WS" --since 2026-10-05 | cut -f1)" "$S2"
check "list --since future exits 1" exits 1 ft list --workspace "$WS" --since 2026-10-20T00:00:00Z
check "list --exclude-current drops newest" eq "$(ft list --workspace "$WS" --exclude-current | cut -f1)" "$S1"
check "list --subagents 3 rows" eq "$(ft list --workspace "$WS" --subagents | wc -l | tr -d ' ')" 3
check "list default stays in workspace" exits 1 ft list --workspace /other/ws --grep zebra
check "list --all-workspaces 3 rows" eq "$(ft list --workspace "$WS" --all-workspaces | wc -l | tr -d ' ')" 3
check "list --all-workspaces --subagents 4 rows" eq "$(ft list --workspace "$WS" --all-workspaces --subagents | wc -l | tr -d ' ')" 4
check "list other workspace column" eq "$(ft list --workspace "$WS" --all-workspaces | grep -- "$OTHER" | cut -f2)" "/other/ws"

# 4. current
check "current is newest" eq "$(ft current --workspace "$WS")" "$S2"
check "current --match" eq "$(ft current --workspace "$WS" --match "fixture skill")" "$S1"
check "current --match miss exits 1" exits 1 ft current --workspace "$WS" --match no-such-words
check "current missing workspace exits 1" exits 1 ft current --workspace /nope/ws

# 5. turns
OPS="$(ft turns "$S1" --role operator)"
check "turns operator 3 lines" eq "$(wc -l <<<"$OPS" | tr -d ' ')" 3
check "turns operator slash command" eq "$(sed -n 2p <<<"$OPS" | cut -f3)" "/loop 5m check"
check "turns operator strips system-reminder" eq "$(sed -n 3p <<<"$OPS" | cut -f3)" "Thanks, also remove the temp file"
check "turns operator role column" eq "$(cut -f2 <<<"$OPS" | sort -u)" "operator"
ALL="$(ft turns "$S1")"
check "turns all 13 lines" eq "$(wc -l <<<"$ALL" | tr -d ' ')" 13
check "turns role counts" eq "$(cut -f2 <<<"$ALL" | sort | uniq -c | awk '{print $2"="$1}' | tr '\n' ' ')" "assistant=5 operator=3 system=2 tool=3 "
check "turns merges one reply" has "$(ft turns "$S1" --role assistant | head -1)" "I will read it.\\\\n\[tool: Read\]"
check "turns tool marker" eq "$(grep -c '\[tool-result\]' <<<"$ALL")" 3
check "turns --text-only 8 lines" eq "$(ft turns "$S1" --text-only | wc -l | tr -d ' ')" 8
check "turns --text-only drops markers" exits 1 grep -q '\[tool' <<<"$(ft turns "$S1" --text-only)"
check "turns --index first column" eq "$(ft turns "$S1" --index | head -1 | cut -f1)" 1
check "turns --json" eq "$(ft turns "$S1" --json | python3 -I -c 'import json,sys; d=json.load(sys.stdin); print(len(d), d[2]["tools"][0], d[2]["index"])')" "13 Read 3"
check "turns ts trimmed to seconds" eq "$(head -1 <<<"$OPS" | cut -f1)" "2026-10-01T10:00:00Z"
check "turns --text-only assistant 2 lines" eq "$(ft turns "$S2" --role assistant --text-only | cut -f3 | tr '\n' ' ')" "Saved. Stopped. "
check "turns no operator in subagent exits 1" exits 1 ft turns "$SUB" --role operator
check "turns subagent parent role" eq "$(ft turns "$SUB" | head -1 | cut -f2)" "parent"
check "turns missing file exits 1" exits 1 ft turns /nope/file.jsonl
check "turns unknown json exits 3" exits 3 ft turns "$TMP/other.jsonl"
check "turns plain text exits 3" exits 3 ft turns "$TMP/plain.txt"

# 6. tail
TAIL="$(ft tail "$S1" -n 2)"
check "tail 2 headers" eq "$(grep -c '^--- ' <<<"$TAIL")" 2
check "tail last text" eq "$(tail -1 <<<"$TAIL")" "Removed."
check "tail bad -n exits 2" exits 2 ft tail "$S1" -n 0

# 7. files
FILES="$(ft files "$S1")"
check "files 2 rows" eq "$(wc -l <<<"$FILES" | tr -d ' ')" 2
check "files read row" has "$FILES" "^1	read=1	/fixture/skills/fixture-skill/SKILL.md$"
check "files bash row" has "$FILES" "^1	bash=1	/fixture/notes/a.md$"
check "files --skills" eq "$(ft files "$S1" --skills)" "1	read=1	/fixture/skills/fixture-skill/SKILL.md"
check "files counts write and edit" eq "$(ft files "$S2")" "2	edit=1,write=1	/fixture/notes/zebra.md"
check "files none exits 1" exits 1 ft files "$OTHER"

# 8. skills-used
SK="$(ft skills-used "$S1" --skills-dir "$TMP/skills")"
check "skills-used 3 rows" eq "$(wc -l <<<"$SK" | tr -d ' ')" 3
check "skills-used read" eq "$(sed -n 1p <<<"$SK")" "fixture-skill	read	3"
check "skills-used agent-prompt" eq "$(sed -n 2p <<<"$SK")" "other-skill	agent-prompt	5"
check "skills-used tool-call" eq "$(sed -n 3p <<<"$SK")" "fixture-skill	tool-call	7"
check "skills-used none exits 1" exits 1 ft skills-used "$S2" --skills-dir "$TMP/skills"
check "skills-used subagent read" eq "$(ft skills-used "$SUB" --skills-dir "$TMP/skills")" "fixture-skill	read	2"
# 8b. skills-used counts Claude Code Skill tool loads (R16)
SK4="$(ft skills-used "$TMP/routing/dddddddd-0000-0000-0000-000000000004.jsonl" --skills-dir "$TMP/skills")"
check "skills-used skill tool 5 rows" eq "$(wc -l <<<"$SK4" | tr -d ' ')" 5
check "skills-used skill-tool current input" eq "$(sed -n 1p <<<"$SK4")" "fixture-skill	skill-tool	2"
check "skills-used shell-read is the weak row" eq "$(sed -n 2p <<<"$SK4")" "other-skill	shell-read	4"
check "skills-used skill-tool older command input" eq "$(sed -n 3p <<<"$SK4")" "other-skill	skill-tool	6"
check "skills-used skill-tool keeps a plugin prefix" eq "$(sed -n 4p <<<"$SK4")" "plugin-pack:pdf	skill-tool	8"
check "skills-used skill-tool name is not a tool-call" eq "$(sed -n 5p <<<"$SK4")" "fixture-tool	skill-tool	12"
check "skills-used repeat load keeps first turn" eq "$(grep -c '^fixture-skill	' <<<"$SK4")" 1
check "skills-used Skill call is no tool-call" eq "$(grep -c '	tool-call	' <<<"$SK4")" 0
check "skills-used codex exec read is shell-read" eq "$(ft skills-used "$TMP/routing/rollout-codex-skill.jsonl" --skills-dir "$TMP/skills")" "fixture-skill	shell-read	2"
check "skills-used help names skill-tool" has "$("$TOOL" --help)" "skill-tool"
# 8c. skills-used normalizes ".." and "." segments before it matches skills/<name>/SKILL.md
SK6="$(ft skills-used "$TMP/routing/eeeeeeee-0000-0000-0000-000000000006.jsonl" --skills-dir "$TMP/skills")"
check "skills-used ../ read" eq "$(sed -n 1p <<<"$SK6")" "other-skill	read	2"
check "skills-used ./../ shell-read" eq "$(sed -n 2p <<<"$SK6")" "fixture-skill	shell-read	4"
check "skills-used ../ paths give 2 rows" eq "$(wc -l <<<"$SK6" | tr -d ' ')" 2
# 8d. skills-used reports a typed /<skill> (<command-name> in a user turn) as slash
SK7="$(ft skills-used "$TMP/routing/ffffffff-0000-0000-0000-000000000007.jsonl" --skills-dir "$TMP/skills")"
check "skills-used slash 3 rows" eq "$(wc -l <<<"$SK7" | tr -d ' ')" 3
check "skills-used slash typed skill" eq "$(sed -n 1p <<<"$SK7")" "fixture-skill	slash	1"
check "skills-used slash keeps a plugin prefix" eq "$(sed -n 2p <<<"$SK7")" "pack:other-skill	slash	6"
check "skills-used slash keeps the read label" eq "$(sed -n 3p <<<"$SK7")" "fixture-skill	read	7"
check "skills-used slash skips a command with no skill" eq "$(grep -c '^loop	' <<<"$SK7")" 0
check "skills-used slash skips an assistant mention" eq "$(grep -c '^other-skill	' <<<"$SK7")" 0
check "skills-used slash missing skills-dir gives no slash row" eq "$(ft skills-used "$TMP/routing/ffffffff-0000-0000-0000-000000000007.jsonl" --skills-dir "$TMP/none" | cut -f2 | sort -u)" "read"
check "skills-used help names slash" has "$("$TOOL" --help)" "of a typed /<name> that expanded the skill"

# 9. grep
G="$(ft grep zebra --workspace "$WS")"
check "grep one hit" eq "$(wc -l <<<"$G" | tr -d ' ')" 1
check "grep columns" eq "$(awk -F'\t' '{print NF, $3}' <<<"$G")" "3 $S2"
check "grep match count" eq "$(cut -f2 <<<"$G")" 3
check "grep -i" eq "$(ft grep -i ZEBRA --workspace "$WS" | cut -f3)" "$S2"
check "grep case sensitive misses" exits 1 ft grep ZEBRA --workspace "$WS"
check "grep --all-workspaces" eq "$(ft grep "other workspace" --workspace "$WS" --all-workspaces | cut -f3)" "$OTHER"
check "grep stays in workspace" exits 1 ft grep "other workspace" --workspace "$WS"
check "grep bad pattern exits 2" exits 2 ft grep "[" --workspace "$WS"
check "grep --subagents" eq "$(ft grep "subagent" --workspace "$WS" --subagents | cut -f3)" "$SUB"

# 10. slice
SL="$(ft list --workspace "$WS" | ft slice --slices 2)"
check "slice 2 lines" eq "$(wc -l <<<"$SL" | tr -d ' ')" 2
check "slice bytes column" eq "$(cut -f1 <<<"$SL" | sort -n | head -1 | grep -c '^[0-9][0-9]*$')" 1
check "slice covers both paths" eq "$(cut -f2- <<<"$SL" | tr '\t' '\n' | sort)" "$(printf '%s\n%s\n' "$S1" "$S2" | sort)"
check "slice bytes sums" eq "$(cut -f1 <<<"$SL" | paste -sd+ - | bc)" "$(( $(stat -f %z "$S1") + $(stat -f %z "$S2") ))"
check "slice --by mtime keeps order" eq "$(ft list --workspace "$WS" | ft slice --slices 2 --by mtime | cut -f2)" "$(printf '%s\n%s\n' "$S2" "$S1")"
check "slice too few exits 1" exits 1 bash -c "HOME='$FIX_HOME' '$TOOL' list --workspace '$WS' | HOME='$FIX_HOME' '$TOOL' slice --slices 3"
check "slice header tolerated" eq "$(printf 'path\tworkspace\tstarted\tended\tturns\toperator_turns\tbytes\tfirst\n/a\tw\ts\te\t1\t1\t10\tp\n' | ft slice --slices 1)" "10	/a"
check "slice bad rows exit 2" exits 2 bash -c "echo 'junk' | '$TOOL' slice --slices 1"

# 11. export
EX="$(ft export --out "$TMP/out" --workspace "$WS")"
check "export exits 0" exits 0 ft export --out "$TMP/out-again" --workspace "$WS"
check "export counts" eq "$(grep -E '^(sessions|turns)' <<<"$EX" | tr '\n' ' ')" "sessions	2 turns	5 "
check "export s1 file" eq "$(wc -l <"$TMP/out/claude/-fixture-ws/aaaaaaaa-0000-0000-0000-000000000001.txt" | tr -d ' ')" 3
check "export s2 file" eq "$(wc -l <"$TMP/out/claude/-fixture-ws/aaaaaaaa-0000-0000-0000-000000000002.txt" | tr -d ' ')" 2
check "export line shape" eq "$(head -1 "$TMP/out/claude/-fixture-ws/aaaaaaaa-0000-0000-0000-000000000002.txt")" "2026-10-10T09:00:00Z	operator	Write the zebra notes file."
check "export index rows" eq "$(wc -l <"$TMP/out/index.tsv" | tr -d ' ')" 3
check "export index header" eq "$(head -1 "$TMP/out/index.tsv")" "path	workspace	started	ended	turns	operator_turns	bytes	first_prompt"
check "export --role all --all-workspaces" eq "$(ft export --out "$TMP/out2" --workspace "$WS" --role all --all-workspaces | head -1)" "sessions	3"
check "export --role all escapes newlines" eq "$(grep -c 'I will read it\.\\n\[tool: Read\]' "$TMP/out2/claude/-fixture-ws/aaaaaaaa-0000-0000-0000-000000000001.txt")" 1
check "export nothing exits 1" exits 1 ft export --out "$TMP/out3" --workspace "$WS" --since 2026-10-20
check "export nothing writes no index" exits 1 test -e "$TMP/out3/index.tsv"

# 12. codex host
check "codex dir" eq "$(ft dir --host codex)" "$FIX_HOME/.codex/sessions"
CL="$(ft list --host codex --workspace "$WS")"
check "codex list 1 row" eq "$(wc -l <<<"$CL" | tr -d ' ')" 1
check "codex list columns" eq "$(cut -f2,5,6,8 <<<"$CL")" "$WS	3	1	Codex, list the fixture files."
check "codex list --subagents 2 rows" eq "$(ft list --host codex --workspace "$WS" --subagents | wc -l | tr -d ' ')" 2
check "codex list other workspace exits 1" exits 1 ft list --host codex --workspace /other/ws
check "codex turns operator" eq "$(ft turns "$CX1" --role operator | cut -f2,3)" "operator	Codex, list the fixture files."
check "codex turns role counts" eq "$(ft turns "$CX1" | cut -f2 | sort | uniq -c | awk '{print $2"="$1}' | tr '\n' ' ')" "assistant=2 operator=1 system=1 tool=1 "
check "codex files from exec" eq "$(ft files "$CX1")" "1	bash=1	/fixture/ws/skills"
check "codex current" eq "$(ft current --host codex --workspace "$WS")" "$CX1"
check "codex subagent parent role" eq "$(ft turns "$CX2" | head -1 | cut -f2)" "parent"
check "codex export" eq "$(ft export --host codex --out "$TMP/out4" --workspace "$WS" | head -2 | tr '\n' ' ')" "sessions	1 turns	1 "
check "codex export file" eq "$(cat "$TMP/out4/codex/-fixture-ws/cccccccc-0000-0000-0000-000000000003.txt")" "2026-10-16T10:00:02Z	operator	Codex, list the fixture files."
check "codex grep" eq "$(ft grep "fixture files" --host codex --workspace "$WS" | cut -f3)" "$CX1"

echo
if [ "$FAIL" -ne 0 ]; then echo "$PASS checks passed, $FAIL failed"; exit 1; fi
echo "$PASS checks passed"
