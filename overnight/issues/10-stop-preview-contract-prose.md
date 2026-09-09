# The stopPreview contract prose still describes a gap that has been closed

Rank: 10 of 18. Minutes of work; the cheapest real fix on the list.
Kind: implement
Gate: unit

## Where it came from
`MAC-HANDOFF.md`, "Open — what the mac still owes" (search for `stopPreview`).

## The problem
`contracts/shared-rules.json` → `stopPreview` → `modes` → `servingOnly` still
ends with a sentence to the effect of "…still live on that platform. That is a
gap, not a decision." The gap was closed — see `GUI-IMPROVEMENTS.md` and the
commits around "One rule for stopping a section's preview, not three"
(2026-09-05). The contract is now describing a state of the world that no
longer exists.

## The handoff's mechanism is wrong — correct it
The entry implies the mac must regenerate this. It must not:
`shared-rules.json` is **hand-authored, not generated** (see
`contracts/README.md`), and no Swift emits that block. Windows could have fixed
this themselves at any point. Say so in your write-up so the next Windows
session knows the authored halves are theirs to edit too — that
misunderstanding is exactly the kind of stale advice rule 3 warns about.

## What done looks like
- The prose describes what the code does today. Read the current stop-preview
  implementation before writing the replacement; do not paraphrase the commit
  message.
- Check the REST of the `stopPreview` block for the same staleness while you
  are in there — one wrong sentence rarely travels alone.
- Both suites read this file, so confirm the mac tests still pass and note in
  the handoff that Windows should re-run theirs.
- Mark the `MAC-HANDOFF.md` entry done in place.

## Caution
Do not restate the rule in a second place. `contracts/` is the one home for
this; if `documentation/` describes it too, point rather than duplicate.
