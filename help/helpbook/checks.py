"""The structural checks every command runs (--check, --mac, --web).

A failure stops the command, so the Xcode build phase fails the Debug, test
and Release build on it. Dates and unused registry ids are WARNINGS only:
they are release problems, refused by F's --release, never by a build.
"""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any, Dict, List, Set, Tuple

from .markdown import readable_inline, walk_blocks
from .render import HelpSource, Page
from .tokens import MACHINE_TOKEN

SCENE_FIELDS = ["page", "shows", "labels", "expectText", "awaiting_capture", "waiting_on", "setup", "windows", "raw"]
REQUIRED_SCENE_FIELDS = ["page", "shows", "labels", "awaiting_capture", "setup"]
VERSION = re.compile(r"^\d+\.\d+\.\d+$")
CONTRACT_SENTENCE_KEYS = ["sentences", "wording", "words"]
CONTRACT_SENTENCE_FILES_WHOLE = ["assist-wording.json"]
SENTENCE_MIN_WORDS = 5


def check_outline(source: HelpSource) -> None:
    problems = source.problems
    outline = source.outline
    file: str = "help/outline.json"
    seen_ids: Set[str] = set()
    seen_scenes: Set[str] = set()
    scene_total: int = 0
    page_total: int = 0
    for section in outline.get("sections", []):
        section_assistant: bool = section.get("assistant") is True
        for entry in section.get("pages", []):
            page_total += 1
            page_id: str = str(entry.get("id", ""))
            if re.match(r"^[a-z0-9]+(-[a-z0-9]+)*$", page_id) is None:
                problems.fail(file, None, repr(page_id) + " is not a page id (lower case words joined by -)")
            if page_id in seen_ids:
                problems.fail(file, None, "two outline entries have the id " + page_id)
            seen_ids.add(page_id)
            if "section" in entry and entry.get("section") != section.get("title"):
                problems.fail(file, None, page_id + ": its section " + repr(entry.get("section")) + " is not the section that holds it")
            if entry.get("anchor") != page_id:
                problems.fail(file, None, page_id + ": its anchor " + repr(entry.get("anchor")) + " differs from its id")
            for field in ("title", "question"):
                if str(entry.get(field, "")).strip() == "":
                    problems.fail(file, None, page_id + " has no " + field)
            if (entry.get("assistant") is True) != section_assistant:
                problems.fail(
                    file, None,
                    page_id + ": a page is `assistant: true` exactly when it sits in the assistant section",
                )
            scene_ids: List[str] = list(entry.get("sceneIds", []))
            if entry.get("scenes") != len(scene_ids):
                problems.fail(file, None, page_id + ": `scenes` is " + str(entry.get("scenes")) + " but it lists " + str(len(scene_ids)))
            for scene_id in scene_ids:
                scene_total += 1
                if re.match("^" + re.escape(page_id) + r"-\d+$", scene_id) is None:
                    problems.fail(file, None, page_id + ": scene ids are <page id>-<n>, not " + repr(scene_id))
                if scene_id in seen_scenes:
                    problems.fail(file, None, "two pages list the scene " + scene_id)
                seen_scenes.add(scene_id)
    if outline.get("pageCount") != page_total:
        problems.fail(file, None, "pageCount is " + str(outline.get("pageCount")) + " but the sections list " + str(page_total))
    if outline.get("sceneCount") != scene_total:
        problems.fail(file, None, "sceneCount is " + str(outline.get("sceneCount")) + " but the pages list " + str(scene_total))


def check_scenes(source: HelpSource) -> None:
    problems = source.problems
    file: str = "help/scenes.json"
    for scene_id in sorted(source.registries.scenes):
        scene: Dict[str, Any] = source.registries.scenes[scene_id]
        for field in scene:
            if field not in SCENE_FIELDS:
                problems.fail(file, None, scene_id + " has an unknown field `" + field + "`")
        for field in REQUIRED_SCENE_FIELDS:
            if field not in scene:
                problems.fail(file, None, scene_id + " is missing `" + field + "`")
        page = source.pages_by_id.get(str(scene.get("page", "")))
        if page is None:
            problems.fail(file, None, scene_id + " names page " + repr(scene.get("page")) + ", which is not in the outline")
        elif scene_id not in page.scene_ids:
            problems.fail(file, None, scene_id + " is not in the sceneIds of page " + page.id)
        waiting_on = scene.get("waiting_on")
        if waiting_on is not None and re.match(r"^#\d+$", str(waiting_on)) is None:
            problems.fail(file, None, scene_id + ": waiting_on is \"#<issue>\" or absent")


