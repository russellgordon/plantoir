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

def readable_texts(source: HelpSource, page: Page) -> List[Tuple[int, str]]:
    """Every piece of text a reader reads on the page, with its line."""
    texts: List[Tuple[int, str]] = [(1, page.title), (1, page.question)]
    if page.is_stub:
        return texts
    texts.append((1, str(page.fields.get("description", ""))))
    for keyword in page.keywords:
        texts.append((1, keyword))
    for block in walk_blocks(page.blocks):
        kind: str = block["kind"]
        if kind == "heading":
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
            if scene is not None:
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
    pages: List[Page] = list(source.pages)
    if source.intro is not None:
        pages.append(source.intro)
    for page in pages:
        file: str = source.page_file_label(page)
        for line, text in readable_texts(source, page):
            source.words.check(page.id, file, line, text, source.problems)


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


def normalise(text: str) -> str:
    return re.sub(r"\s+", " ", text.replace("’", "'")).strip().casefold()


def contract_sentences(repo: Path) -> List[str]:
    """Every run of five or more words the app shows, from the contract files:
    all of assist-wording.json, and the `sentences`, `wording` and `words`
    values of the others. A placeholder ({name}, %@) splits a sentence into
    the runs around it."""
    strings: List[str] = []
    for path in sorted((repo / "contracts").glob("*.json")):
        with path.open(encoding="utf-8") as handle:
            document = json.load(handle)
        if path.name in CONTRACT_SENTENCE_FILES_WHOLE:
            _collect_strings(document.get("wording", document), strings)
        else:
            _collect_sentence_values(document, strings)
    runs: List[str] = []
    seen: Set[str] = set()
    for text in strings:
        for piece in re.split(r"\{[^}]*\}|%@|%d|%\d\$@|\\\([^)]*\)", text):
            normalised: str = normalise(piece).strip(" .,:;")
            if len(normalised.split(" ")) >= SENTENCE_MIN_WORDS and normalised not in seen:
                seen.add(normalised)
                runs.append(normalised)
    return runs


def check_contract_sentences(source: HelpSource) -> None:
    sentences: List[str] = contract_sentences(source.repo)
    for page in source.pages:
        if page.is_stub:
            continue
        for line, text in readable_texts(source, page):
            if text.strip() == "":
                continue
            normalised: str = normalise(text)
            for sentence in sentences:
                if sentence in normalised:
                    source.problems.fail(
                        str(page.file), line,
                        "types a sentence the app shows (" + repr(sentence[:60]) + "): use its {{say:}} token",
                    )


def run_structural_checks(source: HelpSource) -> None:
    check_outline(source)
    source.registries.check_registries(source.problems)
    check_scenes(source)
    check_page_fields(source)
    check_tone_file(source)
    check_words(source)
    check_contract_sentences(source)
