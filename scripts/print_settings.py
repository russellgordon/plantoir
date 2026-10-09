#!/usr/bin/env python3
"""
What a printed handout says in its corners, and the words its page prints (#454).

The course's settings say where the school name and course code go and which
blanks a student fills in (`print_*` in contracts/file-formats.json ->
courseConfigKeys); `contracts/shared-rules.json` -> `printablePages` holds the
words and the rules. Every build writes the result into the section's Quartz
copy as `quartz/plantoir_print.json`, which the Print button's component reads
when the site is built - so a changed setting reaches the next preview without
anything else being copied.

Composed here, in Python, rather than in the page's own code because the
corners are a function of the COURSE's settings, which the site cannot read,
and because a rule with cases is cheapest to test where both platforms can run
it (stdlib only; Windows runs it too).
"""

import json
from pathlib import Path

import contracts

CONTRACT_FILE = "shared-rules"
OUTPUT_NAME = "plantoir_print.json"

PLACES = ("header_left", "footer_left", "none")
BLANK_ORDER = ("name", "date", "class_number")
BLANK_WORD_KEYS = {"name": "blankName", "date": "blankDate", "class_number": "blankClassNumber"}


def _section(*keys):
    return contracts.section(CONTRACT_FILE, "printablePages", *keys)


def _place(value, default: str) -> str:
    return value if isinstance(value, str) and value in PLACES else default


def _blanks(settings: dict) -> list:
    """The blanks to print, in the one order, each once; absent means Name and Date."""
    if "print_blanks" not in settings or settings.get("print_blanks") is None:
        chosen = ["name", "date"]
    else:
        raw = settings.get("print_blanks")
        chosen = raw if isinstance(raw, list) else []
    ordered = []
    for blank in BLANK_ORDER:
        if blank in chosen:
            ordered.append(blank)
    return ordered


def compose(settings: dict, displayed_code: str) -> dict:
    """
    The four corners, each one line of text. bottomRight is always the token
    "pageLabel": the page's own code fills it per page, because questions and
    answers are counted separately.
    """
    words = _section("words")
    corners = _section("corners")
    school = str(settings.get("print_school_name") or "").strip()
    code = str(displayed_code or "").strip().upper()
    school_at = _place(settings.get("print_school_name_at"), "header_left")
    code_at = _place(settings.get("print_course_code_at"), "footer_left")

    slots = {"header_left": [], "footer_left": []}
    if school and school_at in slots:
        slots[school_at].append(school)
    if code and code_at in slots:
        slots[code_at].append(code)

    lines = corners["blankLines"]
    blank_texts = []
    for blank in _blanks(settings):
        blank_texts.append(words[BLANK_WORD_KEYS[blank]] + " " + "_" * int(lines[blank]))

    return {
        "topLeft": " · ".join(slots["header_left"]),
        "topRight": corners["blankJoin"].join(blank_texts),
        "bottomLeft": " · ".join(slots["footer_left"]),
        "bottomRight": "pageLabel",
    }


def page_label(part: str, n: int, total: int) -> str:
    """'Page 1 of 3' over the questions, 'Answers 1 of 2' over the answers."""
    words = _section("words")
    template = words["answersPageLabel"] if part == "answers" else words["pageLabel"]
    return template.replace("{n}", str(n)).replace("{total}", str(total))


def site_settings(settings: dict, displayed_code: str) -> dict:
    """Everything the page's print code reads, from the contract and the course."""
    words = {}
    for key, value in _section("words").items():
        if key in ("where", "why"):
            continue
        words[key] = value
    callouts = _section("answerCallouts")
    return {
        "corners": compose(settings, displayed_code),
        "words": words,
        "answerKinds": list(callouts["answerKinds"]),
        "answerTitleWords": list(callouts["answerTitleWords"]),
        "curriculumHeadings": list(_section("curriculumConnection", "headingWords")),
        "defaultMode": _section("modes", "default"),
    }


def write(output_dir, settings: dict, displayed_code: str) -> Path:
    """Write quartz/plantoir_print.json for this build; same input, same bytes."""
    path = Path(output_dir) / "quartz" / OUTPUT_NAME
    text = json.dumps(site_settings(settings, displayed_code), ensure_ascii=False,
                      indent=2, sort_keys=True) + "\n"
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        if path.read_text(encoding="utf-8") == text:
            return path
    except OSError:
        pass
    path.write_text(text, encoding="utf-8")
    return path
