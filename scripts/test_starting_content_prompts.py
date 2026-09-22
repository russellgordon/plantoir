#!/usr/bin/env python3
"""
What a teacher who declined the ready-made pages gets — what the wizard
SAYS to them, and what actually lands in the course.

The app RUNS this script and shows its output to the teacher, so these are
sentences a teacher reads, not log lines. There are two openings because two
different things are true:

* a course code with no ready-made course of its own — saying so is the
  point, since it is why a skeleton is being offered at all;
* a course code that HAS one, which the teacher has just been asked about
  and declined. Telling them there is no ready-made course for the code
  they were offered a ready-made course for is plainly untrue, and it is
  what they read for all 38 codes with a payload (GitHub issue #248).

The skeleton INSTALL itself needed no change — `find_skeleton_dir` has never
looked at payloads, so `use_skeleton: true` on a payload code has always
worked. Measured while fixing #248, driving the real script through a pty:
ICS4U with `prepopulate:false, use_skeleton:true` installs 47 `.md` files
against the 18 the apps were producing, and the tree is identical to the one
ICS2O (same family, no payload) gets.

What that skeleton's Curriculum folder held, though, was a generic index and
one placeholder expectation called A1.1 — so the curriculum coverage map,
which is built from those pages, would have been drawn over a single fake
cell whose page says "DELETE THIS PAGE". For the 38 codes that HAVE a
payload the real expectations exist; the teacher declined the lessons, not
the curriculum. They now come along (GitHub issue #251), and the cases below
are that fault turned into a test: measured against the real payloads, ICS4U
lands 61 curriculum pages (47 specific expectations, 12 overall), MCMPR11
lands 59 British Columbia standards with NO A1.1 among them, and ICS2O —
which has no payload — is untouched at 2.

Run with:

    python3 scripts/test_starting_content_prompts.py
"""
import unittest
import tempfile
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))

from setup_course import (  # noqa: E402
    starting_point_intro,
    starting_point_curriculum_intro,
    jurisdiction_name,
    install_curriculum_from_payload,
    install_example_content,
    find_example_content_dir,
    find_skeleton_dir,
    load_example_content_manifest,
)


class StartingPointIntroTests(unittest.TestCase):

    def test_a_code_with_no_ready_made_course_is_told_so(self):
        text = starting_point_intro("ICS2O", "Computer Studies", has_payload=False)
        self.assertIn("There is no ready-made course for ICS2O", text)
        self.assertIn("shaped for computer studies", text)

    def test_a_code_whose_ready_made_course_was_declined_is_not_told_there_is_none(self):
        text = starting_point_intro("ICS4U", "Computer Studies", has_payload=True)
        self.assertNotIn("no ready-made course", text,
                         "The teacher declined a ready-made course for this very code one "
                         "question ago; this sentence says there was never one to decline.")
        self.assertIn("There is also a starting point", text)
        self.assertIn("shaped for computer studies", text)

    def test_both_openings_describe_the_same_starting_point(self):
        without_payload = starting_point_intro("ICS2O", "Computer Studies", has_payload=False)
        with_payload = starting_point_intro("ICS4U", "Computer Studies", has_payload=True)
        for promise in ("four units of class pages to rename",
                        "a page explaining what the site can do",
                        "placeholders saying"):
            with self.subTest(promise=promise):
                self.assertIn(promise, without_payload)
                self.assertIn(promise, with_payload)

    def test_a_family_with_no_label_still_reads_as_english(self):
        text = starting_point_intro("CODING", "", has_payload=False)
        self.assertIn("shaped for this subject", text)

    def test_the_last_line_is_not_mistaken_for_a_prompt(self):
        # The app answers any line ending in ":" or "?" by pressing Return
        # (NewCourseCreator.looksLikePrompt). A paragraph whose last line
        # looked like a question would be answered instead of read, and the
        # real question below it would then go unanswered.
        for has_payload in (False, True):
            with self.subTest(has_payload=has_payload):
                last = starting_point_intro("ICS4U", "Computer Studies", has_payload).rstrip().splitlines()[-1]
                self.assertFalse(last.endswith(":"))
                self.assertFalse(last.endswith("?"))


