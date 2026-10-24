#!/usr/bin/env python3
"""
Pages that ask for something extra on the built site (#454) - the rules.

Two frontmatter keys today, both in `contracts/file-formats.json` ->
`pageOptIns`, which is where their cases live:

* `printable: true` puts a Print button on the page and makes ⌘P print it as a
  worksheet. It also makes the section's site CARRY the print engine
  (Paged.js), which no other site carries: a course that never prints pays
  nothing for the feature. That is the gate below.
* `printPdf: <file name>` names a PDF in the course's Media folder that the
  Print button opens instead of the generated handout.

**Values arrive already parsed.** The build loads every page with
python-frontmatter (PyYAML, YAML 1.1) and writes it back, and the site reads
what it wrote - so `printable: yes` is the boolean true by the time anything
asks, and the only honest question here is "is it the boolean true?". The
build does the parsing and hands the value over; this module does not import
frontmatter, so its test runs on a machine without it (Windows'
PythonToolchainTests). What PyYAML makes of each TYPED line is checked down the
real chain, inside the image, by `check_print_rules_against_the_site.py`.

#485 E1 added `function-plot`, which no frontmatter key asks for: a
```functionplot fence on a page students can see does (scripts/figures.py
counts them), and the build hands the count in beside the printable pages'.
#578 adds `geogebra` the same way: a ```geogebra fence (scripts/geogebra.py,
from stage 2) makes the site carry VENDOR_DIR/geogebra, the engine
scripts/geogebra_engine.py prepared - 27 MB, so only a site with a sketch.

#455 adds a third key, `codeRunner: true`, and with it the LANGUAGE TABLE
(RUNNER_LANGUAGES, the literal mirror of contracts/shared-rules.json ->
codeRunnerBlocks.languages): a page that opts in AND holds a runnable block of
a language (```python run) makes its site carry that language's engine. The
engine is VENDOR_DIR/<engine> with SUPPORT_DIR/gated/<engine> laid over it
(the page's own half, plantoir-worker.js), so the worker reaches the image and
the Windows runtime through support/ without a line of its own. The fence rule,
the gate and the words read the table, never the word "python".

#493 adds the second row, Swift: read-only, compiled ahead of time
(`prebuilt`), its engine the overlay alone (OVERLAY_IS_THE_ENGINE), and its
programs prepared by scripts/swift_blocks.py.
"""

import json
import os
import re
import shutil
import unicodedata
from pathlib import Path

import contracts
import markdown_code
import toolchain_paths

# The languages a ```<fence> run block can be written in (#455): the literal
# mirror of contracts/shared-rules.json -> codeRunnerBlocks.languages, keyed by
# `fence`, which test_page_features.py pins field for field. A literal rather
# than a read of the contract because the gate must work where the contract
# cannot be read (a stale copy), and the site's own mirror
# (support/quartz/plugins/transformers/codeRunnerRule.ts) has to be a literal
# anyway. A second language is a second row here and there - nothing else in
# this file names a language.
RUNNER_LANGUAGES = {
    "python": {"idPrefix": "py", "displayName": "Python", "runtime": "pyodide", "engine": "pyodide",
               "worker": "plantoir-worker.js", "editable": True, "flags": ("readonly", "stdin", "autorun"),
               "inputCall": "input()", "inputPattern": r"\binput\s*\(", "prebuilt": False,
               "colour": "python"},
    "swift": {"idPrefix": "swift", "displayName": "Swift", "runtime": "swift-wasm", "engine": "swift",
              "worker": "plantoir-swift-worker.js", "editable": False, "flags": ("stdin", "autorun"),
              "inputCall": "readLine()", "inputPattern": r"\breadLine\s*\(", "prebuilt": True,
              "colour": "swift"},
}

