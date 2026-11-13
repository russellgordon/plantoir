"""The word check: what a teacher reads in Help never names the machinery,
never sells, never mixes up publish and deploy, never types a count or quotes
a long run of words by hand.

One module, so that #840's P6 can make the site import it too. Until then two
of its lists are COPIES, each naming its source:
- `MACHINERY` is `website/build.py` -> `MACHINERY`;
- `typed_count_problems` follows `website/build.py` -> `typed_count_problems`.

It runs on what a reader reads: headings, body text, alt text, captions,
placeholder labels, a page's title, question and description. Code spans,
fenced blocks and the text of tokens are never read (they are blanked first).
"""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any, Dict, List, Pattern

from .problems import HelpError, Problems

# COPY of website/build.py -> MACHINERY (2026-11-13, origin/dev 0253c230e).
MACHINERY = re.compile(
    r"\b(toolchain|scripts?|docker|colima|containers?|launchd|launchagents?|mcp|"
    r"models?|sparkle|appcast|feeds?|pyodide|webassembly|wasm|workers?)\b",
    re.IGNORECASE,
)

# COPY of website/build.py -> TYPED_COUNT_REACH and COUNT_NOUNS.
TYPED_COUNT_REACH = 4
COUNT_NOUNS = re.compile(r"^(course|courses|code|codes)$", re.IGNORECASE)

LONG_SENTENCE_WORDS = 25
QUOTED_RUN_WORDS = 3

# Help's own publish rule (plan review H1). PUBLISH marks a page for students;
# DEPLOY sends a section's site somewhere. So "publish" followed within five
# words by a destination, or "deploy" followed within five words by "page",
# is the wrong verb. Only the words AFTER the verb count, within one sentence:
# "publish the pages, then deploy" is right and must pass.
PUBLISH_WORD = re.compile(r"^publish", re.IGNORECASE)
DEPLOY_WORD = re.compile(r"^deploy", re.IGNORECASE)
PUBLISH_DESTINATION = re.compile(
    r"\b(sites?|websites?|online|netlify|cloudflare|github pages|(?:a|the|your) folder|"
    r"(?:to|onto) (?:the |a |your |each |this |that )?sections?)\b",
    re.IGNORECASE,
)
DEPLOY_A_PAGE = re.compile(r"\bpages?\b", re.IGNORECASE)
PAGES_PRODUCTS = re.compile(r"\b(?:github|cloudflare) pages\b", re.IGNORECASE)
VERB_REACH = 5

WORD = re.compile(r"[A-Za-z0-9(][A-Za-z0-9,.'’()-]*")


def blank(text: str, start: int, end: int) -> str:
    return text[:start] + (" " * (end - start)) + text[end:]


def blank_phrase(text: str, phrase: str) -> str:
    position: int = text.find(phrase)
    while position >= 0:
        text = blank(text, position, position + len(phrase))
        position = text.find(phrase, position + len(phrase))
    return text


def ends_sentence(word: str) -> bool:
    return re.search(r"[.!?:;]\)?$", word) is not None and re.fullmatch(r"\d+(\.\d+)+", word) is None


class WordRules:
    """The lists the check reads, loaded once per build."""

    def __init__(self, forbidden: List[str], tone: Dict[str, Any]) -> None:
        self.forbidden_patterns: List[Pattern[str]] = []
        for word in forbidden:
            # As the app's UserFacingLabelWordsTests matches: whole word, any case.
            self.forbidden_patterns.append(
                re.compile(r"(?<![A-Za-z0-9_])" + re.escape(word) + r"(?![A-Za-z0-9_])", re.IGNORECASE)
            )
        self.banned: List[Dict[str, Any]] = []
        for entry in tone.get("banned", []):
            self.banned.append({"pattern": re.compile(entry["pattern"], re.IGNORECASE), "why": entry["why"]})
        self.exemptions: List[Dict[str, Any]] = list(tone.get("exemptions", []))
        self.quote_exemptions: List[Dict[str, Any]] = list(tone.get("quotes", []))
        # Longest first, so "3D models" is blanked before "3D model".
        self.exemptions.sort(key=lambda entry: len(entry["phrase"]), reverse=True)

    @staticmethod
    def load(repo: Path, help_dir: Path) -> "WordRules":
        rules_path: Path = repo / "contracts" / "shared-rules.json"
        try:
            with rules_path.open(encoding="utf-8") as handle:
                shared = json.load(handle)
            forbidden: List[str] = list(shared["userFacingLabelWords"]["forbidden"])
        except (OSError, KeyError, ValueError) as error:
            raise HelpError("cannot read userFacingLabelWords.forbidden from " + str(rules_path) + ": " + str(error))
        tone_path: Path = help_dir / "tone.json"
        try:
            with tone_path.open(encoding="utf-8") as handle:
                tone = json.load(handle)
        except (OSError, ValueError) as error:
            raise HelpError("cannot read " + str(tone_path) + ": " + str(error))
        return WordRules(forbidden, tone)

    def _exempt(self, page_id: str, text: str) -> str:
        for entry in self.exemptions:
            if page_id in entry.get("pages", []):
                text = blank_phrase(text, entry["phrase"])
        return text

    def check(self, page_id: str, file: str, line: int, text: str, problems: Problems) -> None:
        """Every rule on one piece of readable text (tokens and code already blanked)."""
        readable: str = self._exempt(page_id, text)
        for pattern in self.forbidden_patterns:
            found = pattern.search(readable)
            if found is not None:
                problems.fail(file, line, "names the machinery (" + repr(found.group(0)) + "); CLAUDE.md rule 1")
        for found in MACHINERY.finditer(readable):
            problems.fail(file, line, "names the machinery (" + repr(found.group(0)) + "); the site's MACHINERY list")
        for entry in self.banned:
            found = entry["pattern"].search(readable)
            if found is not None:
                problems.fail(file, line, "tone: " + repr(found.group(0)) + " (" + entry["why"] + ")")
        for message in publish_deploy_problems(readable):
            problems.fail(file, line, message)
        for message in self.quoted_run_problems(page_id, readable):
            problems.fail(file, line, message)
        for message in typed_count_problems(readable):
            problems.fail(file, line, message)
        for message in long_sentence_notes(readable):
            problems.warn(file, line, message)

    def quoted_run_problems(self, page_id: str, text: str) -> List[str]:
        for entry in self.quote_exemptions:
            if page_id in entry.get("pages", []):
                text = blank_phrase(text, entry["phrase"])
        messages: List[str] = []
        for found in re.finditer(r"\"([^\"\n]+)\"|“([^”\n]+)”", text):
            inside: str = found.group(1) if found.group(1) is not None else found.group(2)
            if len(WORD.findall(inside)) > QUOTED_RUN_WORDS:
                messages.append(
                    "quotes a run of more than three words by hand (" + repr(inside.strip()) + "): "
                    "a sentence the app shows is a {{say:}} token; anything else is described, "
                    "or exempted in help/tone.json -> quotes with a reason"
                )
        return messages


