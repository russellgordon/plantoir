"""Reading help/ and turning each page into HTML, for the Mac book and the web
copy alike. A page with no file under help/pages/ is a STUB: its outline title,
its question, and a fixed "being written" box.
"""

from __future__ import annotations

import datetime
import html
import re
import struct
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

from . import BOOK_TITLE, CONTENTS_ANCHOR, LANGUAGE_TAG, PLACEHOLDER_HEADING, STUB_SENTENCE
from .frontmatter import read_front_matter
from .markdown import parse_body, split_inline, walk_blocks
from .problems import HelpError, Problems
from .tokens import Registries, read_json
from .words import WordRules

CONTENTS_FILE = "index.html"
INTRO_PAGE = "index"


class Page:
    """One outline entry, with its source file when there is one."""

    def __init__(self, outline_entry: Dict[str, Any], section: Dict[str, Any]) -> None:
        self.id: str = str(outline_entry.get("id", ""))
        self.entry = outline_entry
        self.section = section
        self.file: Optional[str] = None
        self.fields: Dict[str, Any] = {}
        self.blocks: List[Dict[str, Any]] = []

    @property
    def title(self) -> str:
        return str(self.entry.get("title", ""))

    @property
    def question(self) -> str:
        return str(self.entry.get("question", ""))

    @property
    def is_stub(self) -> bool:
        return self.file is None

    @property
    def assistant(self) -> bool:
        return self.entry.get("assistant") is True

    @property
    def indexed(self) -> bool:
        if "indexed" in self.fields:
            return self.fields["indexed"] is True
        return self.entry.get("indexed", True) is True

    @property
    def scene_ids(self) -> List[str]:
        return list(self.entry.get("sceneIds", []))

    @property
    def description(self) -> str:
        if self.is_stub:
            return self.question
        return str(self.fields.get("description", ""))

    @property
    def keywords(self) -> List[str]:
        value = self.fields.get("keywords", [])
        if isinstance(value, list):
            return value
        return []


class HelpSource:
    """Everything under help/, read once, plus the repository files it is checked against."""

    def __init__(self, repo: Path, help_dir: Path, problems: Problems, today: Optional[datetime.date] = None) -> None:
        self.repo = repo
        self.help_dir = help_dir
        self.problems = problems
        self.today = today if today is not None else datetime.date.today()
        self.outline: Dict[str, Any] = read_json(help_dir / "outline.json")
        self.registries = Registries(repo, help_dir, self.today)
        self.words = WordRules.load(repo, help_dir)
        self.pages: List[Page] = []
        self.pages_by_id: Dict[str, Page] = {}
        self.intro: Optional[Page] = None
        for section in self.outline.get("sections", []):
            for entry in section.get("pages", []):
                page = Page(entry, section)
                self.pages.append(page)
                if page.id not in self.pages_by_id:
                    self.pages_by_id[page.id] = page
        self._read_page_files()

    def _read_page_files(self) -> None:
        pages_dir: Path = self.help_dir / "pages"
        if not pages_dir.exists():
            return
        for path in sorted(pages_dir.iterdir()):
            if path.name.startswith("."):
                continue
            relative: str = "help/pages/" + path.name
            if path.suffix != ".md" or not path.is_file():
                self.problems.fail(relative, None, "help/pages/ holds <id>.md files only")
                continue
            text: str = path.read_text(encoding="utf-8")
            fields, body, first_line = read_front_matter(relative, text, self.problems)
            page_id: str = path.stem
            if page_id == INTRO_PAGE:
                intro = Page({"id": INTRO_PAGE, "title": BOOK_TITLE, "indexed": False}, {})
                intro.file = relative
                intro.fields = fields
                intro.blocks = parse_body(relative, body, first_line, self.problems)
                self.intro = intro
                continue
            if "id" not in fields:
                self.problems.fail(relative, 1, "front matter carries `id`")
            elif fields["id"] != page_id:
                self.problems.fail(relative, 1, "`id: " + str(fields["id"]) + "` differs from the file name " + page_id)
            page = self.pages_by_id.get(page_id)
            if page is None:
                self.problems.fail(relative, 1, page_id + " is not a page in help/outline.json")
                continue
            page.file = relative
            page.fields = fields
            page.blocks = parse_body(relative, body, first_line, self.problems)

    def page_file_label(self, page: Page) -> str:
        if page.file is not None:
            return page.file
        return "help/outline.json (" + page.id + ")"


