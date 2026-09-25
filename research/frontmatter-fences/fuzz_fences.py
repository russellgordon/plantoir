#!/usr/bin/env python3
"""
Where does a page's frontmatter block begin and end? A seeded fuzz of that one
question, comparing each reader's answer with python-frontmatter's own.

The build reads every page with python-frontmatter, so ITS idea of the block
is the truth: whatever it calls frontmatter is what the site obeys, and a
reader or writer that ends the block somewhere else reads or edits a
different block. Issue #188 was one such divergence (an INDENTED line of
dashes, which the apps took as the closing fence and the build does not).

Nothing here is a gate, and the 3,000 pages are not committed: they are
regenerated from the seed, so the corpus is this file. RESULTS.md beside it
records what a run said, and under what conditions.

Subcommands, each reading JSON on stdin and writing JSON on stdout:

    generate            the pages (seed 188, 3,000 of them); no input
    library             python-frontmatter's block for each page, or null —
                        run where python-frontmatter is installed (the image)
    build               scripts/build_site.py's `_frontmatter_fences`, as the
                        lines between the two fences, or null — run with
                        scripts/ on the path (the image)
    compare A B         counts the pages where two answer files disagree

The Swift reader is asked through `fence_probe.swift`, compiled against the
app's own `PageVisibilityReader.swift` — see RESULTS.md for the command.
Blocks are compared with carriage returns removed and outer whitespace
stripped, which is how python-frontmatter hands its block to YAML.
"""
import json
import random
import sys

SEED = 188
COUNT = 3000

FENCES = ["---", "----", "-----", "  ---", "\t---", " ---", "---  ", "---\t", "--", "---x", "- - -", "  ----"]
BODIES = [
    "publish: false", "title: x", "  a: 1", "tags:\n  - a", "# note", "",
    "  ---", "\t---", "publish: >-\n  false", "x: |\n  ---\n  y",
]


def generate():
    chooser = random.Random(SEED)
    pages = []
    for _ in range(COUNT):
        before = chooser.choice(["", "", "\n", "\n\n", "  \n"])
        opening = chooser.choice(FENCES)
        closing = chooser.choice(FENCES)
        middle_lines = []
        for _ in range(chooser.randint(0, 3)):
            middle_lines.append(chooser.choice(BODIES))
        middle = "\n".join(middle_lines)
        newline = "\r\n" if chooser.random() < 0.1 else "\n"
        text = before + opening + "\n" + (middle + "\n" if middle else "") + closing + "\n\nBody\n"
        pages.append(text.replace("\n", newline))
    return pages


def library(pages):
    import frontmatter
    handler = frontmatter.YAMLHandler()
    answers = []
    for text in pages:
        stripped = text.strip()  # what frontmatter.parse does before it splits
        if not handler.detect(stripped):
            answers.append(None)
            continue
        try:
            block, _ = handler.split(stripped)
            answers.append(block)
        except Exception:
            answers.append(None)
    return answers


def build(pages):
    import contextlib
    import io
    with contextlib.redirect_stdout(io.StringIO()):
        import build_site
    answers = []
    for text in pages:
        lines = text.split("\n")
        fences = build_site._frontmatter_fences(lines)
        answers.append(None if fences is None else "\n".join(lines[fences[0] + 1:fences[1]]))
    return answers


def normalised(block):
    return None if block is None else block.replace("\r", "").strip()


def compare(first, second):
    disagreements = 0
    for one, other in zip(first, second):
        if normalised(one) != normalised(other):
            disagreements += 1
    return disagreements


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command == "generate":
        json.dump(generate(), sys.stdout)
    elif command == "library":
        json.dump(library(json.load(sys.stdin)), sys.stdout)
    elif command == "build":
        json.dump(build(json.load(sys.stdin)), sys.stdout)
    elif command == "compare":
        with open(sys.argv[2], encoding="utf-8") as handle:
            first = json.load(handle)
        with open(sys.argv[3], encoding="utf-8") as handle:
            second = json.load(handle)
        print(f"{compare(first, second)} of {len(first)} pages disagree")
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
