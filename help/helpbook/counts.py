"""Numbers Help states, counted from `support/` at every build.

COPIED from `website/build.py` -> `site_counts` (and `number_in_words`,
`about`), because build.py uses Python 3.10 syntax and cannot be imported by
Xcode's Python 3.9. When #840's P6 moves the site onto Help's modules, the site
imports this copy and its own goes. Until then a change to one is made to both.

A page writes `{{count:<name>}}` with one of the names `site_counts` returns;
a count typed by hand is refused (words.typed_count_problems).
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Dict, Set

NUMBER_WORDS = ["no", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]


def number_in_words(count: int) -> str:
    """One to nine in words, the rest in digits."""
    if 0 <= count < len(NUMBER_WORDS):
        return NUMBER_WORDS[count]
    return "{:,}".format(count)


def about(count: int) -> str:
    """The nearest hundred, with a thousands comma: 1,892 reads "1,900"."""
    rounded: int = int(round(count / 100.0)) * 100
    return "{:,}".format(rounded)


def _read_json(path: Path) -> dict:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def site_counts(support: Path) -> Dict[str, str]:
    """A ready-made course is a payload folder with a `manifest.json`; it is
    Ontario's unless its manifest names another `jurisdiction`. Every other
    code in Ontario's catalogue gets a starting outline instead."""
    ontario_payloads: Set[str] = set()
    other_payloads: Dict[str, int] = {}
    for manifest_path in sorted((support / "example_content").glob("*/manifest.json")):
        manifest = _read_json(manifest_path)
        jurisdiction: str = str(manifest.get("jurisdiction", "ON")).upper()
        if jurisdiction == "ON":
            ontario_payloads.add(manifest_path.parent.name)
        else:
            other_payloads[jurisdiction] = other_payloads.get(jurisdiction, 0) + 1

    catalogue_path: Path = support / "ontario_secondary_courses.json"
    outline_codes: int = 0
    if catalogue_path.exists():
        catalogue = _read_json(catalogue_path)
        for code in catalogue:
            if code not in ontario_payloads:
                outline_codes += 1

    british_columbia: int = other_payloads.get("BC", 0)
    other_sentence: str = ""
    if british_columbia == 1:
        other_sentence = ", and one British Columbia course"
    elif british_columbia > 1:
        other_sentence = ", and " + number_in_words(british_columbia) + " British Columbia courses"

    return {
        "ready_made_ontario": str(len(ontario_payloads)),
        "ready_made_bc": str(british_columbia),
        "ready_made_other_sentence": other_sentence,
        "skeleton_codes": about(outline_codes),
        "skeleton_codes_exact": str(outline_codes),
    }
