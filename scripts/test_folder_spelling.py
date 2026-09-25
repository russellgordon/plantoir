#!/usr/bin/env python3
"""
One working folder, one spelling (GitHub #189).

The same folder can reach a launcher spelled several ways — in the wrong case,
through a link, as /tmp for /private/tmp, by the /System/Volumes/Data
firmlink, or with an accented letter in the other Unicode form — and until
#189 each spelling named its own workspace and its own builds folder, because
bash's built-in `pwd -P` keeps the spelling it was handed. Each launcher now
moves into `$(/bin/pwd -P)`, the disk's own spelling, straight after its first
`cd`, and a shared function clears away the second copy an old spelling left.

This runs the REAL lines, cut out of the launchers rather than retyped:

- the one-spelling stanza, from a scratch launcher reached by every spelling
  this Mac can make, so the id, the container name and the courses folder the
  container mounts are one answer whichever spelling ran it;
- `clear_away_this_folders_other_spelling`, from the PREVIEW PORT BLOCK, against
  a pretend `docker` — nothing is started or removed but scratch folders;
- the sentences, against contracts/shared-rules.json ->
  buildOutputLocation.aSecondSpellingIsClearedAway and the trail line.

Pure stdlib. Skipped where there is no bash that can run a program (Windows),
like the launcher tests beside it. Run with:

    python3 scripts/test_folder_spelling.py
"""

import json
import os
import re
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True

from test_deploy_sh_questions import HAS_BASH, REPOSITORY_ROOT

LAUNCHERS = ["setup.sh", "preview.sh", "deploy.sh"]
FIRST_CD = 'cd "$(dirname "$0")"\n'
STANZA_START = "# ---- One spelling of this folder (GitHub #189)"
STANZA_END = 'cd "$(/bin/pwd -P)"\n'
BLOCK_START = "# >>> PREVIEW PORT BLOCK >>>"
BLOCK_END = "# <<< PREVIEW PORT BLOCK <<<"
SWEEP = "clear_away_this_folders_other_spelling"
BASH = "/bin/bash" if Path("/bin/bash").exists() else "bash"


def launcher_text(launcher: str) -> str:
    return (REPOSITORY_ROOT / launcher).read_text(encoding="utf-8")


def the_rule() -> dict:
    rules = json.loads((REPOSITORY_ROOT / "contracts" / "shared-rules.json").read_text(encoding="utf-8"))
    return rules["buildOutputLocation"]["aSecondSpellingIsClearedAway"]


def said(what: str) -> str:
    """The console sentence for one of whatWasCleared's variants."""
    rule = the_rule()
    return rule["sayWhenCleared"].replace("{what}", rule["whatWasCleared"][what])


def the_trail_line() -> str:
    rules = json.loads((REPOSITORY_ROOT / "contracts" / "shared-rules.json").read_text(encoding="utf-8"))
    for entry in rules["activityTrail"]["mustRecord"]:
        if entry["event"] == "built site moved out of the working folder":
            return entry["launcherLineWhenASecondCopyIsClearedAway"]
    raise AssertionError("the contract no longer has a 'built site moved out of the working folder' event")


def the_stanza(text: str) -> str:
    begin = text.find(STANZA_START)
    if begin < 0:
        raise AssertionError("no one-spelling stanza")
    finish = text.find(STANZA_END, begin)
    return text[begin:finish + len(STANZA_END)]


def function_named(text: str, name: str) -> str:
    match = re.search(r"^" + re.escape(name) + r"\(\) \{\n.*?^\}\n", text, flags=re.MULTILINE | re.DOTALL)
    if match is None:
        raise AssertionError(f"no function called {name}")
    return match.group(0)


def workdir_id_line(text: str) -> str:
    for line in text.splitlines():
        if line.startswith("WORKDIR_ID="):
            return line
    raise AssertionError("no WORKDIR_ID= line")


def host_courses_line(text: str) -> str:
    for line in text.splitlines():
        if line.startswith("HOST_COURSES="):
            return line.split("#")[0].rstrip()
    raise AssertionError("no HOST_COURSES= line")


