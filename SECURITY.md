# Security policy

## Report a vulnerability

Report a security problem privately, through GitHub private vulnerability reporting.
On the repository's GitHub page, open the **Security** tab and choose **Report a vulnerability**.
Do not open a public issue for a security problem.
If the Security tab has no **Report a vulnerability** button, open an issue that says only "security report, please contact me", with no details.
The maintainer then replies with a private way to send the report.

Include these details:

1. What you ran, what happened, and what you expected.
2. Your macOS version and your host (Claude Code or Codex).
3. The ctlhq commit you ran, from `git rev-parse HEAD` in your clone.

ctlhq has one maintainer.
The maintainer answers in the private report thread and fixes a confirmed problem before it is made public.

## In scope

1. The installer, `bin/ctlhq-install`. For example, a run that deletes or overwrites a file it did not create, writes outside its home folder (`$HOME`, or the folder given with `--home`), or writes through a link.
2. The push tools: `ctlhq-push`, `ctlhq-first-push`, and the pre-push hook that `ctlhq-first-push hook install` adds. For example, a push that reaches an owner or host other than the one in `~/.ctlhq/first-push.toml`, or output that shows a value `ctlhq-first-push` should hide.
3. The hooks: `ctlhq-reply-lint --hook` and `--hook-json`, and the ctlhq-first-push pre-push hook. For example, a hook that runs a program from the project it checks.
4. Transcript reading: `ctlhq-transcripts` and the skills that read transcripts. For example, `list`, `grep`, or `export` reading another workspace without `--all-workspaces`, or `export` writing outside its `--out` folder.
5. Any other tool in `bin/` that runs a program taken from the repository it checks, or that sends data over the network that its `--help` does not mention.

## Not in scope

1. Claude Code, Codex, and the models themselves. Report those to their makers.
2. Outside programs that ctlhq calls but does not ship, such as `git`, `gh`, `bun` and the packages `bun install` downloads, `node`, `python3`, `rg`, `jq`, `tart`, UTM, `gitleaks`, first-commit, and Chrome.
3. Lines you apply yourself: the PATH line and the Claude Code Stop hook entry that the installer prints, the Codex Stop hook entry in the README, and the `sudo git config --system` commands from `ctlhq-preflight`. A report is in scope when that text itself is unsafe.
4. Skill and playbook text. An agent decides how to follow it. Report an unsafe instruction in a skill as a normal issue.
5. Running ctlhq on Linux or Windows. ctlhq supports macOS only. A problem in `ctlhq-env` on macOS is in scope, even when its test machine runs Linux or Windows.

## Supported versions

Only the latest commit on the main branch gets security fixes.
