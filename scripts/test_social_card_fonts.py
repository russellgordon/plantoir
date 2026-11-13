#!/usr/bin/env python3
"""
The social sharing card opens only the fonts Plantoir offers (GitHub #766).

Pillow 12.3.0's FreeType decodes WOFF2 fonts with Brotli 1.2.0, which
CVE-2026-111497 affects, and no Pillow release carries a fixed Brotli yet.
FreeType picks a font's format from the file's bytes, not its name, and the
card used to join a course's font name onto support/fonts/ unchecked, so an
absolute path or a ../ name could hand the decoder any file. Now only a name
in contracts/shared-rules.json -> socialCardFonts.fonts reaches a path; any
other is drawn in Inter, and the build says which name it did not use.
Measured, with what was rejected, in documentation/05-build-pipeline.md ->
"The social sharing card opens only Plantoir's own fonts (#766)".

Pinned here:

  * every contract case, through the card's own functions;
  * a real file at an absolute path, and one reached by ../, is never
    opened (measured opened by the code before #766);
  * a whole card drawn with an unknown name says so once, and is drawn;
  * every font the contract lists is in support/fonts and is TrueType, so
    the decoder never meets a WOFF2 file from this list;
  * the font names the mac app, the Windows app and setup_course.py offer
    are all in the contract's list, and the mac's bundled-font list is its
    files;
  * the sentence uses none of the words a teacher must not read.

Needs Pillow (the image and the Windows runtime carry it); skips without.
Pure stdlib otherwise, no Docker, no network. Run with:

    python3 scripts/test_social_card_fonts.py
"""

import io
import json
import os
import re
import shutil
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
SUPPORT = REPOSITORY_ROOT / "support"
FONTS = SUPPORT / "fonts"
sys.path.insert(0, str(REPOSITORY_ROOT / "scripts"))

os.environ.setdefault("PLANTOIR_CONTRACTS_DIR", str(REPOSITORY_ROOT / "contracts"))
os.environ.setdefault("PLANTOIR_SUPPORT_DIR", str(SUPPORT))

try:
    import PIL  # noqa: F401
    HAS_PILLOW = True
except ImportError:
    HAS_PILLOW = False

if HAS_PILLOW:
    import social_card  # noqa: E402


def the_rules():
    with open(REPOSITORY_ROOT / "contracts" / "shared-rules.json", encoding="utf-8") as handle:
        return json.load(handle)["socialCardFonts"]


def quoted_names_in(text):
    names = []
    for match in re.finditer(r'"([^"\\]+)"', text):
        names.append(match.group(1))
    return names


@unittest.skipUnless(HAS_PILLOW, "needs Pillow, which the image and the Windows runtime carry")
class TheCardsFontRule(unittest.TestCase):

    def file_name_of(self, font_name):
        found = social_card._font_file(font_name)
        self.assertIsNotNone(found, "no font at all was found, not even Inter")
        return found.name

    def test_every_contract_case(self):
        for case in the_rules()["cases"]:
            with self.subTest(case["name"]):
                self.assertEqual(self.file_name_of(case["header"]), case["headerFile"])
                self.assertEqual(self.file_name_of(case["body"]), case["bodyFile"])
                self.assertEqual(social_card.fonts_not_used(case["header"], case["body"]), case["told"])

    def test_every_offered_font_opens_its_own_file(self):
        for name, file_name in the_rules()["fonts"].items():
            with self.subTest(name):
                self.assertEqual(self.file_name_of(name), file_name)

    def test_a_real_file_at_an_absolute_path_is_never_opened(self):
        folder = Path(tempfile.mkdtemp(prefix="plantoir-766-"))
        self.addCleanup(shutil.rmtree, folder, True)
        planted = folder / "Planted.ttf"
        shutil.copyfile(FONTS / "Lora.ttf", planted)
        name = str(folder / "Planted")
        self.assertEqual(self.file_name_of(name), "Inter.ttf")
        self.assertEqual(social_card.fonts_not_used(name, "Inter"), [name[:60] + ("…" if len(name) > 60 else "")])

    def test_a_real_file_reached_by_climbing_out_is_never_opened(self):
        folder = Path(tempfile.mkdtemp(prefix="plantoir-766-"))
        self.addCleanup(shutil.rmtree, folder, True)
        planted = folder / "Planted.ttf"
        shutil.copyfile(FONTS / "Lora.ttf", planted)
        climbing = os.path.relpath(str(folder / "Planted"), str(FONTS))
        self.assertTrue(climbing.startswith(".."), climbing)
        self.assertEqual(self.file_name_of(climbing), "Inter.ttf")

    def test_a_card_with_an_unknown_name_is_drawn_and_says_so_once(self):
        folder = Path(tempfile.mkdtemp(prefix="plantoir-766-"))
        self.addCleanup(shutil.rmtree, folder, True)
        config = {
            "course_name": "Sample Course",
            "course_code": "ABC1D",
            "fonts": {"default": {"header": "Nunito", "body": "Nunito", "code": "Fira Code"}},
        }
        printed = io.StringIO()
        with redirect_stdout(printed):
            card = social_card.generate_card(config, 1, folder / "og-image.png")
        self.assertTrue(card.is_file())
        sentence = the_rules()["wording"]["unknownFontName"].replace("{name}", "Nunito")
        self.assertEqual(printed.getvalue().splitlines(), [sentence])

    def test_a_card_with_offered_fonts_says_nothing(self):
        folder = Path(tempfile.mkdtemp(prefix="plantoir-766-"))
        self.addCleanup(shutil.rmtree, folder, True)
        config = {
            "course_name": "Sample Course",
            "course_code": "ABC1D",
            "fonts": {"sections": {"section1": {"header": "Montserrat", "body": "Lora"}}},
        }
        printed = io.StringIO()
        with redirect_stdout(printed):
            social_card.generate_card(config, 1, folder / "og-image.png")
        self.assertEqual(printed.getvalue(), "")