def check_page_fields(source: HelpSource) -> None:
    """Head fields the template needs; stubs are exempt (they have none)."""
    problems = source.problems
    for page in source.pages:
        if page.is_stub:
            continue
        file: str = str(page.file)
        checked = page.fields.get("checked")
        if not isinstance(checked, str) or VERSION.match(checked) is None:
            problems.fail(file, 1, "`checked:` is the version the page was last checked against, like 2.0.0")
        if str(page.fields.get("description", "")).strip() == "":
            problems.fail(file, 1, "`description:` is one sentence for search results")
        for keyword in page.keywords:
            if "," in keyword:
                problems.fail(file, 1, "a keyword holds no comma (" + repr(keyword) + "): give each its own `- item` line")
        if page.indexed and len(page.keywords) == 0:
            problems.fail(file, 1, "a task page carries `keywords:`, the words a teacher would type")
        covers = page.fields.get("covers", [])
        if isinstance(covers, list):
            for covered in covers:
                if not (source.repo / covered).exists():
                    problems.fail(file, 1, "covers " + repr(covered) + ", which does not exist")
        for date_field in ("factsChecked",):
            if date_field in page.fields and re.match(r"^\d{4}-\d{2}-\d{2}$", str(page.fields[date_field])) is None:
                problems.fail(file, 1, "`" + date_field + ":` is a date written YYYY-MM-DD")
        if "authority" in page.fields and not str(page.fields["authority"]).startswith("https://"):
            problems.fail(file, 1, "`authority:` is an https:// address")
        if "authority" in page.fields and "factsChecked" not in page.fields:
            problems.fail(file, 1, "`authority:` is printed with the date its facts were checked: add `factsChecked:`")


def check_withheld_file(source: HelpSource) -> None:
    for page_id in sorted(source.withheld_pages):
        if page_id not in source.pages_by_id:
            source.problems.fail("help/withheld-on-the-web.json", None, "pages: " + page_id + " is not in the outline")


def check_tone_file(source: HelpSource) -> None:
    families: List[Tuple[str, List[Dict[str, Any]]]] = [
        ("exemptions", source.words.exemptions),
        ("quotes", source.words.quote_exemptions),
    ]
    for family, entries in families:
        for entry in entries:
            if str(entry.get("why", "")).strip() == "":
                source.problems.fail("help/tone.json", None, family + ": " + repr(entry.get("phrase")) + " needs a reason")
            for page_id in entry.get("pages", []):
                if page_id not in source.pages_by_id:
                    source.problems.fail("help/tone.json", None, family + ": " + repr(entry.get("phrase")) + " names page " + page_id + ", which is not in the outline")


# MARK: what a reader reads

def readable_texts(
    source: HelpSource, page: Page, include_names: bool = True, skip_runs: Tuple[str, ...] = (),
    include_scenes: bool = True,
) -> List[Tuple[int, str]]:
    """Every piece of text a reader reads on the page, with its line.

    With include_names=False it is the running prose only: the outline's title
    and question, headings and keywords are left out. Those NAME things (a
    title may be a menu item's words, "Get ready for the start of the year"),
    so the check for contract sentences typed by hand reads prose only."""
    texts: List[Tuple[int, str]] = []
    if include_names:
        texts.append((1, page.title))
        texts.append((1, page.question))
    if page.is_stub:
        return texts
    # A description takes one token, {{machine}}; it is blanked like any other.
    texts.append((1, str(page.fields.get("description", "")).replace(MACHINE_TOKEN, "computer")))
    if include_names:
        for keyword in page.keywords:
            texts.append((1, keyword))
    for block in walk_blocks(page.blocks, skip_runs):
        kind: str = block["kind"]
        if kind == "heading":
            if include_names:
                texts.append((block["line"], readable_inline(block["text"])))
        elif kind == "paragraph":
            joined: List[str] = []
            for number, text in block["lines"]:
                joined.append(readable_inline(text))
            texts.append((block["line"], " ".join(joined)))
        elif kind == "list":
            for item in _list_items(block):
                joined = []
                for number, text in item["lines"]:
                    joined.append(readable_inline(text))
                texts.append((item["line"], " ".join(joined)))
        elif kind == "table":
            for cell in block["header"]:
                texts.append((block["line"], readable_inline(cell)))
            for number, cells in block["rows"]:
                for cell in cells:
                    texts.append((number, readable_inline(cell)))
        elif kind == "picture":
            texts.append((block["line"], readable_inline(block["alt"])))
            scene = source.registries.scenes.get(block["scene"])
            if scene is not None and include_scenes:
                texts.append((block["line"], str(scene.get("shows", ""))))
                for label in scene.get("labels", []):
                    texts.append((block["line"], str(label)))
    return texts


