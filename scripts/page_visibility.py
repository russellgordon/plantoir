#!/usr/bin/env python3
"""
Whether the built website shows a page — the Python half of one rule.

**The rule is the BUILD'S rule.** A page never reaches Quartz as the teacher
typed it: `build_site.process_frontmatter` loads it with python-frontmatter
(PyYAML, YAML 1.1), resolves this section's per-section keys onto a plain
`publish:`, and writes it back out. Quartz parses THAT with js-yaml on its JSON
schema, and `patches/publish.ts` drops the page only when the value it gets is
the boolean false or the exact string "false". So:

* `publish: no` and `publish: off` HIDE the page — PyYAML reads YAML 1.1's
  nine spellings of no as the boolean and writes `false` back.
* `publish: true # why` publishes it: the comment is gone before Quartz looks.
  So does `publish: maybe`, and anything else PyYAML cannot make a boolean of.
* `publish: FALSE` hides the page and `publish: "False"` does NOT — the quotes
  keep it a string, and `publish.ts` compares strings exactly.

This module is the ONE place in the Python that knows that, for the reason
`class_pages.py` gives about the class folder: the rule used to exist in
several places and disagree. `build_site._is_draft` and
`setup_course.per_section_frontmatter` both ask here. The macOS app's
`PageVisibilityReader` is the same rule in Swift, and
`contracts/file-formats.json` -> `pageVisibility.readingCases` is the list both
of them are run against. The measured table, and what was rejected, is in
`documentation/08-course-config-reference.md`.

Deliberately stdlib only, so `test_page_visibility.py` runs anywhere —
including the Windows machine, which has no python-frontmatter and would
otherwise report a skipped test as a pass.
"""

# YAML 1.1's nine spellings of each, as PyYAML resolves them. Case matters:
# `tRue` is not here, and PyYAML leaves it an ordinary string. Nor are `y` and
# `n`, which PyYAML deliberately does not read as booleans.
YAML_TRUE = ("true", "True", "TRUE", "yes", "Yes", "YES", "on", "On", "ON")
YAML_FALSE = ("false", "False", "FALSE", "no", "No", "NO", "off", "Off", "OFF")

VISIBLE = "visible"
HIDDEN = "hidden"
CANNOT_TELL = "cannot tell"

# A value starting with one of these is a tag, an anchor, an alias, a block
# scalar or a flow collection. Each changes what the value IS, or runs over
# more than one line, and each is rarer than the chance of getting it wrong.
# The last three are characters YAML reserves: measured, `publish: %`,
# `publish: @x` and `` publish: `x `` each STOP THE BUILD.
_REFUSED_FIRST_CHARACTERS = ("!", "&", "*", "|", ">", "[", "{", "%", "@", "`")

# YAML's whitespace is a space and a tab and nothing else — deliberately NOT
# Python's `str.strip()`, which also strips the non-breaking space Option-Space
# types on a Mac. `publish: false<NBSP>` is the STRING "false\xa0" to the build
# and the page is published.
_YAML_SPACES = " \t"


def trim(text):
    """A value without the spaces, tabs and carriage return around it."""
    return text.replace("\r", "").strip(_YAML_SPACES)


def is_comment_line(line):
    """A line whose content is a `# note`, which YAML skips like a blank one."""
    return trim(line).startswith("#")


