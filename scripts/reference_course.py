#!/usr/bin/env python3
"""
Is this course kept for reference — and therefore never deployed?

A REFERENCE COURSE is last year's course, or a course full of example content,
kept in this year's sidebar to be read. It may be opened in Obsidian and it may
be previewed. It is never deployed, and this module is the one place the shared
toolchain answers that question, so `deploy.py`, the launchers and anything
Windows runs natively all answer it the same way.

**Where the rule lives.** `contracts/shared-rules.json` -> `referenceCourses`,
read through `contracts.py`. The sentence a teacher reads is in there too,
because the Python has to SAY it and `contracts.py` can read that file but not
`assist-wording.json`, where the app's own copy lives. A test on each side pins
the two together.

**A missing or malformed config reads as NOT a reference course.** That is the
one place this errs deliberately toward allowing, and the reason is that a
course nobody can open must not become undeployable by accident. It is safe
because the marker is not the only defence: a course kept for reference is also
left with nowhere to deploy to, and its site markers are renamed aside, so the
refusals every shipped version already has catch it too. The HOST-side check in
`deploy.sh` and `deploy.ps1` is the one that fails CLOSED, because that one
runs before anything else and a file it cannot read is a different fact from a
file that says no.
"""

import json
import sys
from pathlib import Path

import contracts

# The key in `course_config.json`. ABSENT MEANS FALSE.
MARKER_KEY = "kept_for_reference"

# The school year it was taught in, as the calendar year it STARTED in.
SCHOOL_YEAR_KEY = "reference_school_year"

# The sentence, carried here as well as in the contract.
#
# Not a second implementation: `refusal_sentence` reads the contract and falls
# back to this only when the contract cannot be read at all. A missing contract
# must still REFUSE — falling through to a deploy because a file was missing is
# the failure this whole piece exists to prevent — and it must refuse in words
# a teacher can act on rather than in a stack trace.
# `test_reference_course.py` asserts this string and the contract's are the
# same, so the copy cannot drift.
FALLBACK_REFUSAL = (
    "{course} is kept for reference, so it is never deployed. "
    "Deploy the course you are teaching instead."
)

_CONFIG_NAME = "course_config.json"


def _config(course_dir) -> dict:
    """
    The course's settings, or an empty dict when there are none to read.

    Read by EXACT NAME, never by glob: a real working folder was measured
    holding `course_config.backup.json` and a Finder duplicate called
    `course_config copy.json` beside the real one.
    """
    path = Path(course_dir) / _CONFIG_NAME
    try:
        with open(path, "r", encoding="utf-8") as handle:
            loaded = json.load(handle)
    except (OSError, ValueError):
        return {}
    if not isinstance(loaded, dict):
        return {}
    return loaded


def is_reference(course_dir) -> bool:
    """True when this course folder is kept for reference."""
    return _config(course_dir).get(MARKER_KEY) is True


def school_year(course_dir):
    """
    The school year it was taught in, as the starting calendar year, or None.

    Anything that is not a whole number is None — which reads as "Other"
    everywhere a year is shown.
    """
    stored = _config(course_dir).get(SCHOOL_YEAR_KEY)
    if isinstance(stored, bool) or not isinstance(stored, int):
        return None
    return stored


def display_code(course_dir) -> str:
    """
    The code a TEACHER reads — `ICS3U`, not the folder name `ICS3U-2025`.

    The folder and `course_code` disagree on purpose for a reference course and
    nowhere else. Falls back to the folder name when the config says nothing,
    because a sentence naming nothing at all is worse than one naming a folder.
    """
    recorded = _config(course_dir).get("course_code")
    if isinstance(recorded, str) and recorded.strip():
        return recorded.strip()
    return Path(course_dir).name


def refusal_sentence(course: str) -> str:
    """What a teacher is told when they try to deploy one."""
    template = contracts.section(
        "shared-rules", "referenceCourses", "refusal", "sentence", optional=True
    )
    if not isinstance(template, str) or "{course}" not in template:
        template = FALLBACK_REFUSAL
    return template.replace("{course}", course)


def _main(argv) -> int:
    """
    `python3 reference_course.py <course folder>` — for a launcher that would
    rather ask than reimplement the read.

    Prints the refusal and exits 1 when the course is kept for reference, and
    exits 0 silently otherwise. Exit 1 rather than a code of its own: `deploy.sh`
    states that its only exits are 0, 1 and 3, and 3 means "a question nobody was
    there to answer" and nothing else. What tells this refusal apart from any
    other failure is its OUTPUT, which `app-rules.json` -> `failureExplanations`
    turns back into a sentence for the teacher.
    """
    if len(argv) != 2:
        print("usage: reference_course.py <course folder>", file=sys.stderr)
        return 2
    course_dir = Path(argv[1])
    if not is_reference(course_dir):
        return 0
    print(refusal_sentence(display_code(course_dir)))
    return 1


if __name__ == "__main__":
    sys.exit(_main(sys.argv))