# ======================================================================
# Text: the three launchers carry the same lines, in the right place.
# ======================================================================
class TheLaunchersMoveIntoOneSpelling(unittest.TestCase):

    def test_the_stanza_is_the_same_in_all_three(self):
        first = the_stanza(launcher_text("setup.sh"))
        for launcher in ["preview.sh", "deploy.sh"]:
            self.assertEqual(first, the_stanza(launcher_text(launcher)),
                             f"{launcher}'s one-spelling lines have drifted from setup.sh's")

    def test_it_comes_straight_after_the_first_cd(self):
        """Before it, nothing may read the folder's path: everything after it
        — the id, the builds folder, the courses folder the workspace mounts —
        has to come from the one spelling."""
        for launcher in LAUNCHERS:
            text = launcher_text(launcher)
            first_cd = text.index(FIRST_CD)
            after = text[first_cd + len(FIRST_CD):]
            self.assertTrue(after.startswith("\n" + STANZA_START),
                            f"{launcher}: the one-spelling lines do not follow its first cd")
            self.assertNotIn("pwd", text[:first_cd], launcher)

    def test_the_id_and_the_note_ask_the_disk(self):
        for launcher in LAUNCHERS:
            text = launcher_text(launcher)
            self.assertEqual(workdir_id_line(text), 'WORKDIR_ID="$(/bin/pwd -P | shasum -a 256 | cut -c1-8)"', launcher)
            self.assertIn('printf \'%s\\n\' "$(/bin/pwd -P)" > "$BUILD_ROOT/working-folder.txt"', text, launcher)

    def test_the_sweep_lives_in_the_shared_block_and_is_called_once(self):
        for launcher in LAUNCHERS:
            text = launcher_text(launcher)
            begin = text.index(BLOCK_START)
            finish = text.index(BLOCK_END)
            block = text[begin:finish]
            self.assertIn(f"\n{SWEEP}() {{\n", block, launcher)
            outside = text[:begin] + text[finish:]
            calls = re.findall(r"^" + SWEEP + r"$", outside, flags=re.MULTILINE)
            self.assertEqual(len(calls), 1, f"{launcher} should call the sweep exactly once")
            self.assertIn(SWEEP + "\nif docker ps -a --format '{{.Names}}' | grep -Eq \"^${CONTAINER_NAME}$\"; then\n",
                          outside, f"{launcher}: the sweep is not called just before the workspace is looked at")

    def test_nothing_is_removed_by_force(self):
        body = function_named(launcher_text("setup.sh"), SWEEP)
        self.assertNotRegex(body, r"docker rm -f|docker rm --force|docker stop")

    def test_the_sentences_are_the_contracts(self):
        body = function_named(launcher_text("setup.sh"), SWEEP)
        rule = the_rule()
        self.assertIn('echo "' + rule["sayWhenCleared"].replace("{what}", "${what}") + '"', body)
        for variant in ["workspace", "builtWebsites", "both"]:
            self.assertIn(f'what="{rule["whatWasCleared"][variant]}"', body, variant)
        for line in rule["sayWhenStillRunning"]:
            self.assertIn('echo "' + line.replace("{workspace}", "${old_name}") + '"', body)
        line = the_trail_line().replace("{course}/{section}", "${WORKSPACE_TRAIL_PLACE:-setup}").replace("{what}", "${what}")
        self.assertIn(f'note_on_the_trail "{line}"', body)

    def test_the_sentences_name_no_machinery(self):
        rule = the_rule()
        lines = [rule["sayWhenCleared"], the_trail_line()]
        lines.extend(rule["whatWasCleared"].values())
        lines.extend(rule["sayWhenStillRunning"])
        for line in lines:
            words = set(re.findall(r"[a-z]+", line.replace("{workspace}", "").lower()))
            for forbidden in ["docker", "container", "toolchain", "script", "symlink", "vault", "hash"]:
                self.assertNotIn(forbidden, words, line)


