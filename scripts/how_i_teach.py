#!/usr/bin/env python3
"""
The teacher's "How I Teach" page, and the rule that keeps it off the website.

GitHub #209, decided by Russell on 2026-09-26: each course may have ONE page,
`How I Teach.md` at the top of the course folder, that says how the course is
taught. The teacher writes it in Obsidian, or an outside assistant drafts it
from the course's own pages and saves it once the teacher agrees; both outside
doors ask the session to read it. It is NEVER on the website. The whole rule,
with what was measured and what was rejected, is
`contracts/shared-rules.json` -> `howITeachPage`.

**The location is the guarantee, not `publish: false`.** Measured before this
module existed: a page with this name at the top of a course, and at the top of
a section folder, was discovered, copied to the top of the site's content and
published — a page typed in Obsidian carries no frontmatter, and a later
`publishForSection<N>: true` beats `publish: false` anyway
(`file-formats.json` -> `pageVisibility`). So `build_site.py` asks here at four
points, every build: discovery, the preflight write-back, the lists the copy
loops read, and a final sweep of the merged content.

Deliberately stdlib only, so `test_how_i_teach.py` runs on Windows' Python
suite, which has no python-frontmatter.
"""
import json
import unicodedata
from pathlib import Path

import contracts

# The fallback is only for a contract that cannot be read at all — the build
# would already have stopped for other reasons by then — and a test pins it to
# the contract's own value, so the two cannot drift apart quietly.
_FALLBACK_FILE_NAME = "How I Teach.md"
_FALLBACK_KEPT_OFF_LINE = (
    "🔒 Kept your How I Teach page off the website — it is for you and your "
    "assistant. If you meant students to see it, give it another name."
)
_FALLBACK_LOOK_ALIKE_LINE = (
    "📝 “{name}” will be on the website like any other page. Only a page named "
    "exactly “How I Teach”, at the top of the course folder, is kept off it."
)
_FALLBACK_MARKER_PREFIX = "PLANTOIR_KEPT_OFF:"


def _rule(*keys, fallback):
    """One value out of `shared-rules.json` -> `howITeachPage`."""
    try:
        value = contracts.section("shared-rules", "howITeachPage", *keys)
    except Exception:
        return fallback
    if isinstance(fallback, str) and not isinstance(value, str):
        return fallback
    return value


def file_name() -> str:
    """The page's name, as the contract spells it."""
    return _rule("fileName", fallback=_FALLBACK_FILE_NAME)


def folded(name: str) -> str:
    """
    A name as the rule compares it: NFC, then ONLY A-Z folded to a-z.

    Not `str.casefold()`. Python's case folding and Swift's `lowercased()`
    disagree on a handful of letters, and this rule has two implementations
    that must never disagree about a name. The page's name is ASCII, so
    folding only ASCII costs nothing and makes the two provably the same
    (`howITeachPage.matching`).
    """
    normalised = unicodedata.normalize("NFC", name)
    letters = []
    for character in normalised:
        if "A" <= character <= "Z":
            letters.append(chr(ord(character) + 32))
        else:
            letters.append(character)
    return "".join(letters)


def is_the_how_i_teach_page(name: str) -> bool:
    """Whether one file NAME (not a path) is the page. Nothing is trimmed."""
    return folded(name) == folded(file_name())


def looks_like_the_page(name: str) -> bool:
    """
    A `.md` name that starts like the page and is NOT it — "How I Teach 1.md",
    "How I teach ICS4U.md". Such a page is published like any other, and the
    build says so, because a teacher who meant it to be private is otherwise
    told nothing.
    """
    if is_the_how_i_teach_page(name):
        return False
    lowered = folded(name)
    if not lowered.endswith(".md"):
        return False
    stem = folded(file_name())
    if stem.endswith(".md"):
        stem = stem[:-3]
    return lowered.startswith(stem)


def is_reserved_place(relative_path: str) -> bool:
    """
    Whether a path relative to the COURSE folder is one the build keeps off
    the site: the page at the top of the course, or at the top of a section
    folder (`section<N>/`), which the build copies to the same place.
    """
    parts = relative_path.replace("\\", "/").split("/")
    if len(parts) == 1:
        return is_the_how_i_teach_page(parts[0])
    if len(parts) == 2:
        folder = parts[0]
        # ASCII digits only, as the app checks — `str.isdigit` would also
        # accept other scripts' digits, which Swift's check does not.
        digits = folder[len("section"):]
        is_a_section = (folder.startswith("section") and len(digits) > 0
                        and all("0" <= character <= "9" for character in digits))
        return is_a_section and is_the_how_i_teach_page(parts[1])
    return False


def keep_off_the_site(names) -> tuple:
    """(kept, dropped): a copy list with the page taken out, and what was."""
    kept = []
    dropped = []
    for name in names or []:
        if is_the_how_i_teach_page(str(name)):
            dropped.append(name)
        else:
            kept.append(name)
    return kept, dropped


def pages_at_the_top(folder: Path) -> list:
    """The page's file(s) directly inside one folder, by their real names."""
    found = []
    try:
        for entry in sorted(folder.iterdir()):
            if entry.is_file() and is_the_how_i_teach_page(entry.name):
                found.append(entry.name)
    except OSError:
        pass
    return found


def look_alikes_at_the_top(folder: Path) -> list:
    """Pages directly inside one folder whose names look like the page."""
    found = []
    try:
        for entry in sorted(folder.iterdir()):
            if entry.is_file() and looks_like_the_page(entry.name):
                found.append(entry.name)
    except OSError:
        pass
    return found


def remove_from_content_root(content_root: Path) -> list:
    """
    The final sweep: delete any file with the page's name from the TOP of the
    merged content, and return the names removed.

    The top level only, never recursively — a page with this name inside a
    folder is an ordinary page (`nameCases`), and the merged content is the
    build's own copy, rebuilt from scratch seconds earlier, never the
    teacher's folder.
    """
    removed = []
    for name in pages_at_the_top(content_root):
        try:
            (content_root / name).unlink()
            removed.append(name)
        except OSError:
            pass
    return removed


def kept_off_the_website_line() -> str:
    return _rule("keptOffTheWebsiteLine", fallback=_FALLBACK_KEPT_OFF_LINE)


def look_alike_line(name: str) -> str:
    stem = name[:-3] if folded(name).endswith(".md") else name
    return _rule("lookAlikeLine", fallback=_FALLBACK_LOOK_ALIKE_LINE).replace("{name}", stem)


def marker_prefix() -> str:
    return _rule("keptOffMarker", "prefix", fallback=_FALLBACK_MARKER_PREFIX)


def announce(course: str, section_number: int, found_here: bool, look_alikes: list,
             dropped_places: list, printer=print) -> None:
    """
    What the build says about the page: one line when a page with the name is
    at the top of the course or of this section; one line per look-alike;
    and the machine-readable `PLANTOIR_KEPT_OFF:` line only when a page the
    course's settings had LISTED was dropped — the case where a page earlier
    builds published is now kept off (`howITeachPage.keptOffMarker`).
    """
    if found_here or dropped_places:
        printer(kept_off_the_website_line())
    for name in look_alikes:
        printer(look_alike_line(name))
    if not dropped_places:
        return
    payload = {"course": course, "section": section_number, "pages": dropped_places}
    printer(f"{marker_prefix()} {json.dumps(payload, ensure_ascii=False)}")


def place_in_the_course(name: str, section_folder: str = "") -> str:
    """A dropped page's place in the course folder, without `.md`."""
    stem = name[:-3] if folded(name).endswith(".md") else name
    if section_folder:
        return f"{section_folder}/{stem}"
    return stem
