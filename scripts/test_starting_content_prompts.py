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
import hashlib
import json
import re
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))

from setup_course import (  # noqa: E402
    starting_point_intro,
    starting_point_curriculum_intro,
    jurisdiction_name,
    install_curriculum_from_payload,
    install_example_content,
    expectation_renames_for_skeleton,
    specific_expectation_stems,
    find_example_content_dir,
    find_skeleton_dir,
    load_example_content_manifest,
    EXAMPLE_CONTENT_ROOTS,
)

NOW = "2026-09-22T09:00:00.000-0400"

# A wiki link or embed, and what it points at. Used to check that nothing a
# course ships points at an expectation page the course does not have.
LINK_TARGET = re.compile(r"!?\[\[([^\]\[|#]+)")
EXPECTATION_STEM = re.compile(r"^([A-Z])(\d+)\.(\d+)$")


def every_payload_code() -> list:
    """Every course code with a ready-made payload, however many there are."""
    codes = set()
    for root in EXAMPLE_CONTENT_ROOTS:
        if not root.is_dir():
            continue
        for candidate in root.iterdir():
            if (candidate / "manifest.json").exists():
                codes.add(candidate.name)
    return sorted(codes)


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

    def test_the_contract_declares_the_key_both_languages_read(self):
        # One rule, two implementations (this one and the mac's
        # `ExampleContentCatalog.jurisdictionName`), so each is pinned to
        # the contract's own words rather than to the other. The mac's
        # half is `ExampleContentContractTests
        # .testTheJurisdictionIsDerivedTheWayTheContractSays`.
        contract = json.loads(
            (Path(__file__).resolve().parent.parent
             / "contracts" / "example-content.json").read_text(encoding="utf-8")
        )
        declared = {entry["key"]: entry for entry in contract["manifestKeys"]}
        self.assertIn("jurisdiction", declared)
        self.assertIn("jurisdiction_name", declared)
        self.assertEqual(declared["jurisdiction"].get("default"), "Ontario")
        why = declared["jurisdiction"]["why"]
        self.assertIn('"BC" to "British Columbia"', why)
        self.assertIn('an absent key to "Ontario"', why)


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


