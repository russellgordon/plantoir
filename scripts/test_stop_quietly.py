#!/usr/bin/env python3
"""
Stopping a build, or a publish, leaves quietly (GitHub #223 and #259).

Pressing Cancel in the progress view while a preview builds types ^C into
the console, which reaches build_site.py as a KeyboardInterrupt. (Stop Preview
and the console's Stop end the process without one.) It used to escape main() and print a
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

The publish half (GitHub #259) is the same fault one program up: Cancel in the
progress view during a publish reached deploy.py, which had no handler, and
the console showed its traceback — measured through a real pty as 26 lines
during the production rebuild and 10 at the surname question, exit -2.
deploy.py now runs main() through run_until_stopped(), which exits 130 with
nothing printed. Its real-interrupt case signals the whole process group, as
a ^C typed into a terminal does, and is skipped on Windows for the same reason.
A Cancel during the upload also drops the uploads still queued, rather than
running them all on the way out — measured through a pty with 40 files, 25
went up after the Cancel before, none after — so a Netlify deploy is left
waiting for files that never arrive and never goes live.
"""
import contextlib
import io
import os
import signal
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import _thread
from pathlib import Path

# Importing build_site by hand would otherwise leave scripts/__pycache__
# behind, which verify.sh fails on (it ships inside the app).
sys.dont_write_bytecode = True

import build_site
import deploy

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



# Run as a separate program by the publish case below: the REAL
# build_site.main(), with the build replaced by a long subprocess.run, placed
# where deploy.py looks for build_site.py (PLANTOIR_SCRIPTS_DIR) so that
# deploy.py's production rebuild runs it.
STAND_IN_BUILD_FOR_A_PUBLISH = r"""
import subprocess, sys
sys.dont_write_bytecode = True
sys.path.insert(0, %r)
import build_site
def build_that_runs_until_stopped(**arguments):
    print("started", flush=True)
    subprocess.run(["sleep", "30"], check=True)
build_site.build_section_site = build_that_runs_until_stopped
build_site.main()
"""


def interrupt_the_main_thread():
    """What the app's ^C does to deploy.py: a SIGINT that wakes its main
    thread wherever it is waiting. Where a real signal cannot be sent to one
    thread (Windows), the interrupter Python offers instead, which the main
    thread notices the next time it runs."""
    if hasattr(signal, "pthread_kill"):
        signal.pthread_kill(threading.main_thread().ident, signal.SIGINT)
    else:
        _thread.interrupt_main()


