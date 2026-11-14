#!/usr/bin/env python3
"""
A built site carries only the files its published pages use (#901): the
check after the build, scripts/site_files.py, run against every case in
contracts/shared-rules.json -> siteFiles it can read without Quartz.

* `slugCases` through slugify_file_path (Quartz's slugifyFilePath, ported;
  the image runs the same cases through Quartz's own function in
  check_site_files_rules_against_the_site.py, so the two cannot drift);
* `resolveCases` through resolved_from_page (the image runs them through
  siteFilesRules.resolvedFromPage);
* `checkCases`: each a built site and its content/ written to a temporary
  folder, the check run with repair on, and the counts and the files left
  as the case says;
* what a teacher reads and when (siteFiles.whenSaid), the marker
  (siteFiles.marker: counts only, never a file's name), the record
  (file-formats.json -> siteFilesRecord) and the side file;
* the deploy's build: the check before the mirror, and a check that fails
  leaves the build unmarked (plan review 901-3).

`cases`, which need Quartz's parser and transformers, are run in the image
by check_site_files_rules_against_the_site.py.
"""
import contextlib
import io
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

scripts_dir = Path(__file__).resolve().parent
sys.path.insert(0, str(scripts_dir))

import contracts  # noqa: E402
import site_files  # noqa: E402
import toolchain_paths  # noqa: E402

# The repository's contract, as every shared test reads it outside the image.
if (scripts_dir.parent / "contracts").is_dir():
    toolchain_paths.CONTRACTS_DIR = scripts_dir.parent / "contracts"
    contracts.reset_cache()

RULES = contracts.section("shared-rules", "siteFiles")


def write_tree(root: Path, files) -> None:
    if isinstance(files, dict):
        items = files.items()
    else:
        items = [(name, "x") for name in files]
    for name, text in items:
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")


class TheRulesAreQuartzs(unittest.TestCase):

    def test_every_slug_case(self):
        for path, slug in RULES["slugCases"]:
            with self.subTest(path=path):
                self.assertEqual(site_files.slugify_file_path(path), slug)

    def test_every_resolve_case(self):
        for page, address, resolved in RULES["resolveCases"]:
            with self.subTest(page=page, address=address):
                self.assertEqual(site_files.resolved_from_page(page, address), resolved)

    def test_a_page_is_served_at_its_name_without_html(self):
        self.assertEqual(site_files.page_slug_of("Unit-1/Day-1.html"), "Unit-1/Day-1")
        self.assertEqual(site_files.page_slug_of("index.html"), "index")


class TheCheck(unittest.TestCase):

    def setUp(self):
        self.temporary = Path(tempfile.mkdtemp(prefix="plantoir-site-files-"))

    def tearDown(self):
        shutil.rmtree(self.temporary, ignore_errors=True)

    def test_every_check_case(self):
        self.assertGreaterEqual(len(RULES["checkCases"]), 10)
        for number, case in enumerate(RULES["checkCases"]):
            with self.subTest(case=case["name"]):
                root = self.temporary / f"case{number}"
                public, content = root / "public", root / "content"
                write_tree(public, case["public"])
                write_tree(content, case["content"])
                public.mkdir(parents=True, exist_ok=True)
                outcome = site_files.check(public, content, repair=True,
                                           emitter=case.get("emitter", "plantoir"))
                for key, value in case["expect"].items():
                    self.assertEqual(outcome[key], value, key)
                for address in case["present"]:
                    self.assertTrue((public / address).is_file(), address + " should be on the site")
                for address in case["absent"]:
                    self.assertFalse((public / address).exists(), address + " should not be on the site")
                # A second check of the repaired site finds nothing to do.
                again = site_files.check(public, content, repair=False,
                                         emitter=case.get("emitter", "plantoir"))
                self.assertEqual(again["putBack"], 0)
                if case.get("emitter", "plantoir") == "quartz":
                    self.assertEqual(again["unreferenced"], 0)

    def test_a_check_without_repair_changes_nothing(self):
        public, content = self.temporary / "public", self.temporary / "content"
        write_tree(public, {"index.html": '<img src="Media/a.png">', "Media/b.png": "b"})
        write_tree(content, ["Media/a.png", "Media/b.png"])
        outcome = site_files.check(public, content, repair=False)
        self.assertEqual((outcome["putBack"], outcome["unreferenced"], outcome["takenOut"]), (1, 1, 1))
        self.assertFalse((public / "Media/a.png").exists())
        self.assertTrue((public / "Media/b.png").exists())

    def test_a_file_that_cannot_be_put_back_is_said_as_failed(self):
        public, content = self.temporary / "public", self.temporary / "content"
        write_tree(public, {"index.html": '<img src="Media/a.png">'})
        write_tree(content, ["Media/a.png"])
        # A folder where the file must go makes the copy fail.
        (public / "Media" / "a.png").mkdir(parents=True)
        outcome = site_files.check(public, content, repair=True)
        self.assertEqual((outcome["putBack"], outcome["putBackFailed"]), (0, 1))
        self.assertEqual(outcome["putBackFailedFiles"], ["Media/a.png"])

    def test_media_reached_through_a_link_is_read(self):
        """content/Media is a symbolic link on a Mac."""
        public, content = self.temporary / "public", self.temporary / "content"
        media = self.temporary / "course" / "Media"
        write_tree(media, ["pic.png", "unused.png"])
        content.mkdir()
        (content / "Media").symlink_to(media, target_is_directory=True)
        write_tree(public, {"index.html": '<img src="./Media/pic.png">'})
        outcome = site_files.check(public, content, repair=True)
        self.assertEqual((outcome["carried"], outcome["leftOff"], outcome["putBack"]), (1, 1, 1))

    def test_the_reader_reads_every_way_a_case_names(self):
        html = ('<img src="a.png" srcset="b.png 1x, c.png 2x"><video poster="d.png"><source src="e.mp4">'
                '<track src="f.vtt"></video><object data="g.pdf"></object><embed src="h.pdf">'
                '<svg><image href="i.png"></image></svg><div style="background:url(\'j.png\')"></div>'
                '<style>p { background: url(k.png) }</style>'
                '<figure data-geogebra="{&quot;sketch&quot;:&quot;Media/l.ggb&quot;,&quot;root&quot;:&quot;..&quot;}"></figure>')
        found = set(site_files.addresses_in_html(html))
        for name in ("a.png", "b.png", "c.png", "d.png", "e.mp4", "f.vtt", "g.pdf", "h.pdf", "i.png",
                     "j.png", "k.png", "../Media/l.ggb"):
            self.assertIn(name, found)


