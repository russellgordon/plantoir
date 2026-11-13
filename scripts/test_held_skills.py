#!/usr/bin/env python3
"""A skill held out of a release is installed nowhere and offered by nothing (#750, 2026-11-13).

Marking and report comments were deferred from v2.0.0 on both platforms. Their skills are kept whole in
the repository, in the folder contracts/shared-rules.json -> printablePages.agentGuidance.held names as
`place`, which neither app copies into a working folder: both apps write every folder under
support/agent_guidance/skills, and nothing else, into .claude/skills and .agents/skills (and the GitHub
Copilot door reads those same two homes). So the source folder IS what a working folder receives, on every
platform and for every outside assistant, and this test reads it rather than an app.

The held list is ONE key, `held.skills`. `held.words.bySkill` carries, per held skill, the regular
expressions that would offer it, `held.words.allowed` the sentences that may say them (the one the
test-authoring skill gives when asked to mark), and `mustTrip` and `mustPass` the cases that prove the
expressions catch the ways a teacher or an assistant would say either feature and leave ordinary uses of
"marks" and "marking" alone. Bringing a skill back is `held.whenTheyReturn.steps`; this test then checks
nothing for it, and fails if the folder moved without the contract or the contract without the folder.

While a skill is held this checks:
  - its folder is in `place`, whole (a SKILL.md), and NOT in support/agent_guidance/skills;
  - neither root file (CLAUDE.md, AGENTS.md), and no file of any written skill except a skill named in
    `held.mayStillName`, names it or says one of its words;
  - no greeting or sentence in contracts/app-rules.json or contracts/assist-wording.json, nothing in either
    app's sources, nothing in Help (help/*.json, the outline's titles, questions and steps included, and
    help/pages) and nothing in plantoir.app's page sources names it or says one of its words.

Stdlib only; runs on the mac (verify.sh) and on Windows (PythonToolchainTests) alike.
"""

import json
import re
import unittest
from pathlib import Path

REPOSITORY = Path(__file__).resolve().parents[1]
SHARED_RULES = REPOSITORY / "contracts" / "shared-rules.json"
GUIDANCE = REPOSITORY / "support" / "agent_guidance"
WRITTEN_SKILLS = GUIDANCE / "skills"
ROOT_FILES = [GUIDANCE / "CLAUDE.md", GUIDANCE / "AGENTS.md"]
WORDING_CONTRACTS = [REPOSITORY / "contracts" / "app-rules.json", REPOSITORY / "contracts" / "assist-wording.json"]
HELP = REPOSITORY / "help"

# Where each app's own words live, Help's included. A folder that is not in this checkout (a partial
# clone) is skipped, and the test says which.
APP_SOURCES = [
    (REPOSITORY / "mac-app" / "QuartzTeachers", [".swift", ".strings", ".json", ".md", ".html"]),
    (REPOSITORY / "windows-app" / "Plantoir", [".cs", ".xaml", ".json", ".md", ".html"]),
    (REPOSITORY / "windows-app" / "Plantoir.Core", [".cs", ".json", ".md"]),
    (REPOSITORY / "windows-app" / "Plantoir.Mcp", [".cs", ".json", ".md"]),
    (REPOSITORY / "website" / "pages", [".html", ".md", ".json"]),
    (REPOSITORY / "website" / "layout", [".html", ".md", ".json"]),
    (HELP / "pages", [".md", ".html", ".json"]),
]
BUILD_FOLDERS = {"bin", "obj", "__pycache__", ".build"}


_RULES = {}


def shared_rules():
    # Read once: the file is several megabytes and every check below asks for it.
    if "rules" not in _RULES:
        _RULES["rules"] = json.loads(SHARED_RULES.read_text(encoding="utf-8"))
    return _RULES["rules"]


def held_block():
    return shared_rules()["printablePages"]["agentGuidance"].get("held", {})


def held_skills():
    return held_block().get("skills", {})


def held_words():
    return held_block().get("words", {})


def folded(text):
    """Every run of white space as one space, so a phrase wrapped across lines is still one phrase."""
    return " ".join(text.split())


def expressions_for(skill_name):
    result = []
    for pattern in held_words().get("bySkill", {}).get(skill_name, []):
        result.append(re.compile(pattern, re.IGNORECASE))
    return result


def first_word_said(text, skill_name):
    """The first passage of `text` that offers the held skill, or None. The `allowed` sentences are
    taken out first: they are what an assistant says when asked, and they offer nothing."""
    text = folded(text)
    for allowed in held_words().get("allowed", []):
        text = text.replace(folded(allowed), " ")
    for expression in expressions_for(skill_name):
        match = expression.search(text)
        if match is not None:
            return match.group(0)
    return None


def first_skill_offered(text):
    for skill_name in held_words().get("bySkill", {}):
        word = first_word_said(text, skill_name)
        if word is not None:
            return skill_name, word
    return None


def readable_text(path):
    """The file's text, or None for a file that is not UTF-8 text (a font, a picture)."""
    try:
        return path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        return None


