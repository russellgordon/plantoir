#!/usr/bin/env python3
"""
GeoGebra's engine for a class website (#578, stage 1): the ONE recipe that
turns GeoGebra's own download into what a site carries.

    python3 geogebra_engine.py adapt <geogebra-math-apps-bundle.zip> <out folder>
    python3 geogebra_engine.py version     # the pinned version, which the
                                           # Dockerfile checks against its own

Run by the Dockerfile into /opt/vendor/geogebra, and by Windows'
fetch-runtime.ps1 into runtime\\vendor\\geogebra, so both platforms carry
byte-identical files. Standard library only.

What it does, and refuses:

1. checks the zip's SHA-256 against ZIP_SHA256 (the pin in
   contracts/toolchain.json -> pins -> geogebra; test_geogebra_engine.py holds
   the two together) and refuses any other zip;
2. keeps `deployggb.js`, `HTML5/5.0/css/` and `HTML5/5.0/web3d/` - the web3d
   codebase serves every app (classic, graphing, geometry, 3d) - minus the 83
   language files (`web3d/js/properties_keys_*.js`, 23 MB; English is built
   into the engine and a missing language falls back to it), the sign-in
   callbacks (`web3d/html/`), the service worker and the module loader nothing
   loads (`sworker-locked.js`, `web3d.nocache.mjs`). `web/`, `webSimple/` and
   `GeoGebra.html` are left out: `web` is the non-3D duplicate, `webSimple`
   has no toolbar or algebra view;
3. makes SIX exact string replacements (REPLACEMENTS, below), each of which
   must match EXACTLY ONCE in the file as it stands at that step - zero or two
   matches means GeoGebra changed the file and the reasoning behind the
   replacement no longer holds, so the step refuses rather than guessing;
4. writes a README.txt naming the version, the licence, the attribution the
   licence asks for, what was removed and what was changed;
5. writes everything into a temporary folder beside <out> and renames it into
   place only when every step has succeeded, so a refusal writes nothing.

Why the replacements exist (measured 2026-10-23, Chromium and WebKit, under
the Netlify policy a published site is sent - scripts/netlify_badge.py:
`script-src 'self' 'unsafe-eval' <hashes>`): the stock engine never loads.
GWT's loader injects its 7.9 MB main file and its deferred fragments as INLINE
script text, GeoGebra adds nine resources to <head> as inline scripts, and its
zip library starts a `blob:` worker - all four refused by that policy. The
replacements make each of those a same-origin <script src> or an eval, which
the policy allows; and the loader's hidden frame goes under <html> rather than
<body>, because Quartz's page navigation replaces <body> and took the frame
with it (Chromium then loaded no second sketch until a reload).
REJECTED: widening the policy (`worker-src blob:` alone is not enough, and the
inline scripts need 'unsafe-inline', which the hashes disable and which would
let Netlify's badge back in); pinning ~10 inline hashes (fonts vary, and one
missed hash is broken lettering, silently); a run-time patch of
head.appendChild (it cannot reach the first two, which run in GWT's frame
before any of our code). documentation/02-docker-image.md ->
"/opt/vendor/geogebra" has the numbers.
"""

from __future__ import annotations

import hashlib
import os
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path, PurePosixPath

# The pin: contracts/toolchain.json -> pins -> geogebra (`value`, `sha256`).
# A literal, because the image layer that runs this has no contracts/ yet (it
# is copied later, so a contract edit does not download 33 MB again); the
# test holds the two together.
VERSION = "5.4.933.1"
ZIP_NAME = "geogebra-math-apps-bundle-5-4-933-1.zip"
ZIP_SHA256 = "409095947e065bce5bde20b8a6d56a60e2b3cb3cce6947e817a802513515ec0c"

# Everything in the bundle sits under this folder.
BUNDLE_ROOT = "GeoGebra/"
WEB3D = "HTML5/5.0/web3d/"
NOCACHE = WEB3D + "web3d.nocache.js"
CACHE_JS = WEB3D + "29EB0586CD5B749E221F6BB019F1B206.cache.js"

# The largest file a bundle may hold, and all of them together, uncompressed:
# the measured largest is 10,185,294 bytes and the whole bundle 121 MB, so a
# zip that claims more is not the one we pinned (the SHA-256 already says so;
# this keeps a bad zip from filling the disk before that is noticed).
MAX_FILE_BYTES = 64 * 1024 * 1024
MAX_TOTAL_BYTES = 256 * 1024 * 1024