# MARK: pictures

def webp_size(path: Path) -> Tuple[int, int]:
    """A WebP's pixel width and height, read from its header (stdlib only)."""
    data: bytes = path.read_bytes()[:40]
    if len(data) < 30 or data[0:4] != b"RIFF" or data[8:12] != b"WEBP":
        raise HelpError(str(path) + " is not a WebP file")
    chunk: bytes = data[12:16]
    if chunk == b"VP8X":
        width = 1 + int.from_bytes(data[24:27], "little")
        height = 1 + int.from_bytes(data[27:30], "little")
        return width, height
    if chunk == b"VP8L":
        if data[20] != 0x2F:
            raise HelpError(str(path) + " has a bad lossless WebP signature")
        bits: int = struct.unpack("<I", data[21:25])[0]
        return 1 + (bits & 0x3FFF), 1 + ((bits >> 14) & 0x3FFF)
    if chunk == b"VP8 ":
        width_bits, height_bits = struct.unpack("<HH", data[26:30])
        return width_bits & 0x3FFF, height_bits & 0x3FFF
    raise HelpError(str(path) + " has an unknown WebP chunk " + repr(chunk))


# MARK: the page renderer

def slug(text: str) -> str:
    lowered: str = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    if lowered == "":
        return "part"
    return lowered


