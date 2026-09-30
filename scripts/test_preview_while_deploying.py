#!/usr/bin/env python3
"""
A preview of a section cannot start while that same section is being
deployed, whoever started the deploy (GitHub #381, Russell's decision 4 on
#378). The rule and its cases are data:
`contracts/shared-rules.json` -> `previewWhileItsSectionDeploys`.

This file runs `launcherCases` against the REAL guard, cut out of preview.sh
between its markers — not retyped — under `/bin/bash` (3.2 on a Mac, the one
a teacher's launchers run under). `ps` and `lsof` are small pretend programs
put first on PATH, answering from files in a scratch folder. The trail is
written under a scratch HOME. Nothing is started and nothing is published.

It also checks, as text, the three things a behaviour test cannot see: that
preview.sh asks on SERVING runs only, that it asks before anything is changed,
and that the look trusts no remembered process id.

**Windows.** Skipped where there is no bash that can run a program, the same
rule as the launcher tests beside it: Windows' preview is preview.ps1, which
owes the same guard (the contract's appliesOnWhy).

Pure stdlib. Run with:

    python3 scripts/test_preview_while_deploying.py
"""

import hashlib
import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True

from test_deploy_sh_questions import HAS_BASH, REPOSITORY_ROOT

GUARD_START = "# >>> PREVIEW WHILE DEPLOYING GUARD >>>"
GUARD_END = "# <<< PREVIEW WHILE DEPLOYING GUARD <<<"
BASH = "/bin/bash" if Path("/bin/bash").exists() else "bash"
THIS_RUNS_PARENT = 4999


def the_rule() -> dict:
    rules = json.loads((REPOSITORY_ROOT / "contracts" / "shared-rules.json").read_text(encoding="utf-8"))
    return rules["previewWhileItsSectionDeploys"]


def the_trail_entry() -> dict:
    rules = json.loads((REPOSITORY_ROOT / "contracts" / "shared-rules.json").read_text(encoding="utf-8"))
    for entry in rules["activityTrail"]["mustRecord"]:
        if entry["event"] == "build declined, course busy elsewhere":
            return entry
    raise AssertionError("the contract no longer has a 'build declined, course busy elsewhere' event")


def preview_text() -> str:
    return (REPOSITORY_ROOT / "preview.sh").read_text(encoding="utf-8")


def the_guard() -> str:
    text = preview_text()
    begin = text.find(GUARD_START)
    finish = text.find(GUARD_END)
    if begin < 0 or finish < 0:
        raise AssertionError("the PREVIEW WHILE DEPLOYING GUARD markers are missing from preview.sh")
    return text[begin:finish + len(GUARD_END)]


def function_named(text: str, name: str) -> str:
    """One top-level function of a launcher, from its first line to its closing brace."""
    begin = text.find(f"\n{name}() {{")
    if begin < 0:
        raise AssertionError(f"{name} is missing")
    finish = text.find("\n}\n", begin)
    return text[begin + 1:finish + 3]


def folder_id(path: str) -> str:
    """The id preview.sh and BuildOutputLocation.folderIdentifier give a folder."""
    return hashlib.sha256((path + "\n").encode("utf-8")).hexdigest()[:8]


# ---- The pretend programs ---------------------------------------------
# `ps -Ao pid=,ppid=,args=`: the case's rows, then this run and its parent.
# THIS_RUN is the guard's own $$, handed in by the harness, so the family
# rule is exercised against the pid the real code compares.
FAKE_PS = r"""#!/bin/bash
echo "ps $*" >> "$FAKE/calls"
if [ -f "$FAKE/ps_fails" ]; then
  echo "ps: something went wrong" >&2
  exit 1
fi
cat "$FAKE/table"
printf '%s %s %s\n' "$THIS_RUN" "4999" "/bin/bash ./preview.sh $PREVIEWED"
printf '%s %s %s\n' "4999" "1" "$(cat "$FAKE/parent_args")"
exit 0
"""

