#!/usr/bin/env python3
"""Deploy the built site/ folder to plantoir.app on Netlify.

Run through ``python3 website/build.py --deploy``, which builds first; this
module can also be run directly to deploy whatever ``site/`` already holds::

    python3 website/netlify_deploy.py

This is the ONLY path by which plantoir.app updates. The Netlify site is not
connected to GitHub — pushing this repository deploys nothing — so a website
change is live when somebody runs the deploy, and not before.

The deploy is a delta: Netlify is sent a manifest of every file's SHA1 and
answers with the digests it does not already have, so an unchanged site
uploads nothing and a typical edit uploads a handful of files. The upload
loop retries on 429 the same way ``scripts/deploy.py`` does — Netlify
rate-limits uploads, and a burst after a large rebuild can trip it.

Credentials: the token is read from ``NETLIFY_AUTH_TOKEN`` if set, and
otherwise from the stored credential named ``containerized-quartz-netlify``:
the login Keychain item of that name on a Mac, the generic Windows
Credential Manager credential of that name on Windows (#452, read with
``CredReadW`` and decoded as UTF-8, which is how ``deploy.ps1`` writes it).
It is the same one the course launchers use, so there is exactly one Netlify
token on the machine. The token is never printed. The site id lives in
``website/site.json`` under ``netlify_site_id``.

plantoir.app is itself a free-tier Netlify project, so it is exposed to the
same "Powered by Netlify" ad badge as every class site — see
``scripts/netlify_badge.py`` (shared with ``scripts/deploy.py``, which
suppresses the identical badge for class sites) for the mechanism.
``write_netlify_headers_file(SITE_DIR)`` runs here, before the manifest is
built, so the ``_headers`` file it writes rides along in the same delta
upload as every other file.
"""

from __future__ import annotations

import concurrent.futures
import hashlib
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

WEBSITE = Path(__file__).resolve().parent
REPO = WEBSITE.parent
SITE_DIR = REPO / "site"
# The stored credential's name on both platforms: the Keychain service on a
# Mac, the generic credential's target on Windows (deploy.ps1 $KEY_TARGET).
CREDENTIAL_NAME = "containerized-quartz-netlify"
KEYCHAIN_SERVICE = CREDENTIAL_NAME

# How long verify_live() keeps retrying before giving up — mirrors the
# 2s-interval pattern deploy() already uses to poll Netlify's own deploy
# state, so a genuine CDN propagation lag has the same kind of runway a
# slow Netlify build already gets.
VERIFY_ATTEMPTS = 5
VERIFY_INTERVAL_SECONDS = 3.0

# scripts/ is a sibling of website/, not a package either lives inside, so it
# has to be added to sys.path by hand before the shared badge-suppression
# module can be imported — the same trick scripts/deploy.py itself uses for
# its own sibling imports (toolchain_paths).
sys.path.insert(0, str(REPO / "scripts"))
from netlify_badge import write_netlify_headers_file  # noqa: E402


def read_config() -> dict:
    return json.loads((WEBSITE / "site.json").read_text(encoding="utf-8"))


def read_site_id() -> str:
    site_id = read_config().get("netlify_site_id", "")
    if not site_id:
        raise SystemExit("website/site.json has no netlify_site_id; nothing to deploy to.")
    return site_id


