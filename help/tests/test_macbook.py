"""The Mac Help book: its Info.plist, its pages, both indexes read back, and
the atomic, quiet rebuild."""

from __future__ import annotations

import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))

import json  # noqa: E402
import plistlib  # noqa: E402
import shutil  # noqa: E402
import unittest  # noqa: E402

from helpers import Fixture  # noqa: E402
from helpbook import CS_INDEX_NAME, LSM_INDEX_NAME  # noqa: E402
from helpbook.macbook import run_hiutil, verify_indexes  # noqa: E402
from helpbook.problems import HelpError  # noqa: E402

FIXTURE_IDS = ["first-steps", "second-look", "send-section", "python-page", "helper-page"]

DECISION_2_KEYS = {
    "CFBundleIdentifier": "ca.russellgordon.Plantoir.help",
    "CFBundleDevelopmentRegion": "en",
    "CFBundlePackageType": "BNDL",
    "CFBundleSignature": "hbwr",
    "CFBundleInfoDictionaryVersion": "6.0",
    "CFBundleName": "Plantoir Help",
    "CFBundleShortVersionString": "2.0.0",
    "CFBundleVersion": "2.0.0",
    "HPDBookType": "3",
    "HPDBookTitle": "Plantoir Help",
    "HPDBookAccessPath": "index.html",
    "HPDBookCSIndexPath": "Plantoir.cshelpindex",
    "HPDBookIndexPath": "Plantoir.helpindex",
    "HPDBookKBProduct": "plantoir",
}