class TheTwoInstallsTogetherTests(unittest.TestCase):
    """
    The payload's curriculum and the skeleton, installed in the order the
    real script installs them. Everything above tests one half at a time;
    the ORDER is the whole mechanism, and these are the only cases that
    would notice it being reversed.
    """

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()

    def tearDown(self):
        self.temporary.cleanup()

    def install(self, code: str, payload_curriculum_first: bool = True) -> Path:
        """Both installs, exactly as `setup_course.py` runs them."""
        payload = find_example_content_dir(code)
        skeleton = find_skeleton_dir(code)
        self.assertIsNotNone(payload, code)
        self.assertIsNotNone(skeleton, code)
        payload_manifest = load_example_content_manifest(payload)
        skeleton_manifest = load_example_content_manifest(skeleton)
        curriculum_folder = skeleton_manifest.get("curriculum_folder")
        self.assertTrue(curriculum_folder, code)
        course_path = Path(self.temporary.name) / code

        folders_for_the_skeleton = [
            name for name in skeleton_manifest.get("shared_folders", [])
            if name != curriculum_folder or not payload_curriculum_first
        ]
        renames = expectation_renames_for_skeleton(
            skeleton, skeleton_manifest, payload, payload_manifest
        ) if payload_curriculum_first else {}

        def the_payload_curriculum():
            install_curriculum_from_payload(
                course_path, payload, payload_manifest, [1], NOW, curriculum_folder,
                course_code=code, course_name="Test Course"
            )

        def the_skeleton():
            install_example_content(
                course_path, skeleton, skeleton_manifest, [1], NOW, True,
                folders_for_the_skeleton,
                list(skeleton_manifest.get("shared_files", [])),
                list(skeleton_manifest.get("per_section_folders", [])),
                list(skeleton_manifest.get("per_section_files", [])),
                course_code=code, course_name="Test Course",
                expectation_renames=renames
            )

        if payload_curriculum_first:
            the_payload_curriculum()
            the_skeleton()
        else:
            the_skeleton()
            the_payload_curriculum()
        return course_path

    def test_the_course_holds_the_payloads_expectations_and_no_placeholder(self):
        for code in ["ICS4U", "MCMPR11", "MTH1W"]:
            with self.subTest(code=code):
                course_path = self.install(code)
                payload = find_example_content_dir(code)
                folder = course_path / "Curriculum"
                expected = sorted(
                    page.name for page in
                    (payload / "shared" / "Curriculum").glob("*.md")
                )
                self.assertEqual(sorted(page.name for page in folder.glob("*.md")),
                                 expected)
                for page in folder.glob("*.md"):
                    self.assertNotIn("DELETE THIS PAGE",
                                     page.read_text(encoding="utf-8"), page.name)

    def test_reversing_the_order_would_leave_the_placeholders_in_place(self):
        # Not a behaviour anyone wants — the guard rail under the one
        # sentence the design rests on. `install_payload_file` returns
        # without writing when the destination exists, so a skeleton
        # installed FIRST claims index.md and A1.md before the payload's
        # own pages can, and the teacher keeps the page that says
        # "DELETE THIS PAGE".
        course_path = self.install("ICS4U", payload_curriculum_first=False)
        placeholder = course_path / "Curriculum" / "A1.1.md"
        self.assertIn("DELETE THIS PAGE", placeholder.read_text(encoding="utf-8"))

    def test_no_page_embeds_an_expectation_the_course_does_not_have(self):
        # Every payload/family pair, because the fault this closes was
        # invisible in 36 of the 38: skipping the skeleton's curriculum
        # folder takes away the A1.1 its template pages embed, and only
        # MCMPR11 and MTH1W have no A1.1 of their own to replace it. A
        # teacher who duplicates one of those templates — which is what
        # the page tells them to do — would publish a broken transclusion.
        codes = every_payload_code()
        self.assertGreaterEqual(len(codes), 38)
        for code in codes:
            with self.subTest(code=code):
                course_path = self.install(code)
                present = set()
                for page in course_path.rglob("*.md"):
                    present.add(page.stem)
                missing = {}
                for page in sorted(course_path.rglob("*.md")):
                    for match in LINK_TARGET.finditer(page.read_text(encoding="utf-8")):
                        target = match.group(1).strip().split("/")[-1]
                        if EXPECTATION_STEM.match(target) and target not in present:
                            missing.setdefault(target, page.name)
                self.assertEqual(missing, {},
                                 f"{code}: pages point at expectation pages that are not "
                                 "in the course")

    def test_every_payloads_curriculum_links_resolve_in_a_skeleton_course(self):
        # Issue #253. Since #251 a teacher who declines the ready-made pages
        # still gets the payload's Curriculum folder, beside the skeleton's
        # pages, so a curriculum page that links to a lesson, a task or a
        # project page of the payload links to nothing in that course. Every
        # link and embed, in every payload, after the real double install;
        # code spans and fenced blocks are examples, not links.
        codes = every_payload_code()
        self.assertGreaterEqual(len(codes), 38)
        for code in codes:
            with self.subTest(code=code):
                course_path = self.install(code)
                present = {"index"}
                for page in course_path.rglob("*.md"):
                    present.add(page.stem)
                unresolved = []
                for page in sorted((course_path / "Curriculum").rglob("*.md")):
                    text = page.read_text(encoding="utf-8")
                    without_fences = re.sub(r"(`{3,})[\s\S]*?\1", "", text)
                    without_code = re.sub(r"`[^`\n]*`", "", without_fences)
                    for match in LINK_TARGET.finditer(without_code):
                        target = match.group(1).strip().rstrip("\\").split("/")[-1]
                        if target not in present:
                            unresolved.append(f"{page.name}: [[{target}]]")
                self.assertEqual(unresolved, [],
                                 f"{code}: a curriculum page links to a page a skeleton "
                                 "course does not have")

    def test_the_two_codes_with_no_A1_1_are_really_the_two(self):
        # The rename rule does nothing for the other 36, and a test that
        # could not tell the difference would pass even if it did nothing
        # anywhere.
        retargeted = []
        for code in every_payload_code():
            payload = find_example_content_dir(code)
            skeleton = find_skeleton_dir(code)
            renames = expectation_renames_for_skeleton(
                skeleton, load_example_content_manifest(skeleton),
                payload, load_example_content_manifest(payload)
            )
            if renames:
                retargeted.append((code, renames))
        self.assertEqual([code for code, _ in retargeted], ["MCMPR11", "MTH1W"])
        self.assertEqual(dict(retargeted)["MCMPR11"], {"A1.1": "D1.1"})
        self.assertEqual(dict(retargeted)["MTH1W"], {"A1.1": "B1.1"})

    def test_the_first_expectation_is_the_maps_first_expectation(self):
        # "First" has to mean the same thing here and in
        # build_site.py's `_collect_expectations`, which walks
        # sorted(glob("*.md")).
        payload = find_example_content_dir("MCMPR11")
        stems = specific_expectation_stems(payload / "shared" / "Curriculum")
        self.assertEqual(stems[0], "D1.1")


