#!/usr/bin/env python3
"""
My Progress (#545): the build's half - contracts/shared-rules.json ->
myProgress and myProgressBuilt.

Every case the build's Python reads, run through it: the two course settings
(read as include_curriculum_coverage is), which headings count, the gate
over every `sections` and `gate` case (true exactly when the site's reading
counts an item - scripts/check_progress_rules_against_the_site.py runs the
same cases through the site's own code), the tables' labels, Key Links, the
words against userFacingLabelWords.forbidden, and the marker lines. Then the
build's own steps over real temporary folders: the page, the plan and Key
Links when the section qualifies; nothing but the plan when it is switched
off, when nothing qualifies, or when the course has its own page by that
name (in any case); the sidebar pin and the emitter's wiring, each
idempotent, with a script or settings file of another shape said and left
alone.

Stdlib only (the grouping cases need python-frontmatter for the build's date
pass and run in the image's check instead); Windows' PythonToolchainTests
discovers this file.

    python3 scripts/test_my_progress.py
"""
import io
import json
import re
import shutil
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

import build_site
import class_pages
import contracts
import my_progress
import toolchain_paths

# The repository's own contract, as the other tests read it: natively the
# toolchain's default is the container's /opt/contracts.
_REPO_CONTRACTS = Path(__file__).resolve().parent.parent / "contracts"
if _REPO_CONTRACTS.is_dir():
    toolchain_paths.CONTRACTS_DIR = _REPO_CONTRACTS
    contracts.reset_cache()

RULES = contracts.section("shared-rules", "myProgress")
BUILT_RULES = contracts.section("shared-rules", "myProgressBuilt")
DEFAULTS = RULES["headings"]["defaults"]

# Quartz v4.5.0's own explorer.inline.ts, as patches/ ships it, cut to the
# lines the pin touches (measured in quartz-teacher:dev-test, 2026-10-19).
EXPLORER = '''import { FileTrieNode } from "../../util/fileTrie"
import { FullSlug, resolveRelative, simplifySlug } from "../../util/path"
import { ContentDetails } from "../../plugins/emitters/contentIndex"

    // Re-assemble: non-expandable folders → expandable folders → files (files retain their order post-trie sort)
    const orderedTopLevel = [...nonExpandableFolders, ...expandableFolders, ...files]

    for (const child of orderedTopLevel) {
      const node = child.isFolder
'''

EMITTERS_INDEX = '''export { ContentPage } from "./contentPage"
export { Assets } from "./assets"
export { CustomOgImages } from "./ogImage"
'''

CONFIG = '''    emitters: [
      Plugin.AliasRedirects(),
      Plugin.ContentIndex({
        enableSiteMap: true,
      }),
      Plugin.Assets(),
      Plugin.Static(),
    ],
'''


def quietly(function, *arguments, **keywords):
    said = io.StringIO()
    with redirect_stdout(said):
        result = function(*arguments, **keywords)
    return result, said.getvalue()


class TheSettings(unittest.TestCase):

    def test_every_config_case(self):
        cases = RULES["config"]["cases"]
        self.assertGreaterEqual(len(cases), 14)
        for case in cases:
            with self.subTest(case["name"]):
                self.assertEqual(build_site.resolve_include_my_progress(case["config"], case["section"]),
                                 case["wanted"])
                self.assertEqual(my_progress.headings_from(case["config"]), case["headings"])

    def test_read_exactly_as_its_sibling(self):
        for case in RULES["config"]["cases"]:
            if "include_my_progress" not in case["config"]:
                continue
            sibling = {"include_curriculum_coverage": case["config"]["include_my_progress"]}
            with self.subTest(case["name"]):
                self.assertEqual(build_site.resolve_include_curriculum_coverage(sibling, case["section"]),
                                 case["wanted"])


