#!/usr/bin/env python3
"""
A publish to a folder on this computer lands where it says it did, or says it
did not — GitHub issue #227.

`deploy.sh --to-folder` publishes with `rsync` on the HOST and exits before
any container is started, so this runs the real launcher, from a COPY in a
scratch working folder, with no Docker, no network and no credentials. The
scratch working folder's own name has a colon in it (`Comm Tech 26:27`),
because that is the name macOS gives a folder a teacher typed as "26/27".

Two things are pinned, and each was measured failing on the launcher before
the fix (see documentation/07-deployment.md → "A relative folder, and a copy
that did not finish"):

  * **Where a relative folder lands** — `shared-rules.json` →
    `folderPublishTarget.cases`. rsync reads a colon before the first slash as
    a REMOTE computer: `out 26:27` copied nothing and said "Published", and
    `localhost:site` opened an ssh connection. `RSYNC_RSH` is pointed at
    `false` for every run here, so the old launcher cannot reach a real
    computer even while this file is proving it wrong.
  * **A copy that did not finish is a failure** — `folderPublishTarget.
    partialCopy`. rsync's exit status used to go into a pipe whose status was
    thrown away.

Pure stdlib. Run with:

    python3 scripts/test_deploy_folder_target.py
"""

import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPOSITORY_ROOT / "scripts"))

os.environ.setdefault("PLANTOIR_CONTRACTS_DIR", str(REPOSITORY_ROOT / "contracts"))

import contracts  # noqa: E402

WORKING_FOLDER_NAME = "Comm Tech 26:27"
BUILT_PAGES = {"index.html": "<html>a built site</html>", "b.html": "<html>b</html>"}


def _rules() -> dict:
    return contracts.section("shared-rules", "folderPublishTarget")


def _failure_cases() -> list:
    return contracts.section("app-rules", "failureExplanations")["cases"]


def _bash_can_reach_a_scratch_folder() -> bool:
    """The same question `test_reference_course.py` asks, for the same
    reason: a Windows machine with WSL has a `bash` on PATH that cannot open a
    Windows temporary path at all, and these tests would FAIL there rather
    than skip — inside `dotnet test`, which is a gate on that side."""
    if shutil.which("bash") is None:
        return False
    try:
        with tempfile.TemporaryDirectory() as tmp:
            probe = subprocess.run(
                ["bash", "-c", 'cd "$1" && printf reachable', "_", str(tmp)],
                capture_output=True, timeout=60,
            )
            return probe.stdout.decode("utf-8", "replace").strip() == "reachable"
    except (OSError, subprocess.SubprocessError):
        return False


HAS_BASH = _bash_can_reach_a_scratch_folder()
HAS_RSYNC = shutil.which("rsync") is not None
ON_WINDOWS = sys.platform == "win32"


def _a_working_folder(tmp: str) -> Path:
    """A scratch working folder, named with a colon, holding one course with a
    built site to publish."""
    folder = Path(tmp) / WORKING_FOLDER_NAME
    folder.mkdir()
    shutil.copy2(REPOSITORY_ROOT / "deploy.sh", folder / "deploy.sh")
    course = folder / "courses" / "ICS4U"
    course.mkdir(parents=True)
    values = {"course_code": "ICS4U", "section_numbers": [1], "num_sections": 1}
    (course / "course_config.json").write_text(json.dumps(values), encoding="utf-8")
    built = course / ".merged_output" / "section1" / "public"
    built.mkdir(parents=True)
    for name, text in BUILT_PAGES.items():
        (built / name).write_text(text, encoding="utf-8")
    return folder


def _run_launcher(folder: Path, to_folder: str):
    """The copied launcher, publishing section 1 to `to_folder`.

    HOME is the scratch folder's, because `deploy.sh` moves a course's built
    site into `$HOME/Library/Application Support/Plantoir/builds/` the first
    time it sees one. PWD is dropped so the launcher's `pwd` is the physical
    path, the way the app starts it. RSYNC_RSH is `false`, so a launcher that
    still reads a colon as a computer name cannot connect to one.
    """
    environment = dict(os.environ)
    environment["HOME"] = str(folder / "home")
    environment.pop("PWD", None)
    environment["RSYNC_RSH"] = "false"
    (folder / "home").mkdir(exist_ok=True)
    return subprocess.run(
        ["bash", "./deploy.sh", "ICS4U", "1", "--to-folder", to_folder,
         "--non-interactive", "--image", "no-such-image"],
        cwd=str(folder), capture_output=True, timeout=180, env=environment,
    )


def _physical(path: Path) -> str:
    """A folder as `/bin/pwd -P` spells it — which is how the launcher spells
    the working folder (under /var/folders a temporary folder is really under
    /private/var/folders)."""
    return os.path.realpath(str(path))


