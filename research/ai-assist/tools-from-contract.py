#!/usr/bin/env python3
"""
Write the tool surface a routing measurement should run against.

Reads `contracts/assist-cases.json` — which is generated from the app itself —
and emits the OpenAI-shaped `tools` array the suites already accept as their
third argument.

**Why this exists.** The earliest suite in this folder hand-wrote its tool
definitions in Python. That is the one copy of the surface it is most expensive
to have: a routing score measured against tools the app does not ship is worse
than no score, because it reads as evidence. The later suites fixed half of it
by loading a JSON file captured from a running server; this fixes the other
half by taking the same definitions from the contract, with no server needed.

The descriptions matter as much as the names. "TEACHERS SAY:" phrasings in them
are measured artifacts — one added sentence in `publish_pages` took the
promise-card score from 110/110 to 90/110 — so a measurement is only about the
shipping surface if the descriptions are the shipping ones too.

**On WINDOWS this file is the wrong starting point, and that is not obvious.**
The contract is generated from the MAC, so what it holds is the mac's
descriptions. The two servers' wording is close but not identical — five of the
25 shared tools differed on 2026-09-08 and one still does — so a Windows
measurement taken from here scores the mac's surface on Windows hardware and
reads as evidence about neither. On Windows, dump the live surface instead:

    research/ai-assist/dump-tools.ps1 -Exe …\plantoir-mcp.exe -Folder … -Course … -Out tools.json
    python research/ai-assist/narrow-tools.py tools.json narrowed.json <COURSE>

    python3 research/ai-assist/tools-from-contract.py [local|mcp] > /tmp/real-tools.json
    python3 research/ai-assist/shipped-surface-suite.py 8099 10 /tmp/real-tools.json

`local` (the default) is what the on-device model is shown — 13 tools, and the
list the routing figures were measured against. `mcp` is the 25 Claude Code
sees.
"""
import json
import pathlib
import sys

WHICH = sys.argv[1] if len(sys.argv) > 1 else "local"
ROOT = pathlib.Path(__file__).resolve().parents[2]
CONTRACT = ROOT / "contracts" / "assist-cases.json"

with open(CONTRACT, encoding="utf-8") as handle:
    cases = json.load(handle)

schemas = cases.get("toolSchemas", {})
if WHICH not in ("local", "mcp"):
    sys.exit("Usage: tools-from-contract.py [local|mcp]")
if WHICH not in schemas:
    sys.exit(
        "contracts/assist-cases.json has no toolSchemas.%s — regenerate the contract:\n"
        "    Plantoir --write-contracts contracts" % WHICH
    )

tools = schemas[WHICH]
print(json.dumps(tools, indent=2, ensure_ascii=False))
sys.stderr.write("%d tools (%s surface) from %s\n" % (len(tools), WHICH, CONTRACT))
