# #899 W7b2-4: the How I Teach page through ONE step (Windows #949)

Branch `issue/899-w7b2-4-how-i-teach`, from `issue/899-w7b-daily-actions` 6f48d833c. `origin/dev` merged in before proving: already contained (no merge commit; `git merge origin/dev` said "Already up to date" at 6f48d833c). Merged again before hand-back: see "Runs".

## For PROGRESS

- #899 W7b2-4: Write How I Teach (`write_how_i_teach`, key `writeHowITeach`) and Start the How I Teach Page (Course Settings' row, key `startHowITeachPage`, `madeBy` `sheet`) each write the page as ONE `UndoActionStep` through the door, held by the course (`holds: course`, no section), as the mac's `JournaledStep(course:section: nil, holds: "course")`. Both fixture rows run the real actions and are out of the ledger; the writer-scan entries for `AssistWorkspace.HowITeach.cs` and `HowITeachSettingsRow.cs` are gone.

## For documentation 12

- **A course-level step.** `AssistWorkspace.NewCourseUndoStep(actionKey, courseCode)` is `NewUndoStep` without a section: the step's header carries `course` and `holds: "course"` and no `section`. The backup's stand-in section (the lowest) is still what the backup and the part-way sentence name; the step does not carry it.
- **Start the How I Teach Page.** The exclusive create (`FileMode.CreateNew`) is replaced by a check at plan time plus the door's refusal: the page is planned new; if the step's before (read as it is planned) is not absent, the page that is there is opened and nothing is made; if one appears after that, the swap refuses it as `changedSince` and the page that appeared is opened. The row derives the working folder from the course folder (`<wf>\courses\<code>`); a course not inside one is written plainly in shadow, staged and swapped all or none, as every step does.
- **Write How I Teach.** The step plans the page FIRST (its before read then), and only then checks the page against the plan (`movedOn`, after the backup), so the before the step holds is the page the plan read, or the swap refuses it. A `changedSince` refusal from the door says today's sentence (`howITeachChangedSincePlanned`), and so does any refusal of a NEW page when a page is now there (review 1, LOW 2: one that appears after the door's last check is refused by the rename itself, `replace: false`, which the door reads as "in use"; the tool tells the case apart by the plan having seen no page, as the row does, so no change outside this piece was needed). A step left part way says the bare `publishStoppedPartWay` sentence naming the kept file, with no way back, in every surface: the mac's `saidWhenTheStepStopped(..., aSectionsCopyPutsItBack: false)`, since the page sits at the top of the course and Restore Section puts back one section only (review 1, MEDIUM; before, Plantoir's own window added "Restore Section 1… puts the section back"). Any other failure is "Nothing was saved: …" (`AssistWorkspace.NothingWasSaved`), the mac's `nothing: "Nothing was saved"` for this tool and the opening of every How I Teach refusal (review 1, LOW 1). The same words again plan no change: no step, no write, no today's-undo entry, the same "saved" answer and the same trail line as before.
- **What a teacher meets differently.** A page that cannot be written now answers "Nothing was saved: …" (the tool) or "The How I Teach page could not be made: nothing could be written beside “How I Teach.md” (…)" (the row), where before the tool threw the system's message and the row put the system's message after "could not be made:". A page that appears in the instant between the tool's last check and its write is no longer written over.

- **Correction for `documentation/12-windows-app.md`, "The How I Teach row, and the CHECK items of #360" (about line 6405).** It still says "The row writes with `FileMode.CreateNew`". Replace that sentence with: "The row writes the page as ONE undo step (`startHowITeachPage`, made by `sheet`, held by the course) and opens THE PAGE (`FolderActions.OpenInObsidian` gained a `page` argument), never the vault. The exclusive create is a check at plan time plus the door's refusal: a page there when the step reads its before is opened and nothing is made; one that appears after that is refused by the swap (`changedSince`, or the rename's own `replace: false` in the last instant) and opened." The test sentence after it stands.
- **Write How I Teach, review 2.** The appeared-meanwhile sentence for a refusal other than `changedSince` is said only when the plan saw NO page (`planned.ExistingPath is null`) and one is there now; a started page with no words (what Start the How I Teach Page leaves) was seen by the plan, so its refusals say "Nothing was saved: {reason}".