def _files_in(folder: Path) -> list:
    found = []
    if not folder.is_dir():
        return found
    for entry in sorted(folder.rglob("*")):
        if entry.is_file():
            found.append(str(entry.relative_to(folder)))
    return found


@unittest.skipUnless(HAS_BASH, "bash cannot reach a scratch folder here")
@unittest.skipUnless(HAS_RSYNC, "rsync is not installed")
class WhereARelativeFolderLands(unittest.TestCase):
    """Every `folderPublishTarget.cases` row, through the real launcher."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.folder = _a_working_folder(self.tmp)
        self.elsewhere = Path(self.tmp) / "elsewhere"
        self.elsewhere.mkdir()

    def _substitute(self, text: str) -> str:
        return (text.replace("@WF@", _physical(self.folder))
                    .replace("@ELSEWHERE@", _physical(self.elsewhere)))

    def test_every_case_lands_where_the_contract_says(self):
        cases = _rules()["cases"]
        self.assertGreaterEqual(len(cases), 6)
        ran = 0
        for case in cases:
            if case.get("notOnWindows") and ON_WINDOWS:
                continue
            to_folder = self._substitute(case["toFolder"])
            expected = self._substitute(case["expectTarget"])
            with self.subTest(to_folder=case["toFolder"]):
                result = _run_launcher(self.folder, to_folder)
                output = (result.stdout + result.stderr).decode("utf-8", "replace")
                self.assertEqual(result.returncode, 0, output)
                self.assertIn("PUBLISHED_FOLDER=" + expected + "\n", output)
                self.assertTrue(expected.startswith("/"), expected)
                self.assertEqual(
                    _files_in(Path(expected)), sorted(BUILT_PAGES),
                    f"the published folder should hold exactly the built site\n{output}",
                )
                ran += 1
        self.assertGreater(ran, 0)


@unittest.skipUnless(HAS_BASH, "bash cannot reach a scratch folder here")
@unittest.skipUnless(HAS_RSYNC, "rsync is not installed")
@unittest.skipIf(hasattr(os, "geteuid") and os.geteuid() == 0,
                 "run as root, a folder's permissions stop nothing, so the copy cannot be made to fail")
class ACopyThatDidNotFinish(unittest.TestCase):
    """`folderPublishTarget.partialCopy`: a stale folder `--delete` cannot
    remove makes rsync exit 23 ("finished in part") while every new page
    still lands."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.folder = _a_working_folder(self.tmp)
        self.target = Path(self.tmp) / "published"
        self.stale = self.target / "section1" / "stale"
        self.stale.mkdir(parents=True)
        (self.stale / "a page taken down.html").write_text("<html>old</html>", encoding="utf-8")
        os.chmod(self.stale, stat.S_IRUSR | stat.S_IXUSR | stat.S_IRGRP | stat.S_IXGRP
                 | stat.S_IROTH | stat.S_IXOTH)

        def _unlock_and_remove():
            os.chmod(self.stale, stat.S_IRWXU)
            shutil.rmtree(self.tmp, ignore_errors=True)
        self.addCleanup(_unlock_and_remove)

    def test_it_is_a_failure_and_names_no_folder(self):
        rule = _rules()["partialCopy"]
        result = _run_launcher(self.folder, str(self.target))
        output = (result.stdout + result.stderr).decode("utf-8", "replace")
        self.assertEqual(result.returncode, rule["expectExit"], output)
        for line in output.splitlines():
            for forbidden in rule["expectNoLineStartingWith"]:
                self.assertFalse(line.startswith(forbidden), f"{line!r}\n{output}")
        # The page the teacher took down is still there — which is exactly why
        # this is not allowed to say Published.
        self.assertTrue((self.stale / "a page taken down.html").exists())

    def test_the_app_can_put_the_failure_into_words(self):
        """The launcher's own ❌ line is the one `failureExplanations` has a
        case for, so the app shows a sentence rather than the generic "did not
        finish" — and a reworded launcher line fails HERE, not silently in the
        app."""
        result = _run_launcher(self.folder, str(self.target))
        output = (result.stdout + result.stderr).decode("utf-8", "replace")
        crosses = [line for line in output.splitlines() if line.startswith("❌")]
        self.assertEqual(len(crosses), 1, output)
        matching = [case for case in _failure_cases() if crosses[0] in case["output"]]
        self.assertEqual(len(matching), 1, f"no failureExplanations case carries {crosses[0]!r}")
        self.assertTrue(matching[0]["expect"])


if __name__ == "__main__":
    unittest.main()
