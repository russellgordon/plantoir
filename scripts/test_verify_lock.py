#!/usr/bin/env python3
"""
`verify.sh` lets ONE run at a time hold this Mac (GitHub #280).

Two runs at once corrupt each other — the same image tag, the same fixed log
files, the same scratch folders in $HOME — and that is how #280 was found. A
second run therefore says who holds the lock and exits 1, rather than
queueing silently; the lock is let go on every exit, Ctrl-C, a kill and a
hang-up included, and only by the run that took it.

**How this runs the real thing.** The functions are cut out of the
repository's `verify.sh` between its VERIFY LOCK markers — not retyped — and
run under `/bin/bash` with `set -euo pipefail`, pointed at a lock in a
scratch folder through `PLANTOIR_VERIFY_LOCK`, so the real lock (and a real
run holding it) is never touched.

**Windows.** Skipped where there is no bash that can run a program;
`verify.sh` is a mac gate and Windows has nothing to mirror.

Pure stdlib. Run with:

    python3 scripts/test_verify_lock.py
"""

import os
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

sys.dont_write_bytecode = True

from test_deploy_sh_questions import HAS_BASH, REPOSITORY_ROOT

BASH = "/bin/bash" if Path("/bin/bash").exists() else "bash"


def the_lock_functions() -> str:
    text = (REPOSITORY_ROOT / "verify.sh").read_text(encoding="utf-8")
    start = text.find("# >>> VERIFY LOCK >>>")
    end = text.find("# <<< VERIFY LOCK <<<")
    if start < 0 or end < 0:
        raise AssertionError("verify.sh has no VERIFY LOCK markers")
    return text[start:end]


def a_run(lock: Path, then: str) -> list:
    """The argv for a bash that takes the lock and then does `then`."""
    program = "set -euo pipefail\n" + the_lock_functions() + "\ntake_verify_lock\n" + then + "\n"
    return [BASH, "-c", program]


def environment(lock: Path) -> dict:
    return {"PATH": "/usr/bin:/bin", "PLANTOIR_VERIFY_LOCK": str(lock), "HOME": str(lock.parent)}


def wait_for(path: Path, seconds: float = 10.0) -> None:
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if path.exists() and path.read_text(encoding="utf-8").strip():
            return
        time.sleep(0.05)
    raise AssertionError(f"{path} never appeared")


def wait_gone(path: Path, seconds: float = 10.0) -> bool:
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if not path.exists():
            return True
        time.sleep(0.05)
    return False


@unittest.skipUnless(HAS_BASH, "no bash here that can run a program")
class OneRunAtATime(unittest.TestCase):

    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.lock = Path(self.scratch.name) / "verify.lock"
        self.holders = []

    def tearDown(self):
        for holder in self.holders:
            if holder.poll() is None:
                holder.kill()
                holder.wait()
        # The holders' `sleep`s outlive them; end exactly those, by pid.
        sleepers = Path(self.scratch.name) / "sleepers"
        if sleepers.exists():
            for line in sleepers.read_text(encoding="utf-8").split():
                try:
                    os.kill(int(line), signal.SIGTERM)
                except (ProcessLookupError, ValueError):
                    pass
        self.scratch.cleanup()

    def hold(self) -> subprocess.Popen:
        holder = subprocess.Popen(a_run(self.lock, 'sleep 30 & echo $! >> "$HOME/sleepers"; wait $!'), env=environment(self.lock),
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.holders.append(holder)
        wait_for(self.lock / "holder")
        return holder

    def second(self) -> subprocess.CompletedProcess:
        return subprocess.run(a_run(self.lock, "echo SECOND RAN"), env=environment(self.lock),
                              capture_output=True, timeout=30)

    def test_a_free_lock_is_taken_and_let_go(self):
        result = subprocess.run(a_run(self.lock, "cat \"$VERIFY_LOCK/holder\""), env=environment(self.lock),
                                capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(os.path.realpath(os.getcwd()).encode(), result.stdout)
        self.assertFalse(self.lock.exists(), "the lock outlived the run that took it")

    def test_a_second_run_names_the_holder_and_exits_1(self):
        holder = self.hold()
        result = self.second()
        said = result.stdout.decode("utf-8")
        self.assertEqual(result.returncode, 1, said)
        self.assertNotIn("SECOND RAN", said)
        self.assertIn(f"pid {holder.pid}", said)
        self.assertIn(str(self.lock), said, "the refusal must name the lock, for a run that was SIGKILLed")
        self.assertTrue(self.lock.exists(), "the second run removed a lock that was not its own")

    def test_a_lock_with_no_holder_written_yet_is_held(self):
        self.lock.mkdir()
        result = self.second()
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertNotIn(b"SECOND RAN", result.stdout)
        self.assertTrue(self.lock.exists())

    def test_a_lock_whose_holder_is_gone_is_taken_over(self):
        finished = subprocess.run(["/bin/sh", "-c", "echo $$"], capture_output=True)
        dead = finished.stdout.decode().strip()
        self.lock.mkdir()
        (self.lock / "holder").write_text(f"{dead} /somewhere (started then)\n", encoding="utf-8")
        result = self.second()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn(b"SECOND RAN", result.stdout)
        self.assertIn(f"pid {dead}".encode(), result.stdout)
        self.assertFalse(self.lock.exists())

    def test_every_catchable_ending_lets_go(self):
        for ending in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            with self.subTest(signal=ending.name):
                holder = self.hold()
                holder.send_signal(ending)
                holder.wait(timeout=30)
                self.assertTrue(wait_gone(self.lock), f"{ending.name} left the lock behind")

    def test_a_run_never_lets_go_of_a_lock_that_is_not_its_own(self):
        """Its own lock was taken over (say it was thought stale) — its exit
        must not remove the new holder's."""
        program = ("take_verify_lock\n"
                   "printf '%s\\n' \"99999999 someone else\" > \"$VERIFY_LOCK/holder\"\n")
        result = subprocess.run(
            [BASH, "-c", "set -euo pipefail\n" + the_lock_functions() + "\n" + program],
            env=environment(self.lock), capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(self.lock.exists(), "a run removed another run's lock on its way out")


class TheLockIsTakenBeforeAnythingShared(unittest.TestCase):

    def test_it_is_taken_before_the_first_log_is_written(self):
        text = (REPOSITORY_ROOT / "verify.sh").read_text(encoding="utf-8")
        taken = text.find("\ntake_verify_lock\n")
        self.assertGreater(taken, 0, "verify.sh never takes the lock")
        self.assertLess(taken, text.find(">/tmp/verify_"), "a shared log is written before the lock is taken")
        self.assertLess(text.find("if [[ ! -t 0 ]]"), taken, "the terminal check should come first")


if __name__ == "__main__":
    unittest.main(verbosity=2)
