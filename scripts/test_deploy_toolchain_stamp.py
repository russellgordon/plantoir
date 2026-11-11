#!/usr/bin/env python3
"""
A site an earlier version of Plantoir built is built again before it is
deployed — GitHub issue #746.

1.9.1's tick-box rule (#693) and quiz print rule (#733) were in the app, in
the working folder's `.toolchain` and in a freshly tagged image, and a section
redeployed under 1.9.1 still served 1.9.0's stylesheet: its pages had not
changed, so the deploy found the site up to date, and the one rebuild it made
ran in the folder's old workspace. Measured, with the fix and what was
rejected, in documentation/05-build-pipeline.md -> "Which toolchain built a
site (#746)".

Pinned here, each part measured failing on the code before the fix:

  * **deploy.sh** compares the stamp beside the built site with the image it
    would use, and builds first (`preview.sh --build-only`, the same image)
    when they differ or there is no stamp. Its comparison is cut out of the
    launcher and run; and the real launcher, copied into a scratch working
    folder, is run publishing to a folder, with a stand-in `preview.sh` that
    records that it was asked and builds a "new" site.
  * **build_site.py** stamps the site with the toolchain it STARTED with, and
    only when the site on the host is that build's (a preview leaves it alone).
  * **deploy.py** builds again, once, when the stamp is not its own
    toolchain's — with or without a site address to compare.
  * **toolchain_paths** names the toolchain: the launcher's name when it
    gives one, otherwise a hash of the files the scripts read that changes
    with a stylesheet and not with Python's caches.

Pure stdlib, no Docker, no network. Run with:

    python3 scripts/test_deploy_toolchain_stamp.py
"""

import os
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPOSITORY_ROOT / "scripts"))

os.environ.setdefault("PLANTOIR_CONTRACTS_DIR", str(REPOSITORY_ROOT / "contracts"))

import toolchain_paths  # noqa: E402

MARKER = ".built-with-toolchain"
IMAGE = "teaching-quartz:src-1a2b3c4d"
OLD_PAGE = "<html>built by 1.9.0</html>"
NEW_PAGE = "<html>built by this version</html>"


def _bash_can_reach_a_scratch_folder() -> bool:
    """As test_deploy_folder_target.py asks: a Windows `bash` from WSL cannot
    open a Windows temporary path, and these must skip there, not fail."""
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


def _the_launchers_comparison() -> str:
    text = (REPOSITORY_ROOT / "deploy.sh").read_text(encoding="utf-8")
    begin = "# BEGIN site_was_built_by_this_toolchain\n"
    end = "# END site_was_built_by_this_toolchain\n"
    if begin not in text or end not in text:
        raise AssertionError("deploy.sh has no site_was_built_by_this_toolchain between its markers")
    return text[text.index(begin) + len(begin):text.index(end)]


