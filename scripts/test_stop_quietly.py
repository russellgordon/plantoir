#!/usr/bin/env python3
"""
Stopping a build leaves quietly (GitHub #223).

Pressing Stop on a preview types ^C into the console, which reaches
build_site.py as a KeyboardInterrupt. It used to escape main() and print a
Python traceback — measured in a real problem report of 2026-09-19 as 21
lines and 1,230 characters of container paths and subprocess internals, the
last thing in the console and the first thing anyone reading the report saw.
main() now catches it and exits 130 with nothing printed.

130, not 0, is the half that matters for safety: deploy.py runs this build
with check=True, so a Stop during a publish's rebuild must still read as a
build that did not finish, or a half-built site would be uploaded.

Pure stdlib, no Docker and no network. Run with:

    python3 scripts/test_stop_quietly.py

The second case sends a real SIGINT and is skipped on Windows, which cannot
deliver one to a child with send_signal; the first case runs everywhere.
"""
import os
import signal
import subprocess
import sys
import time
import unittest
from pathlib import Path

# Importing build_site by hand would otherwise leave scripts/__pycache__
# behind, which verify.sh fails on (it ships inside the app).
sys.dont_write_bytecode = True

import build_site

SCRIPTS_FOLDER = Path(__file__).resolve().parent

# Run as a separate program: the REAL build_site.main(), with the build
# replaced by a long subprocess.run — the same shape as the preview server's
# run inside build_section_site. It says when it has started, so the test
# sends the interrupt at a known point rather than after a guessed delay.
STAND_IN_BUILD = r"""
import signal, subprocess, sys
signal.signal(signal.SIGINT, signal.default_int_handler)
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import build_site
def build_that_runs_until_stopped(**arguments):
    print("started", flush=True)
    subprocess.run(["sleep", "30"], check=True)
build_site.build_section_site = build_that_runs_until_stopped
sys.argv = ["build_site.py", "--course", "ICS3U", "--section", "1"]
build_site.main()
"""


class StopLeavesQuietlyTests(unittest.TestCase):

    # MARK: - Set up and tear down

    def setUp(self):
        self.original_arguments = sys.argv
        self.original_build = build_site.build_section_site

    def tearDown(self):
        sys.argv = self.original_arguments
        build_site.build_section_site = self.original_build

    # MARK: - Tests

    def test_an_interrupted_build_exits_130_rather_than_raising(self):
        def build_that_is_interrupted(**arguments):
            raise KeyboardInterrupt

        build_site.build_section_site = build_that_is_interrupted
        sys.argv = ["build_site.py", "--course", "ICS3U", "--section", "1"]
        # KeyboardInterrupt is not an Exception, so unittest would not catch
        # an escaped one: it would end the whole run instead of failing this
        # test. Catch it here and say so.
        exit_code = None
        escaped = False
        try:
            build_site.main()
        except SystemExit as leaving:
            exit_code = leaving.code
        except KeyboardInterrupt:
            escaped = True
        self.assertFalse(escaped, "The interrupt escaped main(), which prints a traceback")
        self.assertEqual(
            exit_code, 130,
            "A stopped build must exit 130 — not 0, which deploy.py would read as a finished build",
        )

    @unittest.skipIf(os.name == "nt", "Windows cannot send SIGINT to a child process")
    def test_a_real_interrupt_prints_no_traceback(self):
        environment = dict(os.environ)
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        process = subprocess.Popen(
            [sys.executable, "-c", STAND_IN_BUILD, str(SCRIPTS_FOLDER)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=environment,
        )
        first_line = process.stdout.readline()
        self.assertEqual(first_line.strip(), "started")
        # "started" is printed just BEFORE subprocess.run, so wait until its
        # child really exists. An interrupt that lands while Popen is still
        # creating the child is a different moment (the child can be left
        # holding this test's pipes open), and not the one a teacher meets:
        # they press Stop long after the build is running.
        running_child = self.wait_for_a_child_of(process.pid)
        process.send_signal(signal.SIGINT)
        remaining_output, error_output = process.communicate(timeout=20)
        self.assertEqual(process.returncode, 130, "stderr was:\n" + error_output)
        self.assertNotIn("Traceback", error_output)
        self.assertEqual(error_output, "", "Stopping should print nothing at all")
        # And what the build was running went with it — no orphan left behind.
        self.assertFalse(
            self.is_running(running_child),
            "The program the build was running is still running after Stop",
        )

    # MARK: - Helpers

    def wait_for_a_child_of(self, parent_pid):
        for attempt in range(400):
            found = subprocess.run(
                ["pgrep", "-P", str(parent_pid)],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
            )
            child_ids = found.stdout.split()
            if child_ids:
                return int(child_ids[0])
            # Polling for a condition, with a ceiling of twenty seconds.
            time.sleep(0.05)
        self.fail("The stand-in build never started its child")

    def is_running(self, process_id):
        try:
            os.kill(process_id, 0)
        except ProcessLookupError:
            return False
        return True


if __name__ == "__main__":
    unittest.main()