class CurriculumIntroTests(unittest.TestCase):
    """What a teacher reads above the skeleton's curriculum question."""

    def test_a_code_with_a_payload_is_not_told_the_folder_is_empty(self):
        text = starting_point_curriculum_intro(
            "ICS4U", "Ontario", has_payload_curriculum=True
        )
        self.assertNotIn("empty Curriculum folder", text,
                         "The expectations for this code exist — the teacher declined "
                         "the lessons, not the curriculum.")
        self.assertNotIn("when you add them", text)
        self.assertIn("Ontario curriculum for ICS4U", text)

    def test_a_code_with_no_payload_still_reads_as_it_always_did(self):
        text = starting_point_curriculum_intro(
            "ICS2O", "Ontario", has_payload_curriculum=False
        )
        self.assertIn("empty Curriculum folder", text)
        self.assertIn("the expectations for ICS2O when you add them", text)

    def test_a_british_columbia_course_is_not_told_about_ontario(self):
        text = starting_point_curriculum_intro(
            "MCMPR11", "British Columbia", has_payload_curriculum=True
        )
        self.assertIn("British Columbia curriculum for MCMPR11", text)
        self.assertNotIn("Ontario", text)

    def test_the_last_line_is_not_mistaken_for_a_prompt(self):
        # See the note on the same check above.
        for has_payload_curriculum in (False, True):
            with self.subTest(has_payload_curriculum=has_payload_curriculum):
                last = starting_point_curriculum_intro(
                    "ICS4U", "Ontario", has_payload_curriculum
                ).rstrip().splitlines()[-1]
                self.assertFalse(last.endswith(":"))
                self.assertFalse(last.endswith("?"))


class JurisdictionNameTests(unittest.TestCase):
    """
    The console used to say "the official Ontario curriculum" to every
    teacher, including the one taking British Columbia's. The macOS
    wizard's own toggle has always read this from the manifest
    (`ExampleContentCatalog.jurisdictionName`); this is the same rule.
    """

    def test_the_real_ontario_payload_says_ontario(self):
        payload = find_example_content_dir("ICS4U")
        self.assertIsNotNone(payload)
        self.assertEqual(jurisdiction_name(load_example_content_manifest(payload)),
                         "Ontario")

    def test_the_real_british_columbia_payload_says_british_columbia(self):
        payload = find_example_content_dir("MCMPR11")
        self.assertIsNotNone(payload)
        self.assertEqual(jurisdiction_name(load_example_content_manifest(payload)),
                         "British Columbia")

    def test_a_manifest_that_says_nothing_is_ontario(self):
        # Every payload written before the key existed is Ontario's.
        self.assertEqual(jurisdiction_name({}), "Ontario")

    def test_a_manifest_may_spell_the_name_out(self):
        self.assertEqual(
            jurisdiction_name({"jurisdiction": "SK",
                               "jurisdiction_name": "Saskatchewan"}),
            "Saskatchewan"
        )


