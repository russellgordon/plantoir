#!/usr/bin/env python3
"""Requests every link every page of a deployed folder writes, through the
app's own server for a deployed folder (#850), and counts what was not found.

The aim the plan review set (M6, M7): every link the build writes resolves
here. Cloudflare's redirect codes are not the test; this crawl is.

    crawl_deployed_folder.py --app <Plantoir.app> <folder>
    crawl_deployed_folder.py --plain-server <folder>     # the must-fail

--app starts `<app>/Contents/MacOS/Plantoir --serve-deployed-folder <folder>`
and FAILS (exit 2) when the bundle is not there: a check that was asked to
run and could not is a failure, never a skip. --plain-server serves the same
folder with `python3 -m http.server`, which adds no `.html`, and is expected
to FAIL at the first page link: that is the proof this crawl can fail.

Prints one summary line and exits 0 only when nothing was missing.
"""

import argparse
import html.parser
import os
import socket
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request


class LinkReader(html.parser.HTMLParser):
    """Every href and src in a page."""

    def __init__(self):
        super().__init__()
        self.links = []

    def handle_starttag(self, tag, attributes):
        for name, value in attributes:
            if value is None:
                continue
            if (name == "href" and tag in ("a", "link")) or (name == "src" and tag in ("script", "img", "source", "video", "audio", "iframe")):
                self.links.append(value)


def page_address(relative_path):
    """The address the site uses for a page file: no `.html`, and a folder's
    index page at its folder with the slash."""
    parts = relative_path.split(os.sep)
    if parts[-1] == "index.html":
        folder = "/".join(urllib.parse.quote(part) for part in parts[:-1])
        return "/" + (folder + "/" if folder else "")
    parts[-1] = parts[-1][: -len(".html")]
    return "/" + "/".join(urllib.parse.quote(part) for part in parts)


def wanted(link):
    """Links into the site itself, without the parts a server never sees."""
    lowered = link.strip().lower()
    for prefix in ("http:", "https:", "mailto:", "javascript:", "data:", "tel:", "#", "//"):
        if lowered.startswith(prefix):
            return False
    return lowered != ""


class NoRedirects(urllib.request.HTTPRedirectHandler):
    pass


def fetch(base, address, cache):
    """The final status of an address, following redirects."""
    if address in cache:
        return cache[address]
    request = urllib.request.Request(base + address.lstrip("/"), method="GET")
    try:
        with urllib.request.urlopen(request, timeout=20) as answer:
            status = answer.status
    except urllib.error.HTTPError as error:
        status = error.code
    except Exception:
        status = 0
    cache[address] = status
    return status


def free_port():
    probe = socket.socket()
    probe.bind(("127.0.0.1", 0))
    port = probe.getsockname()[1]
    probe.close()
    return port


def start_app(app, folder):
    binary = os.path.join(app, "Contents", "MacOS", "Plantoir")
    if not os.path.isfile(binary):
        print(f"FAILED: no Plantoir at {binary}, so the crawl could not run")
        sys.exit(2)
    process = subprocess.Popen(
        [binary, "--serve-deployed-folder", folder],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
    )
    # Read on a thread with a bound, so a child that prints nothing fails
    # this check instead of hanging it.
    found = []
    reader = threading.Thread(target=lambda: found.append(process.stdout.readline()), daemon=True)
    reader.start()
    reader.join(15)
    line = found[0].strip() if found else "(nothing within 15 s)"
    if not line.startswith("DEPLOYED_FOLDER_ADDRESS="):
        process.kill()
        print(f"FAILED: Plantoir did not say where it was serving ({line!r})")
        sys.exit(2)
    return process, line.split("=", 1)[1]


def start_plain(folder):
    port = free_port()
    process = subprocess.Popen(
        [sys.executable, "-m", "http.server", str(port), "--bind", "127.0.0.1", "--directory", folder],
        stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    for _ in range(50):
        try:
            socket.create_connection(("127.0.0.1", port), timeout=0.2).close()
            break
        except OSError:
            time.sleep(0.1)
    return process, f"http://127.0.0.1:{port}/"


def main():
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--app")
    group.add_argument("--plain-server", action="store_true")
    parser.add_argument("folder")
    arguments = parser.parse_args()
    folder = os.path.realpath(arguments.folder)
    if not os.path.isfile(os.path.join(folder, "index.html")):
        print(f"FAILED: {folder} holds no index.html")
        sys.exit(2)

    if arguments.app:
        process, base = start_app(arguments.app, folder)
    else:
        process, base = start_plain(folder)

    pages = 0
    links = 0
    missing = []
    cache = {}
    try:
        for directory, _, names in os.walk(folder):
            for name in sorted(names):
                if not name.endswith(".html") or name == "404.html":
                    continue
                relative = os.path.relpath(os.path.join(directory, name), folder)
                with open(os.path.join(directory, name), encoding="utf-8", errors="replace") as page:
                    reader = LinkReader()
                    reader.feed(page.read())
                pages += 1
                here = page_address(relative)
                for link in reader.links:
                    if not wanted(link):
                        continue
                    target = urllib.parse.urljoin("http://site" + here, link)
                    parsed = urllib.parse.urlparse(target)
                    address = parsed.path + (("?" + parsed.query) if parsed.query else "")
                    links += 1
                    status = fetch(base, address, cache)
                    if status < 200 or status >= 400:
                        missing.append((here, link, status))
    finally:
        if process.stdin:
            process.stdin.close()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()

    print(f"{pages} pages, {links} links, {len(cache)} distinct addresses, {len(missing)} not found")
    for here, link, status in missing[:10]:
        print(f"  {status} {link!r} on {here}")
    sys.exit(0 if not missing else 1)


if __name__ == "__main__":
    main()
