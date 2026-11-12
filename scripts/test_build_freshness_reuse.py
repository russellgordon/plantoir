#!/usr/bin/env python3
"""
A deploy reuses the last build only when nothing has changed (GitHub #768,
with #748 part 2 and #741).

Russell's ruling, 2026-11-12: any deploy, typed at a command line or pressed
in the app, on either platform, reuses the last build when nothing has changed
and builds again otherwise. Until then only the apps asked about the pages, so
`./deploy.sh ICS3U 1` after an edit sent the last build, and a page deleted
from the course stayed on the site (#741). The rule and its cases are
contracts/app-rules.json -> buildFreshness.reuseTheLastBuild; this file runs
every case against the two readers that are not Swift:

  * toolchain_paths.why_build_before_deploying (deploy.py, and Windows'
    deploy.ps1), and
  * deploy.sh's own question, its pages_or_clock_ask_for_a_build and
    site_was_built_by_this_toolchain cut out of the launcher and run.

And end to end: the real deploy.sh, publishing to a folder with a stand-in
preview.sh, builds once after an edit or a deletion, says why, writes the
trail line (activityTrail.mustRecord."site built again before deploying"),
and reuses the build when nothing changed; deploy.py looks for its build in
WORK_DIR rather than a literal /tmp path (#768's Windows fault) and asks the
pages too, unless deploy.sh already did. The mac's BuildFreshnessTests and
ScheduledPublishOutcomeTests run the same cases against the apps' readers.

Pure stdlib, no Docker, no network. Run with:

    python3 scripts/test_build_freshness_reuse.py
"""

import hashlib
import io
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock

REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPOSITORY_ROOT / "scripts"))

os.environ.setdefault("PLANTOIR_CONTRACTS_DIR", str(REPOSITORY_ROOT / "contracts"))

import freshness_cases  # noqa: E402
import toolchain_paths  # noqa: E402

THIS_TOOLCHAIN = "teaching-quartz:src-1a2b3c4d"
ANOTHER_TOOLCHAIN = "teaching-quartz:src-9fd16022"
CONTRACT = freshness_cases.the_contract(REPOSITORY_ROOT)
PREVIEW_PAGE = freshness_cases.preview_page_of(REPOSITORY_ROOT)
ON_WINDOWS = sys.platform == "win32"


def _the_trail_entry() -> dict:
    with open(REPOSITORY_ROOT / "contracts" / "shared-rules.json", encoding="utf-8") as handle:
        rules = json.load(handle)
    for entry in rules["activityTrail"]["mustRecord"]:
        if entry["event"] == "site built again before deploying":
            return entry
    raise AssertionError("the trail event is not in activityTrail.mustRecord")


def _bash_can_reach_a_scratch_folder() -> bool:
    """As test_deploy_toolchain_stamp.py asks: a Windows `bash` from WSL
    cannot open a Windows temporary path, and these must skip there."""
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


def _cut_out(name: str) -> str:
    text = (REPOSITORY_ROOT / "deploy.sh").read_text(encoding="utf-8")
    begin = f"# BEGIN {name}\n"
    end = f"# END {name}\n"
    assert text.count(begin) == 1 and text.count(end) == 1, name
    return text[text.index(begin) + len(begin):text.index(end)]


def _can_make_links() -> bool:
    with tempfile.TemporaryDirectory() as tmp:
        return freshness_cases.can_make_links(Path(tmp))


CAN_MAKE_LINKS = _can_make_links()


def _skipped_here(case: dict) -> bool:
    if case.get("courseFolderIsALink") and not CAN_MAKE_LINKS:
        return True
    return ON_WINDOWS and "windows" in case.get("knownLimitOn", [])