## Must-fail lines

Rows in `vm-tools/guest/899-w7b2-4-mustfail.json`, run by `899-w7b2-4-go.ps1` (a wrapper of `899-w7b-pc-run.ps1`). Run 899-w7b2-4-a, as printed (each row alone, its named test run, then reverted with git):

- SABOTAGE 1 RED written outside the step: Write How I Teach writes the page itself (`UndoHowITeachStepTests.WriteHowITeachIsOneStepHeldByTheCourse`, Failed 1 of 1)
- SABOTAGE 2 RED written outside the step: the fixture row of writeHowITeach (`UndoActionStepsOnWindowsTests.TheWindowsActionLeavesTheRecordedStep`, Failed 1 of 25)
- SABOTAGE 3 RED the appeared-meanwhile refusal removed: the tool's changedSince answer (`APageThatAppearedBeforeTheSwapIsNeverWrittenOverByTheTool`, Failed 1 of 1)
- SABOTAGE 4 RED the appeared-meanwhile refusal removed: the row's plan-time check (`HowITeachSettingsRowTests.ACreatedPageNeverWritesOverOneMadeAMomentEarlier`, Failed 1 of 1)
- SABOTAGE 5 RED the appeared-meanwhile refusal removed: the row's door refusal (`APageThatAppearedBeforeTheSwapIsOpenedByTheRow`, Failed 1 of 1)
- SABOTAGE 6 RED the wrong madeBy for the sheet (`TheWindowsActionLeavesTheRecordedStep`, Failed 1 of 25)
- SABOTAGE 7 RED a change-nothing write: the same words written again outside the step (`TheSameWordsAgainMakeNoStepAndNoWrite`, Failed 1 of 1)
- RESTORED: Passed 224 of 224.

7 RED of 7.

Review 1's fixes (rows 3, 5 and 7 rewritten to revert the protection, not the answer; rows 8 to 10 new). Run 899-w7b2-4-b, as printed:

- SABOTAGE 1 build=0 test=1 RED written outside the step: Write How I Teach writes the page itself :: Failed!  - Failed:     1, Passed:     0, Skipped:     0, Total:     1, Duration: 99 ms - Plantoir.Tests.dll (net9.0)
- SABOTAGE 2 build=0 test=1 RED written outside the step: the fixture row of writeHowITeach :: Failed!  - Failed:     1, Passed:    24, Skipped:     0, Total:    25, Duration: 4 s - Plantoir.Tests.dll (net9.0)
- SABOTAGE 3 build=0 test=0 NOT-RED the appeared-meanwhile refusal removed: the door's changedSince check, under the tool (the page is written over) :: Passed!  - Failed:     0, Passed:     1, Skipped:     0, Total:     1, Duration: 299 ms - Plantoir.Tests.dll (net9.0)
- SABOTAGE 4 build=0 test=1 RED the appeared-meanwhile refusal removed: the row's plan-time check :: Failed!  - Failed:     1, Passed:     0, Skipped:     0, Total:     1, Duration: 72 ms - Plantoir.Tests.dll (net9.0)
- SABOTAGE 5 build=0 test=0 NOT-RED the appeared-meanwhile refusal removed: the door's changedSince check, under the row (the page is written over) :: Passed!  - Failed:     0, Passed:     1, Skipped:     0, Total:     1, Duration: 259 ms - Plantoir.Tests.dll (net9.0)
- SABOTAGE 6 build=0 test=1 RED the wrong madeBy for the sheet :: Failed!  - Failed:     1, Passed:    24, Skipped:     0, Total:    25, Duration: 4 s - Plantoir.Tests.dll (net9.0)
- SABOTAGE 7 build=0 test=1 RED a change-nothing write making a step: the same words written again through the step :: Failed!  - Failed:     1, Passed:     0, Skipped:     0, Total:     1, Duration: 374 ms - Plantoir.Tests.dll (net9.0)
- SABOTAGE 8 build=0 test=1 RED part way in Plantoir's own window: the section's way back said again (review 1, MEDIUM) :: Failed!  - Failed:     1, Passed:     0, Skipped:     0, Total:     1, Duration: 1 s - Plantoir.Tests.dll (net9.0)
- SABOTAGE 9 build=0 test=1 RED Nothing was changed for Nothing was saved (review 1, LOW 1) :: Failed!  - Failed:     1, Passed:     0, Skipped:     0, Total:     1, Duration: 252 ms - Plantoir.Tests.dll (net9.0)
- SABOTAGE 10 build=0 test=1 RED a page that appears just before the rename said as in use (review 1, LOW 2) :: Failed!  - Failed:     1, Passed:     0, Skipped:     0, Total:     1, Duration: 285 ms - Plantoir.Tests.dll (net9.0)
- RESTORED test=0 Passed!  - Failed:     0, Passed:   226, Skipped:     0, Total:   226, Duration: 34 s - Plantoir.Tests.dll (net9.0)

