#!/usr/bin/env python3
"""
The published-pages record (#379): what has been on a site students could
reach, so that a page hidden again and later published keeps its date
(contracts/class-planning.json -> datingPagesAClassBrings.
publishedBeforeIsRecorded; contracts/file-formats.json ->
publishedPagesRecord and visiblePagesList).

Three writers and one reader, each checked here:
- the build writes the list of the pages it shows, beside `public/` and never
  inside it, and notes its own id as it starts;
- deploy.py adds a fragment after an upload succeeded, only from a list that
  belongs to the build the site folder holds;
- deploy.sh's folder branch, which never enters deploy.py, does the same with
  cp — its function is cut out of the launcher and run under bash;
- the build reads the union of the fragments.

Imports build_site (python-frontmatter), so verify.sh runs it in the image;
Windows' PythonToolchainTests discovers it (the bash half skips without bash).

Run with:

    python3 scripts/test_published_pages_record.py
"""
import inspect
import json
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

import build_site
import deploy

REPOSITORY = Path(__file__).resolve().parent.parent


def write_listing(section_dir: Path, build_id: str, places: list, current_id: str) -> None:
    section_dir.mkdir(parents=True, exist_ok=True)
    (section_dir / ".visible-pages.json").write_text(json.dumps(
        {"version": 1, "course": "TEST", "section": 1, "buildId": build_id, "places": places}),
        encoding="utf-8")
    (section_dir / ".build-id").write_text(current_id + "\n", encoding="utf-8")


def fragments(course_dir: Path) -> list:
    folder = course_dir / ".publish_state" / "section1.published-pages"
    if not folder.is_dir():
        return []
    return sorted(path for path in folder.iterdir() if not path.name.startswith("."))


class DeployRecordsTests(unittest.TestCase):

    def setUp(self):
        self.temporary = Path(tempfile.mkdtemp())
        self.course = self.temporary / "courses" / "TEST"
        self.section_dir = self.temporary / "builds" / "section1"

    def tearDown(self):
        shutil.rmtree(self.temporary, ignore_errors=True)

    def test_a_list_from_this_build_is_recorded_as_a_fragment(self):
        write_listing(self.section_dir, "b2", ["Concepts/Loops", "section1/index"], "b2")
        written = deploy.record_published_pages(self.course, self.section_dir, 1, "netlify",
                                                printer=lambda line: None)
        self.assertIsNotNone(written)
        found = fragments(self.course)
        self.assertEqual(len(found), 1)
        self.assertTrue(found[0].name.endswith("-netlify.json"), found[0].name)
        self.assertEqual(json.loads(found[0].read_text())["places"], ["Concepts/Loops", "section1/index"])

    def test_a_list_from_an_earlier_build_is_not_recorded(self):
        # A preview (or a build that failed) started after the list was
        # written: the site folder no longer holds that build's site.
        write_listing(self.section_dir, "b1", ["Concepts/Loops"], "b2")
        deploy.record_published_pages(self.course, self.section_dir, 1, "netlify",
                                      printer=lambda line: None)
        self.assertEqual(fragments(self.course), [])

    def test_no_list_records_nothing(self):
        self.section_dir.mkdir(parents=True)
        deploy.record_published_pages(self.course, self.section_dir, 1, "cloudflare",
                                      printer=lambda line: None)
        self.assertEqual(fragments(self.course), [])

    def test_each_destination_is_recorded_only_after_its_upload_succeeded(self):
        """The call sits after the upload in main() for both destinations —
        read from main()'s own source, the way test_deploy_netlify_headers.py
        reads it, because driving main() would need a real site."""
        source = inspect.getsource(deploy.main)
        netlify_record = source.index('record_published_pages(course_dir, section_dir, args.section, "netlify")')
        self.assertGreater(netlify_record, source.index("_upload_required_files("),
                           "Netlify's pages are recorded before they are uploaded")
        self.assertGreater(netlify_record, source.index('print("\\n✅ Deploy complete.")'),
                           "Netlify's pages are recorded before the deploy completed")
        cloudflare_record = source.index('record_published_pages(course_dir, section_dir, args.section, "cloudflare")')
        self.assertGreater(cloudflare_record, source.index("publish_to_cloudflare("),
                           "Cloudflare's pages are recorded before they are uploaded")


