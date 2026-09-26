#!/usr/bin/env python3
"""
What the model is SHOWN, as one number per surface.

Hashes `contracts/assist-cases.json` -> `toolSchemas.local` and
`toolSchemas.mcp` — the tool lists exactly as `Plantoir --write-contracts`
writes them from the code (name, description, parameter schema, for every
tool a client is offered). A change that moves no byte here moved nothing the
local model or an MCP client reads, and so owes no routing re-measurement;
a change that moves the LOCAL digest does.

The bytes hashed, stated so anyone can reproduce them without this file:
SHA-256 of the UTF-8 encoding of Python's
`json.dumps(<the list>, sort_keys=True, ensure_ascii=False)` (default
separators, no indent). That is the recipe the truncated digests quoted in
documentation/10-local-ai-assistant.md were made with before this file was
committed (#209's plan review found it cited and missing); re-derived on
2026-09-26 against the committed contract, which it reproduces.

    python3 research/ai-assist/toolhash.py            # both digests, in full
    python3 research/ai-assist/toolhash.py --short    # first/last eight, as the docs quote them

`scripts/test_tool_surface_digest.py` pins the LOCAL digest, so a change to
the thirteen-tool surface fails a gate rather than a reader's memory. The MCP
digest is documentation: it is expected to move whenever an MCP-only tool is
added, and it is recorded where that happens.
"""
import hashlib
import json
import sys
from pathlib import Path

CASES = Path(__file__).resolve().parents[2] / "contracts" / "assist-cases.json"


def digest(tools) -> str:
    text = json.dumps(tools, sort_keys=True, ensure_ascii=False)
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def surfaces(cases_path: Path = CASES) -> dict:
    """{'local': (count, digest), 'mcp': (count, digest)}."""
    schemas = json.loads(cases_path.read_text(encoding="utf-8"))["toolSchemas"]
    found = {}
    for name in ("local", "mcp"):
        found[name] = (len(schemas[name]), digest(schemas[name]))
    return found


def main(arguments) -> int:
    short = "--short" in arguments
    for name, (count, full) in surfaces().items():
        shown = f"{full[:8]}…{full[-8:]}" if short else full
        print(f"{name} {count} tools {shown}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
