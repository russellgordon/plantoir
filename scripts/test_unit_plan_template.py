#!/usr/bin/env python3
"""
The unit-plan template (#707) the `plantoir-unit-planning` skill copies from:
its two stylesheets, its fonts, and its pages.

Russell asked for "that exact format": his own plan site's look. So
each stylesheet is that site's own `<style>` block byte for byte
(`scripts/fixtures/unit_plan/`, CSS only, extracted once from the two pages),
after Plantoir's comment and its `@font-face` rules, with ONE edit: a `--ok`
colour token, so the reviewed mark has a dark-mode value (Russell's ruling 2).
This proves the sheet minus those is still the fixture, and that every rule
any shipped release defined is still there (`unitPlanning.appendOnly`).

What a page needs to look right offline is checked too: every page carries the
noindex meta, nothing points at the internet, every relative link and `url()`
resolves, every class a page uses has a rule in its sheet, and the fonts are
the bytes `contracts/shared-rules.json` -> `unitPlanning.agentGuidance.fonts`
pins.

Stdlib only, and nothing here reads the image: Windows' PythonToolchainTests
discovers this file and runs it from a plain checkout, where text files may
have CRLF line endings (read as text, so they compare alike) and the fonts
are binary.
"""
import hashlib
import json
import re
import unittest
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote

REPOSITORY = Path(__file__).resolve().parents[1]
SKILL = REPOSITORY / "support" / "agent_guidance" / "skills" / "plantoir-unit-planning"
TEMPLATE = SKILL / "template"
FIXTURES = REPOSITORY / "scripts" / "fixtures" / "unit_plan"
SHARED_RULES = REPOSITORY / "contracts" / "shared-rules.json"

# Each sheet, and the example page's block it is made from.
SHEETS = {"plan.css": "index-style.css", "correlation.css": "correlation-style.css"}
# Each page, and the sheet it links.
PAGES = {
    "index.html": "plan.css",
    "unit/index.html": "plan.css",
    "unit/correlation.html": "correlation.css",
}
FONTS_END = "/* fonts: end */\n"
OK_LINE = re.compile(r"^  --ok:#[0-9a-f]{6};\n", re.MULTILINE)
EXAMPLE_OK_COLOUR = "#1f7a3a"
CHECK_MARK = 0x2713


def read_text(path):
    # Universal newlines: a Windows checkout's CRLF reads as LF here.
    return path.read_text(encoding="utf-8")


def unit_planning():
    return json.loads(read_text(SHARED_RULES))["unitPlanning"]


def without_fonts(sheet_text):
    """The sheet after Plantoir's comment and its @font-face rules."""
    return sheet_text[sheet_text.index(FONTS_END) + len(FONTS_END):]


def as_the_example(sheet_text):
    """The sheet with Plantoir's one edit taken out again."""
    text = OK_LINE.sub("", without_fonts(sheet_text))
    return text.replace("var(--ok)", EXAMPLE_OK_COLOUR)


def font_faces(sheet_text):
    block = sheet_text[:sheet_text.index(FONTS_END)]
    return re.findall(r"@font-face\{([^}]*)\}", block)


def defined_classes(sheet_text):
    text = re.sub(r"/\*.*?\*/", "", without_fonts(sheet_text), flags=re.DOTALL)
    classes = set()
    for selector in re.findall(r"([^{}]+)\{", text):
        classes.update(re.findall(r"\.([A-Za-z_][\w-]*)", selector))
    return classes


def tokens_and_dark_blocks(sheet_text):
    """From the first :root to the end of the explicit dark block."""
    text = without_fonts(sheet_text)
    start = text.index(":root{")
    dark = text.index(':root[data-theme="dark"]{')
    end = text.index("}", dark) + 1
    return text[start:end]


def ranges_cover(unicode_range, code_point):
    for part in unicode_range.split(","):
        part = part.strip()[2:]
        if "-" in part:
            low, high = part.split("-")
        else:
            low = high = part
        if int(low, 16) <= code_point <= int(high, 16):
            return True
    return False


class PageReader(HTMLParser):
    """The classes, ids, links and head metas of one page, comments left out."""

    def __init__(self):
        super().__init__()
        self.classes = set()
        self.ids = set()
        self.links = []
        self.metas = []

    def handle_starttag(self, tag, attributes):
        values = dict(attributes)
        if "class" in values:
            self.classes.update(values["class"].split())
        if "id" in values:
            self.ids.add(values["id"])
        for name in ("href", "src"):
            if name in values:
                self.links.append(values[name])
        if tag == "meta":
            self.metas.append(values)


def read_page(relative):
    reader = PageReader()
    reader.feed(read_text(TEMPLATE / relative))
    return reader


