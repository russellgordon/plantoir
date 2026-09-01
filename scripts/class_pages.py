#!/usr/bin/env python3
"""
What a course calls the first half of a class page's name.

Class pages are named "Unit 2, Day 3". Until 2026-09-01 that first word was not
a preference but a structural assumption: the regex that decides whether a page
is a class page, the page the "next class" button writes, and the curriculum
map's idea of what a course TEACHES all had it built in. Teachers who organise
by "Module" or "Thread" could rename the pages in Obsidian and quietly lose
every feature that recognises a class page — and the coverage map does not fail
when it finds none, it falls back to counting every published page, which is a
wrong map that reports success.

A course records its word in `course_config.json` as `unit_word`. **ABSENT
means "Unit"**, which is what every course made before this key existed says,
and what a course made from scratch still says unless the teacher chooses
otherwise.

**"Day" is deliberately fixed.** A teacher who says "Thread" almost certainly
still says "Day 3", and a second configurable word would double the migration
for something nobody asked for.

**This module holds the rule; `build_site.py` holds this build's answer.** The
split matters: the rule is shared with `setup_course.py`, which uses it to
rewrite a payload on the way into a new course, and that runs long before any
build.
"""

import re

DEFAULT_UNIT_WORD = "Unit"


def word_from_config(config: dict) -> str:
    """
    A course's word, defaulting the way an absent key must.

    An absent key and an empty string both mean "Unit". They are NOT
    distinguished the way `graded_folders` distinguishes absent from empty:
    there is no sensible reading of "the teacher cleared the word", and a
    course whose class pages had no name at all could not be built.
    """
    return str(config.get("unit_word") or DEFAULT_UNIT_WORD).strip() or DEFAULT_UNIT_WORD


def class_page_pattern(word: str = DEFAULT_UNIT_WORD) -> str:
    """
    The regex a class page's name must match: "<word> 2, Day 3".

    `re.escape` is not decoration — the word comes from a teacher's own
    configuration, and one containing "(" or "+" would otherwise quietly become
    a different pattern, or fail to compile in the middle of a build.
    """
    return r"^" + re.escape(_cleaned(word)) + r"\s+(\d+),\s*Day\s+(\d+)$"


def first_class_pattern(word: str = DEFAULT_UNIT_WORD) -> str:
    """The regex the FIRST class of the year matches: "<word> 1, Day 1"."""
    return r"^" + re.escape(_cleaned(word)) + r"\s+0*1,\s*Day\s+0*1$"


def rewritten(text: str, word: str) -> str:
    """
    Example-content text with "Unit" replaced wherever it names a unit.

    Matches "Unit" only when a number follows, which is what separates a unit
    reference from the ordinary English word. That covers the page form
    ("Unit 2, Day 3" — in a title, in a wikilink, in prose) and the bare form
    ("by the end of Unit 3"), which around 574 payload files use and which
    would otherwise leave a Module course talking about Units.

    **This is only ever run over content Plantoir itself ships, on the way into
    a brand-new course.** It is never let near a teacher's own writing, where
    "Unit 3 of the textbook" would be a false positive nobody could undo.
    """
    cleaned = _cleaned(word)
    if cleaned == DEFAULT_UNIT_WORD:
        return text
    # A function as the replacement, not a string: a word containing a
    # backslash would otherwise be read as an escape and silently mangled.
    return re.sub(r"\bUnit(?=\s+\d)", lambda match: cleaned, text)


def renamed(name: str, word: str) -> str:
    """A payload file or page name with its leading "Unit" replaced."""
    cleaned = _cleaned(word)
    if cleaned == DEFAULT_UNIT_WORD:
        return name
    return re.sub(r"^Unit(?=\s+\d)", lambda match: cleaned, name)


def _cleaned(word) -> str:
    return str(word or "").strip() or DEFAULT_UNIT_WORD