class PublishStopLeavesQuietlyTests(unittest.TestCase):

    # MARK: - Set up and tear down

    def setUp(self):
        self.original_main = deploy.main
        self.original_run = subprocess.run
        self.original_netlify_api = deploy.netlify_api

    def tearDown(self):
        deploy.main = self.original_main
        subprocess.run = self.original_run
        deploy.netlify_api = self.original_netlify_api

    # MARK: - Tests

    def test_an_interrupted_publish_exits_130_rather_than_raising(self):
        def publish_that_is_interrupted():
            raise KeyboardInterrupt

        deploy.main = publish_that_is_interrupted
        exit_code, escaped = self.run_and_catch(deploy.run_until_stopped)
        self.assertFalse(escaped, "The interrupt escaped deploy.py, which prints a traceback")
        self.assertEqual(
            exit_code, 130,
            "A cancelled publish must exit 130 — not 0, which reads as a finished publish",
        )

    def test_the_program_entry_goes_through_the_quiet_exit(self):
        # The case above calls run_until_stopped() directly, so it would still
        # pass if the program's entry point went back to calling main().
        text = (SCRIPTS_FOLDER / "deploy.py").read_text(encoding="utf-8")
        entry = text[text.rindex('if __name__ == "__main__":'):]
        self.assertIn("run_until_stopped()", entry)

    def test_a_rebuild_that_left_first_on_the_same_cancel_is_not_a_failure(self):
        # The Cancel reaches the build and deploy.py together. When the build
        # (which exits 130 when stopped) finishes leaving before deploy.py
        # hears its own interrupt, the rebuild comes back as a failed command
        # — and must still read as a cancel, not "Production rebuild failed".
        for stopped_status in (130, -2):
            def build_that_was_stopped(command, **arguments):
                raise subprocess.CalledProcessError(stopped_status, command)

            subprocess.run = build_that_was_stopped
            exit_code, escaped = self.run_and_catch(
                lambda: deploy.rebuild_for_production("ICS3U", "1", "mac")
            )
            subprocess.run = self.original_run
            self.assertFalse(escaped)
            self.assertEqual(exit_code, 130, "status %d" % stopped_status)

        def build_that_failed(command, **arguments):
            raise subprocess.CalledProcessError(1, command)

        subprocess.run = build_that_failed
        exit_code, escaped = self.run_and_catch(
            lambda: deploy.rebuild_for_production("ICS3U", "1", "mac")
        )
        subprocess.run = self.original_run
        self.assertEqual(exit_code, 1, "A build that really failed must still say so")

    def test_wrangler_that_left_first_on_the_same_cancel_is_not_a_failure(self):
        # The same race as the rebuild's, on the Cloudflare leg: wrangler is
        # seen leaving first, and its status must read as the Cancel rather
        # than a failed publish with a traceback.
        # 130 left quietly, -2 killed by SIGINT, 0xC000013A killed by Ctrl-C
        # on Windows.
        for stopped_status in (130, -2, 0xC000013A):
            def wrangler_that_was_stopped(command, **arguments):
                return subprocess.CompletedProcess(command, stopped_status)

            subprocess.run = wrangler_that_was_stopped
            exit_code, escaped = self.run_and_catch(
                lambda: deploy.deploy_to_cloudflare(Path("public"), "project", "token", "account")
            )
            subprocess.run = self.original_run
            self.assertFalse(escaped)
            self.assertEqual(exit_code, 130, "status %d" % stopped_status)

        def wrangler_that_failed(command, **arguments):
            return subprocess.CompletedProcess(command, 1)

        subprocess.run = wrangler_that_failed
        with self.assertRaises(RuntimeError, msg="A publish that really failed must still say so"):
            deploy.deploy_to_cloudflare(Path("public"), "project", "token", "account")
        subprocess.run = self.original_run

    def test_a_cancel_during_the_upload_starts_no_more_uploads(self):
        # Leaving the uploads' `with ThreadPoolExecutor` block used to RUN
        # every upload still queued — measured through a pty with 40 files:
        # 25 went up after the Cancel, and a Netlify deploy whose files all
        # arrive goes live. Now only the uploads already in flight finish.
        uploads_started = []
        interrupted_after = []
        lock = threading.Lock()

        def upload_that_takes_a_moment(method, path, token, **arguments):
            with lock:
                uploads_started.append(path)
                if len(uploads_started) == 15:
                    interrupted_after.append(len(uploads_started))
                    interrupt_the_main_thread()
            time.sleep(0.2)
            return {}

        deploy.netlify_api = upload_that_takes_a_moment
        with tempfile.TemporaryDirectory() as temporary:
            required, sha_to_pairs = self.forty_files_in(Path(temporary))
            escaped = False
            try:
                with contextlib.redirect_stdout(io.StringIO()):
                    deploy._upload_required_files("deploy", "token", Path(temporary), required, sha_to_pairs)
            except KeyboardInterrupt:
                escaped = True
        self.assertTrue(escaped, "The Cancel must still reach run_until_stopped()")
        # Up to five uploads are in flight when the Cancel lands, and on a
        # platform slow to deliver it each worker may start one more; never
        # the whole queue.
        self.assertLessEqual(
            len(uploads_started), interrupted_after[0] + 10,
            "%d of 40 uploads started in all, after a Cancel at the 15th" % len(uploads_started),
        )

    @unittest.skipIf(
        not hasattr(signal, "pthread_kill"),
        "Every upload is waiting to retry, so nothing wakes the main thread "
        "without a real signal, which Windows cannot send to one thread",
    )
    def test_an_upload_waiting_to_retry_gives_up_on_a_cancel(self):
        # An upload Netlify turned away (429) waits and tries again, for up to
        # a minute. After a Cancel it must not: the program would sit there
        # uploading after the teacher had stopped it.
        attempts = []
        lock = threading.Lock()

        def upload_turned_away(method, path, token, **arguments):
            with lock:
                attempts.append(path)
                if len(attempts) == 5:
                    interrupt_the_main_thread()
            raise RuntimeError("Netlify API error 429: slow down")

        deploy.netlify_api = upload_turned_away
        with tempfile.TemporaryDirectory() as temporary:
            required, sha_to_pairs = self.forty_files_in(Path(temporary), count=5)
            started = time.monotonic()
            try:
                with contextlib.redirect_stdout(io.StringIO()):
                    deploy._upload_required_files("deploy", "token", Path(temporary), required, sha_to_pairs)
            except KeyboardInterrupt:
                pass
            seconds = time.monotonic() - started
        self.assertLess(seconds, 5, "Uploads kept retrying for %.1f s after a Cancel" % seconds)

    @unittest.skipIf(os.name == "nt", "Windows cannot send SIGINT to a process group")
    def test_a_real_interrupt_during_the_rebuild_prints_no_traceback(self):
        with tempfile.TemporaryDirectory() as temporary:
            stand_in_scripts = Path(temporary) / "scripts"
            stand_in_scripts.mkdir()
            (stand_in_scripts / "build_site.py").write_text(
                STAND_IN_BUILD_FOR_A_PUBLISH % str(SCRIPTS_FOLDER), encoding="utf-8"
            )
            courses = Path(temporary) / "courses"
            public = courses / "ICS3U" / ".merged_output" / "section1" / "public"
            public.mkdir(parents=True)
            (courses / "ICS3U" / "course_config.json").write_text(
                '{"course_code": "ICS3U"}', encoding="utf-8"
            )
            # A preview build's live-reload address makes deploy.py rebuild
            # for production first — the moment a teacher's Cancel lands.
            (public / "index.html").write_text(
                '<script>new WebSocket("ws://localhost:9081")</script>', encoding="utf-8"
            )
            environment = dict(os.environ)
            environment["PYTHONDONTWRITEBYTECODE"] = "1"
            environment["PLANTOIR_SCRIPTS_DIR"] = str(stand_in_scripts)
            environment["PLANTOIR_COURSES_DIR"] = str(courses)
            environment.pop("NETLIFY_AUTH_TOKEN", None)
            process = subprocess.Popen(
                [sys.executable, str(SCRIPTS_FOLDER / "deploy.py"), "--course", "ICS3U", "--section", "1"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=environment,
                start_new_session=True,
            )
            try:
                self.read_until_started(process)
                # Wait until the build's own long-running child exists in the
                # group, so the interrupt lands where a teacher's does:
                # mid-build, not while Popen is still creating the child.
                self.wait_for_sleep_in_group(process.pid)
                # The whole group, as a ^C typed into a terminal reaches it.
                os.killpg(process.pid, signal.SIGINT)
                remaining_output, error_output = process.communicate(timeout=20)
            finally:
                if process.poll() is None:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.communicate()
            self.assertEqual(process.returncode, 130, "stderr was:\n" + error_output)
            self.assertNotIn("Traceback", error_output)
            self.assertEqual(error_output, "", "Cancelling a publish should print nothing at all")

    # MARK: - Helpers

    def run_and_catch(self, action):
        # KeyboardInterrupt is not an Exception, so unittest would not catch
        # an escaped one: it would end the whole run instead of failing.
        exit_code = None
        escaped = False
        try:
            # What deploy.py prints on the way is not under test here.
            with contextlib.redirect_stdout(io.StringIO()):
                action()
        except SystemExit as leaving:
            exit_code = leaving.code
        except KeyboardInterrupt:
            escaped = True
        return exit_code, escaped

    def forty_files_in(self, folder, count=40):
        required = []
        sha_to_pairs = {}
        for number in range(count):
            name = "page%02d.html" % number
            (folder / name).write_text("page %d" % number, encoding="utf-8")
            digest = "%040d" % number
            required.append(digest)
            sha_to_pairs[digest] = [("/" + name, name)]
        return required, sha_to_pairs

    def read_until_started(self, process):
        for line in process.stdout:
            if line.strip() == "started":
                return
        self.fail("The stand-in build never started")

    def wait_for_sleep_in_group(self, group_id):
        for attempt in range(400):
            found = subprocess.run(
                ["pgrep", "-g", str(group_id), "sleep"],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
            )
            if found.stdout.strip():
                return
            # Polling for a condition, with a ceiling of twenty seconds.
            time.sleep(0.05)
        self.fail("The stand-in build never started its child")


if __name__ == "__main__":
    unittest.main()
