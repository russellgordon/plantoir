---
name: ui-review
description: Build the UI/UX review page for a release that changes what a teacher sees - annotated screenshots from the real app, every state and its exact wording, the design decisions and what was rejected - and take Russell through it before the cut. Use before cutting any release that changes the interface or its sentences.
---

# The UI/UX review page

**Standing practice since v1.10.0 (Russell, 2026-11-13):** a release that
changes what a teacher sees gets a review page before it is cut. In his words,
"It's way more efficient than a smoke test." The first one found two layout
faults that every unit test and three reviews had passed (#831, #832), and in
an hour he ruled on about twenty things and reversed four rulings made on his
behalf (#833 to #836).

It does not replace the tests. It replaces most of the smoke test: what is
left for his hands is what a picture cannot show (a real double-click, a real
share or deploy, VoiceOver by ear).

## When

After the release's pieces are merged to `dev` and a Debug build of `dev`
exists, and BEFORE the whole-release sweep and the cut. Leave time for what it
finds: the first one produced six issues.

## Two agents, then the page

Run both at once; they do not depend on each other. Each brief in this folder
is a template: fill in the release's features, issues and the scratch folder.

1. **Capture and annotate** (`capture-brief.md`). ONE agent, the only one
   allowed to touch the screen, and only when Russell has given the Mac.
   - Captured the way the marketing site's pictures are: the
     [`marketing-screenshots`](../marketing-screenshots/SKILL.md) skill and
     `website/shots/capture.py`: the real app, launched isolated with
     `--state-dir`, the example course, never a scaled window. New scenes go
     on a LOCAL branch `scratch/ui-review-captures`, never pushed or merged.
     Nothing is written under `website/` or `site/`.
   - Both appearances when it is cheap; Dark comes first.
   - Annotated in the tutorial house style: a red rounded rectangle
     (`#d0312d`, about 6 px at Retina 2x) around each new control, a solid red
     label with bold white words naming it, no arrows and no numbered circles
     (number inside the words where order matters), not cropped tightly. The
     raw capture is kept beside every annotated copy.
   - Nothing personal in any picture: the example course, a scratch folder
     under `/Users/Shared` so the user name stays out of the path bar, no real
     share or deploy, no credential.
   - **The agent reports what looked wrong while it drove the app.** Those
     observations are the most valuable output. Each is a finding: file it,
     fix it before the cut.
   - It ends by putting `dev` back with a plain Debug build (a test run turns
     the bundle the Dock points at into a test host), the appearance back, the
     app quit, iTerm in front.
2. **Gather the words and decisions** (`content-brief.md`). A reader. For each
   feature: where it lives; how it works, in steps; EVERY state a teacher can
   meet, with the exact sentence copied from the contract and its key (never
   paraphrased); the design decisions with why and what was rejected;
   keyboard and VoiceOver; what nobody has checked in the real window; and the
   judgement calls, including every ruling the director made while he was
   away. Anything unmerged is described as a proposal.

Then build and publish:

```text wrap
python3 .claude/skills/ui-review/build_page.py   # run from a scratch copy of this folder holding content.json, shots/manifest.json and observations.json
```

`build_page.py` reads `content.json` (the second agent's file),
`shots/manifest.json` (the first agent's) and `observations.json` (`title`,
`headline`, `build`, `faults`, `awkward`, `notCaptured`), and writes
`index.html` and `files.json`, the list of pictures to publish beside it.
Publish it as a PRIVATE artifact with those pictures as supporting files.
LOOK AT EVERY PICTURE before publishing (a contact sheet of the annotated
set is enough). A first version with the words alone is worth publishing as
soon as the second agent returns.

## Taking him through it

- **Every judgement call goes through the question dialog, one or two at a
  time.** Never a list of decisions in the chat. Each question stands on its
  own: say what the thing is and what happens under each option.
- **Rulings made on his behalf come back the same way**, one or two at a
  time, to be confirmed or changed.
- **Record each ruling on the issue that owns it the same hour** (a new issue
  with the release's milestone when none does), send it to the agent building
  that area, and correct the page.
- When he reads a state as the normal case and it is a rare failure, the page
  is wrong, not him: label failure states as failure states.
- When a sentence makes him ask "why does it do that?", the sentence is the
  finding, even when the behaviour is right.

## What the first one taught

- A layout fault is invisible to a test that never lays the view out with a
  real page loaded. Capture every tab WITH content in it, at two window sizes.
- A dialog that packs facts into one paragraph reads as a wall of text: one
  short message, then the facts as labelled rows (#834).
- States reachable only after a real share or deploy cannot be pictured from
  an isolated copy. List them on the page as not pictured, with the reason,
  and put them on the hand test.
