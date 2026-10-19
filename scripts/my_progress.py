#!/usr/bin/env python3
"""
My Progress (#545): the build's half that runs BEFORE Quartz -
contracts/shared-rules.json -> myProgress.

A student who ticks the boxes under a page's success-criteria heading (#519
keeps each tick in their own browser) sees, on one page per section, how many
they have ticked on each page, grouped by the class that first linked the page
- for their eyes only: nothing is sent anywhere. Three halves:

* this file decides, before the site is built, whether the section gets the
  page at all (`include_my_progress`, and at least one page students can see
  with a task item under one of the success-criteria headings), writes the
  page, puts it FIRST in the build's copy of Key Links (Russell, 2026-10-19),
  and writes quartz/plantoir_progress.json - the headings, the words, the
  classes in the order the build dates pages from them, which class first
  linked each page DIRECTLY, and which pages it read as having counted items;
* the emitter (support/quartz/plugins/emitters/plantoirProgress.ts) reads the
  counted items off the BUILT pages - PlantoirTasks' stamps, the only
  producer of item ids (#519 review F1) - and writes the manifest, saying on
  a `plantoir: note:` line wherever its reading and this one disagree;
* the page's script (components/scripts/progress.inline.ts) adds up the
  student's ticks against the manifest.

This file never makes an item id: the gate only asks whether a page HAS an
item that counts, read line by line (not a Markdown parser, for the reason
markdown_code gives), and the contract's `sections` and `gate` cases are run
through both readings.

Stdlib only, no frontmatter: Windows' PythonToolchainTests discovers
test_my_progress.py and runs it without python-frontmatter.
"""

import html
import json
import re
import unicodedata
from pathlib import Path

import contracts
import markdown_code

# The page this build writes, at the top of the site, and the plan the
# emitter reads (in the section's quartz/ folder, never in public/).
PAGE_FILE = "My Progress.md"
PLAN_FILE = "plantoir_progress.json"
PLAN_VERSION = 1

# Why a section has no page (myProgress.marker): the reason travels to the
# trail and to the emitter, which still reads the pages when nothing
# qualified here so that a page this reading missed is said.
BUILT = "built"
SWITCHED_OFF = "switchedOff"
NO_SUCCESS_CRITERIA = "noSuccessCriteria"
TEACHERS_OWN_PAGE = "teachersOwnPage"


def rules() -> dict:
    return contracts.section("shared-rules", "myProgress")


def _words_without_notes(section: dict) -> dict:
    words = {}
    for key, text in section.items():
        if key != "note":
            words[key] = text
    return words


def words() -> dict:
    """What a student reads (myProgress.words), without its note."""
    return _words_without_notes(rules()["words"])


def notes() -> dict:
    """What a teacher reads on a `plantoir: note:` line (myProgress.notes)."""
    return _words_without_notes(rules()["notes"])


# ---- Which headings count ------------------------------------------------------


def normalised_heading(text: str) -> str:
    """
    A heading's words as the build compares them (myProgress.headings.rule):
    Unicode's composed form (NFC), curly quotes made straight (the site's
    parser curls a teacher's ' and "), every run of white space made one
    space, trimmed, every trailing punctuation mark and space taken off,
    lower-cased. The same rule as progressRules.normalisedHeading.
    """
    words = unicodedata.normalize("NFC", str(text))
    words = re.sub("[\u2018\u2019]", "'", words)
    words = re.sub("[\u201c\u201d]", '"', words)
    words = re.sub(r"\s+", " ", words).strip()
    end = len(words)
    while end > 0 and (words[end - 1].isspace() or unicodedata.category(words[end - 1]).startswith("P")):
        end -= 1
    return words[:end].lower()


def headings_from(config: dict) -> list:
    """
    The success-criteria headings this course recognises
    (`success_criteria_headings`, myProgress.config): the teacher's own list
    when it is a list with at least one heading that is not blank - it
    REPLACES the defaults - and the contract's three defaults otherwise
    (absent, not a list, or nothing but blanks). Anything in the list that is
    not a string is left out.
    """
    value = config.get("success_criteria_headings") if isinstance(config, dict) else None
    chosen = []
    if isinstance(value, list):
        for entry in value:
            if isinstance(entry, str) and normalised_heading(entry) != "":
                chosen.append(entry)
    if chosen:
        return chosen
    return list(rules()["headings"]["defaults"])


# ---- Whether a page has an item that counts (the gate) ---------------------------