# Engines whose overlay in SUPPORT_DIR/gated/<engine> IS the engine (#493): a
# `prebuilt` language's programs are compiled per course (scripts/
# swift_blocks.py puts them in static/swift-wasm/), so there is nothing to
# vendor - the page's thread and its WASI shim are all a site needs.
OVERLAY_IS_THE_ENGINE = set()
for _row in RUNNER_LANGUAGES.values():
    if _row["prebuilt"]:
        OVERLAY_IS_THE_ENGINE.add(_row["engine"])

# The file the site's code reads: the words, the limits and the engines this
# site carries (codeRunnerBlocks.siteDisagrees), written on every build.
RUNNER_WORDS_FILE = "plantoir_code_runner.json"

# Which engine each opt-in key pulls into a site. The engine's folder under
# VENDOR_DIR, and under the site's quartz/static, has the same name. Every
# runnable language's engine rides the `codeRunner` key.
GATED_ASSETS = {"pagedjs": "printable", "function-plot": "functionplot", "geogebra": "geogebra"}
for _row in RUNNER_LANGUAGES.values():
    GATED_ASSETS[_row["engine"]] = "codeRunner"

# What the build says about each engine, in the words of what it is FOR - a
# graph is not a print layout (#485 review S9: the first draft would have
# told a teacher their graphs were missing "the print layout").
ENGINE_WORDS = {
    "pagedjs": {
        "missing": "⚠️ {pages} page(s) ask to be printable, but this copy of Plantoir "
                   "is missing its print layout, so they will print without it.",
        "carried": "🖨️  This site carries the print layout for {pages} {noun}.",
        "failed": "⚠️ Could not set up the print layout: {error}",
    },
    "function-plot": {
        "missing": "⚠️ {pages} page(s) have a graph, but this copy of Plantoir is missing "
                   "what draws graphs, so students will see each graph's text instead.",
        "carried": "📈 This site carries what draws the graphs on {pages} {noun}.",
        "failed": "⚠️ Could not set up the graphs: {error}",
    },
    "geogebra": {
        "missing": "⚠️ {pages} page(s) have a GeoGebra sketch, but this copy of Plantoir is missing "
                   "GeoGebra, so the sketches will not open for students.",
        "carried": "📐 This site carries GeoGebra for the sketches on {pages} {noun}.",
        "failed": "⚠️ Could not set up GeoGebra for the sketches: {error}",
    },
}
# A runnable language's engine is said in the words of what it is for: the
# language a student runs. {language} is the table's displayName.
_RUNNER_ENGINE_WORDS = {
    "missing": "⚠️ {pages} page(s) have {language} code to run, but this copy of Plantoir is missing "
               "what runs it, so students will see the code without a Run button.",
    "carried": "▶️  This site carries what runs {language} for {pages} {noun}.",
    "failed": "⚠️ Could not set up {language} for the code students run: {error}",
}
for _row in RUNNER_LANGUAGES.values():
    ENGINE_WORDS[_row["engine"]] = {
        kind: text.replace("{language}", _row["displayName"]) for kind, text in _RUNNER_ENGINE_WORDS.items()
    }

# A PDF's first five bytes. A file named .pdf that does not start with them
# opens in a browser as an error page, which is worse than the handout.
PDF_SIGNATURE = b"%PDF-"


def opts_in(value) -> bool:
    """
    Does this parsed value opt the page in? Only the boolean true does.

    `"true"` (quoted) is a string and `1` a number: the site asks for the
    boolean (the component compares with `=== true`), so they do not.
    """
    return value is True


def carries_the_print_layout(printable, visible: bool, print_pdf_button: str) -> bool:
    """
    Does this page make its section's site carry the print engine?

    It must opt in, students must be able to see it, and it must not have its
    own PDF - a page whose PDF resolved never has a generated handout made.
    """
    return opts_in(printable) and bool(visible) and print_pdf_button != "pdf"


