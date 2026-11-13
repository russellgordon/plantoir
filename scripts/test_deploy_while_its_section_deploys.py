#!/usr/bin/env python3
"""
A deploy of a section refuses while that same section is still being
deployed — by a deploy set for later whose script is still running (including
a run ended by setting the section again: the "leftover run"), or by deploy.sh
for that course and section (GitHub #439, decided by Russell 2026-10-04) — and,
since #729, while it is being BUILT by another `preview.sh --build-only`: a
deploy's build leg (`--for-deploy`, said as "being deployed") or a rebuild
(said as "being built"). The rule and its cases are data:
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
launcher tests beside it are: Windows' launchers are .ps1 files, which carry
the same guard since #467 and run every launcherCase through
windows-app/test_launcher_rules.ps1 (LauncherRulesContractTests).

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
              '  refuse_while_this_section_deploys "$COURSE" "$SECTION" "${FOR_DEPLOY:+deploy-}build"\nfi\n')


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


def refuse(mac: PretendMac, launcher: str, leg: str, course: str, section: str,
           this_run_words: str = "") -> subprocess.CompletedProcess:
    """Runs the real guard, cut out of `launcher`, as that launcher's run would.
    `this_run_words` are the words the pretend ps lists for THIS run after
    `./preview.sh` (the course and section when left out)."""
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
    # The app hands every launcher its trail folder (#664); one inherited from
    # the shell running these tests would send the line out of the scratch HOME.
    environment.pop("PLANTOIR_TRAIL_DIR", None)
    # The words the pretend ps lists for this run itself; this run never
    # counts, so they only have to be there.
    environment["PREVIEWED"] = this_run_words or f"{course} {section}"
    return subprocess.run([BASH, "-c", script], cwd=mac.here, env=environment,
                          capture_output=True, text=True, timeout=30)


def expected_lines(who: str, leg: str, course: str, section: str) -> list:
    if who not in ("later", "another", "building"):
        raise AssertionError(f"a refused case names who as later, another or building, not {who!r}")
    # A deploy's own build leg (#729 review, L-a3) says "deployed" only when
    # another BUILD is in the way; otherwise it says what the build leg says.
    says_deploy = leg == "deploy" or (leg == "deploy-build" and who == "building")
    key = who + ("Deploy" if says_deploy else "Build")
    lines = []
    for line in the_rule()["sentences"]["launcher"][key]:
        lines.append(line.replace("{course}", course).replace("{section}", section))
    return lines


def expected_trail(who: str, leg: str, course: str, section: str) -> str:
    entry = the_trail_entry()
    keys = {"later": "launcherLineWhenALaterDeployIsStillWorking",
            "another": "launcherLineWhenItsSectionIsAlreadyBeingDeployed",
            "building": "launcherLineWhenItsSectionIsAlreadyBeingBuilt"}
    key = keys[who]
    trail_leg = "deploy" if leg == "deploy" else "build"
    return entry[key].replace("{course}", course).replace("{section}", section).replace("{leg}", trail_leg)


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

    def test_a_deploy_that_has_ended_since_the_table_was_read_does_not_count(self):
        # #737: a `deploy.sh ICS4U 2` the table listed has exited by the time
        # its folder is asked, so lsof says nothing. It used to count, in ANY
        # folder - a false "already being deployed" whenever a short deploy of
        # the same course and section ended, anywhere, at the wrong moment.
        # Mac mechanics (ps then lsof), so it is not a shared launcherCase:
        # deploy.ps1 reads one snapshot and asks no second question.
        ended = {"processes": [[700, 1, "/bin/bash ./deploy.sh ICS4U 2"]], "cwd": {},
                 "endedAfterTheTableWasRead": [700]}
        still_running = {"processes": [[700, 1, "/bin/bash ./deploy.sh ICS4U 2"]], "cwd": {}}
        for launcher in ("deploy.sh", "preview.sh"):
            leg = "deploy" if launcher == "deploy.sh" else "build"
            with self.subTest(launcher=launcher, case="ended"):
                result, trail, _course, _section, _leg = self.run_case(dict(ended, leg=leg), launcher)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("ALLOWED", result.stdout)
                self.assertEqual(trail, [])
            with self.subTest(launcher=launcher, case="still running, folder unknown"):
                result, trail, _course, _section, _leg = self.run_case(dict(still_running, leg=leg), launcher)
                self.assertEqual(result.returncode, 1, "#381's rule: a live deploy whose folder cannot be asked counts")
                self.assertEqual(len(trail), 1, trail)

    def test_a_build_that_has_ended_since_the_table_was_read_does_not_count(self):
        # #737's race, for the build legs #729 counts: a preview.sh
        # --build-only the table listed has exited by the time its folder is
        # asked. It must not refuse, in either words.
        for args in ("/bin/bash ./preview.sh ICS4U 2 --build-only",
                     "/bin/bash ./preview.sh ICS4U 2 --build-only --for-deploy"):
            ended = {"processes": [[700, 1, args]], "cwd": {}, "endedAfterTheTableWasRead": [700]}
            still_running = {"processes": [[700, 1, args]], "cwd": {}}
            for launcher in ("deploy.sh", "preview.sh"):
                leg = "deploy" if launcher == "deploy.sh" else "build"
                with self.subTest(args=args, launcher=launcher, case="ended"):
                    result, trail, _course, _section, _leg = self.run_case(dict(ended, leg=leg), launcher)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertIn("ALLOWED", result.stdout)
                    self.assertEqual(trail, [])
                with self.subTest(args=args, launcher=launcher, case="still running, folder unknown"):
                    result, trail, _course, _section, _leg = self.run_case(dict(still_running, leg=leg), launcher)
                    self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                    self.assertEqual(len(trail), 1, trail)

    def test_another_accounts_work_never_refuses_this_one(self):
        # #729 review, L-a1: a process another account runs is listed by ps,
        # but lsof cannot read its folder, and a folder that belongs to another
        # account is not this one. Until then it refused, in every folder.
        for args in ("/bin/bash ./deploy.sh ICS4U 2",
                     "/bin/bash ./preview.sh ICS4U 2 --build-only",
                     "/bin/bash ./preview.sh ICS4U 2 --build-only --for-deploy"):
            for launcher in ("deploy.sh", "preview.sh"):
                leg = "deploy" if launcher == "deploy.sh" else "build"
                with self.subTest(args=args, launcher=launcher):
                    result, trail, _course, _section, _leg = self.run_case(
                        {"processes": [[700, 1, args]], "cwd": {}, "otherAccount": [700], "leg": leg}, launcher)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertIn("ALLOWED", result.stdout)
                    self.assertEqual(trail, [])

    def test_this_accounts_work_whose_folder_cannot_be_read_still_counts(self):
        # The choice kept from #381: THIS account's deploy or build of this
        # very section is proved even when lsof cannot name its folder (it
        # can fail for a process in the middle of exec, or under a sandbox),
        # and the safe side for the deploy is to refuse.
        for args, who in (("/bin/bash ./deploy.sh ICS4U 2", "another"),
                          ("/bin/bash ./preview.sh ICS4U 2 --build-only", "building")):
            with self.subTest(args=args):
                result, trail, course, section, leg = self.run_case(
                    {"processes": [[700, 1, args]], "cwd": {}}, "deploy.sh")
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                for line in expected_lines(who, leg, course, section):
                    self.assertIn(line, result.stdout.splitlines())

    def test_this_run_is_never_its_own_overlap(self):
        # The worst fault #729 could add: a build leg refused by ITSELF. The
        # pretend ps lists this very run with the same words as the build it
        # is, and its parent as the app; with nothing else running it goes on.
        for words in ("ICS4U 2 --build-only", "ICS4U 2 --build-only --for-deploy",
                      "ICS4U 2 --build-only --non-interactive --for-deploy"):
            for launcher in ("deploy.sh", "preview.sh"):
                with self.subTest(words=words, launcher=launcher):
                    with tempfile.TemporaryDirectory() as folder:
                        mac = PretendMac(Path(folder))
                        mac.lay_out({"processes": [],
                                     "parentArgs": "/Applications/Plantoir.app/Contents/MacOS/Plantoir"})
                        result = refuse(mac, launcher, "build", "ICS4U", "2", this_run_words=words)
                        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                        self.assertIn("ALLOWED", result.stdout)
                        self.assertEqual(mac.trail(), [])

    def test_the_liveness_look_is_ps_never_kill(self):
        # kill -0 fails for another account's process that is still running,
        # which the guard must still count (#737).
        code = "\n".join(line for line in the_guard().splitlines() if not line.lstrip().startswith("#"))
        self.assertIn('ps -p "$pid" -o uid=', code)

    def test_the_cases_cover_what_the_review_asked_for(self):
        """#439 plan review, finding 3, and ruling 9."""
        names = " ".join(case["name"] for case in the_rule()["launcherCases"])
        for words in ("Application Support", "new run's own leg", "bash -x", "section 12", "another course",
                      "does not list this run", "app line alone, with its trailing words", "unreadable",
                      "command line", "ANOTHER folder", "own ancestor"):
            self.assertIn(words, names)
        # #729: a deploy's build leg and a rebuild, each in this folder and in
        # another, the app's two builds as brothers, and a build only named.
        for words in ("build leg (--build-only --for-deploy) in this folder", "build leg in ANOTHER folder",
                      "a rebuild (--build-only, no --for-deploy)", "a rebuild in ANOTHER folder",
                      "same app are not one family", "beside its own rebuild", "merely named on a line, in an editor",
                      "being stopped"):
            self.assertIn(words, names)
        whos = set()
        for case in the_rule()["launcherCases"]:
            if case["expect"] == "refused":
                whos.add(case["who"])
        self.assertEqual(whos, {"later", "another", "building"})
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

    def test_a_build_in_the_way_is_never_called_a_deploy(self):
        # #729: "building" is said when what is in the way is a build; its
        # sentences must not claim a deploy is running, and the others must
        # not claim a build.
        for name, lines in the_rule()["sentences"]["launcher"].items():
            with self.subTest(name):
                if name.startswith("building"):
                    self.assertIn("is already being built", lines[0])
                    self.assertNotIn("being deployed", lines[0])
                else:
                    self.assertNotIn("being built", lines[0])