# A task item's first line, as the site's parser reads one: any quote markers,
# the indent, one or more list markers, the box, then a space and more on the
# line. A box with nothing after it on its line (_BOX_ONLY) is an item only
# when its words go on in the next line (measured for #545's fixes round):
# alone, `- [ ]` and `- [ ] ` are plain text to the parser (quizzes.py).
_TASK_LINE = re.compile(r"^(?:[ \t]*>)*[ \t]*(?:(?:[-*+]|[0-9]{1,9}[.)])[ \t]+)+\[[ xX]\][ \t]+\S")
_BOX_ONLY = re.compile(r"^(?:[ \t]*>)*[ \t]*(?:(?:[-*+]|[0-9]{1,9}[.)])[ \t]+)+\[[ xX]\][ \t]*$")
_HTML_COMMENT = re.compile(r"<!--[\s\S]*?-->")
_ATX = re.compile(r"^( {0,3})(#{1,6})(?:[ \t]+(.*?))?(?:[ \t]+#+)?[ \t]*$")
_SETEXT = re.compile(r"^ {0,3}(=+|-+)[ \t]*$")
_LIST_ITEM = re.compile(r"^[ \t]*(?:[-*+]|[0-9]{1,9}[.)])(?:[ \t]+|$)")
_QUOTE = re.compile(r"^[ \t]{0,3}>")
_FENCE = re.compile(r"^[ \t]*(```|~~~)")
_QUIZ = re.compile(r"\[!quiz\]", re.IGNORECASE)


def _quote_depth(line: str) -> int:
    depth = 0
    rest = line
    while True:
        match = re.match(r"^[ \t]{0,3}>[ \t]?", rest)
        if match is None:
            return depth
        depth += 1
        rest = rest[match.end():]


def _heading_words(raw: str) -> str:
    """A heading's text as it reads on the page: links by the words they
    show, emphasis, code and highlight marks and inline HTML taken off."""
    text = re.sub(r"!\[\[[^\]]*\]\]", "", raw)
    text = re.sub(r"\[\[[^\]|]*\|([^\]]*)\]\]", r"\1", text)
    text = re.sub(r"\[\[([^\]]*)\]\]", r"\1", text)
    text = re.sub(r"!\[[^\]]*\]\([^)]*\)", "", text)
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)
    text = re.sub(r"<[^>]+>", "", text)
    text = text.replace("`", "").replace("==", "").replace("~~", "")
    text = text.replace("**", "").replace("__", "")
    text = re.sub(r"(?<![\w*])\*|\*(?![\w*])", "", text)
    text = re.sub(r"(?<!\w)_|_(?!\w)", "", text)
    # `&nbsp;` and its kind read as the characters they are, as on the page.
    return html.unescape(text)


def _indent(line: str) -> int:
    """The columns of white space a line starts with, a tab to the next
    multiple of four, as CommonMark counts them."""
    columns = 0
    for character in line:
        if character == " ":
            columns += 1
        elif character == "\t":
            columns += 4 - columns % 4
        else:
            break
    return columns


def _body_of(text: str) -> str:
    """The page without its settings block (`---` ... `---` at the top)."""
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    if text.startswith("﻿"):
        text = text[1:]
    if not text.startswith("---\n"):
        return text
    end = text.find("\n---", 3)
    while end >= 0:
        after = end + 4
        if after >= len(text) or text[after] == "\n":
            return text[after + 1:] if after < len(text) else ""
        end = text.find("\n---", after)
    return text


def _masked(text: str) -> str:
    """Code, %% comments and HTML comments replaced by spaces, line breaks
    kept, so a heading or a task line written as an example is no heading or
    task."""
    characters = list(text)
    ranges = list(markdown_code.not_a_link_ranges(text))
    for match in _HTML_COMMENT.finditer(text):
        ranges.append((match.start(), match.end()))
    for start, end in ranges:
        for index in range(start, min(end, len(characters))):
            if characters[index] != "\n":
                characters[index] = " "
    return "".join(characters)


