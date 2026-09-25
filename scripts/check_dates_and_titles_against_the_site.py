#!/usr/bin/env python3
"""
Every date-and-title writing case in the contract, run against what the SITE reads.

NOT named `test_*.py` on purpose, for the reason its sibling
`check_visibility_against_the_site.py` gives: it needs python-frontmatter,
which only the image has, and a `test_` name would put it in front of Windows'
`PythonToolchainTests`. `verify.sh` runs it in the image:

    docker run --rm \
      -v "$(pwd)/scripts/check_dates_and_titles_against_the_site.py:/opt/scripts/check_dates_and_titles_against_the_site.py:ro" \
      quartz-teacher:dev-test python3 /opt/scripts/check_dates_and_titles_against_the_site.py

**What it proves that a unit test cannot.** `contracts/file-formats.json` ->
`datesAndTitles.writingCases` says, for each page a writer produces, what the
built site reads as its date or title (`expectSiteReads`). Both apps are tested
against the `after` text; this checks the `expectSiteReads` beside it is TRUE,
by running each `after` through `build_site.process_frontmatter` — the step
that parses the page and re-dumps it for Quartz — so a PyYAML or
python-frontmatter bump cannot quietly make the table wrong. GitHub #199.
"""

import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True

import build_site
import contracts
import frontmatter


def main():
    cases = contracts.section("file-formats", "datesAndTitles", "writingCases", "cases")
    if len(cases) < 13:
        print(f"Only {len(cases)} cases — the list has shrunk, so this would pass having read little.")
        return 1
    failures = []
    work = Path(tempfile.mkdtemp())
    for index, case in enumerate(cases):
        key = case["write"].get("key", "title")
        page = work / f"page{index}.md"
        page.write_bytes(case["after"].encode("utf-8"))
        try:
            build_site.process_frontmatter(page, 1)
            value = frontmatter.load(page).metadata.get(key)
        except Exception as error:  # the build stopping is a finding, not a crash
            value = f"<the build stopped: {type(error).__name__}>"
        if str(value) != case["expectSiteReads"]:
            failures.append(
                f"case {index} ({case['why'][:60]}…): the site reads {key} = {value!r}, "
                f"the contract says {case['expectSiteReads']!r}"
            )
    for failure in failures:
        print("❌ " + failure)
    if failures:
        return 1
    print(f"✅ {len(cases)} date and title cases read on the site as the contract says")
    return 0


if __name__ == "__main__":
    sys.exit(main())
