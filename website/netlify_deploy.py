#!/usr/bin/env python3
"""Publish the built site/ folder to plantoir.app on Netlify.

Run through ``python3 website/build.py --deploy``, which builds first; this
module can also be run directly to publish whatever ``site/`` already holds::

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
otherwise from the macOS login Keychain item ``containerized-quartz-netlify``
— the same item the course launchers use, so there is exactly one Netlify
token on the machine. The site id lives in ``website/site.json`` under
``netlify_site_id``.
"""

from __future__ import annotations

import concurrent.futures
import hashlib
import json
import os
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
KEYCHAIN_SERVICE = "containerized-quartz-netlify"


def read_site_id() -> str:
    config = json.loads((WEBSITE / "site.json").read_text(encoding="utf-8"))
    site_id = config.get("netlify_site_id", "")
    if not site_id:
        raise SystemExit("website/site.json has no netlify_site_id; nothing to deploy to.")
    return site_id


def read_token() -> str:
    token = os.environ.get("NETLIFY_AUTH_TOKEN", "").strip()
    if token:
        return token
    if sys.platform == "darwin":
        result = subprocess.run(
            ["/usr/bin/security", "find-generic-password",
             "-s", KEYCHAIN_SERVICE, "-a", os.environ.get("USER", ""), "-w"],
            capture_output=True, text=True,
        )
        token = result.stdout.strip()
        if token:
            return token
    raise SystemExit(
        "No Netlify token found. Set NETLIFY_AUTH_TOKEN, or store one in the "
        f"login Keychain under the service name '{KEYCHAIN_SERVICE}'."
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
            # (zip site/, drag into Netlify), not a page. Never publish one.
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


def deploy() -> int:
    if not (SITE_DIR / "index.html").exists():
        raise SystemExit("site/ has no index.html — run website/build.py first.")
    site_id = read_site_id()
    token = read_token()

    branch = subprocess.run(["git", "-C", str(REPO), "branch", "--show-current"],
                            capture_output=True, text=True).stdout.strip()
    print(f"🌍 Deploying site/ to plantoir.app (from branch '{branch or 'unknown'}')…")

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
            return 0
        if state in ("error", "failed"):
            raise SystemExit(f"❌ Netlify reports the deploy state '{state}'.")
        time.sleep(2)
    print("⚠️ Deploy uploaded but Netlify has not confirmed it is live yet; "
          "check https://app.netlify.com if it does not appear shortly.")
    return 1


if __name__ == "__main__":
    raise SystemExit(deploy())