# ======================================================================
# Behaviour: the real stanza, reached by every spelling this Mac can make.
# ======================================================================
@unittest.skipUnless(HAS_BASH and sys.platform == "darwin", "needs the Mac's /bin/bash and /bin/pwd")
class EverySpellingNamesOneFolder(unittest.TestCase):

    def setUp(self):
        self.scratch = Path(tempfile.mkdtemp(prefix="spelling-"))
        # mkdtemp gives /var/folders/…, which is itself a link to /private/var.
        self.addCleanup(lambda: subprocess.run(["rm", "-rf", str(self.scratch)]))

    def probe_in(self, folder: bytes) -> None:
        text = launcher_text("preview.sh")
        program = "\n".join([
            "#!/bin/bash",
            "set -euo pipefail",
            FIRST_CD.rstrip("\n"),
            the_stanza(text),
            workdir_id_line(text),
            host_courses_line(text),
            'printf "%s\\n%s\\n%s\\n" "$WORKDIR_ID" "$FOLDER_ID_AS_HANDED" "$HOST_COURSES"',
        ]) + "\n"
        path = folder + b"/probe.sh"
        with open(path, "wb") as handle:
            handle.write(program.encode("utf-8"))
        os.chmod(path, 0o755)

    def run_by(self, spelling: bytes) -> list:
        result = subprocess.run([BASH, spelling + b"/probe.sh"], capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr.decode("utf-8", "replace"))
        return result.stdout.decode("utf-8", "surrogateescape").splitlines()

    def spellings_of(self, folder: bytes, name: bytes) -> dict:
        """Every way this test can reach one folder, by what it is."""
        parent = os.path.dirname(folder)
        spellings = {"as the disk spells it": folder}
        upper = parent + b"/" + name.upper()
        if upper != folder and os.path.isdir(upper):
            spellings["in the wrong case"] = upper
        link = os.fsencode(str(self.scratch)) + b"/link-" + name
        os.symlink(folder, link)
        spellings["through a link"] = link
        if folder.startswith(b"/private/"):
            spellings["without /private"] = folder[len(b"/private"):]
            firmlink = b"/System/Volumes/Data" + folder
            if os.path.isdir(firmlink):
                spellings["by the firmlink"] = firmlink
        return spellings

    def check_one_folder(self, folder: bytes, name: bytes, other_form: bytes = None) -> dict:
        self.probe_in(folder)
        spellings = self.spellings_of(folder, name)
        if other_form is not None:
            spellings["with the name in the other Unicode form"] = os.path.dirname(folder) + b"/" + other_form
        answers = {}
        for what, spelling in spellings.items():
            answers[what] = self.run_by(spelling)
        disk = answers["as the disk spells it"]
        disk_spelling = subprocess.run(["/bin/pwd", "-P"], cwd=folder, capture_output=True).stdout.rstrip(b"\n")
        self.assertEqual(disk[2].encode("utf-8", "surrogateescape"), disk_spelling + b"/courses")
        for what, answer in answers.items():
            self.assertEqual(answer[0], disk[0], f"{what}: a different folder id")
            self.assertEqual(answer[2], disk[2], f"{what}: the workspace would mount another spelling")
        self.assertGreaterEqual(len(answers), 4, f"only {sorted(answers)} could be made here")
        return answers

    def test_an_ordinary_folder(self):
        folder = os.fsencode(os.path.realpath(self.scratch)) + b"/Plantoir Courses"
        os.mkdir(folder)
        answers = self.check_one_folder(folder, b"Plantoir Courses")
        if "in the wrong case" in answers:
            self.assertNotEqual(answers["in the wrong case"][1], answers["in the wrong case"][0],
                                "bash's own pwd -P should still see the typed spelling — else this proves nothing")

    def test_an_accented_name_stored_as_one_character(self):
        """É stored as one character (Terminal, a zip, a Windows PC) and
        handed over as E + accent, which is what the app always hands a
        launcher."""
        composed = "Écoles".encode("utf-8")
        decomposed = "Écoles".encode("utf-8")
        folder = os.fsencode(os.path.realpath(self.scratch)) + b"/" + composed
        os.mkdir(folder)
        if not os.path.isdir(os.path.dirname(folder) + b"/" + decomposed):
            self.skipTest("this disk tells the two Unicode forms apart")
        answers = self.check_one_folder(folder, composed, decomposed)
        other = answers["with the name in the other Unicode form"]
        self.assertNotEqual(other[1], other[0], "the old spelling-keeping id should differ, or this proves nothing")

    def test_an_accented_name_stored_as_letter_and_accent(self):
        """The way Finder stores it, reached as one character."""
        composed = "Français".encode("utf-8")
        decomposed = "Français".encode("utf-8")
        folder = os.fsencode(os.path.realpath(self.scratch)) + b"/" + decomposed
        os.mkdir(folder)
        if not os.path.isdir(os.path.dirname(folder) + b"/" + composed):
            self.skipTest("this disk tells the two Unicode forms apart")
        self.check_one_folder(folder, decomposed, composed)


