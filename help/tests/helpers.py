"""Shared by help/tests: a fresh copy of the fixture repository, and a way to
run build_help.py against it.

fixtures/repo/ is a small invented repository: an outline of five pages in
three sections (one the assistant section), registries, a menu golden, two
Swift files, two contract files and a support/ folder. make_fixture() copies
it into a temporary folder, adds help/assets/ from the real help/, and writes
the two pictures of scene first-steps-2, so the fixture builds green; a test
then changes one thing and checks that the build refuses it.
"""

from __future__ import annotations

import os
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import List, Optional, Tuple

TESTS_DIR = Path(__file__).resolve().parent
HELP_DIR = TESTS_DIR.parent
REPO = HELP_DIR.parent
FIXTURE = TESTS_DIR / "fixtures" / "repo"
BUILD_HELP = HELP_DIR / "build_help.py"
FIXTURE_TODAY = "2026-11-13"

if str(HELP_DIR) not in sys.path:
    sys.path.insert(0, str(HELP_DIR))


def write_webp(path: Path, width: int, height: int) -> None:
    """A WebP header (VP8X) of the given size. The tests read only its size."""
    path.parent.mkdir(parents=True, exist_ok=True)
    chunk: bytes = b"\x00\x00\x00\x00" + (width - 1).to_bytes(3, "little") + (height - 1).to_bytes(3, "little")
    body: bytes = b"WEBP" + b"VP8X" + struct.pack("<I", len(chunk)) + chunk
    path.write_bytes(b"RIFF" + struct.pack("<I", len(body)) + body)


class Fixture:
    """A temporary copy of the fixture repository."""

    def __init__(self) -> None:
        self.temporary = tempfile.mkdtemp(prefix="plantoir-help-test-")
        self.repo = Path(self.temporary) / "repo"
        shutil.copytree(str(FIXTURE), str(self.repo))
        self.help_dir = self.repo / "help"
        shutil.copytree(str(HELP_DIR / "assets"), str(self.help_dir / "assets"))
        (self.help_dir / "pictures").mkdir(exist_ok=True)
        write_webp(self.help_dir / "pictures" / "first-steps-2-light.webp", 1600, 1000)
        write_webp(self.help_dir / "pictures" / "first-steps-2-dark.webp", 1600, 1000)
        self.out = Path(self.temporary) / "out"

    def close(self) -> None:
        shutil.rmtree(self.temporary)

    def path(self, relative: str) -> Path:
        return self.repo / relative

    def read(self, relative: str) -> str:
        return self.path(relative).read_text(encoding="utf-8")

    def write(self, relative: str, text: str) -> None:
        target: Path = self.path(relative)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding="utf-8")

    def replace(self, relative: str, old: str, new: str) -> None:
        text: str = self.read(relative)
        if old not in text:
            raise AssertionError(repr(old) + " is not in " + relative)
        self.write(relative, text.replace(old, new, 1))

    def page(self, page_id: str, body: str, extra_front_matter: str = "") -> None:
        """Writes help/pages/<id>.md with minimal valid front matter."""
        self.write(
            "help/pages/" + page_id + ".md",
            "---\nid: " + page_id + "\nchecked: 2.0.0\nkeywords:\n- word\ndescription: A fixture page.\n"
            + extra_front_matter + "---\n" + body,
        )

    def run(self, *arguments: str) -> Tuple[int, str]:
        return run_build(list(arguments), repo=self.repo, help_dir=self.help_dir)


def run_build(arguments: List[str], repo: Optional[Path] = None, help_dir: Optional[Path] = None) -> Tuple[int, str]:
    """Runs build_help.py under this interpreter with -I -B; returns the exit code and output."""
    command: List[str] = [sys.executable, "-I", "-B", str(BUILD_HELP)] + arguments
    if repo is not None:
        command += ["--repo", str(repo), "--today", FIXTURE_TODAY]
    if help_dir is not None:
        command += ["--help-dir", str(help_dir)]
    environment = dict(os.environ)
    environment["PYTHONDONTWRITEBYTECODE"] = "1"
    completed = subprocess.run(
        command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True, env=environment
    )
    return completed.returncode, completed.stdout


# The WHOLE search page path, as a browser runs it: search-index.js and
# search.js loaded into a page with a stub DOM, ?q= in the address, the
# results box read back. Testing searchHelp alone let a ReferenceError in the
# box's own code ship twice (third review of P2a, HIGH 1).
DOM_HARNESS = r"""
const fs = require("fs");
const vm = require("vm");
const [indexPath, searchPath, query, readyState] = process.argv.slice(2);
class Element {
  constructor(tag) { this.tag = tag; this.children = []; this._text = ""; this.hidden = true; this.href = ""; this.value = ""; }
  appendChild(child) { this.children.push(child); return child; }
  set textContent(value) { this._text = String(value); this.children = []; }
  get textContent() {
    let text = this._text;
    for (const child of this.children) { text += child.textContent; }
    return text;
  }
}
const box = new Element("section");
const field = new Element("input");
const listeners = [];
const document = {
  readyState: readyState,
  getElementById(id) { return id === "help-results" ? box : (id === "help-search" ? field : null); },
  createElement(tag) { return new Element(tag); },
  addEventListener(name, handler) { if (name === "DOMContentLoaded") { listeners.push(handler); } },
};
const sandbox = { document: document, URLSearchParams: URLSearchParams };
sandbox.window = sandbox;
sandbox.window.location = { search: "?q=" + encodeURIComponent(query) };
vm.createContext(sandbox);
const report = { threw: null };
try {
  vm.runInContext(fs.readFileSync(indexPath, "utf8"), sandbox, { filename: "search-index.js" });
  vm.runInContext(fs.readFileSync(searchPath, "utf8"), sandbox, { filename: "search.js" });
  for (const handler of listeners) { handler(); }
} catch (error) {
  report.threw = String(error && error.name) + ": " + String(error && error.message);
}
report.hidden = box.hidden;
report.fieldValue = field.value;
report.heading = "";
report.items = [];
report.paragraphs = [];
for (const child of box.children) {
  if (child.tag === "h2") { report.heading = child.textContent; }
  if (child.tag === "ol") {
    for (const item of child.children) {
      report.items.push({ href: item.children[0].href, title: item.children[0].textContent });
    }
  }
  if (child.tag === "p") { report.paragraphs.push(child.textContent); }
}
console.log(JSON.stringify(report));
"""


def run_page_search(node: str, web: Path, query: str, ready_state: str = "complete", search_js: Optional[Path] = None) -> dict:
    """Runs the contents page's search as a browser would; returns what the box shows."""
    import json

    script = web.parent / "page-search-harness.js"
    script.write_text(DOM_HARNESS, encoding="utf-8")
    search_path: Path = search_js if search_js is not None else web / "assets" / "search.js"
    completed = subprocess.run(
        [node, str(script), str(web / "assets" / "search-index.js"), str(search_path), query, ready_state],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True,
    )
    if completed.returncode != 0:
        raise AssertionError("the page harness failed: " + completed.stdout)
    return json.loads(completed.stdout)
