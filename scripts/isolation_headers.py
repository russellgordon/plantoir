"""
Live input (#583): which pages of a built site may be cross-origin isolated,
and the `_headers` block that isolates them on Netlify and Cloudflare Pages.

A runnable block on an ISOLATED page asks for each line of input as the
program reads it (the page's script: codeRunner.inline.ts; the rules:
contracts/shared-rules.json -> codeRunnerBlocks.liveInput). A page is isolated
when its host sends it `Cross-Origin-Opener-Policy: same-origin` and
`Cross-Origin-Embedder-Policy: require-corp`, and the engine's own folder
`require-corp` too. Those headers BREAK what a page shows from other websites
that do not opt in - a YouTube frame, a hotlinked picture, GeoGebra's script -
so a page gets them only when it can ask and carries none of that
(codeRunnerBlocks.isolation.notLive, ruling Q1); every other page keeps the
input box, and the publish says why on a `plantoir: note:` line when one of
its blocks reads input.

Read from the BUILT site (public/), like netlify_badge: the transformer
(codeRunner.ts) marks a block that can ask with data-runner-asks="input" or
"edit", so nothing here needs the language table. The preview's server
decides the same way per request (support/quartz/cli/plantoirIsolation.mjs);
both run the contract's `isolation.cases`, so the two cannot drift.

Called by deploy.py for Netlify (before the badge rule's block) and for
Cloudflare (before wrangler), never for a folder publish. The block between
the contract's two markers is REPLACED on every publish, never appended (the
#462 lesson); lines somebody else wrote are kept.

How each host matches a page's path was MEASURED on the test site
(2026-10-17, documentation/06-quartz-customizations.md -> I11), and the two
differ: Cloudflare wants every character but A-Z a-z 0-9 _ . - ~ percent-
encoded; Netlify wants the path as a browser sends it, lower-cased
(`isolation.pathCases`).
"""
from __future__ import annotations

import json
import re
import urllib.parse
from html.parser import HTMLParser
from pathlib import Path

import contracts

# Reasons a page that can ask is not isolated, strongest first: the one named
# on the note line when there are several.
REASONS = ("frame", "picture", "other")
_REASON_WORD = {"frame": "notLiveFrame", "picture": "notLivePicture", "other": "notLiveOther"}

# What a browser percent-encodes in a URL's path (WHATWG's path set, plus
# everything outside printable ASCII): the form a browser asks Netlify for.
_BROWSER_ENCODES = set(' "#<>?`{}')

_CSS_URL = re.compile(r"""url\(\s*(['"]?)(.*?)\1\s*\)""", re.IGNORECASE | re.DOTALL)
_LINK_RELS_THAT_FETCH = {"stylesheet", "preload", "modulepreload"}


def _rules() -> dict:
    return contracts.section("shared-rules", "codeRunnerBlocks", "isolation")


def _host_of(url: str):
    """The host of a cross-origin URL (lower case), or None for the site's own."""
    value = url.strip()
    lowered = value.lower()
    if lowered.startswith("//"):
        value = "https:" + value
    elif not (lowered.startswith("http://") or lowered.startswith("https://")):
        return None
    try:
        return (urllib.parse.urlsplit(value).hostname or "").lower()
    except ValueError:
        return ""


class _PageReader(HTMLParser):
    """Reads one built page: whether a block can ask, and what would break."""

    def __init__(self, allowed_hosts):
        super().__init__(convert_charrefs=True)
        self.allowed = {host.lower() for host in allowed_hosts}
        self.asks = set()
        self.reasons = set()
        self._in_style = False

    def _cross(self, url) -> bool:
        if url is None:
            return False
        host = _host_of(url)
        return host is not None and host not in self.allowed

    def _srcset_cross(self, srcset) -> bool:
        if not srcset:
            return False
        for candidate in srcset.split(","):
            words = candidate.strip().split()
            if words and self._cross(words[0]):
                return True
        return False

    def _css_cross(self, css) -> bool:
        for match in _CSS_URL.finditer(css or ""):
            if self._cross(match.group(2)):
                return True
        return False

    def handle_starttag(self, tag, attrs):
        self._tag(tag, attrs)
        if tag == "style":
            self._in_style = True

    def handle_startendtag(self, tag, attrs):
        self._tag(tag, attrs)

    def handle_endtag(self, tag):
        if tag == "style":
            self._in_style = False

    def handle_data(self, data):
        # Script text is never read (HTMLParser hands it over as data, like a
        # style's); a style's text is read for url(...).
        if self._in_style and self._css_cross(data):
            self.reasons.add("other")

    def _tag(self, tag, attrs):
        values = {}
        for name, value in attrs:
            values.setdefault(name.lower(), value if value is not None else "")
        if tag == "div" and "plantoir-runner" in (values.get("class") or "").split():
            if values.get("data-runner-asks") in ("input", "edit"):
                self.asks.add(values["data-runner-asks"])
        if tag in ("iframe", "frame", "embed", "object"):
            self.reasons.add("frame")
        elif tag == "img":
            if self._cross(values.get("src")) or self._srcset_cross(values.get("srcset")):
                self.reasons.add("picture")
        elif tag == "source":
            if self._srcset_cross(values.get("srcset")):
                self.reasons.add("picture")
            elif self._cross(values.get("src")):
                self.reasons.add("frame")
        elif tag == "video":
            if self._cross(values.get("src")):
                self.reasons.add("frame")
            if self._cross(values.get("poster")):
                self.reasons.add("picture")
        elif tag in ("audio", "track", "script"):
            if self._cross(values.get("src")):
                self.reasons.add("other")
        elif tag == "input":
            if (values.get("type") or "").lower() == "image" and self._cross(values.get("src")):
                self.reasons.add("picture")
        elif tag == "image":
            if self._cross(values.get("href")) or self._cross(values.get("xlink:href")):
                self.reasons.add("picture")
        elif tag == "link":
            rels = set((values.get("rel") or "").lower().split())
            if rels & _LINK_RELS_THAT_FETCH and self._cross(values.get("href")):
                self.reasons.add("other")
        if "style" in values and self._css_cross(values.get("style")):
            self.reasons.add("other")