def _windows_credential_blob(target: str) -> bytes | None:
    """The bytes of the generic Windows credential `target`, or None.

    CredReadW through ctypes, standard library only, laid out as deploy.ps1's
    own CREDENTIAL struct. None when there is no such credential, when it is
    empty, or when advapi32 cannot be reached at all: whatever the reason,
    the caller falls through to its own "no token" message. The bytes are
    copied out before CredFree, and never printed.
    """
    try:
        import ctypes
        from ctypes import wintypes
    except ImportError:
        return None

    class CREDENTIALW(ctypes.Structure):
        _fields_ = [
            ("Flags", wintypes.DWORD),
            ("Type", wintypes.DWORD),
            ("TargetName", wintypes.LPWSTR),
            ("Comment", wintypes.LPWSTR),
            ("LastWritten", wintypes.FILETIME),
            ("CredentialBlobSize", wintypes.DWORD),
            ("CredentialBlob", ctypes.c_void_p),
            ("Persist", wintypes.DWORD),
            ("AttributeCount", wintypes.DWORD),
            ("Attributes", ctypes.c_void_p),
            ("TargetAlias", wintypes.LPWSTR),
            ("UserName", wintypes.LPWSTR),
        ]

    try:
        advapi32 = ctypes.WinDLL("advapi32", use_last_error=True)
        cred_read = advapi32.CredReadW
        cred_free = advapi32.CredFree
    except (OSError, AttributeError):
        return None
    cred_read.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD,
                          ctypes.POINTER(ctypes.POINTER(CREDENTIALW))]
    cred_read.restype = wintypes.BOOL
    cred_free.argtypes = [ctypes.c_void_p]
    cred_free.restype = None

    CRED_TYPE_GENERIC = 1
    pointer = ctypes.POINTER(CREDENTIALW)()
    if not cred_read(target, CRED_TYPE_GENERIC, 0, ctypes.byref(pointer)):
        return None   # ERROR_NOT_FOUND (1168) or anything else: no token here
    try:
        credential = pointer.contents
        if not credential.CredentialBlob or credential.CredentialBlobSize == 0:
            return None
        return ctypes.string_at(credential.CredentialBlob, credential.CredentialBlobSize)
    finally:
        cred_free(pointer)


def _usable_token(text: str) -> str | None:
    """`text` stripped, or None when it is not a token that can be sent.

    A control character inside a token is refused here, before anything is
    sent. A NUL (a credential written as UTF-16) would otherwise be sent as
    it is — http.client lets it through — and earn a refusal from Netlify
    that says nothing about why; a line break makes http.client raise
    "Invalid header value", which quotes the whole Authorization header, the
    token with it, into the traceback."""
    token = text.strip()
    if not token:
        return None
    for character in token:
        if ord(character) < 32 or ord(character) == 127:
            return None
    return token


def _token_from_blob(blob: bytes | None) -> str | None:
    """A stored credential's bytes as a token: UTF-8, as deploy.ps1 writes
    them (WriteSecret is Encoding.UTF8.GetBytes). None for no blob, for bytes
    that are not UTF-8, and for UTF-16 — which decodes as valid UTF-8 with a
    NUL after every letter, and is caught by _usable_token."""
    if not blob:
        return None
    try:
        text = blob.decode("utf-8")
    except UnicodeDecodeError:
        return None
    return _usable_token(text)


def read_token() -> str:
    environment_token = os.environ.get("NETLIFY_AUTH_TOKEN", "")
    if environment_token.strip():
        token = _usable_token(environment_token)
        if token:
            return token
        raise SystemExit("NETLIFY_AUTH_TOKEN is set but holds a character a token cannot "
                         "(a line break or a control character). Set it again.")
    if sys.platform == "darwin":
        result = subprocess.run(
            ["/usr/bin/security", "find-generic-password",
             "-s", CREDENTIAL_NAME, "-a", os.environ.get("USER", ""), "-w"],
            capture_output=True, text=True,
        )
        token = result.stdout.strip()
        if token:
            return token
        raise SystemExit(
            "No Netlify token found. Set NETLIFY_AUTH_TOKEN, or store one in the "
            f"login Keychain under the service name '{CREDENTIAL_NAME}'."
        )
    if sys.platform == "win32":
        blob = _windows_credential_blob(CREDENTIAL_NAME)
        token = _token_from_blob(blob)
        if token:
            return token
        if blob:
            raise SystemExit(
                f"The Windows credential '{CREDENTIAL_NAME}' is there, but it is not a token "
                "written as UTF-8 text, the way the course launchers write it. Store it again "
                "(a course launcher's deploy with --reset-token asks for it afresh), or set "
                "NETLIFY_AUTH_TOKEN."
            )
        raise SystemExit(
            "No Netlify token found. Set NETLIFY_AUTH_TOKEN, or store one in Windows "
            f"Credential Manager as the generic credential '{CREDENTIAL_NAME}' (the one "
            "the course launchers use)."
        )
    raise SystemExit(
        "No Netlify token found. Set NETLIFY_AUTH_TOKEN (or, on a Mac, the login Keychain "
        f"item '{CREDENTIAL_NAME}'; on Windows, the Credential Manager credential of that name)."
    )


