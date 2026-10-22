# Reset block template

The operator runs this block in a terminal. Fill every `<placeholder>` before handing it over, so the block is ready to paste.

| # | Placeholder | What it holds |
| --- | --- | --- |
| 1 | `<repo>` | the repository's absolute path |
| 2 | `<old tree>` | the tree ID from the precondition step (`git rev-parse 'HEAD^{tree}'`) |
| 3 | `<backup archive>` | the archive from step 2 |
| 4 | `<public name>` | the author name the public will see |
| 5 | `<public email>` | the author email the public will see, for example a GitHub no-reply address |
| 6 | `<signing key>` | the SSH public key that signs, as `$HOME/.ssh/<key>.pub` or an absolute path, never with `~`. The block puts it in double quotes, so the shell expands `$HOME` and Git stores an absolute path. |
| 7 | `<message file>` | the commit message file, outside the repository |
| 8 | `<owner>` and `<name>` | the GitHub owner and repository name |

```bash
(
  set -eu
  cd "<repo>"
  test -d .git
  test "$(git rev-parse --show-toplevel)" = "$(pwd -P)"
  test "$(git rev-parse 'HEAD^{tree}')" = "<old tree>"
  test -s "<backup archive>"
  echo t | ssh-keygen -Y sign -n git -f "<signing key>" >/dev/null
  rm -rf .git
  git init -b main
  git config --local user.name "<public name>"
  git config --local user.email "<public email>"
  git config --local user.useConfigOnly true
  git config --local gpg.format ssh
  git config --local user.signingkey "<signing key>"
  git config --local commit.gpgsign true
  git config --local tag.gpgsign true
  git add -A
  git commit -F "<message file>"
  git remote add origin https://github.com/<owner>/<name>.git
  git remote set-url --push origin git@github.com:<owner>/<name>.git
  echo "reset done"
)
```

What each part does:

1. The parentheses run the block in a subshell, a separate copy of the shell. `set -eu` stops it at the first failed line or unset name. A failed `cd` stops everything, so `rm -rf .git` can never run in the wrong folder. The operator's terminal stays open either way.
2. The `test` lines stop the block unless `<repo>` holds its own `.git` folder and is the top folder of that repository. They also stop it unless the repository has the old tree and the backup archive is not empty. So `rm -rf .git` never runs in a subfolder, in a linked worktree, or in another repository.
3. `'HEAD^{tree}'` is in quotes because zsh with `extended_glob` reads `^` as a pattern.
4. The `ssh-keygen -Y sign` line signs a test text with the signing key. It fails when the key file is wrong or the SSH agent does not hold the key, so a signing problem stops the block before it deletes anything.
5. `rm -rf .git` deletes the whole history, branches, tags, stashes, hooks, and local settings. Only the backup from step 2 brings them back.
6. `git init -b main` starts an empty repository whose first branch is `main`.
7. The `--local` settings keep the identity and signing inside this repository. `user.useConfigOnly true` makes Git refuse to guess an identity from the machine.
8. `git add -A` stages every file that `.gitignore` does not ignore. So the tree must already match the old tree; step 4 proves it.
9. The fetch address uses HTTPS and the push address uses SSH. A push over HTTPS needs a login; a push over SSH uses the loaded keys.
10. The block prints `reset done` last. Without that line, a step failed. Read the error, and do not run the block again before the agent has checked the state.

Optional lines, decided by the operator before the run:

1. **Time zone.** Each commit records the committer's time zone, and it is public once pushed. To record UTC, write the commit line as `TZ=UTC git commit -F "<message file>"`.
2. **Commit hooks.** Hooks installed in `.git/hooks` go away with `.git`. When the project expects them (for example hooks installed by first-commit through pre-commit), reinstall them after `git init` and before `git commit`, with the project's own install command. They then check the reset commit like any other commit.
