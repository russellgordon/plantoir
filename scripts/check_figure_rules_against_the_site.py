#!/usr/bin/env python3
"""
The figure rules in the contract, run against the REAL engines (#485 E1).

NOT named `test_*.py` on purpose, like `check_print_rules_against_the_site.py`:
it needs the image's Node, node-tikzjax and function-plot, so it can only run
inside the container (Windows' `PythonToolchainTests` discovers every
`scripts/test_*.py`). `verify.sh` runs it in the image.

What `scripts/test_figures.py` cannot reach without the engines:

1. `support/quartz/plugins/transformers/figureRules.js` - the file the site's
   transformer and the build's helper both import - runs every
   figureFences.tidy and cacheKey case in Node, so the JavaScript and the
   Python agree byte for byte (review S4).
2. The helper (support/figures/plantoir-figures.mjs), driven through
   `figures.run_jobs` exactly as a build drives it, answers every
   figureFences.texErrors case with real TeX (the never-ending definition
   with a 3 s clock, so it is stopped and the next case still drawn), every
   functionplot.parseCases and expressionCases case with the real evaluator,
   and every functionplot alt case.
"""
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import contracts  # noqa: E402
import figures  # noqa: E402
import toolchain_paths  # noqa: E402

RULES_JS = toolchain_paths.SUPPORT_DIR / "quartz" / "plugins" / "transformers" / "figureRules.js"

RUNNER = r"""
import { readFileSync } from "fs"
import { pathToFileURL } from "url"
const rules = await import(pathToFileURL(process.argv[2]).href)
const block = JSON.parse(readFileSync(process.argv[3], "utf-8"))
const failures = []
for (const c of block.tidy.cases) {
  const got = rules.tidy(c.body)
  if (got !== c.tidy) failures.push(`tidy ${JSON.stringify(c.body)}: ${JSON.stringify(got)} != ${JSON.stringify(c.tidy)}`)
}
for (const c of block.cacheKey.cases) {
  const got = rules.keyOf(c.body)
  if (got !== c.key) failures.push(`cacheKey: ${got} != ${c.key}`)
}
for (const c of block.alt.cases) {
  if (c.engine !== "tikz") continue
  const got = rules.altOf(c.body)
  if (got !== c.alt) failures.push(`alt ${JSON.stringify(c.body)}: ${JSON.stringify(got)} != ${JSON.stringify(c.alt)}`)
}
console.log(JSON.stringify(failures))
"""


