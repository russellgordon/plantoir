#!/usr/bin/env python3
"""Build the three tool surfaces #114's measurement compared (2026-09-26).

Each arm is the mac's shipped 13-tool LOCAL surface
(contracts/assist-cases.json -> toolSchemas.local) with ONLY the tool
descriptions changed, so any difference in routing is the text's:

  A  the contract's text as the mac ships it - the convergence target,
     pinned since #114 in assist-cases.json -> toolDescriptions.
  B  what Windows' router reads today: Briefly() of the Windows server's own
     [Description] text, read out of windows-app/Plantoir.Mcp/PlantoirTools.cs.
  C  Briefly() of the contract's text - what Windows would read if it kept
     trimming after converging.

Briefly() is taken from narrow-tools.py beside this file, which mirrors the
Windows AssistAgent and is pinned there by NarrowToolsMirrorTests.

**Reading C# with a regex is a research input here, NOT a gate.** Doc 10
rejected exactly this as a test, because a reformatted attribute makes it find
fewer names. So this script asserts it found every one of the 32 tools both
servers serve, and exits non-zero otherwise, rather than building an arm from
a partial read.

Usage:
    python3 research/ai-assist/description-arms.py OUT_DIR

writes OUT_DIR/arm-A-contract.json, arm-B-windows-text.json,
arm-C-briefly-contract.json. Point trimmed-surface-suite.py or
teachers-say-suite.py at them.
"""
import ast
import json
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent

def _briefly_from_narrow_tools():
    """narrow-tools.py runs as a script on import, so only its briefly() is
    lifted out of it - the mirror stays one copy rather than two."""
    tree = ast.parse((HERE / "narrow-tools.py").read_text(encoding="utf-8"))
    for node in tree.body:
        if isinstance(node, ast.FunctionDef) and node.name == "briefly":
            namespace = {}
            exec(compile(ast.Module(body=[node], type_ignores=[]), "narrow-tools.py", "exec"), namespace)
            return namespace["briefly"]
    sys.exit("narrow-tools.py has no briefly() any more")


briefly = _briefly_from_narrow_tools()


def windows_descriptions():
    """Tool name -> the Windows server's full description, from the C#."""
    source = (ROOT / "windows-app/Plantoir.Mcp/PlantoirTools.cs").read_text(encoding="utf-8")
    found = {}
    pattern = re.compile(
        r'\[McpServerTool\(Name = "([a-z_]+)"[^\]]*\)\]\s*\[Description\(((?:"(?:[^"\\]|\\.)*"\s*\+?\s*)+)\)\]'
    )
    for match in pattern.finditer(source):
        pieces = re.findall(r'"((?:[^"\\]|\\.)*)"', match.group(2))
        text = "".join(pieces).encode("utf-8").decode("unicode_escape").encode("latin-1").decode("utf-8")
        found[match.group(1)] = text
    return found


def main():
    out = pathlib.Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    cases = json.load(open(ROOT / "contracts/assist-cases.json", encoding="utf-8"))
    local = cases["toolSchemas"]["local"]
    shared = {tool["function"]["name"] for tool in cases["toolSchemas"]["mcp"]}
    windows = windows_descriptions()
    missing = sorted(shared - set(windows))
    if missing:
        sys.exit("read %d Windows descriptions; missing shared tools %s - the C# changed shape, fix the "
                 "regex rather than measure a partial surface" % (len(windows), missing))

    def arm(describe):
        tools = json.loads(json.dumps(local))
        for tool in tools:
            tool["function"]["description"] = describe(tool["function"]["name"], tool["function"]["description"])
        return tools

    arms = {
        "arm-A-contract": arm(lambda name, text: text),
        "arm-B-windows-text": arm(lambda name, text: briefly(windows[name])),
        "arm-C-briefly-contract": arm(lambda name, text: briefly(text)),
    }
    for name, tools in arms.items():
        (out / (name + ".json")).write_text(json.dumps(tools, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
        changed = [a["function"]["name"] for a, b in zip(tools, local) if a != b]
        print("%s: %d tools, descriptions differing from A: %s" % (name, len(tools), changed or "none"))


if __name__ == "__main__":
    main()
