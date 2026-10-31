#!/usr/bin/env python3
"""
How long one machine line may be (#666, `contracts/shared-rules.json` ->
`machineLineLength`).

A machine line is a `PLANTOIR_<NAME>:` prefix and a single-line JSON payload
that an app reads back out of the console. The mac's kernel pseudo terminal
never splits a line, but Windows' pseudo console has a width (8,192 columns
in the app since #662): a longer line that wraps on the bottom row while
Quartz's spinner redraws comes back as two lines, its reader gets a JSON head
cut off mid-text, and records nothing. So every line whose payload carries an
UNBOUNDED list - `PLANTOIR_DATED:`, `PLANTOIR_KEPT_OFF:`, `PLANTOIR_MAPS:`,
and `PLANTOIR_HEALTH:` (whose detail names up to ten blocks or pages) - is
printed through here and kept to `maxCharacters`, prefix included.

A list line that would be longer keeps the FIRST k entries (the most that
fit) and carries `"count"`, the true number, and `"more"`, how many it left
out, so its trail line still says how many there were. JSON is never cut
mid-text: a reader parses a shortened line exactly as it parses a whole one.
A health finding is shortened differently, by naming fewer blocks in its
detail (`site_health.announce`), because its sentence already carries the
count. The bounded markers (MY_PROGRESS, REPAIRED, LINKS_CHECKLIST, SWIFT,
CLOUDFLARE_REMADE) are left as they are; `scripts/test_machine_line_length.py`
holds each of them under the cap at its worst plausible size.

"Characters" here are Python's (code points). The cap is half of what the
console and the app's line carry allow, because a character can be two
UTF-16 units in C# or two cells in a console (CJK, emoji): the Windows suite
pins 2 * maxCharacters under both.
"""

import json

import contracts


def max_characters() -> int:
    """The cap, from the contract (strict, like every contract read)."""
    return int(contracts.section("shared-rules", "machineLineLength", "maxCharacters"))


def text(prefix: str, payload: dict) -> str:
    """One machine line, exactly as every emitter writes one."""
    return f"{prefix} {json.dumps(payload, ensure_ascii=False)}"


def listed(prefix: str, base: dict, key: str, items: list, limit: int = None) -> str:
    """
    `base` with `key` naming `items`, in at most `limit` characters
    (the contract's cap when not given). Whole when it fits; otherwise the
    first k items with `count` (all of them) and `more` (the ones left out),
    k as large as fits - 0 when not even one does.
    """
    limit = max_characters() if limit is None else limit

    def whole() -> dict:
        payload = dict(base)
        payload[key] = list(items)
        return payload

    def first(k: int) -> dict:
        payload = dict(base)
        payload[key] = list(items[:k])
        payload["count"] = len(items)
        payload["more"] = len(items) - k
        return payload

    line = text(prefix, whole())
    if len(line) <= limit or not items:
        return line
    # Longer with every entry, so the largest k that fits is found by halving.
    low, high, best = 0, len(items) - 1, 0
    while low <= high:
        middle = (low + high) // 2
        if len(text(prefix, first(middle))) <= limit:
            best = middle
            low = middle + 1
        else:
            high = middle - 1
    return text(prefix, first(best))


def fitted(prefix: str, payload_for, most: int, limit: int = None) -> str:
    """
    The line for the largest k <= `most` whose `payload_for(k)` fits, or k=0
    when none does - for a payload that shortens itself (a health finding's
    detail naming fewer blocks).
    """
    limit = max_characters() if limit is None else limit
    line = text(prefix, payload_for(most))
    k = most
    while len(line) > limit and k > 0:
        k -= 1
        line = text(prefix, payload_for(k))
    return line
