#!/usr/bin/env python3
"""
Every visibility reading case in the contract, run against what the SITE does.

NOT named `test_*.py` on purpose. This needs python-frontmatter AND the image's
own Node modules, so it can only run inside the container; a `test_` name would
put it in front of Windows' `PythonToolchainTests`, which discovers every
`scripts/test_*.py` and would fail on a machine that is not doing anything
wrong. `verify.sh` runs it in the image. It names the file the way the launchers
name a folder now (`--mount` with quoted fields, `,readonly`); by hand, the
shorter form below is the same thing, and is safe here because nothing about
this path can contain a colon:

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
# wrong without failing anything.
#
# Measured 2026-09-18 against python-frontmatter 1.3.0 / PyYAML 6.0.3. The
# ten forms the build's reader cannot read at all were "stops" until #246
# (2026-09-25): Quartz could not read them either, so the whole build stopped.
# Since #246 the build hides a page whose settings it cannot read, so they are
# "hidden" — which is still not the "visible" each app reports, and so still
# not a shared case. "stops" is now a failure wherever it appears.
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
    ("title: x\n\tpublish: false", "hidden"),
    ("publish: \"false", "hidden"),
    ("publish: - false", "hidden"),
    ("publish: %", "hidden"),
    ("publish: @x", "hidden"),
    ("publish: `x", "hidden"),
    ("publish: false: true", "hidden"),
    ("title: x\npublish:false", "hidden"),
    # Added 2026-09-19 with issue #176. Each is a CONTINUATION form where the
    # reader's refusal is justified and the site's answer is not "visible", so
    # a shared case would oblige the other platform to be wrong. (The two
    # continuation forms the site PUBLISHES are shared cases now — they are in
    # `readingCases`, because there the reporting answer and the site agree.)
    ("publish:\n# note\n  false", "hidden"),
    ("publish: false\n  # note\n  false", "hidden"),
    ("publish: false # why\n  false", "hidden"),
]

# What a WRITER's continuation sweep is justified by — the page BEFORE the
# write, the page it becomes if the key's line is replaced and the lines below
# are LEFT, and the page it becomes when they go with the key.
#
# The sweep's whole argument is that the second column is not the first: a
# teacher asking for one of these pages to be HIDDEN was told it had been while
# students went on reading it, or the page stopped building. If the library
# ever stops folding these, the argument has changed and this is where that
# shows up.
#
# Since #246 the three left-behind pages that STOPPED the build are hidden
# instead, because the build hides a page whose settings it cannot read. That
# is what these writes asked for, and the sweep is still owed: the page is
# named as unreadable on every build, and the same orphan left behind by a
# write that SHOWS a page (`publish: true` over `publish:\n  a: 1`) would now
# hide the page the teacher asked to show.
#
# **What this does NOT pin is the sweep itself.** Nothing in `verify.sh` runs
# Swift or C#: delete `PageVisibilityReader.continuationLineIndices` and every
# row here still passes, because each column is a measurement of the BUILD
# rather than of an app. The apps are pinned by their own suites
# (`PageVisibilityReadingTests` on the mac, `PageVisibilityReadingTests.cs` on
# Windows) and by `pageVisibility.writingCases`, which both of them run. This
# list is the guard on the reasoning underneath them — a PyYAML or Quartz bump
# that made the sweep pointless, or wrong.
#
# Measured 2026-09-19, python-frontmatter 1.3.0 / PyYAML 6.0.3.
CONTINUATIONS_A_WRITER_MUST_SWEEP = [
    # before,                        before,    left behind,                        left,      swept,            swept
    ("publish: >-\n  false", "hidden", "publish: false\n  false", "visible", "publish: false", "hidden"),
    ("publish: |-\n  false", "hidden", "publish: false\n  false", "visible", "publish: false", "hidden"),
    ("publish:\n  false", "hidden", "publish: false\n  false", "visible", "publish: false", "hidden"),
    ("publish:\n  a: 1", "visible", "publish: false\n  a: 1", "hidden", "publish: false", "hidden"),
    ("publish:\n# note\n  false", "hidden", "publish: false\n# note\n  false", "hidden", "publish: false", "hidden"),
    ("publish:\n- a", "visible", "publish: false\n- a", "hidden", "publish: false", "hidden"),
    ("publish: false\n  false", "visible", "publish: false\n  false", "visible", "publish: false", "hidden"),
    ("publish: false\n\n  false", "visible", "publish: false\n\n  false", "visible", "publish: false", "hidden"),
    # The guard: a note with no value under it is NOT a continuation, and the
    # page is hidden either way.
    ("publish: false\n  # note", "hidden", "publish: false\n  # note", "hidden", "publish: false\n  # note", "hidden"),
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


def judge_whole_pages(work, pages):
    """Like `judge`, for cases that carry the WHOLE page, fences and all,
    written byte for byte."""
    processed = []
    for index, (text, section) in enumerate(pages):
        page = work / f"page{index}.md"
        with open(page, "w", encoding="utf-8", newline="") as handle:
            handle.write(text)
        build_site.process_frontmatter(page, section)
        with open(page, "r", encoding="utf-8", newline="") as handle:
            processed.append({"text": handle.read()})
    return processed


def main():
    cases = contracts.section("file-formats", "pageVisibility", "readingCases")
    unreadable_cases = contracts.section("shared-rules", "unreadablePageSettings", "cases")
    # Writing cases that say what the SITE does before and after the write
    # (#188 onwards). The byte comparison is each app's suite; this is the
    # other half — that the bytes it pins do what the case says on the site.
    judged_writes = []
    for case in contracts.section("file-formats", "pageVisibility", "writingCases", "cases"):
        if "expectSiteBefore" in case or "expectSiteAfter" in case:
            judged_writes.append(case)
    restore_cases = contracts.section(
        "course-management", "backups", "restoringOneSectionsKeys", "cases"
    )
    failures = []
    if len(restore_cases) < 6:
        failures.append(
            f"Only {len(restore_cases)} restoringOneSectionsKeys cases - the list has shrunk."
        )
    if len(judged_writes) < 8:
        failures.append(
            f"Only {len(judged_writes)} writing cases carry expectSiteBefore/After — the list "
            f"has shrunk, so this would pass having judged little."
        )
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
    sweeps = work / "sweeps"
    sweeps.mkdir()
    sweep_fragments = []
    for before, _, left, _, swept, _ in CONTINUATIONS_A_WRITER_MUST_SWEEP:
        sweep_fragments += [(before, 1), (left, 1), (swept, 1)]
    processed += judge(sweeps, sweep_fragments)
    unreadable = work / "unreadable"
    unreadable.mkdir()
    processed += judge_whole_pages(
        unreadable, [(case["page"], case["section"]) for case in unreadable_cases]
    )
    writes = work / "writes"
    writes.mkdir()
    write_pages = []
    for case in judged_writes:
        write_pages += [(case["before"], case["section"]), (case["after"], case["section"])]
    processed += judge_whole_pages(writes, write_pages)
    # A restore of one section, judged for EVERY section it names: putting
    # section 1 back must not move section 2 (#182).
    restores = work / "restores"
    restores.mkdir()
    restore_pages = []
    restore_checks = []
    for case in restore_cases:
        for section_text, expected in sorted(case["expectSite"].items()):
            restore_pages.append((case["after"], int(section_text)))
            restore_checks.append((case, int(section_text), expected))
    processed += judge_whole_pages(restores, restore_pages)

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

    sweep_start = (
        len(cases) + len(FORMS_THE_CONTRACT_CANNOT_CARRY) + len(KNOWN_TO_DIFFER)
    )
    sweep_verdicts = verdicts[sweep_start:]
    for position, row in enumerate(CONTINUATIONS_A_WRITER_MUST_SWEEP):
        before, before_says, left, left_says, swept, swept_says = row
        for offset, (fragment, expected) in enumerate(
            ((before, before_says), (left, left_says), (swept, swept_says))
        ):
            verdict = sweep_verdicts[position * 3 + offset]
            actual = "stops" if verdict["error"] is not None else (
                "visible" if verdict["visible"] else "hidden"
            )
            if actual != expected:
                failures.append(
                    f"{fragment!r}: measured as {expected} and the build now says {actual}. "
                    f"This is one of the three columns a WRITER's continuation sweep is "
                    f"justified by — the sweep's argument is that leaving a value's lines "
                    f"behind changes what students see. Re-read "
                    f"documentation/08-course-config-reference.md before changing either "
                    f"writer."
                )

    unreadable_start = sweep_start + 3 * len(CONTINUATIONS_A_WRITER_MUST_SWEEP)
    for case, verdict in zip(unreadable_cases, verdicts[unreadable_start:]):
        actual = "stops" if verdict["error"] is not None else (
            "visible" if verdict["visible"] else "hidden"
        )
        expected = "hidden" if case["expectHidden"] else "visible"
        if actual != expected:
            failures.append(
                f"{case['name']!r} (unreadablePageSettings): the contract says {expected} "
                f"and the site says {actual}. A page whose settings the build cannot "
                f"read must be HIDDEN on the site and must never stop the build (#246)."
            )

    writes_start = unreadable_start + len(unreadable_cases)
    write_verdicts = verdicts[writes_start:]
    for position, case in enumerate(judged_writes):
        for offset, (field, text) in enumerate(
            (("expectSiteBefore", case["before"]), ("expectSiteAfter", case["after"]))
        ):
            if field not in case:
                continue
            verdict = write_verdicts[position * 2 + offset]
            actual = "stops" if verdict["error"] is not None else (
                "visible" if verdict["visible"] else "hidden"
            )
            if actual != case[field]:
                failures.append(
                    f"{text!r} (pageVisibility.writingCases, {field}, section "
                    f"{case['section']}): the contract says {case[field]} and the site "
                    f"says {actual}. why: {case.get('why', '')}"
                )

    restores_start = writes_start + 2 * len(judged_writes)
    for (case, section_number, expected), verdict in zip(
        restore_checks, verdicts[restores_start:]
    ):
        actual = "stops" if verdict["error"] is not None else (
            "visible" if verdict["visible"] else "hidden"
        )
        if actual != expected:
            failures.append(
                f"{case['name']!r} (backups.restoringOneSectionsKeys, section "
                f"{section_number}): the contract says {expected} and the site says "
                f"{actual}. why: {case.get('why', '')}"
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
        f"{len(KNOWN_TO_DIFFER)} knowingly-different forms and "
        f"{len(CONTINUATIONS_A_WRITER_MUST_SWEEP)} continuations a writer must sweep "
        f"(three pages each) and {len(unreadable_cases)} unreadable-settings cases "
        f"and {len(judged_writes)} writing cases (before and after) and "
        f"{len(restore_checks)} restored pages (per section) down the real chain."
    )
    if failures:
        for line in failures:
            print("FAIL: " + line)
        return 1
    print("Every case agrees with the built site.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
