import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


SOURCE = Path(__file__).resolve().parents[2] / "bin" / "ctlhq-doctor"


class FormalToolsDoctorTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="ctlhq-doctor-formal-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.environment = {**os.environ, "HOME": str(self.root)}
        (self.root / "bin").mkdir()
        skill = self.root / "skills" / "ctlhq-mode"
        skill.mkdir(parents=True)
        (skill / "SKILL.md").touch()
        self.doctor = self.root / "bin" / "ctlhq-doctor"
        shutil.copyfile(SOURCE, self.doctor)
        self.calls = self.root / "calls.json"

    def helper(self, java, tlc, code):
        output = (
            f"Java 25.0.4.1+1, released 2026-08-19 | {java} | managed-java\n"
            f"TLC distribution 1.7.4, released 2024-08-05 | {tlc} | managed-jar"
        )
        helper = self.root / "bin" / "ctlhq-formal-tools"
        helper.write_text(
            f"#!{sys.executable}\n"
            "import json, sys\nfrom pathlib import Path\n"
            f"Path({str(self.calls)!r}).write_text(json.dumps(sys.argv[1:]))\n"
            f"print({output!r})\nsys.exit({code})\n"
        )
        helper.chmod(0o755)

    def run_doctor(self, as_json=True):
        result = subprocess.run(
            [sys.executable, str(self.doctor), "--no-tools", "--models",
             str(self.root / "absent-models.toml"), *(["--json"] if as_json else [])],
            capture_output=True, text=True, cwd=self.root, env=self.environment,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        if not as_json:
            return result.stdout
        rows = [row for row in json.loads(result.stdout)["checks"]
                if row["name"] == "Java and TLC"]
        self.assertEqual(len(rows), 1, "doctor must report one optional Java and TLC row")
        self.assertFalse(rows[0]["required"])
        return rows[0]

    def test_ready_tools_are_optional_and_checked_without_installing(self):
        self.helper("ready", "ready", 0)
        row = self.run_doctor()
        self.assertEqual(row["status"], "ok")
        self.assertIsNone(row["install"])
        self.assertEqual(
            row["needed_by"],
            "create-formal-verification-skill, maintain-formal-verification-skill",
        )
        self.assertIn("25.0.4.1+1", row["detail"])
        self.assertIn("1.7.4", row["detail"])
        self.assertEqual(json.loads(self.calls.read_text()), ["check"])

    def test_missing_tools_show_the_operator_install_command(self):
        self.helper("missing", "missing", 1)
        row = self.run_doctor()
        self.assertEqual(row["status"], "missing")
        self.assertEqual(row["install"], "ctlhq-formal-tools install")
        text = self.run_doctor(as_json=False)
        self.assertIn("missing  Java and TLC", text)
        self.assertIn("ctlhq-formal-tools install", text)
        self.assertEqual(json.loads(self.calls.read_text()), ["check"])

    def test_partly_missing_tools_remain_optional(self):
        self.helper("ready", "missing", 1)
        row = self.run_doctor()
        self.assertEqual(row["status"], "missing")
        self.assertIn("ready", row["detail"])
        self.assertIn("missing", row["detail"])

    def test_existing_empty_bundle_shows_inspection_and_manual_recovery(self):
        bundle = self.root / ".ctlhq/tools/formal"
        bundle.mkdir(parents=True)
        checker = self.root / "bin" / "ctlhq-formal-tools"
        checker.write_text(
            f"#!{sys.executable}\n"
            "import runpy, sys\nfrom unittest.mock import Mock, patch\n"
            f"tool = runpy.run_path({str(SOURCE.with_name('ctlhq-formal-tools'))!r})\n"
            "tool['main'].__globals__['download'] = Mock(side_effect=AssertionError('unexpected download'))\n"
            "with patch('platform.system', return_value='Darwin'), patch('platform.machine', return_value='arm64'):\n"
            "    sys.exit(tool['main'](sys.argv[1:]))\n"
        )
        checker.chmod(0o755)
        result = subprocess.run(
            [sys.executable, str(checker), "install"],
            capture_output=True, text=True, env=self.environment,
        )
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("refuse to overwrite", result.stderr)
        self.assertTrue(bundle.is_dir())
        self.assertEqual(list(bundle.iterdir()), [])
        row = self.run_doctor()
        self.assertEqual(row["status"], "missing")
        self.assertEqual(row["install"], "ctlhq-formal-tools check")
        recovery = "remove or move ~/.ctlhq/tools/formal/ yourself before installing again"
        self.assertIn(recovery, row["detail"])
        text = self.run_doctor(as_json=False)
        self.assertIn("ctlhq-formal-tools check", text)
        self.assertIn(recovery, text)

    def test_invalid_tools_are_distinct_from_missing_tools(self):
        self.helper("missing", "invalid SHA-256 checksum", 1)
        row = self.run_doctor()
        self.assertEqual(row["status"], "invalid")
        self.assertIn("invalid SHA-256 checksum", row["detail"])
        self.assertEqual(row["install"], "ctlhq-formal-tools check")

    def test_an_absent_checker_is_optional_and_does_not_claim_missing_java(self):
        row = self.run_doctor()
        self.assertEqual(row["status"], "invalid")
        self.assertIn("ctlhq-formal-tools", row["detail"])
        self.assertIsNone(row["install"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
