#!/usr/bin/env python3
"""
The edits that connect support/quartz to a section's Quartz copy
(build_site.wire_quartz_additions): the Print button's (#454), the figures
transformer's (#485 E1), since #455 the runnable code's - its transformer
straight before SyntaxHighlighting and its component at the head of the
shared afterBody list - since #563 the self-check quizzes' transformer,
straight after the figures transformer, and since #519 the task boxes'
transformer, straight after the quizzes' (its script and styles ride the
Print button's component, PlantoirMetaLine.tsx), and since #545 My
Progress's emitter, straight before Assets (its script and styles ride the
same component). Since #609 the rule that lays every picture out before it
scrolls into view rides that component too.

Run against embedded copies of Quartz v4.5.0's own files (measured in
quartz-teacher:dev-test, 2026-10-17): wired once, a second build changes
nothing, a section wired before #455 gets the new edits, and a file whose
anchor moved is said and left alone. Stdlib only; Windows' PythonToolchainTests
discovers it.

Run with:

    python3 scripts/test_quartz_additions_wiring.py
"""
import shutil
import tempfile
import unittest
from pathlib import Path

import build_site

COMPONENTS_INDEX = '''import Content from "./pages/Content"
import Flex from "./Flex"

export {
  ArticleTitle,
  Content,
  Flex,
}
'''

TRANSFORMERS_INDEX = '''export { FrontMatter } from "./frontmatter"
export { SyntaxHighlighting } from "./syntax"
export { Description } from "./description"
'''

CONFIG = '''  plugins: {
    transformers: [
      Plugin.FrontMatter(),
      Plugin.CreatedModifiedDate({
        priority: ["git", "frontmatter", "filesystem"],
      }),
      Plugin.SyntaxHighlighting({
        theme: {
          light: "github-light",
          dark: "github-dark",
        },
        keepBackground: false,
      }),
      Plugin.ObsidianFlavoredMarkdown({ enableInHtmlEmbed: false }),
      Plugin.Description(),
      Plugin.Latex({ renderEngine: "katex" }),
    ],
    filters: [Plugin.RemoveDrafts()],
    emitters: [
      Plugin.AliasRedirects(),
      Plugin.ContentPage(),
      Plugin.Assets(),
      Plugin.Static(),
    ],
'''

EMITTERS_INDEX = '''export { ContentPage } from "./contentPage"
export { Assets } from "./assets"
'''

LAYOUT = '''import { PageLayout, SharedLayout } from "./quartz/cfg"
import * as Component from "./quartz/components"

// components shared across all pages
export const sharedPageComponents: SharedLayout = {
  head: Component.Head(),
  header: [],
  afterBody: [],
  footer: Component.Footer({}),
}

// components for pages that display a single page (e.g. a single note)
export const defaultContentPageLayout: PageLayout = {
  beforeBody: [
    Component.ArticleTitle(),
    Component.ContentMeta(),
  ],
}
'''