class AScheduledDeployIsNamedAsRunning(unittest.TestCase):
    """#835 part 1. A deploy that is only SCHEDULED holds nothing: only its
    run, while it works, is in anybody's way. Every sentence that names it as
    the thing in the way says that it is running, and none says "set for
    later", which Russell read as "having a deploy scheduled stops me
    deploying" (2026-11-13). The launchers print the contract's sentences
    (TheLauncherCases), and the mac's tests pin the window's help and the
    assistant's sentences to the contract, so the contract is the one place
    to look."""

    def sentences_that_name_it(self) -> dict:
        rules = json.loads((REPOSITORY_ROOT / "contracts" / "shared-rules.json").read_text(encoding="utf-8"))
        wording = json.loads((REPOSITORY_ROOT / "contracts" / "assist-wording.json").read_text(encoding="utf-8"))
        launcher = rules["deployWhileItsSectionDeploys"]["sentences"]["launcher"]
        return {
            "returningToASectionMidDeploy.heldElsewhere.help":
                rules["returningToASectionMidDeploy"]["heldElsewhere"]["help"],
            "deployWhileItsSectionDeploys.sentences.launcher.laterDeploy": launcher["laterDeploy"][0],
            "deployWhileItsSectionDeploys.sentences.launcher.laterBuild": launcher["laterBuild"][0],
            "launcherLineWhenALaterDeployIsStillWorking":
                the_trail_entry()["launcherLineWhenALaterDeployIsStillWorking"],
            "wording.courseIsBeingBuiltElsewhere": wording["wording"]["courseIsBeingBuiltElsewhere"],
            "wording.deployRefusedWhileALaterDeployWorks": wording["wording"]["deployRefusedWhileALaterDeployWorks"],
        }

    def test_each_says_the_scheduled_deploy_is_running(self):
        for key, sentence in self.sentences_that_name_it().items():
            with self.subTest(key):
                self.assertNotIn("set for later", sentence)
                self.assertIn("scheduled deploy that", sentence)
                self.assertTrue("is running" in sentence or "is still running" in sentence
                                or "was still running" in sentence, sentence)

    def test_the_failure_cases_follow_the_launcher(self):
        for case in the_rule()["failureExplanationCases"]:
            with self.subTest(case["expect"]):
                self.assertNotIn("set for later", case["output"])
                self.assertNotIn("set for later", case["expect"])

    def test_the_launchers_print_no_set_for_later(self):
        for name in ("deploy.sh", "preview.sh"):
            for line in launcher_text(name).splitlines():
                if "set for later" in line and ("echo" in line or "note_on_the_trail" in line):
                    self.fail(f"{name} still prints: {line.strip()}")



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

    def run_the_real_prefix(self, launcher: str, call_line: str, arguments: list, working: bool,
                            rows: list = None, cwd: dict = None):
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
            if rows is None:
                rows = [[801, 1, self.LEFTOVER]] if working else []
            mac.lay_out({"processes": rows if working else [], "cwd": cwd or {}})
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
        self.check("preview.sh", 'refuse_while_this_section_deploys "$COURSE" "$SECTION" "${FOR_DEPLOY:+deploy-}build"\n',
                   ["ICS4U", "2", "--build-only", "--image", "x"], "build")

    def test_the_real_launchers_refuse_while_another_build_of_the_section_runs(self):
        """#729 through the real parsers: a deploy's build leg passes
        --for-deploy and is accepted; a plain rebuild in this folder refuses
        it ("built"), and a deploy's build leg in this folder refuses a
        deploy.sh ("deployed")."""
        build_call = 'refuse_while_this_section_deploys "$COURSE" "$SECTION" "${FOR_DEPLOY:+deploy-}build"\n'
        deploy_call = 'refuse_while_this_section_deploys "$COURSE_CODE" "$SECTION_NUM" deploy\n'
        rebuild = [[700, 1, "/bin/bash ./preview.sh ICS4U 2 --build-only --non-interactive"]]
        build_leg = [[700, 1, "/bin/bash ./preview.sh ICS4U 2 --build-only --for-deploy"]]
        for launcher, call, arguments, rows, who, leg in (
                ("preview.sh", build_call, ["ICS4U", "2", "--build-only", "--for-deploy", "--image", "x"],
                 rebuild, "building", "deploy-build"),
                ("preview.sh", build_call, ["ICS4U", "2", "--build-only", "--image", "x"],
                 rebuild, "building", "build"),
                ("preview.sh", build_call, ["ICS4U", "2", "--for-deploy", "--build-only", "--image", "x"],
                 build_leg, "another", "build"),
                ("deploy.sh", deploy_call, ["ICS4U", "2"], build_leg, "another", "deploy"),
                ("deploy.sh", deploy_call, ["ICS4U", "2"], rebuild, "building", "deploy")):
            with self.subTest(launcher=launcher, arguments=arguments, who=who):
                refused = self.run_the_real_prefix(launcher, call, arguments, working=True,
                                                   rows=rows, cwd={"700": "here"})
                self.assertEqual(refused.returncode, 1, refused.stdout + refused.stderr)
                self.assertNotIn("REACHED", refused.stdout)
                for line in expected_lines(who, leg, "ICS4U", "2"):
                    self.assertIn(line, refused.stdout.splitlines())
                allowed = self.run_the_real_prefix(launcher, call, arguments, working=False)
                self.assertEqual(allowed.returncode, 0, allowed.stdout + allowed.stderr)
                self.assertIn("REACHED", allowed.stdout)