class WhichHeadingsCount(unittest.TestCase):

    def test_every_heading_case(self):
        for case in RULES["headings"]["cases"]:
            headings = case.get("headings", DEFAULTS)
            wanted = {my_progress.normalised_heading(heading) for heading in headings}
            with self.subTest(case["heading"]):
                self.assertEqual(my_progress.normalised_heading(case["heading"]) in wanted, case["counts"])

    def test_every_markup_case_reads_as_the_site_renders_it(self):
        for case in RULES["headings"]["markupCases"]:
            raw = re.sub(r"^#+[ \t]+", "", case["markdown"])
            raw = re.sub(r"%%.*?%%", "", raw)
            with self.subTest(case["markdown"]):
                self.assertEqual(my_progress.normalised_heading(my_progress._heading_words(raw)),
                                 my_progress.normalised_heading(case["rendered"]))
                page = case["markdown"] + "\n\n- [ ] I can add fractions\n"
                self.assertEqual(my_progress.page_has_counted_items(page, DEFAULTS), case["counts"])


class TheGate(unittest.TestCase):

    def test_every_sections_case(self):
        cases = RULES["sections"]["cases"]
        self.assertGreaterEqual(len(cases), 24)
        for case in cases:
            with self.subTest(case["name"]):
                self.assertEqual(
                    my_progress.page_has_counted_items(case["markdown"], case.get("headings", DEFAULTS)),
                    len(case["items"]) > 0)

    def test_every_gate_case(self):
        for case in RULES["gate"]["cases"]:
            with self.subTest(case["name"]):
                self.assertEqual(my_progress.page_has_counted_items(case["markdown"], DEFAULTS), case["counts"])

    def test_pages_are_named_as_the_site_names_them(self):
        pages = [
            {"path": "Tasks/Café.md", "text": "## Success criteria\n\n- [ ] I can order\n"},
            {"path": "Tasks/Plain.md", "text": "- [ ] Bring a pencil\n"},
        ]
        self.assertEqual(my_progress.pages_with_counted_items(pages, DEFAULTS), ["Tasks/Café.md"])


class TheLabels(unittest.TestCase):

    def test_every_label_case(self):
        for case in RULES["labels"]["cases"]:
            pattern = class_pages.class_page_pattern(case["unitWord"], case["scheme"])
            numbered = case["scheme"] == class_pages.NUMBERED_SCHEME
            with self.subTest(case["name"]):
                self.assertEqual(
                    my_progress.unit_label(case["title"], pattern, case["unitWord"], numbered, case["classFolder"]),
                    (case["table"], case["order"]))


class KeyLinks(unittest.TestCase):

    def test_every_key_links_case_and_twice_changes_nothing(self):
        for case in RULES["keyLinks"]["cases"]:
            with self.subTest(case["name"]), tempfile.TemporaryDirectory() as name:
                page = Path(name) / "Key Links.md"
                page.write_bytes(case["before"].encode("utf-8"))
                my_progress.link_from_key_links(name)
                self.assertEqual(page.read_bytes().decode("utf-8"), case["after"])
                self.assertFalse(my_progress.link_from_key_links(name))
                self.assertEqual(page.read_bytes().decode("utf-8"), case["after"])

    def test_no_key_links_page_is_no_change(self):
        with tempfile.TemporaryDirectory() as name:
            self.assertFalse(my_progress.link_from_key_links(name))
            self.assertEqual(list(Path(name).iterdir()), [])


