# #899 W7b2-8: the links checklist's Publish and Not Now are ONE step each (Windows #949)

Branch `issue/899-w7b2-8-links-checklist`, from `origin/issue/899-w7b2-7-sheet-records` 711b9a922 (which contains `dev` da7474047). Merge of `origin/dev` before proving: "Already up to date" (no merge commit; `origin/dev` da7474047 already contained). Before hand-back: see "Runs". No `contracts/` change, no `mac-app/` change.

## For PROGRESS

- W7b2-8 (#899, Windows #949): a press on the links checklist is ONE `UndoActionStep`, key `answerTheLinksChecklist`, made by `sheet`, as the mac's `LinksChecklistPublisher.publish` / `setAside`. Publish: every page it publishes and dates, then the answered record, then the record of the later classes it published, in that order, all or none, no recompute (the front page is not repointed, ruling F1; the mac's step names none). Not Now: the answered record alone. The fixture row `answerTheLinksChecklist` is converted and out of the ledger; its six traces run the real Windows write.
- `AssistWorkspace.PublishLinksChecklist` is gone: `PublishAndRemember` is the one press (lease check, backup, step, today's undo recording) and `PlanThePress(sheet, step)` (internal) plans it, reading every page through the step (`PlanningThrough`, `IsVisibleThrough`). `KeepTheClassesItPublished` always takes a step. `NotNow` returns whether the record was written.
- `LinksChecklist.PlanAnswered` (the planner), `RecordTheAnswer` (plan and make, false for any failure, true when part way), and `WriteAnswered` as the record on a step of its own (the mac's `write` with no step; the public five-argument form finds the working folder as the parent of `courses`).
- `LaterClassesKept.Keep` is gone (its last product caller was the press); the tests that laid a kept record with it use `KeepAtDeploy`.
- The sheet (`LinksChecklistDialog.OfferAsync`) now TELLS a refused press (`AssistRefusal.ForTheTeacher`): before, a refusal escaped the dialog and was only logged (section window) or thrown (sidebar).
- Riding lows of W7b2-7 review 1: L1 `KeepAtDeploy` and `RecordNotToday` catch everything (false, no throw); L2 the Not Today reason in `WindowsOwnJson` corrected; L3 `TheSameKeptAnswerAgainMakesNoStep` renamed `…AtTheSameMomentMakesNoStep`, with a new test that the same answer later stamps its moment on a step of its own (the mac's `KeptRecord.adding` stamps `Date()`, so that is the product rule kept, not changed).

## For documentation 12

**W7b2-8: the links checklist's press.** `LinksChecklistDialog.OfferAsync` → `AssistWorkspace.PublishAndRemember(sheet)`: refuses while a deploy holds the course, backs up once, opens today's-undo recording, makes ONE step `NewUndoStep("answerTheLinksChecklist", …, madeBy: "sheet")`, and `PlanThePress` plans into it: the class plan's pages (`SetDraft`), the pages a ticked class brings dated by it (`SetCreated`, read through the step so a page planned twice is read as planned), the going page rows with the offer's dates, then `LinksChecklist.PlanAnswered`, then `KeepTheClassesItPublished` (`LaterClassesKept.PlanInto`, reading the classes as the step leaves them). Both records are `todaysUndoKeepsIt: false`, as they were never in today's undo. No `KeepsTheFrontPageTrue`: the mac's `AssistPublishPlanner.planWrites` names no recompute and the checklist never repoints the front page. A refusal before anything is written is "Nothing was changed: …"; a step left part way is `wording.publishStoppedPartWay` with the mac's own words, "the pages you ticked" (`AssistWorkspace.PagesThePressTicked`, pinned against the mac's `LinksChecklistPublisher.swift` source because they are in no contract), with no Restore Section sentence after it, as the mac's sheet says none. Not Now: `NotNow` → `LinksChecklist.RecordTheAnswer(step, …)`, one step of the record; a record that cannot be written costs only the record (the checklist is offered again), as the mac's `try?`. Windows' answered-record bytes are its own (System.Text.Json, indented, members version, answeredAt, offered, leftUnticked in that order); every member holds the mac's value, named in `WindowsOwnJson`.

## Must-fail lines

`vm-tools/guest/899-w7b2-8-mustfail.json`, run by `899-w7b2-8-go.ps1` (calling `899-w7b2-8-pc-run.ps1`, a copy of `899-w7b2-7-pc-run.ps1`). Each row applied alone, its test run, restored with `git checkout`.

1. the answered record as a second step (`WriteAnswered` on its own step in place of `PlanAnswered`): `UndoLinksChecklistStepTests.PublishIsOneStepOfThePagesThenTheAnsweredRecordThenTheKeptRecord` — RESULT
2. a page saved outside the step (`Save` for the class plan's page): the same test — RESULT
3. the front page repointed (`KeepsTheFrontPageTrue` added to the plan): `ThePressNamesNoRecomputeAndLeavesTheFrontPage` — RESULT
4. a before read at make time (`UndoActionStep.Make` re-reads every before): `EveryBeforeIsReadWhenThePressIsPlanned` — RESULT
5. Not Now's record written outside the workspace's step: `NotNowIsOneStepOfTheAnsweredRecord` — RESULT
6. the part-way sentence with other words: `APressLeftPartWaySaysTheChecklistsPartWaySentence` — RESULT
7. riding LOW 1, `KeepAtDeploy` catching IO only: `UndoSheetRecordStepTests.AKeptRecordStoppedForAnyReasonCostsOnlyTheRecord` — RESULT
8. riding LOW 1, `RecordNotToday` catching IO only: `ANotTodayStoppedForAnyReasonCostsOnlyTheRecord` — RESULT

## Runs

RUNS

## Left for the next piece

- Nothing of this action. The `Reason899W7b2` row now holds only `duplicateClass` (and its sentence names Make Room for Classes and Duplicate Class; `makeRoomForClasses` sits in its own `Reason899W7b2MakeRoomLinkedPage` row).

## For the director

1. **A press refused because a page changed since it was checked.** The mac's `sentence(forRefused:)` says `linksChecklist.wording.pageChangedSince` with the page's sheet name for the door's `changedSince` refusal, and the unreadable-page sentence for a `cannotTellNow` on a file that cannot be read. Windows says "Nothing was changed: {reason}" for every refusal, which is true (nothing was written) but not the mac's words. Not in this brief ("Nothing was changed: …"); a small follow-up in `RefusalForAPressThatStopped` if wanted (the door's `UndoStepRefusedException.Refusal` carries the kind and path).
2. **The press's "what" words are in no contract.** "the pages you ticked" lives only in the mac's Swift; the test reads it from `LinksChecklistPublisher.swift`. Option (recommended): add it to the contract (`linksChecklist.wording.partWayWhat` or similar) at the next contract change, then read it from there.
3. Tests that write the answered or kept record through the public forms (`LinksChecklist.WriteAnswered(courseDirectory, …)`, `LaterClassesKept.KeepAtDeploy` with no list) make their step on this process's list (`UndoForThisProcess.Current`), in shadow, as the workspace tests without a list of their own already do.

## Self-check

SELFCHECK
