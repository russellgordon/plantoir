#!/usr/bin/env python3
"""fetch-obsidian-addons.sh reads every pin out of the real contract (#864).

mac-app/Vendor/fetch-obsidian-addons.sh reads the add-ons' ids, versions,
file names, sizes, SHA-256s and addresses from
contracts/shared-rules.json -> obsidianAddOnsForFigures.addOns, and carries
none of its own. Until 2026-11-13 it read them with /usr/bin/plutil, which
refuses a whole JSON file holding an escaped NUL anywhere in it. #780's cases
put eight of them into the same contract on 2026-11-12, and from then on the
script read nothing, said the contract had no add-ons, and stopped every
fresh clone (xcodegen generate needs the folder) and every release build
(publish.sh runs it before generating). No suite ran the script, so no suite
saw it; a new machine did.

This runs the script's reading step alone (`--print-pins`, which fetches,
checks and installs nothing) against the real contract and compares every
line with Python's own reading of the same file. The next character a reader
refuses, or a pin the reader gets wrong, fails here.

It needs bash and /usr/bin/jq, so it runs on a Mac (macOS 15 or later ships
jq) and skips anywhere else, Windows' PythonToolchainTests included.
Listed in verify.sh.

    python3 scripts/test_fetch_obsidian_addons.py
"""

import json
import os
import shutil
import subprocess
import sys
import unittest
from pathlib import Path

REPOSITORY = Path(__file__).resolve().parent.parent
SCRIPT = REPOSITORY / "mac-app" / "Vendor" / "fetch-obsidian-addons.sh"
CONTRACT = REPOSITORY / "contracts" / "shared-rules.json"
JQ = Path("/usr/bin/jq")


def pins_as_python_reads_them() -> list:
    """Every pinned file, one tuple each, read with Python's json module."""
    with open(CONTRACT, encoding="utf-8") as handle:
        contract = json.load(handle)
    lines: list = []
    for addon in contract["obsidianAddOnsForFigures"]["addOns"]:
        for pinned_file in addon["files"]:
            lines.append((
                addon["id"],
                addon["version"],
                pinned_file["name"],
                str(pinned_file["bytes"]),
                pinned_file["sha256"],
                pinned_file["from"],
            ))
    return lines


def pins_as_the_script_reads_them() -> subprocess.CompletedProcess:
    return subprocess.run(
        ["bash", str(SCRIPT), "--print-pins"],
        capture_output=True, text=True, timeout=120,
    )


@unittest.skipUnless(sys.platform == "darwin" and shutil.which("bash") and JQ.exists(),
                     "the fetch script is the Mac's, and reads with /usr/bin/jq")
class TheFetchScriptReadsTheRealContract(unittest.TestCase):

    def test_the_reading_step_succeeds_on_the_real_contract(self):
        result = pins_as_the_script_reads_them()
        self.assertEqual(result.returncode, 0,
                         "the script could not read contracts/shared-rules.json: " + result.stderr)

    def test_every_pin_it_reads_is_the_contracts(self):
        result = pins_as_the_script_reads_them()
        self.assertEqual(result.returncode, 0, result.stderr)
        read_by_the_script: list = []
        for line in result.stdout.splitlines():
            read_by_the_script.append(tuple(line.split("\t")))
        self.assertEqual(read_by_the_script, pins_as_python_reads_them())

    def test_the_contract_still_carries_what_plutil_refused(self):
        # The escaped NULs are #780's cases and stay; this is what makes the
        # first test mean something. If they ever go, this says so rather
        # than leaving the reading step tested against an easier file.
        text: str = CONTRACT.read_text(encoding="utf-8")
        self.assertIn("\\u0000", text)

    def test_the_reading_step_fetches_and_installs_nothing(self):
        destination: Path = SCRIPT.parent / "obsidian-addons"
        before: list = []
        if destination.exists():
            for entry in sorted(destination.rglob("*")):
                before.append((str(entry), entry.stat().st_mtime_ns))
        result = pins_as_the_script_reads_them()
        self.assertEqual(result.returncode, 0, result.stderr)
        after: list = []
        if destination.exists():
            for entry in sorted(destination.rglob("*")):
                after.append((str(entry), entry.stat().st_mtime_ns))
        self.assertEqual(before, after)
        leftovers: list = []
        for entry in os.listdir(SCRIPT.parent):
            if entry.startswith(".obsidian-addons."):
                leftovers.append(entry)
        self.assertEqual(leftovers, [], "the reading step left a staging folder behind")


if __name__ == "__main__":
    unittest.main()
