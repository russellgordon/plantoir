#!/usr/bin/env python3
"""
The map Plantoir shows on a section's Coverage tab (#793, the 793a half): the
curriculum coverage map as it would be if every existing page were published,
written by every build BESIDE the section's built website.

The rule cases are deserialised from `contracts/shared-rules.json` ->
`coverageTab` (`whatCounts.countingCases`, `countLines`, `link`, `escaping`,
`pageWords`), and the record from `contracts/file-formats.json` ->
`coverageTabMap`. The site's own map is held to the goldens in
test_coverage_maps.py, which must stay green beside this file: one counting
function serves both maps, and the site's page must not move by a byte.

It needs python-frontmatter (the counting cases go through the build's own
process_frontmatter), which on the mac is only in the image: verify.sh runs
it there, with deploy.sh mounted beside it, and Windows' PythonToolchainTests
discovers it. Temporary folders, no network. Nothing here makes a file or
folder whose name Windows refuses (<, >, " and | are handed in as data).
"""
import errno
import hashlib
import html
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from html.parser import HTMLParser
from pathlib import Path

scripts_dir = Path(__file__).resolve().parent
if str(scripts_dir) not in sys.path:
    sys.path.insert(0, str(scripts_dir))

import build_site  # noqa: E402
import contracts  # noqa: E402
import toolchain_paths  # noqa: E402

REPOSITORY_ROOT = scripts_dir.parent
BUILD_ID = "20261112T190405Z-ab12cd34"


def use_the_repository_contracts():
    repo_contracts = REPOSITORY_ROOT / "contracts"
    if repo_contracts.is_dir():
        toolchain_paths.CONTRACTS_DIR = repo_contracts
    contracts.reset_cache()


def coverage_tab_contract() -> dict:
    with open(REPOSITORY_ROOT / "contracts" / "shared-rules.json", encoding="utf-8") as handle:
        return json.load(handle)["coverageTab"]


def coverage_tab_record_contract() -> dict:
    with open(REPOSITORY_ROOT / "contracts" / "file-formats.json", encoding="utf-8") as handle:
        return json.load(handle)["coverageTabMap"]


def schemes() -> list:
    with open(REPOSITORY_ROOT / "support" / "colour_schemes.json", encoding="utf-8") as handle:
        return json.load(handle)


def write(path: Path, text: str):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


class Course:
    """
    A course folder and the build's copy of it, laid out the way the build
    lays it out: every file copied into a fresh content folder, its source
    remembered, and `process_frontmatter` run on it for the section, which
    resolves publishForSection<N> and hides a page whose settings cannot be
    read (#246).
    """

    def __init__(self, root: Path, curriculum: dict, pages: dict, section: int,
                 class_folders=None, graded_folders=None, curriculum_folder="Curriculum",
                 section_pages=None):
        self.root = root
        self.course_dir = root / "course"
        self.content_root = root / "content"
        self.host_output_dir = root / "builds" / "COURSE" / f"section{section}"
        self.section = section
        self.class_folders = class_folders if class_folders is not None else ["All Classes"]
        self.graded_folders = graded_folders if graded_folders is not None else ["Tasks"]
        self.configured = [curriculum_folder]
        files = {}
        for place, text in curriculum.items():
            files[place] = text
        for place, text in pages.items():
            files[place] = text
        for place, text in files.items():
            write(self.course_dir / place, text)
        self.content_root.mkdir(parents=True)
        build_site.forget_vault_sources(self.course_dir)
        build_site.forget_unreadable_pages()
        quiet = io.StringIO()
        with redirect_stdout(quiet):
            for place in sorted(files):
                source = self.course_dir / place
                copy = self.content_root / place
                copy.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, copy)
                build_site.remember_vault_source(copy, source, is_section_page=False)
                build_site.process_frontmatter(copy, section)
            if section_pages:
                section_dir = self.course_dir / f"section{section}"
                folders = set()
                for place, text in section_pages.items():
                    write(section_dir / place, text)
                    folders.add(Path(place).parts[0])
                build_site.copy_the_per_section_folders(section_dir, self.content_root,
                                                        sorted(folders), section)
        self.host_output_dir.mkdir(parents=True)
        self.plan = build_site.plan_coverage_maps(self.content_root, self.configured)
        build_site.set_coverage_titles([title for _, title in self.plan])
        self.taught = build_site._pages_the_course_teaches(self.content_root, self.class_folders)

    def unreadable_copies(self) -> list:
        return build_site.copies_still_unreadable()

    def published(self):
        """The site's count, called as build_curriculum_coverage calls it."""
        folder, _ = self.plan[0]
        specific, overall = build_site._collect_expectations(folder, printer=lambda line: None)
        mapped = [entry for entry, _ in self.plan]
        covered_by, assessed_by = build_site._coverage_counts(
            self.content_root, mapped, specific, self.class_folders, self.graded_folders,
            True, taught=self.taught)
        return specific, overall, covered_by, assessed_by

    def every_page(self) -> dict:
        return build_site.coverage_as_if_published(
            self.content_root, self.course_dir, self.plan, self.class_folders,
            self.graded_folders, True, self.taught, self.unreadable_copies())

    def write_tab(self, config=None, site_map_on=True, words=None, printer=None):
        arguments = (self.host_output_dir, self.content_root, self.course_dir, "COURSE",
                     "COURSE", self.section, BUILD_ID, "preview", self.plan,
                     self.class_folders, self.graded_folders, True, self.taught,
                     config or {}, site_map_on)
        keywords = {"schemes": schemes()}
        if words is not None:
            keywords["words"] = words
        if printer is not None:
            return build_site.make_the_coverage_tab(*arguments, printer=printer, **keywords)
        return build_site.write_coverage_tab(*arguments, **keywords)


def counts_by_code(specific: dict, covered_by: dict, assessed_by: dict) -> dict:
    answer = {}
    for code in specific:
        answer[code] = {"count": len(covered_by[code]), "assessed": bool(assessed_by[code])}
    return answer


def expected_counts(specific: dict, listed: dict) -> dict:
    answer = {}
    for code in specific:
        if code in listed:
            answer[code] = listed[code]
        else:
            answer[code] = {"count": 0, "assessed": False}
    return answer


CHIP = re.compile(r'coverage-chip coverage-chip-(yes|no)"[^>]*>([^<]+)</')


def chips_of(columns: list) -> dict:
    answer = {}
    for match in CHIP.finditer("".join(columns)):
        answer[match.group(2)] = match.group(1) == "yes"
    return answer


