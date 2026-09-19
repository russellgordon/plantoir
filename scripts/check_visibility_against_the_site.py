#!/usr/bin/env python3
"""
Every visibility reading case in the contract, run against what the SITE does.

NOT named `test_*.py` on purpose. This needs python-frontmatter AND the image's
own Node modules, so it can only run inside the container; a `test_` name would
put it in front of Windows' `PythonToolchainTests`, which discovers every
`scripts/test_*.py` and would fail on a machine that is not doing anything
wrong. `verify.sh` mounts and runs it:

    docker run --rm \
      -v "$(pwd)/scripts/check_visibility_against_the_site.py:/opt/scripts/check_visibility_against_the_site.py:ro" \
      quartz-teacher:dev-test python3 /opt/scripts/check_visibility_against_the_site.py

**What it proves that a unit test cannot.** `contracts/file-formats.json` ->
`pageVisibility.readingCases` states, as fact, what the built site does with
fifty-odd frontmatter lines. Both apps are tested against that list — so if the
list is wrong, both apps are confidently wrong together and every suite stays
green. This runs each case down the REAL chain instead:

    the teacher's line
      -> build_site.process_frontmatter   (python-frontmatter, PyYAML, YAML 1.1)
      -> gray-matter + js-yaml on JSON_SCHEMA   (what Quartz v4.5.0 parses with)
      -> patches/publish.ts's own expression

so a PyYAML bump, a Quartz bump, or a patch someone rewrote cannot move the
table without this failing. It also re-runs `build_site._is_draft`, the
curriculum-coverage map's separate reader, over the same post-processed text:
that one is supposed to agree with the site, and until 2026-09-18 it did not.
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

import build_site
import contracts

QUARTZ = Path("/opt/quartz")
FRONTMATTER_TRANSFORMER = QUARTZ / "quartz/plugins/transformers/frontmatter.ts"
PUBLISH_FILTER = QUARTZ / "quartz/plugins/filters/publish.ts"

# The Node half. Deliberately spelled the way Quartz and the patch spell it,
# so a reader can hold the three files side by side.
NODE_SOURCE = """
import fs from "fs"
import matter from "/opt/quartz/node_modules/gray-matter/index.js"
import yaml from "/opt/quartz/node_modules/js-yaml/index.js"

const pages = JSON.parse(fs.readFileSync(process.argv[2], "utf8"))
const out = []
for (const page of pages) {
  try {
    const { data } = matter(Buffer.from(page.text, "utf8"), {
      delimiters: "---",
      language: "yaml",
      engines: { yaml: (s) => yaml.load(s, { schema: yaml.JSON_SCHEMA }) },
    })
    const flag = data?.publish
    out.push({ visible: !(flag === false || flag === "false"), error: null })
  } catch (e) {
    out.push({ visible: null, error: String(e).split("\\n")[0] })
  }
}
fs.writeFileSync(process.argv[3], JSON.stringify(out))
"""


def the_chain_is_still_the_chain(failures):
    """The two lines this whole check is calibrated against."""
    if not FRONTMATTER_TRANSFORMER.exists():
        failures.append("Quartz's frontmatter transformer is not where it was.")
        return
    transformer = FRONTMATTER_TRANSFORMER.read_text(encoding="utf-8")
    if "yaml.JSON_SCHEMA" not in transformer:
        failures.append(
            "Quartz no longer parses frontmatter with js-yaml's JSON_SCHEMA. The whole "
            "table in contracts/file-formats.json -> pageVisibility is calibrated "
            "against that schema — re-measure it before changing this line."
        )
    if not PUBLISH_FILTER.exists():
        failures.append("The publish filter is not where it was.")
        return
    publish_filter = PUBLISH_FILTER.read_text(encoding="utf-8")
    if 'flag === false || flag === "false"' not in publish_filter:
        failures.append(
            "patches/publish.ts no longer holds a page back for exactly `false` and "
            '"false". Every reading case in the contract follows from that expression.'
        )


def main():
    cases = contracts.section("file-formats", "pageVisibility", "readingCases")
    failures = []
    the_chain_is_still_the_chain(failures)

    work = Path(tempfile.mkdtemp())
    processed = []
    for index, case in enumerate(cases):
        page = work / f"case{index}.md"
        page.write_text("---\n" + case["page"] + "\n---\n\nThe lesson.\n", encoding="utf-8")
        build_site.process_frontmatter(page, case.get("section", 1))
        processed.append({"text": page.read_text(encoding="utf-8")})

    pages_json = work / "pages.json"
    pages_json.write_text(json.dumps(processed), encoding="utf-8")
    node_script = work / "judge.mjs"
    node_script.write_text(NODE_SOURCE, encoding="utf-8")
    verdicts_json = work / "verdicts.json"
    subprocess.run(
        ["node", str(node_script), str(pages_json), str(verdicts_json)],
        check=True,
    )
    verdicts = json.loads(verdicts_json.read_text(encoding="utf-8"))

    for case, after, verdict in zip(cases, processed, verdicts):
        wanted = case["expectVisible"]
        if verdict["error"] is not None:
            failures.append(
                f"{case['page']!r}: the site could not parse this page at all "
                f"({verdict['error']}). A case the build cannot read does not belong "
                f"in readingCases."
            )
            continue
        if verdict["visible"] != wanted:
            failures.append(
                f"{case['page']!r} (section {case.get('section', 1)}): the contract says "
                f"expectVisible={wanted}, the real build says {verdict['visible']}. "
                f"After process_frontmatter the page reads {after['text']!r}. "
                f"why: {case.get('why', '')}"
            )
        coverage_map_says_visible = not build_site._is_draft(after["text"])
        if coverage_map_says_visible != verdict["visible"]:
            failures.append(
                f"{case['page']!r}: the curriculum-coverage map's reader "
                f"(build_site._is_draft) says visible={coverage_map_says_visible} about "
                f"a page the site says visible={verdict['visible']}."
            )

    print(f"Ran {len(cases)} reading cases down the real chain.")
    if failures:
        for line in failures:
            print("FAIL: " + line)
        return 1
    print("Every case agrees with the built site.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
