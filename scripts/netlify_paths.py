"""
Page addresses on Netlify (#628): the links in a page, made to name the
address Netlify actually serves the page from.

Netlify answers a PAGE asked for with any capital letter with a 301 to the
same path in lower case (measured 2026-10-23: `/Concepts/Functions` ->
`/concepts/functions`, commas kept), and serves every other file - pictures,
styles, scripts, data - in any case with a 200. Quartz writes every page link
with the page's own capitals, so every click on a Netlify site paid one
redirect before the page came back. Cloudflare Pages is case-sensitive, and a
folder publish and the preview serve the files as they are named, so nothing
there changes.

So, for Netlify ONLY, and in memory as the files are hashed and uploaded
(deploy.py -> _build_files_manifest): the PATH of every same-site page link is
lower-cased, ASCII letters only, and the page is marked with
`data-plantoir-paths="lowercase"` on its <html> tag, which tells the site's
router (build_site.py -> PLANTOIR-SERVED-CASE) to ask for the lower-case
address too when it builds a link itself (the explorer, search, the graph).
`public/` is never written: a Cloudflare destination in the same publish, a
folder publish and the preview see the bytes the build made.

What is rewritten, and nothing else (contracts/shared-rules.json ->
netlifyPageAddresses):
  * in an HTML page: `href` on <a> and <area>, `href` on
    <link rel="canonical">, and the url in <meta http-equiv="refresh"> (the
    last two are Quartz's alias pages, whose canonical link the site's
    fetchCanonical finds with a regex - only the URL's own characters move);
  * in the root `sitemap.xml`: every <loc>; in the root `index.xml` (the RSS
    feed): every <link>, never <guid> or <description>.

How, so the page cannot be damaged:
  * Only the RAW text of the attribute value is edited, in place: no value is
    rebuilt from the parser's decoded copy. A character reference (`&Eacute;`,
    `&amp;`, `&#35;`) is never touched, and one that stands for `?` or `#`
    ends the path as the character itself would.
  * A-Z become a-z and nothing else changes length or place, so every byte
    outside the edited spans - every inline script, the hashes the CSP lists,
    `data-slug` - is identical.
  * The query and the fragment are never touched (heading ids are
    case-sensitive), nor the two hex digits of a %-escape.
  * Same site only: a relative or root-relative link, or an absolute one on
    the section's own host. Never `#...`, `mailto:`, `data:`, `javascript:`,
    a protocol-relative `//...` or another host; never a page with a <base>.
  * Deterministic and idempotent, so the delta deploy's digests are stable:
    the first publish after this change re-uploads every page once, and
    later publishes are unchanged.

The failure direction is today's behaviour, never a broken link: a path this
misses, or lower-cases that did not need it, costs at most the one redirect
Netlify already sends, because Netlify answers any case.
"""
from __future__ import annotations

import html
import re
from html.parser import HTMLParser

MARKER_ATTRIBUTE = "data-plantoir-paths"
MARKER_VALUE = "lowercase"

_ASCII_CAPITALS_TO_SMALL = str.maketrans(
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz"
)
# Anything HTML might read as a character reference: left exactly as written.
_REFERENCE = re.compile(r"&[#A-Za-z0-9]+;?")
_PERCENT_ESCAPE = re.compile(r"%[0-9A-Fa-f]{2}")
_SCHEME = re.compile(r"^[A-Za-z][A-Za-z0-9+.\-]*:")
_ABSOLUTE_HTTP = re.compile(r"(?i)https?://([^/?#\s]*)")

# html.parser's own tolerant attribute pattern, so the spans found here are
# the attributes the parser reported.
_TAG_NAME = re.compile(r"<[a-zA-Z][^\t\n\r\f />\x00]*")
_ATTRIBUTE = re.compile(
    r"((?<=['\"\s/])[^\s/>][^\s/=>]*)(\s*=+\s*"
    r"('[^']*'|\"[^\"]*\"|(?!['\"])[^>\s]*))?(?:\s|/(?!>))*"
)
_REFRESH_URL = re.compile(r"(?is)^(\s*[0-9.]*\s*[;,]?\s*url\s*=\s*)(['\"]?)(.*)$")

