# #899 (Mac): Get Ready for the Start of the Year, stopped part way, offers to restore the course

Branch `issue/899-get-ready-restore-offer`, base `origin/dev` 8046ca2e8. This piece is the SHEET. The assistant's reply is the next piece.

## For PROGRESS.md and the documentation

- `StartOfYearPreparation.carryOut` now catches `JournaledStepError.leftPartWay` from `StartOfYearPlanner.apply` as its own outcome, `Outcome.stoppedPartWay(StoppedPartWay)`. It carries the section, the course code and display code, the backup URL made at step 2, and the kept hidden names. Any other write error, which means the door changed nothing, stays `refused(writeFailed)` as before.
- The sheet (`StartOfYearSheetModel.Stage.stoppedPartWay`) stays open. It shows `startOfYear.wording.stoppedPartWay` and then `restoreOffer` (`StartOfYearSheetModel.stoppedPartWaySentences`). It has two buttons: **Leave As It Is** (`role: .cancel`, `.keyboardShortcut(.cancelAction)`, leading), whose action is only `dismiss()`, and **Restore Course** (`.keyboardShortcut(.defaultAction)`, trailing), whose action is `dismiss()` and then `model.restoreCourse()`.
- `restoreCourse()` builds the `BackupItem` for the backup Go made (`BackupItem.from`) and hands it to the injected `restoreWholeCourse`. The sidebar passes `workspace.restoreBackup(item)`, the same function Restore from Backup… runs. That function archives the course, does the staged restore and selects the course on success, or shows its "Could not restore {CODE}" alert (`BackupProblemTitle.restoring`) on failure. There is no second restore and no second confirmation.
- Trail: a part-way stop no longer writes "did not get ready … nothing was changed (writeFailed)", which was false. It writes `ActivityTrail.startOfYearStoppedPartWayLine` on the same event, `startOfTheYearNotDone`: "stopped part way getting ready for the start of the year from the app — some pages went into draft, N files kept beside the page; offered the backup {file}". It has no page names. The restore leaves its own `courseRestoredFromABackup` line.
- Contract: four keys under `startOfYear.wording` (`stoppedPartWay`, `restoreOffer`, `leaveAsItIsButton`, `restoreCourseButton`), plus `startOfYear.howToRunAStoppedPartWayCase` and `startOfYear.stoppedPartWayCases` (3 cases: part way then leave, part way then restore, nothing written so writeFailed). These are run from the JSON by `StartOfYearRestoreOfferTests.testStoppedPartWayCasesAsTheContractSays`.
- Documentation to update at the merge: `documentation/09-mac-app.md` → Get Ready for the Start of the Year (the failure paths). I did not edit it in this piece.

## HIG lines followed (fetched 2026-11-27 from developer.apple.com, HIG JSON)

- Sheets: "Display only one sheet at a time from the main interface." … "If something people do within a sheet results in another sheet appearing, close the first sheet before displaying the new one." So the offer is the same sheet, and Restore Course closes it before the restore can show its alert.
- Alerts: "Always place the default button on the trailing side of a row … Cancel buttons are typically on the leading side of a row." Also: "Note that you don't want to make a Cancel button the default button." And: "Aim for a one- or two-word title that describes the result of selecting the button … use title-style capitalization and no ending punctuation." (Ruled titles "Leave As It Is" and "Restore Course".) Escape: "Pressing Escape (Esc) or Command-Period (.) … macOS".
- Buttons ▸ Role: "Assign the primary role to the button people are most likely to choose. When a primary button responds to the Return key, it makes it easy for people to quickly confirm their choice." And: "Don't assign the primary role to a button that performs a destructive action". Restore Course is not destructive, because Archived keeps the course as it is now, so it is the default.
- No invisible controls: both keys are carried by the visible buttons' own shortcuts. There is no hidden key catcher.

## Must-fail log

See `899-get-ready-restore-offer-mustfail.log` beside this file. Each break was run on its own and then reverted.

## For Windows

- Windows owes the same four sentences, the same two buttons, and the same split between a stop that changed nothing (writeFailed) and a part-way stop (the offer). Restore Course runs Windows' existing whole-course restore from the backup made at Go, with no second confirmation.
- `NamedGapLedger.cs`: new area `StartOfYearSheetWording` ("shared-rules.json → startOfYear.wording") and `Owed(StartOfYearSheetWording, 899, V200, Reason899GetReadyRestoreOffer, the four keys)`. UNBUILT: this Mac cannot build Windows. Windows' `StartOfYearTests` (about line 248) compares the wording's key set EXACTLY with `StartOfYearWording.ByKey` and does not ask the ledger, so it will go red on Windows until that test reads `NamedGapLedger.GapsIn(NamedGapLedger.StartOfYearSheetWording, keys, saidHere)`, as `TodaysClassContractTests` does. I did not make that test change, because the brief said ledger edit only. See "For the director".
- `startOfYear.stoppedPartWayCases` is new. Windows has no runner for it yet. Hold it, or build the runner with W-side door kill points.

## For U5

The restore is called as it is (`WorkspaceModel.restoreBackup`). When U5 makes a restore an Undo step, Restore Course becomes one with no change here. U5 is not built.

## For the next piece (the assistant's reply)

- The MCP/local path is `AssistToolRunner.swift` about 3250 to 3260. `StartOfYearPlanner.apply` is caught by a plain `catch` there and noted as `startOfYearNotDoneLine(reason: "writeFailed")`. It needs the same `catch JournaledStepError.leftPartWay(_, _, let kept)` split.
- Russell chose: "The backup “{backup}” holds SNC1W as it was before. Ask me to restore it, or choose Restore from Backup…." If the teacher asks, run the existing restore. There is no new tool.
- `StartOfYearPreparation.StoppedPartWay` and `ActivityTrail.startOfYearStoppedPartWayLine(source:keptCount:backupFileName:)` (pass source "mcp" or "local") can be reused.

## For the director

- **Per-file sentence PARKED.** Every existing kept-file sentence names the hidden file, so none fits the ruling ("Way too technical."). I left it out. The exact candidates are:
  - `shared-rules.json` → `undo.wording.keptBesideIt`: "What {place} held before is kept beside it as the hidden file “{kept}”." (`JournaledStepError.keptSentence`)
  - `undo.wording.classDatesKeptBesideIt`: "What {place} held just before is kept beside it as the hidden file “{kept}”."
  - `course-management.json` → `backups.restoreWholeCourse.wording.keptWhatWasInTheFolder` names a visible folder, but it is about a restore, not this.
  A new sentence with no hidden name, such as "What “{place}” held before is kept beside it.", would be a new wording for Russell to rule on.
- Windows `StartOfYearTests` needs the one-line GapsIn change described above, or the ledger entry does not hold.
- Leave As It Is: the proof that it changes nothing is a scan showing its action is `dismiss()` alone and touches no `model.`/`Task`, plus the check that the backup is still listed by `findBackupItems`. A byte-for-byte snapshot taken around a no-op would prove nothing more.

## Self-check

- Broke each fix and watched its test fail, each on its own: yes, see the log.
- No timed waits where an event exists: none added. The tests await `goAhead()` and `restoreCourse()` directly.
- Every sentence on the failure paths is true: the trail no longer says "nothing was changed" for a part-way stop. The offer says the course moves to Archived, which `restoreBackup` does for a course the sidebar lists. writeFailed is unchanged and still said only when nothing was written.
- `dev` merged in: see the hand-back.
- No number tuned by trial: none.
- Contract cases run from the JSON: `stoppedPartWayCases`, laid out from `startOfYear.cases[0]`.