# The six replacements, in the order they are applied. Each is (file, what it
# is for, the exact text GeoGebra ships, what it becomes).
REPLACEMENTS = (
    (NOCACHE, "the main file loads as a same-origin <script src>, never as inline text",
     "if(location.protocol.startsWith(cb)&&!g){",
     "if(false){"),
    (NOCACHE, "a deferred fragment (CAS, 3D) is run with eval, never as an inline <script>",
     "web3d.__installRunAsyncCode=function(a){var b=u();var c=b.body;var d=b.createElement(_);"
     "d.language=hb;d.text=a;c.appendChild(d);c.removeChild(d)}",
     "web3d.__installRunAsyncCode=function(a){u().defaultView.eval(a)}"),
    (NOCACHE, "the loader's hidden frame goes under <html>, which Quartz's page navigation keeps "
              "(it replaces <body>, and took the frame with it)",
     "o.body.appendChild(a)",
     "o.documentElement.appendChild(a)"),
    (CACHE_JS, "a resource GeoGebra adds to <head> is kept inert (its id still answers 'already added?') "
               "and run with eval, never as an inline <script>",
     "b?(d.text='(function(define){'+a.Bh()+'})()'):(d.text=a.Bh());hrd.head.appendChild(d)}}",
     "b?(d.text='(function(define){'+a.Bh()+'})()'):(d.text=a.Bh());d.type='text/x-plantoir-geogebra';"
     "hrd.head.appendChild(d);$wnd.eval(d.text)}}"),
    (CACHE_JS, "saving a sketch zips on the page, never in a blob: worker",
     "_e.Zip=vn,_e.zip=dn,_e.zipSync=gn;",
     "_e.Zip=vn,_e.zip=function(d,o,c){c||(c=o,o={});var r,x=null;try{r=gn(d,o)}catch(e){x=e}"
     "setTimeout(function(){x?c(x,null):c(null,r)},0);return function(){}},_e.zipSync=gn;"),
    (CACHE_JS, "opening a sketch unzips on the page, never in a blob: worker",
     "_e.unzip=zn,_e.unzipSync=kn;",
     "_e.unzip=function(d,o,c){c||(c=o,o={});var r,x=null;try{r=kn(d,o)}catch(e){x=e}"
     "setTimeout(function(){x?c(x,null):c(null,r)},0);return function(){}},_e.unzipSync=kn;"),
)


class Refusal(Exception):
    """The bundle is not the one this recipe was written for. Nothing is written."""


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def is_kept(relative: str) -> bool:
    """
    Does the site carry this file? `relative` is its path under GeoGebra/,
    with forward slashes.
    """
    if relative == "deployggb.js":
        return True
    if relative.startswith("HTML5/5.0/css/"):
        return True
    if not relative.startswith(WEB3D):
        return False
    inside = relative[len(WEB3D):]
    if inside.startswith("js/properties_keys_"):
        return False
    if inside.startswith("html/"):
        return False
    if inside in ("sworker-locked.js", "web3d.nocache.mjs"):
        return False
    return True


def apply_replacements(name: str, text: str, replacements=REPLACEMENTS) -> str:
    """
    Every replacement for `name`, in order, each required to match exactly
    once in the text as it stands at that step.
    """
    for file, purpose, old, new in replacements:
        if file != name:
            continue
        found = text.count(old)
        if found != 1:
            raise Refusal(
                f"{name}: expected the text for '{purpose}' exactly once, found it {found} time(s). "
                f"GeoGebra changed this file; the replacement must be re-measured before the pin moves.")
        text = text.replace(old, new)
    return text


def readme_text(removed_languages: int) -> str:
    lines = [
        f"GeoGebra Math Apps {VERSION}, as a Plantoir class website carries it (#578).",
        "",
        "Made with GeoGebra(R) - https://www.geogebra.org",
        "",
        "Licence: GeoGebra's apps are free to use, copy, distribute, modify and transmit for",
        "NON-COMMERCIAL purposes, with the notice \"Made with GeoGebra(R)\" and a link to",
        "https://www.geogebra.org (https://www.geogebra.org/license). The source is under the",
        "EUPL 1.2; the language and interface files are CC BY-NC-SA 4.0. Sketches uploaded to",
        "geogebra.org are CC BY-NC-SA 4.0 and are credited to their author where they are shown.",
        "",
        f"Source: https://download.geogebra.org/installers/5.4/{ZIP_NAME}",
        f"SHA-256 of that zip: {ZIP_SHA256}",
        "",
        "Kept: deployggb.js, HTML5/5.0/css/ and HTML5/5.0/web3d/.",
        f"Removed: the {removed_languages} language files (web3d/js/properties_keys_*.js; English is built in),",
        "web3d/html/ (sign-in callbacks), web3d/sworker-locked.js, web3d/web3d.nocache.mjs,",
        "and the web/, webSimple/ and GeoGebra.html copies a site does not use.",
        "",
        "Changed: six exact text replacements, so the engine loads under a published site's",
        "content security policy and survives the site's page navigation:",
    ]
    for number, (file, purpose, _old, _new) in enumerate(REPLACEMENTS, start=1):
        lines.append(f"  {number}. {file}: {purpose}")
    lines.append("")
    return "\n".join(lines)


