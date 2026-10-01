#!/usr/bin/env python3
"""
A launcher's line on the breadcrumb trail is never lost to the app trimming the
file at the same moment (GitHub #238).

The app keeps `~/Library/Logs/Plantoir/activity.txt` short by rewriting it
without its oldest lines — the one write to that file that REPLACES it rather
than adding to it. A launcher that appended in the instant between the app's
read and its rename wrote into the file being thrown away. So the app trims
only while holding an exclusive lock on the Logs FOLDER, and every launcher's
`note_on_the_trail` takes the same lock round its `>>` with
`/usr/bin/lockf -k` on the folder. The lock and its measurements are in
`documentation/09-mac-app.md` -> "Two writers at once".

This file runs each launcher's REAL function, cut out of the launcher by name,
under `/bin/bash` with a scratch `HOME`, against a stand-in for the app that
takes the lock the way `ProblemReportStore.appendActivityLine` does (`flock` on
the folder). The app's own side is proven by `ProblemReportTests` in the mac
suite.

**Windows.** The Windows app keeps its trail itself and runs no `.sh`
launcher, so the tests that need `/usr/bin/lockf` are skipped wherever there is
none. The text checks run everywhere.

Pure stdlib. Run with:

    python3 scripts/test_trail_lock.py
"""

import os
import subprocess
import sys
import tempfile
import threading
import unittest
from pathlib import Path

sys.dont_write_bytecode = True

from test_deploy_sh_questions import HAS_BASH, REPOSITORY_ROOT
from test_port_blocks import BASH, function_named, launcher_text

LAUNCHERS = ["setup.sh", "preview.sh", "deploy.sh"]
HAS_LOCKF = Path("/usr/bin/lockf").exists()
if HAS_LOCKF:
    import fcntl


def trail_folder(home: Path) -> Path:
    return home / "Library" / "Logs" / "Plantoir"


def run_notes(launcher: str, home: Path, sentences: list) -> subprocess.Popen:
    """Starts bash writing each sentence with the launcher's own function."""
    program = function_named(launcher_text(launcher), "note_on_the_trail")
    program = "set -euo pipefail\n" + program
    for sentence in sentences:
        program += "note_on_the_trail '" + sentence + "'\n"
    return subprocess.Popen(
        [BASH, "-c", program],
        env={"HOME": str(home), "PATH": os.environ.get("PATH", "")},
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    )


class TheThreeLaunchersCarryOneAppend(unittest.TestCase):

    def test_the_function_is_the_same_in_all_three(self):
        first = function_named(launcher_text("setup.sh"), "note_on_the_trail")
        for launcher in ["preview.sh", "deploy.sh"]:
            self.assertEqual(first, function_named(launcher_text(launcher), "note_on_the_trail"),
                             f"{launcher}'s note_on_the_trail has drifted from setup.sh's")

    def test_the_append_is_made_holding_the_folder_lock(self):
        body = function_named(launcher_text("setup.sh"), "note_on_the_trail")
        self.assertIn('/usr/bin/lockf -k "$trail" /bin/sh -c', body)
        # -k: without it lockf removes its lock file afterwards, and the lock
        # file here is the Logs folder itself.
        self.assertNotRegex(body, r"lockf -[a-z]*t")


@unittest.skipUnless(HAS_BASH, "needs a bash that can reach a scratch folder")
class ALineIsWritten(unittest.TestCase):

    def test_each_launcher_adds_its_line(self):
        for launcher in LAUNCHERS:
            with tempfile.TemporaryDirectory() as scratch:
                home = Path(scratch)
                process = run_notes(launcher, home, ["started ICS3U", "finished ICS3U"])
                self.assertEqual(process.wait(timeout=30), 0, process.stderr.read())
                lines = (trail_folder(home) / "activity.txt").read_text(encoding="utf-8").splitlines()
                self.assertEqual(len(lines), 2, launcher)
                self.assertTrue(lines[0].endswith(" · started ICS3U"), lines[0])
                self.assertTrue(lines[1].endswith(" · finished ICS3U"), lines[1])
                # The lock is the folder: nothing else appears in it.
                self.assertEqual(sorted(os.listdir(trail_folder(home))), ["activity.txt"])