class PageRenderer:
    """Renders pages for one form: "mac" (the Help book) or "web"."""

    def __init__(self, source: HelpSource, form: str, included_ids: Set[str]) -> None:
        self.source = source
        self.form = form
        self.included_ids = included_ids
        self.problems = source.problems
        self.registries = source.registries
        self.pictures_used: Set[str] = set()
        self.placeholders: List[str] = []
        self.prefix: str = "../" if form == "mac" else ""

    # MARK: inline

    def inline(self, text: str, page: Page, line: int, platform: str) -> str:
        file: str = self.source.page_file_label(page)
        parts: List[str] = []
        for kind, value in split_inline(text):
            if kind == "text":
                parts.append(html.escape(str(value), quote=False))
            elif kind == "code":
                parts.append("<code>" + html.escape(str(value), quote=False) + "</code>")
            elif kind == "token":
                parts.append(self.registries.render_inline(str(value), platform, file, line, self.problems))
            elif kind == "bold":
                parts.append("<strong>" + self.inline(str(value), page, line, platform) + "</strong>")
            elif kind == "italic":
                parts.append("<em>" + self.inline(str(value), page, line, platform) + "</em>")
            else:
                words, target = value
                parts.append(self.link(words, target, page, line, platform))
        return "".join(parts)

    def link(self, words: str, target: str, page: Page, line: int, platform: str) -> str:
        file: str = self.source.page_file_label(page)
        inner: str = self.inline(words, page, line, platform)
        if target.startswith("page:"):
            page_id: str = target[5:]
            if page_id not in self.source.pages_by_id:
                self.problems.fail(file, line, "links to page:" + page_id + ", which is not in help/outline.json")
                return inner
            if page_id not in self.included_ids:
                # Left out of this form (the assistant section on the web): the words stay, the link goes.
                return inner
            return '<a href="' + page_id + '.html">' + inner + "</a>"
        if re.match(r"^https://[A-Za-z0-9.-]+\.[A-Za-z]{2,}(?::\d+)?(?:[/?#][^\s<>\"]*)?$", target) is not None:
            return '<a href="' + html.escape(target) + '">' + inner + "</a>"
        self.problems.fail(file, line, "a link goes to page:<id> or to a well-formed https:// address, not " + repr(target))
        return inner

    # MARK: blocks

    def blocks(self, blocks: List[Dict[str, Any]], page: Page, platform: str, page_has_windows: bool) -> str:
        output: List[str] = []
        heading_ids: Set[str] = set()
        self._render_blocks(blocks, page, platform, page_has_windows, output, heading_ids)
        return "\n".join(output)

    def _render_blocks(
        self,
        blocks: List[Dict[str, Any]],
        page: Page,
        platform: str,
        page_has_windows: bool,
        output: List[str],
        heading_ids: Set[str],
    ) -> None:
        for block in blocks:
            kind: str = block["kind"]
            line: int = block["line"]
            if kind == "heading":
                level: int = block["level"]
                base: str = slug(re.sub(r"\{\{[^}]*\}\}|`[^`]*`", "", block["text"]))
                anchor: str = base
                counter: int = 2
                while anchor in heading_ids:
                    anchor = base + "-" + str(counter)
                    counter += 1
                heading_ids.add(anchor)
                output.append(
                    "<h" + str(level) + ' id="' + anchor + '">' + self.inline(block["text"], page, line, platform)
                    + "</h" + str(level) + ">"
                )
            elif kind == "paragraph":
                texts: List[str] = []
                for number, text in block["lines"]:
                    texts.append(self.inline(text, page, number, platform))
                output.append("<p>" + "\n".join(texts) + "</p>")
            elif kind == "list":
                output.append(self.list_html(block, page, platform))
            elif kind == "code":
                css: str = "language-" + block["language"]
                if block["wrap"]:
                    css += " wrap"
                output.append('<pre class="' + css + '"><code>' + html.escape(block["text"], quote=False) + "</code></pre>")
            elif kind == "table":
                output.append(self.table_html(block, page, platform))
            elif kind == "note":
                inner: List[str] = []
                self._render_blocks(block["children"], page, platform, page_has_windows, inner, heading_ids)
                output.append('<aside class="note">' + "\n".join(inner) + "</aside>")
            elif kind == "picture":
                output.append(self.picture_html(block, page, platform))
            elif kind == "platform":
                run_platform: str = block["platform"]
                inner_output: List[str] = []
                if self.form == "mac":
                    if run_platform == "mac":
                        self._render_blocks(block["children"], page, "mac", page_has_windows, inner_output, heading_ids)
                        output.extend(inner_output)
                    else:
                        # Not shown in the Mac book; rendered only to check its tokens.
                        PageRenderer(self.source, "web", self.included_ids)._render_blocks(
                            block["children"], page, "windows", page_has_windows, inner_output, set()
                        )
                    continue
                self._render_blocks(block["children"], page, run_platform, page_has_windows, inner_output, heading_ids)
                attributes: str = 'data-platform="' + run_platform + '"'
                if run_platform == "mac" and not page_has_windows:
                    attributes += ' data-shared="true"'
                output.append("<div " + attributes + ">\n" + "\n".join(inner_output) + "\n</div>")

    def list_html(self, block: Dict[str, Any], page: Page, platform: str) -> str:
        tag: str = "ol" if block["ordered"] else "ul"
        items: List[str] = []
        for item in block["items"]:
            texts: List[str] = []
            for number, text in item["lines"]:
                texts.append(self.inline(text, page, number, platform))
            child: str = ""
            if item["children"] is not None:
                child = "\n" + self.list_html(item["children"], page, platform)
            items.append("<li>" + "\n".join(texts) + child + "</li>")
        return "<" + tag + ">\n" + "\n".join(items) + "\n</" + tag + ">"

    def table_html(self, block: Dict[str, Any], page: Page, platform: str) -> str:
        rows: List[str] = []
        header_cells: List[str] = []
        index: int = 0
        for cell in block["header"]:
            align: str = block["aligns"][index] if index < len(block["aligns"]) else ""
            style: str = ' class="align-' + align + '"' if align != "" else ""
            header_cells.append('<th scope="col"' + style + ">" + self.inline(cell, page, block["line"], platform) + "</th>")
            index += 1
        rows.append("<thead><tr>" + "".join(header_cells) + "</tr></thead>")
        body_rows: List[str] = []
        for number, cells in block["rows"]:
            cell_html: List[str] = []
            column: int = 0
            for cell in cells:
                align = block["aligns"][column] if column < len(block["aligns"]) else ""
                style = ' class="align-' + align + '"' if align != "" else ""
                cell_html.append("<td" + style + ">" + self.inline(cell, page, number, platform) + "</td>")
                column += 1
            body_rows.append("<tr>" + "".join(cell_html) + "</tr>")
        rows.append("<tbody>" + "\n".join(body_rows) + "</tbody>")
        return '<table class="bordered">\n' + "\n".join(rows) + "\n</table>"

    def picture_html(self, block: Dict[str, Any], page: Page, platform: str) -> str:
        file: str = self.source.page_file_label(page)
        scene_id: str = block["scene"]
        line: int = block["line"]
        alt: str = html.escape(block["alt"])
        if scene_id not in page.scene_ids:
            self.problems.fail(file, line, "{{picture:" + scene_id + "}} is not one of this page's outline sceneIds")
        scene: Optional[Dict[str, Any]] = self.registries.scenes.get(scene_id)
        if scene is None:
            self.problems.fail(file, line, "{{picture:" + scene_id + "}}: no such scene in help/scenes.json")
            return ""
        self.registries.used["scene"].add(scene_id)
        if scene.get("page") != page.id:
            self.problems.fail(file, line, "scene " + scene_id + " belongs to page " + str(scene.get("page")) + " in help/scenes.json")
        pictures_dir: Path = self.source.help_dir / "pictures"
        light: Path = pictures_dir / (scene_id + "-light.webp")
        dark: Path = pictures_dir / (scene_id + "-dark.webp")
        if scene.get("awaiting_capture") is not True:
            if not light.exists() or not dark.exists():
                self.problems.fail(file, line, "scene " + scene_id + " is not awaiting capture, but its two pictures are not both in help/pictures/")
            else:
                self.pictures_used.add(light.name)
                self.pictures_used.add(dark.name)
                width, height = webp_size(light)
                return (
                    "<figure>\n<picture>\n"
                    '<source media="(prefers-color-scheme: dark)" srcset="' + self.prefix + "pictures/" + dark.name + '">\n'
                    '<img src="' + self.prefix + "pictures/" + light.name + '" alt="' + alt + '" width="'
                    + str(width // 2) + '" height="' + str(height // 2) + '">\n'
                    "</picture>\n</figure>"
                )
        self.placeholders.append(scene_id)
        shows: str = str(scene.get("shows", ""))
        labels: List[str] = []
        for label in scene.get("labels", []):
            labels.append("<li>" + html.escape(str(label)) + "</li>")
        parts: List[str] = [
            '<figure class="placeholder" aria-label="' + alt + '">',
            '<div class="placeholder-box">',
            '<p class="placeholder-heading">' + html.escape(PLACEHOLDER_HEADING) + ": <code>" + html.escape(scene_id) + "</code></p>",
        ]
        if shows.strip() == "":
            self.problems.warn(file, line, "scene " + scene_id + " has no `shows` yet: its placeholder shows the scene id only")
        else:
            parts.append('<p class="placeholder-shows">' + html.escape(shows) + "</p>")
        if len(labels) > 0:
            parts.append('<ul class="placeholder-labels">' + "".join(labels) + "</ul>")
        parts.append("</div>")
        parts.append("</figure>")
        return "\n".join(parts)

    # MARK: whole pages

    def head(self, title: str, keywords: List[str], description: str, indexed: bool) -> str:
        robots: str = "index, anchors" if indexed else "anchors"
        lines: List[str] = [
            "<!DOCTYPE html>",
            '<html lang="' + LANGUAGE_TAG + '">',
            "<head>",
            '<meta charset="utf-8">',
            "<title>" + html.escape(title) + "</title>",
            '<meta name="keywords" content="' + html.escape(", ".join(keywords)) + '">',
            '<meta name="description" content="' + html.escape(description) + '">',
            '<meta name="robots" content="' + robots + '">',
            '<meta name="color-scheme" content="light dark">',
            '<meta name="viewport" content="width=device-width, initial-scale=1">',
            '<link rel="stylesheet" href="' + self.prefix + 'assets/tokens.css">',
            '<link rel="stylesheet" href="' + self.prefix + 'assets/help.css">',
            "</head>",
        ]
        return "\n".join(lines)

    def top_bar(self) -> str:
        parts: List[str] = ['<header class="top">', '<a class="home" href="' + CONTENTS_FILE + '">' + html.escape(BOOK_TITLE) + "</a>"]
        if self.form == "web":
            parts.append(
                '<form class="search" role="search" action="' + CONTENTS_FILE + '" method="get">'
                '<label for="help-search">Search Help</label>'
                '<input type="search" id="help-search" name="q">'
                '<button type="submit">Search</button>'
                "</form>"
            )
        parts.append("</header>")
        return "\n".join(parts)

    def tail(self) -> str:
        if self.form == "web":
            return (
                '<script src="assets/search-index.js"></script>\n'
                '<script src="assets/search.js"></script>\n</body>\n</html>\n'
            )
        return "</body>\n</html>\n"

    def page_has_windows(self, page: Page) -> bool:
        for block in walk_blocks(page.blocks):
            if block["kind"] == "platform" and block["platform"] == "windows":
                return True
        return False

    def render_page(self, page: Page) -> str:
        parts: List[str] = [
            self.head(page.title, page.keywords, page.description, page.indexed),
            "<body>",
            '<a name="' + html.escape(page.id) + '"></a>',
            self.top_bar(),
            "<main>",
            "<h1>" + html.escape(page.title) + "</h1>",
        ]
        if page.is_stub:
            parts.append('<p class="question">' + html.escape(page.question) + "</p>")
            parts.append('<div class="being-written" role="note"><p>' + html.escape(STUB_SENTENCE) + "</p></div>")
        else:
            parts.append(self.blocks(page.blocks, page, "mac", self.page_has_windows(page)))
        parts.append("</main>")
        return "\n".join(parts) + "\n" + self.tail()

    def render_all(self) -> None:
        """Renders every included page and the contents once, keeping the
        HTML; rendering is also what checks every token and link."""
        self.pages_html: Dict[str, str] = {}
        for page in self.source.pages:
            if page.id in self.included_ids:
                self.pages_html[page.id] = self.render_page(page)
        self.contents_html: str = self.render_contents()

    def render_contents(self) -> str:
        """The table of contents: section titles and page titles only. The
        sections' purposes are the planner's words, not Help prose (decision
        5); an introduction appears once help/pages/index.md is written."""
        parts: List[str] = [
            self.head(BOOK_TITLE, [], "", False),
            "<body>",
            '<a name="' + CONTENTS_ANCHOR + '"></a>',
            self.top_bar(),
            "<main>",
            "<h1>" + html.escape(BOOK_TITLE) + "</h1>",
        ]
        if self.form == "web":
            parts.append('<section id="help-results" aria-live="polite" hidden></section>')
        if self.source.intro is not None:
            intro = self.source.intro
            parts.append(self.blocks(intro.blocks, intro, "mac", False))
        for section in self.source.outline.get("sections", []):
            items: List[str] = []
            for entry in section.get("pages", []):
                page_id: str = str(entry.get("id", ""))
                if page_id not in self.included_ids:
                    continue
                items.append('<li><a href="' + html.escape(page_id) + '.html">' + html.escape(str(entry.get("title", ""))) + "</a></li>")
            if len(items) == 0:
                continue
            parts.append('<section class="contents-section">')
            parts.append("<h2>" + html.escape(str(section.get("title", ""))) + "</h2>")
            parts.append("<ul>\n" + "\n".join(items) + "\n</ul>")
            parts.append("</section>")
        parts.append("</main>")
        return "\n".join(parts) + "\n" + self.tail()
