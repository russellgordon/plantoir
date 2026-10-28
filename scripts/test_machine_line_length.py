#!/usr/bin/env python3
"""
`contracts/shared-rules.json` -> `machineLineLength` (#666): every machine
line the shared Python prints is at most `maxCharacters` long, prefix
included, and a line that would be longer is SHORTENED - never cut mid-text -
so its reader parses it as it parses a whole one.

Every `cases` entry runs through the REAL emitter (`build_site`'s
`announce_dated_pages` and `announce_coverage_maps`, `how_i_teach.announce`,
`site_health.announce`) with a capturing printer. The length bound and the
parse are checked independently of the expected numbers, so a wrong `kept` in
the contract is caught as well as a line that is too long. The bounded
markers are held under the cap at their worst plausible size.

Stdlib only, plus what `build_site` imports; on the mac in `verify.sh` since
#666, on Windows in `PythonToolchainTests`.
"""

import json
import sys
import unittest
from pathlib import Path

sys.dont_write_bytecode = True

import contracts
import toolchain_paths

REPO = Path(__file__).resolve().parent.parent
if (REPO / "contracts").is_dir():
    toolchain_paths.CONTRACTS_DIR = REPO / "contracts"
contracts.reset_cache()

import build_site  # noqa: E402
import how_i_teach  # noqa: E402
import machine_line  # noqa: E402
import site_health  # noqa: E402


def rule(*keys):
    return contracts.section("shared-rules", "machineLineLength", *keys)


def made(items: dict) -> list:
    """`{template, count}` -> the entries, `{n}` filled 1..count, in strings or dict values."""
    template = items["template"]
    entries = []
    for n in range(1, items["count"] + 1):
        if isinstance(template, dict):
            entries.append({key: (value.replace("{n}", str(n)) if isinstance(value, str) else value)
                            for key, value in template.items()})
        else:
            entries.append(template.replace("{n}", str(n)))
    return entries


def emitted(case: dict) -> list:
    """The machine lines the real emitter prints for one case."""
    said = []
    marker = case["marker"]
    entries = made(case["items"])
    if marker == "PLANTOIR_DATED:":
        build_site.announce_dated_pages({"rewritten": entries}, "ICS4U", 1, printer=said.append)
    elif marker == "PLANTOIR_KEPT_OFF:":
        how_i_teach.announce("ICS4U", 1, True, [], entries, printer=said.append)
    elif marker == "PLANTOIR_MAPS:":
        build_site.announce_coverage_maps(entries, "ICS3U", 1, printer=said.append)
    elif marker == "PLANTOIR_HEALTH:":
        facts = {"media_target_exists": True, "section_index_exists": True, case["facts"]: entries}
        site_health.announce(site_health.findings(facts, "ICS4U", 1), printer=said.append)
    else:
        raise AssertionError(f"no emitter for {marker}")
    return [line for line in said if line.startswith(marker)]


class TheCapHolds(unittest.TestCase):
    def test_every_case_through_its_real_emitter(self):
        limit = rule("maxCharacters")
        for case in rule("cases"):
            with self.subTest(case=case["name"]):
                lines = emitted(case)
                self.assertEqual(len(lines), 1, lines)
                line = lines[0]
                self.assertLessEqual(len(line), limit)
                payload = json.loads(line[len(case["marker"]):])
                expect = case["expect"]
                total = case["items"]["count"]
                if case["marker"] == "PLANTOIR_HEALTH:":
                    named = sum(1 for entry in made(case["items"]) if entry["to"] in payload["detail"])
                    self.assertEqual(named, expect["named"])
                    self.assertIn(str(total), payload["sentence"], "the sentence keeps the true count")
                    if expect["named"] < total:
                        # The filled andMore, not just its number: a bare digit
                        # is in a page name ("Unit 1/...") as often as not.
                        table = site_health._checks_by_name()
                        and_more = site_health.filled(table[payload["name"]]["andMore"],
                                                      {"count": total - expect["named"]})
                        self.assertIn(and_more, payload["detail"])
                    continue
                key = rule("lists")[case["marker"]]
                kept = len(payload[key])
                self.assertEqual(kept, expect["kept"])
                self.assertEqual(payload[key], made(case["items"])[:kept], "the FIRST entries are kept")
                if kept == total:
                    self.assertNotIn("count", payload)
                    self.assertNotIn("more", payload)
                else:
                    self.assertEqual(payload["count"], total)
                    self.assertEqual(payload["more"], total - kept)
                    # The most that fit: one more entry would not have.
                    longer = dict(payload, **{key: made(case["items"])[:kept + 1], "more": total - kept - 1})
                    self.assertGreater(len(machine_line.text(case["marker"], longer)), limit)

    def test_a_short_list_is_printed_exactly_as_before(self):
        said = []
        build_site.announce_dated_pages({"rewritten": ["section1/index", "Exercises/Using Aggregate Functions"]},
                                        "ICS4U", 1, printer=said.append)
        example = contracts.section("shared-rules", "pagesDatedByTheBuild", "marker", "examples")[0]
        self.assertEqual(said[-1], example)

    def test_the_bounded_markers_stay_under_the_cap_at_their_worst(self):
        limit = rule("maxCharacters")
        long_code = "A" * 40
        worst = [
            "PLANTOIR_MY_PROGRESS: " + json.dumps({"course": long_code, "section": 99, "built": False,
                                                   "pages": 99999, "reason": "noSuccessCriteria"}),
            "PLANTOIR_REPAIRED: " + json.dumps({"course": long_code, "section": 99, "repair": "frontPageTitleQuoted",
                                                "page": "section99/index"}),
            "PLANTOIR_LINKS_CHECKLIST: " + json.dumps({"course": long_code, "section": 99,
                                                       "buildId": "20260929T233000Z-1a2b3c4d", "pages": 99999,
                                                       "ticked": 99999}),
            "PLANTOIR_SWIFT: " + json.dumps({"course": long_code, "downloadedBytes": 99999999999, "ready": True,
                                             "seconds": 99999, "section": 99}, sort_keys=True),
            "PLANTOIR_CLOUDFLARE_REMADE: " + long_code + "/99 " + "a" * 58 + " " + "a" * 58 + ".pages.dev",
        ]
        for line in worst:
            with self.subTest(line=line[:30]):
                self.assertLess(len(line), limit)
        for marker in rule("bounded"):
            self.assertTrue(any(line.startswith(marker) for line in worst), marker)

    def test_the_cap_leaves_room_for_wide_characters(self):
        # A Python character can be two UTF-16 units in C#, or two cells in a
        # console: twice the cap must fit the app's 8,000-unit carry and the
        # console's 8,192 columns (the C# suite pins the same against the code).
        self.assertLessEqual(2 * rule("maxCharacters"), 8000)


if __name__ == "__main__":
    unittest.main()
