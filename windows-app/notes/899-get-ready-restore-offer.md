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

## Fix round one (review 1: HIGH 1, LOW 1 to 3, INFO 1 and 2)

- **HIGH 1, Restore Course refused by a running preview.** Fixed by the director's decisions:
  1. After a part-way stop, `carryOut` no longer starts the section's preview again. `StoppedPartWay.previewWasStopped` says Go stopped it. **Leave As It Is** (`StartOfYearSheetModel.leaveAsItIs` → `StartOfYearPreparation.leaveAsItIs`) starts it again, once. The button now calls `model.leaveAsItIs()` and then `dismiss()`, and changes no file.
  2. **Restore Course** (`StartOfYearPreparation.restoreCourse`) stops every running preview of the course whose window is open (`SectionWindowControllers.sectionsShowing`, the window's own awaited `stopPreview`, as Go uses), then runs `workspace.restoreBackup`, then starts each stopped preview again once, Go's own included, if the course as restored (`course.asSavedNow().sectionNumbers`) still has that section. It asks nothing, because a preview can always be started again. While another program holds the course, nothing is stopped: the restore refuses that with its own sentence, and a preview stopped then could not be started again (#156).
  3. **A deploy in flight** holds the restore back (`restoreIsHeldBackByADeploy`, asked before the sheet closes). The sentence is the restore's existing busy sentence (`WholeCourseRestore.sentence(.busy)`), shown in the restore's own alert ("Could not restore {CODE}", OK) over the sheet. The sheet stays open with both buttons. The trail gets the restore's own did-not-go-ahead line (`refused: the course is previewing or deploying here`, asked before the archive). Nothing is stopped or started. The offer works once the deploy has ended.
  4. The offer is answered once (`offerAnswered`). A second press, or both buttons, never starts a preview twice, and each start also checks `isPreviewRunning()` first.
- **LOW 1:** `StoppedPartWay` now carries a `BackupItem`, made in `carryOut`. If `BackupItem.from` ever returned nil, the offer is not made. The sheet then says `writeFailed`, which is true here too ("The backup … holds the course as it was before you pressed the button"), and the preview is started again as for any refusal.
- **LOW 2:** the trail line now says "1 file kept beside its page" or "N files kept beside their pages". When nothing was kept it says no count (`testTheStoppedPartWayLineCountsWhatWasKept`).
- **LOW 3:** `testRestoreCourseRestoresWhileThisSectionWasPreviewing`, `testRestoreCourseStopsAndRestartsAnotherSectionsPreview` and `testADeployHoldsRestoreCourseBackAndTheOfferStillWorksAfter` run the REAL `WorkspaceModel.restoreBackup` after a part-way stop. The previews are `FakePreview`s that hold a real `PreviewLeases` lease while running (`holdingALease:`). The first two were RED on aa991d513 with the busy sentence (see the log).
- **INFO 2:** no change asked, and none made.
- **Windows:** `StartOfYearTests.EverySentenceIsTheContracts` now takes `deferred = NamedGapLedger.GapsIn(StartOfYearSheetWording, keys, ByKey.Keys)`, compares `keys.Except(deferred)` with `ByKey.Keys`, and skips deferred keys in the `ByKey[key]` loop, in the shape of `ContractTests.SharedRules_ActivityTrailEvents_Exist`. It is UNBUILT here; the PC suite on the integration tree proves it. For Windows to copy: no preview restart before the answer; Restore Course stops the course's previews, restores, and starts them again; a deploy holds it back with the busy sentence while the sheet stays open.

### For the director (fix round one)

- **Decision 2 is the director's reading, for Russell to confirm.** Restore Course stops other sections' previews without asking, and starts them again afterwards. Example: Section 2 of SNC1W stops part way while Section 3 of SNC1W is previewing in its own window. Pressing Restore Course stops Section 3's preview, restores SNC1W, and starts Section 3's preview again, with nothing asked. A preview that is not in an open window (none today) is not stopped, and the restore then says its busy sentence in its alert.
- **The per-file kept sentence stays out (parked).** The candidates are the three listed above. A new sentence with no hidden name, such as "What “{place}” held before is kept beside it.", would need Russell's words.
- **What Leave As It Is leaves on disk that the sheet does not mention (INFO 1).** While the undo list is in shadow (`UndoSwitch.undoJournalIsLive` false), each kept original whose bytes differ from its page stays beside that page for good, under its hidden name (`.{page}.plantoir-undo-…-orig`, `undo.rule.recovery`). It holds what the page held before Go, which is also in the backup the sheet names. So nothing unique is hidden, and the two sentences the sheet says are true. The backup zip stays in Backups. Restore Course archives the course first, hidden files included, so the hidden files go to Archived with it.

### Self-check (fix round one)

- Broke each fix on its own and watched its test fail: 7 of 7 RED (log).
- No timed waits: the stops are awaited; nothing sleeps except `FakePreview`'s existing stand-in for a real stop.
- Every sentence on the failure paths is true: the busy sentence is said only while a deploy (or, from the restore itself, a preview or deploy) is running. `writeFailed` on the LOW 1 path names the backup that was made.
- `dev` merged in: up to date at 12452f51d.
- No number tuned by trial; contract cases run from the JSON (the new tests take the door from `stoppedPartWayCases`' "then restore" case).
