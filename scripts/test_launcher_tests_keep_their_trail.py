#!/usr/bin/env python3
"""
A launcher run by the tests never writes the teacher's real trail (#738).

The launchers write their lines into `~/Library/Logs/Plantoir/activity.txt`
unless PLANTOIR_TRAIL_DIR names another folder (#664). On 2026-11-01
reproducing a flake in the deploy tests wrote an estimated 30 to 60 lines into
the real log, because those tests ran deploy.sh without the redirect. So every
test file that runs a launcher imports `launcher_test_trail`, which points
PLANTOIR_TRAIL_DIR at a temporary folder for the whole run.

This file holds that rule, and proves the redirect with the launchers' own
`note_on_the_trail`, cut out of deploy.sh by name and run under bash with a
scratch HOME standing for the teacher's: the line lands in the helper's
folder and the scratch HOME gets no trail. The must-fail runs the same
function with the variable taken away, and the line lands in that HOME.

Measured when this was written (2026-11-13, `dev` fcd0a51c5): all 119
`scripts/test_*.py` run on a Mac with HOME pointed at a scratch folder and
PLANTOIR_TRAIL_DIR unset wrote 0 lines into that HOME's trail, so nothing was
leaking that day; this keeps a new test from starting to.

**Windows.** It runs no `.sh` launcher, so the run of the real function is
skipped wherever there is no bash; the rule is read everywhere.

Pure stdlib. Run with:

    python3 scripts/test_launcher_tests_keep_their_trail.py
"""

import ast
import os
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True

import launcher_test_trail  # noqa: E402
from test_deploy_sh_questions import HAS_BASH  # noqa: E402
from test_port_blocks import BASH, function_named, launcher_text  # noqa: E402

SCRIPTS = Path(__file__).resolve().parent
LAUNCHER = re.compile(r"\b(setup|preview|deploy)\.sh\b")
CALL = re.compile(r"subprocess\.(run|Popen|check_output|check_call|call)\b|\bPopen\(")


def runs_a_launcher(text: str) -> bool:
    """A test file that names a launcher and starts a process."""
    return bool(LAUNCHER.search(text) and CALL.search(text))


def imports_the_helper(text: str) -> bool:
    for node in ast.walk(ast.parse(text)):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "launcher_test_trail":
                    return True
    return False


def note(home: Path, sentence: str, keep_redirect: bool) -> subprocess.CompletedProcess:
    """deploy.sh's own note_on_the_trail, in an environment built from this
    process's the way the launcher tests build theirs, HOME replaced."""
    program = "set -euo pipefail\n" + function_named(launcher_text("deploy.sh"), "note_on_the_trail")
    program += "note_on_the_trail '" + sentence + "'\n"
    environment = dict(os.environ, HOME=str(home))
    if not keep_redirect:
        environment.pop("PLANTOIR_TRAIL_DIR", None)
    return subprocess.run([BASH, "-c", program], cwd=str(home), env=environment,
                          capture_output=True, text=True, timeout=60)


class LauncherTestsKeepTheirTrailTests(unittest.TestCase):

    def test_every_test_that_runs_a_launcher_imports_the_helper(self):
        found = []
        missing = []
        for path in sorted(SCRIPTS.glob("test_*.py")):
            text = path.read_text(encoding="utf-8")
            if not runs_a_launcher(text) or path.name == Path(__file__).name:
                continue
            found.append(path.name)
            if not imports_the_helper(text):
                missing.append(path.name)
        self.assertGreaterEqual(len(found), 20, "the rule no longer finds the launcher tests")
        self.assertEqual(missing, [], "these run a launcher without `import launcher_test_trail`")

    def test_the_helper_names_a_temporary_folder_and_this_process_carries_it(self):
        self.assertEqual(os.environ.get("PLANTOIR_TRAIL_DIR"), launcher_test_trail.FOLDER)
        self.assertTrue(Path(launcher_test_trail.FOLDER).is_dir())
        self.assertTrue(Path(launcher_test_trail.FOLDER).is_absolute())
        self.assertTrue(Path(launcher_test_trail.FOLDER).resolve().is_relative_to(Path(tempfile.gettempdir()).resolve()))

    @unittest.skipUnless(HAS_BASH, "no bash here to run the launcher's function")
    def test_a_launchers_line_lands_in_the_helpers_folder_and_not_in_home(self):
        with tempfile.TemporaryDirectory() as scratch:
            home = Path(scratch)
            answer = note(home, "a line from the tests (#738)", keep_redirect=True)
            self.assertEqual(answer.returncode, 0, answer.stderr)
            self.assertFalse((home / "Library" / "Logs" / "Plantoir" / "activity.txt").exists(),
                             "the launcher wrote into HOME's trail")
            written = (Path(launcher_test_trail.FOLDER) / "activity.txt").read_text(encoding="utf-8")
            self.assertIn("a line from the tests (#738)", written)

    @unittest.skipUnless(HAS_BASH, "no bash here to run the launcher's function")
    def test_must_fail_without_the_redirect_the_line_lands_in_home(self):
        with tempfile.TemporaryDirectory() as scratch:
            home = Path(scratch)
            answer = note(home, "a line with no redirect (#738)", keep_redirect=False)
            self.assertEqual(answer.returncode, 0, answer.stderr)
            trail = home / "Library" / "Logs" / "Plantoir" / "activity.txt"
            self.assertTrue(trail.exists(), "this test can no longer see where an unredirected line goes")
            self.assertIn("a line with no redirect (#738)", trail.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
