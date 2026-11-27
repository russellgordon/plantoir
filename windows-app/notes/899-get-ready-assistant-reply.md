# #899 (Mac): Get Ready stopped part way, through the assistant

Branch `issue/899-get-ready-assistant-reply`, on `day27/integration-8` (6dc36fcea).

## What landed (Mac)

- `AssistToolRunner.prepareForStartOfYear` catches `JournaledStepError.leftPartWay` apart from every other failure and hands it to one function, `startOfYearStoppedPartWay`. The built-in assistant and MCP both reach it (one tool runner). The reply: `startOfYear.wording.stoppedPartWay` (the sheet's key), a space, the new `startOfYear.wording.restoreOfferThroughTheAssistant`, then the plan as shown (ruling 10), then the preview's line. Trail: `startOfYearStoppedPartWayLine(source: "mcp"/"local", ...)`, not `(writeFailed)`. Nothing is recorded for Undo. A stop that changed nothing stays `writeFailed`.
- “Restore from Backup…” is `CourseMenu.restoreFromBackupMenuItem`; the Course menu and the sentence both read it.
- Contract: the new key, `howToRunAnAssistantStoppedPartWayCase` and `assistantStoppedPartWayCases` (two cases), run by `StartOfYearRestoreOfferTests.testAssistantStoppedPartWayCasesAsTheContractSays` on both surfaces; the key is pinned in `StartOfYearTests`' wording table.

## For Windows

Owed, held in `NamedGapLedger.cs` under `Reason899GetReadyRestoreOffer`, area `StartOfYearSheetWording`: the key `restoreOfferThroughTheAssistant`. Also owed (no ledger area reads it): the two `assistantStoppedPartWayCases`. Build: in the MCP `prepare_for_start_of_year`, a part-way stop gives the reply above and rebuilds the preview; nothing else.

## For the director

1. **"Restore it" cannot work: parked.** The assistant has NO restore tool on either surface (`AssistToolSurface` lists none; the restores are the sidebar's Restore from Backup… and the conversation window's Restore Section button, neither a tool). The ruling's premise ("the assistant's EXISTING restore runs") does not hold. Exact gap: a tool taking a course and a backup file name and running `WholeCourseRestore` (with the previews stopped and started by `StartOfYearPreparation.restoreCourse`'s way, and the busy sentence during a deploy). That is a new tool, which #897 freezes, so it was not built.
2. **So the sentence is not Russell's word for word. His choice, with a concrete example.** The teacher asks the assistant "get section 2 of SNC1W ready for September"; it stops part way. The reply as built:
   > Plantoir stopped part way through putting the pages into draft, so Section 2 of SNC1W now has some pages in draft and some as they were. The backup “SNC1W_backup_2026-11-27_042559_assistant-section2.zip” holds SNC1W as it was before. Choose Restore from Backup… to put it back.

   (then the plan as shown, then the preview's line). His words were "…holds SNC1W as it was before. Ask me to restore it, or choose Restore from Backup…." If the teacher then said "restore it", the assistant would have no tool to do it and would refuse: the sentence would promise what the next turn refuses. Two options:
   - **(a) The sentence as built** (shipped now): true today, and the teacher restores from the Course menu.
   - **(b) A restore tool** for the assistant (a course and a backup file name; runs `WholeCourseRestore` with the previews stopped and started as `StartOfYearPreparation.restoreCourse` does, and the busy sentence during a deploy), and then his words. #897 freezes the tool surface, so this needs him to lift that for one tool. With (b) the key and `StartOfYearWording.restoreOfferThroughTheAssistant` change in one line each.
3. **The preview.** A part-way stop brings it up to date (`bringThePreviewUpToDate`, as after any assistant action): no offer waits for an answer, and Restore from Backup… stops and starts previews itself. **Fixed in round two:** the assistant's `writeFailed` used to stop a running window preview and leave it stopped. It now starts it again with `controller.startPreview()`, the function the sheet calls, and only when the write stopped it. `testAPreviewRunningBeforeTheAssistantsGetReadyIsRunningAfterEveryOutcome` covers done, nothing to do, write failed and stopped part way, over MCP with the window's preview showing. Only write failed was RED on the head before the fix (events `stop-begins, stop-ends`, no `start`).
4. **Part 2 (round two): 3 of 3, wording only.**
   - `shared-rules.json` → trail `undo set aside a change a restore replaced`: `line` and `carries` are descriptions (the app's line is `UndoAppSeams.setAsideByARestoreLine`, unchanged). They now give the Mac's three forms ("because a restore replaced its files", the partial form "set aside 2 files … 1 other file of it will be settled as before", "could not be reached when a restore replaced files of the course") and say what the line carries: the files set aside and how many are still judged.
   - `file-formats.json` → `folderRenameRecord`: the note now says both platforms read 'from'/'to'/'scope' only as JSON strings and both write every key (arrays only when not empty), with the Newtonsoft/CRLF clause kept, and that a released Windows build writes the three keys only. Example 1 is renamed "what a released Windows build writes" (bytes unchanged). The `moved` why says "a released Windows build, or an older Mac build". `contracts/README.md` about 2285 and 2299 to 2302: Windows no longer says the two half-failure sentences (since W8b 15b and 18b), and it writes the Mac's three part-way lines.
   - `shared-rules.json` → `folder renamed` → `carries`: "On the Mac, the same event…" now reads "on the Mac and, since W8b 18a and 18b, on Windows alike". The "On Windows until W8 …" sentence is gone, and "(one Windows or an older build wrote…)" now reads "(one a released Windows build or an older Mac build wrote…)".
   - Mac tests that read these keys: `SpecialFolderRenamerTests` (folderRenameRecord examples, by name) and `ActivityTrailWiringTests` (mustRecord). Both are green. No `scripts/test_*.py` names these keys (`grep -l` for `folderRenameRecord`, the two event names and the example name: none). Windows tests that read them (not built here): `RenameRecordShapeTests.cs` (examples, by name: it reads names from the JSON, so the rename travels) and `ActivityTrailWiringTests.cs` (mustRecord).

## Self-check

- Tests first, own commit (3e245fcf1), RED on the base (missing symbols; and each break below).
- Must-fail, each break run on its own (StartOfYearRestoreOfferTests): 1 part-way catch never taken: 12 failures; 2 no preview rebuild: 2; 3 no plan in the reply: 2; 4 menu title changed: 3. 4 of 4 RED; with round two's, 5 of 5.
- Proof (round two, on the final code): StartOfYearRestoreOfferTests, StartOfYearTests, SpecialFolderRenamerTests and ActivityTrailWiringTests, 95 of 95 passed. Round two's test was RED on 9b645abb3 for write failed only (the 5th must-fail). The class has its own Undo list (setUp).
- House rules: no GCD, no timed waits, no map/filter/reduce, no shorthand, explicit types. No new files in the app (no xcodegen change). No interim state: the reply is the final one; the parked half is a ruling question, not a meanwhile.
