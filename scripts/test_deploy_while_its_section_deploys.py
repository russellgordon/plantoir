#!/usr/bin/env python3
"""
A deploy of a section refuses while that same section is still being
deployed — by a deploy set for later whose script is still running (including
a run ended by setting the section again: the "leftover run"), or by deploy.sh
for that course and section (GitHub #439, decided by Russell 2026-10-04). The
rule and its cases are data:
`contracts/shared-rules.json` -> `deployWhileItsSectionDeploys`.

This file runs `launcherCases` against the REAL guard, cut out of deploy.sh
AND preview.sh between its markers (the two copies must be identical) — not
retyped — under `/bin/bash`. `ps` and `lsof` are small pretend programs put
first on PATH, answering from files in a scratch folder; the trail is written
under a scratch HOME. Nothing is started and nothing is deployed.

It also checks, as text, what a behaviour test cannot see: where each launcher
asks (deploy.sh on every run that deploys; preview.sh on a --build-only run
only), that each asks before anything is changed, and that the look trusts no
remembered process id and reads the table only through the one reader.

**Windows.** Skipped where there is no bash that can run a program, as the
launcher tests beside it are: Windows' launchers are .ps1 files, which owe the
same guard (the contract's appliesOnWhy).

Pure stdlib. Run with:

    python3 scripts/test_deploy_while_its_section_deploys.py
"""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True

from test_deploy_sh_questions import HAS_BASH, REPOSITORY_ROOT
from test_preview_while_deploying import (BASH, FAKE_PS_FOR_THE_REAL_LAUNCHER, TABLE_END, TABLE_START, PretendMac,
                                          function_named)

GUARD_START = "# >>> DEPLOY WHILE ITS SECTION DEPLOYS GUARD >>>"
GUARD_END = "# <<< DEPLOY WHILE ITS SECTION DEPLOYS GUARD <<<"
DEPLOY_CALL = ('if [[ "$RESET_TOKEN" != "true" ]]; then\n'
               '  refuse_while_this_section_deploys "$COURSE_CODE" "$SECTION_NUM" deploy\nfi\n')
BUILD_CALL = ('if [[ -n "$BUILD_ONLY" && -z "${STOP_MODE:-}" ]]; then\n'
              '  refuse_while_this_section_deploys "$COURSE" "$SECTION" build\nfi\n')


def the_rule() -> dict:
    rules = json.loads((REPOSITORY_ROOT / "contracts" / "shared-rules.json").read_text(encoding="utf-8"))
    return rules["deployWhileItsSectionDeploys"]


def the_trail_entry() -> dict:
    rules = json.loads((REPOSITORY_ROOT / "contracts" / "shared-rules.json").read_text(encoding="utf-8"))
    for entry in rules["activityTrail"]["mustRecord"]:
        if entry["event"] == "build declined, course busy elsewhere":
            return entry
    raise AssertionError("the contract no longer has a 'build declined, course busy elsewhere' event")


def launcher_text(name: str) -> str:
    return (REPOSITORY_ROOT / name).read_text(encoding="utf-8")


def cut(text: str, start: str, end: str, where: str) -> str:
    begin = text.find(start)
    finish = text.find(end)
    if begin < 0 or finish < 0:
        raise AssertionError(f"the markers {start!r} are missing from {where}")
    return text[begin:finish + len(end)]


def the_guard(launcher: str = "deploy.sh") -> str:
    return cut(launcher_text(launcher), GUARD_START, GUARD_END, launcher)


def the_process_table_block(launcher: str = "deploy.sh") -> str:
    return cut(launcher_text(launcher), TABLE_START, TABLE_END, launcher)


def refuse(mac: PretendMac, launcher: str, leg: str, course: str, section: str) -> subprocess.CompletedProcess:
    """Runs the real guard, cut out of `launcher`, as that launcher's run would."""
    text = launcher_text(launcher)
    script = "\n".join([
        "set -uo pipefail",
        function_named(text, "note_on_the_trail"),
        the_process_table_block(launcher),
        the_guard(launcher),
        "export THIS_RUN=$$",
        f"refuse_while_this_section_deploys {course.upper()!r} {section!r} {leg}",
        "echo ALLOWED",
    ])
    environment = dict(os.environ)
    environment["PATH"] = f"{mac.bin}:{environment.get('PATH', '/usr/bin:/bin')}"
    environment["FAKE"] = str(mac.fake)
    environment["HOME"] = str(mac.home)
    # The words the pretend ps lists for this run itself; this run never
    # counts, so they only have to be there.
    environment["PREVIEWED"] = f"{course} {section}"
    return subprocess.run([BASH, "-c", script], cwd=mac.here, env=environment,
                          capture_output=True, text=True, timeout=30)


def expected_lines(who: str, leg: str, course: str, section: str) -> list:
    key = ("later" if who == "later" else "another") + ("Deploy" if leg == "deploy" else "Build")
    lines = []
    for line in the_rule()["sentences"]["launcher"][key]:
        lines.append(line.replace("{course}", course).replace("{section}", section))
    return lines


