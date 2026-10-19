#!/usr/bin/env python3
"""
Suppress Netlify's own "Powered by Netlify" ad badge on a built site.

Netlify can inject its own badge (and a matching pre-launch toolbar) into
any public site on a free-tier project — see
https://docs.netlify.com/manage/projects/powered-by-netlify-badge/. There
is no API field to turn it off (its own OpenAPI spec has nothing named
"badge" anywhere on the Site object), and asking every teacher to find the
toggle in their own Netlify dashboard, per section, forever, is not a real
fix. Netlify's docs name the one lever that IS automatic: the badge only
renders through an inline <script> injected at their edge, and a
Content-Security-Policy whose script-src omits 'unsafe-inline' makes the
browser refuse to run it — "Neither the badge nor the pre-launch toolbar
appears, and no other project functionality is affected."

The risk with a blanket policy like that is breaking a site's OWN inline
scripts. Rather than hand-maintain a fixed allow-list (which would go
stale the moment Quartz changes its bundling, or miss a teacher who embeds
a <script> of their own), this scans the actual built HTML at deploy time
and allows exactly what is really there, by content hash. That is a
behaviour, not a fixed list — it holds even if Quartz's own scripts change
on a version bump, and it does not depend on knowing in advance what a
teacher chose to embed.

'unsafe-eval' is included deliberately, and is a SEPARATE keyword from the
'unsafe-inline' this whole policy exists to omit — Netlify's badge needs
'unsafe-inline' specifically ("the script runs in an inline frame"), so
adding 'unsafe-eval' does not let it back in. It has to be there anyway:
Quartz's own Explorer sidebar (patches/explorer.inline.ts) builds its
sort/filter/map functions from `data-data-fns` JSON via
`new Function("return " + source)()` — a `new Function` call is exactly
what 'unsafe-eval' governs. Without it, every page's sidebar silently
stayed empty on Netlify (Cloudflare, with no CSP at all, was unaffected) —
found by A/B testing the two deploy targets side by side and reading the
real `unhandledrejection` the browser threw: "Refused to evaluate a string
as JavaScript because 'unsafe-eval' ... is not an allowed source of
script." The three inline scripts this module hash-allows all checked out
fine; the break was in vendored Quartz code this policy never touched
directly, which is why hash-checking each inline script's content missed
it — the violation was a *capability* (eval), not a script identity.

The policy covers the code a page's scripts load or import, not only the
code it links (#594). `script-src` governs a dynamic `import()` exactly as it
governs a `<script src>`, and Quartz draws Mermaid diagrams from an inline
module script that does
`await import("https://cdnjs.cloudflare.com/ajax/libs/mermaid/11.4.0/mermaid.esm.min.mjs")`.
Until 2026-10-19 only `<script src>` hosts were collected, so cdnjs was
never allowed and every Netlify site showed its diagrams as source text
since the policy existed (Cloudflare, with no policy, drew them). So the
host of every absolute https:// URL that is the argument of an `import(...)`
is collected too, and so is the https:// specifier of a static `import …
from`, a bare `import "…"` and an `export … from` — from every inline script
on every page, and from every
.js / .mjs file in the built site (Quartz's postscript.js and prescript.js,
and anything a teacher put in static/). Only module specifiers: a
`fetch("https://...")` is a network request, not a script source, and
must not widen script-src.

Extracted from scripts/deploy.py so both it and website/netlify_deploy.py
(the plantoir.app marketing site's own Netlify deploy, which is exposed to
the identical badge) can share one implementation instead of two copies
drifting apart. See documentation/07-deployment.md, "Suppressing Netlify's own ad badge
(entry 300)", for the full design writeup and the two rejected alternatives.
"""
import base64
import hashlib
import re
import urllib.parse
from pathlib import Path