class TheWords(unittest.TestCase):

    def test_no_word_names_the_machinery(self):
        forbidden = contracts.section("shared-rules", "userFacingLabelWords", "forbidden")
        for key, text in my_progress.words().items():
            for word in re.findall(r"[A-Za-z]+", text):
                with self.subTest(key=key, word=word):
                    self.assertNotIn(word.lower(), forbidden)

    def test_the_title_is_my_progress_everywhere(self):
        self.assertEqual(my_progress.words()["title"], "My Progress")
        self.assertEqual(my_progress.PAGE_FILE, my_progress.words()["title"] + ".md")

    def test_the_page_has_no_link_of_any_kind(self):
        text = my_progress.page_text("2026-09-03T09:00:00.000-0400")
        self.assertNotIn("[[", text)
        self.assertNotIn("](", text)
        self.assertNotIn("<a", text)
        self.assertIn("title: My Progress\n", text)
        self.assertIn("publish: true\n", text)
        self.assertIn("excludeBacklinks: true\n", text)
        self.assertIn("created: 2026-09-03T09:00:00.000-0400\n", text)
        self.assertIn("data-plantoir-progress", text)
        self.assertNotIn("created:", my_progress.page_text(None))


class TheMarker(unittest.TestCase):

    def test_the_contracts_examples_are_what_the_build_prints(self):
        examples = BUILT_RULES["marker"]["examples"]
        self.assertEqual(len(examples), 3)
        for example in examples:
            payload = json.loads(example.split(" ", 1)[1])
            lines = []
            my_progress.announce(payload["course"], payload["section"], payload["reason"], payload["pages"],
                                 printer=lines.append)
            with self.subTest(example):
                self.assertEqual(lines[-1], example)
                self.assertEqual(len(lines), 2, "one sentence for the teacher, then the marker")

    def test_switched_off_prints_no_marker(self):
        lines = []
        my_progress.announce("ICS3U", 1, my_progress.SWITCHED_OFF, 0, printer=lines.append)
        self.assertEqual(len(lines), 1)
        self.assertNotIn(BUILT_RULES["marker"]["prefix"], lines[0])


