# Measure reply quality in a session

Run these steps on any finished build session, in Claude Code or Codex. Every command below ships in ctlhq's `bin/` folder.

1. Find the session file. `ctlhq-transcripts list` prints the current workspace's sessions, newest first (add `--host codex` for Codex).
2. Count the reply measures. The script below reads one session through `ctlhq-transcripts turns` and prints rows 1 to 3 of the table. A final reply is the last assistant turn before the next operator turn, or before the end of the session.

```sh
ctlhq-transcripts turns <session.jsonl> --role all --text-only | python3 -c '
import re, statistics, sys
rows = [l.rstrip("\n").split("\t", 2) for l in sys.stdin if l.count("\t") >= 2]
finals, last = [], None
for _, role, text in rows:
    if role == "assistant":
        last = text.replace("\\n", "\n")
    elif role == "operator" and last is not None:
        finals.append(last)
        last = None
if last is not None:
    finals.append(last)
n = len(finals) or 1
status = re.compile(r"^.*\b(status:|proposed|implemented|tested|committed|gate|installed)\b", re.I | re.M)
print("final replies", len(finals))
print("1. ending with Next step, percent", round(100 * sum("next step" in f.strip().split("\n")[-1].lower() for f in finals) / n))
print("2. with a status line, percent", round(100 * sum(bool(status.search(f)) for f in finals) / n))
print("3. median words", statistics.median([len(f.split()) for f in finals] or [0]))
'
```

3. Judge rows 4 to 9 by reading `ctlhq-transcripts turns <session.jsonl> --role operator --text-only`, and check `PLAN.md` and `git log` for the goal state, the acceptance record and the commits.

Bars:

| # | Measure | Bar |
| --- | --- | --- |
| 1 | Final replies ending with "Next step" | at least 90 percent |
| 2 | Final replies with a status line | at least 90 percent |
| 3 | Median final reply, words | under 250 |
| 4 | Operator nudges to continue | 0 |
| 5 | Operator re-explanations | at most 1 per session |
| 6 | Goal state written before the first build | yes, in PLAN.md |
| 7 | Acceptance recorded in the operator's words | yes |
| 8 | Context resets per session | under 3 |
| 9 | Commits reported after a gate exit line | 100 percent |

Operator messages typed while the agent was working are easy to miss when you read only the operator turns. In a Claude Code transcript, count them from the raw file with `grep -c 'The user sent a new message while you were working' <session.jsonl>`.
