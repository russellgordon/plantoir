"""The web form: the same pages as a plain folder of `<id>.html` files.

Flat, with relative links, so it works from `file://` (Windows will open it
that way) and on plantoir.app at `/help/<id>.html`, where these become
addresses that must never move once deployed. Search reads
`assets/search-index.js`, a script rather than a fetched file, so it works
from `file://` too. The assistant section is left out unless
help/facts.json -> assistantOnTheWeb is true (decision 12, #804).
"""

from __future__ import annotations

import json
import shutil
from pathlib import Path
from typing import Any, Dict, List, Set

from .checks import readable_texts
from .folders import build_atomically, folder_size, human_size, place_picture
from .problems import HelpError
from .render import CONTENTS_FILE, HelpSource, PageRenderer

ASSETS_FOR_THE_WEB = ["tokens.css", "help.css", "search.js"]


def web_page_ids(source: HelpSource) -> Set[str]:
    included: Set[str] = set()
    for page in source.pages:
        if page.assistant and not source.registries.assistant_on_the_web:
            continue
        included.add(page.id)
    return included


def search_index(source: HelpSource, included: Set[str]) -> str:
    entries: List[Dict[str, Any]] = []
    for page in source.pages:
        if page.id not in included or not page.indexed:
            continue
        body: List[str] = []
        for _line, text in readable_texts(source, page):
            body.append(text)
        entries.append(
            {
                "id": page.id,
                "title": page.title,
                "description": page.description,
                "keywords": page.keywords,
                "text": " ".join(" ".join(body).split()),
            }
        )
    return "window.PLANTOIR_HELP_INDEX = " + json.dumps(entries, ensure_ascii=False, indent=1) + ";\n"


def release_refusals(source: HelpSource, renderer: PageRenderer, included: Set[str]) -> List[str]:
    """What stops the web copy going live: any stub, any placeholder picture
    (for website/build.py --deploy to call when #840 P6 integrates /help/)."""
    refusals: List[str] = []
    for page in source.pages:
        if page.id in included and page.is_stub:
            refusals.append(page.id + " is still a stub")
    for scene_id in renderer.placeholders:
        refusals.append("scene " + scene_id + " is still a placeholder")
    return refusals


def build_web(source: HelpSource, renderer: PageRenderer, out: Path, release: bool) -> str:
    """`renderer` is a "web" renderer that has run render_all() and whose checks have passed."""
    included: Set[str] = renderer.included_ids
    pages_html: Dict[str, str] = renderer.pages_html
    contents_html: str = renderer.contents_html
    if release:
        refusals: List[str] = release_refusals(source, renderer, included)
        if len(refusals) > 0:
            shown: List[str] = refusals[:20]
            more: str = ""
            if len(refusals) > 20:
                more = "\n  … and " + str(len(refusals) - 20) + " more"
            raise HelpError(
                "the web copy is not ready to go live (" + str(len(refusals)) + " refusals):\n  "
                + "\n  ".join(shown) + more
            )
    assets_dir: Path = source.help_dir / "assets"
    old_pictures: Path = out / "pictures"

    def write(folder: Path) -> None:
        (folder / CONTENTS_FILE).write_text(contents_html, encoding="utf-8")
        for page_id in sorted(pages_html):
            (folder / (page_id + ".html")).write_text(pages_html[page_id], encoding="utf-8")
        (folder / "assets").mkdir()
        for name in ASSETS_FOR_THE_WEB:
            shutil.copy2(str(assets_dir / name), str(folder / "assets" / name))
        (folder / "assets" / "search-index.js").write_text(search_index(source, included), encoding="utf-8")
        for name in sorted(renderer.pictures_used):
            place_picture(source.help_dir / "pictures" / name, folder / "pictures" / name, old_pictures / name)

    build_atomically(out, write)
    return "web copy: " + str(len(pages_html)) + " pages, " + human_size(folder_size(out))