def read_scalar(raw_value, next_line=None):
    """
    A value written after a key's colon, read.

    Returns `(text, was_quoted)`, or None when this reader will not guess.
    `was_quoted` matters: quotes stop PyYAML resolving `no` or `false` into a
    boolean, so they change the answer.

    `next_line` is the first NON-BLANK line below the key, when the caller can
    see it: a key with nothing after the colon takes its value from there, and
    this reader does not follow it.
    """
    value = trim(raw_value)
    if value == "":
        # `publish:` on its own is null, which publishes the page — unless the
        # value is sitting indented below it, which is a value this reader
        # will not follow.
        if next_line is not None and next_line[:1] in (" ", "\t"):
            return None
        return ("", False)
    if value[0] in _REFUSED_FIRST_CHARACTERS:
        return None
    if value == "-" or value.startswith("- "):
        return None

    value = trim(_without_comment(value))
    if value == "":
        return ("", False)

    for quote in ('"', "'"):
        if value.startswith(quote):
            if len(value) < 2 or not value.endswith(quote):
                return None
            inside = value[1:-1]
            # A second quote of the same kind is either a second string or the
            # way a single-quoted string spells one quote.
            if quote in inside:
                return None
            # A backslash is an escape ONLY inside double quotes. Single
            # quotes have no escapes at all, so `publish: 'fal\se'` is the
            # string "fal\se" and the page is published — measured. Refusing
            # it here made the course installer write `false` for a page the
            # build shows.
            if quote == '"' and "\\" in inside:
                return None
            return (inside, True)

    # An unquoted value carrying its own `key: value` is a second mapping where
    # YAML expects a scalar. Measured: `publish: false: true` stops the build.
    if ": " in value or value.endswith(":"):
        return None

    return (value, False)


def publish_family_answer(raw_value, next_line=None):
    """
    What `publish:` or `publishForSection<N>:` means: VISIBLE, HIDDEN or
    CANNOT_TELL.
    """
    scalar = read_scalar(raw_value, next_line)
    if scalar is None:
        return CANNOT_TELL
    text, was_quoted = scalar
    if was_quoted:
        # A string reaches `publish.ts` as itself, and "false" is the only
        # string it holds a page back for. `"False"` is a page students see.
        return HIDDEN if text == "false" else VISIBLE
    if text in YAML_FALSE:
        return HIDDEN
    # Everything else — `true`, `maybe`, `0`, `oN`, nothing at all — is
    # published. Forgetting the flag leaves a page visible, which is the
    # kinder mistake and Quartz's own default here.
    return VISIBLE


def draft_family_answer(raw_value, next_line=None):
    """
    What `draft:` or `draftSection<N>:` means — the older spelling, with the
    OPPOSITE polarity.

    The build asks `build_site._as_bool`: a real boolean counts as itself, and
    anything else is turned into text, trimmed, lowercased and compared with
    "true". So an unquoted `yes` hides the page and a quoted `"yes"` does not,
    while `TrUe` hides it either way.
    """
    scalar = read_scalar(raw_value, next_line)
    if scalar is None:
        return CANNOT_TELL
    text, was_quoted = scalar
    if not was_quoted and text in YAML_TRUE:
        return HIDDEN
    if text.strip().lower() == "true":
        return HIDDEN
    return VISIBLE


def is_complete_on_its_own_line(raw_value):
    """
    Can this value be copied onto another key's line exactly as written?

    Anything a teacher fits on one line can: copying the characters means the
    build makes the same thing of the copy as of the original, whatever that
    turns out to be, and no reader standing between them can invert it by
    misreading it. A value that CONTINUES onto the next line cannot — the copy
    would be a key with nothing after it, and for a block scalar it is YAML the
    build cannot read at all.
    """
    value = trim(raw_value)
    if value == "":
        return False
    return not value.startswith(("|", ">"))


def _without_comment(value):
    """
    A value with its trailing `# comment` taken off.

    A `#` only starts a comment when it is outside quotes and something other
    than text comes before it: `publish: true#x` is the string "true#x", which
    was measured rather than assumed.
    """
    kept = []
    opening_quote = None
    previous = None
    for character in value:
        if opening_quote is not None:
            if character == opening_quote:
                opening_quote = None
            kept.append(character)
            previous = character
            continue
        if character in ('"', "'"):
            opening_quote = character
            kept.append(character)
            previous = character
            continue
        if character == "#" and (previous is None or previous in (" ", "\t")):
            break
        kept.append(character)
        previous = character
    return "".join(kept)
