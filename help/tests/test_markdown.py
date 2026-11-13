"""The Markdown subset: what a page may use, and what is refused with its file and line."""

from __future__ import annotations

import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))

import unittest  # noqa: E402

from helpers import Fixture  # noqa: E402
from helpbook.markdown import parse_body, readable_inline  # noqa: E402
from helpbook.problems import Problems  # noqa: E402


def parse(text: str):
    problems = Problems()
    blocks = parse_body("page.md", text.split("\n"), 10, problems)
    return blocks, problems


class ParserTests(unittest.TestCase):
    def test_a_list_nests_one_level_and_keeps_its_continuation(self) -> None:
        blocks, problems = parse("1. First\n   carries on\n2. Second\n   - inner\n")
        self.assertEqual(problems.failures, [])
        self.assertEqual(blocks[0]["kind"], "list")
        self.assertTrue(blocks[0]["ordered"])
        self.assertEqual(len(blocks[0]["items"]), 2)
        self.assertEqual(blocks[0]["items"][0]["lines"][1][1], "carries on")
        self.assertEqual(blocks[0]["items"][1]["children"]["items"][0]["lines"][0][1], "inner")

    def test_a_second_level_of_nesting_is_refused(self) -> None:
        _blocks, problems = parse("- one\n  - two\n        - three\n")
        self.assertTrue(any("nest one level" in failure for failure in problems.failures), problems.failures)

    def test_a_table_needs_its_separator_and_even_rows(self) -> None:
        blocks, problems = parse("| A | B |\n|---|---:|\n| 1 | 2 |\n")
        self.assertEqual(problems.failures, [])
        self.assertEqual(blocks[0]["aligns"], ["", "right"])
        _blocks, problems = parse("| A | B |\n| 1 | 2 |\n")
        self.assertTrue(any("header row" in failure for failure in problems.failures))
        _blocks, problems = parse("| A | B |\n|---|---|\n| 1 |\n")
        self.assertTrue(any("cells" in failure for failure in problems.failures))

    def test_a_less_than_sign_is_not_html(self) -> None:
        _blocks, problems = parse("When a < b, the page says so.\n")
        self.assertEqual(problems.failures, [])

    def test_the_line_numbers_count_from_the_body(self) -> None:
        _blocks, problems = parse("Fine.\n\n<b>bold</b>\n")
        self.assertTrue(problems.failures[0].startswith("page.md:12:"), problems.failures)

    def test_readable_text_drops_code_tokens_and_link_targets(self) -> None:
        text = readable_inline("Press {{control:x}} and `docker` then [the page](page:deploy) **now**")
        self.assertNotIn("docker", text)
        self.assertNotIn("control", text)
        self.assertNotIn("deploy", text)
        self.assertIn("the page", text)
        self.assertIn("now", text)