class ExampleContentIsUnchangedTests(unittest.TestCase):
    """
    The path that must not move, pinned at the TREE rather than at the
    configuration.

    `mac-app/Tests/Goldens/` pins what the wizard WRITES — the
    `course_config.json` dictionary — and cannot see a single file the
    installer produced. The guard against a payload install drifting is
    structural (a course taking example content never reaches the skeleton
    branch at all), but it is one `if` away from not being, so the tree
    itself is pinned here.

    The two hashes were captured from `origin/dev` at e9000169 on
    2026-09-22, BEFORE any of issue #251 was written, by running this
    same install against that script: 295 files, identical name list,
    identical bytes. Deterministic because the install is given a fixed
    timestamp and no class-date reference.
    """

    PAYLOAD_FILE_COUNT = 295
    PAYLOAD_NAMES_HASH = "6de9b151539aeb40eae91152641a3c2870d36b9618af02a49aff30e7b516e612"
    PAYLOAD_CONTENT_HASH = "6a2276dbbedc27c504667ffcbecb7b8f4371f31a23bbc78e50ac553011b277c9"

    def test_a_payload_course_is_installed_byte_for_byte_as_it_always_was(self):
        payload = find_example_content_dir("ADA1O")
        self.assertIsNotNone(payload)
        manifest = load_example_content_manifest(payload)
        with tempfile.TemporaryDirectory() as temporary:
            course_path = Path(temporary) / "ADA1O"
            install_example_content(
                course_path, payload, manifest, [1, 3], NOW, True,
                [name for name in manifest.get("shared_folders", []) if name != "Media"],
                list(manifest.get("shared_files", [])),
                list(manifest.get("per_section_folders", [])),
                list(manifest.get("per_section_files", [])),
                course_code="ADA1O", course_name="Drama"
            )
            files = sorted(
                str(path.relative_to(course_path))
                for path in course_path.rglob("*") if path.is_file()
            )
            self.assertEqual(len(files), self.PAYLOAD_FILE_COUNT)
            self.assertEqual(
                hashlib.sha256("\n".join(files).encode()).hexdigest(),
                self.PAYLOAD_NAMES_HASH,
                "A file appeared in or vanished from a course taking the ready-made pages."
            )
            digest = hashlib.sha256()
            for name in files:
                digest.update(name.encode())
                digest.update(b"\0")
                digest.update((course_path / name).read_bytes())
                digest.update(b"\0")
            self.assertEqual(
                digest.hexdigest(), self.PAYLOAD_CONTENT_HASH,
                "The bytes of a course taking the ready-made pages have changed. This path "
                "may not move: run the install against origin/dev and diff before touching "
                "this constant."
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
