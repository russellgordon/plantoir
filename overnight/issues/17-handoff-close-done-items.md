# Five items in the handoff are marked owed but are already done

Rank: 17 of 18. Housekeeping, and the cheapest way to stop the next reader
wasting a session.
Kind: housekeeping
Gate: unit

## Why this matters
`MAC-HANDOFF.md`'s open sections are read top-down and abandoned partway — that
is the file's own stated assumption. An item that is done but still listed as
owed is indistinguishable from real work, and somebody will pick it up and
spend a session discovering it is finished. That has already happened here: a
v1.1.0 cut sheet sat at the top of the file for seventeen days telling sessions
to cut a release that had shipped.

## The five, each of which you must VERIFY before marking
Do not take this list on trust — it came from an audit, and the audit could be
wrong. Check each in the code and record the evidence:

1. **Preview progress-bar marker** — the entry says "NEEDS A MAC BUILD/TEST/REGEN".
   `TaskMilestones.swift` appears to carry `marker: "Done processing"` already,
   and `contracts/app-rules.json` → `milestones.preview` appears regenerated
   with it. Two sub-bullets may genuinely remain: a stale description in
   `MarketingScreenshotTests.swift` about the old 100% state, and a missing
   `GUI-IMPROVEMENTS.md` row. Handle those as real work if they are real.
2. **`WINDOWS-HANDOFF.md` item 20 bullet** — appears already struck through
   `✅ Done 2026-09-06` in that file.
3. **1.0.0 DMG from a tree with the syncfs fix** — check
   `git grep syncfs v1.0.0 -- scripts/build_site.py` and the same for v1.1.0.
4. **A system-prompt tweak marked "NEEDS A MAC BUILD + TEST"** — the edit
   appears to be in `AssistAgent.swift` since 2026-08-24, with the suite run
   many times since. The optional Metal re-measurement was never done and no
   research file records it; if you close the build/test half, say the
   measurement half is still open rather than closing both.
5. **Tests writing into the real activity trail** — the entry asks the mac to
   check. Mac tests appear to swap `ActivityTrail.store` and restore the
   PREVIOUS store rather than nil. Verify and close if the mac does not have
   the leak.

## What done looks like
- Each verified item marked `✅ DONE <date>` **in place**, with one line of
  evidence, and moved to "Done — the ledger" per that section's own rule.
- Anything that turns out NOT to be done stays open, with what you found.
- No item deleted. The ledger keeps its history.

## Caution
This session changes documentation only. Run the suite anyway — the driver will
— but do not touch code. If verifying turns up a real defect, write it up as a
NEW open item rather than fixing it here; it has not been reviewed.