class Attributes(HTMLParser):
    """Every tag and attribute on a page, to check what it may carry."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.tags = []
        self.attributes = []
        self.hrefs = []
        self.text = []

    def handle_starttag(self, tag, attrs):
        self.tags.append(tag)
        for name, value in attrs:
            self.attributes.append((tag, name, value))
            if name == "href":
                self.hrefs.append(value)

    def handle_data(self, data):
        self.text.append(data)


ALLOWED_TAGS = {"html", "head", "meta", "title", "style", "body", "main", "h1", "h2", "p", "bdi",
                "section", "div", "a", "span", "hr", "table", "caption", "tr", "th", "td"}
ALLOWED_ATTRIBUTES = {"lang", "charset", "http-equiv", "content", "name", "class", "href",
                      "aria-label", "title", "role", "data-assessed", "id",
                      "aria-labelledby", "scope"}
LINK = re.compile(r"plantoir-coverage:open/[0-9A-Za-z-]+/\d+/[0-9A-Za-z.-]+")


def read_page(text: str) -> Attributes:
    parser = Attributes()
    parser.feed(text)
    parser.close()
    return parser


CURRICULUM = None


def the_counting_fixture() -> dict:
    return coverage_tab_contract()["whatCounts"]["countingCases"]


# === The counting cases (coverageTab.whatCounts.countingCases) ===============

class TheCountingCases(unittest.TestCase):

    def setUp(self):
        use_the_repository_contracts()

    def test_there_are_cases(self):
        self.assertGreaterEqual(len(the_counting_fixture()["cases"]), 12)

    def test_every_case_both_ways(self):
        fixture = the_counting_fixture()
        for case in fixture["cases"]:
            with self.subTest(case["name"]), tempfile.TemporaryDirectory() as temp:
                course = Course(Path(temp), fixture["curriculum"], case["pages"], case["section"],
                                class_folders=fixture["classFolders"],
                                graded_folders=fixture["gradedFolders"],
                                section_pages=case.get("sectionPages"))
                specific, overall, covered_by, assessed_by = course.published()
                self.assertEqual(counts_by_code(specific, covered_by, assessed_by),
                                 expected_counts(specific, case["expect"]["published"]),
                                 "the site's map")
                if "publishedChips" in case["expect"]:
                    columns, _ = build_site._coverage_columns(
                        course.content_root, specific, overall, covered_by, assessed_by)
                    self.assertEqual(chips_of(columns), case["expect"]["publishedChips"])

                answer = course.every_page()
                self.assertEqual(len(answer["maps"]), 1)
                one_map = answer["maps"][0]
                self.assertEqual(
                    counts_by_code(one_map["specific"], one_map["covered_by"], one_map["assessed_by"]),
                    expected_counts(one_map["specific"], case["expect"]["everyPage"]),
                    "the map for the app")
                if "everyPageChips" in case["expect"]:
                    columns, _ = build_site._coverage_columns(
                        None, one_map["specific"], one_map["overall"], one_map["covered_by"],
                        one_map["assessed_by"], href_for=lambda code, page: None,
                        labels=coverage_tab_contract()["pageWords"])
                    self.assertEqual(chips_of(columns), case["expect"]["everyPageChips"])
                self.assertEqual(answer["hiddenCounted"], case["expect"]["hiddenCounted"])

                record = course.write_tab()
                self.assertEqual(record["hiddenPagesCounted"], case["expect"]["hiddenCounted"])
                self.assertEqual(record["unreadablePagesLeftOut"],
                                 case["expect"]["unreadableLeftOut"])

    def test_the_site_passes_neither_new_argument(self):
        # The site's call in build_curriculum_coverage is today's call: no
        # every_page and no leave_out, so its count is the published one.
        source = Path(build_site.__file__).read_text(encoding="utf-8")
        start = source.index("def build_curriculum_coverage(")
        end = source.index("\ndef ", start + 1)
        body = source[start:end]
        self.assertIn("_coverage_counts(", body)
        self.assertNotIn("every_page", body)
        self.assertNotIn("leave_out", body)


# === The page ================================================================

def the_anti_drift_course(temp: str, section=1, **keywords) -> Course:
    fixture = the_counting_fixture()
    case = None
    for candidate in fixture["cases"]:
        if "anti-drift" in candidate["name"]:
            case = candidate
    return Course(Path(temp), fixture["curriculum"], case["pages"], section,
                  class_folders=fixture["classFolders"],
                  graded_folders=fixture["gradedFolders"], **keywords)


def panel_of(text: str) -> str:
    start = text.index('<div class="coverage-panel">')
    end = text.index("</div>\n</div>", start) + len("</div>\n</div>")
    return text[start:end]


ATTRIBUTES_ONLY_ONE_MAP_HAS = re.compile(r'\s(?:href|title|aria-label|role)="[^"]*"')


class TheTwoPanelsAreOnePanel(unittest.TestCase):

    def setUp(self):
        use_the_repository_contracts()

    def test_with_every_page_published_the_panels_differ_only_in_links_and_labels(self):
        with tempfile.TemporaryDirectory() as temp:
            course = the_anti_drift_course(temp)
            with redirect_stdout(io.StringIO()):
                build_site.build_curriculum_coverage(
                    course.content_root, "COURSE", class_folders=course.class_folders,
                    graded_folders=course.graded_folders, graded_was_configured=True,
                    configured_folders=course.configured, taught=course.taught)
            site = (course.content_root / "Curriculum Coverage.md").read_text(encoding="utf-8")
            course.write_tab()
            record = json.loads((build_site.coverage_tab_folder(course.host_output_dir)
                                 / "about.json").read_text(encoding="utf-8"))
            tab = (build_site.coverage_tab_folder(course.host_output_dir)
                   / record["page"]).read_text(encoding="utf-8")
            site_panel = ATTRIBUTES_ONLY_ONE_MAP_HAS.sub("", panel_of(site))
            tab_panel = ATTRIBUTES_ONLY_ONE_MAP_HAS.sub("", panel_of(tab))
            self.assertEqual(tab_panel, site_panel)

    def test_the_site_stylesheet_is_byte_for_byte_what_it_was(self):
        # Captured from origin/dev e7c452711's append_coverage_styles over
        # this same one-line file, before coverage_stylesheet was split out.
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "base.scss"
            path.write_text("body { color: red; }\n", encoding="utf-8")
            # Hashed with CRLF read as LF: on Windows Python's text mode writes
            # every "\n" of the stylesheet as "\r\n" (here and in the product,
            # write_text), which changes the bytes and not the stylesheet
            # (step 0 of v2.0.0). On the mac and in the container nothing is
            # translated, so this is the very hash it always was.
            def lf_hash():
                return hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest()
            with redirect_stdout(io.StringIO()):
                build_site.append_coverage_styles(path)
                first = lf_hash()
                build_site.append_coverage_styles(path)
                second = lf_hash()
            expected = "ec55f70196542ea0d00b1c114e8b465fc538061d25c38119278441b19ba7062b"
            self.assertEqual(first, expected)
            self.assertEqual(second, expected, "an earlier block is replaced, not repeated")

    def test_the_page_carries_the_sites_stylesheet(self):
        with tempfile.TemporaryDirectory() as temp:
            course = the_anti_drift_course(temp)
            record = course.write_tab()
            tab = (build_site.coverage_tab_folder(course.host_output_dir)
                   / record["page"]).read_text(encoding="utf-8")
            self.assertIn(build_site.coverage_stylesheet(), tab)


def a_page(temp: str, **keywords) -> tuple:
    course = the_anti_drift_course(temp, **keywords)
    record = course.write_tab()
    text = (build_site.coverage_tab_folder(course.host_output_dir)
            / record["page"]).read_text(encoding="utf-8")
    return course, record, text


class NothingRunsAndNothingReachesOut(unittest.TestCase):

    def setUp(self):
        use_the_repository_contracts()

    def test_no_script_no_event_no_outside_reference(self):
        with tempfile.TemporaryDirectory() as temp:
            _, _, text = a_page(temp)
            lowered = text.lower()
            for needle in ("<script", "javascript:", "http:", "https:", "//", "url(",
                           "@import", "<link", "<img", "<iframe", "<object", "<embed",
                           "src=", "<form", "<base", "refresh"):
                self.assertNotIn(needle, lowered, needle)
            self.assertIsNone(re.search(r"\son[a-z]+\s*=", lowered))
            parsed = read_page(text)
            for tag in parsed.tags:
                self.assertIn(tag, ALLOWED_TAGS)
            for tag, name, _ in parsed.attributes:
                self.assertIn(name, ALLOWED_ATTRIBUTES, f"{tag} {name}")
            self.assertTrue(parsed.hrefs)
            for href in parsed.hrefs:
                self.assertIsNotNone(LINK.fullmatch(href), href)

    def test_the_content_security_policy_allows_nothing_from_outside(self):
        with tempfile.TemporaryDirectory() as temp:
            _, _, text = a_page(temp)
            self.assertIn('<meta http-equiv="Content-Security-Policy" '
                          "content=\"default-src 'none'; style-src 'unsafe-inline'\">", text)
            self.assertTrue(text.startswith("<!doctype html>\n"))
            self.assertIn('<meta charset="utf-8">', text)

    def test_every_cell_and_chip_says_its_state_in_words(self):
        with tempfile.TemporaryDirectory() as temp:
            _, _, text = a_page(temp)
            cells = re.findall(r'<(?:a|span) class="(?:internal )?coverage-(?:cell|chip) [^>]*>', text)
            self.assertTrue(cells)
            for cell in cells:
                label = re.search(r'aria-label="([^"]+)"', cell)
                title = re.search(r'title="([^"]+)"', cell)
                self.assertIsNotNone(label, cell)
                self.assertIsNotNone(title, cell)
                self.assertEqual(label.group(1), title.group(1))
            words = coverage_tab_contract()["pageWords"]
            self.assertIn(words["chipAssessed"].replace("{code}", "B1"), text)
            self.assertIn(words["chipNotAssessed"].replace("{code}", "A1"), text)

    def test_the_standings_are_a_table_with_row_headings(self):
        with tempfile.TemporaryDirectory() as temp:
            _, _, text = a_page(temp)
            for key in ("total", "uncovered", "once", "unevaluated"):
                self.assertIn(f'<tr><th scope="row">{build_site.COVERAGE_STANDING_ROWS[key]}</th>',
                              text)
            self.assertIn('<tr><th scope="row">Specific expectations</th><td>3</td></tr>', text)


class TheLinks(unittest.TestCase):

    def setUp(self):
        use_the_repository_contracts()

    def test_every_link_case(self):
        for case in coverage_tab_contract()["link"]["cases"]:
            with self.subTest(case["name"]):
                self.assertEqual(build_site.coverage_tab_link(case["buildId"], case["map"], case["code"]),
                                 case["expect"])

    def test_the_page_links_each_code_to_its_own_build_map_and_code(self):
        with tempfile.TemporaryDirectory() as temp:
            _, record, text = a_page(temp)
            hrefs = read_page(text).hrefs
            for code in ("A1.1", "A1.2", "B1.1", "A1", "B1"):
                self.assertIn(build_site.coverage_tab_link(BUILD_ID, 0, code), hrefs)
                self.assertIn(code, record["maps"][0]["pages"])
            self.assertEqual(record["maps"][0]["pages"]["A1.1"], "Curriculum/A1.1.md")
            self.assertEqual(record["maps"][0]["pages"]["A1"], "Curriculum/A1. Ideas.md")

    def test_a_code_whose_page_the_build_cannot_name_is_not_a_link(self):
        with tempfile.TemporaryDirectory() as temp:
            course = the_anti_drift_course(temp)
            # As if the build had made A1.2's page itself: no source recorded.
            del build_site._vault_sources[course.content_root / "Curriculum" / "A1.2.md"]
            record = course.write_tab()
            text = (build_site.coverage_tab_folder(course.host_output_dir)
                    / record["page"]).read_text(encoding="utf-8")
            self.assertNotIn("A1.2", record["maps"][0]["pages"])
            self.assertNotIn(build_site.coverage_tab_link(BUILD_ID, 0, "A1.2"), text)
            self.assertIn('<span class="coverage-cell coverage-1" role="img" '
                          'aria-label="A1.2, addressed once"', text)

    def test_every_path_in_the_record_is_inside_the_course_folder(self):
        # The plan review's M5: a shared curriculum page and a section's own
        # both get an entry, and every entry is a file inside the course.
        with tempfile.TemporaryDirectory() as temp:
            course = the_anti_drift_course(temp)
            section_copy = course.content_root / "Curriculum" / "B1.1.md"
            section_source = course.course_dir / "section1" / "Curriculum" / "B1.1.md"
            write(section_source, "---\ntitle: B1.1\n---\nDescribe a system, this section's way.\n")
            build_site.remember_vault_source(section_copy, section_source, is_section_page=True)
            record = course.write_tab()
            pages = record["maps"][0]["pages"]
            self.assertEqual(pages["B1.1"], "section1/Curriculum/B1.1.md")
            self.assertEqual(sorted(pages), sorted(["A1.1", "A1.2", "B1.1", "A1", "B1"]))
            inside = course.course_dir.resolve()
            for place in pages.values():
                joined = (course.course_dir / place).resolve()
                self.assertTrue(joined.is_file(), place)
                joined.relative_to(inside)


class Escaping(unittest.TestCase):

    def setUp(self):
        use_the_repository_contracts()

    def render(self, case: dict) -> str:
        words = coverage_tab_contract()["pageWords"]
        with tempfile.TemporaryDirectory() as temp:
            course = the_anti_drift_course(temp)
            answer = course.every_page()
        one_map = answer["maps"][0]
        if "curriculumFolder" in case:
            one_map["folder"] = case["curriculumFolder"]
            one_map["title"] = build_site.coverage_page_titles(
                ["Curriculum", case["curriculumFolder"]], "Curriculum")[1]
            one_map["namesTheFolder"] = True
        if "overallPage" in case:
            one_map["overall"]["A1"] = Path("Curriculum") / f"{case['overallPage']}.md"
        course_code = case.get("courseCode", "ICS3U")
        return build_site.coverage_tab_page([one_map], course_code, 1, BUILD_ID,
                                            build_site.coverage_tab_scheme_colours({}, 1, schemes()),
                                            words, 1, 1, True)

    def test_every_escaping_case(self):
        for case in coverage_tab_contract()["escaping"]["cases"]:
            with self.subTest(case["name"]):
                text = self.render(case)
                for needle in case["mustNotContain"]:
                    self.assertNotIn(needle, text)
                for needle in case["mustContain"]:
                    self.assertIn(needle, text)
                parsed = read_page(text)
                for tag in parsed.tags:
                    self.assertIn(tag, ALLOWED_TAGS)
                for tag, name, _ in parsed.attributes:
                    self.assertIn(name, ALLOWED_ATTRIBUTES, f"{tag} {name}")
                for href in parsed.hrefs:
                    self.assertIsNotNone(LINK.fullmatch(href), href)
                self.assertEqual(len(parsed.hrefs), 5)

    def test_the_folders_title_is_text_on_the_page(self):
        case = {"curriculumFolder": "Curriculum <script>x<script>"}
        parsed = read_page(self.render(case))
        self.assertIn("Every expectation in Curriculum <script>x<script> for ICS3U, coloured by "
                      "how many pages would address it if every page were published.",
                      "".join(parsed.text))


def on_the_page(sentence: str) -> str:
    """A sentence as the page writes it: escaped, apostrophes included."""
    return html.escape(sentence, quote=True)


class TheWords(unittest.TestCase):

    def setUp(self):
        use_the_repository_contracts()

    def test_the_words_reach_the_page_verbatim(self):
        words = coverage_tab_contract()["pageWords"]
        with tempfile.TemporaryDirectory() as temp:
            _, _, text = a_page(temp)
        for key in ("heading", "chipsHint", "standingsCaption", "whatCountsHere", "hiddenNone"):
            self.assertIn(on_the_page(words[key]), text, key)
        shown = "".join(read_page(text).text)
        self.assertIn(words["subheading"].replace("{course}", "COURSE").replace("{section}", "1"), shown)
        self.assertIn(words["intro"].replace("{course}", "COURSE"), shown)
        self.assertIn("<bdi>COURSE</bdi>", text)
        self.assertNotIn(on_the_page(words["whatCountsHereSiteMapOff"]), text)
        self.assertNotIn(on_the_page(words["unreadableOne"]), text)

    def test_a_section_whose_site_map_is_off_says_so(self):
        words = coverage_tab_contract()["pageWords"]
        with tempfile.TemporaryDirectory() as temp:
            course = the_anti_drift_course(temp)
            record = course.write_tab(site_map_on=False)
            text = (build_site.coverage_tab_folder(course.host_output_dir)
                    / record["page"]).read_text(encoding="utf-8")
        self.assertIn(on_the_page(words["whatCountsHereSiteMapOff"]), text)
        self.assertNotIn(on_the_page(words["whatCountsHere"]), text)
        self.assertFalse(record["siteMapSwitchedOn"])

    def test_every_count_lines_case(self):
        words = coverage_tab_contract()["pageWords"]
        for case in coverage_tab_contract()["countLines"]["cases"]:
            with self.subTest(case):
                lines = build_site._coverage_tab_count_lines(words, case["hidden"], case["unreadable"])
                expected = []
                for key in case["expectLines"]:
                    expected.append(words[key].replace("{n}", str(case["unreadable"] if key.startswith("unreadable") else case["hidden"])))
                self.assertEqual(lines, expected)

    def test_no_word_names_the_machinery(self):
        # Rule 1 of CLAUDE.md, for the page a teacher reads.
        words = coverage_tab_contract()["pageWords"]
        for key, sentence in words.items():
            if key == "note":
                continue
            for banned in ("toolchain", "script", "docker", "container", "build_site"):
                self.assertNotIn(banned, sentence.lower(), key)


class TheColours(unittest.TestCase):

    def setUp(self):
        use_the_repository_contracts()

    def colours_on_the_page(self, config: dict, section: int) -> tuple:
        with tempfile.TemporaryDirectory() as temp:
            course = the_anti_drift_course(temp, section=section)
            record = course.write_tab(config=config)
            text = (build_site.coverage_tab_folder(course.host_output_dir)
                    / record["page"]).read_text(encoding="utf-8")
        light = re.search(r":root \{\n(.*?)\n\}", text, re.S).group(1)
        dark = re.search(r"@media \(prefers-color-scheme: dark\) \{\n:root \{\n(.*?)\n\}", text, re.S).group(1)
        return light, dark

    def test_the_sections_own_scheme(self):
        config = {"color_schemes": {"section1": "forest-moss", "section2": "coastal-breeze"}}
        light, dark = self.colours_on_the_page(config, 2)
        self.assertIn("--light: #f7fbfd;", light)
        self.assertIn("--light: #0f1419;", dark)
        light_one, _ = self.colours_on_the_page(config, 1)
        forest = build_site.find_scheme_by_id(schemes(), "forest-moss")["colors"]["lightMode"]["light"]
        self.assertIn(f"--light: {forest};", light_one)
        self.assertNotEqual(light_one, light)

    def test_no_choice_or_an_unknown_one_is_the_standard_scheme(self):
        for config in ({}, {"color_schemes": {"section1": "no-such-scheme"}}, {"color_schemes": None}):
            with self.subTest(config):
                light, dark = self.colours_on_the_page(config, 1)
                self.assertIn("--light: #faf8f8;", light)
                self.assertIn("--light: #161618;", dark)
                for key in build_site.COVERAGE_TAB_COLOUR_KEYS:
                    self.assertIn(f"--{key}: ", light)
                    self.assertIn(f"--{key}: ", dark)

    def test_a_value_that_is_not_plainly_a_colour_is_left_out(self):
        rules = build_site._coverage_tab_colour_rules({"light": "#fff; } body { display: none",
                                                       "dark": "#123456"})
        self.assertEqual(rules, "  --dark: #123456;")


# === Where it is written, and when ============================================

class WhereItIsWritten(unittest.TestCase):

    def setUp(self):
        use_the_repository_contracts()

    def test_beside_the_site_never_in_it_and_the_record_is_written_last(self):
        with tempfile.TemporaryDirectory() as temp:
            course = the_anti_drift_course(temp)
            public = course.host_output_dir / "public"
            write(public / "index.html", "<html>site</html>")
            folder = build_site.coverage_tab_folder(course.host_output_dir)
            write(folder / "map-old.html", "an older map")
            write(folder / "notes.txt", "not ours")
            before_public = sorted(path.relative_to(public).as_posix() for path in public.rglob("*"))
            before_content = sorted(path.relative_to(course.content_root).as_posix()
                                    for path in course.content_root.rglob("*"))
            record = course.write_tab()
            self.assertEqual(folder, course.host_output_dir / ".coverage-tab")
            self.assertEqual(record["page"], f"map-{BUILD_ID}.html")
            self.assertTrue((folder / record["page"]).is_file())
            self.assertFalse((folder / "map-old.html").exists())
            self.assertTrue((folder / "notes.txt").exists(), "only map-*.html pages are removed")
            names = sorted(os.listdir(folder))
            self.assertEqual(names, sorted(["about.json", record["page"], "notes.txt"]))
            self.assertEqual(sorted(path.relative_to(public).as_posix() for path in public.rglob("*")),
                             before_public)
            self.assertEqual(sorted(path.relative_to(course.content_root).as_posix()
                                    for path in course.content_root.rglob("*")), before_content)
            on_disk = json.loads((folder / "about.json").read_text(encoding="utf-8"))
            self.assertEqual(on_disk, record)

    def test_the_record_has_exactly_the_contracts_keys(self):
        with tempfile.TemporaryDirectory() as temp:
            _, record, _ = a_page(temp)
        contract = coverage_tab_record_contract()
        self.assertEqual(sorted(record), sorted(contract["keys"]))
        self.assertEqual(sorted(record["maps"][0]), sorted(contract["mapKeys"]))
        self.assertEqual(record["version"], 1)
        self.assertEqual(record["course"], "COURSE")
        self.assertEqual(record["section"], 1)
        self.assertEqual(record["buildId"], BUILD_ID)
        self.assertEqual(record["occasion"], "preview")
        self.assertEqual(record["maps"][0]["title"], "Curriculum Coverage")
        self.assertEqual(record["maps"][0]["expectations"], 3)
        self.assertEqual(record["maps"][0]["notYetAddressed"], 0)
        self.assertEqual(record["maps"][0]["addressedOnce"], 1)
        self.assertEqual(record["maps"][0]["overallWithoutAssessedWork"], 1)

    def test_no_curriculum_means_no_page_and_an_older_one_is_removed(self):
        with tempfile.TemporaryDirectory() as temp:
            course = Course(Path(temp), {}, {"All Classes/Day 1.md": "---\npublish: true\n---\nHello\n"}, 1)
            folder = build_site.coverage_tab_folder(course.host_output_dir)
            write(folder / "map-20260101T000000Z-00000000.html", "a stale map")
            record = course.write_tab()
            self.assertEqual(record["maps"], [])
            self.assertIsNone(record["page"])
            self.assertEqual(sorted(os.listdir(folder)), ["about.json"])

    def test_the_start_is_the_pending_markers_own_time(self):
        with tempfile.TemporaryDirectory() as temp:
            course = the_anti_drift_course(temp)
            build_site._mark_build_starting(course.host_output_dir)
            marker = course.host_output_dir / build_site.BUILD_STARTED_PENDING
            moment = 1_763_000_000_123_456_789
            os.utime(marker, ns=(moment, moment))
            record = course.write_tab()
            self.assertEqual(record["startedNs"], os.stat(marker).st_mtime_ns)
            self.assertEqual(record["startedAt"], "2025-11-13T02:13:20Z")

    def test_no_marker_means_no_start(self):
        with tempfile.TemporaryDirectory() as temp:
            _, record, _ = a_page(temp)
        self.assertIsNone(record["startedNs"])
        self.assertIsNone(record["startedAt"])

    def test_it_never_fails_the_build(self):
        with tempfile.TemporaryDirectory() as temp:
            course = the_anti_drift_course(temp)
            # A FILE where the folder must go: making it fails.
            write(build_site.coverage_tab_folder(course.host_output_dir), "in the way")
            said = []
            answer = course.write_tab(printer=said.append)
            self.assertIsNone(answer)
            self.assertEqual(len(said), 1)
            sentence = coverage_tab_contract()["consoleWords"]["couldNotMake"]
            self.assertTrue(said[0].startswith("⚠️  " + sentence.split("{reason}")[0]))

    def test_a_contract_it_cannot_read_is_one_warning(self):
        with tempfile.TemporaryDirectory() as temp:
            course = the_anti_drift_course(temp)
            toolchain_paths.CONTRACTS_DIR = Path(temp) / "no-contracts-here"
            contracts.reset_cache()
            try:
                said = []
                self.assertIsNone(course.write_tab(printer=said.append))
                self.assertEqual(len(said), 1)
            finally:
                use_the_repository_contracts()

    def test_a_success_prints_nothing(self):
        with tempfile.TemporaryDirectory() as temp:
            course = the_anti_drift_course(temp)
            said = []
            printed = io.StringIO()
            with redirect_stdout(printed):
                self.assertIsNotNone(course.write_tab(printer=said.append))
            self.assertEqual(said, [])
            self.assertEqual(printed.getvalue(), "")


class TwoMaps(unittest.TestCase):

    def setUp(self):
        use_the_repository_contracts()

    def test_one_page_with_a_section_per_map_in_the_sites_order(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            curriculum = dict(the_counting_fixture()["curriculum"])
            curriculum["College Board/1.A.md"] = "---\ntitle: 1.A\n---\nA skill.\n"
            curriculum["College Board/CRD-1.A.md"] = "---\ntitle: CRD-1.A\n---\nAn objective.\n"
            pages = {
                "All Classes/Day 1.md": "---\npublish: true\n---\n[[Lesson]]\n",
                "Lessons/Lesson.md": "---\npublish: false\n---\n![[A1.1]]\n![[1.A]]\n",
            }
            course = Course(root, curriculum, pages, 1)
            course.configured = ["Curriculum", "College Board"]
            course.plan = build_site.plan_coverage_maps(course.content_root, course.configured)
            build_site.set_coverage_titles([title for _, title in course.plan])
            record = course.write_tab()
            text = (build_site.coverage_tab_folder(course.host_output_dir)
                    / record["page"]).read_text(encoding="utf-8")
        titles = []
        for one_map in record["maps"]:
            titles.append(one_map["title"])
        planned = []
        for _, title in course.plan:
            planned.append(title)
        self.assertEqual(titles, planned)
        self.assertEqual(titles[0], "Curriculum Coverage")
        self.assertEqual(len(re.findall(r"<section ", text)), 2)
        self.assertLess(text.index(f'<h2 id="coverage-map-0"><bdi>{titles[0]}</bdi></h2>'),
                        text.index(f'<h2 id="coverage-map-1"><bdi>{titles[1]}</bdi></h2>'))
        self.assertIn(build_site.coverage_tab_link(BUILD_ID, 0, "A1.1"), text)
        self.assertIn(build_site.coverage_tab_link(BUILD_ID, 1, "1.A"), text)
        self.assertIn(build_site.coverage_tab_link(BUILD_ID, 1, "CRD-1.A"), text)
        # The one unpublished lesson counts on both maps and is one page.
        self.assertEqual(record["hiddenPagesCounted"], 1)
        self.assertEqual(record["maps"][1]["notYetAddressed"], 1)


class InTheBuild(unittest.TestCase):
    """Where the build calls it, read from the build's own source: the
    placement rules here are pinned that way too."""

    def setUp(self):
        source = Path(build_site.__file__).read_text(encoding="utf-8")
        start = source.index("def build_section_site(")
        self.body = source[start:source.index("\ndef ", start + 1)]
        self.call = self.body.index("    make_the_coverage_tab(\n")

    def test_after_the_sweep_the_hiding_and_the_clearing(self):
        self.assertLess(self.body.index("how_i_teach.remove_from_content_root(content_root)"), self.call)
        self.assertLess(self.body.index("_clear_a_site_this_build_cannot_replace(health_facts"), self.call)
        self.assertLess(self.body.index("forget_unreadable_pages()"), self.call)
        self.assertLess(self.body.index("copy_the_per_section_folders("), self.call)

    def test_before_the_problems_record_and_quartz(self):
        self.assertLess(self.call, self.body.index("section_problems.write_after_build("))
        self.assertLess(self.call, self.body.index("_prepare_my_progress("))

    def test_whatever_the_sites_map_setting_says(self):
        # At the function's own indentation, so not inside `if coverage_wanted:`.
        line_start = self.body.rindex("\n", 0, self.call) + 1
        self.assertEqual(self.body[line_start:self.call], "")
        self.assertIn("coverage_wanted)", self.body[self.call:self.call + 600])

    def test_beside_the_site(self):
        self.assertIn("host_output_dir, content_root, course_dir", self.body[self.call:self.call + 200])


class WhetherTheMapIsThisBuilds(unittest.TestCase):
    """coverageTab.mapOfThisBuild: the PLANTOIR_PROBLEMS: line says the map
    step ran, not that it made a map (the implementation review's M2)."""

    def setUp(self):
        use_the_repository_contracts()

    def test_every_case(self):
        for case in coverage_tab_contract()["mapOfThisBuild"]["cases"]:
            with self.subTest(case["name"]), tempfile.TemporaryDirectory() as temp:
                host = Path(temp) / "section1"
                folder = build_site.coverage_tab_folder(host)
                folder.mkdir(parents=True)
                if "recordText" in case:
                    write(folder / "about.json", case["recordText"])
                elif case.get("record") is not None:
                    write(folder / "about.json", json.dumps(case["record"]))
                for name in case["pagesOnDisk"]:
                    write(folder / name, "a page")
                self.assertEqual(build_site.coverage_tab_map_state(host, case["buildId"]),
                                 case["expect"])

    def test_a_failed_map_step_leaves_the_earlier_map_and_says_older(self):
        with tempfile.TemporaryDirectory() as temp:
            course = the_anti_drift_course(temp)
            first = course.write_tab()
            folder = build_site.coverage_tab_folder(course.host_output_dir)
            second_id = "20261112T200000Z-bbbbbbbb"
            real_replace = build_site.os.replace

            def no_space(source, target):
                raise OSError(errno.ENOSPC, "No space left on device", str(target))

            build_site.os.replace = no_space
            said = []
            try:
                arguments = (course.host_output_dir, course.content_root, course.course_dir,
                             "COURSE", "COURSE", 1, second_id, "preview", course.plan,
                             course.class_folders, course.graded_folders, True, course.taught,
                             {}, True)
                self.assertIsNone(build_site.make_the_coverage_tab(
                    *arguments, printer=said.append, schemes=schemes()))
            finally:
                build_site.os.replace = real_replace
            self.assertEqual(said, ["⚠️  " + coverage_tab_contract()["consoleWords"]["couldNotMake"]
                                    .replace("{reason}", "No space left on device")])
            self.assertEqual(sorted(os.listdir(folder)), sorted(["about.json", first["page"]]),
                             "no half-written temporary is left behind")
            self.assertEqual(build_site.coverage_tab_map_state(course.host_output_dir, second_id), "anotherBuild")
            self.assertEqual(build_site.coverage_tab_map_state(course.host_output_dir, BUILD_ID), "thisBuild")


class TwoBuildsAndLeftovers(unittest.TestCase):
    """The implementation review's L1 and L2 (and TheBuildThatStartedLastOwnsTheMap)."""

    def setUp(self):
        use_the_repository_contracts()

    def test_the_page_about_json_names_is_never_removed(self):
        with tempfile.TemporaryDirectory() as temp:
            course = the_anti_drift_course(temp)
            folder = build_site.coverage_tab_folder(course.host_output_dir)
            older_page = "map-20200101T000000Z-00000000.html"
            write(folder / older_page, "an older page")
            write(folder / "about.json", json.dumps({"version": 1, "page": older_page,
                                                      "buildId": "20200101T000000Z-00000000"}))
            # As if this build's record had been overtaken, right before the tidy.
            build_site._tidy_the_coverage_tab_folder(folder, BUILD_ID)
            self.assertTrue((folder / older_page).is_file())


class TheBuildThatStartedLastOwnsTheMap(unittest.TestCase):
    """Never ordered by the clock (the fix review's M1): the map that belongs
    is the one made by the build `.build-id` names, the last to start."""

    def setUp(self):
        use_the_repository_contracts()

    def build(self, course: Course, build_id: str, note_it: bool = True):
        if note_it:
            build_site._note_the_build_id(course.host_output_dir, build_id)
        return build_site.write_coverage_tab(
            course.host_output_dir, course.content_root, course.course_dir, "COURSE", "COURSE", 1,
            build_id, "preview", course.plan, course.class_folders, course.graded_folders, True,
            course.taught, {}, True, schemes=schemes())

    def test_a_build_whose_clock_is_30_seconds_behind_the_last_one_keeps_its_own_map(self):
        with tempfile.TemporaryDirectory() as temp:
            course = the_anti_drift_course(temp)
            first = "20261112T100000Z-aaaaaaaa"
            behind = "20261112T095930Z-bbbbbbbb"
            self.build(course, first)
            record = self.build(course, behind)
            folder = build_site.coverage_tab_folder(course.host_output_dir)
            self.assertEqual(record["buildId"], behind)
            self.assertEqual(json.loads((folder / "about.json").read_text(encoding="utf-8"))["buildId"], behind)
            self.assertEqual(sorted(os.listdir(folder)), sorted(["about.json", f"map-{behind}.html"]))
            self.assertEqual(build_site.coverage_tab_map_state(course.host_output_dir, behind), "thisBuild")

    def test_a_build_that_no_longer_owns_build_id_leaves_the_others_map_alone(self):
        # Two overlapping builds: B started after A and finished first. A,
        # finishing last, must not write over B's record or remove B's page.
        with tempfile.TemporaryDirectory() as temp:
            course = the_anti_drift_course(temp)
            a_id = "20261112T100000Z-aaaaaaaa"
            b_id = "20261112T100001Z-bbbbbbbb"
            build_site._note_the_build_id(course.host_output_dir, a_id)
            build_site._note_the_build_id(course.host_output_dir, b_id)
            b_record = self.build(course, b_id, note_it=False)
            a_answer = self.build(course, a_id, note_it=False)
            folder = build_site.coverage_tab_folder(course.host_output_dir)
            self.assertEqual(a_answer, b_record)
            self.assertEqual(sorted(os.listdir(folder)), sorted(["about.json", f"map-{b_id}.html"]))
            self.assertEqual(build_site.coverage_tab_map_state(course.host_output_dir, b_id), "thisBuild")
            self.assertEqual(build_site.coverage_tab_map_state(course.host_output_dir, a_id), "anotherBuild")

    def test_the_owner_removes_every_other_builds_leftovers_whatever_their_ids(self):
        with tempfile.TemporaryDirectory() as temp:
            course = the_anti_drift_course(temp)
            folder = build_site.coverage_tab_folder(course.host_output_dir)
            leftovers = [".map-20200101T000000Z-00000000.html.123.tmp",
                         ".about.json.20200101T000000Z-00000000.tmp",
                         ".map-20991231T000000Z-ffffffff.html.456.tmp",
                         ".about.json.20991231T000000Z-ffffffff.tmp",
                         "map-20991231T000000Z-ffffffff.html", "map-old.html"]
            for name in leftovers:
                write(folder / name, "left behind")
            record = self.build(course, BUILD_ID)
            self.assertEqual(sorted(os.listdir(folder)), sorted(["about.json", record["page"]]))


class AReusedBuild(unittest.TestCase):
    """#768, as merged: a deploy that reuses the last build runs no Python,
    so the map is that build's, still true, and reads as this build's
    against `.build-id`. Writing the map must not itself make the course
    look changed, or no deploy could ever reuse a build."""

    def setUp(self):
        use_the_repository_contracts()

    def test_the_map_of_a_reused_build_is_still_that_builds_and_asks_for_no_build(self):
        with tempfile.TemporaryDirectory() as temp:
            course = the_anti_drift_course(temp)
            # The old layout: the built output INSIDE the course folder, under
            # its hidden .merged_output, the case where the change walk could
            # meet the map at all.
            section_dir = course.course_dir / ".merged_output" / "section1"
            section_dir.mkdir(parents=True)
            # In the order a build makes them: everything in the course, then
            # the build's start, then its site, then (mid-build) the map.
            build_site._note_the_build_id(section_dir, BUILD_ID)
            write(section_dir / toolchain_paths.BUILD_STARTED_MARKER_NAME, "started")
            write(section_dir / "public" / "index.html", "<html>site</html>")
            course.host_output_dir = section_dir
            course.write_tab()
            self.assertIsNone(toolchain_paths.why_the_pages_ask_for_a_build(
                course.course_dir, section_dir), "the map made the course look changed")
            # The reuse runs no build: .build-id and the map are untouched.
            owner = (section_dir / ".build-id").read_text(encoding="utf-8").strip()
            self.assertEqual(owner, BUILD_ID)
            self.assertEqual(build_site.coverage_tab_map_state(section_dir, owner), "thisBuild")


def a_launchers_clear(launcher: str) -> str:
    """`clear_built_sites_keeping_copies` and the name it keeps, cut out of
    a launcher, the way test_build_freshness_reuse.py cuts out its rules."""
    source = (REPOSITORY_ROOT / launcher).read_text(encoding="utf-8")
    kept = re.search(r'^KEPT_COPIES_FOLDER="[^"]*"$', source, re.M).group(0)
    start = source.index("clear_built_sites_keeping_copies() {")
    end = source.index("\n}\n", start) + 3
    return kept + "\n" + source[start:end]


class ClearedWithTheSite(unittest.TestCase):
    """#789, as merged: when a course's builds folder is cleared, the map goes
    with the built site it describes, and the kept GeoGebra copies stay."""

    def test_every_launchers_clear_takes_the_map_and_keeps_the_copies(self):
        # Not plain "bash": on Windows that is C:\Windows\System32\bash.exe,
        # the WSL launcher, which fails ("must be updated") or cannot open a
        # Windows path (step 0 of v2.0.0, measured on Windows 11 Pro 26200).
        # The shared harness finds Git Bash there, and a real bash elsewhere.
        import test_deploy_non_interactive as launcher_harness
        shell = launcher_harness._a_bash_that_can_run_deploy_sh()
        if shell is None:
            self.skipTest("no bash on this machine that can run the launchers' clear")
        for launcher in ("setup.sh", "preview.sh", "deploy.sh"):
            with self.subTest(launcher), tempfile.TemporaryDirectory() as temp:
                target = Path(temp) / "CODE"
                write(target / "section1" / ".coverage-tab" / "about.json", "{}")
                write(target / "section1" / ".coverage-tab" / f"map-{BUILD_ID}.html", "a map")
                write(target / "section1" / "public" / "index.html", "a site")
                write(target / ".geogebra-cache" / "k.ggb", "a kept copy")
                script = a_launchers_clear(launcher) + '\nclear_built_sites_keeping_copies "$1"\n'
                subprocess.run(shell + ["-c", script, "clear", str(target)], check=True)
                left = sorted(path.relative_to(target).as_posix() for path in target.rglob("*"))
                self.assertEqual(left, [".geogebra-cache", ".geogebra-cache/k.ggb"])


class TheConsoleLine(unittest.TestCase):

    def setUp(self):
        use_the_repository_contracts()

    def test_the_fallback_is_the_contracts_sentence(self):
        self.assertEqual(build_site.COVERAGE_TAB_COULD_NOT_MAKE,
                         coverage_tab_contract()["consoleWords"]["couldNotMake"])

    def test_it_names_no_tab_and_no_path(self):
        with tempfile.TemporaryDirectory() as temp:
            course = the_anti_drift_course(temp)
            write(build_site.coverage_tab_folder(course.host_output_dir), "in the way")
            said = []
            course.write_tab(printer=said.append)
        self.assertEqual(len(said), 1)
        self.assertNotIn("/", said[0])
        self.assertNotIn("\\", said[0])
        self.assertNotIn("tab", said[0].lower())
        self.assertNotIn(temp, said[0])


class TheHiddenLine(unittest.TestCase):

    def setUp(self):
        use_the_repository_contracts()

    def test_a_page_the_site_never_publishes_is_counted_as_hidden(self):
        fixture = the_counting_fixture()
        pages = {"All Classes/Day 1.md": "---\npublish: true\n---\n[[Lesson Outline]]\n",
                 "templates/Lesson Outline.md": "---\npublish: true\n---\n![[A1.1]]\n"}
        with tempfile.TemporaryDirectory() as temp:
            course = Course(Path(temp), fixture["curriculum"], pages, 1)
            record = course.write_tab()
        self.assertEqual(record["hiddenPagesCounted"], 1)

    def test_an_empty_map_says_nothing_untrue(self):
        words = coverage_tab_contract()["pageWords"]
        fixture = the_counting_fixture()
        with tempfile.TemporaryDirectory() as temp:
            course = Course(Path(temp), fixture["curriculum"], {}, 1)
            record = course.write_tab()
            text = (build_site.coverage_tab_folder(course.host_output_dir)
                    / record["page"]).read_text(encoding="utf-8")
        self.assertEqual(record["hiddenPagesCounted"], 0)
        self.assertIn(on_the_page(words["hiddenNone"]), text)


# === Never on a website ======================================================

class NeverOnAWebsite(unittest.TestCase):

    def setUp(self):
        use_the_repository_contracts()

    def a_built_section(self, temp: str) -> Course:
        course = the_anti_drift_course(temp)
        with redirect_stdout(io.StringIO()):
            build_site.build_curriculum_coverage(
                course.content_root, "COURSE", class_folders=course.class_folders,
                graded_folders=course.graded_folders, graded_was_configured=True,
                configured_folders=course.configured, taught=course.taught)
        public = course.host_output_dir / "public"
        write(public / "index.html", "<html>front page</html>")
        write(public / "Curriculum-Coverage.html", "<html>the site's map</html>")
        course.write_tab()
        return course

    def test_the_netlify_upload_never_lists_it(self):
        import deploy
        with tempfile.TemporaryDirectory() as temp:
            course = self.a_built_section(temp)
            files_map, _ = deploy._build_files_manifest(course.host_output_dir / "public")
            self.assertTrue(files_map)
            for remote in files_map:
                self.assertNotIn(".coverage-tab", remote)
                self.assertNotIn("map-", remote)

    def test_wrangler_and_netlify_are_handed_public_alone(self):
        source = (scripts_dir / "deploy.py").read_text(encoding="utf-8")
        self.assertIn('    public_dir = section_dir / "public"\n', source)
        self.assertIn('toolchain_paths.WRANGLER, "pages", "deploy", str(public_dir),', source)
        self.assertNotIn("coverage-tab", source)
        self.assertNotIn("coverage_tab", source)

    def test_a_folder_publish_copies_public_alone(self):
        source = (REPOSITORY_ROOT / "deploy.sh").read_text(encoding="utf-8")
        self.assertIn('PUBLIC_DIR_HOST="${SECTION_DIR_HOST}/public"\n', source)
        rsync_lines = []
        for line in source.splitlines():
            if re.search(r"\brsync -a", line) and "#" not in line.split("rsync")[0]:
                rsync_lines.append(line)
        self.assertTrue(rsync_lines)
        for line in rsync_lines:
            self.assertIn('"${PUBLIC_DIR_HOST}/" "${TARGET_DIR}/"', line)
        self.assertNotIn("coverage-tab", source)

    @unittest.skipUnless(shutil.which("rsync"), "no rsync on this machine (a folder publish from deploy.sh needs it)")
    def test_the_folder_publishs_own_copy_leaves_it_behind(self):
        with tempfile.TemporaryDirectory() as temp:
            course = self.a_built_section(temp)
            target = Path(temp) / "target"
            target.mkdir()
            subprocess.run(["rsync", "-a", "--delete", f"{course.host_output_dir / 'public'}/",
                            f"{target}/"], check=True)
            copied = sorted(path.relative_to(target).as_posix() for path in target.rglob("*"))
            self.assertEqual(copied, ["Curriculum-Coverage.html", "index.html"])

    def test_the_site_links_to_it_nowhere(self):
        with tempfile.TemporaryDirectory() as temp:
            course = self.a_built_section(temp)
            for page in course.content_root.rglob("*"):
                if page.is_file():
                    text = page.read_text(encoding="utf-8", errors="replace")
                    self.assertNotIn("plantoir-coverage", text, page.name)
                    self.assertNotIn(".coverage-tab", text, page.name)
            self.assertFalse(list(course.content_root.rglob("*.html")))


if __name__ == "__main__":
    unittest.main()
