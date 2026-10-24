#!/usr/bin/env python3
"""Compare `npm audit --json` for the image's JavaScript against the accepted
list in contracts/toolchain.json -> npmAudit (#667).

    python3 scripts/npm_audit.py compare  quartz=a.json tikz-engine=b.json ...
    python3 scripts/npm_audit.py findings quartz=a.json ... [--lock quartz=package-lock.json ...]

`compare` is the gate verify.sh runs (and Windows runs over its runtime's copies
of the same trees). It prints one line per BLOCKING advisory, then the counts:

    exit 0  every high or critical advisory is accepted for its tree, at the
            severity the database gives it today
    exit 1  a high or critical advisory that is not accepted, or that is accepted
            at a LOWER severity than it has now ("re-decide"); a tree the
            contract names that has no audit, no lockfile (ENOLOCK) or output
            that is not JSON; or a tree the contract does not name
    exit 2  the advisory database could not be reached, and nothing failed:
            the caller SKIPS, saying no tree counts as audited until every tree can be. Never a pass.

Low and moderate advisories that are not accepted are REPORTED, not failed. An
accepted advisory the audit no longer reports is STALE: said, never failed,
because an upgrade is what makes an entry stale.

`findings` prints the Markdown table for research/npm-audit/<date>.md, so the
revisit at a release cut (RELEASING.md) is mechanical.

Stdlib only, no network and no Docker, so Windows' PythonToolchainTests runs
its tests too. The input is npm's STDOUT only: offline, npm prints its JSON on
stdout and an `npm error` line on stderr, and exits 1 either way, so neither
stderr nor the exit code says anything the JSON does not.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REPOSITORY = Path(__file__).resolve().parent.parent
CONTRACT = REPOSITORY / "contracts" / "toolchain.json"

SEVERITY_ORDER = ["info", "low", "moderate", "high", "critical"]

# What npm prints when the audit request itself never got an answer:
# {"message": "request to https://registry.npmjs.org/-/npm/v1/security/audits/quick
# failed, reason: getaddrinfo EAI_AGAIN registry.npmjs.org", ...} (measured with
# `docker run --network none`, 2026-10-24).
AUDIT_REQUEST_FAILED = re.compile(r"^request to \S+/-/npm/v1/security/\S+ failed")

# What the lockfile step prints for a tree whose lockfile is built from its pin
# (pagedjs, function-plot) when the registry cannot be reached: "npm error code
# EAI_AGAIN" with --network none.
NETWORK_ERROR = re.compile(r"\b(EAI_AGAIN|ENOTFOUND|ECONNREFUSED|ECONNRESET|ETIMEDOUT|ENETUNREACH|EHOSTUNREACH)\b")

SYNTHESISED_FROM_PIN = "synthesised from the pin"


def severity_rank(severity: str) -> int:
    """Where a severity sits in npm's order; an unknown one ranks highest, so it blocks."""
    if severity in SEVERITY_ORDER:
        return SEVERITY_ORDER.index(severity)
    return len(SEVERITY_ORDER)


def advisory_id(url: str) -> str:
    """GHSA-xxxx-xxxx-xxxx from https://github.com/advisories/GHSA-xxxx-xxxx-xxxx."""
    return url.rstrip("/").rsplit("/", 1)[-1]


def advisories_in(audit: dict) -> list[dict]:
    """Every advisory the audit names, once per id. A `via` that is a string means
    "affected through another package", which is reported under that package."""
    found: list[dict] = []
    seen_ids: set[str] = set()
    vulnerabilities = audit.get("vulnerabilities", {})
    for package_name in sorted(vulnerabilities):
        entry = vulnerabilities[package_name]
        for via in entry.get("via", []):
            if not isinstance(via, dict):
                continue
            identifier = advisory_id(str(via.get("url", "")))
            if identifier in seen_ids:
                continue
            seen_ids.add(identifier)
            found.append({
                "package": str(via.get("name", package_name)),
                "id": identifier,
                "severity": str(via.get("severity", "")),
                "range": str(via.get("range", "")),
                "title": str(via.get("title", "")),
                "url": str(via.get("url", "")),
                "nodes": list(entry.get("nodes", [])),
            })
    return found