def expected_trail(who: str, leg: str, course: str, section: str) -> str:
    entry = the_trail_entry()
    key = ("launcherLineWhenALaterDeployIsStillWorking" if who == "later"
           else "launcherLineWhenItsSectionIsAlreadyBeingDeployed")
    return entry[key].replace("{course}", course).replace("{section}", section).replace("{leg}", leg)


@unittest.skipUnless(HAS_BASH, "needs a bash that can run a program")
class TheLauncherCases(unittest.TestCase):
    """Every launcherCases case, against the real guard in BOTH launchers."""

    def run_case(self, case: dict, launcher: str) -> tuple:
        with tempfile.TemporaryDirectory() as folder:
            mac = PretendMac(Path(folder))
            mac.lay_out(case)
            course = case.get("course", "ICS4U")
            section = case.get("section", "2")
            leg = case.get("leg", "deploy")
            result = refuse(mac, launcher, leg, course, section)
            return result, mac.trail(), course.upper(), section, leg

    def test_every_case(self):
        cases = the_rule()["launcherCases"]
        self.assertGreaterEqual(len(cases), 20)
        for case in cases:
            # The guard is one block, identical in both launchers; each case
            # is run through the launcher whose leg it names, and through the
            # other copy as well, so a copy cannot drift and stay green.
            for launcher in ("deploy.sh", "preview.sh"):
                with self.subTest(case["name"], launcher=launcher):
                    result, trail, course, section, leg = self.run_case(case, launcher)
                    if case["expect"] == "refused":
                        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                        self.assertNotIn("ALLOWED", result.stdout)
                        for line in expected_lines(case["who"], leg, course, section):
                            self.assertIn(line, result.stdout.splitlines())
                        self.assertEqual(len(trail), 1, trail)
                        self.assertTrue(trail[0].endswith(" · " + expected_trail(case["who"], leg, course, section)),
                                        trail[0])
                    else:
                        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                        self.assertIn("ALLOWED", result.stdout)
                        self.assertEqual(trail, [], "an allowed deploy writes nothing on the trail")

    def test_the_cases_cover_what_the_review_asked_for(self):
        """#439 plan review, finding 3, and ruling 9."""
        names = " ".join(case["name"] for case in the_rule()["launcherCases"])
        for words in ("Application Support", "new run's own leg", "bash -x", "section 12", "another course",
                      "does not list this run", "app line alone, with its trailing words", "unreadable",
                      "command line", "ANOTHER folder", "own ancestor"):
            self.assertIn(words, names)
        spaced = [case for case in the_rule()["launcherCases"] if "Application Support" in case["name"]]
        self.assertIn("Application Support/", spaced[0]["processes"][0][2])


class TheTwoCopies(unittest.TestCase):

    def test_deploy_sh_and_preview_sh_carry_the_same_guard(self):
        self.assertEqual(the_guard("deploy.sh"), the_guard("preview.sh"))

    def test_setup_sh_has_no_guard(self):
        self.assertNotIn(GUARD_START, launcher_text("setup.sh"))


class TheCallSites(unittest.TestCase):
    """What a behaviour test cannot see: when and where each launcher asks."""

    def test_deploy_sh_asks_unless_it_only_clears_a_token(self):
        text = launcher_text("deploy.sh")
        self.assertEqual(text.count(DEPLOY_CALL), 1)
        self.assertLess(text.find(GUARD_END), text.find(DEPLOY_CALL), "defined before it is asked")
        self.assertLess(text.find(TABLE_START), text.find(DEPLOY_CALL), "the reader is defined before it is asked")

    def test_deploy_sh_asks_before_anything_is_changed(self):
        text = launcher_text("deploy.sh")
        call = text.find(DEPLOY_CALL)
        for first_change in ('link_course_build_output "$COURSE_CODE"', "ensure_container_runtime\n",
                             "BUILD_CONTEXT=$(resolve_build_context)"):
            place = text.find(first_change)
            self.assertGreater(place, 0, first_change)
            self.assertLess(call, place, f"the guard must run before {first_change!r}")
        # ... and after the arguments are read, so the course is the one asked.
        self.assertLess(text.find('COURSE_CODE="$(printf'), call)
        self.assertLess(text.find("--reset-token|--logout)"), call)

    def test_preview_sh_asks_on_a_build_only_run_only(self):
        text = launcher_text("preview.sh")
        self.assertEqual(text.count(BUILD_CALL), 1)
        call = text.find(BUILD_CALL)
        self.assertLess(text.find(GUARD_END), call)
        for first_change in ('link_course_build_output "$COURSE"', "# -------------------- Stop mode",
                             "ensure_container_runtime\n", "# >>> PREVIEW PORT BLOCK >>>"):
            place = text.find(first_change)
            self.assertGreater(place, 0, first_change)
            self.assertLess(call, place, f"the guard must run before {first_change!r}")

    def test_the_look_trusts_no_remembered_process_id(self):
        for code_line in the_guard().splitlines():
            if code_line.lstrip().startswith("#"):
                continue
            self.assertNotIn("kill -0", code_line)
            self.assertNotIn(".lease", code_line)

    def test_the_guard_reads_the_table_only_through_the_one_reader(self):
        code = "\n".join(line for line in the_guard().splitlines() if not line.lstrip().startswith("#"))
        self.assertEqual(code.count("the_launchers_running "), 1)
        for private in ("ps -Ao", "ca\\.russellgordon", "ca.russellgordon", "label_code"):
            self.assertNotIn(private, code, private)

    def test_the_sentences_name_no_machinery_and_say_deploy(self):
        for lines in the_rule()["sentences"]["launcher"].values():
            for line in lines:
                for word in ("workspace", "container", "script", "Docker", "docker", "publish"):
                    self.assertNotIn(word, line)