@unittest.skipIf(shutil.which("hiutil") is None, "hiutil is not on this machine (it comes with macOS)")
class MacBookTests(unittest.TestCase):
    def setUp(self) -> None:
        self.fixture = Fixture()
        self.book = self.fixture.out / "Plantoir.help"

    def tearDown(self) -> None:
        self.fixture.close()

    def build(self) -> str:
        code, output = self.fixture.run("--mac", str(self.book), "--app-version", "2.0.0")
        self.assertEqual(code, 0, output)
        return output

    def language_folder(self) -> Path:
        return self.book / "Contents" / "Resources" / "en.lproj"

    def test_the_info_plist_has_exactly_decision_2s_keys(self) -> None:
        self.build()
        with (self.book / "Contents" / "Info.plist").open("rb") as handle:
            info = plistlib.load(handle)
        self.assertEqual(info, DECISION_2_KEYS)

    def test_the_version_defaults_to_zero(self) -> None:
        code, output = self.fixture.run("--mac", str(self.book))
        self.assertEqual(code, 0, output)
        with (self.book / "Contents" / "Info.plist").open("rb") as handle:
            info = plistlib.load(handle)
        self.assertEqual(info["CFBundleVersion"], "0")

    def test_the_book_holds_its_pages_indexes_and_anchor_list(self) -> None:
        output = self.build()
        self.assertIn("Plantoir.help: 5 pages, ", output)
        folder = self.language_folder()
        for name in (CS_INDEX_NAME, LSM_INDEX_NAME, "InfoPlist.strings", "index.html"):
            self.assertTrue((folder / name).exists(), name)
            self.assertGreater((folder / name).stat().st_size, 0, name)
        anchors = json.loads((self.book / "Contents" / "Resources" / "anchors.json").read_text(encoding="utf-8"))
        self.assertEqual(anchors, FIXTURE_IDS)
        self.assertFalse((self.book / "Contents" / "Resources" / "assets" / "search.js").exists())
        self.assertTrue((self.book / "Contents" / "Resources" / "pictures" / "first-steps-2-dark.webp").exists())

    def test_the_anchor_is_the_first_thing_in_the_body(self) -> None:
        self.build()
        for page_id in FIXTURE_IDS:
            text = (self.language_folder() / (page_id + ".html")).read_text(encoding="utf-8")
            self.assertIn('<body>\n<a name="' + page_id + '"></a>', text)
            self.assertLess(text.index('<a name="'), text.index("<h1>"))
            self.assertEqual(text.count("<a name="), 1)
            self.assertEqual(text.count("<h1>"), 1)
            self.assertIn('<meta name="color-scheme" content="light dark">', text)
            head = text[: text.index("</head>")]
            order = ["<meta charset", "<title>", 'name="keywords"', 'name="description"', 'name="robots"', 'name="color-scheme"']
            positions = [head.index(marker) for marker in order]
            self.assertEqual(positions, sorted(positions))
        contents = (self.language_folder() / "index.html").read_text(encoding="utf-8")
        self.assertIn('<a name="plantoir-help"></a>', contents)
        self.assertIn('content="anchors"', contents)
        self.assertNotIn("Planner's words", contents)

    def test_the_spotlight_index_lists_and_maps_every_anchor(self) -> None:
        self.build()
        listed = run_hiutil("hiutil", ["-I", "corespotlight", "-Af", CS_INDEX_NAME], self.language_folder()).split()
        for page_id in FIXTURE_IDS + ["plantoir-help"]:
            self.assertIn(page_id, listed)
        mapping = plistlib.loads(
            run_hiutil("hiutil", ["-I", "corespotlight", "-Df", CS_INDEX_NAME], self.language_folder()).encode("utf-8")
        )
        for page_id in FIXTURE_IDS:
            self.assertEqual(mapping[page_id], ["/" + page_id + ".html#" + page_id])

    def test_a_page_whose_first_anchor_is_another_fails_the_index_check(self) -> None:
        self.build()
        folder = self.language_folder()
        page = folder / "send-section.html"
        page.write_text(
            page.read_text(encoding="utf-8").replace("<body>\n", '<body>\n<a name="stray"></a>\n', 1), encoding="utf-8"
        )
        run_hiutil("hiutil", ["-I", "corespotlight", "-Caf", CS_INDEX_NAME, "-vv", "."], folder)
        with self.assertRaises(HelpError) as caught:
            verify_indexes("hiutil", folder, FIXTURE_IDS)
        self.assertIn("send-section -> ['/send-section.html#stray']", str(caught.exception))

    def test_a_deleted_page_leaves_no_stale_file(self) -> None:
        self.build()
        self.assertTrue((self.language_folder() / "send-section.html").exists())
        outline = json.loads(self.fixture.read("help/outline.json"))
        kept = []
        for entry in outline["sections"][1]["pages"]:
            if entry["id"] != "send-section":
                kept.append(entry)
        outline["sections"][1]["pages"] = kept
        outline["pageCount"] = 4
        self.fixture.write("help/outline.json", json.dumps(outline, indent=1, ensure_ascii=False))
        (self.fixture.help_dir / "pages" / "send-section.md").unlink()
        self.build()
        self.assertFalse((self.language_folder() / "send-section.html").exists())
        self.assertFalse(self.fixture.out.joinpath("Plantoir.help.building").exists())
        self.assertFalse(self.fixture.out.joinpath("Plantoir.help.old").exists())

    def test_an_unchanged_picture_keeps_its_inode(self) -> None:
        self.build()
        picture = self.book / "Contents" / "Resources" / "pictures" / "first-steps-2-light.webp"
        first = picture.stat().st_ino
        self.fixture.replace("help/pages/send-section.md", "afterwards", "when it finishes")
        self.build()
        self.assertEqual(picture.stat().st_ino, first)
        self.assertIn("when it finishes", (self.language_folder() / "send-section.html").read_text(encoding="utf-8"))

    def test_a_failed_build_leaves_the_old_book_and_no_building_folder(self) -> None:
        self.build()
        stale = self.fixture.out / "Plantoir.help.building"
        stale.mkdir()
        (stale / "leftover.txt").write_text("from an earlier run", encoding="utf-8")
        (self.fixture.help_dir / "assets" / "help.css").unlink()
        code, output = self.fixture.run("--mac", str(self.book), "--app-version", "2.0.0")
        self.assertNotEqual(code, 0, output)
        self.assertFalse(stale.exists())
        self.assertTrue((self.language_folder() / "first-steps.html").exists())

    def test_a_refused_page_writes_no_book(self) -> None:
        self.fixture.page("second-look", "<div>boxed</div>\n")
        code, output = self.fixture.run("--mac", str(self.book))
        self.assertNotEqual(code, 0, output)
        self.assertFalse(self.book.exists())


if __name__ == "__main__":
    unittest.main()