class TheBuildsOwnSteps(unittest.TestCase):

    def setUp(self):
        self.folder = Path(tempfile.mkdtemp())
        self.content = self.folder / "content"
        self.output = self.folder / "output"
        (self.content / "All Classes").mkdir(parents=True)
        (self.content / "Tasks").mkdir()
        (self.output / "quartz").mkdir(parents=True)
        (self.content / "Key Links.md").write_text("---\ntitle: Key Links\n---\n- [[Course Outline]]\n", encoding="utf-8")
        (self.content / "All Classes" / "Unit 1, Day 2.md").write_text(
            "---\ntitle: Unit 1, Day 2\ncreated: 2026-09-04T09:00:00.000-0400\n---\n[[Fractions]]\n", encoding="utf-8")
        (self.content / "Tasks" / "Fractions.md").write_text(
            "---\ntitle: Fractions\n---\n## Success criteria\n\n- [ ] I can add fractions\n", encoding="utf-8")
        (self.content / "Tasks" / "Hidden.md").write_text(
            "---\ntitle: Hidden\npublish: false\n---\n## Success criteria\n\n- [ ] I can hide\n", encoding="utf-8")
        self.dating = {
            "classes": [{"page": self.content / "All Classes" / "Unit 1, Day 2.md", "title": "Unit 1, Day 2",
                         "created": "2026-09-04T09:00:00.000-0400"}],
            "first_class_of": {self.content / "Tasks" / "Fractions.md": self.content / "All Classes" / "Unit 1, Day 2.md"},
        }
        self.config = {"per_section_folders": ["All Classes"]}

    def tearDown(self):
        shutil.rmtree(self.folder, ignore_errors=True)

    def prepare(self, config=None):
        return quietly(build_site._prepare_my_progress, self.content, self.output,
                       self.config if config is None else config, 1, "ICS3U", self.dating,
                       "2026-09-03T09:00:00.000-0400")

    def plan(self) -> dict:
        return json.loads((self.output / "quartz" / my_progress.PLAN_FILE).read_text(encoding="utf-8"))

    def test_a_section_that_qualifies(self):
        slug, said = self.prepare()
        self.assertEqual(slug, "My-Progress")
        page = self.content / "My Progress.md"
        self.assertEqual(page.read_text(encoding="utf-8"), my_progress.page_text("2026-09-03T09:00:00.000-0400"))
        self.assertTrue((self.content / "Key Links.md").read_text(encoding="utf-8").startswith(
            "---\ntitle: Key Links\n---\n- [[My Progress]]\n- [[Course Outline]]"))
        plan = self.plan()
        self.assertTrue(plan["page"])
        self.assertEqual(plan["reason"], "built")
        self.assertEqual(plan["gate"], ["Tasks/Fractions.md"], "a hidden page never counts")
        self.assertEqual(plan["classes"], [{"path": "All Classes/Unit 1, Day 2.md", "title": "Unit 1, Day 2",
                                             "date": "2026-09-04T09:00:00.000-0400", "unit": "Unit 1",
                                             "unitOrder": 1}])
        self.assertEqual(plan["firstClassOf"], {"Tasks/Fractions.md": "All Classes/Unit 1, Day 2.md"})
        self.assertEqual(plan["headings"], ["test of success", "tests of success", "success criteria"])
        self.assertIn('PLANTOIR_MY_PROGRESS: {"course": "ICS3U", "section": 1, "built": true, "pages": 1, '
                      '"reason": "built"}', said)
        before = (self.output / "quartz" / my_progress.PLAN_FILE).read_bytes()
        self.assertFalse(my_progress.write_plan(self.output, plan), "nothing changed, nothing written")
        # The next build starts from a fresh content folder, as every build does.
        (self.content / "My Progress.md").unlink()
        self.prepare()
        self.assertEqual((self.output / "quartz" / my_progress.PLAN_FILE).read_bytes(), before,
                         "the same bytes for the same input")

    def test_switched_off_writes_only_the_plan(self):
        slug, said = self.prepare({"per_section_folders": ["All Classes"], "include_my_progress": False})
        self.assertEqual(slug, "")
        self.assertFalse((self.content / "My Progress.md").exists())
        self.assertNotIn("My Progress", (self.content / "Key Links.md").read_text(encoding="utf-8"))
        self.assertEqual((self.plan()["page"], self.plan()["reason"]), (False, "switchedOff"))
        self.assertNotIn("PLANTOIR_MY_PROGRESS:", said)

    def test_nothing_qualifies_writes_only_the_plan(self):
        (self.content / "Tasks" / "Fractions.md").write_text("---\ntitle: Fractions\n---\n- [ ] I can add\n",
                                                            encoding="utf-8")
        slug, said = self.prepare()
        self.assertEqual(slug, "")
        self.assertFalse((self.content / "My Progress.md").exists())
        self.assertNotIn("My Progress", (self.content / "Key Links.md").read_text(encoding="utf-8"))
        self.assertEqual((self.plan()["page"], self.plan()["reason"]), (False, "noSuccessCriteria"))
        self.assertIn('"reason": "noSuccessCriteria"', said)

    def test_the_teachers_own_page_wins_in_any_case(self):
        own = self.content / "my progress.md"
        own.write_text("---\ntitle: my progress\n---\nMine.\n", encoding="utf-8")
        slug, said = self.prepare()
        self.assertEqual(slug, "")
        self.assertEqual(own.read_text(encoding="utf-8"), "---\ntitle: my progress\n---\nMine.\n")
        self.assertNotIn("[[My Progress]]", (self.content / "Key Links.md").read_text(encoding="utf-8"))
        self.assertEqual(self.plan()["reason"], "teachersOwnPage")
        self.assertIn('"reason": "teachersOwnPage"', said)

    def test_a_page_called_my_progress_deeper_down_is_not_the_teachers_own(self):
        (self.content / "Tasks" / "My Progress.md").write_text("---\ntitle: Mine\n---\n", encoding="utf-8")
        slug, _ = self.prepare()
        self.assertEqual(slug, "My-Progress")

    def test_a_club_has_one_table_named_after_its_folder(self):
        build_site.set_class_page_scheme("numbered")
        build_site.set_unit_word("Week")
        try:
            self.dating["classes"][0]["title"] = "Week 3"
            self.prepare({"per_section_folders": ["Resources", "All Meetings"], "class_folder": "All Meetings"})
            self.assertEqual(self.plan()["classes"][0]["unit"], "All Meetings")
        finally:
            build_site.set_class_page_scheme("unit_day")
            build_site.set_unit_word("Unit")