class FolderPublishRecordsTests(unittest.TestCase):
    """deploy.sh's folder branch never enters deploy.py, so it records itself."""

    @classmethod
    def setUpClass(cls):
        text = (REPOSITORY / "deploy.sh").read_text(encoding="utf-8")
        match = re.search(r"# BEGIN record_published_pages\n(.*?)# END record_published_pages", text, re.S)
        cls.function = match.group(1) if match else None
        cls.launcher = text

    def setUp(self):
        if shutil.which("bash") is None:
            self.skipTest("no bash on this machine")
        self.temporary = Path(tempfile.mkdtemp())
        self.course = self.temporary / "courses" / "TEST"
        self.section_dir = self.temporary / "courses" / "TEST" / ".merged_output" / "section1"

    def tearDown(self):
        shutil.rmtree(self.temporary, ignore_errors=True)

    def run_the_function(self):
        self.assertIsNotNone(self.function, "deploy.sh has no record_published_pages block")
        script = self.function + f'\nrecord_published_pages "{self.section_dir}" TEST 1 folder\necho "after the call"\n'
        return subprocess.run(["bash", "-c", "set -euo pipefail\n" + script], cwd=self.temporary,
                              capture_output=True, text=True)

    def test_a_folder_publish_records_the_list(self):
        write_listing(self.section_dir, "b7", ["Concepts/Loops"], "b7")
        result = self.run_the_function()
        self.assertEqual(result.returncode, 0, result.stderr)
        found = fragments(self.course)
        self.assertEqual(len(found), 1)
        self.assertTrue(found[0].name.endswith("-folder.json"), found[0].name)
        self.assertEqual(json.loads(found[0].read_text())["places"], ["Concepts/Loops"])

    def test_a_folder_publish_of_an_earlier_list_records_nothing(self):
        write_listing(self.section_dir, "b6", ["Concepts/Loops"], "b7")
        result = self.run_the_function()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(fragments(self.course), [])

    def test_a_list_without_a_build_id_records_nothing_and_does_not_end_the_publish(self):
        """Under `set -euo pipefail` a failed assignment ended the launcher
        after the copy had succeeded (implementation review, S1)."""
        self.section_dir.mkdir(parents=True, exist_ok=True)
        (self.section_dir / ".visible-pages.json").write_text('{"version": 1, "places": []}', encoding="utf-8")
        (self.section_dir / ".build-id").write_text("b7\n", encoding="utf-8")
        result = self.run_the_function()
        self.assertEqual(result.returncode, 0, "The publish was ended by the record: " + result.stderr)
        self.assertIn("after the call", result.stdout, "The line after the call never ran")
        self.assertEqual(fragments(self.course), [])

    def test_an_unreadable_build_id_records_nothing_and_does_not_end_the_publish(self):
        import os
        if hasattr(os, "geteuid") and os.geteuid() == 0:
            self.skipTest("root reads a file whatever its mode")
        write_listing(self.section_dir, "b7", ["Concepts/Loops"], "b7")
        id_file = self.section_dir / ".build-id"
        id_file.chmod(0)
        try:
            result = self.run_the_function()
        finally:
            id_file.chmod(0o644)
        self.assertEqual(result.returncode, 0, "The publish was ended by the record: " + result.stderr)
        self.assertIn("after the call", result.stdout)
        self.assertEqual(fragments(self.course), [])

    def test_the_folder_branch_records_after_its_copy_succeeded(self):
        call = self.launcher.index('record_published_pages "$SECTION_DIR_HOST" "$COURSE_CODE" "$SECTION_NUM" "folder"')
        copy_checked = self.launcher.index("if [[ $_rsync_rc -ne 0 ]]; then")
        self.assertGreater(call, copy_checked, "The folder publish records before its copy is known to have worked")
        self.assertLess(call, self.launcher.index('echo "PUBLISHED_FOLDER=${TARGET_DIR}"'))


class TheBuildsListTests(unittest.TestCase):

    def setUp(self):
        self.temporary = Path(tempfile.mkdtemp())

    def tearDown(self):
        shutil.rmtree(self.temporary, ignore_errors=True)

    def test_the_list_sits_beside_the_site_and_never_inside_it(self):
        """A folder publish copies public/; the list must not travel with it."""
        built = self.temporary / "section1"
        (built / "public").mkdir(parents=True)
        build_site._write_visible_places(built, ["Concepts/Loops"], "b1", "TEST", 1)
        self.assertTrue((built / ".visible-pages.json").exists())
        self.assertEqual(list((built / "public").rglob("*")), [], "The list was written inside public/")

    def test_the_build_notes_its_id_as_it_starts(self):
        built = self.temporary / "section1"
        build_site._note_the_build_id(built, "b9")
        self.assertEqual((built / ".build-id").read_text().strip(), "b9")

    def test_the_list_is_written_only_after_the_site_was_built_and_mirrored(self):
        """Written early, a build that failed half way would leave a list the
        site in the folder does not match (plan review, finding 11)."""
        source = inspect.getsource(build_site.build_section_site)
        written = source.index("_write_visible_places(host_output_dir")
        self.assertGreater(written, source.index('"build", "--concurrency", "1"]'),
                           "The list is written before the site is built")
        self.assertGreater(written, source.index("if _sync_public_to_host(output_dir, host_output_dir):"),
                           "The list is written before the site was mirrored")
        self.assertEqual(source.count("_write_visible_places("), 1, "Written from more than one place")

    def test_the_reader_takes_the_union_of_every_fragment(self):
        course = self.temporary / "TEST"
        folder = course / ".publish_state" / "section1.published-pages"
        folder.mkdir(parents=True)
        (folder / "a-netlify.json").write_text(json.dumps({"places": ["A", "B"]}))
        (folder / "b-folder.json").write_text(json.dumps({"places": ["C"]}))
        (folder / "c-broken.json").write_text("{not json")
        self.assertEqual(build_site._published_places(course, 1), {"A", "B", "C"})
        self.assertEqual(build_site._published_places(course, 2), set())


if __name__ == "__main__":
    unittest.main()
