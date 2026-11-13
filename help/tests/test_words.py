"""The word check: machinery, tone, publish and deploy, typed counts, quoted
runs, long sentences and contract sentences typed by hand."""

from __future__ import annotations

import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))

import unittest  # noqa: E402

from helpers import Fixture  # noqa: E402
from helpbook.words import publish_deploy_problems, typed_count_problems  # noqa: E402


class RuleTests(unittest.TestCase):
    def test_publish_followed_by_a_destination_is_the_wrong_verb(self) -> None:
        self.assertEqual(len(publish_deploy_problems("Publish the site to Netlify.")), 1)
        self.assertEqual(len(publish_deploy_problems("Publishing it online takes a while.")), 1)
        self.assertEqual(len(publish_deploy_problems("Publish the class to section 2.")), 1)
        self.assertEqual(len(publish_deploy_problems("Publish it to a folder on this Mac.")), 1)

    def test_publish_and_deploy_used_rightly_pass(self) -> None:
        self.assertEqual(publish_deploy_problems("Publish the pages, then deploy the section."), [])
        self.assertEqual(publish_deploy_problems("Publish the class for a date."), [])
        self.assertEqual(publish_deploy_problems("Show or hide pages for a section."), [])
        self.assertEqual(publish_deploy_problems("Deploy to GitHub Pages."), [])
        self.assertEqual(publish_deploy_problems("Put your site online with Cloudflare Pages."), [])

    def test_deploy_followed_by_page_is_the_wrong_verb(self) -> None:
        self.assertEqual(len(publish_deploy_problems("Deploy the page for Thursday.")), 1)

    def test_only_the_words_after_the_verb_count(self) -> None:
        self.assertEqual(publish_deploy_problems("When the site is ready, publish one class."), [])

    def test_a_year_is_not_a_typed_count(self) -> None:
        self.assertEqual(typed_count_problems("The 2026-27 courses start in September."), [])
        self.assertEqual(len(typed_count_problems("There are 39 ready-made courses.")), 1)


class WordCheckTests(unittest.TestCase):
    def setUp(self) -> None:
        self.fixture = Fixture()

    def tearDown(self) -> None:
        self.fixture.close()

    def refused(self, body: str, expected: str) -> None:
        self.fixture.page("second-look", body)
        code, output = self.fixture.run("--check")
        self.assertNotEqual(code, 0, output)
        self.assertIn(expected, output)

    def passes(self, body: str) -> str:
        self.fixture.page("second-look", body)
        code, output = self.fixture.run("--check")
        self.assertEqual(code, 0, output)
        return output

    def test_seamlessly_in_a_body_is_refused(self) -> None:
        self.refused("The site updates seamlessly.\n", "help/pages/second-look.md:8: tone: 'seamlessly'")

    def test_docker_in_alt_text_is_refused(self) -> None:
        self.fixture.replace("help/outline.json", '"scenes": 0, "sceneIds": []}', '"scenes": 1, "sceneIds": ["second-look-1"]}')
        self.fixture.replace("help/outline.json", '"sceneCount": 2', '"sceneCount": 3')
        self.fixture.replace(
            "help/scenes.json",
            '"scenes": {',
            '"scenes": {\n  "second-look-1": {"page": "second-look", "shows": "A window", "labels": [], '
            '"awaiting_capture": true, "setup": "fixture"},',
        )
        self.passes("{{picture:second-look-1}}\nalt: The window, with its sidebar.\n")
        self.refused("{{picture:second-look-1}}\nalt: The Docker window, with its sidebar.\n", "names the machinery ('Docker')")

    def test_python_in_a_code_span_passes_and_in_a_body_does_not(self) -> None:
        self.passes("Mark the block `python` in the page.\n")
        self.refused("Write it in Python.\n", "names the machinery ('Python')")

    def test_an_exemption_is_scoped_to_its_pages(self) -> None:
        # python-page carries "Python" in its body and description: exempt there only.
        code, output = self.fixture.run("--check")
        self.assertEqual(code, 0, output)

    def test_a_machinery_word_from_the_site_list_is_refused(self) -> None:
        self.refused("The model reads it.\n", "the site's MACHINERY list")

    def test_a_typed_count_is_refused(self) -> None:
        self.refused("There are 39 ready-made courses.\n", "types a count ('39' near 'courses.')")

    def test_a_count_token_is_not_a_typed_count(self) -> None:
        self.passes("There are {{count:ready_made_ontario}} ready-made courses.\n")

    def test_publish_to_a_site_is_refused_on_a_page(self) -> None:
        self.refused("Publish the site to Netlify.\n", "PUBLISH marks a page for students")

    def test_publish_inside_a_menu_token_is_not_read(self) -> None:
        self.fixture.replace(
            "help/menu-paths.json", '"new-course": {', '"publish": {"mac": "Section ▸ Deploy…", "windows": null},\n  "new-course": {'
        )
        self.passes("Choose {{menu:publish}} and then the site.\n")

    def test_a_long_quoted_run_is_refused_unless_exempted(self) -> None:
        self.passes("The button says “Keep it”.\n")
        self.refused("The sheet says “the section was sent away”.\n", "quotes a run of more than three words")
        self.fixture.replace(
            "help/tone.json",
            '"quotes": []',
            '"quotes": [{"phrase": "“the section was sent away”", "pages": ["second-look"], "why": "fixture"}]',
        )
        self.passes("The sheet says “the section was sent away”.\n")

    def test_a_long_sentence_is_a_warning(self) -> None:
        sentence = " ".join(["word"] * 30) + ".\n"
        output = self.passes(sentence)
        self.assertIn("warning: help/pages/second-look.md:8: a sentence of 30 words", output)

    def test_a_contract_sentence_typed_by_hand_is_refused(self) -> None:
        self.refused("It says the section was copied into the folder you chose.\n", "types a sentence the app shows")
        self.refused("Ask me to show or hide a class for a section.\n", "types a sentence the app shows")

    def test_the_same_sentence_through_a_say_token_passes(self) -> None:
        self.passes("It says {{say:shared-rules#fixtureNotice.wording.finished}}\n")

    def test_the_title_and_question_of_a_stub_are_read(self) -> None:
        self.fixture.replace("help/outline.json", "What else is in the fixture window?", "What is seamlessly in the window?")
        code, output = self.fixture.run("--check")
        self.assertNotEqual(code, 0, output)
        self.assertIn("help/outline.json (second-look):1: tone: 'seamlessly'", output)


if __name__ == "__main__":
    unittest.main()
