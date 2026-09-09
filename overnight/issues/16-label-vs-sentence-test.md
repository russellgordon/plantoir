# The mac has no test that its advice names the toggle a teacher can actually see

Rank: 16 of 18.
Kind: implement
Gate: unit

## Where it came from
`MAC-HANDOFF.md`, "Open — what the mac still owes", inside the
exclusions/protection entry. Windows has such a test; the mac does not.

## The problem
Advice that tells a teacher to change a setting must name the setting **as the
interface labels it**. The handoff records a real instance: a message saying
"turn off *Publish the curriculum coverage map*" is worse than useless when the
app's toggle says "Include Curriculum Coverage map". The teacher looks for text
that is not on screen.

It is worse than a single mismatch, because the labels are not stable across
places: Course Settings uses one label, the wizard uses another
(`CoverageSwitchLabelInWizard`), and the wizard's curriculum-pages toggle is
built per-province — so a BC teacher may see a third. Read the handoff entry
for the exact names before writing anything.

## What done looks like
- A mac test that pins every piece of advice naming a control against the
  actual label of that control, in every place the label differs.
- The test fails usefully: when it breaks, the message should say which
  sentence names which control and what the control actually says.
- Any mismatch it finds is FIXED, not asserted as correct — confirmed by
  Russell on 2026-09-06. Correct the ADVICE to match the control's real label,
  never the control's label to match the advice: the label is what the teacher
  is looking at when they go hunting. Each fix is teacher-visible and gets a
  `GUI-IMPROVEMENTS.md` row.

## Caution
Do not hard-code the label strings into the test — read them from wherever the
interface reads them, or the test passes forever after somebody changes the
toggle. That is the whole failure mode this is meant to catch.