def netlify_api(method: str, path: str, token: str,
                payload: dict | None = None, data: bytes | None = None,
                content_type: str | None = None) -> dict:
    request = urllib.request.Request(f"https://api.netlify.com/api/v1{path}", method=method)
    request.add_header("Accept", "application/json")
    request.add_header("Authorization", f"Bearer {token}")
    body = None
    if data is not None:
        body = data
        request.add_header("Content-Type", content_type or "application/octet-stream")
    elif payload is not None:
        body = json.dumps(payload).encode("utf-8")
        request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request, data=body, timeout=60) as response:
            raw = response.read()
            return json.loads(raw.decode("utf-8")) if raw else {}
    except urllib.error.HTTPError as error:
        message = error.read().decode("utf-8", errors="ignore")
        raise RuntimeError(f"Netlify API error {error.code}: {message}") from error


def build_manifest() -> tuple[dict[str, str], dict[str, Path]]:
    """SHA1 every file under site/, keyed by its path on the live site."""
    digests_by_remote_path: dict[str, str] = {}
    local_file_by_digest: dict[str, Path] = {}
    for file in sorted(SITE_DIR.rglob("*")):
        if not file.is_file():
            continue
        if any(part.startswith(".") for part in file.relative_to(SITE_DIR).parts):
            continue  # .DS_Store and friends never ship
        if file.parent == SITE_DIR and file.suffix == ".zip":
            # A zip at the site root is a leftover from the manual deploy era
            # (zip site/, drag into Netlify), not a page. Never deploy one.
            print(f"   Skipping {file.name} — a zip at the site root is not part of the site.")
            continue
        digest = hashlib.sha1(file.read_bytes()).hexdigest()
        remote_path = "/" + file.relative_to(SITE_DIR).as_posix()
        digests_by_remote_path[remote_path] = digest
        local_file_by_digest.setdefault(digest, file)
    return digests_by_remote_path, local_file_by_digest


def upload_one(deploy_id: str, token: str, remote_path: str, file: Path) -> None:
    encoded_path = urllib.parse.quote(remote_path)
    data = file.read_bytes()
    # Netlify rate-limits uploads; a 429 (or transient 5xx) is expected under
    # a burst, not an error — back off and retry, as scripts/deploy.py does.
    delay = 1.0
    last_error: Exception | None = None
    for _attempt in range(6):
        try:
            netlify_api("PUT", f"/deploys/{deploy_id}/files{encoded_path}", token, data=data)
            return
        except RuntimeError as error:
            retryable = any(f"Netlify API error {code}" in str(error)
                            for code in (429, 500, 502, 503, 504))
            if not retryable:
                raise
            last_error = error
            time.sleep(min(delay, 30.0))
            delay *= 2
        except (urllib.error.URLError, TimeoutError) as error:
            last_error = error
            time.sleep(min(delay, 30.0))
            delay *= 2
    raise RuntimeError(f"Upload of {remote_path} kept failing after retries: {last_error}")