class SheetsAreTheExampleTests(unittest.TestCase):

    def test_each_sheet_is_its_example_block_after_the_fonts_and_the_one_edit(self):
        for sheet, fixture in SHEETS.items():
            with self.subTest(sheet=sheet):
                example = read_text(FIXTURES / fixture)
                text = as_the_example(read_text(TEMPLATE / "assets" / sheet))
                self.assertTrue(
                    text.startswith(example),
                    f"assets/{sheet} is no longer the example's block: a rule was changed or removed "
                    "(unitPlanning.appendOnly allows rules ADDED at the end only)",
                )

    def test_the_one_edit_is_the_ok_token_in_both_sheets_and_the_mark_in_the_plan_sheet(self):
        for sheet in SHEETS:
            with self.subTest(sheet=sheet):
                text = without_fonts(read_text(TEMPLATE / "assets" / sheet))
                self.assertEqual(len(OK_LINE.findall(text)), 3, "--ok in :root and both dark blocks")
        plan = without_fonts(read_text(TEMPLATE / "assets" / "plan.css"))
        self.assertIn(".ok{", plan)
        self.assertIn("color:var(--ok)", plan)
        self.assertNotIn(EXAMPLE_OK_COLOUR + ";font-weight", plan)

    def test_the_tokens_and_dark_blocks_are_the_same_in_both_sheets(self):
        plan = tokens_and_dark_blocks(read_text(TEMPLATE / "assets" / "plan.css"))
        correlation = tokens_and_dark_blocks(read_text(TEMPLATE / "assets" / "correlation.css"))
        self.assertEqual(plan, correlation)
        self.assertIn("@media (prefers-color-scheme: dark)", plan)
        self.assertIn('[data-theme="dark"]', plan)

    def test_the_font_rules_are_the_same_in_both_sheets(self):
        plan = font_faces(read_text(TEMPLATE / "assets" / "plan.css"))
        correlation = font_faces(read_text(TEMPLATE / "assets" / "correlation.css"))
        self.assertEqual(plan, correlation)

    def test_every_class_every_shipped_release_defined_still_has_a_rule(self):
        shipped = json.loads(read_text(FIXTURES / "classes-shipped.json"))["releases"]
        self.assertIn("1.10.0", shipped)
        for release, sheets in shipped.items():
            for sheet, classes in sheets.items():
                defined = defined_classes(read_text(TEMPLATE / "assets" / sheet))
                for name in classes:
                    with self.subTest(release=release, sheet=sheet, name=name):
                        self.assertIn(name, defined, f".{name} shipped in {release} and has lost its rule")


class FontsTests(unittest.TestCase):

    def test_the_fonts_are_the_bytes_the_contract_pins_and_nothing_else(self):
        pinned = unit_planning()["agentGuidance"]["fonts"]
        on_disk = sorted(path.name for path in (TEMPLATE / "assets" / "fonts").glob("*.woff2"))
        self.assertEqual(sorted(Path(font["file"]).name for font in pinned), on_disk)
        for font in pinned:
            with self.subTest(file=font["file"]):
                data = (SKILL / font["file"]).read_bytes()
                self.assertEqual(len(data), font["bytes"])
                self.assertEqual(hashlib.sha256(data).hexdigest(), font["sha256"])

    def test_every_font_rule_names_a_font_that_is_there(self):
        named = set()
        for face in font_faces(read_text(TEMPLATE / "assets" / "plan.css")):
            match = re.search(r'url\("fonts/([^"]+)"\)', face)
            self.assertIsNotNone(match, face)
            self.assertTrue((TEMPLATE / "assets" / "fonts" / match.group(1)).is_file(), match.group(1))
            self.assertIn("unicode-range:", face)
            named.add(match.group(1))
        on_disk = set(path.name for path in (TEMPLATE / "assets" / "fonts").glob("*.woff2"))
        self.assertEqual(named, on_disk)
        self.assertTrue((TEMPLATE / "assets" / "fonts" / "OFL.txt").is_file(), "the fonts' licence travels with them")

    def test_the_check_mark_is_in_a_declared_range_of_every_family(self):
        # 707 plan review M3: the reviewed mark is real Plex, from the Pi subset.
        covered = {}
        for face in font_faces(read_text(TEMPLATE / "assets" / "plan.css")):
            family = re.search(r'font-family:"([^"]+)"', face).group(1)
            unicode_range = re.search(r"unicode-range:([^;}]+)", face).group(1)
            if ranges_cover(unicode_range, CHECK_MARK):
                covered[family] = True
        for family in ("IBM Plex Serif", "IBM Plex Sans", "IBM Plex Mono"):
            self.assertTrue(covered.get(family), f"{family} has no rule covering U+2713")


