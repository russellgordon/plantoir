# #899 W7b2-4: the How I Teach page through ONE step (Windows #949)

Branch `issue/899-w7b2-4-how-i-teach`, from `issue/899-w7b-daily-actions` 6f48d833c. `origin/dev` merged in before proving: already contained (no merge commit; `git merge origin/dev` said "Already up to date" at 6f48d833c). Merged again before hand-back: see "Runs".

## For PROGRESS

- #899 W7b2-4: Write How I Teach (`write_how_i_teach`, key `writeHowITeach`) and Start the How I Teach Page (Course Settings' row, key `startHowITeachPage`, `madeBy` `sheet`) each write the page as ONE `UndoActionStep` through the door, held by the course (`holds: course`, no section), as the mac's `JournaledStep(course:section: nil, holds: "course")`. Both fixture rows run the real actions and are out of the ledger; the writer-scan entries for `AssistWorkspace.HowITeach.cs` and `HowITeachSettingsRow.cs` are gone.

## For documentation 12

- **A course-level step.** `AssistWorkspace.NewCourseUndoStep(actionKey, courseCode)` is `NewUndoStep` without a section: the step's header carries `course` and `holds: "course"` and no `section`. The backup's stand-in section (the lowest) is still what the backup and the part-way sentence name; the step does not carry it.
- **Start the How I Teach Page.** The exclusive create (`FileMode.CreateNew`) is replaced by a check at plan time plus the door's refusal: the page is planned new; if the step's before (read as it is planned) is not absent, the page that is there is opened and nothing is made; if one appears after that, the swap refuses it as `changedSince` and the page that appeared is opened. The row derives the working folder from the course folder (`<wf>\courses\<code>`); a course not inside one is written plainly in shadow, staged and swapped all or none, as every step does.
- **Write How I Teach.** The step plans the page FIRST (its before read then), and only then checks the page against the plan (`movedOn`, after the backup), so the before the step holds is the page the plan read, or the swap refuses it. A `changedSince` refusal from the door says today's sentence (`howITeachChangedSincePlanned`); any other refusal is `RefusalForAStepThatStopped` ("Nothing was changed: …", or the part-way sentence naming the kept file, "the How I Teach page"). The same words again plan no change: no step, no write, no today's-undo entry, the same "saved" answer and the same trail line as before.
- **What a teacher meets differently.** A page that cannot be written now answers "Nothing was changed: …" (the tool) or "The How I Teach page could not be made: nothing could be written beside “How I Teach.md” (…)" (the row), where before the tool threw the system's message and the row put the system's message after "could not be made:". A page that appears in the instant between the tool's last check and its write is no longer written over.

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

## Runs

- 899-w7b2-4-a on the PC (plantoir-pc), ref 6f97df959, lock taken 20:09:09, RUN_DONE 20:13:31; HEAD-AFTER the same, status clean. BUILD-APP-EXIT 0, BUILD-TESTS-EXIT 0. Classes (UndoHowITeachStepTests, HowITeachTests, HowITeachSettingsRowTests, UndoActionStepsOnWindowsTests, UndoActionTraceContractTests, NamedGapLedgerTests, UndoWriterScanTests): Passed 224, Failed 0, Total 224. No harness run (none asked).
- `origin/dev` merged before proving: already contained at 6f48d833c (no merge commit). Not merged again before hand-back.

## Left for the next piece

Nothing of this piece.

## For the director

- **The Course Settings row has no part-way words, and needs none (recommendation first).** The brief asks the row to say a part-way stop in its own words, or park it. A step of ONE new page cannot be left part way on Windows: `UndoSwap.SwapAFile` refuses a file only before it goes in (`wentIn` false), and a new page has no earlier content kept beside it, so `Reverse` has nothing to put back and the refusal is never `LeftPartWay`. Options: (1, recommended) nothing: the row's only failure words stay `couldNotCreate`, true for every way the step can fail; (2) add part-way words for the row to `shared-rules.json` → `howITeachPage.settingsButton` for a case that cannot occur. Parked as (1); no code depends on it.

## Self-check

1. Broke each fix and watched its test fail: the 7 must-fail rows above, all RED, then restored 224/224. The new tests were not run against the old product first (no separate run; the must-fail run stands in for it).
2. No timed waits: none added in product or test.
3. Sentences on the failure paths: appeared meanwhile, today's `howITeachChangedSincePlanned` (tool) or the page opened (row); cannot be written, "Nothing was changed: …" (tool) or `couldNotCreate` with the door's reason (row), nothing on disk (tested); part way, `RefusalForAStepThatStopped` naming the kept file (tested), and the row cannot stop part way (see "For the director").
4. `dev` merged before proving: already contained at 6f48d833c.
5. No number tuned by trial.
6. House style and contracts: fixture and traces run from the JSON; `contracts/` and `mac-app/` untouched.
7. Both fixture rows green, ledger rows gone, the `Reason899W7b2` sentence rewritten to name what is still held.
8. Writer scan: both entries removed; neither file writes now (UndoWriterScanTests green).
9. Riding lows: none in the brief.
10. One file per step, so the order is kept; each before is read at plan time (`step.Write` before the tool's `movedOn` check and before the row's plan-time check).