def typed_name(value):
    """
    The file name a `printPdf:` value gives, as the page gives it, or None.

    Accepts the plain name, the link Obsidian writes for a link property
    (`[[Name.pdf]]`, `[[Name.pdf|alias]]`), and the unquoted link, which YAML
    reads as a list inside a list. A number or anything else becomes its
    text, which is then not a PDF.
    """
    # The unquoted `[[x]]`: [["x"]]. Peel single-item lists down to the value.
    while isinstance(value, list) and len(value) == 1:
        value = value[0]
    if value is None or isinstance(value, (list, dict)):
        return None if value is None or len(value) == 0 else str(value)
    if isinstance(value, bool):
        return str(value).lower()
    text = str(value).strip()
    if text.startswith("[[") and text.endswith("]]"):
        text = text[2:-2]
    if "|" in text:
        text = text.split("|", 1)[0]
    text = text.strip()
    return text if text else None


def _same_name(one: str, other: str) -> bool:
    return (unicodedata.normalize("NFC", one).casefold()
            == unicodedata.normalize("NFC", other).casefold())


def _find_in_media(media_dir: Path, name: str):
    """
    The Media folder's own spelling of `name`, or None.

    By the folder's LISTING, never by asking the file system whether the name
    exists: macOS and Windows would say yes to `WORKSHEET 3.PDF` for
    `Worksheet 3.pdf` and Linux would say no, and the site carries the
    folder's spelling whichever answered (Netlify and Cloudflare are
    case-sensitive). An exact match wins over one that differs only in
    capitals.
    """
    try:
        entries = os.listdir(media_dir)
    except OSError:
        return None
    for entry in entries:
        if unicodedata.normalize("NFC", entry) == unicodedata.normalize("NFC", name):
            return entry
    for entry in entries:
        if _same_name(entry, name):
            return entry
    return None


def _is_a_pdf(path: Path) -> bool:
    if not path.name.lower().endswith(".pdf"):
        return False
    try:
        with open(path, "rb") as handle:
            return handle.read(len(PDF_SIGNATURE)) == PDF_SIGNATURE
    except OSError:
        return False


def resolve_print_pdf(value, printable: bool, visible: bool, media_dir) -> dict:
    """
    What the Print button on a page does, given its `printPdf:` value.

    Answers {"button": "pdf" | "handout" | "none", "file": the Media folder's
    spelling or None, "problem": "missing" | "notAPdf" | "hasAPath" | None,
    "typed": the name as the page gives it}. Reads the Media folder; never
    writes to it.
    """
    fallback = "handout" if printable else "none"
    if not visible:
        # Not on the site: nothing to resolve and nothing to tell anyone.
        return {"button": "none", "file": None, "problem": None, "typed": typed_name(value)}

    name = typed_name(value)
    if name is None:
        return {"button": fallback, "file": None, "problem": None, "typed": None}
    if "/" in name or "\\" in name:
        return {"button": fallback, "file": None, "problem": "hasAPath", "typed": name}

    found = _find_in_media(Path(media_dir), name)
    if found is None:
        if not name.lower().endswith(".pdf"):
            return {"button": fallback, "file": None, "problem": "notAPdf", "typed": name}
        return {"button": fallback, "file": None, "problem": "missing", "typed": name}
    if not _is_a_pdf(Path(media_dir) / found):
        return {"button": fallback, "file": None, "problem": "notAPdf", "typed": name}
    return {"button": "pdf", "file": found, "problem": None, "typed": name}


def _sync_folder(sources, target: Path) -> int:
    """
    Copy `sources` over `target` where the bytes differ; drop extras. Counts
    copies. `sources` is one folder or a list of them, LATER ones winning
    file by file (#455: the engine, then its overlay from support/gated) -
    one pass rather than a copy after the sync, which would delete the
    overlay as an extra and copy it again on every build.
    """
    if isinstance(sources, (str, Path)):
        sources = [sources]
    copied = 0
    target.mkdir(parents=True, exist_ok=True)
    wanted = {}
    for source in sources:
        source = Path(source)
        for item in sorted(source.rglob("*")):
            if item.is_file():
                wanted[item.relative_to(source)] = item
    for relative in sorted(wanted):
        item = wanted[relative]
        destination = target / relative
        if destination.is_file() and destination.read_bytes() == item.read_bytes():
            continue
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(item, destination)
        copied += 1
    for existing in sorted(target.rglob("*"), reverse=True):
        if existing.is_file() and existing.relative_to(target) not in wanted:
            existing.unlink()
    return copied


