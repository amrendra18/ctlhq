# Fresh-clone scan brief template

The scan reads what the remote holds, so it catches what the local checks missed, such as an extra ref, a wrong identity, or a file that slipped in.
Give it to a fresh read-only agent that did not run the reset.

```markdown
# Brief: scan of <owner>/<name> on GitHub before it becomes public

You are a read-only reviewer. The operator will make this repository public after your report. Find anything sensitive or personal before that happens.

## Get the published copy

1. Clone it fresh over SSH into <scratch>: `git clone --mirror git@github.com:<owner>/<name>.git <scratch>/<name>.git`, then `git clone <scratch>/<name>.git <scratch>/<name>`. If cloning is refused, stop and report it.
2. Confirm what GitHub holds: every ref (`git -C <scratch>/<name>.git show-ref`), the commit count, and that `main` is commit <hash>.

## Scan everything GitHub would publish

1. **Commit and tag metadata:** author and committer names and emails, dates, time zones, signature key fingerprints, tag messages, commit messages. Flag anything beyond the intended public identity `<public name> <<public email>>` and the co-author `<co-author line>`.
2. **Private word list:** every word in <private word list>, ignoring case, in every file's content and path, including split forms (pieces joined across quotes, string concatenation, line breaks). Use `ctlhq-privacy-scan --root <scratch>/<name> --words <private word list>`, then again with `--joined`. It prints file:line and the word number, never a word. Judge each joined hit: pieces of one name or string are real; separate words of ordinary text are a false positive. The owner's name in the copyright line, the author metadata, and the repository's own address (`github.com/<owner>/...`) is intended; report it only anywhere else.
3. **Secrets:** run Gitleaks over the full history with `gitleaks git <scratch>/<name> --redact --no-banner`. It exits 0 with no leak and 1 with a leak. When `gitleaks` is not on PATH, look at `~/.ctlhq/bin/gitleaks`, where `ctlhq-first-push` looks first. Then search by hand for key shapes: private key headers, tokens, `AKIA`, `ghp_`, `sk-`, `xox`, passwords in URLs. A test fixture with a fake value is fine when it is clearly fake; say why.
4. **Machine and environment details:** home-folder paths (`/Users/<user>/`, `/home/<user>/`), machine and host names, local IP addresses, user names, temp-folder paths with session IDs, private project names, internal notes, dates that reveal private activity.
5. **Files that should not be public:** `.env`, keys, logs, `.local/`, caches, build output, large binaries, editor and OS files.
6. **Links:** list every external URL host; flag any private or internal address.

## Rules

1. Read-only for the operator's repositories and machine settings. Write only in <scratch>. Do not push, open issues, or change GitHub settings.
2. Never print a private word or a secret value; name file:line and kind.
3. Plain English, short sentences, no long dashes.

## Report

1. Verdict: safe to make public, or not, in one sentence.
2. A table with a leading # column: severity (high, medium, low), file:line or commit, what, why it matters, fix.
3. What you checked and the counts (files scanned, commits, hits per check), so the main agent can rerun any one.
```