# ======================================================================
# Behaviour: the sweep, against a pretend docker.
# ======================================================================
FAKE_DOCKER = r"""#!/bin/bash
echo "docker $*" >> "$FAKE/calls"
if [ -f "$FAKE/unreachable" ]; then echo "Cannot connect to the Docker daemon" >&2; exit 1; fi
case "$1" in
  ps)
    if [ "${2:-}" = "-a" ]; then cat "$FAKE/workspaces" 2>/dev/null; else cat "$FAKE/running" 2>/dev/null; fi
    exit 0 ;;
  inspect)
    if [ -f "$FAKE/inspect_fails" ]; then exit 1; fi
    shift 2
    for name in "$@"; do cat "$FAKE/mounts_$name" 2>/dev/null; done
    exit 0 ;;
  rm)
    if [ "${2:-}" = "-f" ]; then echo "forced" >> "$FAKE/forced"; fi
    if [ -f "$FAKE/rm_refuses" ]; then echo "Error: container is running" >&2; exit 1; fi
    grep -Fxv -- "$2" "$FAKE/workspaces" > "$FAKE/left" || true
    mv "$FAKE/left" "$FAKE/workspaces"
    exit 0 ;;
esac
echo "unexpected docker $*" >&2
exit 99
"""

OLD_ID = "0ddba115"
NEW_ID = "00c0ffee"