@unittest.skipUnless(HAS_BASH, "needs a bash that can reach a scratch folder")
class TheLaunchersComparison(unittest.TestCase):
    """deploy.sh's own definition, cut out and run."""

    def _matches(self, stamp, image: str = IMAGE) -> bool:
        with tempfile.TemporaryDirectory() as tmp:
            if stamp is not None:
                Path(tmp, MARKER).write_text(stamp, encoding="utf-8")
            script = _the_launchers_comparison() + '\nsite_was_built_by_this_toolchain "$1" "$2"\n'
            result = subprocess.run(["bash", "-c", script, "_", tmp, image],
                                    capture_output=True, timeout=60)
            return result.returncode == 0

    def test_the_same_image_matches(self):
        self.assertTrue(self._matches(IMAGE + "\n"))

    def test_another_image_does_not(self):
        self.assertFalse(self._matches("teaching-quartz:src-9fd16022\n"))

    def test_no_stamp_does_not(self):
        # Every site built before 1.9.2: built again once.
        self.assertFalse(self._matches(None))

    def test_an_empty_stamp_does_not(self):
        self.assertFalse(self._matches("\n"))

    def test_an_empty_image_never_matches_an_empty_stamp(self):
        self.assertFalse(self._matches("", image=""))

    def test_the_ends_are_trimmed_as_python_trims_them(self):
        self.assertTrue(self._matches("  " + IMAGE + "\r\n\n"))
        stamp = "teaching-quartz:src 1a2b"
        self.assertFalse(self._matches(stamp + "\n", image="teaching-quartz:src1a2b"))
        with tempfile.TemporaryDirectory() as tmp:
            Path(tmp, MARKER).write_text(stamp + "\n", encoding="utf-8")
            self.assertEqual(toolchain_paths.toolchain_that_built(Path(tmp)), stamp)
        self.assertTrue(self._matches(stamp + "\n", image=stamp))

    @unittest.skipIf(hasattr(os, "geteuid") and os.geteuid() == 0, "root reads everything")
    def test_an_unreadable_stamp_is_a_quiet_rebuild(self):
        with tempfile.TemporaryDirectory() as tmp:
            marker = Path(tmp, MARKER)
            marker.write_text(IMAGE + "\n", encoding="utf-8")
            marker.chmod(0)
            try:
                script = _the_launchers_comparison() + '\nsite_was_built_by_this_toolchain "$1" "$2"\n'
                result = subprocess.run(["bash", "-c", script, "_", tmp, IMAGE],
                                        capture_output=True, timeout=60)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout + result.stderr, b"", "printed something")
                self.assertIsNone(toolchain_paths.toolchain_that_built(Path(tmp)))
            finally:
                marker.chmod(0o644)


class EveryWorkspaceCarriesItsImagesName(unittest.TestCase):
    """The name every build in a workspace stamps its site with is the image
    the workspace was made from - set when it is made, by all three
    launchers (their PREVIEW PORT BLOCKs are identical, test_port_blocks.py)."""

    def test_each_launcher_makes_its_workspace_with_the_name(self):
        for launcher in ("setup.sh", "preview.sh", "deploy.sh"):
            text = (REPOSITORY_ROOT / launcher).read_text(encoding="utf-8")
            start = text.index("create_the_workspace_on_free_ports() {")
            run = text.index("docker run -dit", start)
            image = text.index('"$IMAGE" \\\n', run)
            self.assertIn('-e "PLANTOIR_TOOLCHAIN_ID=$IMAGE"', text[run:image], launcher)


STAND_IN_PREVIEW = """#!/bin/bash
# Stands in for preview.sh: notes how it was asked, then builds "this
# version's" site into the section's build folder, stamped as the real one is.
printf '%s\\n' "$*" >> "$PWD/preview-was-asked"
built="$PWD/courses/ICS4U/.merged_output/section1"
printf '%s' '{new_page}' > "$built/public/index.html"
printf '%s\\n' '{image}' > "$built/.built-with-toolchain"
""".format(new_page=NEW_PAGE, image=IMAGE)