def tree_entry(npm_audit: dict, tree: str) -> dict | None:
    for entry in npm_audit.get("trees", []):
        if entry.get("tree") == tree:
            return entry
    return None


def audit_state(audit: dict | None, entry: dict) -> tuple[str, str]:
    """(state, why) for one tree's audit output, already parsed (None = not JSON).

    audited      metadata.vulnerabilities is there
    unreachable  the audit request failed, or a pin's lockfile could not be
                 built for a network reason (pagedjs, function-plot only)
    failed       anything else: not JSON, no lockfile (ENOLOCK - the IMAGE
                 changed), or a shape this does not know. Never a skip, so a
                 half-audit cannot read as "offline"."""
    if audit is None:
        return "failed", "the audit's output was not JSON"
    if not isinstance(audit, dict):
        return "failed", "the audit's output was not a JSON object"
    metadata = audit.get("metadata")
    if isinstance(metadata, dict) and isinstance(metadata.get("vulnerabilities"), dict):
        return "audited", ""
    marker = audit.get("plantoir", "")
    error = audit.get("error") if isinstance(audit.get("error"), dict) else {}
    message = str(audit.get("message", ""))
    if marker == "no-lockfile" or error.get("code") == "ENOLOCK":
        return "failed", "it has no lockfile (ENOLOCK) - the image changed"
    if marker == "lockfile-step-failed":
        if entry.get("lockfile") == SYNTHESISED_FROM_PIN and NETWORK_ERROR.search(message):
            return "unreachable", message
        return "failed", "its lockfile could not be built: " + (message or "no message")
    if AUDIT_REQUEST_FAILED.search(message):
        return "unreachable", message
    return "failed", "the audit said something this does not know: " + (message[:200] or "no message")


def accepted_by_tree(npm_audit: dict) -> dict[str, dict[str, dict]]:
    """{tree: {advisory id: {severity, package, reason}}}."""
    result: dict[str, dict[str, dict]] = {}
    for entry in npm_audit.get("accepted", []):
        tree = entry["tree"]
        if tree not in result:
            result[tree] = {}
        for advisory in entry.get("advisories", []):
            result[tree][advisory["id"]] = {
                "severity": advisory["severity"],
                "package": entry["package"],
                "reason": entry["reason"],
                "exposure": entry["exposure"],
            }
    return result


def compare(audits: dict[str, dict | None], npm_audit: dict) -> dict:
    """The gate's decision over every tree's parsed audit (None = not JSON)."""
    fails_on = npm_audit.get("failsOn", ["high", "critical"])
    lowest_failing = min(severity_rank(severity) for severity in fails_on)
    accepted = accepted_by_tree(npm_audit)
    report: dict = {"blocking": [], "reported": [], "accepted_seen": [], "stale": [],
                    "failed_trees": [], "unreachable_trees": [], "audited_trees": [],
                    "advisories_seen": 0}
    contract_trees: list[str] = []
    for entry in npm_audit.get("trees", []):
        contract_trees.append(entry["tree"])
    for tree in sorted(audits):
        if tree not in contract_trees:
            report["failed_trees"].append((tree, "contracts/toolchain.json -> npmAudit names no such tree"))
    for tree in contract_trees:
        if tree not in audits:
            report["failed_trees"].append((tree, "it was not audited"))
            continue
        entry = tree_entry(npm_audit, tree) or {}
        state, why = audit_state(audits[tree], entry)
        if state == "failed":
            report["failed_trees"].append((tree, why))
            continue
        if state == "unreachable":
            report["unreachable_trees"].append((tree, why))
            continue
        report["audited_trees"].append(tree)
        accepted_here = accepted.get(tree, {})
        reported_ids: set[str] = set()
        for advisory in advisories_in(audits[tree]):
            report["advisories_seen"] += 1
            reported_ids.add(advisory["id"])
            row = dict(advisory)
            row["tree"] = tree
            now = severity_rank(advisory["severity"])
            decision = accepted_here.get(advisory["id"])
            if decision is None:
                if now >= lowest_failing:
                    row["why"] = "not accepted"
                    report["blocking"].append(row)
                else:
                    report["reported"].append(row)
                continue
            if now >= lowest_failing and severity_rank(decision["severity"]) < now:
                row["why"] = f"accepted at {decision['severity']}, now {advisory['severity']}: re-decide"
                report["blocking"].append(row)
                continue
            report["accepted_seen"].append(row)
        for identifier in sorted(accepted_here):
            if identifier not in reported_ids:
                report["stale"].append({"tree": tree, "id": identifier,
                                        "package": accepted_here[identifier]["package"]})
    return report


