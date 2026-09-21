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

**The marker is read as TEXT, and that is deliberate.** Three implementations
have to agree on this question — this module, `deploy.sh` and `deploy.ps1` —
and two of them are plain shell with no JSON parser. So the rule is one regular
expression all three can run, over the whole file as a single string:

    "kept_for_reference"  :  true

with any whitespace (newlines included) around the colon, and `true` in any
case. `contracts/shared-rules.json` -> `referenceCourses.markerAgreement`
carries the pattern in all three dialects and the table of inputs all three are
asserted to agree on; `test_reference_course.py` runs it.

**Every ambiguity is resolved by REFUSING**, because the two directions are not
comparable: a live course wrongly refused is loud and harmless, while a
reference course wrongly deployed reports success. So the text rule refuses a
marker nested inside another object, and it refuses the marker's own text
appearing inside a string VALUE — plain shell cannot tell those from the real
key, and one answer shared by three implementations beats three answers that
are each right about something.

**Two things are deliberately NOT a reference course**, and both are decided by
what the APPS do rather than by caution: a marker whose value is the STRING
"true", and one whose value is `1`. Both read as false in
`CourseConfiguration` on either platform, so those courses appear in the
sidebar as ordinary courses and deploy from the button. A launcher that refused
them would disagree with the app about the same file, which protects nothing
and strands a teacher between two answers. `true` in any case, unquoted, is the
whole rule.

**A malformed config with no marker in it is NOT a reference course**, which is
the one place this still errs toward allowing: a course nobody can open must
not become undeployable by accident. A malformed config that DOES carry the
marker is refused, because there is nothing accidental about it.
"""

import json
import re
import sys
from pathlib import Path

import contracts

# The key in `course_config.json`. ABSENT MEANS FALSE.
MARKER_KEY = "kept_for_reference"

# The one rule all three implementations run, in this dialect.
#
# `\s` matches a newline here, in .NET, and in a POSIX `[[:space:]]` class
# once the launchers have flattened the file to one line with `tr`. That
# flattening is not a detail: `grep` works a LINE AT A TIME, so without it a
# config whose key and colon sit on different lines walked straight past the
# launcher's check while this module called it a reference course — and the
# folder publish, which never enters the container, went through at exit 0
# saying "Published: 1 file(s) updated."
MARKER_PATTERN = r'"kept_for_reference"\s*:\s*[Tt][Rr][Uu][Ee]'

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


def _config_text(course_dir) -> str:
    """
    The settings file as text, or "" when there is none to read.

    Read by EXACT NAME, never by glob: a real working folder was measured
    holding `course_config.backup.json` and a Finder duplicate called
    `course_config copy.json` beside the real one.

    `utf-8-sig` rather than `utf-8`, so a byte-order mark at the head of the
    file is swallowed rather than making the whole config unreadable. The
    launchers' `grep` never noticed a BOM; this used to, and that was a
    disagreement between the three readers for no gain.
    """
    path = Path(course_dir) / _CONFIG_NAME
    try:
        with open(path, "r", encoding="utf-8-sig") as handle:
            return handle.read()
    except OSError:
        return ""


def _config(course_dir) -> dict:
    """The course's settings parsed, or an empty dict when they will not parse."""
    try:
        loaded = json.loads(_config_text(course_dir))
    except ValueError:
        return {}
    if not isinstance(loaded, dict):
        return {}
    return loaded


def is_reference(course_dir) -> bool:
    """
    True when this course folder is kept for reference.

    Asked of the TEXT, not of the parsed settings, so that this module, the
    shell and PowerShell all answer the same question the same way — see the
    module docstring. The parsed form is consulted as well, for the one shape
    text cannot see: a key spelled with JSON escapes.
    """
    text = _config_text(course_dir)
    if re.search(MARKER_PATTERN, text) is not None:
        return True
    return _config(course_dir).get(MARKER_KEY) is True


def cannot_tell(course_dir) -> bool:
    """
    True when a settings file is THERE and cannot be read.

    "Cannot tell" is not "no", and the two must not be collapsed: a file that
    exists and refuses to open is exactly the case where refusing costs a
    teacher one puzzled moment and allowing costs them a frozen course on the
    web. The launchers fail closed on it in their own words; this is the same
    question, so `deploy.py` run directly gives the same answer.

    A MISSING file is not this: the launcher's own course-folder check answers
    that one, in words a teacher can act on.
    """
    path = Path(course_dir) / _CONFIG_NAME
    if not path.is_file():
        return False
    try:
        with open(path, "r", encoding="utf-8-sig") as handle:
            handle.read()
    except OSError:
        return True
    return False


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