@unittest.skipUnless(HAS_BASH, "needs a bash that can run a program")
class TheForDeployFlag(unittest.TestCase):
    """#729: `--for-deploy` names a deploy's build in the process table and
    changes nothing the build does, so it is refused on a serving run, where it
    could mean nothing, and accepted beside --build-only in either order. The
    REAL preview.sh is run up to just after its argument checks."""

    STOP_AT = "# Validate course and section\n"

    def run_preview(self, arguments: list) -> subprocess.CompletedProcess:
        text = launcher_text("preview.sh")
        self.assertEqual(text.count(self.STOP_AT), 1)
        prefix = text[:text.index(self.STOP_AT)] + 'echo "REACHED BUILD_ONLY=$BUILD_ONLY FOR_DEPLOY=$FOR_DEPLOY"\nexit 0\n'
        with tempfile.TemporaryDirectory() as folder:
            here = Path(folder)
            (here / "preview.sh").write_text(prefix, encoding="utf-8")
            environment = {"HOME": str(here), "PATH": "/usr/bin:/bin"}
            return subprocess.run([BASH, "./preview.sh"] + arguments + ["--image", "x"], cwd=here,
                                  env=environment, capture_output=True, text=True, timeout=60)

    def test_alone_it_is_refused_in_words(self):
        result = self.run_preview(["ICS4U", "2", "--for-deploy"])
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("❌ --for-deploy goes with --build-only.", result.stdout.splitlines())
        self.assertNotIn("REACHED", result.stdout)
        self.assertNotIn("Unknown option", result.stdout)

    def test_beside_build_only_it_is_accepted_in_either_order(self):
        for arguments in (["ICS4U", "2", "--build-only", "--for-deploy"],
                          ["ICS4U", "2", "--for-deploy", "--build-only", "--non-interactive"]):
            with self.subTest(arguments=arguments):
                result = self.run_preview(arguments)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("REACHED BUILD_ONLY=--build-only FOR_DEPLOY=--for-deploy", result.stdout)

    def test_a_serving_run_is_not_touched_by_an_inherited_variable(self):
        # FOR_DEPLOY is set to empty before the parser, so a variable of that
        # name in the environment cannot make a serving preview refuse.
        text = launcher_text("preview.sh")
        self.assertLess(text.index('FOR_DEPLOY=""'), text.index("    --for-deploy)"))


if __name__ == "__main__":
    unittest.main(verbosity=1)
