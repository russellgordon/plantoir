#!/usr/bin/env python3
"""Tests for scripts/npm_audit.py, the comparator behind verify.sh's npm audit (#667).

    python3 scripts/test_npm_audit.py -v

No network and no Docker: the audits are real `npm audit --json` output from the
image (2026-10-24), trimmed, in scripts/testdata/npm-audit/. Windows'
PythonToolchainTests discovers this file, so the comparator Windows calls over its
runtime is gated there too.
"""

from __future__ import annotations

import copy
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPTS))

import npm_audit  # noqa: E402

FIXTURES = SCRIPTS / "testdata" / "npm-audit"

# In the trimmed fixtures: quartz has glob (one high) and ws (one moderate, one
# high); wrangler has sharp (three high) and the SAME two ws advisories.
GLOB_CLI = "GHSA-5j98-mcp5-4vw2"
WS_MEMORY_DOS = "GHSA-96hv-2xvq-fx4p"
WS_DISCLOSURE = "GHSA-58qx-3vcg-4xpx"
SHARP_IDS = ["GHSA-f88m-g3jw-g9cj", "GHSA-rgj7-g3m4-5g8c", "GHSA-wq5f-xc86-pv6w"]


def load(name: str) -> dict:
    return json.loads((FIXTURES / name).read_text(encoding="utf-8"))


def small_contract() -> dict:
    """A contract shaped like the real one, accepting exactly what the fixtures report."""
    sharp_advisories: list[dict] = []
    for identifier in SHARP_IDS:
        sharp_advisories.append({"id": identifier, "severity": "high"})
    return {
        "failsOn": ["high", "critical"],
        "trees": [
            {"tree": "quartz", "lockfile": "package-lock.json", "exposure": "build"},
            {"tree": "wrangler", "lockfile": "synthesised from the installed tree", "pin": "wrangler",
             "exposure": "deploy"},
            {"tree": "pagedjs", "lockfile": "synthesised from the pin", "pin": "pagedjs", "exposure": "browser"},
        ],
        "accepted": [
            {"tree": "quartz", "package": "glob", "exposure": "build", "reason": "the CLI is never run",
             "advisories": [{"id": GLOB_CLI, "severity": "high"}]},
            {"tree": "quartz", "package": "ws", "exposure": "preview", "reason": "preview only",
             "advisories": [{"id": WS_DISCLOSURE, "severity": "moderate"},
                            {"id": WS_MEMORY_DOS, "severity": "high"}]},
            {"tree": "wrangler", "package": "sharp", "exposure": "not run", "reason": "miniflare only",
             "advisories": sharp_advisories},
            {"tree": "wrangler", "package": "ws", "exposure": "not run", "reason": "miniflare only",
             "advisories": [{"id": WS_DISCLOSURE, "severity": "moderate"},
                            {"id": WS_MEMORY_DOS, "severity": "high"}]},
        ],
    }


def every_tree_audited() -> dict:
    return {
        "quartz": load("quartz-trimmed.json"),
        "wrangler": load("wrangler-trimmed.json"),
        "pagedjs": load("tikz-engine-clean.json"),
    }


def remove_advisory(contract: dict, tree: str, identifier: str) -> None:
    for entry in contract["accepted"]:
        if entry["tree"] != tree:
            continue
        kept: list[dict] = []
        for advisory in entry["advisories"]:
            if advisory["id"] != identifier:
                kept.append(advisory)
        entry["advisories"] = kept


def blocking_ids(report: dict) -> list[tuple[str, str]]:
    found: list[tuple[str, str]] = []
    for row in report["blocking"]:
        found.append((row["tree"], row["id"]))
    return found