def exit_code(report: dict) -> int:
    if report["blocking"] or report["failed_trees"]:
        return 1
    if report["unreachable_trees"]:
        return 2
    return 0


def contract_problems(npm_audit: dict, pins: list[dict]) -> list[str]:
    """What is wrong with the authored list itself (the tests read the real one)."""
    problems: list[str] = []
    pin_names: set[str] = set()
    for pin in pins:
        pin_names.add(pin["pin"])
    tree_names: list[str] = []
    for entry in npm_audit.get("trees", []):
        name = entry.get("tree", "")
        if name in tree_names:
            problems.append(f"tree {name} is listed twice")
        tree_names.append(name)
        if not str(entry.get("exposure", "")).strip():
            problems.append(f"tree {name} has no exposure")
        if "pin" in entry and entry["pin"] not in pin_names:
            problems.append(f"tree {name} names pin {entry['pin']}, which is not in pins")
        if entry.get("lockfile") == SYNTHESISED_FROM_PIN and "pin" not in entry:
            problems.append(f"tree {name} is synthesised from a pin but names none")
    for severity in npm_audit.get("failsOn", []):
        if severity not in SEVERITY_ORDER:
            problems.append(f"failsOn names an unknown severity {severity}")
    seen: set[tuple[str, str]] = set()
    for entry in npm_audit.get("accepted", []):
        label = f"{entry.get('tree')} {entry.get('package')}"
        if entry.get("tree") not in tree_names:
            problems.append(f"{label}: unknown tree")
        for field in ("package", "exposure", "reason"):
            if not str(entry.get(field, "")).strip():
                problems.append(f"{label}: no {field}")
        if not entry.get("advisories"):
            problems.append(f"{label}: no advisories")
        for advisory in entry.get("advisories", []):
            key = (str(entry.get("tree")), str(advisory.get("id")))
            if key in seen:
                problems.append(f"{label}: {advisory.get('id')} is accepted twice for that tree")
            seen.add(key)
            if not re.fullmatch(r"GHSA(-[23456789cfghjmpqrvwx]{4}){3}", str(advisory.get("id", ""))):
                problems.append(f"{label}: {advisory.get('id')} is not an advisory id")
            if advisory.get("severity") not in SEVERITY_ORDER:
                problems.append(f"{label}: {advisory.get('id')} has an unknown severity")
    return problems


def installed_versions(lockfile: dict, nodes: list[str]) -> str:
    versions: list[str] = []
    packages = lockfile.get("packages", {})
    for node in nodes:
        version = str(packages.get(node, {}).get("version", ""))
        if version and version not in versions:
            versions.append(version)
    return ", ".join(sorted(versions))