def _sentences(text: str) -> List[List[str]]:
    sentences: List[List[str]] = []
    current: List[str] = []
    for word in WORD.findall(text):
        current.append(word)
        if ends_sentence(word):
            sentences.append(current)
            current = []
    if len(current) > 0:
        sentences.append(current)
    return sentences


def publish_deploy_problems(text: str) -> List[str]:
    messages: List[str] = []
    for sentence in _sentences(text):
        for index in range(len(sentence)):
            word: str = sentence[index].strip(".,;:()")
            following: str = " ".join(sentence[index + 1:index + 1 + VERB_REACH])
            if PUBLISH_WORD.match(word) is not None:
                found = PUBLISH_DESTINATION.search(following)
                if found is not None:
                    messages.append(
                        repr(word) + " is followed by " + repr(found.group(0)) + ": PUBLISH marks a page for "
                        "students; sending a site somewhere is DEPLOY"
                    )
            elif DEPLOY_WORD.match(word) is not None:
                # "GitHub Pages" and "Cloudflare Pages" are destinations, not pages.
                destinations_removed: str = PAGES_PRODUCTS.sub(" ", following)
                found = DEPLOY_A_PAGE.search(destinations_removed)
                if found is not None:
                    messages.append(
                        repr(word) + " is followed by " + repr(found.group(0)) + ": a page is PUBLISHED; "
                        "DEPLOY sends a section's whole site"
                    )
    return messages


def typed_count_problems(text: str) -> List[str]:
    """A digit written near "course" or "code" is a count somebody typed.
    Follows website/build.py -> typed_count_problems."""
    # A year or a school year ("2025-26") is a date, not a count.
    text = re.sub(r"\b(?:19|20)\d\d(?:[–-]\d\d)?\b", lambda match: " " * len(match.group(0)), text)
    words = list(WORD.finditer(text))
    messages: List[str] = []
    for index in range(len(words)):
        word = words[index]
        token: str = word.group(0).rstrip(".,")
        if re.fullmatch(r"\d[\d,]*", token) is None:
            continue
        neighbours: List[str] = []
        if not ends_sentence(word.group(0)):
            for step in range(1, TYPED_COUNT_REACH + 1):
                if index + step >= len(words):
                    break
                neighbours.append(words[index + step].group(0))
                if ends_sentence(words[index + step].group(0)):
                    break
        for step in range(1, TYPED_COUNT_REACH + 1):
            if index - step < 0 or ends_sentence(words[index - step].group(0)):
                break
            neighbours.append(words[index - step].group(0))
        for neighbour in neighbours:
            if COUNT_NOUNS.match(neighbour.rstrip(".,")) is not None:
                messages.append(
                    "types a count (" + repr(token) + " near " + repr(neighbour) + "): counts come from "
                    "support/, written {{count:ready_made_ontario}} and the like (helpbook/counts.py)"
                )
                break
    return messages


def long_sentence_notes(text: str) -> List[str]:
    notes: List[str] = []
    for sentence in _sentences(text):
        if len(sentence) > LONG_SENTENCE_WORDS:
            notes.append(
                "a sentence of " + str(len(sentence)) + " words (over " + str(LONG_SENTENCE_WORDS) + "): "
                + " ".join(sentence[:6]) + " ..."
            )
    return notes