class WhatIsSaid(unittest.TestCase):

    OUTCOME = {"carried": 3, "leftOff": 2, "leftOffBytes": 2_400_000, "putBack": 0, "putBackFailed": 0,
               "takenOut": 0, "unreferenced": 0, "putBackFiles": [], "putBackFailedFiles": []}

    def test_the_first_build_says_once_in_its_own_words(self):
        words = RULES["words"]
        deploy = site_files.lines_to_say(self.OUTCOME, None, mode="deploy", section=2)
        self.assertEqual(deploy, [words["firstTimeDeploy"].replace("{count}", "2").replace("{files}", "files")
                                  .replace("{size}", "2.4 MB").replace("{section}", "2")])
        preview = site_files.lines_to_say(self.OUTCOME, None, mode="preview", section=2)
        self.assertEqual(len(preview), 1)
        self.assertTrue(preview[0].startswith(words["firstTimePreview"].split("{count}")[0]))

    def test_the_same_count_says_nothing_and_a_new_count_says_it(self):
        self.assertEqual(site_files.lines_to_say(self.OUTCOME, {"leftOff": 2}, mode="deploy", section=1), [])
        changed = site_files.lines_to_say(self.OUTCOME, {"leftOff": 5}, mode="deploy", section=1)
        self.assertEqual(len(changed), 1)
        self.assertIn("2 files", changed[0])

    def test_nothing_left_off_on_the_first_build_says_nothing(self):
        outcome = dict(self.OUTCOME, leftOff=0, leftOffBytes=0)
        self.assertEqual(site_files.lines_to_say(outcome, None, mode="deploy", section=1), [])

    def test_one_file_and_a_put_back_file(self):
        outcome = dict(self.OUTCOME, leftOff=1, leftOffBytes=500, putBack=1, putBackFiles=["Media/a.png"])
        lines = site_files.lines_to_say(outcome, {"leftOff": 3}, mode="deploy", section=1)
        self.assertEqual(lines[0], RULES["words"]["putBack"].replace("{file}", "Media/a.png"))
        self.assertIn("1 file in this course (1 KB)", lines[1])

    def test_sizes(self):
        self.assertEqual(site_files.size_words(0), "1 KB")
        self.assertEqual(site_files.size_words(1_001), "2 KB")
        self.assertEqual(site_files.size_words(2_400_000), "2.4 MB")
        self.assertEqual(site_files.size_words(1_170_000_000), "1.2 GB")

    def test_the_marker_is_counts_only(self):
        outcome = dict(self.OUTCOME, putBack=1, putBackFiles=["Media/secret answers.pdf"])
        line = site_files.marker_line(outcome, {"leftOff": 2}, course="MCR3U", section=1, mode="deploy",
                                      emitter="plantoir")
        self.assertTrue(line.startswith(RULES["marker"]["prefix"] + " "))
        payload = json.loads(line[len(RULES["marker"]["prefix"]):])
        self.assertEqual(payload, {"course": "MCR3U", "section": 1, "mode": "deploy", "carried": 3, "leftOff": 2,
                                   "leftOffBytes": 2400000, "putBack": 1, "putBackFailed": 0, "takenOut": 0,
                                   "unreferenced": 0, "firstTime": False, "changed": False,
                                   "assetsEmitter": "plantoir"})
        self.assertNotIn("secret", line)
        for key in payload:
            self.assertIn(key, RULES["marker"]["rule"])

    def test_every_trail_case_is_the_line_the_build_prints(self):
        """The apps read these lines (SiteFilesReportTests on the Mac), so the
        build must print exactly them."""
        cases = RULES["marker"]["trailCases"]
        self.assertGreaterEqual(len(cases), 6)
        for case in cases:
            with self.subTest(case=case["name"]):
                line = site_files.marker_line(case["outcome"], case["previous"], course="SCH3U", section=2,
                                              mode=case["mode"], emitter=case["emitter"])
                self.assertEqual(line, case["line"])

    def test_the_record_keeps_every_key_the_format_names_and_nothing_else(self):
        folder = Path(tempfile.mkdtemp(prefix="plantoir-site-files-record-"))
        try:
            site_files.write_record(folder, dict(self.OUTCOME, putBackFiles=["Media/a.png"]), "b1")
            record = site_files.read_record(folder)
            keys = contracts.section("file-formats", "siteFilesRecord", "keys")
            self.assertEqual(set(record), set(keys))
            self.assertNotIn("Media/a.png", (folder / site_files.RECORD_NAME).read_text())
            (folder / site_files.RECORD_NAME).write_text("not json")
            self.assertIsNone(site_files.read_record(folder))
        finally:
            shutil.rmtree(folder, ignore_errors=True)

    def test_after_the_build_says_puts_back_prints_and_records(self):
        root = Path(tempfile.mkdtemp(prefix="plantoir-site-files-after-"))
        try:
            public, content, host = root / "public", root / "content", root / "host"
            write_tree(public, {"index.html": '<img src="Media/a.png">'})
            write_tree(content, ["Media/a.png", "Media/b.png"])
            said = []
            site_files.after_the_build(public, content, host, course="SBI4U", section=3, mode="deploy",
                                       emitter="plantoir", build_id="b7", printer=said.append)
            self.assertTrue((public / "Media/a.png").is_file())
            self.assertEqual(said[0], RULES["words"]["putBack"].replace("{file}", "Media/a.png"))
            self.assertTrue(said[1].startswith(RULES["words"]["firstTimeDeploy"][:40]))
            self.assertTrue(said[-1].startswith(RULES["marker"]["prefix"]))
            self.assertEqual(site_files.read_record(host)["buildId"], "b7")
            said.clear()
            site_files.after_the_build(public, content, host, course="SBI4U", section=3, mode="deploy",
                                       emitter="quartz", build_id="b8", printer=said.append)
            self.assertEqual(said[0], "plantoir: error: " + RULES["words"]["emitterNotSwapped"])
            self.assertEqual(len(said), 2, "the same count says nothing more")
        finally:
            shutil.rmtree(root, ignore_errors=True)

    def test_the_side_file_holds_the_footers_addresses(self):
        side = site_files.side_file('<a href="https://school.example"><img src="Media/logo.png" alt="Logo"></a>')
        self.assertEqual(side["alwaysCarried"], RULES["alwaysCarried"])
        self.assertIn("Media/logo.png", side["footerAddresses"])
        self.assertEqual(site_files.side_file("")["footerAddresses"], [])

    def test_the_constants_are_the_contracts(self):
        self.assertEqual(site_files.MARKER, RULES["marker"]["prefix"])
        self.assertEqual(site_files.DONE_MARKER, RULES["doneMarker"]["file"])
        self.assertEqual(list(site_files.ALWAYS_CARRIED), RULES["alwaysCarried"])
        self.assertEqual("quartz/" + site_files.SIDE_FILE, RULES["sideFile"]["file"])
        self.assertEqual(site_files.RECORD_NAME,
                         contracts.section("file-formats", "siteFilesRecord", "path").split("/")[1].split(",")[0])