class CurriculumFromPayloadTests(unittest.TestCase):
    """
    The measured fault of GitHub issue #251, turned into a test: a teacher
    who declines the ready-made pages and takes the subject's skeleton got
    a Curriculum folder of two placeholder pages, so the coverage map had
    one fake cell to colour.
    """

    def install(self, code: str) -> Path:
        payload = find_example_content_dir(code)
        self.assertIsNotNone(payload, f"{code} is expected to have a payload")
        skeleton = find_skeleton_dir(code)
        self.assertIsNotNone(skeleton, f"{code} is expected to have a skeleton")
        skeleton_manifest = load_example_content_manifest(skeleton)
        destination_folder = skeleton_manifest.get("curriculum_folder")
        self.assertTrue(destination_folder)
        course_path = Path(self.temporary.name) / code
        written = install_curriculum_from_payload(
            course_path, payload, load_example_content_manifest(payload),
            [1], "2026-09-22T09:00:00.000-0400", destination_folder,
            course_code=code, course_name="Test Course"
        )
        self.installed_count = written
        return course_path / destination_folder

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.installed_count = 0

    def tearDown(self):
        self.temporary.cleanup()

    def test_the_whole_ontario_curriculum_lands(self):
        folder = self.install("ICS4U")
        payload_folder = find_example_content_dir("ICS4U") / "shared" / "Curriculum"
        expected = len(list(payload_folder.glob("*.md")))
        self.assertEqual(self.installed_count, expected)
        self.assertEqual(len(list(folder.glob("*.md"))), expected)
        self.assertGreater(expected, 50,
                           "ICS4U's curriculum was 61 pages when this was written; a "
                           "number this much smaller means the walk found almost nothing.")

    def test_the_expectation_pages_are_the_real_ones(self):
        folder = self.install("ICS4U")
        expectation = (folder / "A1.1.md").read_text(encoding="utf-8")
        self.assertNotIn("DELETE THIS PAGE", expectation,
                         "This is the skeleton's placeholder, not the real expectation.")
        self.assertIn("strand-a", expectation)
        index = (folder / "index.md").read_text(encoding="utf-8")
        self.assertNotIn("__CREATED__", index,
                         "The install-time substitutions must run on these pages too.")

    def test_a_british_columbia_course_gets_no_ontario_shaped_placeholder(self):
        # MCMPR11 and MTH1W are the two payloads with no A1.1 of their own,
        # so nothing of theirs displaces the skeleton's placeholder by name.
        # That is why the caller skips the skeleton's curriculum folder
        # entirely rather than relying on the install order alone.
        folder = self.install("MCMPR11")
        self.assertFalse((folder / "A1.1.md").exists())
        self.assertTrue((folder / "D1.1.md").exists())

    def test_nothing_but_the_curriculum_comes_along(self):
        # Every one of the 38 payloads has a `per_section/index.md`, and the
        # shared installer lets any `index.md` through unconditionally — so
        # a narrowed call to THAT would pour the payload's section landing
        # page into a course taking none of the payload's pages.
        folder = self.install("ICS4U")
        course_path = folder.parent
        self.assertEqual(sorted(entry.name for entry in course_path.iterdir()),
                         ["Curriculum"])
        self.assertFalse((course_path / "section1").exists())

    def test_a_code_with_no_payload_never_reaches_this_at_all(self):
        # The control. ICS2O has a skeleton and no payload, so the caller's
        # guard is false and the course keeps today's two placeholder pages.
        self.assertIsNone(find_example_content_dir("ICS2O"))
        self.assertIsNotNone(find_skeleton_dir("ICS2O"))

    def test_the_skeleton_keeps_its_curriculum_connection_blocks(self):
        # The skeleton's own Curriculum folder is skipped BY NAME, never by
        # turning its `include_curriculum` argument off — that flag also
        # decides whether every other skeleton page keeps the
        # "%%curriculum-start%%" block its teacher is meant to fill in.
        skeleton = find_skeleton_dir("ICS4U")
        manifest = load_example_content_manifest(skeleton)
        shared_folders = [name for name in manifest.get("shared_folders", [])
                          if name != manifest.get("curriculum_folder")]
        course_path = Path(self.temporary.name) / "ICS4U-skeleton"
        install_example_content(
            course_path, skeleton, manifest, [1],
            "2026-09-22T09:00:00.000-0400", True,
            shared_folders, list(manifest.get("shared_files", [])),
            list(manifest.get("per_section_folders", [])),
            list(manifest.get("per_section_files", [])),
            course_code="ICS4U", course_name="Test Course"
        )
        self.assertFalse((course_path / manifest["curriculum_folder"]).exists())
        templates = sorted(course_path.rglob("_DUPLICATE ME.md"))
        self.assertTrue(templates, "The skeleton's template pages should have installed.")
        for template in templates:
            with self.subTest(template=template.name):
                self.assertIn("## Curriculum connection",
                              template.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