class RefusedThroughTheBuild(unittest.TestCase):
    """Each refusal is seen through build_help.py --check, with file and line."""

    def setUp(self) -> None:
        self.fixture = Fixture()

    def tearDown(self) -> None:
        self.fixture.close()

    def refused(self, body: str, expected: str) -> str:
        self.fixture.page("second-look", body)
        code, output = self.fixture.run("--check")
        self.assertNotEqual(code, 0, output)
        self.assertIn(expected, output)
        return output

    def test_the_fixture_builds(self) -> None:
        code, output = self.fixture.run("--check")
        self.assertEqual(code, 0, output)

    def test_raw_html_is_refused_with_file_and_line(self) -> None:
        output = self.refused("Some words.\n\n<div>boxed</div>\n", "help/pages/second-look.md:10: raw HTML")
        self.assertIn("<div>", output)

    def test_a_bare_text_fence_is_refused(self) -> None:
        self.refused("```text\nwords\n```\n", "help/pages/second-look.md:8: a text block is written ```text wrap")

    def test_a_fence_without_a_language_is_refused(self) -> None:
        self.refused("```\nwords\n```\n", "names its language")

    def test_an_h1_is_refused(self) -> None:
        self.refused("# A title\n", "a page has one h1")

    def test_a_level_three_heading_before_level_two_is_refused(self) -> None:
        self.refused("### Too deep\n\nWords.\n", "a ### heading comes under a ## heading")

    def test_a_plain_quote_is_refused(self) -> None:
        self.refused("> quoted words\n", "the only quote block is a `> [!note]` callout")

    def test_a_platform_run_must_close_and_may_not_nest(self) -> None:
        self.refused("{{mac}}\nWords.\n", "is never closed")
        self.refused("{{mac}}\n{{windows}}\nWords.\n{{/windows}}\n{{/mac}}\n", "may not nest")

    def test_a_picture_needs_alt_text(self) -> None:
        self.refused("{{picture:second-look-1}}\n\nWords.\n", "needs alt text")

    def test_an_image_in_markdown_syntax_is_refused(self) -> None:
        self.refused("![a picture](x.webp)\n", "pictures are written {{picture:<scene>}}")

    def test_an_unknown_token_is_refused(self) -> None:
        self.refused("Press {{button:x}}.\n", "unknown token")

    def test_a_wrong_list_marker_is_refused(self) -> None:
        self.refused("1. One\n* Two\n", "list items start with `1.` or `-`")
        self.refused("1. One\n2) Two\n", "list items start with `1.` or `-`")
        self.refused("1. One\n\t- Two\n", "list items start with `1.` or `-`")
        self.refused("- One\n  * Two\n", "list items start with `1.` or `-`")

    def test_an_html_entity_or_an_unclosed_marker_is_refused(self) -> None:
        self.refused("Press&nbsp;here.\n", "an HTML entity is printed as typed")
        self.refused("Select **a section.\n", "a ` or ** is never closed")
        self.refused("Type `here.\n", "a ` or ** is never closed")

    def test_steps_must_count_up_by_one(self) -> None:
        self.refused("1. One\n3. Three\n", "step 3 follows step 1")
        self.refused("2. Two\n", "numbered steps start at 1")


class StepsAcrossBlocks(unittest.TestCase):
    """Numbered steps keep counting across a picture, a note, a table or a code block."""

    BETWEEN = {
        "picture": "{{picture:first-steps-1}}\nalt: The window, with its sidebar.\n",
        "note": "> [!note]\n> A note between the steps.\n",
        "table": "| A | B |\n|---|---|\n| 1 | 2 |\n",
        "code": "```text wrap\nsome words\n```\n",
    }

    def setUp(self) -> None:
        self.fixture = Fixture()

    def tearDown(self) -> None:
        self.fixture.close()

    def steps_around(self, between: str, second_number: int):
        body = (
            "Words.\n\n## Steps\n\n1. Open it.\n2. Look.\n\n" + between + "\n"
            + str(second_number) + ". Press it.\n" + str(second_number + 1) + ". Wait.\n"
        )
        self.fixture.replace("help/pages/first-steps.md", "Open the fixture and look at the window.\n", body)
        return self.fixture.run("--web", str(self.fixture.out / "web"))

    def test_the_steps_after_each_block_carry_on_at_3(self) -> None:
        for name in self.BETWEEN:
            with self.subTest(between=name):
                fixture = Fixture()
                self.fixture.close()
                self.fixture = fixture
                code, output = self.steps_around(self.BETWEEN[name], 3)
                self.assertEqual(code, 0, output)
                html = (self.fixture.out / "web" / "first-steps.html").read_text(encoding="utf-8")
                self.assertIn('<ol start="3">\n<li>Press it.</li>', html)

    def test_steps_that_restart_at_1_after_a_block_are_refused(self) -> None:
        for name in self.BETWEEN:
            with self.subTest(between=name):
                fixture = Fixture()
                self.fixture.close()
                self.fixture = fixture
                code, output = self.steps_around(self.BETWEEN[name], 1)
                self.assertNotEqual(code, 0, output)
                self.assertIn("these steps follow step 2 across a picture, note, table or code block: number this one 3", output)

    def test_a_paragraph_between_starts_new_steps(self) -> None:
        code, output = self.steps_around("Then a sentence of its own.\n", 1)
        self.assertEqual(code, 0, output)


if __name__ == "__main__":
    unittest.main()