_INLINE_SCRIPT_RE = re.compile(
    r"<script\b(?![^>]*\bsrc\s*=)[^>]*>(.*?)</script>", re.IGNORECASE | re.DOTALL
)
_SCRIPT_SRC_RE = re.compile(r'<script\b[^>]*\bsrc\s*=\s*["\']([^"\']+)["\']', re.IGNORECASE)
# The argument of a dynamic import(): an absolute https:// URL in single or
# double quotes, or in backticks with no ${ in it (a template with a
# substitution names no fixed host). `import(` must not follow a letter, a
# digit, `_`, `$` or `.`, so `index.import(` and `reimport(` are not it.
_DYNAMIC_IMPORT_RE = re.compile(
    r"""(?<![\w$.])import\s*\(\s*(["'`])(https://[^"'`\s]+)\1""", re.IGNORECASE
)
# The specifier of a STATIC module import or re-export: `import x from
# "https://…"`, `import {a, b} from "https://…"`, `import * as m from
# "https://…"`, the bare `import "https://…"`, and `export … from "https://…"`.
# A quoted specifier that starts with https:// after `from`, or straight
# after a bare `import`; nothing else. `import.meta` and same-origin
# specifiers ("./x.mjs") never match.
_STATIC_IMPORT_RE = re.compile(
    r"""(?:(?<![\w$.])import\s*|\bfrom\s*)(["'])(https://[^"'\s]+)\1"""
)


def _origin_of(url: str) -> str | None:
    """`scheme://host` of an absolute http(s) URL, or None."""
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme in ("http", "https") and parsed.netloc:
        return f"{parsed.scheme}://{parsed.netloc}"
    return None


def _imported_origins(script_text: str) -> set[str]:
    """The `scheme://host` of every absolute https:// module `script_text`
    loads or imports: the argument of a dynamic import(), and the specifier
    of a static `import … from`, a bare `import "…"` or an `export … from`.
    A same-origin import ("./x.mjs", "/static/x.mjs") is covered by 'self'
    and gives nothing."""
    origins: set[str] = set()
    for match in _DYNAMIC_IMPORT_RE.finditer(script_text):
        quote = match.group(1)
        url = match.group(2)
        if quote == "`" and "${" in url:
            continue
        origin = _origin_of(url)
        if origin is not None:
            origins.add(origin)
    for match in _STATIC_IMPORT_RE.finditer(script_text):
        origin = _origin_of(match.group(2))
        if origin is not None:
            origins.add(origin)
    return origins


def _collect_inline_script_policy(public_dir: Path) -> tuple[list[str], list[str]]:
    """
    Walk every built HTML page and every .js / .mjs file, and return:
      - sorted 'sha256-<base64>' entries, one per unique inline <script> body
      - sorted "scheme://host" entries for every cross-origin place a page
        loads script from: the src of a <script src="https://...">, and the
        absolute https:// argument of a dynamic import(...), or specifier of
        a static import / export … from, in an inline
        script or in one of the site's own .js / .mjs files (#594 — Quartz
        imports Mermaid from cdnjs that way). Same-origin scripts and
        imports are covered by 'self' and need no entry.
    Returns ([], []) rather than raising if public_dir has no HTML yet — the
    CSP is a nice-to-have, never a reason to fail a deploy.
    """
    hashes: set[str] = set()
    hosts: set[str] = set()
    for html_file in public_dir.rglob("*.html"):
        try:
            text = html_file.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        for match in _INLINE_SCRIPT_RE.finditer(text):
            body = match.group(1)
            if not body.strip():
                continue
            digest = hashlib.sha256(body.encode("utf-8")).digest()
            hashes.add(base64.b64encode(digest).decode("ascii"))
            hosts.update(_imported_origins(body))
        for src in _SCRIPT_SRC_RE.findall(text):
            if src.startswith("http://") or src.startswith("https://"):
                origin = _origin_of(src)
                if origin is not None:
                    hosts.add(origin)
    for pattern in ("*.js", "*.mjs"):
        for script_file in public_dir.rglob(pattern):
            try:
                text = script_file.read_text(encoding="utf-8", errors="ignore")
            except OSError:
                continue
            hosts.update(_imported_origins(text))
    return sorted(f"'sha256-{h}'" for h in hashes), sorted(hosts)


# The comment line above the block this module writes. Netlify's _headers
# reads a line starting with # as a comment, so the marker changes nothing a
# browser is sent; it is how the NEXT deploy finds this block and replaces it
# rather than appending a second one beside it (#462).
MANAGED_MARKER = (
    "# Plantoir: keeps Netlify's own ad badge off. Rewritten on every deploy; "
    "edit the lines outside this block, not these."
)
_OUR_POLICY_PREFIX = "  Content-Security-Policy: script-src 'self' 'unsafe-eval'"


def _is_our_policy_pair(lines: list[str], index: int) -> bool:
    """True when lines[index:index+2] are `/*` and the policy line we write."""
    return (
        index + 1 < len(lines)
        and lines[index].rstrip() == "/*"
        and lines[index + 1].startswith(_OUR_POLICY_PREFIX)
    )