def page_has_counted_items(text: str, headings: list) -> bool:
    """
    Whether one page has a task item that counts (myProgress.sections, as a
    gate): a heading at the page's own top level - not in a quote or callout,
    not inside a list - whose words are one of `headings`, opens a section
    that runs to the next top-level heading of the same or a higher level;
    a task item anywhere inside it counts unless a `> [!quiz]` callout holds
    it (a quiz's boxes stay the quiz's). Code and %% comments are not read.
    """
    wanted = set()
    for heading in headings:
        wanted.add(normalised_heading(heading))
    body = _body_of(text)
    lines = _masked(body).split("\n")
    # A heading's words are read from the line as written, %% comments taken
    # off: masking blanks inline code too, and a heading's code is its words.
    written = body.split("\n")
    open_level = 0
    in_list = False
    quiz_depth = 0
    paragraph = []
    for number, line in enumerate(lines):
        as_written = re.sub(r"%%.*?%%", "", written[number])
        depth = _quote_depth(line)
        if quiz_depth and depth < quiz_depth:
            quiz_depth = 0
        if depth and _QUIZ.search(line) and not quiz_depth:
            quiz_depth = depth
        blank = line.strip() == ""
        heading_level = 0
        heading_text = None
        atx = _ATX.match(line) if depth == 0 else None
        if atx is not None and not (in_list and atx.group(1)):
            heading_level = len(atx.group(2))
            spelled = _ATX.match(as_written)
            heading_text = (spelled.group(3) or "") if spelled is not None else ""
        elif depth == 0 and not in_list and paragraph and _SETEXT.match(line):
            heading_level = 1 if line.strip().startswith("=") else 2
            heading_text = " ".join(paragraph)
        if heading_level:
            if open_level and heading_level <= open_level:
                open_level = 0
            if not open_level and normalised_heading(_heading_words(heading_text)) in wanted:
                open_level = heading_level
            paragraph = []
            in_list = False
            continue
        # Four columns in at the page's own level, outside a list, is an
        # indented code block (or a paragraph's continuation): never an item.
        code_line = depth == 0 and not in_list and _indent(line) >= 4
        if open_level and not quiz_depth and not code_line:
            if _TASK_LINE.match(line):
                return True
            if _BOX_ONLY.match(line) and number + 1 < len(lines):
                after = lines[number + 1]
                if (after.strip() != "" and _quote_depth(after) == depth and not _LIST_ITEM.match(after)
                        and not _ATX.match(after) and not _FENCE.match(after)):
                    return True
        if code_line and not paragraph:
            continue
        if blank:
            paragraph = []
            continue
        if depth:
            paragraph = []
            in_list = False
            continue
        if _LIST_ITEM.match(line):
            in_list = True
            paragraph = []
            continue
        if in_list and line[:1] in (" ", "\t"):
            continue
        in_list = False
        if _FENCE.match(line):
            paragraph = []
            continue
        paragraph.append(as_written.strip())
    return False


def pages_with_counted_items(pages: list, headings: list) -> list:
    """The `path` of every page (figures.pages_students_see's shape) the gate
    says has an item that counts, in the site's composed form (NFC)."""
    found = []
    for page in pages:
        if page_has_counted_items(page["text"], headings):
            found.append(unicodedata.normalize("NFC", page["path"]))
    return sorted(found)


# ---- The plan the emitter reads -------------------------------------------------


def unit_label(title: str, pattern: str, unit_word: str, numbered: bool, class_folder: str):
    """
    The table a class goes in (myProgress.labels): "<unit word> N" from the
    class page's own name, ordered by N; a club (one number per page) has one
    table, named after the folder its meetings are in.
    """
    if numbered:
        return class_folder, 0
    match = re.match(pattern, title.strip(), re.IGNORECASE)
    if match is None:
        return unit_word, 0
    number = int(match.group(1))
    return f"{unit_word} {number}", number


def plan(page: bool, reason: str, slug: str, headings: list, classes: list,
         first_class_of: dict, gate: list) -> dict:
    """What quartz/plantoir_progress.json carries (myProgress.plan)."""
    normalised = []
    for heading in headings:
        normalised.append(normalised_heading(heading))
    return {
        "version": PLAN_VERSION,
        "page": page,
        "reason": reason,
        "slug": slug,
        "headings": normalised,
        "words": words(),
        "notes": notes(),
        "classes": classes,
        "firstClassOf": first_class_of,
        "gate": gate,
    }


def write_plan(output_dir, content: dict) -> bool:
    """Written on every build, the same bytes for the same input; answers
    whether it changed (the quizzes' pattern)."""
    path = Path(output_dir) / "quartz" / PLAN_FILE
    data = (json.dumps(content, indent=2, sort_keys=True, ensure_ascii=False) + "\n").encode("utf-8")
    if path.is_file() and path.read_bytes() == data:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return True


# ---- The page and its Key Links entry ---------------------------------------------


def teachers_own_page(content_root) -> Path | None:
    """A page of the teacher's at the top of the site whose name is the
    page's, in any case (#545 plan review F5): it wins, and the build writes
    nothing over it - on a file system that ignores case, writing ours would
    replace theirs."""
    root = Path(content_root)
    wanted = PAGE_FILE.lower()
    try:
        entries = sorted(root.iterdir())
    except OSError:
        return None
    for entry in entries:
        if entry.name.lower() == wanted and entry.is_file():
            return entry
    return None


