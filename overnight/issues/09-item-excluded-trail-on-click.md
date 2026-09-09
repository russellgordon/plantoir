# "Item excluded" is recorded the moment it is clicked, so Revert leaves a false trail line

Rank: 9 of 18. A rule-5 trail defect needing a decision.
Kind: implement
Gate: unit

## Where it came from
`MAC-HANDOFF.md`, "Open — what the mac still owes", inside the
exclusions/protection entry from Windows.

## The problem
`mac-app/QuartzTeachers/Views/CourseSettings/CourseSettingsView.swift` records
the "item excluded" trail event at the point of the CLICK (see roughly lines
87, 120, 134 and 167 — verify the current line numbers). If the teacher then
uses Revert, the exclusion never happened, but the trail still says it did.

CLAUDE.md rule 5 is explicit that the trail exists so a problem reported next
week can be looked into without asking the teacher to reproduce it, and that
"a line describing what the feature used to do is worse than no line, because
it will be believed." A line describing something the teacher UNDID is the same
failure.

## Russell decided this on 2026-09-06, before the batch ran
**Record the revert as its own event.** The click keeps its line and the revert
gets one of its own, so the trail is complete and self-correcting: you can see
that a teacher excluded something and then changed their mind, which is itself
worth knowing when a problem is reported.

He was offered two alternatives and rejected both — **record on commit instead
of on click**, because a teacher who excludes something and crashes before
saving would then leave no trace of the attempt at all; and **leave it and
document the quirk**, because a trail line saying something happened when it did
not is the exact failure rule 5 exists to prevent. Write both rejections down
with their reasons: this is a decision for both platforms, and Windows will
re-derive it in a month if the reasoning is not there.

Implement it. Do not re-open the choice.

## What done looks like
- The decision written down with its reasoning.
- If you implement: the event list in `ActivityTrail.Event` and
  `contracts/shared-rules.json` → `activityTrail.mustRecord` stay in step —
  a test pins them against each other.
- If a new event is added, it gets the sentence a teacher would recognise, and
  it never records what is written on a page.
