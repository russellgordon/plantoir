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
2. **So the sentence is not Russell's word for word.** His: “The backup “{backup}” holds SNC1W as it was before. Ask me to restore it, or choose Restore from Backup….” Shipped: “The backup “{backup}” holds {course} as it was before. Choose Restore from Backup… to put it back.” "Ask me to restore it" would promise what the assistant then refuses. If he wants his words, they need the tool first; one line changes the key and `StartOfYearWording.restoreOfferThroughTheAssistant`.
3. **The preview** is brought up to date after a part-way stop (`bringThePreviewUpToDate`, as after any assistant action): no offer waits for an answer, and Restore from Backup… stops and starts previews itself. Tested (the stub's rebuild count). Not changed and seen in passing: the assistant's `writeFailed` refusal stops a running window preview before writing and does not start it again (no test here; the case says `expectPreviewRebuilt: false`, which is true for the no-window path the test runs).
4. **Part 2 (three stale contract sentences) was not started**: the budget went to part 1. Left whole.

## Self-check

- Tests first, own commit (3e245fcf1), RED on the base (missing symbols; and each break below).
- Must-fail, each break run on its own (StartOfYearRestoreOfferTests): 1 part-way catch never taken: 12 failures; 2 no preview rebuild: 2; 3 no plan in the reply: 2; 4 menu title changed: 3. 4 of 4 RED.
- Proof: StartOfYearRestoreOfferTests + StartOfYearTests, 37 of 37 passed. The class has its own Undo list (setUp).
- House rules: no GCD, no timed waits, no map/filter/reduce, no shorthand, explicit types. No new files in the app (no xcodegen change). No interim state: the reply is the final one; the parked half is a ruling question, not a meanwhile.
