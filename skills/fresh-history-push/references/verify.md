# Verification commands

Read each exit code directly. Replace every `<placeholder>`.

## 1. Private-remote check

Run it in the preconditions, and again right before the push.

```bash
env -u GIT_ASKPASS -u SSH_ASKPASS GIT_TERMINAL_PROMPT=0 git -c core.askPass= -c credential.helper= ls-remote https://github.com/<owner>/<name>.git
echo "ls-remote exit $?"
```

1. `credential.helper=` turns off stored logins for this one command. `env -u GIT_ASKPASS -u SSH_ASKPASS` and `core.askPass=` turn off login helper programs, such as the one a Git app sets. `GIT_TERMINAL_PROMPT=0` stops Git from asking in the terminal. So the command sees only what anyone on the internet sees.
2. A non-zero exit with `terminal prompts disabled` in the error means the repository is private or missing. Go on.
3. Exit 0 means anyone can read the repository, even when it lists no refs. Stop and ask, unless the operator chose a public remote in their own words.
4. Any other error, such as `Could not resolve host`, gives no verdict. Stop and report it.

## 2. Backup before the reset

```bash
mkdir -p "<backup folder>"
tar -czf "<backup folder>/<name>-git-<UTC date and time>.tar.gz" -C "<repo>" .git
echo "tar exit $?"
mkdir -p "<scratch>/backup-check"
tar -xzf "<backup folder>/<name>-git-<UTC date and time>.tar.gz" -C "<scratch>/backup-check"
echo "tar exit $?"
git --git-dir="<scratch>/backup-check/.git" rev-parse 'HEAD^{tree}'
```

1. The backup folder sits outside the repository.
2. Both `tar` lines exit 0.
3. The last line prints the old tree ID from the precondition step. That proves the archive holds a working copy of the history.

## 3. After the reset, before the push

| # | Check | Command | Expected |
| --- | --- | --- | --- |
| 1 | One commit | `git rev-list --count --all` | `1` |
| 2 | Same files as before | `git rev-parse 'HEAD^{tree}'` | the old tree ID from the precondition step |
| 3 | Author and committer | `git log -1 --format='%an <%ae>%n%cn <%ce>%n%ad'` | the intended public identity; the date's time zone as the operator chose |
| 4 | Signed | `git cat-file -p HEAD` | a `gpgsig` header with an SSH signature |
| 5 | Good signature | `git -c gpg.ssh.allowedSignersFile="<allowed signers file>" log --show-signature -1` | `Good "git" signature for <public email>` |
| 6 | Only `main`, no tags | `git show-ref` | one line, `refs/heads/main` |
| 7 | History check | `ctlhq-first-push` | exit 0 |
| 8 | Gate on the new commit | `ctlhq-run-gate -- <check command>` | exit 0 |

The allowed signers file maps the email to the public key, one line, outside the repository:

```bash
printf '%s %s\n' "<public email>" "$(cat "<signing key>")" > "<scratch>/allowed_signers"
```

A different tree ID means the new commit holds other files than the old one. Stop. The usual causes are an untracked file, or a pattern that lived only in `.git/info/exclude`.

## 4. Push and tag

```bash
git remote -v
ssh -T git@github.com
ctlhq-push -u origin main
```

1. Rerun section 1 first. The visibility may have changed since the preconditions.
2. `git remote -v` shows the HTTPS fetch address and the SSH push address.
3. `ssh -T git@github.com` greets the owner by name and exits 1; that exit is normal. A "Permission denied" line means the SSH agent holds no key (see the notes).
4. `ctlhq-push` pushes only when every push address belongs to the GitHub owner in its settings file. It prints `pushed` last.

Only when the project releases by tag. Keep `TZ=UTC` when the operator chose UTC for the commit, so the tag records the same time zone:

```bash
TZ=UTC git tag -s v<version> -m "<project> <version>"
git -c gpg.ssh.allowedSignersFile="<allowed signers file>" tag -v v<version>
ctlhq-push origin v<version>
```

## 5. Restore from the backup

Only on the operator's word, and only to undo a reset that nobody has pushed yet. This is an operator block, like the reset.

```bash
(
  set -eu
  cd "<repo>"
  test "$(pwd -P)" = "<repo>"
  test -s "<backup archive>"
  mkdir -p "<scratch>"
  mkdir "<scratch>/restore-<UTC time>"
  tar -xzf "<backup archive>" -C "<scratch>/restore-<UTC time>"
  test "$(git --git-dir="<scratch>/restore-<UTC time>/.git" rev-parse 'HEAD^{tree}')" = "<old tree>"
  git --git-dir="<scratch>/restore-<UTC time>/.git" --work-tree=. diff --quiet HEAD --
  if test -e .git; then
    test "$(git rev-parse --show-toplevel)" = "<repo>"
    test "$(git rev-list --count --all)" -le 1
    mv .git "<scratch>/fresh-git-<UTC time>"
  fi
  mv "<scratch>/restore-<UTC time>/.git" .git
  test "$(git rev-parse 'HEAD^{tree}')" = "<old tree>"
  git status --short
  echo "restore done"
)
```

1. The subshell with `set -eu` stops at the first failed line, as in the reset block. `<scratch>` is a folder outside the repository, and `<UTC time>` is the time now, such as `20261021T1530Z`.
2. Write `<repo>` as `pwd -P` prints it, because `git rev-parse --show-toplevel` prints that form. The first `test` line checks that `cd` reached that folder.
3. The block first extracts the archive to a new folder in scratch. `mkdir` without `-p` fails when that folder already exists, so an earlier run is never mixed in. The tree check proves the archive holds the old history.
4. `git diff --quiet HEAD` compares the files in `<repo>` with the archive's last commit. It stops the block when `<repo>` is another repository or a subfolder.
5. When `.git` exists, it must belong to `<repo>` itself and hold at most one commit, which is the fresh commit from the reset or none. A `.git` with more commits is the old history or another repository, so the block stops. The block also accepts a missing `.git`, which a reset that failed midway can leave.
6. Only then does the block touch `.git`. It moves the fresh `.git` to `<scratch>/fresh-git-<UTC time>` and keeps it, so this step can be undone too. Then it moves the checked history into place.
7. The last tree check proves the old history is back. The block prints `restore done` last.
