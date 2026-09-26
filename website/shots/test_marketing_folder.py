#!/usr/bin/env python3
"""
Tests for the kept marketing folder's set-up (marketing_folder.py), the
ICS3U -> AP CSP correlation it applies, and the College Board extraction.

Stdlib only, no app and no network: the file steps run against the ICS3U
payload laid out in a temporary folder the way the app installs it. The
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

    def test_a_netlify_destination_somebody_chose_is_left_alone(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = staged_folder(Path(temporary))
            config_path = folder / "courses" / "ICS3U" / "course_config.json"
            config = json.loads(config_path.read_text(encoding="utf-8"))
            config["deploy_target"] = "netlify"
            config_path.write_text(json.dumps(config), encoding="utf-8")
            mf.apply_file_steps(folder, FAKE_PAGES)
            after = json.loads(config_path.read_text(encoding="utf-8"))
        self.assertEqual(after["deploy_target"], "netlify")

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

    def test_correlation_names_real_pages_and_codes(self):
        rows = mf.load_correlation()
        shared = SUPPORT / "example_content" / "ICS3U" / "shared"
        self.assertGreater(len(rows), 40)
        for row in rows:
            page = shared / f"{row['page']}.md"
            self.assertTrue(page.is_file(), row["page"])
            self.assertIn("## Curriculum connection", page.read_text(encoding="utf-8"), row["page"])
            self.assertTrue(row["codes"], row["page"])
            for code in row["codes"]:
                self.assertRegex(code, r"^(CRD|AAP|DAT|CSN|IOC)-\d\.[A-Z]$", row["page"])
            self.assertTrue(row["reason"].strip())
            self.assertTrue(row["evidence"].strip())

    def test_every_evidence_phrase_is_on_its_page(self):
        shared = SUPPORT / "example_content" / "ICS3U" / "shared"
        for row in mf.load_correlation():
            # Emphasis and link brackets are formatting, not words.
            text = (shared / f"{row['page']}.md").read_text(encoding="utf-8")
            text = re.sub(r"(?m)^\s*>\s?", "", text)  # a callout's quote marks
            text = re.sub(r"[*_`\[\]]", "", text)
            text = re.sub(r"\s+", " ", text)
            evidence = re.sub(r"\s+", " ", re.sub(r"[*_`\[\]]", "", row["evidence"])).strip()
            self.assertIn(evidence.lower(), text.lower(), f"{row['page']}: {evidence!r}")

    def test_every_linked_page_is_published_and_taught(self):
        # An embed on a page the course does not teach, or does not publish,
        # counts for nothing on the map.
        import build_site
        payload = SUPPORT / "example_content" / "ICS3U"
        taught = build_site._pages_the_course_teaches(payload, ["All Classes"])
        for row in mf.load_correlation():
            stem = row["page"].split("/")[-1]
            self.assertIn(stem, taught, row["page"])
            text = (payload / "shared" / f"{row['page']}.md").read_text(encoding="utf-8")
            self.assertRegex(text, r"(?m)^publish: true$", row["page"])

    def test_no_page_is_both_kept_and_dropped(self):
        data = json.loads(mf.CORRELATION_FILE.read_text(encoding="utf-8"))
        kept = {row["page"] for row in data["rows"]}
        dropped = {row["page"] for row in data["dropped"]}
        self.assertEqual(kept & dropped, set())


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
        for row in mf.load_correlation():
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
