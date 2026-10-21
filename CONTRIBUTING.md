# Contributing

ctlhq has one maintainer.
Issues are welcome: a bug, a step that did not work, or text that was hard to follow.
Before you write a pull request, open an issue that describes the change, so the maintainer can say whether it fits.

## Layout

```
bin/                 one command per tool; add this folder to PATH
skills/<name>/       one skill per folder: SKILL.md, references/, playbooks/, scripts/, bin/
agents/              subagent definitions (ctlhq-agent)
home/                AGENTS.md, the optional shared rules file; ctlhq-install --agents-md writes it to ~/.codex/AGENTS.md
docs/                the building principles
envs/                test machine recipes for ctlhq-env: ubuntu, macos-clean, windows, nas, peer
tests/<name>/run.sh  one test script per tool or area
tests/stand-ins/     fakes for tests: Claude Code, GitHub CLI, and a throwaway signing key;
                     each answers --help with its use and what it does not cover
```

## What the checks need

1. macOS, the only platform ctlhq supports. Some tests call macOS-only commands.
2. `node`, version 22.18 or newer. Four tests fail without it, the tests of ctlhq-plan-lint, stand-ins, ctlhq-browser, and ctlhq-icon-sheet.
3. Google Chrome, for the ctlhq-browser and ctlhq-icon-sheet tests.
4. `bun`, only for the TypeScript unit tests and type check of `ctlhq-orch` and `ctlhq-watch-pr`. The gate runs them only when bun is installed, and prints a skipped line otherwise.

There is no CI (continuous integration) yet. Nothing runs these checks for you when you push or open a pull request, so run them yourself first.

## Checks before a change

Run these from the repository root. Each one exits 0 when everything is in order.

1. **The gate.** `bin/ctlhq-test` runs every `tests/*/run.sh`, plus the bun unit tests and type check when bun is installed (a skipped row otherwise). It prints one line per script with its exit code, and a summary line with the total seconds. It exits 0 only when every script exits 0. The scripts start no model session and cost nothing.

   ```bash
   bin/ctlhq-test
   ```

2. **The repository check.** `bin/ctlhq-check` fails on any of these:
   1. a broken relative link in a Markdown file;
   2. a leftover word from the project ctlhq came from, one of its own old names, or a tool name from the editor it was first written for, outside the README's Credits section and `LICENSE`;
   3. a README without the sections `## Install`, `## What it changes on your machine`, and `## Uninstall`, or with one of them empty;
   4. a tool in `bin/` whose `--help` fails or whose first help line is not `<name>: `;
   5. a skill with `bin/` and no `## Tool` section;
   6. a coding principle in the Coding principles section of `skills/ctlhq-mode/SKILL.md` with no `skills/principle-*` folder, or a folder with no entry there. That section is the one list of coding principles; `ctlhq-principles` and `ctlhq-catalog` read it.

   ```bash
   bin/ctlhq-check
   ```

3. **The privacy test.** `tests/privacy/run.sh` scans every tracked file and path for home-folder paths such as `/Users/<name>/`, and for the words in a private word list. The gate runs it with the word list of each folder in `~/.ctlhq/layers.toml` (the file `privacy/private-terms.txt` in that folder). With no layers file, only the path check runs. To use one list directly, give its path:

   ```bash
   PRIVACY_TERMS=/path/to/private-terms.txt bash tests/privacy/run.sh
   ```

   The list holds one word per line: your user name, your project names, anything that must not ship.

To see the result of a skill change the way a user does, run `bin/ctlhq-catalog open`. It builds the catalog into `.local/catalog/`, which Git ignores, and opens it in your browser.

## What a new skill needs

1. A folder `skills/<name>/` with a `SKILL.md`. Its front matter has `name` (equal to the folder name) and `description`. The description says what the skill does and when to use it. `ctlhq-catalog` and `ctlhq-skills show` print it.
2. A `## Tool` section in `SKILL.md` when the skill has a `bin/` folder. Each file in `bin/` is executable and answers `--help` with exit 0 and a first line `<name>: `. Link each one into the top-level `bin/`, for example `ln -s ../skills/<name>/bin/ctlhq-<tool> bin/ctlhq-<tool>`. Every name in the top-level `bin/` starts with `ctlhq-`; `bin/ctlhq-check` fails on any other name.
3. A test in `tests/<name>/run.sh`, or a reason row in `tests/coverage/reasons.tsv`. `bin/ctlhq-coverage` lists what each test covers.
4. Only when the skill must not go to both Claude Code and Codex, a row in `docs/install.tsv` (the skill name, a tab, and the hosts from `claude`, `codex`, `agents`). This repository has no such file; `ctlhq-install --help` describes it.

`bin/ctlhq-check --skill <name>` checks one skill by itself.

## Writing rules

Every text in this repository is written for a reader who is new to the topic.

1. Use short sentences, one idea each, in plain words.
2. Explain a technical term the first time you use it.
3. Use no long dashes.
4. Number every list and every table row that someone may want to cite.
5. Write a code comment only for a reason the code cannot show.

`bin/ctlhq-unslop <file>` finds the mechanical patterns, such as long dashes and filler phrases. The `unslop` and `technical-writing` skills hold the full rules.
