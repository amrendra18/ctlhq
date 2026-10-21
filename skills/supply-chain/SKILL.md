---
name: supply-chain
description: "Check a dependency or an installer before you trust it. Official sources only, no version younger than 21 days, pinned and checksummed, and a recorded exception for anything else. Use before you add or upgrade a dependency, or before you run a downloaded installer."
disable-model-invocation: true
---

# Supply chain

A new release can carry a hijacked account's code for days before anyone notices. Waiting 21 days and using only the official registry removes most of that risk. The wait does not apply to the operator's own repositories, because the operator wrote that code. The operator names them in their rules file (`~/.codex/AGENTS.md` or `~/.claude/CLAUDE.md`), for example "My own repositories are every folder under ~/projects and github.com/<my-account>/*." Only repositories named there are exempt. With no such line, every dependency waits 21 days. The check is a command; the policy and the exceptions are your judgment.

## Tool

`bin/ctlhq-dep-age` (a symlink to `skills/supply-chain/bin/ctlhq-dep-age`) does the checks. `ctlhq-dep-age --help` lists every option and exit code.

```
bin/ctlhq-dep-age [LOCKFILE ...]                    # every locked package: release date, age, source, verdict
bin/ctlhq-dep-age --pkg npm:left-pad@1.3.0          # one package before you add it (npm, pypi, go, crates)
bin/ctlhq-dep-age --exceptions deps-exceptions.txt  # flags named in the exceptions file pass
bin/ctlhq-dep-age --file ~/Downloads/install.sh     # SHA-256 of a download, and any checksum or signature next to it
```

It reads package-lock.json, pnpm-lock.yaml, go.sum, go.mod, uv.lock, requirements.txt, and Cargo.lock. Exit 0 nothing flagged, 1 a flag without an exception, 2 usage, 3 network unavailable. Exit 3 is no verdict. Never treat it as clean.

## Policy

| # | rule | what counts |
|---|---|---|
| 1 | official sources only | registry.npmjs.org, pypi.org, proxy.golang.org, crates.io, and the vendor's own release page for an installer. A mirror, a git URL, a tarball URL, a private index, or a `replace` is unofficial |
| 2 | 21-day minimum | the version's release date is 21 or more days before today; the operator's own repositories, local or on GitHub, are exempt, but only those the operator names in their rules file |
| 3 | pin and checksum | exact versions in a lockfile that holds integrity hashes; `==` in requirements.txt, with `--hash` lines when the project uses them |
| 4 | check an installer | read the script, compare its checksum with the vendor's published one, and verify a signature when one exists, before you run it |

## Steps

1. Before you add or upgrade a dependency, run `bin/ctlhq-dep-age --pkg <eco>:<name>@<version>` on the exact version you plan to use. Pick the newest version that is at least 21 days old when the newest one is flagged young.
2. After the lockfile changes, run `bin/ctlhq-dep-age <lockfile>`. Transitive packages count too. Read every flagged row. A young transitive package usually means an older parent version avoids it.
3. When the result is exit 3, say "dependency age not checked: network unavailable". Do not add the dependency on a guess. Retry when the network is back, or ask the operator.
4. Before you run a downloaded installer or a `curl ... | sh` script, save it to a file first. Run `bin/ctlhq-dep-age --file <download>`. Get the checksum or signature from the vendor's official page when none sits next to the file. Read the script. Run it only when the checksum matches.
5. An exception is the operator's decision, never yours. Ask with one question: the package, version, verdict, why it is needed now, and the safer alternative (an older version, or waiting until a named date). Ask in chat, also when the operator is away.
6. Record an approved exception as one line in the project's exceptions file (default `deps-exceptions.txt` at the repository root): `name<TAB>version<TAB>approved by <who> on <date>: <reason>; remove after <date>`. Use `*` as the version only when the operator approved every version. Pass the file with `--exceptions`.
7. Remove an exception when its version ages past 21 days or the package leaves the lockfile. Run `bin/ctlhq-dep-age --exceptions <file>` without the line first; exit 0 proves it is no longer needed.
8. Reply contract: the command, the exit code, the count of packages and flags, every flagged row, and each exception used with its approval line. Write "dependency age checked, 0 flags", never "safe".