@unittest.skipUnless(HAS_BASH, "no bash here that can run a program")
class TheSecondCopyIsClearedAway(unittest.TestCase):

    def setUp(self):
        self.scratch = Path(os.path.realpath(tempfile.mkdtemp(prefix="sweep-")))
        self.addCleanup(lambda: subprocess.run(["rm", "-rf", str(self.scratch)]))
        self.fake = self.scratch / "fake"
        self.bin = self.scratch / "bin"
        self.home = self.scratch / "home"
        self.work = self.scratch / "work"
        for folder in (self.fake, self.bin, self.home, self.work / "courses" / "ICS4U"):
            folder.mkdir(parents=True)
        (self.work / "courses" / "ICS4U" / "notes.md").write_text("mine", encoding="utf-8")
        docker = self.bin / "docker"
        docker.write_text(FAKE_DOCKER, encoding="utf-8")
        docker.chmod(docker.stat().st_mode | stat.S_IEXEC)
        self.builds_root = self.home / "Library" / "Application Support" / "Plantoir" / "builds"
        self.old_builds = self.builds_root / OLD_ID
        self.new_builds = self.builds_root / NEW_ID
        self.new_builds.mkdir(parents=True)

    def an_old_builds_folder(self, serving: Path = None) -> None:
        (self.old_builds / "ICS4U").mkdir(parents=True)
        (self.old_builds / "ICS4U" / "index.html").write_text("built", encoding="utf-8")
        (self.old_builds / "working-folder.txt").write_text(str(serving or self.work) + "\n", encoding="utf-8")

    def workspaces(self, everything: list, running: list = None) -> None:
        (self.fake / "workspaces").write_text("".join(n + "\n" for n in everything), encoding="utf-8")
        (self.fake / "running").write_text("".join(n + "\n" for n in (running or [])), encoding="utf-8")

    def mounts(self, name: str, sources: list) -> None:
        (self.fake / ("mounts_" + name)).write_text("".join(s + "\n" for s in sources), encoding="utf-8")

    def sweep(self, launcher: str = "preview.sh", handed: str = OLD_ID) -> str:
        text = launcher_text(launcher)
        place = ""
        for line in text.splitlines():
            if line.startswith("WORKSPACE_TRAIL_PLACE="):
                place = line
        program = "\n".join([
            "set -euo pipefail",
            'COURSE="ICS4U"; SECTION="2"; COURSE_CODE="ICS4U"; SECTION_NUM="2"',
            f'FOLDER_ID_AS_HANDED="{handed}"',
            f'WORKDIR_ID="{NEW_ID}"',
            'BUILD_ROOT="${HOME%/}/Library/Application Support/Plantoir/builds/${WORKDIR_ID}"',
            function_named(text, "note_on_the_trail"),
            function_named(text, SWEEP),
            place,
            SWEEP,
            "echo carried-on",
        ]) + "\n"
        environment = {"HOME": str(self.home), "FAKE": str(self.fake), "PATH": f"{self.bin}:/usr/bin:/bin"}
        result = subprocess.run([BASH, "-c", program], capture_output=True, timeout=30, env=environment, cwd=self.work)
        output = result.stdout.decode("utf-8", "replace") + result.stderr.decode("utf-8", "replace")
        self.assertEqual(result.returncode, 0, output)
        self.assertIn("carried-on", output, "the sweep must never stop the run")
        return output

    def calls(self) -> list:
        path = self.fake / "calls"
        return path.read_text(encoding="utf-8").splitlines() if path.exists() else []

    def trail(self) -> list:
        path = self.home / "Library" / "Logs" / "Plantoir" / "activity.txt"
        return path.read_text(encoding="utf-8").splitlines() if path.exists() else []

    def assert_courses_untouched(self):
        self.assertEqual((self.work / "courses" / "ICS4U" / "notes.md").read_text(encoding="utf-8"), "mine")
        self.assertTrue(self.new_builds.is_dir(), "this folder's own builds folder was touched")

    def test_the_disks_own_spelling_asks_nothing(self):
        self.an_old_builds_folder()
        self.sweep(handed=NEW_ID)
        self.assertEqual(self.calls(), [])
        self.assertTrue(self.old_builds.is_dir())

    def test_a_stopped_copy_and_its_builds_are_cleared_away(self):
        old = "teaching-quartz-" + OLD_ID
        self.workspaces([old, "teaching-quartz-" + NEW_ID, "supabase_db"])
        self.mounts(old, [str(self.old_builds), str(self.work / "courses")])
        self.mounts("teaching-quartz-" + NEW_ID, [str(self.new_builds)])
        self.an_old_builds_folder()
        for launcher in LAUNCHERS:
            with self.subTest(launcher=launcher):
                if not self.old_builds.exists():
                    self.workspaces([old, "teaching-quartz-" + NEW_ID, "supabase_db"])
                    self.an_old_builds_folder()
                output = self.sweep(launcher)
                self.assertIn(f"docker rm {old}", self.calls())
                self.assertFalse((self.fake / "forced").exists())
                self.assertFalse(self.old_builds.exists())
                self.assertIn(said("both"), output)
                place = "setup" if launcher == "setup.sh" else "ICS4U/2"
                expected = the_trail_line().replace("{course}/{section}", place).replace(
                    "{what}", the_rule()["whatWasCleared"]["both"])
                self.assertTrue(self.trail()[-1].endswith(" · " + expected), self.trail())
                self.assert_courses_untouched()

    def test_a_running_copy_is_left_alone_and_named(self):
        old = "teaching-quartz-" + OLD_ID
        self.workspaces([old], running=[old])
        self.mounts(old, [str(self.old_builds)])
        self.an_old_builds_folder()
        output = self.sweep()
        self.assertNotIn(f"docker rm {old}", self.calls())
        self.assertTrue(self.old_builds.is_dir())
        self.assertIn(the_rule()["sayWhenStillRunning"][0].replace("{workspace}", old), output)
        self.assertNotIn("🧹", output)
        self.assertEqual(self.trail(), [])

    def test_nothing_is_removed_when_docker_cannot_be_asked(self):
        (self.fake / "unreachable").write_text("", encoding="utf-8")
        self.an_old_builds_folder()
        output = self.sweep()
        self.assertTrue(self.old_builds.is_dir())
        self.assertNotIn("🧹", output)
        self.assertEqual(self.trail(), [])

    def test_a_refused_removal_stops_the_sweep(self):
        """Started a moment ago by an older launcher: its builds folder is in use."""
        old = "teaching-quartz-" + OLD_ID
        self.workspaces([old])
        (self.fake / "rm_refuses").write_text("", encoding="utf-8")
        self.an_old_builds_folder()
        self.sweep()
        self.assertTrue(self.old_builds.is_dir())
        self.assertEqual(self.trail(), [])

    def test_with_no_copy_left_the_builds_folder_alone_is_cleared(self):
        self.workspaces(["teaching-quartz-" + NEW_ID])
        self.mounts("teaching-quartz-" + NEW_ID, [str(self.new_builds)])
        self.an_old_builds_folder()
        output = self.sweep()
        self.assertFalse(self.old_builds.exists())
        self.assertIn(said("builtWebsites"), output)
        self.assertTrue(self.trail()[-1].endswith(the_rule()["whatWasCleared"]["builtWebsites"]
                                                  + ", left under another spelling of its name"), self.trail())
        self.assert_courses_untouched()

    def test_a_builds_folder_another_workspace_mounts_is_kept(self):
        self.workspaces(["teaching-quartz-5eed5eed"])
        self.mounts("teaching-quartz-5eed5eed", [str(self.old_builds)])
        self.an_old_builds_folder()
        self.sweep()
        self.assertTrue(self.old_builds.is_dir())
        self.assertEqual(self.trail(), [])

    def test_when_only_the_workspace_goes_the_sentence_says_so(self):
        """Review L3: the sentence names only what was removed."""
        old = "teaching-quartz-" + OLD_ID
        self.workspaces([old, "teaching-quartz-5eed5eed"])
        self.mounts("teaching-quartz-5eed5eed", [str(self.old_builds)])
        self.an_old_builds_folder()
        output = self.sweep()
        self.assertIn(f"docker rm {old}", self.calls())
        self.assertTrue(self.old_builds.is_dir())
        self.assertIn(said("workspace"), output)
        self.assertNotIn(said("both"), output)
        self.assertTrue(self.trail()[-1].endswith(the_rule()["whatWasCleared"]["workspace"]
                                                  + ", left under another spelling of its name"), self.trail())

    def test_an_empty_note_names_no_folder(self):
        """Review L1: `cd ""` stays where it is, so an empty note would read
        as this folder."""
        self.workspaces([])
        (self.old_builds / "ICS4U").mkdir(parents=True)
        (self.old_builds / "working-folder.txt").write_text("", encoding="utf-8")
        output = self.sweep()
        self.assertTrue(self.old_builds.is_dir())
        self.assertNotIn("🧹", output)
        self.assertEqual(self.trail(), [])

    def test_a_mount_question_docker_does_not_answer_keeps_it(self):
        self.workspaces(["teaching-quartz-" + NEW_ID])
        (self.fake / "inspect_fails").write_text("", encoding="utf-8")
        self.an_old_builds_folder()
        self.sweep()
        self.assertTrue(self.old_builds.is_dir())

    def test_a_builds_folder_serving_another_folder_is_kept(self):
        elsewhere = self.scratch / "another working folder"
        elsewhere.mkdir()
        self.workspaces([])
        self.an_old_builds_folder(serving=elsewhere)
        self.sweep()
        self.assertTrue(self.old_builds.is_dir())

    def test_a_builds_folder_with_no_note_is_kept(self):
        self.workspaces([])
        (self.old_builds / "ICS4U").mkdir(parents=True)
        self.sweep()
        self.assertTrue(self.old_builds.is_dir())

    @unittest.skipUnless(sys.platform == "darwin", "the Mac's case-blind disk")
    def test_a_note_in_another_spelling_of_this_folder_is_this_folder(self):
        """An old launcher wrote the note in the spelling it was HANDED."""
        wrong_case = self.work.parent / self.work.name.upper()
        if not wrong_case.is_dir():
            self.skipTest("this disk tells upper and lower case apart")
        self.workspaces([])
        self.an_old_builds_folder(serving=wrong_case)
        self.sweep()
        self.assertFalse(self.old_builds.exists())

    def test_an_id_that_is_not_an_id_is_ignored(self):
        """Never let a stray value aim a removal at the builds root itself."""
        self.workspaces([])
        self.an_old_builds_folder()
        for handed in ["", "..", "../../x", "0ddba11", "0DDBA115"]:
            self.sweep(handed=handed)
        self.assertTrue(self.old_builds.is_dir())
        self.assertTrue(self.builds_root.is_dir())
        self.assertEqual(self.calls(), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