# `lsof -a -p PID -d cwd -Fn`: the working directory written for that pid,
# or nothing (and exit 1) when there is none — as lsof does for a process it
# may not ask about.
FAKE_LSOF = r"""#!/bin/bash
echo "lsof $*" >> "$FAKE/calls"
pid=""
while [ $# -gt 0 ]; do
  if [ "$1" = "-p" ]; then pid="$2"; shift; fi
  shift
done
if [ -f "$FAKE/cwd/$pid" ]; then
  printf 'p%s\nfcwd\nn%s\n' "$pid" "$(cat "$FAKE/cwd/$pid")"
  exit 0
fi
exit 1
"""


class PretendMac:
    """A scratch folder holding the pretend programs and what they answer."""

    def __init__(self, scratch: Path):
        self.scratch = scratch
        self.fake = scratch / "fake"
        self.bin = scratch / "bin"
        self.home = scratch / "home"
        self.here = scratch / "here"
        self.elsewhere = scratch / "elsewhere"
        for folder in (self.fake, self.bin, self.home, self.here, self.elsewhere, self.fake / "cwd"):
            folder.mkdir(parents=True, exist_ok=True)
        for name, body in (("ps", FAKE_PS), ("lsof", FAKE_LSOF)):
            program = self.bin / name
            program.write_text(body, encoding="utf-8")
            program.chmod(program.stat().st_mode | stat.S_IEXEC)
        # The folder as /bin/pwd -P names it: /var is /private/var on a Mac.
        self.here_path = subprocess.run(["/bin/pwd", "-P"], cwd=self.here, capture_output=True,
                                        text=True).stdout.strip()
        self.elsewhere_path = subprocess.run(["/bin/pwd", "-P"], cwd=self.elsewhere, capture_output=True,
                                             text=True).stdout.strip()

    def fill(self, text: str) -> str:
        return (text.replace("{here}", self.here_path)
                .replace("{hereID}", folder_id(self.here_path))
                .replace("{elsewhereID}", folder_id(self.elsewhere_path)))

    def lay_out(self, case: dict) -> None:
        rows = []
        for pid, parent, args in case.get("processes", []):
            rows.append(f"{pid} {parent} {self.fill(args)}")
        (self.fake / "table").write_text("".join(row + "\n" for row in rows), encoding="utf-8")
        (self.fake / "parent_args").write_text(self.fill(case.get("parentArgs", "-bash")), encoding="utf-8")
        if case.get("psFails"):
            (self.fake / "ps_fails").write_text("", encoding="utf-8")
        for pid, where in case.get("cwd", {}).items():
            path = self.here_path if where == "here" else self.elsewhere_path
            (self.fake / "cwd" / str(pid)).write_text(path, encoding="utf-8")

    def refuse(self, course: str, section: str) -> subprocess.CompletedProcess:
        """Runs the real guard as preview.sh's serving run would, for course/section."""
        text = preview_text()
        script = "\n".join([
            "set -uo pipefail",
            function_named(text, "note_on_the_trail"),
            the_guard(),
            "export THIS_RUN=$$",
            # preview.sh upper-cases the course before anything else reads it.
            f"COURSE={course.upper()!r}",
            f"SECTION={section!r}",
            "refuse_a_preview_while_its_section_deploys",
            "echo ALLOWED",
        ])
        environment = dict(os.environ)
        environment["PATH"] = f"{self.bin}:{environment.get('PATH', '/usr/bin:/bin')}"
        environment["FAKE"] = str(self.fake)
        environment["HOME"] = str(self.home)
        environment["PREVIEWED"] = f"{course} {section}"
        return subprocess.run([BASH, "-c", script], cwd=self.here, env=environment,
                              capture_output=True, text=True, timeout=30)

    def trail(self) -> list:
        path = self.home / "Library" / "Logs" / "Plantoir" / "activity.txt"
        if not path.exists():
            return []
        return path.read_text(encoding="utf-8").splitlines()