class TheListItself(unittest.TestCase):

    def test_every_listed_font_is_bundled_truetype(self):
        rules = the_rules()
        listed = list(rules["fonts"].values()) + [rules["fallbackFile"]]
        for file_name in listed:
            with self.subTest(file_name):
                self.assertNotIn("/", file_name)
                self.assertNotIn("\\", file_name)
                path = FONTS / file_name
                self.assertTrue(path.is_file(), f"support/fonts/{file_name} is missing")
                with open(path, "rb") as handle:
                    self.assertEqual(handle.read(4), b"\x00\x01\x00\x00",
                                     f"{file_name} is not plain TrueType, so it may reach the Brotli decoder")

    def test_the_mac_apps_offered_names_are_listed(self):
        text = (REPOSITORY_ROOT / "mac-app" / "QuartzTeachers" / "Catalogs" / "FontCatalog.swift").read_text(encoding="utf-8")
        self.assert_all_known(quoted_names_in(text[text.index("static let pairings"):text.index("// MARK: - Functions")]),
                              "FontCatalog.swift")

    def test_the_windows_apps_offered_names_are_listed(self):
        text = (REPOSITORY_ROOT / "windows-app" / "Plantoir.Core" / "Catalogs" / "StaticCatalogs.cs").read_text(encoding="utf-8")
        start = text.index("public sealed record Pairing")
        end = text.index("The pairing's label")
        self.assert_all_known(quoted_names_in(text[start:end]), "StaticCatalogs.cs")

    def test_setup_course_offers_only_listed_names(self):
        text = (REPOSITORY_ROOT / "scripts" / "setup_course.py").read_text(encoding="utf-8")
        start = text.index("FONT_PAIRINGS = [")
        end = text.index("]", text.index("CODE_FONTS = ["))
        self.assert_all_known(quoted_names_in(text[start:end]), "setup_course.py")

    def assert_all_known(self, names, where):
        rules = the_rules()
        self.assertGreater(len(names), 5, f"read no font names out of {where}")
        for name in names:
            if name.startswith("System fonts"):
                continue
            self.assertTrue(name in rules["fonts"] or name in rules["silentNames"],
                            f"{where} offers \"{name}\", which socialCardFonts.fonts does not list")

    def test_the_mac_apps_bundled_fonts_are_the_listed_files(self):
        text = (REPOSITORY_ROOT / "mac-app" / "QuartzTeachers" / "Catalogs" / "BundledFontList.swift").read_text(encoding="utf-8")
        bundled = []
        for match in re.finditer(r'case \w+ = "([^"]+)"', text):
            bundled.append(match.group(1) + ".ttf")
        self.assertEqual(sorted(bundled), sorted(the_rules()["fonts"].values()))

    def test_the_sentence_says_nothing_about_the_machinery(self):
        with open(REPOSITORY_ROOT / "contracts" / "shared-rules.json", encoding="utf-8") as handle:
            forbidden = json.load(handle)["userFacingLabelWords"]["forbidden"]
        sentence = the_rules()["wording"]["unknownFontName"]
        self.assertIn("{name}", sentence)
        for word in re.findall(r"[a-z]+", sentence.lower()):
            self.assertNotIn(word, forbidden)


if __name__ == "__main__":
    unittest.main(verbosity=2)
