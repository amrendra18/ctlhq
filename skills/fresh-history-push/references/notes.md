# Notes

Each note is a problem seen in a real run, with its fix.

| # | Problem | Fix |
| --- | --- | --- |
| 1 | Agents are usually blocked from `rm -rf .git`, `git init`, and `git config`. | The operator runs the reset block. The agent prepares it, filled in and ready to paste. |
| 2 | Each commit records the committer's time zone, for example `-0700`. Once the commit is public, changing it needs a forced push. | Decide before the reset. `TZ=UTC git commit -F <message file>` records UTC. A tag records a time zone too, so tag with `TZ=UTC git tag -s` as well. |
| 3 | A push over an HTTPS address asks for a login. | Keep HTTPS for fetch and set an SSH push address with `git remote set-url --push`. SSH uses the loaded keys. |
| 4 | After a restart, the SSH agent may hold no key, and the push fails with "Permission denied". | Check with `ssh-add -l`. Load the key with `ssh-add --apple-use-keychain ~/.ssh/<key>`, or add `IdentityFile ~/.ssh/<key>` under `Host github.com` in `~/.ssh/config`. |
| 5 | A long pre-push hook can leave the SSH connection idle until GitHub drops it, and the push fails after the hook passes. | Add `ServerAliveInterval 30` under `Host github.com` in `~/.ssh/config`. |
| 6 | `ctlhq-commit` refuses a gate that ran on another tree. | Rerun `ctlhq-run-gate` after every change, then commit. |
| 7 | A test that reads `HEAD` fails while the repository has no commit yet. | Run the gate before the reset and again after the new commit, never in between. |
| 8 | Hooks in `.git/hooks` go away with `.git`. A project set up by first-commit has commit hooks that check the reset commit too. | Reinstall the project's hooks after `git init` and before the commit, when the project expects them. Expect them to check the reset commit like any other. |
| 9 | The project's private word list may hold the owner's name, which also appears in the repository's own address. | Treat a hit in the repository address, the copyright line, or the commit author as expected. Report a hit anywhere else. |
| 10 | Private vulnerability reporting exists only for public repositories. | The operator turns it on after switching visibility, in the repository's security settings. |
| 11 | Only the paths in `.gitignore` stay out of `git add -A`. Deleting `.git` also deletes the patterns in `.git/info/exclude`. | Move them into `.gitignore` before the reset. The tree ID check catches a miss. |
