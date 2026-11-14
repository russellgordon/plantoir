#!/usr/bin/env python3
"""
A deploy typed in Terminal takes a work lease, so the app's Deploy greys for
it too (GitHub #829).

contracts/shared-rules.json -> workLeases.launcherLeases is the rule and its
cases; contracts/file-formats.json -> workLease the shape. This file:

  * runs the REAL deploy.sh, copied into a scratch working folder, deploying
    to a folder with a stand-in preview.sh that copies out the activity
    folder at the moment the deploy's own build runs, for every case that
    deploys (what PLANTOIR_LEASES_HELD_BY says decides whether it holds a
    lease);
  * checks the six lines against what the process table says of the bash
    that wrote them (its name, its start in whole seconds);
  * checks the leases are given back on the ways out a trap can see (a
    normal end, a failed one, ^C to the group, SIGTERM and SIGHUP to bash
    alone), and that kill -9, which runs no trap, leaves them naming a
    process that is gone;
  * checks the two trail lines (activityTrail.mustRecord "task started" and
    "task finished", their launcher lines): written by a run that took the
    leases, once each, and never by one the app started;
  * checks the start is read in UTC, with a fixed clock in the hour the
    clocks go back, and that a start that cannot be read means no lease;
  * and, for the cases that must never run here (--reset-token and --logout
    clear a saved sign-in; --plans needs the website builder), that the
    lease is taken only under the condition that leaves those out.

The mac's WorkLeaseLivenessTests runs workLeases.liveness's whole-second
cases against ProcessLiveness. Pure stdlib, no Docker, no network:

    python3 scripts/test_deploy_sh_work_leases.py
"""

