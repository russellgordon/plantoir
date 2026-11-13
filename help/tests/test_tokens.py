"""Tokens and their truth checks: menus against the golden, controls against
the Swift source, sentences against the contract, facts, keys and counts."""

from __future__ import annotations

import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))

import unittest  # noqa: E402

from helpers import REPO, Fixture  # noqa: E402
from helpbook.tokens import parse_menu_golden  # noqa: E402


class RealGoldenTests(unittest.TestCase):
    def test_the_real_golden_parses_into_every_menu_and_item(self) -> None:
        text = (REPO / "mac-app" / "Tests" / "Goldens" / "menu-bar.txt").read_text(encoding="utf-8")
        paths = parse_menu_golden(text)
        menus = 0
        items = 0
        for line in text.split("\n"):
            if line.startswith("== "):
                menus += 1
            elif line.startswith("  ") and line.strip() != "----":
                items += 1
        self.assertGreater(menus, 3)
        self.assertGreater(items, 50)
        self.assertEqual(len(paths), menus + items)
        self.assertIn(("Section",), paths)
        self.assertEqual(paths[("Section", "Deploy…")], "⇧⌘D")
        self.assertEqual(paths[("Section", "Preview at Last Viewed")], "⌥⇧⌘P")
        self.assertIn(("Course", "Revise With", "Claude…"), paths)
        self.assertIn(("File", "Open Recent", "Clear Menu"), paths)
        self.assertIsNone(paths[("Help", "Plantoir Help")])
        for path in paths:
            self.assertNotIn("----", path)
            for part in path:
                self.assertNotIn("[", part)
                self.assertNotIn("(alternate)", part)


class TokenTests(unittest.TestCase):
    def setUp(self) -> None:
        self.fixture = Fixture()

    def tearDown(self) -> None:
        self.fixture.close()

    def check(self):
        return self.fixture.run("--check")

    def refused(self, expected: str) -> None:
        code, output = self.check()
        self.assertNotEqual(code, 0, output)
        self.assertIn(expected, output)

    def test_an_unknown_menu_id_is_refused(self) -> None:
        self.fixture.page("second-look", "Choose {{menu:nope}}.\n")
        self.refused("{{menu:nope}}: no such id")

    def test_a_menu_path_not_in_the_golden_is_refused(self) -> None:
        self.fixture.replace("help/menu-paths.json", "Section ▸ Preview", "Section ▸ Preview Everything")
        self.refused("'Section ▸ Preview Everything' is not a path in")

    def test_a_system_menu_passes_and_a_made_up_one_does_not(self) -> None:
        code, output = self.check()
        self.assertEqual(code, 0, output)
        self.fixture.replace("help/menu-paths.json", '"Plantoir ▸ Settings…", "system": true', '"Section ▸ Nope…", "system": true')
        self.refused("is marked system but 'Section ▸ Nope…' is not in help/system-menus.json")

    def test_a_control_label_that_is_not_in_its_file_is_refused(self) -> None:
        self.fixture.replace("help/controls.json", '"Send the Section"', '"Send It"')
        self.refused("label 'Send It' is not a string literal")

    def test_a_wording_constant_that_reads_otherwise_is_refused(self) -> None:
        self.fixture.replace("help/controls.json", '"Keep Both Copies"', '"Keep Both"')
        self.refused("no `static let keepButton` in FixtureWording")

    def test_a_control_from_the_contract_must_match(self) -> None:
        self.fixture.replace("help/controls.json", '"Open in Browser"', '"Open in a Browser"')
        self.refused("reads 'Open in Browser', not 'Open in a Browser'")

    def test_a_say_key_that_does_not_exist_is_refused(self) -> None:
        self.fixture.page("second-look", "It says {{say:shared-rules#fixtureNotice.wording.nothere}}.\n")
        self.refused("{{say:shared-rules#fixtureNotice.wording.nothere}} does not resolve")

    def test_a_say_key_must_name_a_sentence(self) -> None:
        self.fixture.page("second-look", "It says {{say:shared-rules#fixtureNotice.count}}.\n")
        self.refused("names a int, not a sentence")

    def test_a_say_key_into_a_list(self) -> None:
        self.fixture.page("second-look", "It is {{say:shared-rules#userFacingLabelWords.forbidden[1]}}.\n")
        code, output = self.check()
        self.assertEqual(code, 0, output)

    def test_an_unknown_fact_count_or_key_is_refused(self) -> None:
        self.fixture.page("second-look", "It is {{fact:nope}}.\n")
        self.refused("{{fact:nope}}: no such id")
        self.fixture.page("second-look", "It is {{count:nope}}.\n")
        self.refused("{{count:nope}}: the counts are")
        self.fixture.page("second-look", "Press {{key:nope}}.\n")
        self.refused("{{key:nope}}: no menu id or keys entry")

    def test_an_old_fact_is_a_warning_and_not_a_failure(self) -> None:
        code, output = self.fixture.run("--check")
        self.assertNotIn("days ago", output)
        from helpers import run_build

        code, output = run_build(
            ["--check", "--repo", str(self.fixture.repo), "--help-dir", str(self.fixture.help_dir), "--today", "2027-03-01"]
        )
        self.assertEqual(code, 0, output)
        self.assertIn("warning: help/facts.json: fixture-fact was read on 2026-11-01, more than 60 days ago", output)

    def test_an_unused_menu_id_is_a_warning_and_exits_zero(self) -> None:
        self.fixture.replace(
            "help/menu-paths.json",
            '"new-course": {',
            '"spare": {"mac": "Help ▸ Plantoir Help", "windows": null},\n  "new-course": {',
        )
        code, output = self.check()
        self.assertEqual(code, 0, output)
        self.assertIn("warning: help/menu-paths.json: spare is used by no page", output)

    def test_a_windows_run_needs_the_windows_column(self) -> None:
        self.fixture.page("second-look", "{{windows}}\nChoose {{menu:preview}}.\n{{/windows}}\n")
        self.refused("{{menu:preview}} has no windows path yet")


if __name__ == "__main__":
    unittest.main()