class TheContractIsWellFormed(unittest.TestCase):
    """The cases can be read the same way by four readers in two languages."""

    def test_every_reason_is_named(self):
        reasons = set(CONTRACT["reasons"])
        for case in CONTRACT["cases"]:
            with self.subTest(case=case["name"]):
                self.assertIn(case["expect"], ("reuse", "build"))
                if case["expect"] == "build":
                    self.assertIn(case["because"], reasons)
                else:
                    self.assertNotIn("because", case)
                if "inTheApps" in case:
                    self.assertIn(case["inTheApps"]["expect"], ("reuse", "build"))

    def test_every_change_is_one_the_shape_describes(self):
        shape = CONTRACT["casesShape"]
        for case in CONTRACT["cases"]:
            for change in case.get("changes", []):
                with self.subTest(case=case["name"], change=change["do"]):
                    self.assertIn(change["do"], shape)
                    self.assertIn(change["when"], shape)

    def test_the_names_are_all_different(self):
        names = []
        for case in CONTRACT["cases"]:
            names.append(case["name"])
        self.assertEqual(len(names), len(set(names)))

    def test_the_review_found_cases_are_all_here(self):
        """H1 and M1 of the plan review: the deletions, renames, kept times
        and the clock, which a files-only, modification-time-only check
        missed."""
        changes_done = set()
        for case in CONTRACT["cases"]:
            for change in case.get("changes", []):
                changes_done.add(change["do"])
        for needed in ("delete", "rename", "replaceKeepingItsOldTime",
                       "overwriteKeepingItsOldTime", "createKeepingAnOldTime", "edit"):
            self.assertIn(needed, changes_done)
        dated_later = False
        hidden_parent = False
        for case in CONTRACT["cases"]:
            dated_later = dated_later or bool(case.get("datedLaterThanNow"))
            hidden_parent = hidden_parent or bool(case.get("workingFolderUnderAHiddenFolder"))
        self.assertTrue(dated_later)
        self.assertTrue(hidden_parent)

    def test_the_trail_has_words_for_every_reason_a_deploy_builds_for(self):
        entry = _the_trail_entry()
        words = entry["whyWords"]
        for reason in CONTRACT["reasons"]:
            if reason in ("address", "neverBuilt"):
                continue
            self.assertIn(reason, words)
        self.assertIn("lineWhenItHadNotBeenBuilt", entry)
        # Russell's words for the update, approved on #748 (2026-11-12).
        line = entry["line"].replace("{why}", words["toolchain"])
        self.assertTrue(line.endswith(
            "built the website again before deploying it — Plantoir had been updated since it was last built"))


class TheSharedAnswerIsTheContracts(unittest.TestCase):
    """toolchain_paths.why_build_before_deploying against every case."""

    def test_every_case(self):
        for case in CONTRACT["cases"]:
            with self.subTest(case=case["name"]):
                if _skipped_here(case):
                    self.skipTest("not on this computer: " + case["name"])
                with tempfile.TemporaryDirectory() as tmp:
                    course, section = freshness_cases.build(
                        Path(tmp), case, CONTRACT["theCourse"], THIS_TOOLCHAIN, ANOTHER_TOOLCHAIN, PREVIEW_PAGE)
                    reason = toolchain_paths.why_build_before_deploying(
                        course, section, toolchain_id=THIS_TOOLCHAIN)
                expect, because = freshness_cases.expected(case, reads_the_stamp=True)
                if expect == "reuse":
                    self.assertIsNone(reason)
                else:
                    self.assertEqual(reason, because)

    def test_the_pages_alone_against_the_cases_the_apps_read(self):
        """The half the apps also answer, with the stamp left unread. A
        preview's site is asked separately (site_carries_preview_client)."""
        for case in CONTRACT["cases"]:
            with self.subTest(case=case["name"]):
                if _skipped_here(case):
                    self.skipTest("not on this computer: " + case["name"])
                if freshness_cases.expected(case, reads_the_stamp=False)[1] == "preview":
                    continue
                with tempfile.TemporaryDirectory() as tmp:
                    course, section = freshness_cases.build(
                        Path(tmp), case, CONTRACT["theCourse"], THIS_TOOLCHAIN, ANOTHER_TOOLCHAIN, PREVIEW_PAGE)
                    reason = toolchain_paths.why_the_pages_ask_for_a_build(course, section)
                expect, because = freshness_cases.expected(case, reads_the_stamp=False)
                if expect == "reuse":
                    self.assertIsNone(reason)
                else:
                    self.assertEqual(reason, because)