class WiringTests(unittest.TestCase):
    def setUp(self):
        self.output = Path(tempfile.mkdtemp(prefix="plantoir-wiring-"))
        (self.output / "quartz" / "components").mkdir(parents=True)
        (self.output / "quartz" / "plugins" / "transformers").mkdir(parents=True)
        (self.output / "quartz" / "plugins" / "emitters").mkdir(parents=True)
        self.files = {
            "components": self.output / "quartz" / "components" / "index.ts",
            "transformers": self.output / "quartz" / "plugins" / "transformers" / "index.ts",
            "emitters": self.output / "quartz" / "plugins" / "emitters" / "index.ts",
            "config": self.output / "quartz.config.ts",
            "layout": self.output / "quartz.layout.ts",
        }
        self.files["components"].write_text(COMPONENTS_INDEX, encoding="utf-8")
        self.files["transformers"].write_text(TRANSFORMERS_INDEX, encoding="utf-8")
        self.files["emitters"].write_text(EMITTERS_INDEX, encoding="utf-8")
        self.files["config"].write_text(CONFIG, encoding="utf-8")
        self.files["layout"].write_text(LAYOUT, encoding="utf-8")

    def tearDown(self):
        shutil.rmtree(self.output, ignore_errors=True)

    def text(self, name):
        return self.files[name].read_text(encoding="utf-8")

    def test_every_edit_is_made_once(self):
        build_site.wire_quartz_additions(self.output)
        components = self.text("components")
        self.assertEqual(components.count('import CodeRunner from "./CodeRunner"'), 1)
        self.assertEqual(components.count("  CodeRunner,\n"), 1)
        self.assertEqual(components.count('import PlantoirMetaLine from "./PlantoirMetaLine"'), 1)
        self.assertEqual(self.text("transformers").count('export { CodeRunnerFences } from "./codeRunner"'), 1)
        config = self.text("config")
        self.assertEqual(config.count("Plugin.CodeRunnerFences(),"), 1)
        self.assertIn("      Plugin.CodeRunnerFences(),\n      Plugin.SyntaxHighlighting({", config,
                      "the runner's transformer goes straight before SyntaxHighlighting, at its indent")
        self.assertEqual(self.text("transformers").count('export { PlantoirQuizzes } from "./plantoirQuizzes"'), 1)
        self.assertEqual(config.count("Plugin.PlantoirQuizzes(),"), 1)
        self.assertIn("      Plugin.Description(),\n      Plugin.PlantoirFigures(),\n      Plugin.PlantoirQuizzes(),\n", config,
                      "the quizzes' transformer goes straight after the figures', so after Description, at its indent")
        self.assertEqual(self.text("transformers").count('export { PlantoirTasks } from "./plantoirTasks"'), 1)
        self.assertEqual(config.count("Plugin.PlantoirTasks(),"), 1)
        self.assertIn("      Plugin.PlantoirQuizzes(),\n      Plugin.PlantoirTasks(),\n      Plugin.Latex(", config,
                      "the task boxes' transformer goes straight after the quizzes', at its indent")
        self.assertEqual(self.text("emitters").count('export { PlantoirProgress } from "./plantoirProgress"'), 1)
        self.assertEqual(config.count("Plugin.PlantoirProgress(),"), 1)
        self.assertIn("      Plugin.ContentPage(),\n      Plugin.PlantoirProgress(),\n      Plugin.Assets(),", config,
                      "My Progress's emitter (#545) goes straight before Assets, at its indent")
        layout = self.text("layout")
        self.assertIn("afterBody: [Component.CodeRunner()],", layout)
        self.assertIn("Component.PlantoirMetaLine(Component.ContentMeta())", layout)

    def test_a_second_build_changes_nothing(self):
        build_site.wire_quartz_additions(self.output)
        first = {name: self.text(name) for name in self.files}
        build_site.wire_quartz_additions(self.output)
        for name in self.files:
            self.assertEqual(self.text(name), first[name], name)

    def test_a_section_wired_before_455_gets_the_runners_edits(self):
        self.files["components"].write_text(COMPONENTS_INDEX.replace(
            "\nexport {\n",
            '\nimport PlantoirMetaLine from "./PlantoirMetaLine" // PLANTOIR-ADDITIONS\n\nexport {\n  PlantoirMetaLine,\n', 1),
            encoding="utf-8")
        self.files["transformers"].write_text(
            TRANSFORMERS_INDEX + 'export { PlantoirFigures } from "./plantoirFigures" // PLANTOIR-ADDITIONS\n',
            encoding="utf-8")
        build_site.wire_quartz_additions(self.output)
        self.assertEqual(self.text("components").count("import PlantoirMetaLine from"), 1)
        self.assertEqual(self.text("components").count('import CodeRunner from "./CodeRunner"'), 1)
        self.assertEqual(self.text("transformers").count("PlantoirFigures"), 1)
        self.assertEqual(self.text("transformers").count("CodeRunnerFences"), 1)

    def test_an_afterbody_that_already_holds_something_keeps_it(self):
        self.files["layout"].write_text(LAYOUT.replace("afterBody: [],", "afterBody: [Component.Comments()],"),
                                        encoding="utf-8")
        build_site.wire_quartz_additions(self.output)
        self.assertIn("afterBody: [Component.CodeRunner(), Component.Comments()],", self.text("layout"))

    def test_a_section_wired_before_563_gets_the_quizzes_after_its_figures(self):
        self.files["config"].write_text(CONFIG.replace(
            "      Plugin.Description(),\n", "      Plugin.Description(),\n      Plugin.PlantoirFigures(),\n", 1),
            encoding="utf-8")
        build_site.wire_quartz_additions(self.output)
        config = self.text("config")
        self.assertEqual(config.count("Plugin.PlantoirFigures("), 1)
        self.assertIn("Plugin.PlantoirFigures(),\n      Plugin.PlantoirQuizzes(),\n", config)

    def test_a_section_wired_before_519_gets_the_task_boxes_after_its_quizzes(self):
        self.files["config"].write_text(CONFIG.replace(
            "      Plugin.Description(),\n",
            "      Plugin.Description(),\n      Plugin.PlantoirFigures(),\n      Plugin.PlantoirQuizzes(),\n", 1),
            encoding="utf-8")
        self.files["transformers"].write_text(
            TRANSFORMERS_INDEX + 'export { PlantoirQuizzes } from "./plantoirQuizzes" // PLANTOIR-ADDITIONS\n',
            encoding="utf-8")
        build_site.wire_quartz_additions(self.output)
        config = self.text("config")
        self.assertEqual(config.count("Plugin.PlantoirQuizzes("), 1)
        self.assertIn("Plugin.PlantoirQuizzes(),\n      Plugin.PlantoirTasks(),\n", config)
        self.assertEqual(self.text("transformers").count("PlantoirTasks"), 1)

    def test_task_boxes_without_the_quizzes_anchor_are_said_and_left_out(self):
        changed = CONFIG.replace("Plugin.Description(),", "Plugin.Summary(),")
        self.files["config"].write_text(changed, encoding="utf-8")
        build_site.wire_quartz_additions(self.output)
        self.assertNotIn("PlantoirTasks", self.text("config"))

    def test_the_print_buttons_component_carries_the_task_boxes_script_and_styles(self):
        component = (Path(build_site.__file__).resolve().parent.parent / "support" / "quartz" / "components"
                     / "PlantoirMetaLine.tsx").read_text(encoding="utf-8")
        self.assertIn('import tasksStyle from "./styles/tasks.scss"', component)
        self.assertIn('import tasksScript from "./scripts/tasks.inline"', component)
        self.assertIn("quizStyle, tasksStyle, progressStyle)", component)
        self.assertIn("quizScript, tasksScript, progressScript, headingAnchorScript)", component)
        self.assertIn('import headingAnchorScript from "./scripts/headingAnchor.inline"', component)

    def test_the_print_buttons_component_carries_my_progress(self):
        component = (Path(build_site.__file__).resolve().parent.parent / "support" / "quartz" / "components"
                     / "PlantoirMetaLine.tsx").read_text(encoding="utf-8")
        self.assertIn('import progressStyle from "./styles/progress.scss"', component)
        self.assertIn('import progressScript from "./scripts/progress.inline"', component)

    def test_the_print_buttons_component_carries_the_picture_rule(self):
        # #609: every picture laid out at its real height before it scrolls
        # into view, on every page (Quartz's base.scss gives an off-screen
        # img zero height). The selector must outrank Quartz's bare `img`,
        # because this stylesheet comes BEFORE base.scss in index.css.
        components = Path(build_site.__file__).resolve().parent.parent / "support" / "quartz" / "components"
        component = (components / "PlantoirMetaLine.tsx").read_text(encoding="utf-8")
        self.assertIn('import picturesStyle from "./styles/pictures.scss"', component)
        self.assertIn("sidebarPageMarkerStyle, picturesStyle, quizStyle", component)
        rules = []
        for line in (components / "styles" / "pictures.scss").read_text(encoding="utf-8").splitlines():
            if not line.strip().startswith("//") and line.strip() != "":
                rules.append(line.strip())
        self.assertEqual(rules, ["html body img {", "content-visibility: visible;", "}"])

    def test_quizzes_without_the_figures_anchor_are_said_and_left_out(self):
        changed = CONFIG.replace("Plugin.Description(),", "Plugin.Summary(),")
        self.files["config"].write_text(changed, encoding="utf-8")
        build_site.wire_quartz_additions(self.output)
        self.assertNotIn("PlantoirQuizzes", self.text("config"))

    def test_a_moved_anchor_is_left_alone(self):
        changed = CONFIG.replace("Plugin.SyntaxHighlighting(", "Plugin.Highlighting(")
        self.files["config"].write_text(changed, encoding="utf-8")
        build_site.wire_quartz_additions(self.output)
        self.assertNotIn("CodeRunnerFences", self.text("config"))


if __name__ == "__main__":
    unittest.main()