def files_under(folder, endings=None):
    found = []
    for path in sorted(folder.rglob("*")):
        if not path.is_file():
            continue
        in_build_folder = False
        for part in path.relative_to(folder).parts:
            if part in BUILD_FOLDERS:
                in_build_folder = True
        if in_build_folder:
            continue
        if endings is not None and path.suffix.lower() not in endings:
            continue
        found.append(path)
    return found


def strings_in(node):
    """Every string in a JSON document, keys included."""
    found = []
    if isinstance(node, dict):
        for key, value in node.items():
            found.append(key)
            for text in strings_in(value):
                found.append(text)
    elif isinstance(node, list):
        for value in node:
            for text in strings_in(value):
                found.append(text)
    elif isinstance(node, str):
        found.append(node)
    return found


class HeldWordTests(unittest.TestCase):

    def test_every_must_trip_sentence_is_caught(self):
        if not held_skills():
            self.skipTest("no skill is held in this release")
        sentences = held_words().get("mustTrip", [])
        self.assertGreaterEqual(len(sentences), 10)
        for sentence in sentences:
            self.assertIsNotNone(first_skill_offered(sentence), "not caught: " + sentence)

    def test_every_must_pass_sentence_is_left_alone(self):
        sentences = held_words().get("mustPass", [])
        for sentence in sentences:
            self.assertIsNone(first_skill_offered(sentence), "caught, but it offers nothing: " + sentence)

    def test_the_held_list_and_its_words_agree(self):
        skills = held_skills()
        if not skills:
            self.skipTest("no skill is held in this release")
        by_skill = held_words().get("bySkill", {})
        for skill_name in skills:
            self.assertIn(skill_name, by_skill, f"held.words.bySkill has no entry for the held {skill_name}")
            self.assertTrue(by_skill[skill_name], f"held.words.bySkill has no words for {skill_name}")
        for skill_name in by_skill:
            self.assertIn(skill_name, skills, f"held.words.bySkill names {skill_name}, which is not held")
        assessment_held = shared_rules()["assessment"].get("held", {})
        for skill_name in assessment_held.get("skills", []):
            self.assertIn(skill_name, skills, f"assessment.held names {skill_name}, which is not held")


class HeldSkillTests(unittest.TestCase):

    def test_a_held_skill_is_kept_whole_and_not_where_the_apps_copy_from(self):
        block = held_block()
        for skill_name in held_skills():
            kept = REPOSITORY / block["place"] / skill_name / "SKILL.md"
            self.assertTrue(kept.is_file(), f"{skill_name} is held, so it is kept at {kept.relative_to(REPOSITORY)}")
            written = WRITTEN_SKILLS / skill_name
            self.assertFalse(written.exists(),
                             f"{skill_name} is held, so support/agent_guidance/skills must not have it: "
                             "both apps write every folder there into every working folder")

    def test_nothing_written_into_a_working_folder_names_a_held_skill(self):
        may_still_name = held_block().get("mayStillName", {})
        places = []
        for root_file in ROOT_FILES:
            places.append(root_file)
        for skill_folder in sorted(WRITTEN_SKILLS.iterdir()):
            if not skill_folder.is_dir():
                continue
            if skill_folder.name in may_still_name:
                continue
            for path in files_under(skill_folder):
                places.append(path)
        for skill_name in held_skills():
            for path in places:
                text = readable_text(path)
                if text is None:
                    continue
                word = first_word_said(text, skill_name)
                self.assertIsNone(word, f"{path.relative_to(REPOSITORY)} says '{word}', offering the held {skill_name}")

    def test_no_greeting_sentence_or_help_entry_names_a_held_skill(self):
        documents = []
        for contract in WORDING_CONTRACTS:
            documents.append(contract)
        if HELP.is_dir():
            for path in sorted(HELP.glob("*.json")):
                documents.append(path)
        sentences = []
        for document_path in documents:
            document = json.loads(document_path.read_text(encoding="utf-8"))
            for text in strings_in(document):
                sentences.append((document_path.relative_to(REPOSITORY).as_posix(), text))
        for skill_name in held_skills():
            for place, text in sentences:
                word = first_word_said(text, skill_name)
                self.assertIsNone(word, f"{place} says '{word}', offering the held {skill_name}: {text[:120]}")

    def test_neither_app_nor_help_nor_the_website_names_a_held_skill(self):
        skipped = []
        places = []
        for folder, endings in APP_SOURCES:
            if not folder.is_dir():
                skipped.append(str(folder.relative_to(REPOSITORY)))
                continue
            for path in files_under(folder, endings):
                places.append(path)
        if skipped:
            print("not in this checkout, so not read: " + ", ".join(skipped))
        for skill_name in held_skills():
            for path in places:
                text = readable_text(path)
                if text is None:
                    continue
                word = first_word_said(text, skill_name)
                self.assertIsNone(word, f"{path.relative_to(REPOSITORY)} says '{word}', offering the held {skill_name}")


if __name__ == "__main__":
    unittest.main()