def page_verdict(html: str, allowed_hosts=None) -> dict:
    """
    One built page's verdict (codeRunnerBlocks.isolation.cases):
    {"verdict": "none" | "live" | "frame" | "picture" | "other",
     "readsInput": bool}. "none": no block can ask, so the page gets nothing;
    "live": it gets the headers; otherwise the strongest reason it does not.
    """
    if allowed_hosts is None:
        allowed_hosts = _rules()["allowedHosts"]
    reader = _PageReader(allowed_hosts)
    reader.feed(html)
    reader.close()
    reads_input = "input" in reader.asks
    if not reader.asks:
        return {"verdict": "none", "readsInput": False}
    for reason in REASONS:
        if reason in reader.reasons:
            return {"verdict": reason, "readsInput": reads_input}
    return {"verdict": "live", "readsInput": reads_input}


def _page_path(relative: str) -> str:
    """public/<relative> -> the address a student opens: `a/b.html` -> `/a/b`,
    `a/index.html` -> `/a/`, `index.html` -> `/`."""
    if relative == "index.html":
        return "/"
    if relative.endswith("/index.html"):
        return "/" + relative[: -len("index.html")]
    return "/" + relative[: -len(".html")]


def _browser_form(path: str) -> str:
    out = []
    for character in path:
        if ord(character) > 0x7E or ord(character) < 0x21 or character in _BROWSER_ENCODES:
            out.append("".join(f"%{byte:02X}" for byte in character.encode("utf-8")))
        else:
            out.append(character)
    return "".join(out)


def page_paths(relative: str, host: str) -> list:
    """
    The rule paths one built page gets on `host` (isolation.hosts,
    isolation.pathCases): Cloudflare matches the fully percent-encoded path,
    case-sensitively; Netlify the path as a browser asks for it, after its
    own 301 to lower case. A `*` (a splat on both hosts) gets nothing.
    """
    path = _page_path(relative)
    if "*" in path:
        return []
    if host == "cloudflare":
        return [urllib.parse.quote(path, safe="/")]
    lowered = _browser_form(path.lower())
    as_is = _browser_form(path)
    if as_is.lower() != lowered.lower():
        return [lowered, as_is]
    return [lowered]


def scan_site(public_dir) -> list:
    """Every built page with a block that can ask, in path order:
    [{"file": "a/b.html", "verdict", "readsInput"}]."""
    public = Path(public_dir)
    allowed = _rules()["allowedHosts"]
    found = []
    for page in sorted(public.rglob("*.html")):
        relative = page.relative_to(public).as_posix()
        if relative == "404.html":
            continue
        try:
            html = page.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        if "plantoir-runner" not in html:
            continue
        verdict = page_verdict(html, allowed)
        if verdict["verdict"] != "none":
            found.append({"file": relative, **verdict})
    return found


def _rule_lines(text: str) -> int:
    """How many rules (path lines) a _headers text holds."""
    count = 0
    for line in text.splitlines():
        if line.strip() and not line[:1].isspace() and not line.lstrip().startswith("#"):
            count += 1
    return count