class ComparatorTests(unittest.TestCase):

    def test_everything_accepted_is_clean(self) -> None:
        report = npm_audit.compare(every_tree_audited(), small_contract())
        self.assertEqual(report["blocking"], [])
        self.assertEqual(report["failed_trees"], [])
        self.assertEqual(len(report["accepted_seen"]), 8)
        self.assertEqual(npm_audit.exit_code(report), 0)

    def test_a_high_advisory_that_is_not_accepted_blocks(self) -> None:
        """The must-fail: take one accepted HIGH id out and the gate names it."""
        contract = small_contract()
        remove_advisory(contract, "quartz", WS_MEMORY_DOS)
        report = npm_audit.compare(every_tree_audited(), contract)
        self.assertEqual(blocking_ids(report), [("quartz", WS_MEMORY_DOS)])
        self.assertEqual(npm_audit.exit_code(report), 1)
        self.assertIn(WS_MEMORY_DOS, "\n".join(npm_audit.describe(report)))

    def test_a_moderate_that_is_not_accepted_is_reported_not_failed(self) -> None:
        contract = small_contract()
        remove_advisory(contract, "quartz", WS_DISCLOSURE)
        report = npm_audit.compare(every_tree_audited(), contract)
        self.assertEqual(report["blocking"], [])
        reported: list[str] = []
        for row in report["reported"]:
            reported.append(row["id"])
        self.assertEqual(reported, [WS_DISCLOSURE])
        self.assertEqual(npm_audit.exit_code(report), 0)

    def test_a_raised_severity_blocks_until_it_is_decided_again(self) -> None:
        contract = small_contract()
        for entry in contract["accepted"]:
            if entry["tree"] == "quartz" and entry["package"] == "ws":
                for advisory in entry["advisories"]:
                    if advisory["id"] == WS_MEMORY_DOS:
                        advisory["severity"] = "moderate"
        report = npm_audit.compare(every_tree_audited(), contract)
        self.assertEqual(blocking_ids(report), [("quartz", WS_MEMORY_DOS)])
        self.assertIn("re-decide", report["blocking"][0]["why"])
        self.assertEqual(npm_audit.exit_code(report), 1)

    def test_a_lowered_severity_is_still_accepted(self) -> None:
        contract = small_contract()
        for entry in contract["accepted"]:
            if entry["package"] == "glob":
                entry["advisories"][0]["severity"] = "critical"
        report = npm_audit.compare(every_tree_audited(), contract)
        self.assertEqual(npm_audit.exit_code(report), 0)

    def test_acceptance_is_per_tree(self) -> None:
        """ws's advisories accepted for quartz do not cover the same ids in wrangler."""
        contract = small_contract()
        kept: list[dict] = []
        for entry in contract["accepted"]:
            if not (entry["tree"] == "wrangler" and entry["package"] == "ws"):
                kept.append(entry)
        contract["accepted"] = kept
        report = npm_audit.compare(every_tree_audited(), contract)
        self.assertEqual(blocking_ids(report), [("wrangler", WS_MEMORY_DOS)])
        self.assertEqual(npm_audit.exit_code(report), 1)

    def test_offline_is_unreachable_never_clean(self) -> None:
        offline = load("offline.json")
        audits = {"quartz": offline, "wrangler": offline, "pagedjs": offline}
        report = npm_audit.compare(audits, small_contract())
        self.assertEqual(npm_audit.exit_code(report), 2)
        self.assertEqual(report["audited_trees"], [])

    def test_one_tree_offline_skips_the_whole_gate(self) -> None:
        audits = every_tree_audited()
        audits["wrangler"] = load("offline.json")
        report = npm_audit.compare(audits, small_contract())
        self.assertEqual(npm_audit.exit_code(report), 2)

    def test_a_pins_lockfile_that_could_not_be_built_offline_is_unreachable(self) -> None:
        audits = every_tree_audited()
        audits["pagedjs"] = load("lockfile-step-offline.json")
        report = npm_audit.compare(audits, small_contract())
        self.assertEqual(npm_audit.exit_code(report), 2)

    def test_a_blocking_advisory_wins_over_an_unreachable_tree(self) -> None:
        contract = small_contract()
        remove_advisory(contract, "quartz", GLOB_CLI)
        audits = every_tree_audited()
        audits["pagedjs"] = load("offline.json")
        report = npm_audit.compare(audits, contract)
        self.assertEqual(npm_audit.exit_code(report), 1)

    def test_no_lockfile_fails(self) -> None:
        audits = every_tree_audited()
        audits["wrangler"] = load("enolock.json")
        report = npm_audit.compare(audits, small_contract())
        self.assertEqual(npm_audit.exit_code(report), 1)
        self.assertEqual(report["failed_trees"][0][0], "wrangler")

    def test_an_installed_trees_lockfile_step_failing_fails_even_offline(self) -> None:
        """Only a lockfile built from a PIN may be unreachable; wrangler's is built from the
        installed tree, which needs no network (measured with --network none)."""
        audits = every_tree_audited()
        audits["wrangler"] = load("lockfile-step-offline.json")
        report = npm_audit.compare(audits, small_contract())
        self.assertEqual(npm_audit.exit_code(report), 1)

    def test_a_tree_that_was_not_audited_fails(self) -> None:
        audits = every_tree_audited()
        del audits["pagedjs"]
        report = npm_audit.compare(audits, small_contract())
        self.assertEqual(npm_audit.exit_code(report), 1)

    def test_a_tree_the_contract_does_not_name_fails(self) -> None:
        audits = every_tree_audited()
        audits["mystery"] = load("tikz-engine-clean.json")
        report = npm_audit.compare(audits, small_contract())
        self.assertEqual(npm_audit.exit_code(report), 1)

    def test_output_that_is_not_json_fails_never_skips(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            garbage = Path(folder) / "garbage.json"
            garbage.write_text("npm error code EAI_AGAIN\nnot json at all\n", encoding="utf-8")
            audits = every_tree_audited()
            audits["quartz"] = npm_audit.read_audit(garbage)
        self.assertIsNone(audits["quartz"])
        report = npm_audit.compare(audits, small_contract())
        self.assertEqual(npm_audit.exit_code(report), 1)

    def test_json_with_an_unknown_message_fails_never_skips(self) -> None:
        audits = every_tree_audited()
        audits["quartz"] = {"message": "something else went wrong", "error": {"summary": "", "detail": ""}}
        report = npm_audit.compare(audits, small_contract())
        self.assertEqual(npm_audit.exit_code(report), 1)

    def test_an_accepted_advisory_no_longer_reported_is_stale_not_failed(self) -> None:
        contract = small_contract()
        contract["accepted"][0]["advisories"].append({"id": "GHSA-xxxx-xxxx-xxxx", "severity": "high"})
        report = npm_audit.compare(every_tree_audited(), contract)
        self.assertEqual(report["stale"], [{"tree": "quartz", "id": "GHSA-xxxx-xxxx-xxxx", "package": "glob"}])
        self.assertEqual(npm_audit.exit_code(report), 0)

    def test_advisories_are_read_from_via_and_deduplicated(self) -> None:
        advisories = npm_audit.advisories_in(load("quartz-trimmed.json"))
        identifiers: list[str] = []
        for advisory in advisories:
            identifiers.append(advisory["id"])
        self.assertEqual(sorted(identifiers), sorted([GLOB_CLI, WS_DISCLOSURE, WS_MEMORY_DOS]))


class CommandLineTests(unittest.TestCase):
    """The exit codes verify.sh reads, through the real command line."""

    def run_compare(self, contract: dict, pairs: dict[str, str]) -> subprocess.CompletedProcess:
        folder = Path(tempfile.mkdtemp(prefix="npm-audit-test-"))
        self.addCleanup(shutil.rmtree, folder, True)
        contract_file = folder / "toolchain.json"
        contract_file.write_text(json.dumps({"npmAudit": contract}), encoding="utf-8")
        arguments: list[str] = [sys.executable, str(SCRIPTS / "npm_audit.py"), "compare",
                                "--contract", str(contract_file)]
        for tree, name in pairs.items():
            arguments.append(f"{tree}={FIXTURES / name}")
        return subprocess.run(arguments, capture_output=True, text=True)

    def test_exit_codes(self) -> None:
        audited = {"quartz": "quartz-trimmed.json", "wrangler": "wrangler-trimmed.json",
                   "pagedjs": "tikz-engine-clean.json"}
        clean = self.run_compare(small_contract(), audited)
        self.assertEqual(clean.returncode, 0, clean.stdout + clean.stderr)
        self.assertIn("blocking=0", clean.stdout)

        contract = small_contract()
        remove_advisory(contract, "wrangler", SHARP_IDS[0])
        blocked = self.run_compare(contract, audited)
        self.assertEqual(blocked.returncode, 1)
        self.assertIn(f"BLOCKING wrangler sharp {SHARP_IDS[0]} high", blocked.stdout)

        offline = self.run_compare(small_contract(), {"quartz": "offline.json", "wrangler": "offline.json",
                                                      "pagedjs": "lockfile-step-offline.json"})
        self.assertEqual(offline.returncode, 2, offline.stdout)


class RealContractTests(unittest.TestCase):
    """contracts/toolchain.json -> npmAudit, the authored list itself."""

    def setUp(self) -> None:
        self.toolchain = json.loads(npm_audit.CONTRACT.read_text(encoding="utf-8"))
        self.npm_audit = self.toolchain["npmAudit"]

    def test_the_list_is_well_formed(self) -> None:
        self.assertEqual(npm_audit.contract_problems(self.npm_audit, self.toolchain["pins"]), [])

    def test_it_names_the_five_trees_and_where_windows_keeps_each(self) -> None:
        names: list[str] = []
        for entry in self.npm_audit["trees"]:
            names.append(entry["tree"])
            self.assertTrue(entry.get("windowsRuntime", "").startswith("runtime\\"), entry["tree"])
        self.assertEqual(names, ["quartz", "tikz-engine", "wrangler", "pagedjs", "function-plot"])

    def test_it_fails_on_high_and_critical(self) -> None:
        self.assertEqual(self.npm_audit["failsOn"], ["high", "critical"])

    def test_it_is_not_a_pin(self) -> None:
        """Both apps' pin tests read every pin as a Dockerfile line."""
        for pin in self.toolchain["pins"]:
            self.assertNotEqual(pin["pin"], "npmAudit")

    def test_the_real_list_accepts_the_real_fixtures(self) -> None:
        audits = {"quartz": load("quartz-trimmed.json"), "wrangler": load("wrangler-trimmed.json"),
                  "tikz-engine": load("tikz-engine-clean.json"), "pagedjs": load("tikz-engine-clean.json"),
                  "function-plot": load("tikz-engine-clean.json")}
        report = npm_audit.compare(audits, self.npm_audit)
        self.assertEqual(report["blocking"], [])
        self.assertEqual(report["failed_trees"], [])
        self.assertEqual(npm_audit.exit_code(report), 0)

    def test_copying_the_contract_does_not_change_it(self) -> None:
        before = copy.deepcopy(self.npm_audit)
        npm_audit.compare(every_tree_audited(), self.npm_audit)
        self.assertEqual(before, self.npm_audit)


if __name__ == "__main__":
    unittest.main()