def findings_table(audits: dict[str, dict | None], npm_audit: dict, lockfiles: dict[str, dict]) -> str:
    accepted = accepted_by_tree(npm_audit)
    lines: list[str] = [
        "| Tree | Package | Installed | Advisory | Severity | Exposure | Decision |",
        "|---|---|---|---|---|---|---|",
    ]
    for entry in npm_audit.get("trees", []):
        tree = entry["tree"]
        audit = audits.get(tree)
        if audit is None or audit_state(audit, entry)[0] != "audited":
            continue
        for advisory in advisories_in(audit):
            installed = installed_versions(lockfiles.get(tree, {}), advisory["nodes"])
            decision = accepted.get(tree, {}).get(advisory["id"])
            if decision is None:
                exposure = "(not decided)"
                verdict = "**NOT ACCEPTED**: decide it"
            else:
                exposure = decision["exposure"]
                verdict = "accepted: " + decision["reason"]
            lines.append(f"| {tree} | {advisory['package']} | {installed} | "
                         f"[{advisory['id']}]({advisory['url']}) | {advisory['severity']} | "
                         f"{exposure} | {verdict} |")
    return "\n".join(lines) + "\n"


def read_audit(path: Path) -> dict | None:
    """The audit as JSON, or None when it is not JSON (which fails, never skips)."""
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return None
    try:
        return json.loads(text)
    except ValueError:
        return None


def parse_pairs(arguments: list[str]) -> dict[str, Path]:
    pairs: dict[str, Path] = {}
    for argument in arguments:
        tree, separator, path = argument.partition("=")
        if not separator or not tree or not path:
            raise SystemExit(f"expected <tree>=<file>, got {argument!r}")
        pairs[tree] = Path(path)
    return pairs


def describe(report: dict) -> list[str]:
    lines: list[str] = []
    for row in report["blocking"]:
        lines.append(f"BLOCKING {row['tree']} {row['package']} {row['id']} {row['severity']} "
                     f"({row['why']}): {row['title']}")
    for tree, why in report["failed_trees"]:
        lines.append(f"FAILED {tree}: {why}")
    for tree, why in report["unreachable_trees"]:
        lines.append(f"UNREACHABLE {tree}: {why}")
    for row in report["reported"]:
        lines.append(f"REPORTED {row['tree']} {row['package']} {row['id']} {row['severity']}: {row['title']}")
    for row in report["stale"]:
        lines.append(f"STALE {row['tree']} {row['package']} {row['id']}: accepted, no longer reported")
    lines.append(f"COUNTS audited={len(report['audited_trees'])} advisories={report['advisories_seen']} "
                 f"accepted={len(report['accepted_seen'])} blocking={len(report['blocking'])} "
                 f"reported={len(report['reported'])} stale={len(report['stale'])} "
                 f"failed={len(report['failed_trees'])} unreachable={len(report['unreachable_trees'])}")
    return lines


def main(arguments: list[str]) -> int:
    if not arguments or arguments[0] not in ("compare", "findings"):
        print(__doc__)
        return 64
    command = arguments[0]
    rest = arguments[1:]
    contract_path = CONTRACT
    lock_arguments: list[str] = []
    audit_arguments: list[str] = []
    index = 0
    while index < len(rest):
        if rest[index] == "--contract":
            contract_path = Path(rest[index + 1])
            index += 2
            continue
        if rest[index] == "--lock":
            lock_arguments.append(rest[index + 1])
            index += 2
            continue
        audit_arguments.append(rest[index])
        index += 1
    npm_audit = json.loads(contract_path.read_text(encoding="utf-8"))["npmAudit"]
    audits: dict[str, dict | None] = {}
    for tree, path in parse_pairs(audit_arguments).items():
        audits[tree] = read_audit(path)
    if command == "findings":
        lockfiles: dict[str, dict] = {}
        for tree, path in parse_pairs(lock_arguments).items():
            lockfiles[tree] = json.loads(path.read_text(encoding="utf-8"))
        sys.stdout.write(findings_table(audits, npm_audit, lockfiles))
        return 0
    report = compare(audits, npm_audit)
    for line in describe(report):
        print(line)
    return exit_code(report)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
