#!/usr/bin/env python3
"""
A course's name, cleaned where it is read (GitHub #780).

`course_config.json` -> `course_name` is a JSON string, and JSON can carry any
code point as `\\uXXXX`: a NUL, a line break, an escape, a right-to-left
override. No such character is ever meant in a course's name, and each one
does harm somewhere it is shown: a NUL cuts a label short, a line break splits
one line into two, ESC starts a terminal escape sequence, and U+202E makes the
name read differently from what is stored.

The rule is `contracts/shared-rules.json` -> `courseNameCharacters`, and the
macOS app (`OneLineText` and `CourseName` in Swift) and the Windows app apply
the same one. It works on code points, which is what a Python `str` holds, so
an emoji or an accented letter is never split:

  * C0 controls U+0000 to U+001F (tab and line breaks included), DEL U+007F,
    the C1 controls U+0080 to U+009F and the line and paragraph separators
    U+2028 and U+2029 each become ONE space;
  * the bidirectional embeddings, overrides and isolates, U+202A to U+202E and
    U+2066 to U+2069, are removed;
  * everything else is kept on purpose: the zero-width joiner and non-joiner,
    the left-to-right, right-to-left and Arabic letter marks, the zero-width
    space, the soft hyphen, combining marks, every non-breaking space.

Nothing is trimmed and nothing is collapsed here; a caller that wants the ends
trimmed (`build_site.computed_landing_title`) trims after cleaning.

The ranges are written out in code rather than read from the contract at run
time, the same as in Swift, and `scripts/test_course_names.py` pins them to
the contract, so a change to one without the other fails a test.
"""


def is_spaced_out(code_point: int) -> bool:
    """Whether the character at `code_point` becomes one space."""
    if code_point <= 0x1F:
        return True
    if code_point == 0x7F:
        return True
    if 0x80 <= code_point <= 0x9F:
        return True
    if code_point == 0x2028 or code_point == 0x2029:
        return True
    return False


def is_removed(code_point: int) -> bool:
    """Whether the character at `code_point` is taken out altogether."""
    if 0x202A <= code_point <= 0x202E:
        return True
    if 0x2066 <= code_point <= 0x2069:
        return True
    return False


def cleaned(name: str) -> str:
    """`name` with the rule applied: no trimming, no collapsing."""
    kept = []
    for character in name:
        code_point = ord(character)
        if is_removed(code_point):
            continue
        if is_spaced_out(code_point):
            kept.append(" ")
        else:
            kept.append(character)
    return "".join(kept)