def install_gated_assets(output_dir, counts: dict, vendor_dir=None, printer=print, support_dir=None) -> dict:
    """
    Put each engine into the site's quartz/static when at least one page
    students can see asks for it, and take it out when none does.

    `counts` is {engine: pages asking}. Never raises: a missing engine is said
    in one plain line and the build carries on, because the Print button still
    prints without it (the browser lays the page out instead), a graph shows
    its text, and runnable code stays plain code.

    An engine with an overlay in SUPPORT_DIR/gated/<engine> (#455's worker)
    gets it laid over the vendor copy. The vendor folder IS the engine: an
    overlay alone installs nothing and is said as missing - except for a
    `prebuilt` language's engine (#493, OVERLAY_IS_THE_ENGINE), whose overlay
    is all there is.
    """
    vendor = Path(vendor_dir) if vendor_dir is not None else toolchain_paths.VENDOR_DIR
    support = Path(support_dir) if support_dir is not None else toolchain_paths.SUPPORT_DIR
    static = Path(output_dir) / "quartz" / "static"
    outcome = {}
    for engine in GATED_ASSETS:
        pages = int(counts.get(engine, 0) or 0)
        target = static / engine
        outcome[engine] = {"pages": pages, "copied": 0, "installed": False}
        try:
            if pages <= 0:
                if target.exists():
                    shutil.rmtree(target, ignore_errors=True)
                continue
            said = ENGINE_WORDS[engine]
            source = vendor / engine
            overlay = support / "gated" / engine
            if engine in OVERLAY_IS_THE_ENGINE:
                source = overlay
            if not source.is_dir():
                if target.exists():
                    shutil.rmtree(target, ignore_errors=True)
                printer(said["missing"].format(pages=pages))
                continue
            sources = [source]
            if overlay.is_dir() and overlay != source:
                sources.append(overlay)
            outcome[engine]["copied"] = _sync_folder(sources, target)
            outcome[engine]["installed"] = True
            noun = "page" if pages == 1 else "pages"
            printer(said["carried"].format(pages=pages, noun=noun))
        except OSError as error:
            printer(ENGINE_WORDS[engine]["failed"].format(error=error))
    return outcome



# ---- Runnable code (#455): contracts/shared-rules.json -> codeRunnerBlocks ----

def _runner_row(fence: str):
    row = RUNNER_LANGUAGES.get(fence)
    if row is None:
        return None
    return dict(row, fence=fence)


# The separators between the words of an info string, the SAME set as the
# site's (codeRunnerRule.ts, INFO_SPACE): tab, space and Unicode's space
# separators, NBSP among them (Option-Space on a Mac) - #455 review N2. Not
# str.split(), which also splits on \x1c-\x1f and \x85, and not JavaScript's
# \s, which adds U+FEFF: an explicit class is the only way both agree.
INFO_SPACE = re.compile("[\t \u00a0\u1680\u2000-\u200a\u202f\u205f\u3000]+")


def runner_for(lang, meta, opted_in):
    """
    Is a fence with this info string a runnable block (codeRunnerBlocks.fences)?
    Answers {"fence", "flags", "row"} or None. The info string (`lang`, then
    `meta`) is split on INFO_SPACE; the language is its first word, exactly;
    `run` must be one of the other words; flags are the row's own, exact,
    each once, in the row's order.
    """
    if not opted_in:
        return None
    words = [word for word in INFO_SPACE.split(f"{lang or ''} {meta or ''}") if word]
    if not words:
        return None
    row = _runner_row(words[0])
    if row is None:
        return None
    tokens = words[1:]
    if "run" not in tokens:
        return None
    flags = [flag for flag in row["flags"] if flag in tokens]
    return {"fence": row["fence"], "flags": flags, "row": row}