def _html_attribute(text: str) -> str:
    return (str(text).replace("&", "&amp;").replace('"', "&quot;")
            .replace("<", "&lt;").replace(">", "&gt;"))


def page_text(created: str | None) -> str:
    """
    The page the build writes (myProgress.page): its title, the first class's
    date (the date every other build-written page carries, for the feeds),
    on the site and with no Backlinks panel, and one EMPTY element the page's
    script draws into, carrying the placeholder sentence (shown by the
    page's styles until the script draws) and the sentence for a copy of the
    site the manifest cannot be read from as attributes. No text on the page
    means Quartz draws no date line and no reading time
    (myProgress.page.dateLine; Russell's Q6). No link of any kind, so no
    other page's Backlinks or the coverage map changes.
    """
    said = words()
    lines = ["---", f"title: {said['title']}"]
    if created:
        lines.append(f"created: {created}")
    lines += ["publish: true", "excludeBacklinks: true", "---", ""]
    lines.append(
        f'<div class="plantoir-progress" data-plantoir-progress '
        f'data-placeholder="{_html_attribute(said["placeholder"])}" '
        f'data-unreadable="{_html_attribute(said["unreadable"])}"></div>'
    )
    return "\n".join(lines) + "\n"


_BULLET = re.compile(r"^[ \t]*[-*+][ \t]")


def link_from_key_links(content_root) -> bool:
    """
    Put My Progress FIRST in the build's copy of Key Links (Russell,
    2026-10-19; myProgress.keyLinks): a bullet `- [[My Progress]]` before the
    page's first bullet, or a line of its own at the end when it has none.
    The teacher's own page is never touched, and a copy that already links
    the page (any case) is left exactly as it is. Answers whether it changed.
    """
    key_links = Path(content_root) / "Key Links.md"
    if not key_links.is_file():
        return False
    # Bytes, not read_text: universal newlines would turn a page saved with
    # CR LF into LF, and the build's copy would change every line.
    text = key_links.read_bytes().decode("utf-8")
    title = words()["title"]
    # [[My Progress]], [[My Progress|...]] (or the `\|` a table writes) and
    # [[My Progress#...]], in any case - never a page whose name only begins
    # with the same words, such as [[My Progress Journal]] (#545
    # implementation review 1).
    already = re.compile(r"\[\[" + re.escape(title) + r"[ \t]*(?:\]\]|\\?\||#)", re.IGNORECASE)
    if already.search(text):
        return False
    entry = f"- [[{title}]]"
    newline = "\r\n" if "\r\n" in text else "\n"
    lines = text.split(newline)
    body_start = 0
    if lines and lines[0].strip() == "---":
        for index in range(1, len(lines)):
            if lines[index].strip() == "---":
                body_start = index + 1
                break
    for index in range(body_start, len(lines)):
        if _BULLET.match(lines[index]):
            indent = lines[index][: len(lines[index]) - len(lines[index].lstrip(" \t"))]
            lines.insert(index, indent + entry)
            key_links.write_bytes(newline.join(lines).encode("utf-8"))
            return True
    if text.endswith(newline) or text == "":
        updated = text + entry + newline
    else:
        updated = text + newline + newline + entry + newline
    key_links.write_bytes(updated.encode("utf-8"))
    return True


# ---- Telling the app ------------------------------------------------------------


def announce(course: str, section_number: int, reason: str, pages: int, printer=print) -> None:
    """
    One sentence for the teacher, then the machine-readable line the app puts
    on its activity trail (myProgressBuilt) - how many pages count and why
    there is no page, never anything written on one. Nothing when the page
    is switched off: the console says so, and the trail would only repeat
    the setting.
    """
    if reason == SWITCHED_OFF:
        printer(f"ℹ️ The My Progress page is switched off for {course} Section {section_number}.")
        return
    if reason == BUILT:
        printer(f"📈 My Progress: counted the success criteria on {pages} page(s).")
    elif reason == TEACHERS_OWN_PAGE:
        printer("ℹ️ My Progress: the course has its own page called My Progress, so the build left it as it is.")
    else:
        printer("ℹ️ My Progress: no page students can see has boxes to tick under a success-criteria heading, so there is no My Progress page.")
    try:
        prefix = contracts.section("shared-rules", "myProgressBuilt", "marker", "prefix")
    except Exception:
        return
    payload = {"course": course, "section": section_number, "built": reason == BUILT,
               "pages": pages, "reason": reason}
    printer(f"{prefix} {json.dumps(payload, ensure_ascii=False)}")
