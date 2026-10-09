#!/usr/bin/env python3
"""
The printing rules in the contract, run against what the SITE runs (#454).

NOT named `test_*.py` on purpose, like `check_visibility_against_the_site.py`:
it needs the image's Node and esbuild and python-frontmatter, so it can only
run inside the container, and Windows' `PythonToolchainTests` discovers every
`scripts/test_*.py`. `verify.sh` runs it in the image:

    docker run --rm \
      -v "$(pwd)/scripts/check_print_rules_against_the_site.py:/opt/scripts/check_print_rules_against_the_site.py:ro" \
      quartz-teacher:dev-test python3 /opt/scripts/check_print_rules_against_the_site.py

Two halves:

1. `support/quartz/components/scripts/printRules.ts` - the file the page's
   own print code imports - is bundled with the scaffold's esbuild and every
   case in `contracts/shared-rules.json` -> `printablePages` (answerCallouts,
   labels, titleCleaning, pageLabels, curriculumConnection) is run through it
   in Node. The Python
   tests cannot reach these: the rule lives in the browser.
2. Every typed line in `contracts/file-formats.json` -> `pageOptIns` is put
   through the build's own reader (python-frontmatter, after
   `build_site.process_frontmatter`), and what comes out must be the parsed
   value the case states. So a PyYAML raise that changed what `printable: yes`
   or an unquoted `[[x.pdf]]` means fails here.
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import build_site  # noqa: E402
import contracts  # noqa: E402
import toolchain_paths  # noqa: E402

RULES_TS = toolchain_paths.SUPPORT_DIR / "quartz" / "components" / "scripts" / "printRules.ts"
ESBUILD = toolchain_paths.QUARTZ_DIR / "node_modules" / "esbuild" / "bin" / "esbuild"

RUNNER = r"""
const rules = require(process.argv[2])
const pages = JSON.parse(require("fs").readFileSync(process.argv[3], "utf-8"))
const failures = []
const words = pages.words
const kinds = pages.answerCallouts.answerKinds
const titleWords = pages.answerCallouts.answerTitleWords
for (const c of pages.answerCallouts.cases) {
  const got = rules.role(c.kind, c.folded, c.title, kinds, titleWords)
  if (got !== c.role) failures.push(`answerCallouts ${JSON.stringify(c.title)}: ${got} != ${c.role}`)
}
for (const c of pages.labels.cases) {
  const got = rules.label(c.title, c.kind, c.listItem, c.heading, c.answerNumber, words, titleWords)
  if (got !== c.label) failures.push(`labels ${JSON.stringify(c.title)}: ${JSON.stringify(got)} != ${JSON.stringify(c.label)}`)
}
for (const c of pages.titleCleaning.cases) {
  const got = rules.cleanTitle(c.title)
  if (got !== c.cleaned) failures.push(`titleCleaning ${JSON.stringify(c.title)}: ${JSON.stringify(got)}`)
}
for (const c of pages.pageLabels.cases) {
  const got = rules.pageLabel(c.part, c.n, c.total, words)
  if (got !== c.label) failures.push(`pageLabels ${c.part} ${c.n}/${c.total}: ${got}`)
}
const curriculum = pages.curriculumConnection
for (const c of curriculum.headings) {
  const got = rules.isCurriculumHeading(c.heading, curriculum.headingWords)
  if (got !== c.curriculum) failures.push(`curriculumConnection.headings ${JSON.stringify(c.heading)}: ${got} != ${c.curriculum}`)
}
for (const c of curriculum.sections) {
  const blocks = c.blocks.map((text) => {
    const heading = /^(#{1,6}) (.*)$/.exec(text)
    return heading ? { heading: heading[2], level: heading[1].length } : { heading: null, level: 0 }
  })
  const leftOff = rules.leftOffPaper(blocks, curriculum.headingWords)
  const printed = c.blocks.filter((text, index) => !leftOff[index])
  if (JSON.stringify(printed) !== JSON.stringify(c.printed)) failures.push(`curriculumConnection.sections ${c.name}: prints ${JSON.stringify(printed)}`)
}
const count = pages.answerCallouts.cases.length + pages.labels.cases.length +
  pages.titleCleaning.cases.length + pages.pageLabels.cases.length +
  curriculum.headings.length + curriculum.sections.length
console.log(JSON.stringify({ count, failures }))
"""


def run_the_rules_in_node(folder: Path) -> list:
    bundle = folder / "printRules.cjs"
    subprocess.run([str(ESBUILD), str(RULES_TS), "--bundle", "--format=cjs", "--platform=node",
                    f"--outfile={bundle}", "--log-level=warning"], check=True)
    pages = folder / "printablePages.json"
    pages.write_text(json.dumps(contracts.section("shared-rules", "printablePages")), encoding="utf-8")
    runner = folder / "runner.js"
    runner.write_text(RUNNER, encoding="utf-8")
    output = subprocess.run(["node", str(runner), str(bundle), str(pages)],
                            check=True, capture_output=True, text=True).stdout
    result = json.loads(output.strip().splitlines()[-1])
    print(f"printRules.ts: {result['count']} contract cases run in Node")
    return result["failures"]


def read_through_the_build(folder: Path, lines: list, key: str):
    """What the site will read for `key` after the build has processed the page."""
    page = folder / "page.md"
    page.write_text("---\n" + "\n".join(lines) + "\n---\nBody.\n", encoding="utf-8")
    build_site.process_frontmatter(page, 1)
    return build_site.frontmatter.load(page).get(key)


def run_the_typed_lines(folder: Path) -> list:
    failures = []
    reading = contracts.section("file-formats", "pageOptIns", "readingCases", "cases")
    for case in reading:
        got = read_through_the_build(folder, case["lines"], "printable")
        if got != case["printable"] or type(got) is not type(case["printable"]):
            failures.append(f"readingCases {case['lines']}: the build reads {got!r}, the contract says {case['printable']!r}")
    pdf_cases = contracts.section("file-formats", "pageOptIns", "printPdfCases", "cases")
    typed = 0
    for case in pdf_cases:
        if "typed" not in case:
            continue
        typed += 1
        got = read_through_the_build(folder, [case["typed"]], "printPdf")
        if got != case["printPdf"]:
            failures.append(f"printPdfCases {case['typed']}: the build reads {got!r}, the contract says {case['printPdf']!r}")
    print(f"pageOptIns: {len(reading)} reading cases and {typed} typed printPdf lines read through the build")
    return failures


def main() -> int:
    with tempfile.TemporaryDirectory() as name:
        folder = Path(name)
        failures = run_the_rules_in_node(folder) + run_the_typed_lines(folder)
    for failure in failures:
        print("FAIL " + failure)
    if failures:
        return 1
    print("OK: the printing rules in the contract hold in the site and in the build")
    return 0


if __name__ == "__main__":
    sys.exit(main())
