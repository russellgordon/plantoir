# #899 W7b2-8: the links checklist's Publish and Not Now are ONE step each (Windows #949)

Branch `issue/899-w7b2-8-links-checklist`, from `origin/issue/899-w7b2-7-sheet-records` 711b9a922 (which contains `dev` da7474047). Merge of `origin/dev` before proving: "Already up to date" (no merge commit; `origin/dev` da7474047 already contained). Before hand-back: see "Runs". No `contracts/` change, no `mac-app/` change. (Merged on 2026-11-26 in `night25/integration-5`, c50bc8112, with W7b2-7, -1 and -2. "For PROGRESS" and "For documentation 12" are folded into `windows-app/PROGRESS.md` and documentation 12. What follows says the ledger and the writer scan as this branch saw them: on the merged tree the `Reason899W7b2` row and reason, and `Reason899W7b2MakeRoomLinkedPage`, are gone, and only `Reason899NoDuplicateAsNextClass` is left of W7b2, for W7b2-3.)

## Must-fail lines

`vm-tools/guest/899-w7b2-8-mustfail.json`, run by `899-w7b2-8-go.ps1` (calling `899-w7b2-8-pc-run.ps1`, a copy of `899-w7b2-7-pc-run.ps1`). Each row applied alone, its test run, restored with `git checkout`.

1. the answered record as a second step (`WriteAnswered` on its own step in place of `PlanAnswered`): `UndoLinksChecklistStepTests.PublishIsOneStepOfThePagesThenTheAnsweredRecordThenTheKeptRecord` — RED
2. a page saved outside the step (`Save` for the class plan's page): the same test — RED
3. the front page repointed (`KeepsTheFrontPageTrue` added to the plan): `ThePressNamesNoRecomputeAndLeavesTheFrontPage` — RED
4. a before read at make time (`UndoActionStep.Make` re-reads every before): `EveryBeforeIsReadWhenThePressIsPlanned` — RED
5. Not Now's record written outside the workspace's step: `NotNowIsOneStepOfTheAnsweredRecord` — RED
6. the part-way sentence with other words: `APressLeftPartWaySaysTheChecklistsPartWaySentence` — RED
7. riding LOW 1, `KeepAtDeploy` catching IO only: `UndoSheetRecordStepTests.AKeptRecordStoppedForAnyReasonCostsOnlyTheRecord` — RED
8. riding LOW 1, `RecordNotToday` catching IO only: `ANotTodayStoppedForAnyReasonCostsOnlyTheRecord` — RED

8 RED of 8 (run r3); RESTORED 402 of 402. Riding LOWs 2 and 3 are a reason sentence and a test rename with a new test (`TheSameKeptAnswerLaterStampsItsMomentOnAStepOfItsOwn`); no product sabotage applies.

## Runs

All on the PC under `C:\vm-setup\wt-compare.lock` (the run script takes it and removes it last). Classes: the brief's twelve plus the test classes this piece edits or whose code it changes (UndoSheetRecordStepTests, FutureDatedClassesContractTests, AssistScenarioTests, DeclinedPagesAreNamedTests, PublishedPagesRecordTests, ClassesDatedLaterAtDeployTests).

- r1 (f348bf5ec): app build 0 errors; tests build failed (`ClassesDatedLaterAtDeployTests` called `KeepTheClassesItPublished` with no step). Its must-fail and RESTORED lines ran stale binaries and do not count.
- r2 (3d00b3b85): both builds 0 errors; 401 of 402, `PublishIsOneStep…` red because the test expected every op to be `writeFile` (the pages are `editLine`, as in W7a). Test corrected; r2's must-fail rows 1 and 2 do not count (their test was red already).
- r3 (4c715e7f4, the head): both builds 0 errors (app x64 Debug 37 warnings, none new); 402 of 402 on first run; must-fail 8 RED of 8; RESTORED 402 of 402; HEAD-AFTER the same, tree clean.
- No UI class, no harness, no whole suite.
- `origin/dev` merged before proving and again before r3: still da7474047, already contained (no merge commit).

## Left for the next piece

- Nothing of this action. The `Reason899W7b2` row now holds only `duplicateClass` (and its sentence names Make Room for Classes and Duplicate Class; `makeRoomForClasses` sits in its own `Reason899W7b2MakeRoomLinkedPage` row).

## For the director

1. **A press refused because a page changed since it was checked.** The mac's `sentence(forRefused:)` says `linksChecklist.wording.pageChangedSince` with the page's sheet name for the door's `changedSince` refusal, and the unreadable-page sentence for a `cannotTellNow` on a file that cannot be read. Windows says "Nothing was changed: {reason}" for every refusal, which is true (nothing was written) but not the mac's words. Not in this brief ("Nothing was changed: …"); a small follow-up in `RefusalForAPressThatStopped` if wanted (the door's `UndoStepRefusedException.Refusal` carries the kind and path).
2. **The press's "what" words are in no contract.** "the pages you ticked" lives only in the mac's Swift; the test reads it from `LinksChecklistPublisher.swift`. Option (recommended): add it to the contract (`linksChecklist.wording.partWayWhat` or similar) at the next contract change, then read it from there.
3. Tests that write the answered or kept record through the public forms (`LinksChecklist.WriteAnswered(courseDirectory, …)`, `LaterClassesKept.KeepAtDeploy` with no list) make their step on this process's list (`UndoForThisProcess.Current`), in shadow, as the workspace tests without a list of their own already do.

## Self-check

1. Broke each fix and watched its test fail: 8 must-fail rows RED in r3. The new tests call `PlanThePress`, `NotNow`'s bool and the new `WriteAnswered` form, so they could not compile against the old code; the old behaviour was put back by sabotage (rows 1, 2, 5 restore the old plain writes).
2. No timed waits added, in product or test.
3. Failure paths: a refused press writes nothing (records included) and says "Nothing was changed: …"; part way says `publishStoppedPartWay` with the mac's words and names the kept file; both now reach the teacher through the dialog (before, a refusal was only logged). Not Now that cannot be written returns false and says nothing, as the mac's `try?`; the trail's "left … hidden, Not Now" line is still true (the pages were left). No "couldn't be read", no plain "saved", no `CouldNotSave`.
4. `dev` merged before proving: da7474047, already contained; again before r3, unchanged.
5. No number tuned by trial.
6. House style and contracts: the fixture row runs from `undo-action-steps.json` by name; the bytes' difference is named in `WindowsOwnJson`, never retyped; the part-way words are read from the mac's source in the test. Nothing outside `windows-app/` (and `vm-tools/guest`) changed.
7. The fixture row `answerTheLinksChecklist` is green (UndoActionStepsOnWindowsTests and its traces in UndoActionTraceContractTests), out of the ledger; `Reason899W7b2` now names W7b2-8 as done and only Make Room for Classes and Duplicate Class as left; the `Reason899W7b2` row holds exactly `duplicateClass`.
8. Writer scan: `LinksChecklist.cs` 9 → 7 (WriteAnswered's folder and write gone), reason names W7c and W8; `LaterClassesKept.cs`'s entry is gone (`Keep` removed, nothing writes there); `AssistWorkspace.LinksChecklist.cs` holds no `Save` (pinned by a test).
9. Riding lows: L1 fixed with two tests and must-fail rows 7 and 8; L2 the sentence corrected; L3 the test renamed to what it proves plus a test of the later answer (the mac's rule kept, so no product change).
10. File order is the plan's: pages, answered record, kept record (pinned); every before is read at plan time by `UndoActionStep.Plan` (pinned by `EveryBeforeIsReadWhenThePressIsPlanned`, must-fail row 4).