def main() -> int:
    block = contracts.section("shared-rules", "figureFences")
    failures = []
    work = Path(tempfile.mkdtemp(prefix="plantoir-figure-rules-"))
    try:
        # The rules file is an ES module, as the section's Quartz (type:
        # module) reads it; a copy beside a package.json saying so.
        (work / "package.json").write_text('{"type": "module"}\n', encoding="utf-8")
        shutil.copyfile(RULES_JS, work / "figureRules.js")
        (work / "runner.mjs").write_text(RUNNER, encoding="utf-8")
        (work / "block.json").write_text(json.dumps(block), encoding="utf-8")
        said = subprocess.run(["node", str(work / "runner.mjs"), str(work / "figureRules.js"),
                               str(work / "block.json")], capture_output=True, text=True)
        if said.returncode != 0:
            failures.append("the rules did not run in Node: " + said.stderr.strip()[-400:])
        else:
            failures.extend(json.loads(said.stdout.strip().splitlines()[-1]))

        # The helper as a build drives it, with the section's own copy of
        # the rules standing in.
        output = work / "section"
        (output / "quartz" / "plugins" / "transformers").mkdir(parents=True)
        shutil.copyfile(RULES_JS, output / "quartz" / "plugins" / "transformers" / "figureRules.js")
        (output / "package.json").write_text('{"type": "module"}\n', encoding="utf-8")
        command = figures.helper_command(output)

        jobs = []
        expected = {}
        for case in block["texErrors"]["cases"]:
            jobs.append({"id": len(jobs) + 1, "engine": "tikz", "body": case["body"]})
            expected[len(jobs)] = ("texErrors", case)
        for case in block["functionplot"]["parseCases"]:
            jobs.append({"id": len(jobs) + 1, "engine": "functionplot", "body": case["body"]})
            expected[len(jobs)] = ("parseCases", case)
        for case in block["functionplot"]["expressionCases"]["cases"]:
            jobs.append({"id": len(jobs) + 1, "engine": "functionplot", "body": "y = " + case["fn"]})
            expected[len(jobs)] = ("expressionCases", case)
        for case in block["alt"]["cases"]:
            if case["engine"] == "functionplot":
                jobs.append({"id": len(jobs) + 1, "engine": "functionplot", "body": case["body"]})
                expected[len(jobs)] = ("alt", case)
        # A drawing after the one that never finishes must still be drawn.
        jobs.append({"id": len(jobs) + 1, "engine": "tikz",
                     "body": "\\begin{document}\n\\begin{tikzpicture}\\draw (0,0) -- (1,1);\\end{tikzpicture}\n\\end{document}"})
        expected[len(jobs)] = ("afterTheStop", None)

        results = figures.run_jobs(jobs, command, job_seconds=3, start_seconds=60, printer=print)
        site_words = block["words"]["site"]
        for job in jobs:
            kind, case = expected[job["id"]]
            answer = results.get(job["id"]) or {}
            if kind == "afterTheStop":
                if not answer.get("ok"):
                    failures.append(f"the diagram after the one that was stopped was not drawn: {answer}")
                continue
            if kind == "texErrors":
                name = case["name"]
                if case["reason"] is None:
                    if not answer.get("ok"):
                        failures.append(f"texErrors {name}: not drawn: {answer}")
                    continue
                if answer.get("ok") or answer.get("reason") != case["reason"]:
                    failures.append(f"texErrors {name}: reason {answer.get('reason')!r}, not {case['reason']!r}")
                    continue
                block_line = None
                if answer.get("texLine") is not None:
                    _, came_from = figures.tidy_lines(case["body"])
                    index = int(answer["texLine"]) - 1
                    block_line = came_from[index] if 0 <= index < len(came_from) else None
                if block_line != case["blockLine"]:
                    failures.append(f"texErrors {name}: line {block_line}, not {case['blockLine']}")
                if case.get("command") and answer.get("name") != case["command"]:
                    failures.append(f"texErrors {name}: named {answer.get('name')!r}, not {case['command']!r}")
                continue
            problems = sorted(answer.get("problems") or [], key=lambda problem: problem.get("blockLine") or 0)
            first = problems[0] if problems else None
            if kind == "parseCases":
                label = case["name"]
                want = case["problem"]
                if want is None:
                    if not answer.get("ok"):
                        failures.append(f"parseCases {label}: not drawn: {problems}")
                        continue
                    plot = answer.get("plot") or {}
                    for field in ("functions", "bounds", "title", "disableZoom"):
                        if field in case and plot.get(field) != case[field]:
                            failures.append(f"parseCases {label}: {field} {plot.get(field)!r}, not {case[field]!r}")
                    if "alt" in case and answer.get("alt") != case["alt"]:
                        failures.append(f"parseCases {label}: alt {answer.get('alt')!r}, not {case['alt']!r}")
                    if "unknown" in case and answer.get("unknown") != case["unknown"]:
                        failures.append(f"parseCases {label}: unknown {answer.get('unknown')!r}, not {case['unknown']!r}")
                elif answer.get("ok") or first is None or first.get("reason") != want["reason"] \
                        or first.get("blockLine") != want["blockLine"]:
                    failures.append(f"parseCases {label}: first problem {first}, not {want}")
                continue
            if kind == "expressionCases":
                label = case["fn"]
                if case["problem"] is None:
                    if not answer.get("ok"):
                        failures.append(f"expressionCases {label}: refused: {problems}")
                elif answer.get("ok") or first is None or first.get("reason") != case["problem"]:
                    failures.append(f"expressionCases {label}: {first}, not {case['problem']}")
                elif case.get("name") and first.get("name") != case["name"]:
                    failures.append(f"expressionCases {label}: named {first.get('name')!r}, not {case['name']!r}")
                continue
            if kind == "alt":
                alt = answer.get("alt") or figures.describe_plot(answer.get("plot") or {}, site_words)
                if alt != case["alt"]:
                    failures.append(f"alt {case['body']!r}: {alt!r}, not {case['alt']!r}")
    finally:
        shutil.rmtree(work, ignore_errors=True)

    for failure in failures:
        print("   " + failure)
    print(f"{'FAIL' if failures else 'PASS'}: figureFences rules against the real engines "
          f"({len(failures)} problem(s))")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