@unittest.skipUnless(HAS_BASH, "needs bash")
@unittest.skipIf(ON_WINDOWS, "deploy.sh is the mac's launcher")
class DeploySHAsksTheSameQuestion(unittest.TestCase):
    """deploy.sh's own question, cut out of the launcher, against every case.
    Run under /bin/bash where there is one: the mac's 3.2 is what a teacher's
    Terminal runs, and its `[ -nt ]` compares whole seconds."""

    BASH = "/bin/bash" if os.path.exists("/bin/bash") else "bash"

    def _ask(self, course: Path, section: Path, pages_only: bool) -> str:
        launcher = (REPOSITORY_ROOT / "deploy.sh").read_text(encoding="utf-8")
        pattern = re.search(r"^LIVE_RELOAD_CLIENT_PATTERN=.*$", launcher, re.MULTILINE).group(0)
        carries = re.search(r"^site_carries_preview_client\(\) \{\n.*?^\}\n", launcher,
                            re.MULTILINE | re.DOTALL).group(0)
        script = (
            "set -euo pipefail\n"
            + pattern + "\n" + carries
            + _cut_out("site_was_built_by_this_toolchain")
            + _cut_out("pages_or_clock_ask_for_a_build")
            + _cut_out("why_this_deploy_builds_first")
        )
        if pages_only:
            script += 'pages_or_clock_ask_for_a_build "$1" "$2" || echo none\n'
        else:
            script += 'why_this_deploy_builds_first "$1" "$2" "$3" || echo none\n'
        result = subprocess.run(
            [self.BASH, "-c", script, "_", str(course), str(section), THIS_TOOLCHAIN],
            capture_output=True, timeout=60,
        )
        self.assertEqual(result.returncode, 0, result.stderr.decode("utf-8", "replace"))
        self.assertEqual(result.stderr, b"")
        return result.stdout.decode("utf-8").strip()

    def test_every_case(self):
        for case in CONTRACT["cases"]:
            with self.subTest(case=case["name"]):
                with tempfile.TemporaryDirectory() as tmp:
                    course, section = freshness_cases.build(
                        Path(tmp), case, CONTRACT["theCourse"], THIS_TOOLCHAIN, ANOTHER_TOOLCHAIN, PREVIEW_PAGE)
                    if case.get("typedByHand") == "refused":
                        # Refused before the question is asked; the question
                        # itself says nothing about a site with no front page.
                        self.assertEqual(self._ask(course, section, pages_only=True), "none")
                        continue
                    answer = self._ask(course, section, pages_only=False)
                expect, because = freshness_cases.expected(case, reads_the_stamp=True)
                if expect == "reuse":
                    self.assertEqual(answer, "none")
                else:
                    self.assertEqual(answer, because)

    def test_it_leaves_nothing_behind(self):
        """The `now` file it compares with is removed again, by its own path."""
        with tempfile.TemporaryDirectory() as tmp:
            scratch = Path(tmp) / "tmp"
            scratch.mkdir()
            course, section = freshness_cases.build(
                Path(tmp), CONTRACT["cases"][0], CONTRACT["theCourse"], THIS_TOOLCHAIN, ANOTHER_TOOLCHAIN)
            script = _cut_out("pages_or_clock_ask_for_a_build") + 'pages_or_clock_ask_for_a_build "$1" "$2" || true\n'
            environment = dict(os.environ)
            environment["TMPDIR"] = str(scratch)
            subprocess.run([self.BASH, "-c", script, "_", str(course), str(section)],
                           capture_output=True, timeout=60, env=environment)
            self.assertEqual(list(scratch.iterdir()), [])


