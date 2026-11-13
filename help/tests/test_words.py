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
    # The cases of both reviews: correct sentences that explain publish and deploy,
    # and misuses that must be refused.
    CORRECT = [
        "Publish the pages, then deploy the section.",
        "Publish the class for a date.",
        "Show or hide pages for a section.",
        "Deploy to GitHub Pages.",
        "Put your site online with Cloudflare Pages.",
        "When the site is ready, publish one class.",
        "Published pages appear on the site.",
        "Deploy sends every published page in the section.",
        "Choose videos from a publisher whose site allows embedding.",
        "A page you publish today shows on the site once you deploy.",
        "Pages you have published stay hidden from the site until you deploy.",
        "Deploy now, and the new pages appear.",
    ]
    MISUSE = [
        "Publish the site to Netlify.",
        "Publishing it online takes a while.",
        "Publish the class to section 2.",
        "Publish it to a folder on this Mac.",
        "Deploy the page for Thursday.",
        "Publish to the web when the site is ready.",
        "Publish it to your school's server.",
        "The site was published yesterday.",
        "Deploy Unit 3 so students see it.",
        "Publish it to GitHub Pages.",
    ]

    def test_correct_sentences_about_publish_and_deploy_pass(self) -> None:
        for sentence in self.CORRECT:
            with self.subTest(sentence=sentence):
                self.assertEqual(publish_deploy_problems(sentence), [])

    def test_each_misuse_of_publish_and_deploy_is_refused(self) -> None:
        for sentence in self.MISUSE:
            with self.subTest(sentence=sentence):
                self.assertGreater(len(publish_deploy_problems(sentence)), 0)

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
        self.refused("It says the section was copied into the folder you chose.\n", "retypes a whole sentence the app shows")
        self.refused("Ask me to show or hide a class for a section.\n", "retypes a whole sentence the app shows")

    def test_a_whole_sentence_retyped_with_small_changes_is_still_refused(self) -> None:
        # A line break in the middle, a changed full stop, a straight quote for a curly one.
        self.refused("Then the section was copied into the\nfolder you chose; that is all it does.\n", "help/pages/second-look.md:8: retypes a whole sentence")
        self.refused("The teacher's copy stays on this Mac.\n", "help/pages/second-look.md:8: retypes a whole sentence")
        self.refused("It shows THE SECTION WAS COPIED INTO THE FOLDER YOU CHOSE\n", "retypes a whole sentence")

    def test_a_fragment_of_a_contract_sentence_is_ordinary_english(self) -> None:
        self.passes("The section was copied into a new place.\n")
        self.passes("Pick the folder you chose last time.\n")

    def test_a_contract_sentence_with_a_placeholder_matches_any_words_there(self) -> None:
        self.refused("Deploying Section 2 to the folder now.\n", "retypes a whole sentence")

    def test_the_same_sentence_through_a_say_token_passes(self) -> None:
        self.passes("It says {{say:shared-rules#fixtureNotice.wording.finished}}\n")

    def test_an_outline_title_holding_a_contract_sentence_builds_as_a_written_page(self) -> None:
        # A title NAMES something (often a menu item's words); it is not a sentence retyped.
        self.fixture.replace("help/outline.json", '"title": "Have a second look"', '"title": "Ask me to show or hide a class for a section"')
        self.fixture.replace("help/outline.json", "What else is in the fixture window?", "Can I show or hide a class for a section?")
        self.passes("Words.\n\n## Show or hide a class for a section\n\nMore words.\n")
        # The same words in running prose are still refused.
        self.refused("Words.\n\nAsk me to show or hide a class for a section.\n", "retypes a whole sentence the app shows")

    def test_the_interface_words_are_checked(self) -> None:
        self.fixture.replace("help/interface-words.json", '"Search Help"', '"Search Help seamlessly"')
        code, output = self.fixture.run("--check")
        self.assertNotEqual(code, 0, output)
        self.assertIn("help/interface-words.json: tone: 'seamlessly'", output)

    def test_the_title_and_question_of_a_stub_are_read(self) -> None:
        self.fixture.replace("help/outline.json", "What else is in the fixture window?", "What is seamlessly in the window?")
        code, output = self.fixture.run("--check")
        self.assertNotEqual(code, 0, output)
        self.assertIn("help/outline.json (second-look):1: tone: 'seamlessly'", output)


if __name__ == "__main__":
    unittest.main()
