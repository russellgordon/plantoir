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

#455 adds `codeRunner` to GATED_ASSETS beside `printable`.
"""

import os
import shutil
import unicodedata
from pathlib import Path

import toolchain_paths

# Which engine each opt-in key pulls into a site. The engine's folder under
# VENDOR_DIR, and under the site's quartz/static, has the same name.
GATED_ASSETS = {"pagedjs": "printable"}

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


def _sync_folder(source: Path, target: Path) -> int:
    """Copy `source` over `target` where the bytes differ; drop extras. Counts copies."""
    copied = 0
    target.mkdir(parents=True, exist_ok=True)
    wanted = set()
    for item in sorted(source.rglob("*")):
        if not item.is_file():
            continue
        relative = item.relative_to(source)
        wanted.add(relative)
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


def install_gated_assets(output_dir, counts: dict, vendor_dir=None, printer=print) -> dict:
    """
    Put each engine into the site's quartz/static when at least one page
    students can see asks for it, and take it out when none does.

    `counts` is {engine: pages asking}. Never raises: a missing engine is said
    in one plain line and the build carries on, because the Print button still
    prints without it (the browser lays the page out instead).
    """
    vendor = Path(vendor_dir) if vendor_dir is not None else toolchain_paths.VENDOR_DIR
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
            source = vendor / engine
            if not source.is_dir():
                printer(f"⚠️ {pages} page(s) ask to be printable, but this copy of Plantoir "
                        f"is missing its print layout, so they will print without it.")
                continue
            outcome[engine]["copied"] = _sync_folder(source, target)
            outcome[engine]["installed"] = True
            noun = "page" if pages == 1 else "pages"
            printer(f"🖨️  This site carries the print layout for {pages} {noun}.")
        except OSError as error:
            printer(f"⚠️ Could not set up the print layout: {error}")
    return outcome
