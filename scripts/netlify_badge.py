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

Extracted from scripts/deploy.py so both it and website/netlify_deploy.py
(the plantoir.app marketing site's own Netlify deploy, which is exposed to
the identical badge) can share one implementation instead of two copies
drifting apart. See WINDOWS-HANDOFF.md, "Suppressing Netlify's own ad badge
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


def _collect_inline_script_policy(public_dir: Path) -> tuple[list[str], list[str]]:
    """
    Walk every built HTML page and return:
      - sorted 'sha256-<base64>' entries, one per unique inline <script> body
      - sorted "scheme://host" entries for any cross-origin <script src="...">
        (same-origin scripts are covered by 'self' and need no entry)
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
        for src in _SCRIPT_SRC_RE.findall(text):
            if src.startswith("http://") or src.startswith("https://"):
                parsed = urllib.parse.urlparse(src)
                if parsed.scheme and parsed.netloc:
                    hosts.add(f"{parsed.scheme}://{parsed.netloc}")
    return sorted(f"'sha256-{h}'" for h in hashes), sorted(hosts)


def write_netlify_headers_file(public_dir: Path) -> int:
    """
    Write (or extend) public/_headers with a Content-Security-Policy that
    covers only script-src — never default-src — so nothing else about a
    page (images, fonts, styles, network requests) is restricted; this only
    ever narrows which inline JavaScript is allowed to run, which is exactly
    what suppresses Netlify's own badge script without touching anything a
    student would notice.

    Called on the Netlify path only, right before the delta-deploy manifest
    is built, so _headers rides along in the same SHA-1 manifest as every
    other page — no separate upload step. Returns the number of unique
    inline scripts the policy had to account for, purely for the deploy log.
    """
    hash_sources, host_sources = _collect_inline_script_policy(public_dir)
    policy = "script-src 'self' " + " ".join(hash_sources + host_sources) + ";"
    block = f"/*\n  Content-Security-Policy: {policy}\n"

    headers_path = public_dir / "_headers"
    try:
        existing = headers_path.read_text(encoding="utf-8") if headers_path.exists() else ""
        if existing.strip():
            headers_path.write_text(existing.rstrip("\n") + "\n" + block, encoding="utf-8")
        else:
            headers_path.write_text(block, encoding="utf-8")
    except OSError as e:
        # Never fail a deploy over this — the badge is cosmetic, the class
        # site (or the marketing site) publishing is not.
        print(f"⚠️ Could not write _headers file (badge may still appear): {e}")
        return 0

    return len(hash_sources)