@unittest.skipUnless(HAS_BASH and HAS_RSYNC, "needs bash and rsync")
@unittest.skipIf(sys.platform == "win32", "deploy.sh is the mac's launcher")
class TheRealLauncherPublishingToAFolder(unittest.TestCase):
    """deploy.sh itself: a stale stamp builds first, a current one does not."""

    def _publish(self, stamp):
        tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, tmp, True)
        folder = Path(tmp) / "work"
        folder.mkdir()
        shutil.copy2(REPOSITORY_ROOT / "deploy.sh", folder / "deploy.sh")
        preview = folder / "preview.sh"
        preview.write_text(STAND_IN_PREVIEW, encoding="utf-8")
        preview.chmod(preview.stat().st_mode | stat.S_IXUSR)
        course = folder / "courses" / "ICS4U"
        built = course / ".merged_output" / "section1" / "public"
        built.mkdir(parents=True)
        (course / "course_config.json").write_text(
            '{"course_code": "ICS4U", "section_numbers": [1], "num_sections": 1}', encoding="utf-8")
        (built / "index.html").write_text(OLD_PAGE, encoding="utf-8")
        if stamp is not None:
            (built.parent / MARKER).write_text(stamp, encoding="utf-8")
        environment = dict(os.environ)
        environment["HOME"] = str(folder / "home")
        environment.pop("PLANTOIR_TRAIL_DIR", None)
        environment.pop("PWD", None)
        environment["RSYNC_RSH"] = "false"
        (folder / "home").mkdir()
        target = Path(tmp) / "published"
        result = subprocess.run(
            ["bash", "./deploy.sh", "ICS4U", "1", "--to-folder", str(target),
             "--non-interactive", "--image", IMAGE],
            cwd=str(folder), capture_output=True, timeout=180, env=environment,
        )
        output = (result.stdout + result.stderr).decode("utf-8", "replace")
        asked_file = folder / "preview-was-asked"
        asked = asked_file.read_text(encoding="utf-8") if asked_file.exists() else ""
        page_file = target / "section1" / "index.html"
        page = page_file.read_text(encoding="utf-8") if page_file.exists() else ""
        return result.returncode, output, asked, page

    def test_a_site_an_earlier_version_built_is_built_again_first(self):
        code, output, asked, page = self._publish("teaching-quartz:src-9fd16022\n")
        self.assertEqual(code, 0, output)
        self.assertIn("ICS4U 1 --build-only", asked, output)
        # The same image the deploy compares with, and nobody to ask.
        self.assertIn("--non-interactive", asked)
        self.assertIn("--image " + IMAGE, asked)
        self.assertEqual(page, NEW_PAGE, "the folder got the site the earlier version built")

    def test_a_site_with_no_stamp_is_built_again_first(self):
        code, output, asked, page = self._publish(None)
        self.assertEqual(code, 0, output)
        self.assertIn("--build-only", asked, output)
        self.assertEqual(page, NEW_PAGE)

    def test_a_site_this_version_built_is_published_as_it_is(self):
        code, output, asked, page = self._publish(IMAGE + "\n")
        self.assertEqual(code, 0, output)
        self.assertEqual(asked, "", "built again although this version built it")
        self.assertEqual(page, OLD_PAGE)