class TheDeploysBuild(unittest.TestCase):
    """build_site._check_mirror_and_mark: the check first, then the mirror,
    then the mark; a check that fails leaves the build unmarked."""

    def setUp(self):
        import build_site
        self.build_site = build_site
        self.root = Path(tempfile.mkdtemp(prefix="plantoir-site-files-deploy-"))
        self.output = self.root / "work"
        self.host = self.root / "host"
        write_tree(self.output / "public", {"index.html": '<img src="Media/a.png">'})
        write_tree(self.output / "content", ["Media/a.png"])
        (self.output / "quartz.config.ts").write_text("Plugin.PlantoirAssets(),\n")
        write_tree(self.output / "quartz" / "plugins" / "emitters",
                   {"index.ts": 'export { PlantoirAssets } from "./plantoirAssets"\n'})
        self.host.mkdir()
        build_site._mark_build_starting(self.host)

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def test_a_checked_build_is_put_right_mirrored_and_marked(self):
        with contextlib.redirect_stdout(io.StringIO()) as said:
            mirrored = self.build_site._check_mirror_and_mark(self.output, self.host, "SBI4U", 1)
        self.assertTrue(mirrored)
        self.assertTrue((self.host / "public" / "Media" / "a.png").is_file(), "the put-back file reached the host")
        self.assertTrue((self.host / self.build_site.BUILD_STARTED_MARKER).exists())
        self.assertIn(site_files.MARKER, said.getvalue())
        self.assertIn('"assetsEmitter":"plantoir"', said.getvalue())

    def test_a_check_that_fails_leaves_the_build_unmarked(self):
        original = site_files.after_the_build

        def broken(*args, **kwargs):
            raise RuntimeError("a fault in the check")
        site_files.after_the_build = broken
        try:
            with contextlib.redirect_stdout(io.StringIO()) as said:
                mirrored = self.build_site._check_mirror_and_mark(self.output, self.host, "SBI4U", 1)
        finally:
            site_files.after_the_build = original
        self.assertTrue(mirrored, "the site still reaches the host")
        self.assertFalse((self.host / self.build_site.BUILD_STARTED_MARKER).exists(),
                         "an unchecked build must not be marked current")
        self.assertIn("plantoir: error:", said.getvalue())