Rows 3 and 5 were NOT-RED because the door guards an appeared page twice: `Holds` before the rename, and L4's read of the kept original after it (`SameBytes(kept, target.Expected)`), which reverses the swap. Removing one leaves the other. Both rows now take both away in one edit (the door takes a page where it planned none as unchanged, `Holds` and `SameBytes`), and were re-run alone as 899-w7b2-4-c:

- SABOTAGE 1 build=0 test=1 RED the appeared-meanwhile refusal removed: the door takes a page where it planned none as unchanged, both before and after the rename, under the tool (the page is written over) :: Failed!  - Failed:     1, Passed:     0, Skipped:     0, Total:     1, Duration: 382 ms - Plantoir.Tests.dll (net9.0)
- SABOTAGE 2 build=0 test=1 RED the appeared-meanwhile refusal removed: the door takes a page where it planned none as unchanged, both before and after the rename, under the row (the page is written over) :: Failed!  - Failed:     1, Passed:     0, Skipped:     0, Total:     1, Duration: 277 ms - Plantoir.Tests.dll (net9.0)
- RESTORED test=0 Passed!  - Failed:     0, Passed:   226, Skipped:     0, Total:   226, Duration: 33 s - Plantoir.Tests.dll (net9.0)

The failing lines: the tool's row, `Assert.Throws() Failure: No exception was thrown` (UndoHowITeachStepTests.cs line 118: the write went ahead over the page that appeared); the row's, `Expected: Opened, Actual: Created` (line 131: it made its page over the teacher's). These are rows 3 and 5 of `899-w7b2-4-mustfail.json` as it now stands; the re-run used `899-w7b2-4-mustfail-35.json` (those two rows alone) through `899-w7b2-4-go-35.ps1`.

10 RED of 10 (rows 3 and 5 from run c, the rest from run b).

## Runs

- 899-w7b2-4-a on the PC (plantoir-pc), ref 6f97df959, lock taken 20:09:09, RUN_DONE 20:13:31; HEAD-AFTER the same, status clean. BUILD-APP-EXIT 0, BUILD-TESTS-EXIT 0. Classes (UndoHowITeachStepTests, HowITeachTests, HowITeachSettingsRowTests, UndoActionStepsOnWindowsTests, UndoActionTraceContractTests, NamedGapLedgerTests, UndoWriterScanTests): Passed 224, Failed 0, Total 224. No harness run (none asked).
- `origin/dev` merged before proving: already contained at 6f48d833c (no merge commit). Not merged again before the first hand-back.
- Review 1's round: `origin/dev` 8f73b39a4 merged in first (merge commit 0bd11c0d8). 899-w7b2-4-b on the PC (plantoir-pc), ref 9ef462962, lock taken 20:22:44, RUN_DONE 20:27:19; HEAD-AFTER 9ef462962 SAME, status clean. BUILD-APP-EXIT 0, BUILD-TESTS-EXIT 0. The same seven classes (`UndoHowITeachStepTests` now holds the two new tests): Passed 226, Failed 0, Total 226. Must-fail 10 rows, lines above.
- 899-w7b2-4-c on the PC, ref 9ef462962, mode mustfail only (rows 3 and 5), lock taken 20:30:48 (waited its turn), RUN_DONE 20:32:09; HEAD-AFTER SAME, status clean; RESTORED 226 of 226. Lock free afterwards.

- Review 2's round: 899-w7b2-4-d on the PC, ref 90c428496, lock taken 20:57:48 (waited behind the whole-suite run), RUN_DONE 20:59:51; HEAD-AFTER 90c428496 SAME, status clean; lock free afterwards. Classes `UndoHowITeachStepTests`, `HowITeachTests` and `HowITeachSettingsRowTests` only, as the coordinator asked. As printed:
  - BUILD-APP-EXIT 0
  - BUILD-TESTS-EXIT 0
  - Passed!  - Failed:     0, Passed:    32, Skipped:     0, Total:    32, Duration: 7 s - Plantoir.Tests.dll (net9.0)
  - SABOTAGE 1 build=0 test=1 RED a started page's refusal said as changed since planned (review 2, MEDIUM) :: Failed!  - Failed:     1, Passed:     0, Skipped:     0, Total:     1, Duration: 356 ms - Plantoir.Tests.dll (net9.0)
  - RESTORED test=0 Passed!  - Failed:     0, Passed:    32, Skipped:     0, Total:    32, Duration: 6 s - Plantoir.Tests.dll (net9.0)
  That sabotage is row 11 of `899-w7b2-4-mustfail.json`, run alone from `899-w7b2-4-mustfail-11.json` through `899-w7b2-4-go-11.ps1`. Must-fail across the piece: 11 RED of 11.

## Left for the next piece

Nothing of this piece.

## For the director

- **The Course Settings row has no part-way words, and needs none (recommendation first).** The brief asks the row to say a part-way stop in its own words, or park it. A step of ONE new page cannot be left part way on Windows: `UndoSwap.SwapAFile` refuses a file only before it goes in (`wentIn` false), and a new page has no earlier content kept beside it, so `Reverse` has nothing to put back and the refusal is never `LeftPartWay`. Options: (1, recommended) nothing: the row's only failure words stay `couldNotCreate`, true for every way the step can fail; (2) add part-way words for the row to `shared-rules.json` → `howITeachPage.settingsButton` for a case that cannot occur. Parked as (1); no code depends on it.

## Self-check

Review 1's round (the first round's answers were replaced, not kept beside these):