class PagesTests(unittest.TestCase):

    def test_the_template_is_the_files_the_contract_lists(self):
        guidance = unit_planning()["agentGuidance"]
        listed = set(guidance["template"])
        for font in guidance["fonts"]:
            listed.add(font["file"])
        on_disk = set()
        for path in TEMPLATE.rglob("*"):
            relative = path.relative_to(SKILL)
            # Finder's .DS_Store and the like are not the template's (review L5).
            if path.is_file() and not any(part.startswith(".") for part in relative.parts):
                on_disk.add(relative.as_posix())
        self.assertEqual(listed, on_disk)

    def test_every_page_asks_search_engines_to_stay_away(self):
        for page in PAGES:
            with self.subTest(page=page):
                metas = read_page(page).metas
                self.assertIn({"name": "robots", "content": "noindex, nofollow"}, metas)
        self.assertEqual(read_text(TEMPLATE / "robots.txt"), "User-agent: *\nDisallow: /\n")

    def test_nothing_in_the_template_points_at_the_internet(self):
        for path in TEMPLATE.rglob("*"):
            if path.suffix in (".html", ".css", ".json"):
                with self.subTest(file=path.name):
                    text = read_text(path)
                    self.assertNotRegex(text, r"https?://")
                    self.assertNotRegex(text, r"""(?:href|src)=["']//""")
                    self.assertNotRegex(text, r"""url\(\s*["']?//""")

    def test_every_page_links_its_own_sheet(self):
        for page, sheet in PAGES.items():
            with self.subTest(page=page):
                depth = page.count("/")
                expected = "../" * depth + "assets/" + sheet
                self.assertIn(expected, read_page(page).links)

    def test_every_relative_link_and_url_resolves(self):
        for page in PAGES:
            reader = read_page(page)
            for link in reader.links:
                with self.subTest(page=page, link=link):
                    target, _, fragment = link.partition("#")
                    if target:
                        resolved = (TEMPLATE / page).parent / unquote(target)
                        self.assertTrue(resolved.is_file(), f"{page} links {link}, which is not there")
                        if fragment:
                            self.assertIn(fragment, read_page(resolved.relative_to(TEMPLATE).as_posix()).ids)
                    elif fragment:
                        self.assertIn(fragment, reader.ids, f"{page} links #{fragment}, which is not on it")
        for sheet in SHEETS:
            text = read_text(TEMPLATE / "assets" / sheet)
            for target in re.findall(r'url\("([^"]+)"\)', text):
                with self.subTest(sheet=sheet, url=target):
                    self.assertTrue((TEMPLATE / "assets" / target).is_file())

    def test_every_answer_key_the_template_links_is_in_the_answer_keys_folder(self):
        """#833: the example plan, its commented patterns included, links every
        answer key inside the unit's Answer Keys folder, never in pdfs/."""
        import os
        import sys as _sys
        os.environ.setdefault("PLANTOIR_CONTRACTS_DIR", str(REPOSITORY / "contracts"))
        os.environ.setdefault("PLANTOIR_SUPPORT_DIR", str(REPOSITORY / "support"))
        _sys.path.insert(0, str(REPOSITORY / "scripts"))
        import unit_plan_site
        found = 0
        for page in PAGES:
            text = read_text(TEMPLATE / page)
            for target in re.findall(r'href="([^"#]+\.pdf)"', text):
                name = unquote(target).rsplit("/", 1)[-1]
                if unit_plan_site.is_answer_key(name):
                    found += 1
                    with self.subTest(page=page, link=target):
                        self.assertTrue(unit_plan_site.in_answer_keys_folder(unquote(target)),
                                        f"{page} links the answer key {target} outside Answer Keys/")
        self.assertGreater(found, 0, "the example plan should show where an answer key goes")

    def test_every_class_a_page_uses_has_a_rule_in_its_sheet(self):
        for page, sheet in PAGES.items():
            defined = defined_classes(read_text(TEMPLATE / "assets" / sheet))
            for name in sorted(read_page(page).classes):
                with self.subTest(page=page, name=name):
                    self.assertIn(name, defined)

    def test_the_example_plan_file_keeps_the_contracts_rules(self):
        rules = unit_planning()
        plan = json.loads(read_text(TEMPLATE / "unit" / "plan.json"))
        self.assertEqual(plan, rules["planFile"]["example"])
        for key in plan:
            self.assertIn(key, rules["planFile"]["keys"])
        self.assertRegex("unit", rules["slugRules"]["pattern"])
        self.assertNotIn("unit", rules["neverSlugs"])
        for name in rules["neverFolderNames"]:
            # Folders only: a Finder .DS_Store FILE is no fault (fix review L1).
            folders = [path for path in TEMPLATE.rglob(name) if path.is_dir()]
            self.assertFalse(folders, f"a folder called {name} is left out of a backup")


if __name__ == "__main__":
    unittest.main()