class ThePreviewWaitsForTheBuild(unittest.TestCase):
    """The watcher mirrors and checks nothing until the done marker (plan
    review 901-1): a check at index.html's first change would read files
    still being copied as holes."""

    def test_nothing_happens_before_the_marker_and_the_check_runs_once_after(self):
        import threading
        import time
        import build_site
        root = Path(tempfile.mkdtemp(prefix="plantoir-site-files-preview-"))
        try:
            output, host = root / "work", root / "host"
            write_tree(output / "public", {"index.html": "<html></html>"})
            host.mkdir()
            calls = []
            build_site._start_public_sync_watcher(output, host, lambda: calls.append(time.monotonic()))
            time.sleep(1.2)
            self.assertEqual(calls, [])
            self.assertFalse((host / "public").exists(), "mirrored before the build said it had finished")
            (output / site_files.DONE_MARKER).write_text("b1")
            deadline = time.monotonic() + 5
            while not (host / "public" / "index.html").exists() and time.monotonic() < deadline:
                time.sleep(0.1)
            self.assertEqual(len(calls), 1)
            self.assertTrue((host / "public" / "index.html").exists())
            time.sleep(1.2)
            self.assertEqual(len(calls), 1, "the check runs once")
            del threading
        finally:
            shutil.rmtree(root, ignore_errors=True)

    def test_the_done_marker_patch_is_made_once_and_only_at_its_line(self):
        import build_site
        root = Path(tempfile.mkdtemp(prefix="plantoir-site-files-buildts-"))
        try:
            build_ts = root / "build.ts"
            old = (scripts_dir.parent / "patches" / "build.ts").read_text(encoding="utf-8")
            old = old.replace(build_site._EMIT_DONE_LINES, "")
            self.assertNotIn(build_site.EMIT_DONE_PATCH_MARKER, old)
            build_ts.write_text(old, encoding="utf-8")
            self.assertTrue(build_site.patch_quartz_build_done_marker(build_ts))
            once = build_ts.read_text(encoding="utf-8")
            self.assertEqual(once.count(build_site.EMIT_DONE_PATCH_MARKER), 1)
            self.assertTrue(build_site.patch_quartz_build_done_marker(build_ts))
            self.assertEqual(build_ts.read_text(encoding="utf-8"), once)
            # The image's own copy carries exactly the same lines.
            self.assertIn(build_site._EMIT_DONE_ANCHOR + build_site._EMIT_DONE_LINES,
                          (scripts_dir.parent / "patches" / "build.ts").read_text(encoding="utf-8"))
            build_ts.write_text("// another shape\n", encoding="utf-8")
            self.assertFalse(build_site.patch_quartz_build_done_marker(build_ts))
            self.assertEqual(build_ts.read_text(encoding="utf-8"), "// another shape\n")
        finally:
            shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    unittest.main()