STAND_IN_PREVIEW = """#!/bin/bash
printf '%s\\n' "$*" >> "$PWD/preview-was-asked"
built="$PWD/courses/C/.merged_output/section1"
printf '%s' '<html>built again</html>' > "$built/public/index.html"
: > "$built/.build-started"
printf '%s\\n' '{image}' > "$built/.built-with-toolchain"
""".format(image=THIS_TOOLCHAIN)

PREVIEW_CLIENT_PAGE = (
    '<html><body><script type="application/javascript">\n'
    "        const socket = new WebSocket('ws://localhost:9081')\n"
    "      </script></body></html>"
)


@unittest.skipUnless(HAS_BASH and HAS_RSYNC, "needs bash and rsync")
@unittest.skipIf(ON_WINDOWS, "deploy.sh is the mac's launcher")
class AHandTypedDeployBuildsOnlyWhenSomethingChanged(unittest.TestCase):
    """The real deploy.sh, copied into a scratch working folder, publishing to
    a folder, with a stand-in preview.sh that records that it was asked."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.folder = self.tmp / "work"
        self.folder.mkdir()
        shutil.copy2(REPOSITORY_ROOT / "deploy.sh", self.folder / "deploy.sh")
        preview = self.folder / "preview.sh"
        preview.write_text(STAND_IN_PREVIEW, encoding="utf-8")
        preview.chmod(preview.stat().st_mode | stat.S_IXUSR)
        self.course = self.folder / "courses" / "C"
        (self.course / "notes").mkdir(parents=True)
        (self.course / "course_config.json").write_text(
            '{"course_code": "C", "section_numbers": [1], "num_sections": 1}', encoding="utf-8")
        (self.course / "notes" / "day-1.md").write_text("Day 1\n", encoding="utf-8")
        (self.course / "notes" / "day-2.md").write_text("Day 2\n", encoding="utf-8")
        # Where deploy.sh keeps this folder's built sites, linked as it links
        # them, so it finds the link right and touches nothing.
        spelled = subprocess.run(["/bin/pwd", "-P"], cwd=str(self.folder),
                                 capture_output=True, check=True).stdout
        folder_id = hashlib.sha256(spelled).hexdigest()[:8]
        builds = (self.tmp / "home" / "Library" / "Application Support" / "Plantoir"
                  / "builds" / folder_id / "C")
        (builds / "section1" / "public").mkdir(parents=True)
        os.symlink(builds, self.course / ".merged_output")
        self.section = builds / "section1"
        self.trail = self.tmp / "trail"
        self.trail.mkdir()
        time.sleep(0.02)

    def _built(self, page="<html>the last build</html>"):
        (self.section / ".build-started").write_text("started\n", encoding="utf-8")
        time.sleep(0.02)
        (self.section / "public" / "index.html").write_text(page, encoding="utf-8")
        (self.section / ".built-with-toolchain").write_text(THIS_TOOLCHAIN + "\n", encoding="utf-8")
        time.sleep(0.02)

    def _deploy(self):
        asked_file = self.folder / "preview-was-asked"
        if asked_file.exists():
            asked_file.unlink()
        environment = dict(os.environ)
        environment["HOME"] = str(self.tmp / "home")
        environment["PLANTOIR_TRAIL_DIR"] = str(self.trail)
        environment.pop("PWD", None)
        environment["RSYNC_RSH"] = "false"
        (self.tmp / "home").mkdir(exist_ok=True)
        target = self.tmp / "published"
        result = subprocess.run(
            ["bash", "./deploy.sh", "C", "1", "--to-folder", str(target),
             "--non-interactive", "--image", THIS_TOOLCHAIN],
            cwd=str(self.folder), capture_output=True, timeout=180, env=environment,
        )
        output = (result.stdout + result.stderr).decode("utf-8", "replace")
        asked = asked_file.read_text(encoding="utf-8") if asked_file.exists() else ""
        page_file = target / "section1" / "index.html"
        page = page_file.read_text(encoding="utf-8") if page_file.exists() else ""
        trail_file = self.trail / "activity.txt"
        trail = trail_file.read_text(encoding="utf-8") if trail_file.exists() else ""
        return result.returncode, output, asked, page, trail

    def _trail_line(self, reason: str) -> str:
        entry = _the_trail_entry()
        line = entry["line"].replace("{why}", entry["whyWords"][reason])
        return line.replace("{course}", "C").replace("{section}", "1")

    def test_nothing_changed_reuses_the_build(self):
        self._built()
        code, output, asked, page, trail = self._deploy()
        self.assertEqual(code, 0, output)
        self.assertEqual(asked, "", output)
        self.assertNotIn("🔁", output)
        self.assertEqual(page, "<html>the last build</html>")
        self.assertNotIn("built the website", trail)

    def test_an_edit_builds_once_and_says_why(self):
        self._built()
        with open(self.course / "notes" / "day-1.md", "a", encoding="utf-8") as handle:
            handle.write("edited\n")
        code, output, asked, page, trail = self._deploy()
        self.assertEqual(code, 0, output)
        self.assertEqual(asked.count("--build-only"), 1, output)
        self.assertIn("C 1 --build-only", asked)
        self.assertIn("--non-interactive", asked)
        self.assertIn("--image " + THIS_TOOLCHAIN, asked)
        self.assertEqual(output.count("Something in this course has changed since its site was last built,"), 1, output)
        self.assertEqual(page, "<html>built again</html>")
        self.assertEqual(trail.count(self._trail_line("pages")), 1, trail)

    def test_a_deleted_page_builds_again(self):
        """#741: the page removed in Obsidian stayed on the site."""
        self._built()
        os.remove(self.course / "notes" / "day-2.md")
        code, output, asked, page, trail = self._deploy()
        self.assertEqual(code, 0, output)
        self.assertEqual(asked.count("--build-only"), 1, output)
        self.assertEqual(page, "<html>built again</html>")

    def test_the_deploy_after_a_build_reuses_it(self):
        """No loop: what the deploy and the build write is hidden."""
        self._built()
        os.remove(self.course / "notes" / "day-2.md")
        first = self._deploy()
        self.assertEqual(first[2].count("--build-only"), 1, first[1])
        time.sleep(0.02)
        code, output, asked, page, trail = self._deploy()
        self.assertEqual(code, 0, output)
        self.assertEqual(asked, "", output)
        self.assertNotIn("🔁", output)

    def test_an_earlier_versions_site_says_the_update_once(self):
        self._built()
        (self.section / ".built-with-toolchain").write_text(ANOTHER_TOOLCHAIN + "\n", encoding="utf-8")
        with open(self.course / "notes" / "day-1.md", "a", encoding="utf-8") as handle:
            handle.write("edited too\n")
        code, output, asked, page, trail = self._deploy()
        self.assertEqual(code, 0, output)
        self.assertEqual(asked.count("--build-only"), 1, output)
        self.assertIn("Plantoir has been updated since this site was built", output)
        self.assertNotIn("Something in this course has changed", output)
        self.assertEqual(trail.count(self._trail_line("toolchain")), 1, trail)
        self.assertNotIn(self._trail_line("pages"), trail)

    def test_a_previews_site_says_so_on_the_trail(self):
        """What a real preview leaves: its front page with the client, and no
        toolchain stamp and no start marker, since a preview writes neither
        (the #768 review's M1: this said an earlier version had built it)."""
        (self.section / "public" / "index.html").write_text(PREVIEW_CLIENT_PAGE, encoding="utf-8")
        time.sleep(0.02)
        code, output, asked, page, trail = self._deploy()
        self.assertEqual(code, 0, output)
        self.assertEqual(asked.count("--build-only"), 1, output)
        self.assertIn("This site was built by a preview", output)
        self.assertNotIn("Plantoir has been updated", output)
        self.assertEqual(trail.count(self._trail_line("preview")), 1, trail)
        self.assertNotIn(self._trail_line("toolchain"), trail)

    def test_a_failed_build_writes_no_line(self):
        self._built()
        (self.folder / "preview.sh").write_text("#!/bin/bash\nexit 1\n", encoding="utf-8")
        with open(self.course / "notes" / "day-1.md", "a", encoding="utf-8") as handle:
            handle.write("edited\n")
        code, output, asked, page, trail = self._deploy()
        self.assertEqual(code, 1, output)
        self.assertIn("Could not rebuild this site before deploying it.", output)
        self.assertNotIn("built the website", trail)

    def test_a_section_never_built_is_still_refused(self):
        code, output, asked, page, trail = self._deploy()
        self.assertEqual(code, 1, output)
        self.assertIn("Built site not found", output)
        self.assertEqual(asked, "")