import hashlib
import launcher_test_trail  # noqa: F401  every launcher run here keeps its trail in a temp folder (#738)
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
THIS_TOOLCHAIN = "teaching-quartz:src-1a2b3c4d"
MOMENT_SHAPE = re.compile(r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{7}Z$")


def _the_rule() -> dict:
    with open(REPOSITORY_ROOT / "contracts" / "shared-rules.json", encoding="utf-8") as handle:
        return json.load(handle)["workLeases"]["launcherLeases"]


def _the_block() -> str:
    text = (REPOSITORY_ROOT / "deploy.sh").read_text(encoding="utf-8")
    begin = "# >>> WORK LEASE BLOCK >>>"
    end = "# <<< WORK LEASE BLOCK <<<"
    assert text.count(begin) == 1 and text.count(end) == 1
    return text[text.index(begin):text.index(end)]


def _the_trail_lines() -> tuple:
    """The two launcher lines, as the contract writes them, for course C
    section 1 (the course and section these tests deploy)."""
    with open(REPOSITORY_ROOT / "contracts" / "shared-rules.json", encoding="utf-8") as handle:
        entries = json.load(handle)["activityTrail"]["mustRecord"]
    held = None
    let_go = None
    for entry in entries:
        if entry["event"] == "task started":
            held = entry["launcherLineWhenADeployRunningOutsidePlantoirHoldsItsSection"]
        if entry["event"] == "task finished":
            let_go = entry["launcherLineWhenItLetsItsSectionGo"]
    assert held and let_go, "the contract names both launcher lines"
    return (held.replace("{course}", "C").replace("{section}", "1"),
            let_go.replace("{course}", "C").replace("{section}", "1"))


# The second the fall-back hour makes ambiguous: 01:30 EST on Sunday
# 1 November 2026, which America/Toronto also shows for 01:30 EDT an hour
# earlier (1793511000).
FALL_BACK_SECOND = 1793514600

# A stand-in ps for work_lease_start_of: prints FALL_BACK_SECOND as `ps -o
# lstart` does, in whatever zone it is given (the real ps uses localtime too).
STAND_IN_PS = """#!/bin/bash
LC_ALL=C /bin/date -r {second} "+%a %b %e %T %Y"
""".format(second=FALL_BACK_SECOND)


def _a_process_id_nobody_has() -> int:
    finished = subprocess.Popen(["/usr/bin/true"])
    finished.wait()
    return finished.pid


# The stand-in build. It copies the activity folder out as the deploy's own
# build sees it, then waits for `go` (or a second) so a test can signal the
# deploy while it works.
STAND_IN_PREVIEW = """#!/bin/bash
activity="$PWD/courses/.internal/activity"
mkdir -p "$PWD/seen"
if [ -d "$activity" ]; then
  for lease in "$activity"/*.lease; do
    [ -e "$lease" ] && cp "$lease" "$PWD/seen/"
  done
fi
printf '%s' "$$" > "$PWD/stand-in-pid"
: > "$PWD/building"
waited=0
while [ ! -e "$PWD/go" ] && [ "$waited" -lt 100 ]; do sleep 0.05; waited=$((waited + 1)); done
built="$PWD/courses/C/.merged_output/section1"
printf '%s' '<html>built again</html>' > "$built/public/index.html"
: > "$built/.build-started"
printf '%s\\n' '{image}' > "$built/.built-with-toolchain"
""".format(image=THIS_TOOLCHAIN)


@unittest.skipIf(sys.platform == "win32", "deploy.sh is the mac's launcher")
@unittest.skipUnless(shutil.which("rsync") and os.path.exists("/bin/bash"), "needs bash and rsync")
class ADeployTypedInTerminalHoldsItsLeases(unittest.TestCase):

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.folder = self.tmp / "work"
        self.folder.mkdir()
        shutil.copy2(REPOSITORY_ROOT / "deploy.sh", self.folder / "deploy.sh")
        preview = self.folder / "preview.sh"
        preview.write_text(STAND_IN_PREVIEW, encoding="utf-8")
        preview.chmod(0o755)
        self.course = self.folder / "courses" / "C"
        (self.course / "notes").mkdir(parents=True)
        (self.course / "course_config.json").write_text(
            '{"course_code": "C", "section_numbers": [1], "num_sections": 1}', encoding="utf-8")
        (self.course / "notes" / "day-1.md").write_text("Day 1\n", encoding="utf-8")
        spelled = subprocess.run(["/bin/pwd", "-P"], cwd=str(self.folder),
                                 capture_output=True, check=True).stdout
        folder_id = hashlib.sha256(spelled).hexdigest()[:8]
        self.home = self.tmp / "home"
        builds = self.home / "Library" / "Application Support" / "Plantoir" / "builds" / folder_id / "C"
        section = builds / "section1"
        (section / "public").mkdir(parents=True)
        os.symlink(builds, self.course / ".merged_output")
        (section / ".build-started").write_text("started\n", encoding="utf-8")
        time.sleep(0.02)
        (section / "public" / "index.html").write_text("<html>the last build</html>", encoding="utf-8")
        (section / ".built-with-toolchain").write_text(THIS_TOOLCHAIN + "\n", encoding="utf-8")
        time.sleep(0.02)
        # An edit, so the deploy builds first and the stand-in sees its leases.
        with open(self.course / "notes" / "day-1.md", "a", encoding="utf-8") as handle:
            handle.write("edited\n")
        self.activity = self.folder / "courses" / ".internal" / "activity"
        self.trail = self.tmp / "trail"

    def _trail(self) -> list:
        written = self.trail / "activity.txt"
        if not written.exists():
            return []
        lines = []
        for line in written.read_text(encoding="utf-8").splitlines():
            # Each line opens with the moment it was written, then " · ".
            lines.append(line.split(" · ", 1)[1])
        return lines

    def _forget_the_trail(self):
        written = self.trail / "activity.txt"
        if written.exists():
            written.unlink()

    def _environment(self, held_by):
        environment = dict(os.environ)
        environment["HOME"] = str(self.home)
        environment.pop("PWD", None)
        environment["RSYNC_RSH"] = "false"
        environment.pop("PLANTOIR_LEASES_HELD_BY", None)
        # This test's own trail, so it can read the lines this run wrote
        # (launcher_test_trail above still keeps every other run's away from
        # the real trail).
        environment["PLANTOIR_TRAIL_DIR"] = str(self.trail)
        if held_by is not None:
            environment["PLANTOIR_LEASES_HELD_BY"] = held_by
        return environment

    def _command(self):
        return ["/bin/bash", "./deploy.sh", "C", "1", "--to-folder", str(self.tmp / "published"),
                "--non-interactive", "--image", THIS_TOOLCHAIN]

    def _deploy(self, held_by=None):
        (self.folder / "go").write_text("", encoding="utf-8")
        result = subprocess.run(self._command(), cwd=str(self.folder), capture_output=True,
                                timeout=180, env=self._environment(held_by))
        return result

    def _seen(self):
        seen = self.folder / "seen"
        if not seen.exists():
            return {}
        found = {}
        for lease in sorted(seen.iterdir()):
            found[lease.name] = lease.read_text(encoding="utf-8")
        return found

    def _kinds_seen(self):
        kinds = []
        for name in self._seen():
            kinds.append(name.split(".")[-3])
        return sorted(kinds)

    def test_every_case_that_deploys(self):
        held = {
            "absent": None,
            "running": str(os.getpid()),
            "gone": str(_a_process_id_nobody_has()),
            "notANumber": "the app",
        }
        held_line, let_go_line = _the_trail_lines()
        for case in _the_rule()["cases"]:
            if case["arguments"][0] != "--to-folder" or "start" in case:
                continue
            with self.subTest(case=case["name"]):
                self._forget_the_trail()
                seen = self.folder / "seen"
                if seen.exists():
                    shutil.rmtree(seen)
                # Each run builds: the edit is made again after the last build.
                with open(self.course / "notes" / "day-1.md", "a", encoding="utf-8") as handle:
                    handle.write("again\n")
                result = self._deploy(held[case["heldBy"]])
                self.assertEqual(result.returncode, 0, result.stdout.decode("utf-8", "replace"))
                self.assertTrue((self.folder / "building").exists(), "the deploy's own build ran")
                self.assertEqual(self._kinds_seen(), sorted(case["expect"]))
                self.assertFalse(self.activity.exists(), "the leases and the folders made for them are gone")
                self.assertFalse((self.folder / "courses" / ".internal").exists())
                ours = []
                for line in self._trail():
                    if "outside Plantoir" in line:
                        ours.append(line)
                if case["expect"]:
                    self.assertEqual(ours, [held_line, let_go_line], "once each, in order")
                else:
                    self.assertEqual(ours, [], "a deploy the app started writes neither line")

    def test_the_six_lines_are_the_formats(self):
        result = self._deploy()
        self.assertEqual(result.returncode, 0, result.stdout.decode("utf-8", "replace"))
        seen = self._seen()
        self.assertEqual(len(seen), 2, seen)
        bodies = set(seen.values())
        self.assertEqual(len(bodies), 1, "both leases say the same")
        body = bodies.pop()
        self.assertTrue(body.endswith("\n"))
        lines = body.split("\n")[:-1]
        self.assertEqual(len(lines), 6, lines)
        pid = int(lines[0])
        for name in seen:
            self.assertEqual(name.split(".")[0], "C")
            self.assertEqual(int(name.split(".")[-2]), pid)
            self.assertTrue(name.endswith(".lease"))
        self.assertEqual(lines[1], "bash", "the name the process table keeps (p_comm)")
        self.assertRegex(lines[2], MOMENT_SHAPE)
        self.assertRegex(lines[3], r"^\d{10}$", "the start, whole seconds")
        self.assertEqual(lines[4], "")
        self.assertEqual(lines[5], "sections 1=" + lines[2])

    def test_the_start_is_the_process_tables_second(self):
        """What the block writes for a running bash is the second the table
        gives for it, the comparison workLeases.liveness makes."""
        script = (_the_block() + 'printf "%s|" "$(work_lease_start_of "$$")"\n'
                  + 'LC_ALL=C ps -o lstart= -p "$$"\n')
        result = subprocess.run(["/bin/bash", "-c", "set -euo pipefail\n" + script],
                                capture_output=True, timeout=30)
        start, listed = result.stdout.decode().strip().split("|")
        stamp = time.mktime(time.strptime(listed.strip(), "%a %b %d %H:%M:%S %Y"))
        self.assertEqual(int(start), int(stamp))

    def test_the_start_is_read_in_utc_in_the_hour_the_clocks_go_back(self):
        """A fixed clock: a stand-in ps that prints one second of the fall-back
        hour in the zone it is given. Read in Toronto's local time (the code
        before the fix) that text names 01:30 EDT, an hour early, and the
        lease would read as gone for the deploy's whole life."""
        bin_folder = self.tmp / "bin"
        bin_folder.mkdir()
        (bin_folder / "ps").write_text(STAND_IN_PS, encoding="utf-8")
        (bin_folder / "ps").chmod(0o755)
        environment = dict(os.environ)
        environment["PATH"] = f"{bin_folder}:/usr/bin:/bin"
        environment["TZ"] = "America/Toronto"
        script = _the_block() + 'work_lease_start_of "$$"\n'
        result = subprocess.run(["/bin/bash", "-c", "set -euo pipefail\n" + script],
                                capture_output=True, timeout=30, env=environment)
        self.assertEqual(result.returncode, 0, result.stderr.decode("utf-8", "replace"))
        self.assertEqual(result.stdout.decode().strip(), str(FALL_BACK_SECOND))

    def test_a_start_that_cannot_be_read_takes_no_lease(self):
        """workLeases.launcherLeases' case with start unreadable: the block's
        own take_the_work_leases, with work_lease_start_of answering nothing,
        writes no lease, makes no folder and leaves no trail line."""
        case = None
        for each in _the_rule()["cases"]:
            if each.get("start") == "unreadable":
                case = each
        self.assertIsNotNone(case, "the contract holds the case")
        self.assertEqual(case["expect"], [])
        text = (REPOSITORY_ROOT / "deploy.sh").read_text(encoding="utf-8")
        begin = text.index("note_on_the_trail() {")
        note = text[begin:text.index("\n}\n", begin) + 3]
        script = "\n".join([
            "set -euo pipefail",
            note,
            _the_block(),
            "work_lease_start_of() { return 0; }",
            'take_the_work_leases C 1',
            # Asked while the deploy would work, before anything is given back.
            'if [[ -d courses/.internal ]]; then echo HELD; fi',
            'give_back_the_work_leases',
            "echo DEPLOYED",
        ])
        environment = dict(os.environ)
        environment["PLANTOIR_TRAIL_DIR"] = str(self.trail)
        result = subprocess.run(["/bin/bash", "-c", script], cwd=str(self.folder),
                                capture_output=True, timeout=30, env=environment)
        self.assertEqual(result.returncode, 0, result.stderr.decode("utf-8", "replace"))
        self.assertIn("DEPLOYED", result.stdout.decode())
        self.assertNotIn("HELD", result.stdout.decode(), "no lease and no folder while it works")
        self.assertFalse(self.activity.exists())
        self.assertFalse((self.folder / "courses" / ".internal").exists())
        self.assertEqual(self._trail(), [])

    def test_an_activity_folder_that_was_there_stays(self):
        self.activity.mkdir(parents=True)
        other = self.activity / "C.assist.1.lease"
        other.write_text("1\nPlantoir\n2026-11-14T00:00:00.0000000Z\n\n", encoding="utf-8")
        result = self._deploy()
        self.assertEqual(result.returncode, 0)
        self.assertEqual(self._kinds_seen(), ["assist", "build", "publish"])
        self.assertEqual(sorted(os.listdir(self.activity)), ["C.assist.1.lease"])

    def test_a_deploy_that_fails_gives_them_back(self):
        # A deploy folder that cannot be made fails after the leases are taken.
        blocker = self.tmp / "not-a-folder"
        blocker.write_text("", encoding="utf-8")
        environment = self._environment(None)
        result = subprocess.run(
            ["/bin/bash", "./deploy.sh", "C", "1", "--to-folder", str(blocker),
             "--non-interactive", "--image", THIS_TOOLCHAIN],
            cwd=str(self.folder), capture_output=True, timeout=180, env=environment)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.activity.exists())

    def _start_and_wait_for_the_build(self, new_group: bool):
        for leftover in (self.folder / "go", self.folder / "stand-in-pid"):
            if leftover.exists():
                leftover.unlink()
        process = subprocess.Popen(self._command(), cwd=str(self.folder), stdout=subprocess.DEVNULL,
                                   stderr=subprocess.DEVNULL, env=self._environment(None),
                                   start_new_session=new_group)
        deadline = time.monotonic() + 60
        while not (self.folder / "building").exists():
            self.assertLess(time.monotonic(), deadline, "the deploy's build never started")
            self.assertIsNone(process.poll(), "the deploy ended before its build")
            time.sleep(0.02)
        names = sorted(os.listdir(self.activity))
        self.assertEqual(len(names), 2, names)
        return process

    def _let_the_stand_in_finish(self):
        """The stand-in build is a child that can outlive a deploy ended by a
        signal; until it ends, the next deploy's guard sees it building."""
        (self.folder / "go").write_text("", encoding="utf-8")
        pid = int((self.folder / "stand-in-pid").read_text(encoding="utf-8"))
        deadline = time.monotonic() + 30
        while True:
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                return
            self.assertLess(time.monotonic(), deadline, "the stand-in build never finished")
            time.sleep(0.05)

    def test_the_ways_out_a_trap_sees_give_them_back(self):
        held_line, let_go_line = _the_trail_lines()
        for how in ("interrupt the group", "terminate bash", "hang up bash"):
            with self.subTest(how=how):
                self._forget_the_trail()
                building = self.folder / "building"
                if building.exists():
                    building.unlink()
                with open(self.course / "notes" / "day-1.md", "a", encoding="utf-8") as handle:
                    handle.write(how + "\n")
                process = self._start_and_wait_for_the_build(new_group=True)
                if how == "interrupt the group":
                    os.killpg(process.pid, signal.SIGINT)
                elif how == "terminate bash":
                    os.kill(process.pid, signal.SIGTERM)
                else:
                    os.kill(process.pid, signal.SIGHUP)
                process.wait(timeout=60)
                self._let_the_stand_in_finish()
                self.assertFalse(self.activity.exists(), how)
                ours = []
                for line in self._trail():
                    if "outside Plantoir" in line:
                        ours.append(line)
                self.assertEqual(ours, [held_line, let_go_line], how)

    def test_kill_9_leaves_them_naming_a_process_that_is_gone(self):
        process = self._start_and_wait_for_the_build(new_group=True)
        pid = process.pid
        os.kill(pid, signal.SIGKILL)
        process.wait(timeout=30)
        self._let_the_stand_in_finish()
        names = sorted(os.listdir(self.activity))
        self.assertEqual(names, [f"C.build.{pid}.lease", f"C.publish.{pid}.lease"])
        with self.assertRaises(ProcessLookupError):
            os.kill(pid, 0)
        held_line, let_go_line = _the_trail_lines()
        self.assertIn(held_line, self._trail())
        self.assertNotIn(let_go_line, self._trail(), "kill -9 runs no trap, so no second line")

