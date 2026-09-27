#!/usr/bin/env python3
"""
Runs every `contracts/file-formats.json` -> `sidebarHiding.matchRule` case
through the REAL Quartz file tree (`quartz/util/fileTrie.ts`, the class the
site's sidebar builds itself from) and the filter text the build actually
writes (`setup_course.EXPLORER_BLOCK`, filled in by
`build_site.update_quartz_layout`). Issue #265.

Needs Node, tsx and Quartz's sources, so it runs INSIDE the image, from
verify.sh — not a `test_` file, because Windows' Python suite has none of
those (the `check_visibility_against_the_site.py` precedent). The filter is
turned back into a function from its own text, the way the page does in the
browser, so a helper outside it would fail here as it would there.

Exit 0 when every case agrees, 1 otherwise, printing each disagreement.
"""
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import contracts
import build_site
import setup_course

QUARTZ_DIR = Path(os.environ.get("PLANTOIR_QUARTZ_SOURCE", "/opt/quartz"))

RUNNER = """
import { readFileSync } from "fs"
import { FileTrieNode } from "QUARTZ/quartz/util/fileTrie"
import { slugifyFilePath } from "QUARTZ/quartz/util/path"
import { options } from "./layout"

const input = JSON.parse(readFileSync(process.argv[2], "utf8"))
const filterFn = new Function("return " + options.filterFn.toString())()
const entries: any[] = []
for (const path of input.paths) {
  const slug = slugifyFilePath(path as any)
  const fileName = path.split("/").pop() as string
  const title = (input.titles && input.titles[path]) || fileName.replace(/\\.md$/, "")
  entries.push([slug, { slug, filePath: path, title }])
}
const trie = FileTrieNode.fromEntries(entries)
trie.filter(filterFn)
const shown: string[] = []
function walk(node: any, prefix: string) {
  for (const child of node.children) {
    if (child.isFolder) {
      const name = prefix + child.fileSegmentHint + "/"
      shown.push(name)
      walk(child, name)
    } else if (child.data) {
      shown.push(child.data.filePath)
    }
  }
}
walk(trie, "")
console.log(JSON.stringify(shown))
"""


def items_for(paths):
    """Every file (other than an index page) and every folder the paths imply."""
    items = []
    for path in paths:
        parts = path.split("/")
        for depth in range(1, len(parts)):
            folder = "/".join(parts[:depth]) + "/"
            if folder not in items:
                items.append(folder)
        if parts[-1] != "index.md" and path not in items:
            items.append(path)
    return items


def shown_by_the_site(case, work_dir: Path):
    layout = work_dir / "layout.ts"
    layout.write_text(
        "const Component = { Explorer: (options: any) => options }\n"
        "export const options = " + setup_course.EXPLORER_BLOCK + "\n",
        encoding="utf-8",
    )
    build_site.update_quartz_layout(layout, list(case["hidden"]))
    runner = work_dir / "run.ts"
    runner.write_text(RUNNER.replace("QUARTZ", str(QUARTZ_DIR)), encoding="utf-8")
    case_file = work_dir / "case.json"
    case_file.write_text(json.dumps(case, ensure_ascii=False), encoding="utf-8")
    tsx = QUARTZ_DIR / "node_modules" / ".bin" / "tsx"
    result = subprocess.run(
        [str(tsx), str(runner), str(case_file)],
        cwd=str(QUARTZ_DIR), capture_output=True, text=True,
    )
    if result.returncode != 0:
        return None, result.stderr.strip()[-600:]
    return json.loads(result.stdout.strip().splitlines()[-1]), ""


def main() -> int:
    cases = contracts.section("file-formats", "sidebarHiding", "matchRule", "cases")
    failures = 0
    for case in cases:
        with tempfile.TemporaryDirectory() as temp_name:
            shown, problem = shown_by_the_site(case, Path(temp_name))
        if shown is None:
            failures += 1
            print(f"FAIL {case['name']}: the filter did not run: {problem}")
            continue
        expected = [item for item in items_for(case["paths"]) if item not in case["expectHidden"]]
        if sorted(shown) != sorted(expected):
            failures += 1
            print(f"FAIL {case['name']}: sidebar shows {sorted(shown)}, expected {sorted(expected)}")
        else:
            print(f"ok   {case['name']}")
    print(f"{len(cases) - failures} of {len(cases)} sidebar hiding cases agree with the site")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
