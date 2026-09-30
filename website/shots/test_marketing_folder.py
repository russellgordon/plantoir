#!/usr/bin/env python3
"""
Tests for the kept marketing folder's set-up (marketing_folder.py), the
ICS3U and ICS4U -> AP CSP correlations it applies, and the College Board
extraction.

Stdlib only, no app and no network: the file steps run against the ICS3U and
ICS4U payloads laid out in a temporary folder the way the app installs it. The
extraction test runs only when the Course and Exam Description is on this Mac
(the kept folder's .sources/, or PLANTOIR_CED_PDF), and says so when it skips.

    python3 website/shots/test_marketing_folder.py
"""
import json
import os
import re
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(REPO / "scripts"))

import marketing_folder as mf  # noqa: E402

SUPPORT = REPO / "support"
FAKE_PAGES = {"AAP-2.A": "fake page A\n", "CRD-2.I": "fake page B\n"}


def staged_folder(root: Path) -> Path:
    folder = root / "Plantoir Marketing"
    mf.stage_from_payload(folder, SUPPORT)
    return folder


class FileStepTests(unittest.TestCase):

    def test_a_second_run_changes_nothing(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = staged_folder(Path(temporary))
            first = mf.apply_file_steps(folder, FAKE_PAGES)
            self.assertGreater(first.made, 0)
            before = {path: path.read_bytes() for path in folder.rglob("*") if path.is_file()}
            second = mf.apply_file_steps(folder, FAKE_PAGES)
            after = {path: path.read_bytes() for path in folder.rglob("*") if path.is_file()}
        self.assertEqual(second.made, 0, second.lines)
        self.assertEqual(before, after)

    def test_a_changed_file_is_left_as_changed(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = staged_folder(Path(temporary))
            mf.apply_file_steps(folder, FAKE_PAGES)
            page = folder / "courses" / "ICS3U" / mf.HOW_I_TEACH_NAME
            page.write_text("Russell's own words\n", encoding="utf-8")
            board_page = folder / "courses" / "ICS3U" / mf.COLLEGE_BOARD_FOLDER / "AAP-2.A.md"
            board_page.write_text("edited\n", encoding="utf-8")
            report = mf.apply_file_steps(folder, FAKE_PAGES)
            self.assertEqual(page.read_text(encoding="utf-8"), "Russell's own words\n")
            self.assertEqual(board_page.read_text(encoding="utf-8"), "edited\n")
        self.assertEqual(report.left_as_changed, 2)

    def test_a_folder_with_a_foreign_course_is_refused(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = staged_folder(Path(temporary))
            foreign = folder / "courses" / "MCR3U"
            foreign.mkdir()
            (foreign / "course_config.json").write_text(json.dumps({"course_code": "MCR3U"}), encoding="utf-8")
            how_i_teach = folder / "courses" / "ICS3U" / mf.HOW_I_TEACH_NAME
            with self.assertRaises(mf.ForeignFolder):
                mf.apply_file_steps(folder, FAKE_PAGES)
            self.assertFalse(how_i_teach.exists(), "nothing may be written to a folder that is refused")

    def test_a_folder_this_set_up_did_not_make_is_refused(self):
        # A Computer Science teacher's real folder holds ICS3U too.
        with tempfile.TemporaryDirectory() as temporary:
            folder = staged_folder(Path(temporary))
            (folder / mf.MARKER_NAME).unlink()
            with self.assertRaises(mf.ForeignFolder):
                mf.apply_file_steps(folder, FAKE_PAGES)

    def test_a_reference_copy_of_ics3u_is_not_foreign(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = staged_folder(Path(temporary))
            copy = folder / "courses" / "ICS3U 2025-26"
            copy.mkdir()
            (copy / "course_config.json").write_text(
                json.dumps({"course_code": "ICS3U", "kept_for_reference": True}), encoding="utf-8")
            mf.apply_file_steps(folder, FAKE_PAGES)

    def test_embeds_follow_the_ontario_ones_inside_the_block(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = staged_folder(Path(temporary))
            page = folder / "courses" / "ICS3U" / "Explorations" / "The Unplugged Algorithm.md"
            mf.link_activity(page, ["AAP-2.A", "CRD-2.I"], mf.Report())
            text = page.read_text(encoding="utf-8")
        block = text[text.index("## Curriculum connection"):]
        self.assertLess(block.index("![[B2.2]]"), block.index("![[AAP-2.A]]"))
        self.assertLess(block.index("![[AAP-2.A]]"), block.index("![[CRD-2.I]]"))
        self.assertIn("![[B2.2]]\n\n![[AAP-2.A]]\n\n![[CRD-2.I]]", block)

    def test_a_page_without_a_block_is_named_and_skipped(self):
        with tempfile.TemporaryDirectory() as temporary:
            page = Path(temporary) / "No Block.md"
            page.write_text("---\ntitle: x\n---\nJust prose.\n", encoding="utf-8")
            report = mf.Report()
            mf.link_activity(page, ["AAP-2.A"], report)
            self.assertEqual(page.read_text(encoding="utf-8"), "---\ntitle: x\n---\nJust prose.\n")
        self.assertEqual(len(report.named_and_skipped), 1)
        self.assertIn("No Block.md", report.named_and_skipped[0])

    def test_the_college_board_folder_is_kept_out_of_the_sidebar(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = staged_folder(Path(temporary))
            mf.apply_file_steps(folder, FAKE_PAGES)
            config = json.loads((folder / "courses" / "ICS3U" / "course_config.json").read_text(encoding="utf-8"))
        self.assertIn(mf.COLLEGE_BOARD_FOLDER, config["hidden"])
        self.assertEqual(config["deploy_target"], "local_folder")

    def test_section_two_moves_to_a_second_semester_by_whole_weeks(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = staged_folder(Path(temporary))
            course = folder / "courses" / "ICS3U"
            own = course / "section2" / "All Classes"
            own.mkdir(parents=True)
            (own / "Unit 1, Day 1.md").write_text(
                "---\ntitle: Unit 1, Day 1\ncreated: 2026-09-08T07:00:00.000+0000\n---\nBody\n", encoding="utf-8")
            (own / "Unit 1, Day 2.md").write_text(
                "---\ntitle: Unit 1, Day 2\ncreated: 2026-09-09T07:00:00.000+0000\n---\nBody\n", encoding="utf-8")
            shared = course / "Concepts" / "A Shared Page.md"
            shared.parent.mkdir(parents=True, exist_ok=True)
            shared.write_text("---\ncreatedSection1: 2026-09-08T07:00:00.000+0000\n"
                              "createdSection2: 2026-09-08T07:00:00.000+0000\n---\nText\n", encoding="utf-8")
            mf.apply_file_steps(folder, FAKE_PAGES)
            first = (own / "Unit 1, Day 1.md").read_text(encoding="utf-8")
            second = (own / "Unit 1, Day 2.md").read_text(encoding="utf-8")
            both = shared.read_text(encoding="utf-8")
            before = {path: path.read_bytes() for path in folder.rglob("*") if path.is_file()}
            mf.apply_file_steps(folder, FAKE_PAGES)
            after = {path: path.read_bytes() for path in folder.rglob("*") if path.is_file()}
        # 21 weeks: Tuesday 2026-09-08 becomes Tuesday 2027-02-02, the week of 2027-02-01.
        self.assertIn("created: 2027-02-02T07:00:00.000+0000", first)
        self.assertIn("created: 2027-02-03T07:00:00.000+0000", second)
        self.assertIn("createdSection2: 2027-02-02T07:00:00.000+0000", both)
        self.assertIn("createdSection1: 2026-09-08T07:00:00.000+0000", both, "section 1 keeps its dates")
        self.assertEqual(before, after, "a second run moves nothing")

    def test_the_new_course_panels_netlify_is_not_a_choice(self):
        # The app writes "netlify" for every new course; with no site recorded
        # nobody chose it, and the folder destination replaces it.
        with tempfile.TemporaryDirectory() as temporary:
            folder = staged_folder(Path(temporary))
            config_path = folder / "courses" / "ICS3U" / "course_config.json"
            config = json.loads(config_path.read_text(encoding="utf-8"))
            config["deploy_target"] = "netlify"
            config["deploy_folder_path"] = ""
            config_path.write_text(json.dumps(config), encoding="utf-8")
            mf.apply_file_steps(folder, FAKE_PAGES)
            after = json.loads(config_path.read_text(encoding="utf-8"))
        self.assertEqual(after["deploy_target"], mf.FOLDER_DESTINATION)

    def test_a_netlify_site_somebody_published_to_is_left_alone(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = staged_folder(Path(temporary))
            course = folder / "courses" / "ICS3U"
            config_path = course / "course_config.json"
            config = json.loads(config_path.read_text(encoding="utf-8"))
            config["deploy_target"] = "netlify"
            config_path.write_text(json.dumps(config), encoding="utf-8")
            (course / ".netlify_sites").mkdir()
            (course / ".netlify_sites" / "section1.json").write_text("{}", encoding="utf-8")
            report = mf.apply_file_steps(folder, FAKE_PAGES)
            after = json.loads(config_path.read_text(encoding="utf-8"))
        self.assertEqual(after["deploy_target"], "netlify")
        self.assertTrue(any("netlify" in line for line in report.named_and_skipped))

    def test_a_destination_somebody_chose_is_left_alone(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = staged_folder(Path(temporary))
            config_path = folder / "courses" / "ICS3U" / "course_config.json"
            config = json.loads(config_path.read_text(encoding="utf-8"))
            config["deploy_target"] = "cloudflare"
            config_path.write_text(json.dumps(config), encoding="utf-8")
            report = mf.apply_file_steps(folder, FAKE_PAGES)
            after = json.loads(config_path.read_text(encoding="utf-8"))
        self.assertEqual(after["deploy_target"], "cloudflare")
        self.assertTrue(any("cloudflare" in line for line in report.named_and_skipped))


class CorrelationTests(unittest.TestCase):
    """Each course's correlation, against that course's own payload. ICS3U
    and ICS4U are held to the same rules: every page real, taught and
    published, every code an objective's shape, every evidence phrase on
    its page, and no page both kept and dropped."""

    def test_correlation_names_real_pages_and_codes(self):
        for course in mf.CSP_COURSES:
            rows = mf.load_correlation(course["correlation"])
            shared = SUPPORT / "example_content" / course["code"] / "shared"
            self.assertGreater(len(rows), 40, course["code"])
            for row in rows:
                label = f"{course['code']} {row['page']}"
                page = shared / f"{row['page']}.md"
                self.assertTrue(page.is_file(), label)
                self.assertIn("## Curriculum connection", page.read_text(encoding="utf-8"), label)
                self.assertTrue(row["codes"], label)
                self.assertEqual(len(row["codes"]), len(set(row["codes"])), label)
                for code in row["codes"]:
                    self.assertRegex(code, r"^(CRD|AAP|DAT|CSN|IOC)-\d\.[A-Z]$", label)
                self.assertTrue(row["reason"].strip())
                self.assertTrue(row["evidence"].strip())

    def test_every_evidence_phrase_is_on_its_page(self):
        for course in mf.CSP_COURSES:
            shared = SUPPORT / "example_content" / course["code"] / "shared"
            for row in mf.load_correlation(course["correlation"]):
                # Emphasis and link brackets are formatting, not words.
                text = (shared / f"{row['page']}.md").read_text(encoding="utf-8")
                text = re.sub(r"(?m)^\s*>\s?", "", text)  # a callout's quote marks
                text = re.sub(r"[*_`\[\]]", "", text)
                text = re.sub(r"\s+", " ", text)
                evidence = re.sub(r"\s+", " ", re.sub(r"[*_`\[\]]", "", row["evidence"])).strip()
                self.assertIn(evidence.lower(), text.lower(), f"{course['code']} {row['page']}: {evidence!r}")

    def test_every_linked_page_is_published_and_taught(self):
        # An embed on a page the course does not teach, or does not publish,
        # counts for nothing on the map.
        import build_site
        for course in mf.CSP_COURSES:
            payload = SUPPORT / "example_content" / course["code"]
            taught = build_site._pages_the_course_teaches(payload, ["All Classes"])
            for row in mf.load_correlation(course["correlation"]):
                label = f"{course['code']} {row['page']}"
                stem = row["page"].split("/")[-1]
                self.assertIn(stem, taught, label)
                text = (payload / "shared" / f"{row['page']}.md").read_text(encoding="utf-8")
                self.assertRegex(text, r"(?m)^publish: true$", label)

    def test_no_page_is_both_kept_and_dropped(self):
        for course in mf.CSP_COURSES:
            data = json.loads(course["correlation"].read_text(encoding="utf-8"))
            self.assertEqual(data["course"], course["code"])
            self.assertEqual(data["folder"], mf.COLLEGE_BOARD_FOLDER)
            kept = {row["page"] for row in data["rows"]}
            dropped = {row["page"] for row in data["dropped"]}
            self.assertEqual(kept & dropped, set(), course["code"])
            self.assertEqual(len(kept), len(data["rows"]), f"{course['code']}: a page listed twice")

    def test_every_ics4u_activity_page_was_read_and_decided(self):
        # ICS4U's correlation was made by reading EVERY published activity
        # page that carries a curriculum block: each is either tagged or
        # dropped with a reason. A page added to the payload later fails
        # here until somebody reads it and decides.
        data = json.loads(mf.ICS4U_CORRELATION_FILE.read_text(encoding="utf-8"))
        shared = SUPPORT / "example_content" / "ICS4U" / "shared"
        with_a_block: set = set()
        for page in shared.rglob("*.md"):
            relative = page.relative_to(shared).with_suffix("").as_posix()
            if relative.startswith("Curriculum/") or page.stem == "_DUPLICATE ME":
                continue
            text = page.read_text(encoding="utf-8")
            if "## Curriculum connection" in text and re.search(r"(?m)^publish: true$", text):
                with_a_block.add(relative)
        decided: set = set()
        for row in data["rows"]:
            decided.add(row["page"])
        for row in data["dropped"]:
            self.assertTrue(row["why"].strip(), row["page"])
            decided.add(row["page"])
        self.assertEqual(with_a_block - decided, set(), "pages nobody has decided about")
        self.assertEqual(decided - with_a_block, set(), "decisions about pages that are not activity pages")


class Ics4uFileStepTests(unittest.TestCase):

    def test_ics4u_gets_the_pages_the_embeds_and_a_declared_second_curriculum(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = staged_folder(Path(temporary))
            mf.apply_file_steps(folder, FAKE_PAGES)
            course = folder / "courses" / "ICS4U"
            config = json.loads((course / "course_config.json").read_text(encoding="utf-8"))
            page = (course / "Warm-Ups" / "Trace It.md").read_text(encoding="utf-8")
            board_page = course / mf.COLLEGE_BOARD_FOLDER / "AAP-2.A.md"
            ics3u = json.loads((folder / "courses" / "ICS3U" / "course_config.json").read_text(encoding="utf-8"))
            how_i_teach = course / mf.HOW_I_TEACH_NAME
            self.assertTrue(board_page.is_file())
            self.assertFalse(how_i_teach.exists(), "How I Teach is ICS3U's alone")
        self.assertEqual(config["curriculum_folders"], ["Curriculum", mf.COLLEGE_BOARD_FOLDER])
        self.assertIn(mf.COLLEGE_BOARD_FOLDER, config["hidden"])
        # Its pages print the College Board's words, so it publishes to a
        # folder of its own and never to a public site (ruling Q2).
        self.assertEqual(config["deploy_target"], mf.FOLDER_DESTINATION)
        self.assertEqual(config["deploy_folder_path"], str(folder / "School Web Space" / "ICS4U"))
        self.assertEqual(ics3u["deploy_folder_path"], str(folder / mf.PUBLISH_FOLDER_NAME))
        # ICS3U's tick is the curriculum-settings scene's to make, through the app.
        self.assertEqual(ics3u["curriculum_folders"], ["Curriculum"])
        block = page[page.index("## Curriculum connection"):]
        self.assertIn("![[C2.1]]\n\n![[AAP-3.A]]", block)

    def test_a_course_not_made_yet_is_named_and_skipped(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = staged_folder(Path(temporary))
            (folder / "courses" / "ICS4U" / "course_config.json").unlink()
            report = mf.apply_file_steps(folder, FAKE_PAGES)
            ics3u_page = folder / "courses" / "ICS3U" / mf.HOW_I_TEACH_NAME
            self.assertTrue(ics3u_page.exists(), "ICS3U's steps still run")
        self.assertTrue(any(line.startswith("ICS4U") for line in report.named_and_skipped), report.named_and_skipped)


def cached_ced() -> Path | None:
    candidates = []
    if os.environ.get("PLANTOIR_CED_PDF"):
        candidates.append(Path(os.environ["PLANTOIR_CED_PDF"]))
    codes = json.loads((HERE / "marketing" / "csp-codes.json").read_text(encoding="utf-8"))
    candidates.append(mf.DEFAULT_FOLDER / ".sources" / codes["source"]["fileName"])
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    return None


class ExtractionTests(unittest.TestCase):

    def test_extraction(self):
        pdf = cached_ced()
        if pdf is None:
            self.skipTest("the Course and Exam Description is not on this Mac "
                          "(set PLANTOIR_CED_PDF, or run the marketing set-up once)")
        import college_board
        extraction = college_board.build_pages(pdf)
        self.assertEqual(extraction.problems, [])
        objectives = set(extraction.pages) | set(extraction.needs_a_person)
        self.assertEqual(len(objectives), 66)
        codes_used: set = set()
        for course in mf.CSP_COURSES:
            for row in mf.load_correlation(course["correlation"]):
                codes_used.update(row["codes"])
        self.assertEqual(codes_used - objectives, set(), "the correlation names an objective the document lacks")
        for code, page in extraction.pages.items():
            self.assertIn(" ^text\n", page, code)
            objective = page.split("---\n")[2].split(" ^text")[0]
            # A skill badge left inside a multi-part objective, a tab stop
            # read as spaces, or a word split in two: none is the document's.
            self.assertNotRegex(objective, r"\b\d\.[A-F]\b", code)
            self.assertNotIn("  ", page.replace("\n  - ", "\n- "), code)
            self.assertNotRegex(page, r"\b(modif|Identif) y\b|\bE valuate\b", code)
            self.assertNotIn("§", page, code)
            self.assertNotIn("\u0007", page, code)


if __name__ == "__main__":
    unittest.main()
