# Stand-ins

Stand-ins replace outside systems in tests: Claude Code, GitHub, and your commit signing
key. None of them makes a network call or touches your ssh-agent. The test is
`tests/stand-ins/run.sh`; `bin/ctlhq-test` runs it.

## Fake Claude Code (`claude/claude`)

What it replaces: the real `claude` command line in print mode, so a test needs no model
call, no login, and no money.

How to use it:

1. Put recordings in a folder. A recording is two files with the same name:
   `<name>.prompt` holds the exact prompt text, and `<name>.stream.jsonl` holds the output of
   a real `claude -p --output-format stream-json --verbose` run.
2. Put `tests/stand-ins/claude` first on `PATH` and set `FAKE_CLAUDE_RECORDINGS` to that folder.
3. Call it the way `tests/stand-ins/run.sh` does: `claude -p "PROMPT" --output-format stream-json --verbose
   --model NAME`. The prompt can also come on stdin.

It prints the recorded stream for `stream-json`, the result event for `json`, and the result
text for `text`. A prompt with no recording exits 1 and names the two files to add. Set
`FAKE_CLAUDE_LOG` to a file to record each call's arguments.

To make a recording, run the real tool once and save both files:

```
printf '%s' "$prompt" > hello.prompt
claude -p "$prompt" --output-format stream-json --verbose > hello.stream.jsonl
```

What it does not cover: interactive mode, any flag other than `-p`, `--output-format`,
`--verbose`, and `--model`, tool use (recorded tool calls are printed, never run), and
model behavior. `--model` is accepted and logged; it does not pick a recording. The test
recordings in `tests/stand-ins/fixtures/claude/` are written by hand in the shape of a real
stream; no real run was captured.

It matches recordings by prompt text. It does not fake Codex, so it has no
`--output-last-message` flag.

## Fake GitHub CLI (`gh/gh`)

What it replaces: the `gh` calls that `bin/ctlhq-watch-pr` makes (from
`skills/ctlhq-mode/scripts/watch-pr/github.ts`):

1. `gh pr view [N] [--repo OWNER/REPO] --json FIELDS`
2. `gh pr list --repo OWNER/REPO --state open --limit 300 --json FIELDS`
3. `gh pr checks N --repo OWNER/REPO --json FIELDS`
4. `gh api graphql` with the queries `ReviewThreads`, `PrCheckRollup`, and `PrCommitStatuses`,
   with an `after` page token for later pages

How to use it:

1. Make a recordings folder with one subfolder per repository: `OWNER/REPO/`.
2. Save what the real `gh` printed, one file per call, named as `gh --help` lists. Examples:
   `pr-view-5.json`, `pr-checks-5.json`, `graphql-ReviewThreads-pr-5.json`.
3. For a non-zero exit code, add `<file>.exit`. For stderr text, add `<file>.stderr`.
4. Put `tests/stand-ins/gh` first on `PATH` and set `FAKE_GH_RECORDINGS` to the folder.

It keeps only the `--json` fields asked for, as the real `gh` does. A call with no recording
exits 1 and names the file to add. Set `FAKE_GH_LOG` to record each call.

The test runs ctlhq-watch-pr's own TypeScript on these recordings through
`tests/stand-ins/watch-pr-replay.mjs`, so the test runs without bun. That driver follows
`main()` in `cli.ts` for single and stack mode, and runs one poll with a fake clock. It
skips the option parsing, the queued-stack mode, and `--pretty`. The test also
runs the fake with proxies unset, `GH_HOST=unroutable.invalid`, and the macOS sandbox
denying network, and it still answers.

What it does not cover: any other `gh` command (they exit 2), `--jq` and `--template`,
authentication, rate limits, and changes on GitHub between polls (each file gives the same
answer every time).

## Throwaway signing key (`signing-key/new-key`, `signing-key/stop`)

What it replaces: your commit signing key and ssh-agent, for scratch repositories
in tests.

How to use it:

1. Run `tests/stand-ins/signing-key/new-key`. Line 1 of its output is a new folder. The folder holds
   an ed25519 key, a private ssh-agent on `agent.sock`, `allowed_signers`, and `env`.
2. In a subshell or a test only, source `<folder>/env`. It sets `SSH_AUTH_SOCK` to the private
   agent.
3. In the scratch repository, set local git configuration: `gpg.format ssh`,
   `user.signingkey "key::$(cat <folder>/key.pub)"`, and
   `gpg.ssh.allowedSignersFile <folder>/allowed_signers`. The `key::` form gives git only the
   public key, so only the private agent can sign.
4. Run `tests/stand-ins/signing-key/stop <folder>`. It kills only that agent and deletes the folder.

`new-key` never adds a key to the agent your own `SSH_AUTH_SOCK` names. `stop` refuses a folder
without the marker that `new-key` writes, and a pid that is not that folder's agent. The test
checks that your ssh-agent's key count is the same before and after.

What it does not cover: GPG keys, hardware keys (a YubiKey stand-in belongs in the projects
that use hardware keys), passphrases, and signing a push or a tag on a real host.
