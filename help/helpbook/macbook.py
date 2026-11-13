"""The Mac form: a real Apple Help Book, `Plantoir.help`.

Info.plist carries exactly the keys of decision 2 (Mario Guzman's article and
its sample project). Pages go in Contents/Resources/en.lproj; both indexes are
built there by `hiutil`, then READ BACK: every page id must be an anchor, and
each anchor must resolve to its own page (measured 2026-11-13: every anchor on
a page resolves to that page's FIRST anchor, so a stray earlier anchor would
send a Help button to the wrong place).
"""

from __future__ import annotations

import json
import plistlib
import shutil
import subprocess
from pathlib import Path
from typing import Any, Dict, List, Set

from . import (
    BOOK_IDENTIFIER,
    BOOK_TITLE,
    CONTENTS_ANCHOR,
    CS_INDEX_NAME,
    LANGUAGE_FOLDER,
    LSM_INDEX_NAME,
)
from .folders import build_atomically, folder_size, human_size, place_picture
from .problems import HelpError
from .render import CONTENTS_FILE, HelpSource, PageRenderer

ASSETS_FOR_THE_BOOK = ["tokens.css", "help.css"]


def info_plist(app_version: str) -> Dict[str, Any]:
    return {
        "CFBundleIdentifier": BOOK_IDENTIFIER,
        "CFBundleDevelopmentRegion": "en",
        "CFBundlePackageType": "BNDL",
        "CFBundleSignature": "hbwr",
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": BOOK_TITLE,
        "CFBundleShortVersionString": app_version,
        "CFBundleVersion": app_version,
        "HPDBookType": "3",
        "HPDBookTitle": BOOK_TITLE,
        "HPDBookAccessPath": CONTENTS_FILE,
        "HPDBookCSIndexPath": CS_INDEX_NAME,
        "HPDBookIndexPath": LSM_INDEX_NAME,
        "HPDBookKBProduct": "plantoir",
    }


def find_hiutil() -> str:
    found = shutil.which("hiutil")
    if found is None:
        raise HelpError("--mac needs hiutil, which comes with macOS; build the Mac book on a Mac")
    return found


def run_hiutil(hiutil: str, arguments: List[str], folder: Path) -> str:
    completed = subprocess.run(
        [hiutil] + arguments,
        cwd=str(folder),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        universal_newlines=True,
    )
    if completed.returncode != 0:
        raise HelpError("hiutil " + " ".join(arguments) + " exited " + str(completed.returncode) + ":\n" + completed.stdout)
    return completed.stdout


def verify_indexes(hiutil: str, language_folder: Path, anchors: List[str]) -> None:
    """Reads the built Spotlight index back (always with -I corespotlight; the
    LSM index cannot be inspected, so it is checked for existence and size)."""
    lsm: Path = language_folder / LSM_INDEX_NAME
    if not lsm.exists() or lsm.stat().st_size == 0:
        raise HelpError("hiutil wrote no " + LSM_INDEX_NAME)
    listed_text: str = run_hiutil(hiutil, ["-I", "corespotlight", "-Af", CS_INDEX_NAME], language_folder)
    listed: Set[str] = set()
    for line in listed_text.split("\n"):
        if line.strip() != "":
            listed.add(line.strip())
    missing: List[str] = []
    for anchor in anchors:
        if anchor not in listed:
            missing.append(anchor)
    if len(missing) > 0:
        raise HelpError("the Help index lists no anchor for: " + ", ".join(missing))
    mapping_text: str = run_hiutil(hiutil, ["-I", "corespotlight", "-Df", CS_INDEX_NAME], language_folder)
    try:
        mapping: Dict[str, Any] = plistlib.loads(mapping_text.encode("utf-8"))
    except Exception as error:  # plistlib raises several types
        raise HelpError("cannot read hiutil -Df's anchor map: " + str(error))
    wrong: List[str] = []
    for anchor in anchors:
        expected: str = "/" + (CONTENTS_FILE if anchor == CONTENTS_ANCHOR else anchor + ".html") + "#" + anchor
        targets: Any = mapping.get(anchor, [])
        if not isinstance(targets, list) or expected not in targets:
            wrong.append(anchor + " -> " + repr(targets) + " (expected " + expected + ")")
    if len(wrong) > 0:
        raise HelpError("an anchor does not open its own page:\n  " + "\n  ".join(wrong))


def build_mac(source: HelpSource, renderer: PageRenderer, out: Path, app_version: str) -> str:
    """Writes the book; returns the summary line. `renderer` is a "mac"
    renderer that has run render_all() and whose checks have passed."""
    hiutil: str = find_hiutil()
    anchors: List[str] = [CONTENTS_ANCHOR]
    for page in source.pages:
        anchors.append(page.id)
    assets_dir: Path = source.help_dir / "assets"
    old_pictures: Path = out / "Contents" / "Resources" / "pictures"

    def write(book: Path) -> None:
        contents: Path = book / "Contents"
        resources: Path = contents / "Resources"
        language_folder: Path = resources / LANGUAGE_FOLDER
        language_folder.mkdir(parents=True)
        with (contents / "Info.plist").open("wb") as handle:
            plistlib.dump(info_plist(app_version), handle)
        (language_folder / "InfoPlist.strings").write_text(
            'HPDBookTitle = "' + BOOK_TITLE + '";\n', encoding="utf-8"
        )
        (language_folder / CONTENTS_FILE).write_text(renderer.contents_html, encoding="utf-8")
        for page in source.pages:
            (language_folder / (page.id + ".html")).write_text(renderer.pages_html[page.id], encoding="utf-8")
        (resources / "assets").mkdir()
        for name in ASSETS_FOR_THE_BOOK:
            shutil.copy2(str(assets_dir / name), str(resources / "assets" / name))
        for name in sorted(renderer.pictures_used):
            place_picture(source.help_dir / "pictures" / name, resources / "pictures" / name, old_pictures / name)
        (resources / "anchors.json").write_text(json.dumps(anchors[1:], indent=1) + "\n", encoding="utf-8")
        run_hiutil(hiutil, ["-I", "corespotlight", "-Caf", CS_INDEX_NAME, "-vv", "."], language_folder)
        run_hiutil(hiutil, ["-I", "lsm", "-Caf", LSM_INDEX_NAME, "-vv", "."], language_folder)
        verify_indexes(hiutil, language_folder, anchors)

    build_atomically(out, write)
    return "Plantoir.help: " + str(len(anchors) - 1) + " pages, " + human_size(folder_size(out)) + " (" + str(folder_size(out)) + " bytes)"