_SITEMAP_LOC = re.compile(r"(<loc>)([^<]*)(</loc>)")
_FEED_LINK = re.compile(r"(<link>)([^<]*)(</link>)")


def own_host_of(base: str | None) -> str:
    """The host part of a section's address (`host`, `https://host/`,
    `host/sub`), lower-cased; "" when there is none."""
    if not base:
        return ""
    value = base.strip()
    value = re.sub(r"(?i)^https?://", "", value)
    host = re.split(r"[/?#]", value, maxsplit=1)[0]
    return host.lower()


def _lower_path_text(raw: str) -> str:
    """ASCII capitals to small in raw path text, up to the query or the
    fragment, leaving references and %-escapes exactly as written."""
    pieces: list[str] = []
    position = 0
    while position < len(raw):
        character = raw[position]
        if character == "?" or character == "#":
            pieces.append(raw[position:])
            return "".join(pieces)
        if character == "&":
            reference = _REFERENCE.match(raw, position)
            if reference is not None:
                stands_for = html.unescape(reference.group(0))
                if stands_for == "?" or stands_for == "#":
                    pieces.append(raw[position:])
                    return "".join(pieces)
                pieces.append(reference.group(0))
                position = reference.end()
                continue
        if character == "%":
            escape = _PERCENT_ESCAPE.match(raw, position)
            if escape is not None:
                pieces.append(escape.group(0))
                position = escape.end()
                continue
        pieces.append(character.translate(_ASCII_CAPITALS_TO_SMALL))
        position += 1
    return "".join(pieces)


def served_href(raw: str, own_host: str = "") -> str:
    """The raw text of one link, as Netlify serves it (the contract's
    netlifyPageAddresses.cases). Anything that is not a same-site link comes
    back exactly as it went in."""
    decoded = html.unescape(raw).strip()
    if decoded == "" or decoded.startswith("#"):
        return raw
    if decoded.startswith("//") or decoded.startswith("\\"):
        return raw
    leading = len(raw) - len(raw.lstrip())
    body = raw[leading:]
    if _SCHEME.match(decoded):
        if not own_host:
            return raw
        absolute = _ABSOLUTE_HTTP.match(body)
        if absolute is None or absolute.group(1).lower() != own_host.lower():
            return raw
        cut = absolute.end()
        return raw[:leading] + body[:cut] + _lower_path_text(body[cut:])
    return raw[:leading] + _lower_path_text(body)


def _served_refresh(raw: str, own_host: str) -> str:
    """The url in a <meta http-equiv="refresh"> content: `0; url=...`."""
    parts = _REFRESH_URL.match(raw)
    if parts is None:
        return raw
    prefix, quote, rest = parts.group(1), parts.group(2), parts.group(3)
    tail = ""
    if quote and rest.endswith(quote):
        rest, tail = rest[:-1], quote
    return prefix + quote + served_href(rest, own_host) + tail


