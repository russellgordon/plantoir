#!/usr/bin/env python3
"""
One rule for "this built site is a preview's", run against the launchers'
own readers (GitHub #136).

Serve mode bakes a live-reload client into every page it builds, and a site
that carries it must never be published. Whether a built site carries it is
answered in six places: BuildFreshness in each app, the mac's scheduled
publish, `deploy.sh` (three times), `deploy.py` and `deploy.ps1`. Until #136
the apps read the front page alone while the launchers read every page, so a
clean front page in front of a preview's pages was "fresh" to the app and
"a preview's" to the launcher — which then rebuilt it under the wrong leg.

The rule is `contracts/app-rules.json` -> `buildFreshness.previewBuild`, and
each case there is a tree of pages. The mac's own test suite runs the app's
check and the scheduled publish's against it; this file runs the two readers
the shared toolchain owns:

- **deploy.sh.** Its rule is cut out of the launcher — not retyped: one
  `LIVE_RELOAD_CLIENT_PATTERN`, which bash must read as the contract's
  `asABasicRegex`, and one `site_carries_preview_client`, called exactly three
  times. That function is then RUN through bash against each case under a
  UTF-8 locale, the way a Terminal runs it (#291). Skipped where there is no
  bash that can reach a scratch folder, as the launcher tests beside it are.
- **deploy.py.** The real program, which reads the signature from the
  contract, is RUN against each case with a stand-in
  `build_site.py` and no Netlify token, so it stops before anything leaves the
  machine, and whether it announced a rebuild is the answer. `HOME`,
  `PLANTOIR_BUILD_ROOT` and the token are taken out of its environment, so it
  can neither find a real build nor publish one.

`deploy.ps1` is Windows' to run against the same cases.

Cases that name `unreadable` pages are skipped where a page cannot be made
unreadable by clearing its permissions (Windows, or a run as root).

Pure stdlib, no Docker, no network. Run with:

    python3 scripts/test_preview_build_detection.py
"""

import os
import re
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True

SCRIPTS_FOLDER = Path(__file__).resolve().parent
if str(SCRIPTS_FOLDER) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_FOLDER))

import contracts
import toolchain_paths
from test_deploy_sh_questions import HAS_BASH, REPOSITORY_ROOT

# The readers under test. Module-level so a must-fail run can point them at a
# narrowed copy without touching the real files.
DEPLOY_SH = REPOSITORY_ROOT / "deploy.sh"
DEPLOY_PY = SCRIPTS_FOLDER / "deploy.py"

# What deploy.py prints when it has found the client. Its own words, not a
# teacher's sentence: the line is a progress note in the publish console.
REBUILD_ANNOUNCEMENT = "Preview build detected"

# deploy.sh's rule, as it is written in the launcher: the pattern, defined
# once, and the one function that reads a tree with it (#291).
DEPLOY_SH_PATTERN_LINE = re.compile(r"^LIVE_RELOAD_CLIENT_PATTERN=.*$", re.MULTILINE)
DEPLOY_SH_FUNCTION = re.compile(r"^site_carries_preview_client\(\) \{\n.*?^\}\n", re.MULTILINE | re.DOTALL)
DEPLOY_SH_CALL = re.compile(r"""site_carries_preview_client "\$\{PUBLIC_DIR_HOST\}";""")
# Any grep of a built tree that still names the address itself.
DEPLOY_SH_BARE_GREP = re.compile(r"grep[^\n]*ws://localhost")

# The locale a teacher's Terminal runs deploy.sh in. The rule must hold there,
# not only in the C locale launchd and many CI shells happen to give (#291:
# under UTF-8, BSD grep -z misses the client in a file with an invalid byte).
TERMINAL_LOCALE = "en_US.UTF-8"

CAN_MAKE_UNREADABLE = os.name != "nt" and (not hasattr(os, "geteuid") or os.geteuid() != 0)


def the_rule():
    repo_contracts = REPOSITORY_ROOT / "contracts"
    if repo_contracts.is_dir():
        toolchain_paths.CONTRACTS_DIR = repo_contracts
    contracts.reset_cache()
    return contracts.section("app-rules", "buildFreshness", "previewBuild")


def deploy_sh_text() -> str:
    return DEPLOY_SH.read_text(encoding="utf-8")


def deploy_sh_rule() -> str:
    """deploy.sh's pattern line and function, cut out of the launcher."""
    text = deploy_sh_text()
    pattern_lines = DEPLOY_SH_PATTERN_LINE.findall(text)
    functions = DEPLOY_SH_FUNCTION.findall(text)
    return "\n".join(pattern_lines + functions)


def deploy_sh_pattern_as_bash_reads_it() -> str:
    result = subprocess.run(
        ["bash", "-c", deploy_sh_rule() + '\nprintf %s "$LIVE_RELOAD_CLIENT_PATTERN"'],
        capture_output=True, timeout=60,
    )
    return result.stdout.decode("utf-8")


def write_pages(test_case, public_dir: Path):
    """The case's tree under `public_dir`; the pages it names unreadable."""
    for relative_path, text in test_case["pages"].items():
        page = public_dir / relative_path
        page.parent.mkdir(parents=True, exist_ok=True)
        page.write_bytes(text.encode("utf-8"))
    # Bytes that are not UTF-8 at the very start of the page, a line of their
    # own, far from the client: under a UTF-8 locale grep -z still misses it.
    for relative_path in test_case.get("invalidUTF8Before", []):
        page = public_dir / relative_path
        page.write_bytes(b"\xff\n" + page.read_bytes())
    locked = []
    for relative_path in test_case.get("unreadable", []):
        page = public_dir / relative_path
        os.chmod(page, 0)
        locked.append(page)
    return locked


def make_readable(pages):
    for page in pages:
        os.chmod(page, stat.S_IRUSR | stat.S_IWUSR)