def runner_fences(body: str, opted_in) -> list:
    """
    The runnable blocks on one page's body, in order, read with the #313 fence
    rule (markdown_code.fenced_blocks): [{"fence", "flags", "line", "body"}].
    A block opened after a second container on a list marker's line is not
    runnable (codeRunnerBlocks.fences.pageShapes), on either side.
    """
    if not opts_in(opted_in) or ("```" not in body and "~~~" not in body):
        return []
    found = []
    for block in markdown_code.fenced_blocks(body):
        if block["nested"]:
            continue
        # The raw info string, split as the site splits it (INFO_SPACE).
        runner = runner_for(block["info"], "", True)
        if runner is None:
            continue
        found.append({"fence": runner["fence"], "flags": runner["flags"],
                      "line": block["line"], "body": block["body"]})
    return found


def runner_id(slug: str, fence: str, n: int) -> str:
    """`<slug>-<idPrefix>-<n>` (codeRunnerBlocks.ids)."""
    return f"{slug}-{RUNNER_LANGUAGES[fence]['idPrefix']}-{n}"


def runner_ids(slug: str, body: str) -> list:
    """The id of every runnable block on a page that opts in, n counting each
    language's blocks from 1. The site names them (codeRunner.ts); this is the
    same rule, for the contract's cases."""
    counts = {}
    ids = []
    for runner in runner_fences(body, True):
        counts[runner["fence"]] = counts.get(runner["fence"], 0) + 1
        ids.append(runner_id(slug, runner["fence"], counts[runner["fence"]]))
    return ids


def runner_engines_on_page(code_runner_value, body: str) -> set:
    """The engines one page makes its site carry: none unless it opts in
    (`codeRunner` is the boolean true) AND holds a runnable block of the
    language (codeRunnerBlocks.siteCarriesEngine). The caller applies the
    visibility rule."""
    engines = set()
    for runner in runner_fences(body, code_runner_value):
        engines.add(RUNNER_LANGUAGES[runner["fence"]]["engine"])
    return engines


def runner_words() -> dict:
    """What quartz/plantoir_code_runner.json carries, apart from `carried`."""
    rules = contracts.section("shared-rules", "codeRunnerBlocks")
    words = {}
    for key, text in rules["words"].items():
        if key != "note":
            words[key] = text
    return {
        "words": words,
        "limits": {
            "outputCharacters": rules["output"]["maxCharacters"],
            "loadSeconds": rules["loading"]["watchdogSeconds"],
            "debounceMilliseconds": rules["storage"]["debounceMilliseconds"],
            "editorLines": rules["editor"]["maxLines"],
            "indent": rules["editor"]["indent"],
            "answerCharacters": rules["liveInput"]["answerCharacters"],
        },
    }


def write_runner_words(output_dir, carried) -> bool:
    """
    Write quartz/plantoir_code_runner.json - the words and limits from the
    contract, and the engines this site carries - where the page's code
    (bundled into the site's script) and the transformer read it. Same input,
    same bytes; answers whether the file changed. If the contract cannot be
    read, the file still says which engines are carried, with no words, and
    the transformer then makes no block runnable.
    """
    try:
        content = runner_words()
    except Exception as error:  # a stale contract must not stop a build
        print(f"⚠️ Could not read the words for the code students run: {error}")
        content = {"words": {}, "limits": {}}
        carried = set()
    content["carried"] = sorted(carried)
    data = (json.dumps(content, indent=2, sort_keys=True, ensure_ascii=False) + "\n").encode("utf-8")
    path = Path(output_dir) / "quartz" / RUNNER_WORDS_FILE
    if path.is_file() and path.read_bytes() == data:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return True