def _safe_relative(member_name: str):
    """The member's path under GeoGebra/, or None when it is not one we may write."""
    if not member_name.startswith(BUNDLE_ROOT):
        return None
    relative = member_name[len(BUNDLE_ROOT):]
    if not relative or relative.endswith("/"):
        return None
    pure = PurePosixPath(relative)
    if pure.is_absolute() or ".." in pure.parts or "\\" in relative or ":" in relative:
        raise Refusal(f"the bundle names a file outside its own folder: {member_name}")
    return relative


def adapt(zip_path, out_dir, expected_sha256: str = ZIP_SHA256) -> dict:
    """
    Make the site's copy of the engine at `out_dir`. Answers
    {"files": count, "bytes": total, "removedLanguages": count}. Raises Refusal
    (and writes nothing) when the zip or a replacement is not what was measured.
    """
    zip_path = Path(zip_path)
    out_dir = Path(out_dir)
    actual = sha256_of(zip_path)
    if actual != expected_sha256:
        raise Refusal(f"{zip_path.name} has SHA-256 {actual}, not the pinned {expected_sha256}.")

    out_dir.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix=".geogebra-staging-", dir=str(out_dir.parent)))
    try:
        files = 0
        total = 0
        removed_languages = 0
        unpacked = 0
        seen_replaced = set()
        with zipfile.ZipFile(zip_path) as bundle:
            for member in bundle.infolist():
                if member.is_dir():
                    continue
                relative = _safe_relative(member.filename)
                if relative is None:
                    continue
                if relative.startswith(WEB3D + "js/properties_keys_"):
                    removed_languages += 1
                if not is_kept(relative):
                    continue
                if member.file_size > MAX_FILE_BYTES:
                    raise Refusal(f"{relative} is {member.file_size} bytes, more than any measured file.")
                unpacked += member.file_size
                if unpacked > MAX_TOTAL_BYTES:
                    raise Refusal("the bundle unpacks to more than any measured bundle.")
                data = bundle.read(member)
                if relative in (NOCACHE, CACHE_JS):
                    data = apply_replacements(relative, data.decode("utf-8")).encode("utf-8")
                    seen_replaced.add(relative)
                destination = staging.joinpath(*relative.split("/"))
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(data)
                files += 1
                total += len(data)
        for file, purpose, _old, _new in REPLACEMENTS:
            if file not in seen_replaced:
                raise Refusal(f"the bundle has no {file}, so '{purpose}' could not be made.")
        readme = readme_text(removed_languages).encode("utf-8")
        (staging / "README.txt").write_bytes(readme)
        files += 1
        total += len(readme)

        previous = None
        if out_dir.exists():
            previous = out_dir.with_name(out_dir.name + ".previous")
            if previous.exists():
                shutil.rmtree(previous)
            os.replace(out_dir, previous)
        os.replace(staging, out_dir)
        if previous is not None:
            shutil.rmtree(previous, ignore_errors=True)
        return {"files": files, "bytes": total, "removedLanguages": removed_languages}
    finally:
        if staging.exists():
            shutil.rmtree(staging, ignore_errors=True)


def main(argv) -> int:
    if len(argv) == 2 and argv[1] == "version":
        print(VERSION)
        return 0
    if len(argv) != 4 or argv[1] != "adapt":
        print("Usage: geogebra_engine.py adapt <geogebra-math-apps-bundle.zip> <out folder>", file=sys.stderr)
        return 2
    try:
        outcome = adapt(argv[2], argv[3])
    except Refusal as refusal:
        print(f"GeoGebra's engine was not set up: {refusal}", file=sys.stderr)
        return 1
    print(f"GeoGebra {VERSION}: {outcome['files']} files, {outcome['bytes']:,} bytes "
          f"({outcome['removedLanguages']} language files left out).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