def verify_live() -> str:
    """Fetch the live site and confirm its version-note line matches site.json.

    Compares against site.json's own "version" field, not the git release
    tag: the tag carries a "v" prefix ("v1.1.0") the page text never does,
    so comparing against the tag would misfire on every release. This is
    checking "did Netlify actually deploy what we just told it to", not
    "does the live site match the tag" — keep it that way if this is ever
    touched again.

    A mismatch and a fetch failure are different findings and are reported
    differently: a fetch failure (network blip, DNS hiccup) says nothing
    about whether the deploy worked, so it is a soft "unknown", never
    treated as evidence the deploy failed. Only a page that loads AND shows
    the wrong version, still wrong after retrying through VERIFY_ATTEMPTS,
    is reported as a real mismatch — and retrying matters here specifically
    because Netlify reporting a deploy "ready" and its CDN edges actually
    serving the new content are not the same instant.

    Returns "match", "mismatch", or "unknown". Never raises for a network
    or parsing problem — callers decide what an "unknown" should mean for
    their own exit code.
    """
    config = read_config()
    expected_version = config.get("version", "").strip()
    base_url = config.get("base_url", "").strip()
    if not expected_version or not base_url:
        print("⚠️ Cannot verify the live site: site.json is missing 'version' or 'base_url'.")
        return "unknown"

    fetch_problem: Exception | None = None
    wrong_version: str | None = None
    for attempt in range(VERIFY_ATTEMPTS):
        if attempt:
            time.sleep(VERIFY_INTERVAL_SECONDS)
        try:
            request = urllib.request.Request(
                base_url, headers={"Cache-Control": "no-cache", "Pragma": "no-cache"})
            with urllib.request.urlopen(request, timeout=30) as response:
                html = response.read().decode("utf-8", errors="ignore")
        except (urllib.error.URLError, TimeoutError) as error:
            fetch_problem = error
            continue
        match = re.search(r'class="version-note"[^>]*>\s*Version\s+([^\s<&]+)', html)
        if not match:
            fetch_problem = RuntimeError("no version-note line found on the page")
            continue
        fetch_problem = None
        live_version = match.group(1).strip()
        if live_version == expected_version:
            print(f"✅ {base_url} is serving version {live_version} — the deploy reached "
                  f"the live site.")
            return "match"
        wrong_version = live_version
        # Keep retrying: the mismatch may just be the CDN not yet caught up
        # with a deploy Netlify already reports as ready.

    if wrong_version is not None:
        # The loop only sleeps BETWEEN attempts (none before the first), so
        # elapsed wall time is one interval short of attempts * interval.
        elapsed = (VERIFY_ATTEMPTS - 1) * VERIFY_INTERVAL_SECONDS
        print(f"❌ {base_url} still shows version {wrong_version} after {VERIFY_ATTEMPTS} "
              f"checks over ~{elapsed:.0f}s; expected {expected_version}. The deploy "
              f"reported success but the live site has not picked it up. Check "
              f"https://app.netlify.com for a stuck or failed build, then either wait "
              f"for it to finish or re-run 'python3 website/build.py --deploy'.")
        return "mismatch"

    print(f"⚠️ Could not confirm {base_url} is serving version {expected_version} "
          f"({fetch_problem}). This looks like a network problem reaching the site, not "
          f"evidence the deploy failed — check https://plantoir.app by hand if in doubt.")
    return "unknown"


def verify_feeds_live() -> str:
    """Every update feed in site/updates/ is live as built, and its newest
    download exists (#204). Advisory after a deploy, like verify_live."""
    import update_feeds
    import windows_feed
    config = read_config()
    base_url = config.get("base_url", "").strip()
    outcome = "match"
    # Both feeds since Windows 1.4.2 (#337), each by its own checker since
    # #428: the mac's compares the bytes and the newest download's length;
    # the Windows one also verifies the live windows.xml.signature against the
    # live feed, picks the newest item by real version order, and — on Windows,
    # or anywhere with PLANTOIR_VERIFY_WINDOWS_INSTALLER=1 — READS the newest
    # installer to verify its signature (about 240 MB); elsewhere its length.
    feeds = [SITE_DIR / "updates" / "macos.xml", SITE_DIR / "updates" / "windows.xml"]
    for feed in feeds:
        if not feed.is_file():
            continue
        signature = feed.with_name(feed.name + ".signature")
        if feed.name == "windows.xml":
            if not signature.is_file():
                print(f"❌ site/updates/{signature.name} is missing: the Windows app refuses a feed with no signature file.")
                result = "mismatch"
            else:
                result = windows_feed.verify_live(base_url, feed)
        else:
            result = update_feeds.verify_live(base_url, feed)
        if result == "mismatch":
            outcome = "mismatch"
        elif result == "unknown" and outcome == "match":
            outcome = "unknown"
    return outcome