def without_our_block(text: str, markers: dict) -> str:
    """`text` with the block between our markers taken out (an unended block
    runs to the next `# Plantoir:` line or the end); the rest kept, blank-line
    runs collapsed and the end trimmed."""
    lines = text.splitlines()
    kept = []
    index = 0
    while index < len(lines):
        if lines[index].rstrip() == markers["begin"]:
            index += 1
            while index < len(lines):
                line = lines[index].rstrip()
                if line == markers["end"]:
                    index += 1
                    break
                if line.startswith("# Plantoir:"):
                    break
                index += 1
            continue
        kept.append(lines[index])
        index += 1
    collapsed = []
    for line in kept:
        if not line.strip() and (not collapsed or not collapsed[-1].strip()):
            continue
        collapsed.append(line.rstrip() if not line.strip() else line)
    return "\n".join(collapsed).rstrip()


def write_isolation_headers(public_dir, host: str) -> dict:
    """
    Write (or take out) the live-input block in public/_headers for `host`
    ("netlify" or "cloudflare"). Answers {"live": [files], "notLive":
    [{"file", "verdict", "readsInput"}], "capped": [files]}. Nothing is
    written when no page can be isolated - the block is only taken out.
    """
    rules = _rules()
    public = Path(public_dir)
    markers = rules["markers"]
    scanned = scan_site(public)
    live = [item for item in scanned if item["verdict"] == "live"]
    not_live = [item for item in scanned if item["verdict"] != "live"]
    # Pages whose blocks read input first, then the rest; each in path order.
    live.sort(key=lambda item: (not item["readsInput"], item["file"]))

    headers_path = public / "_headers"
    existing = headers_path.read_text(encoding="utf-8") if headers_path.is_file() else ""
    kept = without_our_block(existing, markers)

    engine_rules = []
    for folder in rules["engineFolders"]:
        if (public / folder).is_dir():
            engine_rules.append("/" + folder + "/*")
    room = None
    if host == "cloudflare":
        room = rules["hosts"]["cloudflareMostRules"] - _rule_lines(kept) - len(engine_rules)

    page_rules = []
    written = []
    capped = []
    for item in live:
        paths = page_paths(item["file"], host)
        if not paths:
            continue
        if room is not None and len(page_rules) + len(paths) > room:
            capped.append(item["file"])
            continue
        page_rules.extend(paths)
        written.append(item["file"])

    if written:
        lines = [markers["begin"]]
        for path in engine_rules:
            lines.append(path)
            for name, value in rules["headers"]["engine"].items():
                lines.append(f"  {name}: {value}")
        for path in page_rules:
            lines.append(path)
            for name, value in rules["headers"]["page"].items():
                lines.append(f"  {name}: {value}")
        lines.append(markers["end"])
        block = "\n".join(lines) + "\n"
        text = f"{kept}\n\n{block}" if kept else block
    else:
        text = kept + "\n" if kept else ""

    if text or headers_path.is_file():
        if text:
            with open(headers_path, "w", encoding="utf-8", newline="\n") as handle:
                handle.write(text)
        else:
            headers_path.unlink()
    return {"live": written, "notLive": not_live, "capped": capped}


def _source_names(public_dir) -> dict:
    """slug -> the page's file in the course (Quartz's contentIndex.json), so a
    note names the file a teacher knows."""
    index = Path(public_dir) / "static" / "contentIndex.json"
    try:
        data = json.loads(index.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    names = {}
    for slug, entry in data.items():
        if isinstance(entry, dict) and isinstance(entry.get("filePath"), str):
            names[slug] = entry["filePath"]
    return names


def note_lines(public_dir, outcome: dict) -> list:
    """The `plantoir: note:` lines for one publish: each page that keeps the
    box although a block reads input, saying why; and how many pages the
    Cloudflare limit left with the box."""
    words = contracts.section("shared-rules", "codeRunnerBlocks", "words")
    names = _source_names(public_dir)
    lines = []
    for item in outcome["notLive"]:
        if not item["readsInput"]:
            continue
        slug = item["file"][: -len(".html")]
        name = names.get(slug, slug + ".md")
        what = words[_REASON_WORD[item["verdict"]]]
        lines.append(f"plantoir: note: {name}: " + words["notLiveBecause"].replace("{what}", what))
    if outcome["capped"]:
        lines.append("plantoir: note: " + words["notLiveCapped"].replace("{count}", str(len(outcome["capped"]))))
    return lines


def publish_headers(public_dir, host: str, printer=print) -> dict:
    """deploy.py's one call: write the block for `host`, then say what a
    teacher should know. A contract that cannot be read leaves the site as it
    was (no block written): a stale copy must not stop a publish."""
    try:
        outcome = write_isolation_headers(public_dir, host)
        notes = note_lines(public_dir, outcome)
    except Exception as error:  # never fail a publish over this
        printer(f"⚠️ Could not set up the pages whose code asks for input as it runs: {error}")
        return {"live": [], "notLive": [], "capped": []}
    if outcome["live"]:
        printer(f" Setting up {len(outcome['live'])} page(s) so their code can ask students for input as it runs…")
    for line in notes:
        printer(line)
    return outcome