1. Broke each fix and watched its test fail: 10 must-fail rows, each reverting a protection or a sentence (rows 3 and 5 re-run after they were made to take away both of the door's guards; rows 8 to 10 for the MEDIUM, LOW 1 and LOW 2), then restored 226/226. The two new tests were not run against the old product on their own; rows 8 and 10 put the old product's code back and show each one failing.
2. No timed waits: none added in product or test.
3. Every sentence on the failure paths of the two actions: appeared meanwhile, `howITeachChangedSincePlanned` (the tool, now in the last instant before the rename too) or the page opened (the row); cannot be written, "Nothing was saved: …" (the tool, the mac's word) or `couldNotCreate` (the row); left part way, the bare `publishStoppedPartWay` naming the kept file in every surface, with no Restore Section (the mac's `aSectionsCopyPutsItBack: false`), tested in Plantoir's own window with a course copy made. The row cannot stop part way (unchanged, "For the director").
4. `dev` merged before proving: 8f73b39a4, merge commit 0bd11c0d8; nothing newer on `origin/dev` at hand-back (checked again before the push).
5. No number tuned by trial.
6. House style kept; `contracts/` and `mac-app/` untouched; Windows says the contract's and the mac's words, none retyped (`AssistWording.PublishStoppedPartWay`, `HowITeachChangedSincePlanned`; "Nothing was saved" is in no contract on either side, as "Nothing was changed" is not).
7. Both fixture rows green (`UndoActionStepsOnWindowsTests` in the 226), ledger rows gone, the reason sentence unchanged and still true.
8. Writer scan: unchanged by this round; both entries stay gone (`UndoWriterScanTests` green).
9. Riding lows: the review's L1 to L3 fixed, each with a test or a must-fail row; L2 closed inside the piece (the tool tells the case apart by the plan having seen no page); L4 (merge before hand-back) done.
10. One file per step, so the order is kept; each before is read at plan time (unchanged).