def deploy() -> int:
    if not (SITE_DIR / "index.html").exists():
        raise SystemExit("site/ has no index.html — run website/build.py first.")
    site_id = read_site_id()
    token = read_token()

    branch = subprocess.run(["git", "-C", str(REPO), "branch", "--show-current"],
                            capture_output=True, text=True).stdout.strip()
    print(f"🌍 Deploying site/ to plantoir.app (from branch '{branch or 'unknown'}')…")

    # Netlify can add its own advertisement badge to free-plan sites, same as
    # any class site deployed by scripts/deploy.py. Must run before the
    # manifest below, so the _headers file it writes is part of what gets
    # uploaded.
    protected_scripts = write_netlify_headers_file(SITE_DIR)
    print(f"   Wrote a website rule keeping Netlify's own ad badge off "
          f"plantoir.app (checked {protected_scripts} script(s) already on the site).")

    digests_by_remote_path, local_file_by_digest = build_manifest()
    print(f"   {len(digests_by_remote_path)} file(s) in the manifest.")
    created = netlify_api("POST", f"/sites/{site_id}/deploys", token,
                          payload={"files": digests_by_remote_path})
    deploy_id = created["id"]
    required = created.get("required") or []
    print(f"   Netlify needs {len(required)} file(s) uploaded.")

    remote_path_by_digest: dict[str, str] = {}
    for remote_path, digest in digests_by_remote_path.items():
        remote_path_by_digest.setdefault(digest, remote_path)

    uploads: list[tuple[str, Path]] = []
    for digest in required:
        file = local_file_by_digest.get(digest)
        remote_path = remote_path_by_digest.get(digest)
        if file is None or remote_path is None:
            print(f"⚠️ Netlify asked for unknown digest {digest[:8]}…; skipping.")
            continue
        uploads.append((remote_path, file))

    if uploads:
        # 5 workers, not more: proven to stay under Netlify's rate limit.
        with concurrent.futures.ThreadPoolExecutor(max_workers=min(5, len(uploads))) as executor:
            futures = [executor.submit(upload_one, deploy_id, token, remote_path, file)
                       for remote_path, file in uploads]
            for future in concurrent.futures.as_completed(futures):
                future.result()

    for _ in range(60):
        state = netlify_api("GET", f"/deploys/{deploy_id}", token).get("state", "")
        if state == "ready":
            print("✅ plantoir.app is live with this deploy.")
            # Advisory only: Netlify has already accepted and served the
            # upload by this point, so a flaky fetch or a still-propagating
            # CDN edge here must never turn a genuinely successful deploy
            # into a failing exit code. See verify_live()'s docstring.
            verify_live()
            verify_feeds_live()
            return 0
        if state in ("error", "failed"):
            raise SystemExit(f"❌ Netlify reports the deploy state '{state}'.")
        time.sleep(2)
    print("⚠️ Deploy uploaded but Netlify has not confirmed it is live yet; "
          "check https://app.netlify.com if it does not appear shortly.")
    return 1


if __name__ == "__main__":
    # Must match the flag website/build.py --verify-deploy and every doc
    # reference teach — "--verify" alone would fall through to a real
    # deploy below on a plausible typo, which is the one outcome a
    # read-only check can never be allowed to risk.
    if "--verify-deploy" in sys.argv:
        # Standalone check, no deploy: "did the last deploy actually reach
        # plantoir.app", runnable independently and after the fact.
        outcome = verify_live()
        feeds = verify_feeds_live()
        if feeds == "mismatch" or (feeds == "unknown" and outcome == "match"):
            outcome = feeds
        raise SystemExit({"match": 0, "mismatch": 2, "unknown": 1}[outcome])
    raise SystemExit(deploy())
