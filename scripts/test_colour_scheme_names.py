#!/usr/bin/env python3
"""
A colour scheme's name never names the machinery (CLAUDE.md rule 1, GitHub #383).

The names a teacher picks from — in both apps' colour-scheme pickers, the
command-line wizard, and the build's "Applied colour scheme" line — are DATA,
held in support/colour_schemes.json. The mac's label scan (#369,
UserFacingLabelWordsTests) reads Swift string literals and so cannot see them,
which is how "Quartz Standard Colours" shipped from v1.0.0 to v1.4.1. This file
holds every scheme's name against the same list of forbidden words that scan
uses — contracts/shared-rules.json → userFacingLabelWords.forbidden, read here
rather than retyped, so a word added there is checked here too.

Pure Python with no shell, so Windows' PythonToolchainTests discovers and runs
it as well. Both files are read as UTF-8 explicitly: on Windows, open() would
otherwise use the locale's code page, and shared-rules.json holds UTF-8.
"""

import json
import re
import unittest
from pathlib import Path

REPOSITORY = Path(__file__).resolve().parent.parent
SCHEMES_FILE = REPOSITORY / "support" / "colour_schemes.json"
SHARED_RULES_FILE = REPOSITORY / "contracts" / "shared-rules.json"

# The id every existing course stores and both wizards default to
# (NewCourseWizardView.swift, WizardDefaults.cs). Renaming the scheme must
# never rename this: a course whose stored id is not found would change colour.
DEFAULT_SCHEME_ID = "quartz-standard"


def read_json(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def words_in(text):
    """Whole words, lower-cased, as the contract's `matching` describes:
    "description" is the word "description", and does not contain "script"."""
    return re.findall(r"[a-z0-9]+", text.lower())


def forbidden_words_in(text, forbidden):
    found = []
    for word in words_in(text):
        if word in forbidden and word not in found:
            found.append(word)
    return found


class TheSchemeNames(unittest.TestCase):

    def setUp(self):
        self.schemes = read_json(SCHEMES_FILE)
        rules = read_json(SHARED_RULES_FILE)
        self.forbidden = rules["userFacingLabelWords"]["forbidden"]

    def test_no_scheme_name_holds_a_forbidden_word(self):
        self.assertTrue(len(self.forbidden) > 0, "the forbidden list was read empty")
        problems = []
        for scheme in self.schemes:
            found = forbidden_words_in(scheme["name"], self.forbidden)
            if found:
                problems.append(
                    f"{scheme['id']}: “{scheme['name']}” says {', '.join(found)}"
                )
        self.assertEqual(
            problems, [],
            "a colour scheme's name is read by a teacher and must not name the "
            "machinery (userFacingLabelWords.forbidden): " + "; ".join(problems),
        )

    def test_the_default_scheme_keeps_its_id(self):
        self.assertTrue(len(self.schemes) > 0)
        first = self.schemes[0]
        self.assertEqual(
            first["id"], DEFAULT_SCHEME_ID,
            "the first scheme is the one both wizards default to, and every "
            "existing course stores its id: rename its NAME, never its id",
        )


class TheWordRule(unittest.TestCase):
    """The matcher this file uses is whole-word, so a substring matcher cannot
    slip in and flag an honest name."""

    FORBIDDEN = ["quartz", "script", "docker"]

    def test_the_old_name_is_caught(self):
        self.assertEqual(
            forbidden_words_in("Quartz Standard Colours", self.FORBIDDEN), ["quartz"]
        )

    def test_a_word_inside_another_word_is_not_caught(self):
        self.assertEqual(forbidden_words_in("Descriptive Blues", self.FORBIDDEN), [])

    def test_case_does_not_hide_a_word(self):
        self.assertEqual(forbidden_words_in("DOCKER Blue", self.FORBIDDEN), ["docker"])


if __name__ == "__main__":
    unittest.main()