class _StartTags(HTMLParser):
    """Every start tag's offset, raw text and decoded attributes."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.tags: list[tuple[tuple[int, int], str, str, list]] = []

    def handle_starttag(self, tag, attrs):
        self.tags.append((self.getpos(), self.get_starttag_text() or "", tag, attrs))

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)


def _offsets_of_lines(text: str) -> list[int]:
    starts = [0]
    for index, character in enumerate(text):
        if character == "\n":
            starts.append(index + 1)
    return starts


def _value_spans(raw_tag: str):
    """(name lower-cased, start, end) of each attribute VALUE in a raw start
    tag, quotes excluded; the first of a repeated name only."""
    name_match = _TAG_NAME.match(raw_tag)
    if name_match is None:
        return []
    seen: set[str] = set()
    spans = []
    position = name_match.end()
    while position < len(raw_tag):
        attribute = _ATTRIBUTE.match(raw_tag, position)
        if attribute is None or attribute.end() == position:
            position += 1
            continue
        name = attribute.group(1).lower()
        if attribute.group(3) is not None and name not in seen:
            start = attribute.start(3)
            end = attribute.end(3)
            value = attribute.group(3)
            if value[:1] in ("'", '"'):
                start += 1
                end -= 1
            spans.append((name, start, end))
        seen.add(name)
        position = attribute.end()
    return spans


def served_html(text: str, own_host: str = "") -> str:
    """A page's text as Netlify serves it: its same-site page links in lower
    case and the marker on its <html> tag. A file with no <html> tag (a
    teacher's own HTML in Media/) has its links rewritten and no marker."""
    parser = _StartTags()
    try:
        parser.feed(text)
        parser.close()
    except Exception:
        return text
    line_starts = _offsets_of_lines(text)
    edits: list[tuple[int, int, str]] = []
    marked = False
    has_base = False
    link_edits: list[tuple[int, int, str]] = []
    for (line, column), raw_tag, tag, attrs in parser.tags:
        if line - 1 >= len(line_starts):
            continue
        offset = line_starts[line - 1] + column
        if not raw_tag or text[offset:offset + len(raw_tag)] != raw_tag:
            continue
        decoded = {}
        for name, value in attrs:
            decoded.setdefault(name.lower(), value if value is not None else "")
        if tag == "base" and "href" in decoded:
            has_base = True
        if tag == "html" and not marked:
            marked = True
            if MARKER_ATTRIBUTE not in decoded:
                name_end = offset + _TAG_NAME.match(raw_tag).end()
                edits.append((name_end, name_end, f' {MARKER_ATTRIBUTE}="{MARKER_VALUE}"'))
            continue
        wanted = None
        if tag in ("a", "area"):
            wanted = "href"
        elif tag == "link" and "canonical" in (decoded.get("rel") or "").lower().split():
            wanted = "href"
        elif tag == "meta" and (decoded.get("http-equiv") or "").strip().lower() == "refresh":
            wanted = "content"
        if wanted is None:
            continue
        for name, start, end in _value_spans(raw_tag):
            if name != wanted:
                continue
            raw_value = raw_tag[start:end]
            if wanted == "content":
                served = _served_refresh(raw_value, own_host)
            else:
                served = served_href(raw_value, own_host)
            if served != raw_value:
                link_edits.append((offset + start, offset + end, served))
    if not has_base:
        edits.extend(link_edits)
    if not edits:
        return text
    pieces: list[str] = []
    position = 0
    for start, end, replacement in sorted(edits):
        pieces.append(text[position:start])
        pieces.append(replacement)
        position = end
    pieces.append(text[position:])
    return "".join(pieces)


def _served_feed(text: str, pattern: re.Pattern, own_host: str) -> str:
    def served(match: re.Match) -> str:
        return match.group(1) + served_href(match.group(2), own_host) + match.group(3)
    return pattern.sub(served, text)


def rewrites(relative: str) -> bool:
    """Whether a built file (its path inside public/, with /) is one this
    module may rewrite."""
    lowered = relative.lower()
    if lowered.endswith(".html") or lowered.endswith(".htm"):
        return True
    return relative in ("sitemap.xml", "index.xml")


def served_file(relative: str, data: bytes, own_host: str = "") -> bytes:
    """A built file's bytes as Netlify is sent them. The same object comes
    back when nothing changes; a file that is not UTF-8 is never touched."""
    if not rewrites(relative):
        return data
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        return data
    if relative == "sitemap.xml":
        served = _served_feed(text, _SITEMAP_LOC, own_host)
    elif relative == "index.xml":
        served = _served_feed(text, _FEED_LINK, own_host)
    else:
        served = served_html(text, own_host)
    if served == text:
        return data
    return served.encode("utf-8")