@unittest.skipUnless(HAS_BASH and HAS_LOCKF, "needs bash and /usr/bin/lockf (a Mac)")
class TheAppendWaitsForTheTrim(unittest.TestCase):

    def test_a_line_waits_while_the_app_holds_the_lock_and_survives_the_trim(self):
        """The app is mid-trim: it holds the lock, and the file it read is
        about to be replaced. A launcher appending now must wait, and land in
        the NEW file."""
        with tempfile.TemporaryDirectory() as scratch:
            home = Path(scratch)
            folder = trail_folder(home)
            folder.mkdir(parents=True)
            trail = folder / "activity.txt"
            trail.write_text("old line 1\nold line 2\n", encoding="utf-8")
            lock = os.open(folder, os.O_RDONLY)
            fcntl.flock(lock, fcntl.LOCK_EX)
            process = run_notes("setup.sh", home, ["started ICS3U"])
            try:
                # Deliberately paced: time enough for an append that did NOT
                # wait to have landed in the file about to be replaced.
                with self.assertRaises(subprocess.TimeoutExpired):
                    process.wait(timeout=1.0)
                self.assertNotIn("started ICS3U", trail.read_text(encoding="utf-8"),
                                 "the launcher wrote while the app held the lock")
                shorter = folder / ".activity.trimmed"
                shorter.write_text("old line 2\n", encoding="utf-8")
                os.replace(shorter, trail)
            finally:
                fcntl.flock(lock, fcntl.LOCK_UN)
                os.close(lock)
            self.assertEqual(process.wait(timeout=30), 0)
            lines = trail.read_text(encoding="utf-8").splitlines()
            self.assertEqual(lines[0], "old line 2")
            self.assertTrue(lines[1].endswith(" · started ICS3U"), lines)

    def test_a_launcher_racing_a_trimming_app_keeps_every_line(self):
        """A stand-in for the app appends and trims under the folder lock as
        fast as it can — with limits small enough that it trims every few
        lines — while each launcher writes 100 lines. The stand-in keeps every
        line it trims away, so a launcher line is either still in the file or
        was trimmed: one in neither place was lost. Measured with the launcher
        from before #238, which appended without the lock: lines lost in every
        run."""
        most, kept = 40, 20
        count = 100
        for launcher in LAUNCHERS:
            with tempfile.TemporaryDirectory() as scratch:
                home = Path(scratch)
                folder = trail_folder(home)
                folder.mkdir(parents=True)
                trail = folder / "activity.txt"
                trail.write_text("", encoding="utf-8")
                process = run_notes(launcher, home, [f"launcher line {n}" for n in range(count)])
                trimmed_away = []
                trims = 0
                while process.poll() is None:
                    lock = os.open(folder, os.O_RDONLY)
                    fcntl.flock(lock, fcntl.LOCK_EX)
                    try:
                        with open(trail, "a", encoding="utf-8") as appending:
                            appending.write("app line\n")
                        lines = trail.read_text(encoding="utf-8").split("\n")
                        if len(lines) > most:
                            trimmed_away.extend(lines[:len(lines) - kept])
                            shorter = folder / ".activity.trimmed"
                            shorter.write_text("\n".join(lines[len(lines) - kept:]), encoding="utf-8")
                            os.replace(shorter, trail)
                            trims += 1
                    finally:
                        fcntl.flock(lock, fcntl.LOCK_UN)
                        os.close(lock)
                self.assertEqual(process.returncode, 0, launcher)
                self.assertGreater(trims, 20, "too few trims to prove anything")
                seen = set()
                for line in trimmed_away + trail.read_text(encoding="utf-8").split("\n"):
                    marker = line.find("launcher line ")
                    if marker >= 0:
                        seen.add(int(line[marker + len("launcher line "):]))
                lost = []
                for number in range(count):
                    if number not in seen:
                        lost.append(number)
                self.assertEqual(lost, [], f"{launcher}: {len(lost)} of {count} lines lost to a trim")


if __name__ == "__main__":
    unittest.main()
