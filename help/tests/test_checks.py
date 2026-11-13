"""The structural checks: the outline owns each page's identity, and pages,
scenes, links and head fields agree with it."""

from __future__ import annotations

import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))

import unittest  # noqa: E402

from helpers import Fixture  # noqa: E402


class StructureTests(unittest.TestCase):
    def setUp(self) -> None:
        self.fixture = Fixture()

    def tearDown(self) -> None:
        self.fixture.close()

    def refused(self, expected: str) -> None:
        code, output = self.fixture.run("--check")
        self.assertNotEqual(code, 0, output)
        self.assertIn(expected, output)

    def test_two_outline_entries_with_one_id_are_refused(self) -> None:
        self.fixture.replace("help/outline.json", '"id": "python-page", "anchor": "python-page"', '"id": "send-section", "anchor": "send-section"')
        self.refused("two outline entries have the id send-section")

    def test_an_anchor_that_differs_from_the_id_is_refused(self) -> None:
        self.fixture.replace("help/outline.json", '"anchor": "second-look"', '"anchor": "second-glance"')
        self.refused("second-look: its anchor 'second-glance' differs from its id")

    def test_a_picture_outside_the_pages_scene_ids_is_refused(self) -> None:
        self.fixture.page("second-look", "{{picture:first-steps-1}}\nalt: A window.\n")
        self.refused("{{picture:first-steps-1}} is not one of this page's outline sceneIds")

    def test_a_scene_that_names_another_page_is_refused(self) -> None:
        self.fixture.replace("help/scenes.json", '"first-steps-1": {"page": "first-steps"', '"first-steps-1": {"page": "second-look"')
        self.refused("first-steps-1 is not in the sceneIds of page second-look")
        self.refused("scene first-steps-1 belongs to page second-look")

    def test_a_scene_in_no_outline_scene_ids_is_refused(self) -> None:
        self.fixture.replace(
            "help/scenes.json",
            '"scenes": {',
            '"scenes": {\n  "first-steps-9": {"page": "first-steps", "shows": "x", "labels": [], "awaiting_capture": true, "setup": "x"},',
        )
        self.refused("first-steps-9 is not in the sceneIds of page first-steps")

    def test_a_scene_with_an_unknown_field_is_refused(self) -> None:
        self.fixture.replace("help/scenes.json", '"raw": false}', '"raw": false, "colour": "red"}')
        self.refused("has an unknown field `colour`")

    def test_a_covers_path_that_does_not_exist_is_refused(self) -> None:
        self.fixture.replace("help/pages/first-steps.md", "Views/FixtureView.swift", "Views/NoSuchView.swift")
        self.refused("covers 'mac-app/QuartzTeachers/Views/NoSuchView.swift', which does not exist")

    def test_page_and_scene_counts_must_agree_with_the_lists(self) -> None:
        self.fixture.replace("help/outline.json", '"pageCount": 5', '"pageCount": 6')
        self.refused("pageCount is 6 but the sections list 5")
        self.fixture.replace("help/outline.json", '"pageCount": 6', '"pageCount": 5')
        self.fixture.replace("help/outline.json", '"sceneCount": 2', '"sceneCount": 3')
        self.refused("sceneCount is 3 but the pages list 2")

    def test_a_front_matter_title_is_refused(self) -> None:
        self.fixture.page("second-look", "Words.\n", extra_front_matter="title: Another title\n")
        self.refused("`title` comes from help/outline.json only")

    def test_front_matter_may_not_restate_the_assistant_flag(self) -> None:
        self.fixture.page("second-look", "Words.\n", extra_front_matter="assistant: true\n")
        self.refused("`assistant` comes from help/outline.json only")

    def test_a_page_file_with_no_outline_entry_is_refused(self) -> None:
        self.fixture.page("not-in-outline", "Words.\n")
        self.refused("not-in-outline is not a page in help/outline.json")

    def test_an_id_that_differs_from_the_file_name_is_refused(self) -> None:
        self.fixture.replace("help/pages/helper-page.md", "id: helper-page", "id: helper")
        self.refused("`id: helper` differs from the file name helper-page")

    def test_a_link_to_a_missing_page_is_refused(self) -> None:
        self.fixture.page("second-look", "Read [this](page:no-such-page).\n")
        self.refused("links to page:no-such-page, which is not in help/outline.json")

    def test_a_malformed_https_link_is_refused(self) -> None:
        self.fixture.page("second-look", "Read [this](https://nowhere).\n")
        self.refused("a well-formed https:// address")
        self.fixture.page("second-look", "Read [this](http://example.com/).\n")
        self.refused("a well-formed https:// address")

    def test_a_written_page_needs_its_head_fields_and_a_stub_does_not(self) -> None:
        code, output = self.fixture.run("--check")
        self.assertEqual(code, 0, output)
        self.fixture.write("help/pages/second-look.md", "---\nid: second-look\nchecked: 2.0\n---\nWords.\n")
        self.refused("`checked:` is the version")
        self.refused("`description:` is one sentence")
        self.refused("a task page carries `keywords:`")

    def test_an_assistant_page_sits_in_the_assistant_section(self) -> None:
        self.fixture.replace("help/outline.json", '"section": "Working", "assistant": false', '"section": "Working", "assistant": true')
        self.refused("a page is `assistant: true` exactly when it sits in the assistant section")

    def test_a_tone_exemption_for_a_missing_page_is_refused(self) -> None:
        self.fixture.replace("help/tone.json", '"pages": ["python-page"]', '"pages": ["no-page"]')
        self.refused("names page no-page, which is not in the outline")

    def test_check_writes_nothing(self) -> None:
        code, output = self.fixture.run("--check")
        self.assertEqual(code, 0, output)
        self.assertFalse(self.fixture.out.exists())


if __name__ == "__main__":
    unittest.main()
