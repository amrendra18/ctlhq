#!/usr/bin/env python3
"""check_contract.py: free contract checks over every SKILL.md, playbook, and agent file.

Usage: check_contract.py [--root DIR]

Checks, each reported as `file:line: message`:
  1. every `bin/<tool>`, `skills/<s>/bin/<tool>`, or `ctlhq-*` command named exists and
     answers `--help` with exit 0 (ctlhq-* names that are skills or agents are skipped);
  2. every subcommand and `--flag` written after a tool name (inline code or a fenced code
     line) appears in that tool's top-level `--help`;
  3. every `playbooks/<file>.md` named exists;
  4. every `references/<path>` named exists;
  5. every skill named as `/<name>` or as "the `<name>` skill" exists, or is a declared
     external skill (skills/ctlhq-help/SKILL.md, "not bundled" list).

Placeholders such as `<title>` and globs are skipped. `--help` runs with HOME set to an
empty temp folder and stdin closed. Prints "N checks passed" and exits 0, or prints every
problem and "M problems, N checks passed" and exits 1. Exit 2 on a usage error.
"""
import os
import re
import subprocess
import sys
import tempfile

# Names the skill texts call external (not bundled in ctlhq): skills/ctlhq-help/SKILL.md
# "Not in ctlhq" list, including /plugin, the Claude Code command that installs skill-creator.
EXTERNAL_SKILLS = {"loop", "goal", "skill-creator", "orchestrate", "plugin"}
# Hyphenated words that read as "the X skill" but name no skill.
NOT_SKILL_WORDS = {"project-local"}

PATHCH = r"A-Za-z0-9_./~$@-"


def scan_files(root):
    out = []
    sk = os.path.join(root, "skills")
    if os.path.isdir(sk):
        for name in sorted(os.listdir(sk)):
            f = os.path.join(sk, name, "SKILL.md")
            if os.path.isfile(f):
                out.append(f)
            pb = os.path.join(sk, name, "playbooks")
            if os.path.isdir(pb):
                for p in sorted(os.listdir(pb)):
                    if p.endswith(".md"):
                        out.append(os.path.join(pb, p))
    ag = os.path.join(root, "agents")
    if os.path.isdir(ag):
        for p in sorted(os.listdir(ag)):
            if p.endswith(".md"):
                out.append(os.path.join(ag, p))
    return out


def skill_dir_of(root, path):
    rel = os.path.relpath(path, root).split(os.sep)
    if len(rel) >= 3 and rel[0] == "skills":
        return os.path.join(root, "skills", rel[1])
    return None