def _list_items(block: Dict[str, Any]) -> List[Dict[str, Any]]:
    items: List[Dict[str, Any]] = []
    for item in block["items"]:
        items.append(item)
        if item["children"] is not None:
            for child in _list_items(item["children"]):
                items.append(child)
    return items


def check_words(source: HelpSource) -> None:
    for key in sorted(source.interface):
        source.words.check("interface-words", "help/interface-words.json", None, source.interface[key], source.problems)
    pages: List[Page] = list(source.pages)
    if source.intro is not None:
        pages.append(source.intro)
    for page in pages:
        file: str = source.page_file_label(page)
        for line, text in readable_texts(source, page):
            source.words.check(page.id, file, line, text, source.problems)


# MARK: the reader's computer is {{machine}}

BARE_MAC = re.compile(r"\bMac\b")


def check_machine_word(source: HelpSource) -> None:
    """A page's prose never says "Mac" (#898): the same pages are built for
    Windows, where the reader's computer is a PC. Write {{machine}}, or put a
    passage that is true only on a Mac in a {{mac}} ... {{/mac}} run, where the
    word is allowed. Read: the description, headings, paragraphs, list items,
    table cells and alt lines, with tokens and code blanked, so a label or a
    sentence the app shows ("A folder on this Mac") is never refused. Not read:
    keywords (a teacher may type the word), the outline's titles and questions,
    and scenes.json. Product names pass by themselves: the pattern is the whole
    word with its capital, so macOS and MacBook do not match. A tone.json
    exemption (an exact phrase, scoped to pages) covers any other name."""
    pages: List[Page] = list(source.pages)
    if source.intro is not None:
        pages.append(source.intro)
    for page in pages:
        if page.is_stub:
            continue
        file: str = source.page_file_label(page)
        texts: List[Tuple[int, str]] = readable_texts(
            source, page, include_names=False, skip_runs=("mac",), include_scenes=False
        )
        for block in walk_blocks(page.blocks, ("mac",)):
            if block["kind"] == "heading":
                texts.append((block["line"], readable_inline(block["text"])))
        for line, text in texts:
            if BARE_MAC.search(source.words._exempt(page.id, text)) is not None:
                source.problems.fail(
                    file, line,
                    'says "Mac": write {{machine}}, or put what is true only on a Mac in a {{mac}} run (#898)',
                )


# MARK: contract sentences typed by hand

def _collect_strings(value: Any, into: List[str]) -> None:
    if isinstance(value, str):
        into.append(value)
    elif isinstance(value, list):
        for item in value:
            _collect_strings(item, into)
    elif isinstance(value, dict):
        for key in value:
            _collect_strings(value[key], into)


def _collect_sentence_values(value: Any, into: List[str]) -> None:
    if isinstance(value, dict):
        for key in value:
            if key in CONTRACT_SENTENCE_KEYS:
                _collect_strings(value[key], into)
            else:
                _collect_sentence_values(value[key], into)
    elif isinstance(value, list):
        for item in value:
            _collect_sentence_values(item, into)


def contract_words(text: str) -> List[str]:
    """A text as the words it holds, for comparing a page with the contract:
    curly quotes made straight, dashes and punctuation dropped, white space
    (line breaks included) ignored. Case is kept here and ignored by the
    patterns, except where a placeholder stands (see contract_sentences)."""
    straightened: str = text
    for curly, straight in (("\u2019", "'"), ("\u2018", "'"), ("\u201c", '"'), ("\u201d", '"')):
        straightened = straightened.replace(curly, straight)
    return re.findall(r"[0-9A-Za-z\u00c0-\u024f]+(?:'[0-9A-Za-z\u00c0-\u024f]+)*", straightened)