def _without_our_blocks(text: str) -> str:
    """`text` with every block this module wrote taken out, the rest kept.

    Two shapes are ours. A MARKED block: the marker line, then `/*` and the
    headers indented under it, of which our policy line (wherever it sits
    among them) is ours; if the marker is not followed by `/*` at all, only
    the marker goes. And an OLD unmarked block, appended before the marker
    existed: a `/*` line, our policy line, and nothing else indented under
    it. Any header somebody else put under a `/*` keeps its `/*`: an
    unmarked block with one is kept whole, and a marked one loses only the
    marker and our policy line, so their header is never left under
    whatever path came before. Blank-line runs are collapsed and
    the end is trimmed, so the result depends only on the lines that are
    kept.
    """
    lines = text.splitlines()
    kept: list[str] = []
    index = 0
    while index < len(lines):
        line = lines[index]
        if line.rstrip() == MANAGED_MARKER:
            index += 1
            if index < len(lines) and lines[index].rstrip() == "/*":
                # Our `/*` and every header indented under it. Our policy
                # line goes wherever it sits among them (somebody may have
                # put a header above it); any other header stays, under its
                # own `/*`, so it is never left under the path before.
                theirs: list[str] = []
                after = index + 1
                while after < len(lines) and lines[after].startswith((" ", "\t")):
                    if not lines[after].startswith(_OUR_POLICY_PREFIX):
                        theirs.append(lines[after])
                    after += 1
                if theirs:
                    kept.append(lines[index])
                    kept.extend(theirs)
                index = after
            continue
        if _is_our_policy_pair(lines, index):
            after = index + 2
            if after >= len(lines) or not lines[after].startswith((" ", "\t")):
                index = after
                continue
        kept.append(line)
        index += 1

    collapsed: list[str] = []
    for line in kept:
        if not line.strip() and (not collapsed or not collapsed[-1].strip()):
            continue
        collapsed.append(line.rstrip() if not line.strip() else line)
    return "\n".join(collapsed).rstrip()


def write_netlify_headers_file(public_dir: Path) -> int:
    """
    Write public/_headers with a Content-Security-Policy that covers only
    script-src — never default-src — so nothing else about a page (images,
    fonts, styles, network requests) is restricted; this only ever narrows
    which inline JavaScript is allowed to run, which is exactly what
    suppresses Netlify's own badge script without touching anything a
    student would notice.

    The hosts it allows are every host a page's scripts load or import code from, not
    only the hosts it links with <script src> (#594): Quartz's Mermaid
    loader is an inline module that does
    `await import("https://cdnjs.cloudflare.com/.../mermaid.esm.min.mjs")`,
    and script-src governs that import, so without cdnjs in the policy every
    diagram on a Netlify site stayed as its source text.

    Lines somebody else put in an existing _headers are kept. The block this
    function writes is MARKED and REPLACED on every call, never appended
    again (#462): two `/*` policies would both be enforced, so an old block
    still holding an old script's hash would block that script the day it
    changed. Old unmarked blocks from before the marker are recognised by
    their exact shape and replaced too. Written with LF line endings, so the
    same site gives the same bytes from a Mac and from Windows.

    Called on the Netlify path only, right before the delta-deploy manifest
    is built, so _headers rides along in the same SHA-1 manifest as every
    other page — no separate upload step. Returns the number of unique
    inline scripts the policy had to account for, purely for the deploy log.
    """
    hash_sources, host_sources = _collect_inline_script_policy(public_dir)
    policy = "script-src 'self' 'unsafe-eval' " + " ".join(hash_sources + host_sources) + ";"
    block = f"{MANAGED_MARKER}\n/*\n  Content-Security-Policy: {policy}\n"

    headers_path = public_dir / "_headers"
    try:
        existing = headers_path.read_text(encoding="utf-8") if headers_path.exists() else ""
        kept = _without_our_blocks(existing)
        text = f"{kept}\n\n{block}" if kept else block
        with open(headers_path, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(text)
    except OSError as e:
        # Never fail a deploy over this — the badge is cosmetic, deploying
        # the class site (or plantoir.app) is not.
        print(f"⚠️ Could not write _headers file (badge may still appear): {e}")
        return 0

    return len(hash_sources)
