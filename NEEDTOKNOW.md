# Need to know

Things Russell asked to have written down as well as said, from the
special-folders hardening work (branch `issue/special-folders-hardening`,
merged into `dev` on 2026-08-25) and its 2026-09-01 follow-ups. Newest first.
This is a HANDOVER note, not a log — `GUI-IMPROVEMENTS.md` is the log, and
where a row and this file disagree, check the code.

**Its one known-open defect is now closed**: a section with no `index.md` used
to build "successfully" and then refuse to publish with a message that sent the
teacher round in a circle. Fixed 2026-09-01, along with a worse one beside it.
The section below says what changed and keeps the old behaviour on the record,
because the trap is easy to reintroduce.

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

## A section with no `index.md` cannot be published at all (2026-08-23) — ✅ FIXED 2026-09-01

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

The `sectionIndexMissing` check understated it: its detail was true of a
PREVIEW and said nothing about publishing. It now names both outcomes — the
wording itself is `shared-rules.json` → `siteHealth.checks`, not repeated here,
because a sentence copied into a document is the copy that keeps reading right
after the product's words change.

**Fixed 2026-09-01, and the fix found a worse defect beside it.** The build no
longer claims to be complete when it produced nothing: it says "Nothing to
publish … it has no front page, so no website was produced" and exits non-zero,
so a publish stops at the build with the reason in front of it. And the skipped
sync used to leave the PREVIOUS build's `public/` on the host, which `deploy`
uploads — so a publish after deleting a front page reported success and shipped
last week's pages. That mirror is now cleared. See `GUI-IMPROVEMENTS.md` row
384 and `WINDOWS-HANDOFF.md`.

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

---

# Trying it yourself, step by step

About fifteen minutes. Use a THROWAWAY working folder — several steps delete
folders on purpose, and one of them publishes a real website.

## Setting up (2 minutes)

1. In Finder, make a folder called `plantoir-trial` somewhere convenient.
2. Inside it make a folder called `courses`.
3. Copy `support/example_course/EXC2O` from this repository into `courses/`.
4. Copy the nine launchers from the repository root — `setup.sh`, `preview.sh`,
   `deploy.sh` and their `.bat`/`.ps1` twins — into `plantoir-trial/` itself.
   **This step is not optional**: without `preview.sh` at the top level Plantoir
   does not recognise the folder as a working folder, and the picker simply
   stays up with no error. (That is intended behaviour, and it cost me an hour.)
5. Open Plantoir → File → choose `plantoir-trial`. You should see EXC2O in the
   sidebar. Expand it and select **Section 1**.

## 1. The warning appears, and the machinery does not (3 minutes)

6. In Finder, delete `courses/EXC2O/Media` and `courses/EXC2O/section1/index.md`.
7. In Plantoir, press **Preview**.

**Expect:** part-way through the build a dialog titled **"2 things need your
attention"**, naming the Media folder and the missing front page in plain words,
with buttons **Put them back** and **OK**.

**Also check** — press **Show details** in the console and scroll: you should
see the two ⚠️ sentences and NOT see any line beginning `PLANTOIR_HEALTH:`.
That JSON line is how the app hears about the problem, and a teacher should
never see it. It was visible until last night.

## 2. The repair, and what it tells you (3 minutes)

8. Press **Put them back**.

**Expect:** a second dialog, **"Put the Media folder and the front page back."**,
saying your preview still shows how things were, with **Preview Again** and
**OK**.

**Check in Finder:** both `Media/` and `section1/index.md` are back. The index
should contain only a title line — deliberately, since it is your page to write.

9. Press **Preview Again**. It should stop the running preview and start a new
   one. (Until last night it did nothing at all, silently.)

10. Press **Put them back** a second time on a later run, or after restoring the
    folders yourself.

**Expect:** **"That is already put right."** — NOT a warning about the folder
being locked or read-only. That wording was wrong until last night.

## 3. Publishing, and the different wording (5 minutes)

11. Let the preview finish. Then press **Deploy**. If you want to avoid
    publishing anything real, set the course's destination to a folder on this
    Mac first (Course settings → Deploying).

**Expect:** the findings dialog again if anything is still missing — and after
pressing **Put them back**, the wording is DIFFERENT: **"Publishing is what puts
this in front of students, so it is not on their site until you publish
again."** with **Preview Again** still offered.

That difference is the point: a preview shows YOU the repair, and only
publishing reaches students.

12. Look at the window title after a repair on a section that has published
    before.

**Expect:** **" — Edited"**. On a section that has NEVER published there is no
marker, by design — nothing to be "edited since".

## 4. The one that surprised me (2 minutes)

13. Delete `section1/index.md` again, press Preview, dismiss the dialog with
    **OK** (do not repair), wait for the build, then press **Deploy**.

**Expect, since 2026-09-01:** the PREVIEW still runs — nothing about a preview
changed, and it will open on whatever page comes first. It is pressing
**Deploy** that is different: the publish's own build stops, saying it produced
no website because the section has no front page, and the folder-problem dialog
comes back with **Put them back**. What a teacher is told about the failure is
`app-rules.json` → `failureExplanations`, the case whose output names a missing
front page. It no longer says "Built site not found — build first" to somebody
who just built.

**What it used to do**, kept because the trap is easy to reintroduce: the build
said "Static build complete", the publish then said *"Built site not found …
Build first"*, and — worse — if that section had ever been published before,
the publish would have succeeded and sent out the OLDER pages.

Repairing the front page and previewing again fixes it.

## 5. Which folders count for marks (2 minutes)

14. Course settings → **Marks**. You should see a checklist of this course's
    folders with **Tasks** ticked, and a link, "What else does Plantoir use my
    folders for?", which opens a sheet naming THIS course's folders.
15. Tick **Tests** as well, save, and preview. On the Curriculum Coverage page,
    the "What counts" section should now say your course's own folders rather
    than always saying "Tasks".

## 6. Publishing, for real, to everything (opt-in)

`./verify-deploy.sh` publishes this course to a folder, to Netlify and to
Cloudflare, runs all three primary+secondary pairings, previews it in serve
mode, and checks the no-front-page refusal — then **fetches every published
site back and reads it**, because a launcher's own output only proves the
launcher is happy with itself. 42 checks.

It is deliberately NOT part of `verify.sh`: it needs three credentials, the
network, and it creates real sites on real accounts. Run it when the publishing
path changes. It restores the course's settings and its front page on any exit,
including Ctrl-C.

Two things it found on its first two runs, both of which are the reason it
exists: publishing straight after a preview shipped the live-reload client to
students, and a rebuild for publishing lost a race against the preview's own
sync watcher.

## If something looks wrong

The activity trail is `~/Library/Logs/Plantoir/Logs/activity.txt`
(`~/Library/Logs/Plantoir/activity.txt`). A folder problem writes
`found a problem with this course's folders (name)` and a repair writes
`put the Media folder back` / `put the front page back`.