class Checker:
    def __init__(self, root):
        self.root = root
        self.bindir = os.path.join(root, "bin")
        self.tools = set(os.listdir(self.bindir)) if os.path.isdir(self.bindir) else set()
        sk = os.path.join(root, "skills")
        self.skills = set(n for n in os.listdir(sk)
                          if os.path.isfile(os.path.join(sk, n, "SKILL.md"))) if os.path.isdir(sk) else set()
        ag = os.path.join(root, "agents")
        self.agents = set(p[:-3] for p in os.listdir(ag) if p.endswith(".md")) if os.path.isdir(ag) else set()
        self.help = {}
        self.home = tempfile.mkdtemp(prefix="skill-contract-home.")
        self.problems = []
        self.passed = 0

    def rel(self, path):
        return os.path.relpath(path, self.root)

    def problem(self, path, n, msg):
        self.problems.append("%s:%d: %s" % (self.rel(path), n, msg))

    def ok(self):
        self.passed += 1

    def help_of(self, exe):
        """Return (exit code, text) of `exe --help`, cached."""
        if exe not in self.help:
            env = dict(os.environ, HOME=self.home)
            try:
                p = subprocess.run([exe, "--help"], stdin=subprocess.DEVNULL,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   env=env, timeout=30, cwd=self.home)
                self.help[exe] = (p.returncode, p.stdout.decode("utf-8", "replace"))
            except (OSError, subprocess.TimeoutExpired) as e:
                self.help[exe] = (-1, str(e))
        return self.help[exe]

    def check_command(self, path, n, label, exe):
        if not os.path.exists(exe):
            self.problem(path, n, "command `%s` not found (%s)" % (label, self.rel(exe)))
            return
        if not os.access(exe, os.X_OK):
            self.problem(path, n, "command `%s` is not executable" % label)
            return
        rc, _ = self.help_of(exe)
        if rc != 0:
            self.problem(path, n, "command `%s --help` exits %d" % (label, rc))
            return
        self.ok()

    # 1. Commands named.
    def commands(self, path, n, line):
        seen = set()
        for m in re.finditer(r"(?<![%s])(skills/([a-z0-9-]+)/)?bin/([A-Za-z0-9_][A-Za-z0-9_.-]*[A-Za-z0-9_])" % PATHCH, line):
            label = m.group(0)
            if label in seen:
                continue
            seen.add(label)
            self.check_command(path, n, label, os.path.join(self.root, label))
        for m in re.finditer(r"(?<![%s])(ctlhq-[a-z0-9]+(?:-[a-z0-9]+)*)(?![A-Za-z0-9_/-])" % PATHCH, line):
            name = m.group(1)
            if name in self.skills or name in self.agents or name in seen:
                continue
            seen.add(name)
            self.check_command(path, n, name, os.path.join(self.bindir, name))

    # 2. Subcommands and flags written after a tool name.
    def invocation(self, path, n, text):
        text = re.sub(r"^\s*\$\s+", "", text)
        text = re.split(r"\s(?:\||;|&&|\|\||#)\s|\s#", text)[0]
        toks = text.split()
        if not toks:
            return
        first = toks[0]
        m = re.match(r"^(?:\./)?(?:skills/[a-z0-9-]+/)?(?:bin/)?([A-Za-z0-9_.-]+)$", first)
        if not m or m.group(1) not in self.tools:
            return
        tool = m.group(1)
        exe = os.path.join(self.bindir, tool)
        rc, help_text = self.help_of(exe)
        if rc != 0:
            return  # reported by check 1 when named with bin/; nothing to compare against
        words = set(re.findall(r"[A-Za-z0-9][A-Za-z0-9_-]*", help_text))
        flags = set(re.findall(r"--[A-Za-z0-9][A-Za-z0-9-]*", help_text))
        if len(toks) > 1 and re.match(r"^[a-z][a-z0-9-]*$", toks[1]):
            if toks[1] in words:
                self.ok()
            else:
                self.problem(path, n, "`%s %s`: subcommand `%s` is not in `%s --help`" % (tool, toks[1], toks[1], tool))
        for t in toks[1:]:
            fm = re.match(r"^(--[A-Za-z0-9][A-Za-z0-9-]*)", t)
            if not fm:
                continue
            flag = fm.group(1)
            if flag in flags or flag == "--help":
                self.ok()
            else:
                self.problem(path, n, "`%s %s`: flag not in `%s --help`" % (tool, flag, tool))

    # 3 and 4. Playbook and references paths.
    def resolve(self, path, ref):
        if ref.startswith("skills/"):
            return [os.path.join(self.root, ref)]
        if ref.startswith("../"):
            return [os.path.normpath(os.path.join(os.path.dirname(path), ref))]
        cands = []
        sd = skill_dir_of(self.root, path)
        if sd:
            cands.append(os.path.join(sd, ref))
        cands.append(os.path.join(os.path.dirname(path), ref))
        if ref.startswith("playbooks/"):
            cands.append(os.path.join(self.root, "skills", "ctlhq-mode", ref))
        cands.append(os.path.join(self.root, ref))
        return cands

    def paths(self, path, n, line):
        pat = r"(?<![A-Za-z0-9_.~$@-])((?:skills/[a-z0-9-]+/|(?:\.\./)+(?:[a-z0-9-]+/)?)?(playbooks|references)/[A-Za-z0-9_./-]*)"
        for m in re.finditer(pat, line):
            ref = m.group(1)
            nxt = line[m.end():m.end() + 1]
            if nxt in ("<", "*", "{") or "<" in ref:
                continue
            ref = ref.rstrip(".")
            kind = m.group(2)
            tail = ref.split(kind + "/", 1)[1]
            if kind == "playbooks" and not tail.endswith(".md"):
                continue
            if kind == "references" and tail == "":
                pass  # the folder itself
            if any(os.path.exists(c) for c in self.resolve(path, ref)):
                self.ok()
            else:
                self.problem(path, n, "%s path `%s` does not exist" % ("playbook" if kind == "playbooks" else "references", ref))

    # 5. Skills named.
    def skill_name(self, path, n, name, how):
        if name in self.skills or name in EXTERNAL_SKILLS:
            self.ok()
        else:
            self.problem(path, n, "skill `%s` (named as %s) does not exist" % (name, how))

    def skill_names(self, path, n, line):
        for m in re.finditer(r"(?:^|(?<=[\s`(\"\[]))/([a-z][a-z0-9-]*[a-z0-9])(?![A-Za-z0-9/._-])", line):
            self.skill_name(path, n, m.group(1), "/" + m.group(1))
        for m in re.finditer(r"\bthe (`|\*\*)?([a-z0-9][a-z0-9-]*)(`|\*\*)? skill\b", line, re.I):
            name = m.group(2).lower()
            marked = bool(m.group(1)) and m.group(1) == m.group(3)
            if not marked and "-" not in name:
                continue
            if name in NOT_SKILL_WORDS:
                continue
            self.skill_name(path, n, name, "the %s skill" % name)

    def run(self):
        for path in scan_files(self.root):
            with open(path, encoding="utf-8") as fh:
                lines = fh.read().split("\n")
            fenced = False
            for i, line in enumerate(lines, 1):
                if line.lstrip().startswith("```"):
                    fenced = not fenced
                    continue
                self.commands(path, i, line)
                self.paths(path, i, line)
                if fenced:
                    self.invocation(path, i, line)
                    continue
                for span in re.findall(r"`([^`]+)`", line):
                    self.invocation(path, i, span)
                self.skill_names(path, i, line)
        return self


def main(argv):
    root = os.getcwd()
    args = list(argv)
    while args:
        a = args.pop(0)
        if a in ("-h", "--help"):
            print(__doc__.strip())
            return 0
        if a == "--root" and args:
            root = args.pop(0)
        else:
            sys.stderr.write("check_contract.py: unknown argument %s\n" % a)
            return 2
    if not os.path.isdir(root):
        sys.stderr.write("check_contract.py: no such folder %s\n" % root)
        return 2
    c = Checker(os.path.abspath(root)).run()
    for p in c.problems:
        print(p)
    if c.problems:
        print("%d problems, %d checks passed" % (len(c.problems), c.passed))
        return 1
    print("%d checks passed" % c.passed)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