class TheSidebarPin(unittest.TestCase):

    def test_added_once_rewritten_every_build_and_idempotent(self):
        with tempfile.TemporaryDirectory() as name:
            script = Path(name) / "explorer.inline.ts"
            script.write_text(EXPLORER, encoding="utf-8")
            self.assertTrue(build_site.pin_my_progress_in_sidebar(script, "My-Progress", ["All-Classes"]))
            text = script.read_text(encoding="utf-8")
            self.assertEqual(text.count(build_site.MY_PROGRESS_PIN_MARKER), 2)
            self.assertIn('import { pinnedOrder } from "../../plugins/emitters/progressRules"', text)
            self.assertIn('const PLANTOIR_MY_PROGRESS_PIN = {"slug": "My-Progress", "after": ["All-Classes"]}', text)
            self.assertIn("for (const child of pinnedOrder(orderedTopLevel, PLANTOIR_MY_PROGRESS_PIN)) {", text)
            self.assertNotIn("orderedTopLevel = pinnedOrder", text, "orderedTopLevel is a const (review F1)")
            self.assertFalse(build_site.pin_my_progress_in_sidebar(script, "My-Progress", ["All-Classes"]))
            self.assertTrue(build_site.pin_my_progress_in_sidebar(script, "", ["All-Classes"]))
            text = script.read_text(encoding="utf-8")
            self.assertIn('const PLANTOIR_MY_PROGRESS_PIN = {"slug": "", "after": ["All-Classes"]}', text)
            self.assertEqual(len(re.findall("PLANTOIR_MY_PROGRESS_PIN = ", text)), 1)

    def test_a_script_of_another_shape_is_said_and_left_alone(self):
        with tempfile.TemporaryDirectory() as name:
            script = Path(name) / "explorer.inline.ts"
            changed = EXPLORER.replace("for (const child of orderedTopLevel) {", "orderedTopLevel.forEach((child) => {")
            script.write_text(changed, encoding="utf-8")
            result, said = quietly(build_site.pin_my_progress_in_sidebar, script, "My-Progress", ["All-Classes"])
            self.assertFalse(result)
            self.assertIn("changed shape", said)
            self.assertEqual(script.read_text(encoding="utf-8"), changed)


class TheEmittersWiring(unittest.TestCase):

    def test_wired_once_and_idempotent(self):
        with tempfile.TemporaryDirectory() as name:
            index = Path(name) / "index.ts"
            index.write_text(EMITTERS_INDEX, encoding="utf-8")
            config = Path(name) / "quartz.config.ts"
            config.write_text(CONFIG, encoding="utf-8")
            for _ in range(2):
                build_site._wire_emitters_index(index)
                build_site._wire_progress_emitter(config)
            self.assertEqual(index.read_text(encoding="utf-8").count("export { PlantoirProgress }"), 1)
            text = config.read_text(encoding="utf-8")
            self.assertEqual(text.count("Plugin.PlantoirProgress()"), 1)
            self.assertIn("      Plugin.PlantoirProgress(),\n      Plugin.Assets(),", text)

    def test_settings_of_another_shape_are_said_and_left_alone(self):
        with tempfile.TemporaryDirectory() as name:
            config = Path(name) / "quartz.config.ts"
            config.write_text(CONFIG.replace("Plugin.Assets(),", "Plugin.Assets({}),"), encoding="utf-8")
            _, said = quietly(build_site._wire_progress_emitter, config)
            self.assertIn("changed shape", said)
            self.assertNotIn("PlantoirProgress", config.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
