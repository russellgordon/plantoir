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
from test_preview_while_deploying import BASH, TABLE_END, TABLE_START, PretendMac, function_named

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


if __name__ == "__main__":
    unittest.main(verbosity=1)