class DeployPyLooksInTheWorkFolderAndAsksThePages(unittest.TestCase):
    """deploy.py's one rebuild decision for Netlify and Cloudflare."""

    @classmethod
    def setUpClass(cls):
        import deploy
        cls.deploy = deploy

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        courses = self.tmp / "courses"
        self.course = courses / "C"
        (self.course / "notes").mkdir(parents=True)
        (self.course / "notes" / "day-1.md").write_text("Day 1\n", encoding="utf-8")
        time.sleep(0.02)
        self.section = self.tmp / "builds" / "C" / "section1"
        (self.section / "public").mkdir(parents=True)
        (self.section / ".build-started").write_text("started\n", encoding="utf-8")
        (self.section / "public" / "index.html").write_text("<html></html>", encoding="utf-8")
        (self.section / ".built-with-toolchain").write_text(THIS_TOOLCHAIN + "\n", encoding="utf-8")
        work = self.tmp / "work"
        (work / "C" / "section1").mkdir(parents=True)
        # The address is the site's, in the BUILD's folder only, where
        # build_site.py writes it.
        (work / "C" / "section1" / "quartz.config.ts").write_text(
            'baseUrl: "example.pages.dev",\n', encoding="utf-8")
        time.sleep(0.02)
        for patch in (
            mock.patch.object(toolchain_paths, "WORK_DIR", work),
            mock.patch.object(toolchain_paths, "COURSES_DIR", courses),
            mock.patch.dict(os.environ, {toolchain_paths.TOOLCHAIN_ID_VARIABLE: THIS_TOOLCHAIN}),
        ):
            patch.start()
            self.addCleanup(patch.stop)
        os.environ.pop(self.deploy.PAGES_ALREADY_ASKED_VARIABLE, None)
        self.rebuilds = []
        rebuild = mock.patch.object(self.deploy, "rebuild_for_production",
                                    lambda *arguments: self.rebuilds.append(arguments))
        rebuild.start()
        self.addCleanup(rebuild.stop)

    def _deploy(self) -> str:
        said = io.StringIO()
        with redirect_stdout(said):
            self.deploy.ensure_base_url_and_rebuild(self.section, "https://example.pages.dev/", "C", "1", "windows")
        return said.getvalue()

    def test_a_current_build_in_the_work_folder_is_reused(self):
        """#768: the literal /tmp/quartz-builds never matched on Windows, so
        every Netlify and Cloudflare deploy there built again."""
        said = self._deploy()
        self.assertEqual(self.rebuilds, [], said)

    def test_an_edit_builds_once_with_the_pages_words(self):
        with open(self.course / "notes" / "day-1.md", "a", encoding="utf-8") as handle:
            handle.write("edited\n")
        said = self._deploy()
        self.assertEqual(len(self.rebuilds), 1)
        self.assertIn(self.deploy.SAY_SOMETHING_CHANGED_SINCE_THE_BUILD, said)

    def test_a_deletion_builds_once(self):
        os.remove(self.course / "notes" / "day-1.md")
        self._deploy()
        self.assertEqual(len(self.rebuilds), 1)

    def test_an_earlier_version_and_an_edit_build_once_for_the_update(self):
        (self.section / ".built-with-toolchain").write_text(ANOTHER_TOOLCHAIN + "\n", encoding="utf-8")
        with open(self.course / "notes" / "day-1.md", "a", encoding="utf-8") as handle:
            handle.write("edited\n")
        said = self._deploy()
        self.assertEqual(len(self.rebuilds), 1)
        self.assertIn(self.deploy.SAY_BUILT_BY_AN_EARLIER_VERSION, said)
        self.assertNotIn(self.deploy.SAY_SOMETHING_CHANGED_SINCE_THE_BUILD, said)

    def test_a_build_dated_later_than_now_builds(self):
        later = time.time_ns() + 3600 * 1_000_000_000
        for dated in (self.section / ".build-started", self.section / "public" / "index.html"):
            os.utime(dated, ns=(later, later))
        said = self._deploy()
        self.assertEqual(len(self.rebuilds), 1)
        self.assertIn(self.deploy.SAY_THE_BUILD_IS_DATED_LATER_THAN_NOW, said)

    def test_the_pages_are_left_to_deploy_sh_when_it_asked(self):
        """deploy.sh sets the variable on its docker exec: the website
        builder's clock is a second clock, so the backstop does not ask."""
        with open(self.course / "notes" / "day-1.md", "a", encoding="utf-8") as handle:
            handle.write("edited\n")
        with mock.patch.dict(os.environ, {self.deploy.PAGES_ALREADY_ASKED_VARIABLE: "1"}):
            self._deploy()
        self.assertEqual(self.rebuilds, [])

    def test_the_toolchain_is_still_asked_when_deploy_sh_asked_the_pages(self):
        (self.section / ".built-with-toolchain").write_text(ANOTHER_TOOLCHAIN + "\n", encoding="utf-8")
        with mock.patch.dict(os.environ, {self.deploy.PAGES_ALREADY_ASKED_VARIABLE: "1"}):
            self._deploy()
        self.assertEqual(len(self.rebuilds), 1)

    def test_deploy_sh_sets_the_variable_on_its_docker_exec(self):
        text = (REPOSITORY_ROOT / "deploy.sh").read_text(encoding="utf-8")
        self.assertIn("  -e PLANTOIR_PAGES_ALREADY_ASKED=1 \\\n", text)
        self.assertEqual(self.deploy.PAGES_ALREADY_ASKED_VARIABLE, "PLANTOIR_PAGES_ALREADY_ASKED")

    def test_the_build_folder_is_not_a_literal(self):
        source = (REPOSITORY_ROOT / "scripts" / "deploy.py").read_text(encoding="utf-8")
        self.assertNotIn('Path(f"/tmp/quartz-builds/', source)