class TheRunsThatMustNotHoldOne(unittest.TestCase):
    """--reset-token and --logout clear a saved sign-in, and --plans needs the
    website builder, so they are not run here: the lease is taken only under
    the condition that leaves all three out, after the #439 guard."""

    def test_the_call_is_guarded_and_after_the_guard(self):
        text = (REPOSITORY_ROOT / "deploy.sh").read_text(encoding="utf-8")
        call = ('if [[ "$RESET_TOKEN" != "true" && "$PLANS_MODE" != "true" ]]; then\n'
                '  if this_run_takes_work_leases "${PLANTOIR_LEASES_HELD_BY:-}"; then\n'
                '    take_the_work_leases "$COURSE_CODE" "$SECTION_NUM"\n')
        self.assertEqual(text.count(call), 1)
        self.assertEqual(text.count('take_the_work_leases "'), 1)
        guard = 'refuse_while_this_section_deploys "$COURSE_CODE" "$SECTION_NUM" deploy\n'
        self.assertLess(text.index(guard), text.index(call))
        self.assertIn('    --reset-token|--logout)\n      RESET_TOKEN="true" ;;\n', text)
        self.assertIn('"${' + _the_rule()["variable"] + ':-}"', text, "the variable the contract names")

    def test_the_cases_name_every_run_that_holds_none(self):
        empty = []
        for case in _the_rule()["cases"]:
            if not case["expect"]:
                empty.append(case["arguments"][0] if case["heldBy"] == "absent" else case["heldBy"])
            if case.get("start") == "unreadable":
                empty[-1] = "unreadable start"
        self.assertEqual(sorted(empty), ["--logout", "--plans", "--reset-token", "running", "unreadable start"])

    def test_every_later_exit_trap_gives_them_back(self):
        """A later `trap … EXIT` replaces an earlier one, so every EXIT trap
        set after the leases are taken gives them back as well."""
        text = (REPOSITORY_ROOT / "deploy.sh").read_text(encoding="utf-8")
        taken_at = text.index('take_the_work_leases "$COURSE_CODE"')
        for match in re.finditer(r"^\s*trap (.*) EXIT$", text, re.MULTILINE):
            if match.start() < taken_at and "give_back_the_work_leases" not in match.group(1):
                # Set before the leases exist (inside a function defined
                # earlier but run later is checked below by name).
                pass
            with self.subTest(trap=match.group(1)[:60]):
                self.assertIn("give_back_the_work_leases", match.group(1))


if __name__ == "__main__":
    unittest.main()
