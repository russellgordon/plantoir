# Need to know

Things Russell asked to have written down as well as said, from the
special-folders hardening work (branch `issue/special-folders-hardening`).
Newest first. This is a HANDOVER note, not a log — `GUI-IMPROVEMENTS.md` is the
log, and where a row and this file disagree, check the code.

## All three deploy destinations were tested for real (2026-08-23, overnight)

Driven through the app, on the example course, with `Media` deleted so the
checks had something to report:

| Destination | Result |
|---|---|
| A folder on this Mac | published; site written to `~/plantoir-published/section1` |
| Netlify | published; **https://exc2o-s1-2026-gordon-92321.netlify.app** — HTTP 200 |
| Cloudflare Pages | published in 17.7s; **https://exc2o-s1-2026-gordon.pages.dev** — HTTP 200 |

Both live sites are real and were created under your accounts, on your say-so.
Delete them whenever you like; nothing depends on them.

What the run confirmed, watched rather than asserted: the findings dialog
appears on the DEPLOY path as well as the preview one; the publish wording is
the right one ("Publishing is what puts this in front of students…"); the
**Preview Again** button is offered after a publish; the repair works from that
dialog; and the window title showed **" — Edited"** after the repair, which is
the marker doing its job on a section that had already published.

Netlify asked two questions the first time (surname, then a site address);
Cloudflare asked none, because the account ID was already saved. The account ID
was correctly redacted out of the activity trail.

## A section with no `index.md` cannot be published at all (2026-08-23)

Found while testing the deploy path, and it is worse than the health check's
wording suggests. `_sync_public_to_host` (`scripts/build_site.py:3138`) only
copies the built site back to the host when `public/index.html` exists — and
with no `index.md`, Quartz emits no root `index.html`. So:

1. the build SUCCEEDS and says so;
2. the sync back to `.merged_output` is silently skipped;
3. `deploy.sh` then reports **"Built site not found … Build first:
   ./preview.sh EXC2O 1 --build-only"** — after you have just built.

The guard itself is defensible (do not publish half a build), but the message
sends the teacher to do the thing they just did. What actually fixes it is
restoring `index.md`, which is what the repair button does — verified end to
end: repair → Preview Again → `public/index.html` appears on the host → deploy
succeeds.

The `sectionIndexMissing` check currently says the site "will open on whatever
page happens to come first". That is true of a PREVIEW and understates the
consequence for publishing. Worth strengthening.

## The repair dialog asked the wrong "is it busy" question (2026-08-23)

`CourseActivity.courseIsBusy` means "previewing OR publishing". The repair
dialog's Preview Again guard used it, so it refused whenever a preview was
running — which is every time the button is offered, since the findings come
from a build. There is now `coursePublishIsRunning` for callers that mean
publishing. **If you need to know whether a publish is in flight, do not reach
for `courseIsBusy`.**

## The " — Edited" marker after a repair (2026-08-23)

**A repair only shows as " — Edited" on a section that has ALREADY published.**
`SectionPublishState.hasUnpublishedEdits` compares the section's fingerprint
against a stamp written by a publish, and returns false outright when there is
no stamp. That is deliberate — "Edited" on a course that has never published
would always be on — but it has a consequence worth knowing:

- a `sectionIndexMissing` finding is raised by a PREVIEW as well as a publish;
- a preview writes no stamp;
- so on a never-published section, Plantoir puts the front page back and the
  marker says nothing at all.

What tells the teacher in that case is the repair dialog's own sentence. An
earlier version of this work claimed the marker was "the only prompt a teacher
gets that a publish is owed" — that was wrong, and the sentence in the dialog is
the counter-example.

**The marker is now refreshed when a repair happens.** It was not: the marker
only refreshes on appear, when the section stops being busy, and on window
activation — and the section had already stopped being busy before the findings
dialog appeared, while an alert on the same window does not make it key again.
So the repair changed the course and the title bar went on saying nothing.

**What counts as an edit**: `Media/` IS inside the fingerprint's walk, so a
picture in it is an edit — but an EMPTY `Media` folder is not, because the
fingerprint is built from regular files. Restoring an empty Media folder
therefore does not nudge anybody to publish, which is right: nothing a student
can see has changed.

## Previewing is never refused for "not edited" (2026-08-23)

Nothing in Plantoir refuses a preview because a section has not changed.
`buildFreshness` in `contracts/app-rules.json` governs whether a DEPLOY must
build first; it is not a gate on previewing. The only refusals are a port-lease
failure, a launch error, and — added by this work — pressing **Preview Again**
in the repair dialog while a publish is running.

## The repair dialog's buttons (2026-08-23)

**"Preview Again", not "Build Again".** The old label never said WHAT would be
built. This is a clarity point, not a rule 1 one: "build" is ordinary vocabulary
in this product ("Click Preview to build this section's website"), and does not
need hunting out of other strings.

**The preview is offered after a publish too.** It was withheld at first, on the
grounds that a preview does not change what students see. True, and beside the
point: the teacher has just put a folder back and wants to SEE that it worked.
The words carry what the preview cannot do.

**The dialog is one alert, switched by state.** `SectionDetailView` had four
`.alert` modifiers at one point and SwiftUI's alert bridge segfaulted; a view
presents one alert at a time, so the two this feature adds are modelled as one.

## Two traps that cost hours here, both about line endings (2026-08-23)

1. **Swift folds "\r\n" into ONE Character**, so `split(separator: "\n")` does
   not split output from a PTY at all. A marker line arrives glued to its
   neighbours: the text CONTAINS the prefix without STARTING with it, and every
   finding is silently dropped. `TranscriptBuilder` warns about this in a
   comment; splitting is now scalar-based in `SiteHealthFinding.linesOf`.
2. **`TranscriptBuilder` finishes a line in two places** — one for "\r\n", one
   for a bare "\n". A filter in only one of them passes every test (they all use
   "\n") and does nothing in real use.

Any test written with "\n" proves nothing about real output. Write them with
"\r\n".

## The test suite crashes about one run in four, and it is NOT this work
(2026-08-23)

Measured on a clean `origin/dev` worktree: one crash in four full runs, same
rate as the branch. `EXC_BAD_ACCESS` in `SwiftUI.AppKitDialogBridge.updateExistingAlert`
while an NSAlert sheet closes; the run aborts partway and `xcodebuild` exits 65
with ZERO failed test CASES. **Grep for `^Failing tests:` rather than trusting
the exit code**, and re-run before believing a failure. Written up with both of
the wrong diagnoses that preceded the right one in `TODO.md`.

## verify.sh exits early on a missing fixture (2026-08-23)

It needs `courses/EXC2O` present (copy `support/example_course/EXC2O` into
`courses/`). Without it, it fails that precondition and stops, having run only
the fast host-side checks — the whole Docker half never executes. With the
fixture: 42 passed, 0 failed.