class TheLaunchersReadTheContractsCases(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.rule = the_rule()
        cls.cases = cls.rule["cases"]

    def cases_this_machine_can_build(self):
        usable = []
        for test_case in self.cases:
            if test_case.get("unreadable") and not CAN_MAKE_UNREADABLE:
                continue
            usable.append(test_case)
        return usable

    # MARK: - deploy.sh

    def test_deploy_sh_defines_the_rule_once_and_uses_it_three_times(self):
        text = deploy_sh_text()
        self.assertEqual(
            len(DEPLOY_SH_PATTERN_LINE.findall(text)), 1,
            "deploy.sh defines LIVE_RELOAD_CLIENT_PATTERN exactly once",
        )
        self.assertEqual(
            len(DEPLOY_SH_FUNCTION.findall(text)), 1,
            "deploy.sh defines site_carries_preview_client exactly once",
        )
        self.assertEqual(
            len(DEPLOY_SH_CALL.findall(text)), 3,
            "deploy.sh checks for a preview's build before the folder copy, after "
            "its rebuild, and to say it could not remove it — three times. A "
            "different count means the launcher changed and this file must be told.",
        )
        self.assertEqual(
            DEPLOY_SH_BARE_GREP.findall(text), [],
            "a grep for the bare address is the #291 fault: every check goes "
            "through site_carries_preview_client",
        )

    @unittest.skipUnless(HAS_BASH, "no bash that can reach a scratch folder")
    def test_deploy_sh_pattern_is_the_contracts(self):
        self.assertEqual(
            deploy_sh_pattern_as_bash_reads_it(),
            self.rule["signature"]["asABasicRegex"],
        )

    @unittest.skipUnless(HAS_BASH, "no bash that can reach a scratch folder")
    def test_deploy_sh_answers_every_case_as_the_contract_does(self):
        rule = deploy_sh_rule()
        for test_case in self.cases_this_machine_can_build():
            with self.subTest(test_case["name"]):
                with tempfile.TemporaryDirectory() as scratch:
                    public_dir = Path(scratch) / "public"
                    locked = write_pages(test_case, public_dir)
                    try:
                        environment = dict(os.environ)
                        environment["PUBLIC_DIR_HOST"] = str(public_dir)
                        environment["LANG"] = TERMINAL_LOCALE
                        environment["LC_ALL"] = TERMINAL_LOCALE
                        environment["LC_CTYPE"] = TERMINAL_LOCALE
                        result = subprocess.run(
                            ["bash", "-c", rule + '\nif site_carries_preview_client "${PUBLIC_DIR_HOST}"; '
                             "then exit 0; else exit 1; fi"],
                            env=environment, capture_output=True, timeout=60,
                        )
                    finally:
                        make_readable(locked)
                    self.assertEqual(result.returncode == 0, test_case["expectPreview"], test_case["name"])

    # MARK: - deploy.py

    def test_deploy_py_answers_every_case_as_the_contract_does(self):
        for test_case in self.cases_this_machine_can_build():
            with self.subTest(test_case["name"]):
                output = self.run_deploy_py_over(test_case)
                self.assertEqual(
                    REBUILD_ANNOUNCEMENT in output, test_case["expectPreview"],
                    test_case["name"] + "\n--- deploy.py said:\n" + output,
                )

    def run_deploy_py_over(self, test_case) -> str:
        with tempfile.TemporaryDirectory() as scratch:
            scratch_path = Path(scratch)
            stand_in_scripts = scratch_path / "scripts"
            stand_in_scripts.mkdir()
            # The rebuild a preview's site sets off: refuses at once, so the
            # run ends there with nothing built and nothing sent.
            (stand_in_scripts / "build_site.py").write_text(
                "import sys\nsys.exit(1)\n", encoding="utf-8"
            )
            courses = scratch_path / "courses"
            (courses / "ZZP1U").mkdir(parents=True)
            (courses / "ZZP1U" / "course_config.json").write_text(
                '{"course_code": "ZZP1U"}', encoding="utf-8"
            )
            public_dir = courses / "ZZP1U" / ".merged_output" / "section1" / "public"
            locked = write_pages(test_case, public_dir)
            home = scratch_path / "home"
            home.mkdir()
            environment = dict(os.environ)
            environment["PYTHONDONTWRITEBYTECODE"] = "1"
            environment["PLANTOIR_SCRIPTS_DIR"] = str(stand_in_scripts)
            environment["PLANTOIR_COURSES_DIR"] = str(courses)
            environment["PLANTOIR_CONTRACTS_DIR"] = str(REPOSITORY_ROOT / "contracts")
            environment["HOME"] = str(home)
            environment["USERPROFILE"] = str(home)
            # Windows moves built sites out of the working folder with this;
            # left in, deploy.py would look for the site somewhere real.
            environment.pop("PLANTOIR_BUILD_ROOT", None)
            environment.pop("NETLIFY_AUTH_TOKEN", None)
            try:
                result = subprocess.run(
                    [sys.executable, str(DEPLOY_PY), "--course", "ZZP1U", "--section", "1"],
                    env=environment, stdin=subprocess.DEVNULL,
                    capture_output=True, text=True, encoding="utf-8", errors="replace",
                    timeout=120,
                )
            finally:
                make_readable(locked)
            output = result.stdout + result.stderr
            # Every case must reach the check: a run that stopped earlier
            # would read as "not a preview's" and pass for the wrong reason.
            # A clean site goes on to ask for the token, and stops there.
            if REBUILD_ANNOUNCEMENT not in output:
                self.assertIn(
                    "Netlify token missing", output,
                    "deploy.py stopped before it looked at the pages",
                )
            return output


if __name__ == "__main__":
    unittest.main(verbosity=2)