def the_launcher_sentence(course: str, section: str) -> list:
    lines = []
    for line in the_rule()["sentences"]["launcher"]:
        lines.append(line.replace("{course}", course).replace("{section}", section))
    return lines


@unittest.skipUnless(HAS_BASH, "needs a bash that can run a program")
class TheLauncherCases(unittest.TestCase):
    """Every launcherCases case, against the real guard."""

    def run_case(self, case: dict) -> tuple:
        with tempfile.TemporaryDirectory() as folder:
            mac = PretendMac(Path(folder))
            mac.lay_out(case)
            course = case.get("course", "ICS4U")
            section = case.get("section", "2")
            result = mac.refuse(course, section)
            return result, mac.trail(), course, section

    def test_every_case(self):
        for case in the_rule()["launcherCases"]:
            with self.subTest(case["name"]):
                result, trail, course, section = self.run_case(case)
                shown_course = course.upper()
                if case["expect"] == "refused":
                    self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                    self.assertNotIn("ALLOWED", result.stdout)
                    for line in the_launcher_sentence(shown_course, section):
                        self.assertIn(line, result.stdout.splitlines())
                    wanted = (the_trail_entry()["launcherLineWhenItsSectionIsBeingDeployed"]
                              .replace("{course}", shown_course).replace("{section}", section))
                    self.assertEqual(len(trail), 1, trail)
                    self.assertTrue(trail[0].endswith(" · " + wanted), trail[0])
                else:
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertIn("ALLOWED", result.stdout)
                    self.assertEqual(trail, [], "an allowed preview writes nothing on the trail")

    def test_the_cases_cover_every_kind_of_deployer(self):
        names = " ".join(case["name"] for case in the_rule()["launcherCases"])
        for words in ("command line", "set for later", "unreadable", "ANOTHER section", "--build-only"):
            self.assertIn(words, names)


class TheCallSite(unittest.TestCase):
    """What a behaviour test cannot see: when and where preview.sh asks."""

    def test_the_guard_is_called_on_serving_runs_only(self):
        text = preview_text()
        after = text[text.find(GUARD_END):]
        self.assertIn('if [[ -z "$BUILD_ONLY" && -z "${STOP_MODE:-}" ]]; then\n'
                      '  refuse_a_preview_while_its_section_deploys\nfi', after)

    def test_the_guard_asks_before_anything_is_changed(self):
        text = preview_text()
        call = text.find("\n  refuse_a_preview_while_its_section_deploys\n")
        self.assertGreater(call, 0)
        for first_change in ('link_course_build_output "$COURSE"', "# -------------------- Stop mode",
                             "ensure_container_runtime\n", "# >>> PREVIEW PORT BLOCK >>>",
                             'echo "🚀 Getting this folder\'s website builder ready…"'):
            place = text.find(first_change)
            self.assertGreater(place, 0, first_change)
            self.assertLess(call, place, f"the guard must run before {first_change!r}")

    def test_the_look_trusts_no_remembered_process_id(self):
        guard = the_guard()
        for code_line in guard.splitlines():
            if code_line.lstrip().startswith("#"):
                continue
            self.assertNotIn("kill -0", code_line)
            self.assertNotIn(".lease", code_line)

    def test_only_preview_sh_has_the_guard(self):
        for launcher in ("setup.sh", "deploy.sh"):
            self.assertNotIn(GUARD_START, (REPOSITORY_ROOT / launcher).read_text(encoding="utf-8"))

    def test_the_sentence_names_no_machinery(self):
        for line in the_rule()["sentences"]["launcher"]:
            for word in ("workspace", "container", "script", "Docker", "docker"):
                self.assertNotIn(word, line)


if __name__ == "__main__":
    unittest.main(verbosity=1)