PLACEHOLDER = re.compile(r"\{[^}]*\}|%@|%d|%\d\$@|\\\([^)]*\)")
WILDCARD_WORD = "\u0000"


def contract_sentences(repo: Path) -> List[Tuple[str, Any]]:
    """Every WHOLE sentence the app shows of five words or more (one that ends
    as a sentence does, with . ! ? or …), from the
    contract files: all of assist-wording.json, and the `sentences`, `wording`
    and `words` values of the others. A value holding several sentences gives
    each one; a placeholder ({name}, %@) stands for one to four words. A
    shorter string, or a fragment of a longer one, is ordinary English and is
    never matched. Returns (the sentence, its pattern over contract_words)."""
    strings: List[str] = []
    for path in sorted((repo / "contracts").glob("*.json")):
        with path.open(encoding="utf-8") as handle:
            document = json.load(handle)
        if path.name in CONTRACT_SENTENCE_FILES_WHOLE:
            _collect_strings(document.get("wording", document), strings)
        else:
            _collect_sentence_values(document, strings)
    sentences: List[Tuple[str, Any]] = []
    seen: Set[str] = set()
    for value in strings:
        for sentence in re.split(r"(?<=[.!?\u2026])\s+", value.strip()):
            # A sentence ends as one; a label or a phrase ("a folder on this computer") does not.
            if re.search(r"[.!?\u2026][\"'\u201d\u2019)]*$", sentence) is None:
                continue
            marked: str = PLACEHOLDER.sub(" " + WILDCARD_WORD + " ", sentence)
            pieces: List[str] = []
            real_words: int = 0
            for chunk in marked.split(WILDCARD_WORD):
                for word in contract_words(chunk):
                    pieces.append("(?i:" + re.escape(word) + ")")
                    real_words += 1
                # A placeholder stands for a name or a number (a section, a page title,
                # a count): one to four words, the first a capital or a digit, so
                # "Put back as they were: {pages}." never swallows "the pages show again".
                pieces.append(r"[A-Z0-9\u00c0-\u00de]\S*(?: \S+){0,3}")
            pieces.pop()
            if real_words < SENTENCE_MIN_WORDS:
                continue
            pattern_text: str = "^" + " ".join(pieces) + "$"
            if pattern_text in seen:
                continue
            seen.add(pattern_text)
            sentences.append((sentence, re.compile(pattern_text)))
    return sentences


def check_contract_sentences(source: HelpSource) -> None:
    """A whole sentence the app shows, retyped as a whole sentence of a page's
    running prose, would go stale silently when the app's words change: it is
    refused, and written {{say:<key>}} instead. Titles, questions, headings and keywords are names
    and are not read."""
    sentences: List[Tuple[str, Any]] = contract_sentences(source.repo)
    pages: List[Page] = list(source.pages)
    if source.intro is not None:
        pages.append(source.intro)
    for page in pages:
        if page.is_stub:
            continue
        for line, text in readable_texts(source, page, include_names=False):
            if text.strip() == "":
                continue
            # Per sentence of the page: refused only when the writer's WHOLE sentence is
            # a contract sentence. A longer sentence that holds one is ordinary prose.
            for prose_sentence in re.split(r"(?<=[.!?\u2026])\s+", text.strip()):
                prose: str = " ".join(contract_words(prose_sentence))
                if prose == "":
                    continue
                for sentence, pattern in sentences:
                    if pattern.match(prose) is not None:
                        source.problems.fail(
                            str(page.file), line,
                            "retypes a whole sentence the app shows (" + repr(sentence[:70]) + "): write its "
                            "{{say:}} token (a menu item is {{menu:}}, a button or label {{control:}})",
                        )


def run_structural_checks(source: HelpSource) -> None:
    check_outline(source)
    source.registries.check_registries(source.problems)
    check_scenes(source)
    check_page_fields(source)
    check_tone_file(source)
    check_withheld_file(source)
    check_words(source)
    check_machine_word(source)
    check_contract_sentences(source)