class TheNewLinesCarryNoWindowsAnchor(unittest.TestCase):
    """windows-app's LauncherRulesContractTests.TheRebuildLinesAreDeploySHsWordForWord
    takes every deploy.sh echo holding one of its anchors and requires them to
    be ONE line (Distinct().Single()). Its deploy.sh half, run here, so the
    mac cannot turn the Windows suite red with a new rebuild line."""

    def test_each_anchor_is_one_line_in_deploy_sh(self):
        test_file = REPOSITORY_ROOT / "windows-app" / "Plantoir.Tests" / "LauncherRulesContractTests.cs"
        source = test_file.read_text(encoding="utf-8")
        start = source.index("public void TheRebuildLinesAreDeploySHsWordForWord")
        anchors = re.findall(r'\[InlineData\("([^"]+)"\)\]', source[max(0, start - 1200):start])
        self.assertGreaterEqual(len(anchors), 7, anchors)
        lines = (REPOSITORY_ROOT / "deploy.sh").read_text(encoding="utf-8").splitlines()
        for anchor in anchors:
            with self.subTest(anchor=anchor):
                echoed = set()
                for line in lines:
                    stripped = line.strip()
                    if stripped.startswith("echo ") and anchor in stripped:
                        echoed.add(stripped[stripped.index('"') + 1:stripped.rindex('"')])
                self.assertEqual(len(echoed), 1, echoed)


if __name__ == "__main__":
    unittest.main()