class WhichToolchainThisIs(unittest.TestCase):
    """toolchain_paths' name for the toolchain, and the stamp it reads and writes."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        for name in ("scripts", "support/quartz/components/styles", "contracts", "quartz/quartz"):
            (self.tmp / name).mkdir(parents=True)
        (self.tmp / "scripts" / "build_site.py").write_text("print('build')\n", encoding="utf-8")
        self.style = self.tmp / "support" / "quartz" / "components" / "styles" / "tasks.scss"
        self.style.write_text("vertical-align: baseline;\n", encoding="utf-8")
        (self.tmp / "contracts" / "app-rules.json").write_text("{}\n", encoding="utf-8")
        (self.tmp / "quartz" / "quartz" / "build.ts").write_text("// build\n", encoding="utf-8")
        patches = [
            mock.patch.object(toolchain_paths, "SCRIPTS_DIR", self.tmp / "scripts"),
            mock.patch.object(toolchain_paths, "SUPPORT_DIR", self.tmp / "support"),
            mock.patch.object(toolchain_paths, "CONTRACTS_DIR", self.tmp / "contracts"),
            mock.patch.object(toolchain_paths, "QUARTZ_DIR", self.tmp / "quartz"),
            mock.patch.dict(os.environ, {}, clear=False),
        ]
        for patch in patches:
            patch.start()
            self.addCleanup(patch.stop)
        os.environ.pop(toolchain_paths.TOOLCHAIN_ID_VARIABLE, None)
        # No cache unless a test asks for one (the native Windows run sets it).
        os.environ.pop("PLANTOIR_BUILD_ROOT", None)

    # ---- #749: the runtime is part of the toolchain, and the id is remembered

    def _age_everything(self, seconds_ago=600):
        """Files written just now are 'racy' and never cached; set them back."""
        moment = time.time() - seconds_ago
        for folder, _subfolders, files in os.walk(self.tmp):
            for name in files:
                os.utime(os.path.join(folder, name), (moment, moment))

    def _use_a_cache(self):
        build_root = self.tmp / "builds"
        build_root.mkdir()
        os.environ["PLANTOIR_BUILD_ROOT"] = str(build_root)
        return build_root / toolchain_paths.TOOLCHAIN_ID_CACHE_NAME

    def _uncached_id(self):
        saved = os.environ.pop("PLANTOIR_BUILD_ROOT", None)
        try:
            return toolchain_paths.current_toolchain_id()
        finally:
            if saved is not None:
                os.environ["PLANTOIR_BUILD_ROOT"] = saved

    def test_the_runtimes_manifest_is_part_of_the_toolchain(self):
        without = toolchain_paths.current_toolchain_id()
        self.assertEqual(without, toolchain_paths.current_toolchain_id(), "no manifest is not stable")
        manifest = self.tmp / "manifest.json"
        manifest.write_text('{"python": "3.14.9"}\n', encoding="utf-8")
        with_one = toolchain_paths.current_toolchain_id()
        self.assertNotEqual(without, with_one, "a runtime manifest changed nothing")
        manifest.write_text('{"python": "3.14.10"}\n', encoding="utf-8")
        self.assertNotEqual(with_one, toolchain_paths.current_toolchain_id(),
                            "a runtime-only change (a new Python) did not change the toolchain")

    def test_the_remembered_id_is_used_while_nothing_has_changed(self):
        cache = self._use_a_cache()
        self._age_everything()
        first = toolchain_paths.current_toolchain_id()
        self.assertTrue(cache.is_file(), "the id was not remembered")
        self.assertEqual(first, self._uncached_id())
        with mock.patch.object(toolchain_paths, "_hash_of_the_contents",
                               side_effect=AssertionError("read every file although nothing changed")):
            self.assertEqual(first, toolchain_paths.current_toolchain_id())

    def test_an_edited_file_is_worked_out_again(self):
        self._use_a_cache()
        self._age_everything()
        before = toolchain_paths.current_toolchain_id()
        self.style.write_text("vertical-align: calc(0.5cap - 8px);\n", encoding="utf-8")
        self._age_everything(seconds_ago=300)
        after = toolchain_paths.current_toolchain_id()
        self.assertNotEqual(before, after, "the remembered id outlived an edit")
        self.assertEqual(after, self._uncached_id())

    def test_the_same_size_and_a_new_time_is_worked_out_again(self):
        self._use_a_cache()
        self._age_everything()
        before = toolchain_paths.current_toolchain_id()
        self.style.write_text("vertical-align: BASELINE;\n", encoding="utf-8")  # same length
        self._age_everything(seconds_ago=300)
        self.assertNotEqual(before, toolchain_paths.current_toolchain_id())

    def test_a_new_runtime_is_worked_out_again(self):
        self._use_a_cache()
        manifest = self.tmp / "manifest.json"
        manifest.write_text('{"python": "3.14.9"}\n', encoding="utf-8")
        self._age_everything()
        before = toolchain_paths.current_toolchain_id()
        manifest.write_text('{"python": "3.14.10"}\n', encoding="utf-8")
        self._age_everything(seconds_ago=300)
        self.assertNotEqual(before, toolchain_paths.current_toolchain_id())

    def test_a_file_changed_just_now_is_not_remembered(self):
        cache = self._use_a_cache()
        # Written in setUp a moment ago: within the racy window.
        toolchain_paths.current_toolchain_id()
        self.assertFalse(cache.exists(), "remembered an id for a file changed this instant")

    def test_a_cache_that_cannot_be_read_is_worked_out_again(self):
        cache = self._use_a_cache()
        self._age_everything()
        cache.write_bytes(b"\xff\xfe not a cache\n")
        self.assertEqual(toolchain_paths.current_toolchain_id(), self._uncached_id())
        cache.write_text(toolchain_paths._fingerprint_of(toolchain_paths._the_toolchain_files())
                         + "\nnot-an-id\n", encoding="utf-8")
        self.assertEqual(toolchain_paths.current_toolchain_id(), self._uncached_id())

    def test_a_cache_for_another_folder_is_not_used(self):
        cache = self._use_a_cache()
        self._age_everything()
        toolchain_paths.current_toolchain_id()
        lines = cache.read_text(encoding="utf-8").splitlines()
        cache.write_text(lines[0] + "\nfiles-0000000000000000\n", encoding="utf-8")
        self.assertEqual(toolchain_paths.current_toolchain_id(), "files-0000000000000000",
                         "the forged entry is not even read, so the next check proves nothing")
        moved = mock.patch.object(toolchain_paths, "SCRIPTS_DIR", self.tmp / "elsewhere" / "scripts")
        # copytree keeps every file's size and time, so only the folder differs.
        shutil.copytree(self.tmp / "scripts", self.tmp / "elsewhere" / "scripts")
        with moved:
            self.assertNotEqual(toolchain_paths.current_toolchain_id(), "files-0000000000000000",
                                "a remembered id was used for scripts in another folder")

    def test_a_cache_that_cannot_be_written_changes_nothing(self):
        cache = self._use_a_cache()
        self._age_everything()
        with mock.patch.object(toolchain_paths.os, "replace", side_effect=PermissionError("in use")):
            identity = toolchain_paths.current_toolchain_id()
        self.assertEqual(identity, self._uncached_id())
        self.assertFalse(cache.exists())
        self.assertEqual(list(cache.parent.glob("*.tmp")), [], "left its temporary file behind")

    def test_the_cache_is_never_used_without_a_build_root(self):
        # The container's case: no PLANTOIR_BUILD_ROOT, so every call reads
        # the files, and a forged cache where one would be is never consulted.
        self._age_everything()
        self.assertIsNone(toolchain_paths._toolchain_id_cache())
        with mock.patch.object(toolchain_paths, "_read_cached_id",
                               side_effect=AssertionError("consulted a cache in the container")):
            toolchain_paths.current_toolchain_id()

    def test_the_launchers_name_wins_when_it_gives_one(self):
        os.environ[toolchain_paths.TOOLCHAIN_ID_VARIABLE] = IMAGE
        self.assertEqual(toolchain_paths.current_toolchain_id(), IMAGE)

    def test_a_changed_stylesheet_is_a_different_toolchain(self):
        before = toolchain_paths.current_toolchain_id()
        self.assertEqual(before, toolchain_paths.current_toolchain_id(), "not stable")
        self.style.write_text("vertical-align: calc(0.5cap - 8px);\n", encoding="utf-8")
        self.assertNotEqual(before, toolchain_paths.current_toolchain_id())

    def test_pythons_caches_are_not_the_toolchain(self):
        before = toolchain_paths.current_toolchain_id()
        cache = self.tmp / "scripts" / "__pycache__"
        cache.mkdir()
        (cache / "build_site.cpython-314.pyc").write_bytes(b"\x00compiled")
        (self.tmp / "support" / "stray.pyc").write_bytes(b"\x00compiled")
        (self.tmp / "support" / ".DS_Store").write_bytes(b"finder")
        self.assertEqual(before, toolchain_paths.current_toolchain_id())

    def test_the_stamp_is_read_back_as_written(self):
        section = self.tmp / "section1"
        section.mkdir()
        self.assertFalse(toolchain_paths.site_was_built_by_this_toolchain(section, IMAGE))
        toolchain_paths.note_the_toolchain_that_built(section, IMAGE)
        self.assertEqual((section / MARKER).read_text(encoding="utf-8"), IMAGE + "\n")
        self.assertTrue(toolchain_paths.site_was_built_by_this_toolchain(section, IMAGE))
        self.assertFalse(toolchain_paths.site_was_built_by_this_toolchain(section, "another"))

    def test_a_stamp_that_could_not_be_written_leaves_none_behind(self):
        section = self.tmp / "section1"
        section.mkdir()
        (section / MARKER).write_text("teaching-quartz:src-old\n", encoding="utf-8")
        with mock.patch.object(toolchain_paths.os, "replace", side_effect=OSError("disk full")):
            toolchain_paths.note_the_toolchain_that_built(section, IMAGE)
        self.assertFalse((section / MARKER).exists(), "an old stamp survived a failed write")


class TheBuildStampsItsSite(unittest.TestCase):
    """build_site.py: the toolchain it started with, once the site is its own."""

    @classmethod
    def setUpClass(cls):
        import build_site
        cls.build_site = build_site

    def setUp(self):
        self.section = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.section, True)
        saved = self.build_site._this_build_toolchain
        self.addCleanup(setattr, self.build_site, "_this_build_toolchain", saved)

    def test_a_finished_build_stamps_the_toolchain_it_started_with(self):
        self.build_site._mark_build_starting(self.section)
        self.build_site._this_build_toolchain = IMAGE
        self.build_site._mark_build_finished(self.section)
        self.assertEqual((self.section / MARKER).read_text(encoding="utf-8"), IMAGE + "\n")

    def test_a_build_that_did_not_finish_leaves_the_old_stamp(self):
        # No pending marker: a preview, or a build that failed, never got here.
        (self.section / MARKER).write_text("teaching-quartz:src-old\n", encoding="utf-8")
        self.build_site._this_build_toolchain = IMAGE
        self.build_site._mark_build_finished(self.section)
        self.assertEqual((self.section / MARKER).read_text(encoding="utf-8"), "teaching-quartz:src-old\n")

    def test_the_build_reads_the_toolchain_when_it_starts(self):
        source = (REPOSITORY_ROOT / "scripts" / "build_site.py").read_text(encoding="utf-8")
        start = source.index("    _mark_build_starting(host_output_dir)\n")
        reading = source.index("_this_build_toolchain = toolchain_paths.current_toolchain_id()")
        reading_the_settings = source.index("with open(config_file, \"r\", encoding=\"utf-8\") as f:", start)
        self.assertLess(start, reading)
        self.assertLess(reading, reading_the_settings, "read after the build began reading the course")


class TheDeployBuildsAgainOnce(unittest.TestCase):
    """deploy.py's one rebuild decision for Netlify and Cloudflare."""

    @classmethod
    def setUpClass(cls):
        import deploy
        cls.deploy = deploy

    def setUp(self):
        self.section = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.section, True)
        # A workspace whose address is already the site's, so only the
        # toolchain can ask for a build.
        (self.section / "quartz.config.ts").write_text('baseUrl: "example.pages.dev",\n', encoding="utf-8")
        environment = mock.patch.dict(os.environ, {toolchain_paths.TOOLCHAIN_ID_VARIABLE: IMAGE})
        environment.start()
        self.addCleanup(environment.stop)
        self.rebuilds = []
        rebuild = mock.patch.object(self.deploy, "rebuild_for_production",
                                    lambda *arguments: self.rebuilds.append(arguments))
        rebuild.start()
        self.addCleanup(rebuild.stop)

    def _stamp(self, text):
        (self.section / MARKER).write_text(text, encoding="utf-8")

    def test_a_site_an_earlier_version_built_is_built_again(self):
        self._stamp("teaching-quartz:src-9fd16022\n")
        self.deploy.ensure_base_url_and_rebuild(self.section, "https://example.pages.dev/", "ICS3U", "1", "mac")
        self.assertEqual(len(self.rebuilds), 1)

    def test_a_site_with_no_stamp_is_built_again(self):
        self.deploy.ensure_base_url_and_rebuild(self.section, "example.pages.dev", "ICS3U", "1", "mac")
        self.assertEqual(len(self.rebuilds), 1)

    def test_a_site_this_version_built_is_not(self):
        self._stamp(IMAGE + "\n")
        self.deploy.ensure_base_url_and_rebuild(self.section, "example.pages.dev", "ICS3U", "1", "mac")
        self.assertEqual(self.rebuilds, [])

    def test_no_address_still_asks_about_the_toolchain(self):
        self._stamp("teaching-quartz:src-9fd16022\n")
        self.deploy.ensure_base_url_and_rebuild(self.section, "", "ICS3U", "1", "mac")
        self.assertEqual(len(self.rebuilds), 1)

    def test_a_new_address_and_an_old_toolchain_build_once(self):
        self._stamp("teaching-quartz:src-9fd16022\n")
        self.deploy.ensure_base_url_and_rebuild(self.section, "another.pages.dev", "ICS3U", "1", "mac")
        self.assertEqual(len(self.rebuilds), 1)

    def test_netlify_asks_even_without_an_address(self):
        source = (REPOSITORY_ROOT / "scripts" / "deploy.py").read_text(encoding="utf-8")
        self.assertNotIn("    if target_domain:\n        ensure_base_url_and_rebuild(", source)


if __name__ == "__main__":
    unittest.main()