# Mac only, for TheRealPreviewUpToItsGuard's reason: the pretend ps walks the
# REAL process table with /bin/ps -o to list this run and its ancestors.
@unittest.skipUnless(HAS_BASH and sys.platform == "darwin" and Path("/bin/ps").exists(),
                     "needs a Mac: the pretend ps walks the real table with /bin/ps -o")
class TheRealLaunchersUpToTheirGuard(unittest.TestCase):
    """The cases above paste the reader and the guard in themselves, and the
    call sites are otherwise checked as TEXT, so a call made under the wrong
    condition (a build-only run that never asks, say) would stay green (#439
    implementation review, finding 9). This runs deploy.sh and preview.sh
    --build-only THEMSELVES, from their first line to just after the guard's
    call, and stops there: no docker or colima on PATH, a scratch HOME, and
    pretend ps and lsof. The cut is made at the call LINE, not at its whole
    if-block, so a changed condition is caught by what the launcher does."""

    LEFTOVER = ("/bin/bash /Users/t/Library/Application Support/Plantoir/scheduled/"
                "ca.russellgordon.Plantoir.deploy.ICS4U.section2.{hereID}.sh")

    def run_the_real_prefix(self, launcher: str, call_line: str, arguments: list, working: bool):
        text = launcher_text(launcher)
        self.assertEqual(text.count(call_line), 1, call_line)
        end_of_block = text.index("fi\n", text.index(call_line)) + len("fi\n")
        prefix = text[:end_of_block] + "echo REACHED\nexit 0\n"
        with tempfile.TemporaryDirectory() as folder:
            mac = PretendMac(Path(folder))
            (mac.bin / "ps").write_text(FAKE_PS_FOR_THE_REAL_LAUNCHER, encoding="utf-8")
            (mac.here / launcher).write_text(prefix, encoding="utf-8")
            (mac.here / "courses" / "ICS4U" / "section2").mkdir(parents=True)
            (mac.here / "courses" / "ICS4U" / "course_config.json").write_text("{}\n", encoding="utf-8")
            rows = [[801, 1, self.LEFTOVER]] if working else []
            mac.lay_out({"processes": rows})
            environment = {"HOME": str(mac.home), "FAKE": str(mac.fake), "PATH": f"{mac.bin}:/usr/bin:/bin"}
            result = subprocess.run([BASH, "./" + launcher] + arguments, cwd=mac.here, env=environment,
                                    capture_output=True, text=True, timeout=60)
            calls_file = mac.fake / "calls"
            calls = calls_file.read_text(encoding="utf-8") if calls_file.exists() else ""
            self.assertIn("ps -Ao pid=,ppid=,args=", calls,
                          f"the real {launcher} never read the process table: " + result.stdout + result.stderr)
            return result

    def check(self, launcher: str, call_line: str, arguments: list, leg: str):
        refused = self.run_the_real_prefix(launcher, call_line, arguments, working=True)
        self.assertEqual(refused.returncode, 1, refused.stdout + refused.stderr)
        self.assertNotIn("REACHED", refused.stdout)
        for line in expected_lines("later", leg, "ICS4U", "2"):
            self.assertIn(line, refused.stdout.splitlines())
        self.assertNotIn("command not found", refused.stderr)
        allowed = self.run_the_real_prefix(launcher, call_line, arguments, working=False)
        self.assertEqual(allowed.returncode, 0, allowed.stdout + allowed.stderr)
        self.assertIn("REACHED", allowed.stdout)

    def test_the_real_deploy_sh_refuses_while_a_leftover_run_works(self):
        self.check("deploy.sh", 'refuse_while_this_section_deploys "$COURSE_CODE" "$SECTION_NUM" deploy\n',
                   ["ICS4U", "2"], "deploy")

    def test_the_real_preview_sh_build_only_refuses_while_a_leftover_run_works(self):
        self.check("preview.sh", 'refuse_while_this_section_deploys "$COURSE" "$SECTION" build\n',
                   ["ICS4U", "2", "--build-only", "--image", "x"], "build")

if __name__ == "__main__":
    unittest.main(verbosity=1)
