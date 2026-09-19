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

# Forms the SHARED contract deliberately cannot carry, measured here anyway.
#
# Each app reads these as "cannot tell" and reports them as visible, so a
# shared case stating what the SITE does would oblige the other platform to be
# wrong in the same direction. The measurement still has to be pinned
# somewhere: these are the lines each reader's REFUSAL is justified by, and a
# PyYAML or Quartz change that moved any of them would make those refusals
# wrong without failing anything. "stops" means the build cannot parse the
# page at all, which is why there is no verdict to mirror.
#
# Measured 2026-09-18 against python-frontmatter 1.3.0 / PyYAML 6.0.3.
FORMS_THE_CONTRACT_CANNOT_CARRY = [
    ("publish:\n  false", "hidden"),
    ("publish:\n\n  false", "hidden"),
    ("draft:\n  true", "hidden"),
    ("publishForSection1:\n  false", "hidden"),
    ("publish: !!str false", "hidden"),
    ("publish: !!bool false", "hidden"),
    ("publish: >-\n  false", "hidden"),
    ("publish: |-\n  false", "hidden"),
    ("publish: &flag false", "hidden"),
    ("flag: &flag false\npublish: *flag", "hidden"),
    ("publish: \"fal\\u0073e\"", "hidden"),
    ("publish: [false]", "visible"),
    ("publish: {a: false}", "visible"),
    ("publish: 'fal''se'", "visible"),
    ("title: x\n\tpublish: false", "stops"),
    ("publish: \"false", "stops"),
    ("publish: - false", "stops"),
    ("publish: %", "stops"),
    ("publish: @x", "stops"),
    ("publish: `x", "stops"),
    ("publish: false: true", "stops"),
    ("title: x\npublish:false", "stops"),
]

# The one answer both readers knowingly get WRONG, pinned so it cannot quietly
# become a different wrongness.
#
# YAML's whitespace is a space and a tab, so `false<NBSP>` is the string
# "false\xa0" and the page is published — which is what both readers say, and
# what the build says whenever anything sorts after `publish` in the re-dumped
# block. ALONE it is different: python-frontmatter's `YAMLHandler.export` ends
# with `yaml.dump(...).strip()`, and with `publish` sorting last that strip
# takes the non-breaking space off, so the build HIDES the page. Both readers
# still say visible, which is the mild direction. Written down here because a
# knowingly-wrong answer is only safe while the reason for it holds.
KNOWN_TO_DIFFER = [
    ("publish: false\u00a0", "hidden", "the readers say VISIBLE"),
    ("publish: false\u00a0\ntitle: x", "visible", "and here they agree"),
]

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


def judge(work, frontmatters):
    """Run each frontmatter fragment down the real chain; return what it became."""
    processed = []
    for index, (fragment, section) in enumerate(frontmatters):
        page = work / f"page{index}.md"
        page.write_text("---\n" + fragment + "\n---\n\nThe lesson.\n", encoding="utf-8")
        build_site.process_frontmatter(page, section)
        processed.append({"text": page.read_text(encoding="utf-8")})
    return processed


def main():
    cases = contracts.section("file-formats", "pageVisibility", "readingCases")
    failures = []
    the_chain_is_still_the_chain(failures)

    work = Path(tempfile.mkdtemp())
    shared = work / "shared"
    shared.mkdir()
    refused = work / "refused"
    refused.mkdir()
    processed = judge(shared, [(case["page"], case.get("section", 1)) for case in cases])
    processed += judge(
        refused, [(fragment, 1) for fragment, _ in FORMS_THE_CONTRACT_CANNOT_CARRY]
    )
    differ = work / "differ"
    differ.mkdir()
    processed += judge(differ, [(fragment, 1) for fragment, _, _ in KNOWN_TO_DIFFER])

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

    for (fragment, expected), verdict in zip(
        FORMS_THE_CONTRACT_CANNOT_CARRY, verdicts[len(cases):]
    ):
        if verdict["error"] is not None:
            actual = "stops"
        else:
            actual = "visible" if verdict["visible"] else "hidden"
        if actual != expected:
            failures.append(
                f"{fragment!r}: this form was measured as {expected} and the build now says "
                f"{actual}. Each app REFUSES to read this form and reports it visible; the "
                f"refusal was justified by this measurement, so re-read "
                f"documentation/08-course-config-reference.md before changing either reader."
            )

    known_start = len(cases) + len(FORMS_THE_CONTRACT_CANNOT_CARRY)
    for (fragment, expected, note), verdict in zip(KNOWN_TO_DIFFER, verdicts[known_start:]):
        actual = "stops" if verdict["error"] is not None else (
            "visible" if verdict["visible"] else "hidden"
        )
        if actual != expected:
            failures.append(
                f"{fragment!r}: measured as {expected} ({note}) and the build now says "
                f"{actual}. Both readers knowingly answer this one the mild way round; "
                f"re-read documentation/08-course-config-reference.md, because the reason "
                f"they are allowed to has changed."
            )

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

    print(
        f"Ran {len(cases)} reading cases and "
        f"{len(FORMS_THE_CONTRACT_CANNOT_CARRY)} refused forms and "
        f"{len(KNOWN_TO_DIFFER)} knowingly-different forms down the real chain."
    )
    if failures:
        for line in failures:
            print("FAIL: " + line)
        return 1
    print("Every case agrees with the built site.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
