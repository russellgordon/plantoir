# W7b2-9 (#899, Windows #949): the kept-file alert for Show on Front Page

**contracts/ changed:** `class-planning.json` → `todaysClassOnTheFrontPage.keptOnWindows` (new), `plainWordsExceptions` (new, review 1), `plainWordsCheck` (one sentence added) and the Windows clause of `fill`; `contracts/README.md`'s `todaysClassOnTheFrontPage` row (review 1). The Mac gate comes back. No `mac-app/` change.

Branch `issue/899-w7b2-9-kept-file-alert`, from `origin/issue/899-w7b2-6-todays-class` 43fd9af96 (reviewed CLEAN). It merges together with W7b2-6. `origin/dev` 0a0fbe267 was merged in first, in a0c2567f1. That merge had conflicts in two notes files (`899-w7b2-5-start-of-year.md` and `899-w7b2-11-w7b1-small-lows.md`): `dev`'s fold removed their "For PROGRESS" and "For documentation 12" sections, and W7b2-6 had edited those sections. I took the fold's removal and kept W7b2-6's edits everywhere else. It was merged again before hand-back: "Already up to date", so there is no second merge commit.

## What was built

When Show on Front Page is left part way (`Outcome.ShownWithWhatItHeldKept`), the section window shows ONE alert: `TodaysClassOnTheFrontPage.KeptAlertFor` describes it, and `SectionDetailView.ShowAlertAsync` renders that description (since review 1; the first round's `SayWhatTheFrontPageKeptAsync` is gone). It is a `ContentDialog` shown through `ShowDialogSafelyAsync`:

- **Title:** `keptTitle`, filled with the class (`TodaysClassOnTheFrontPage.KeptTitle`).
- **Message:** one `kept` sentence for each kept name, then the hidden-items sentence (`KeptMessage`).
- **Close button:** `OK`, which is also `DefaultButton = Close`. Enter and Escape both give OK.
- **Primary button:** `Open Folder` (`OpenKeptFolder`), a visible, labelled button on the left.

Open Folder calls `TodaysClassOnTheFrontPage.OpenTheKeptFolderAsync(keptOriginals, sayGone, openFolder)`. This is the seam the tests can see:

- Any kept file that is no longer there is said first, with `keptGone`, one sentence per name, in a content-only alert with OK.
- Then the FOLDER that holds the kept files still there is opened once, through the path bar's `FolderActions.OpenFolder`.
- The file itself is never selected or revealed. There is no Show in File Explorer button, and the file stays hidden.
- When the file is gone, nothing is opened.

This copies the Mac's `FolderActions.showInFinder(files:)`: its plan and its order, alert first, then Finder.

The words read the contract. `keptTitle`, `kept` and `keptGone` are retyped as C# and pinned against `wording` by `TheSentencesAreTheContracts`, the house pattern. The app reads no contract at runtime; the brief's "never from a C# literal" is met the same way every other sentence in this file meets it. The two Windows words are new keys beside `wording`, not inside it:

- `keptOnWindows.hiddenItems`: "To see it, open View in File Explorer and turn on Hidden items." (review 1, MEDIUM 2: the director's wording, true on Windows 10 and 11 alike, which Russell confirmed on 2026-11-26; it replaced the Windows 11 path "View > Show". After `kept`, which ends "… hidden, as “{kept}”.", it reads well: "… as “.index.md.plantoir-undo-1-apply-orig”. To see it, open View in File Explorer and turn on Hidden items.")
- `keptOnWindows.showKept`: "Open Folder". It is also pinned equal to `shared-rules.json` → `workingFolderPathBar`'s open action `windowsLabel`.
- **Why beside `wording`:** the Mac's `TodaysClassOnTheFrontPageTests.testTheWordingIsTheContracts` compares the WHOLE `wording` dictionary with its own (`XCTAssertEqual(ours, wording)`). A Windows key inside it would turn the Mac red, and this piece may not change `mac-app/`. The section's `fill` sentence said Windows' button "reads 'Show in File Explorer' … to be measured". That clause is now untrue, and it was rewritten to point at `keptOnWindows`.
- **`contracts/README.md`:** `class-planning.json` is one of the eight AUTHORED files. The README's opening paragraph names the five generated files, and `class-planning.json` is not among them. Nothing was parked.

## Guidance read today (2026-11-25)

- **Microsoft, Dialog controls:** https://learn.microsoft.com/en-us/windows/apps/design/controls/dialogs-and-flyouts/dialogs.
  - "Ensure that your dialog has at least one button corresponding to a safe, nondestructive action like 'Got it!', 'Close', or 'Cancel'. Use the CloseButton API to add this button." The Close button appears as the rightmost button and is what Escape presses. So OK is the Close button.
  - "The 'do it' action button(s) should appear as the leftmost buttons." So Open Folder is the Primary button.
  - DefaultButton is optional ("By default, no default button is set") and takes Enter. It is set to Close, because the alert is informational and the brief makes OK the default.
  - "The dialog title is the main instruction and is optional." That is why the `keptGone` alert carries its sentence as content, with no title.
  - "Don't repeat the title with slightly different wording": the message does not restate `keptTitle`.
- **Microsoft Support, View hidden files and folders in Windows:** https://support.microsoft.com/en-us/windows/view-hidden-files-and-folders-in-windows-97fbc472-c603-9d90-91d0-1166d1d9f4b5. The Windows 11 tab reads "Select View > Show, then select Hidden items to view hidden files and folders." The first round's sentence used those words; since review 1 the sentence is the one under `keptOnWindows.hiddenItems` above, true on the page's Windows 10 and Windows 11 tabs alike. The page loaded, so the fallback page was not needed.
- **Apple HIG, Alerts:** https://developer.apple.com/design/human-interface-guidelines/alerts. The web page renders by script, so it was read through its JSON (`/tutorials/data/design/human-interface-guidelines/alerts.json`).
  - "If the title is a complete sentence, use sentence-style capitalization and appropriate ending punctuation": `keptTitle` ends with a full stop.
  - "In informational alerts only, you can use 'OK' for acceptance."
  - "Always place the default button on the trailing side of a row": OK is rightmost on Windows, as on the Mac.
  - Button titles: "Aim for a one- or two-word title that describes the result of selecting the button": Open Folder.
- **The Mac's alert** (`SectionDetailView.swift` about 1110 and 2130, `FrontPageWording.swift` 45 to 90, `FolderActions.swift` 25 to 110) has the title `keptTitle`, the message `kept`, OK as `.defaultAction`, and then Show in Finder. A gone file gets an `NSAlert` whose messageText is `keptGone`, with OK, and Finder then selects only what is still there. Windows copies that order and opens the folder instead of selecting the file, by ruling (a).
- **A plain-words note for the director:** `plainWordsCheck` keeps "file" out of the sentences. The hidden-items sentence says "File Explorer", which is the name of Windows' program, and the new key's `why` says so. It lives outside `wording`, so no check reads it today.

## Review 1 (2026-11-25): 2 MEDIUM and 4 LOW, all fixed at c00d4b852

- **MEDIUM 1, fixed.** The alert is now plain data in Core: `TodaysClassOnTheFrontPage.AlertDescription(Title, Message, ActionButton, CloseButton, Default)` and `KeptAlert(Shows, KeptOriginals)`, built by `KeptAlertFor(offer, kept)`, with `PressedAsync(pressed, show, openFolder)` and `GoneAlert(sentences)`. The section window only renders a description (`ShowAlertAsync`, the one `new ContentDialog` for both alerts, so the census is 16) and wires the press in two lines. Tests: `TheKeptAlertIsTitledWithTheClassNowShownWithOkTheDefaultAndTheClose` (record equality against the contract's words), `TheGoneAlertSaysItsSentenceWithOkAlone`, `OnlyOpenFolderOpensAndAGoneFileShowsTheGoneAlert` (OK, Escape and never-shown open nothing; Open Folder opens the folder; gone shows the gone alert), and `TheSectionWindowOnlyRendersTheKeptAlertsDescription`, which pins each rendering and wiring line whole, once. That last one replaces the loose source test. Each of the review's five slips has a must-fail row (7 to 11), plus two in the view (12, 13).
- **MEDIUM 2, built as the director gave it:** see `keptOnWindows.hiddenItems` above; under "For the director"; Russell confirmed it on 2026-11-26.
- **LOW 1, fixed.** `plainWordsExceptions` lists "File Explorer", with where it is and why, following `userFacingLabelWords.exceptions`' shape; `plainWordsCheck` says a listed name is taken out before checking. `NoKeptAlertSentenceSaysATechnicalWord` checks the filled kept-alert sentences against the mac's T3 word list (must-fail 15).
- **LOW 2, fixed.** `contracts/README.md`'s row names `keptOnWindows` and `plainWordsExceptions`.
- **LOW 3, fixed.** `ReDateTests.ATimetableWindowsRefusesSaysWindowsWordsAfterTheCurlyApostrophe` (must-fail 14).
- **LOW 4, noted.** Tests-first still rests on the must-fail rows; with M1 fixed, each of them reads the alert's real make-up.

## Must-fail lines

Recorded in `vm-tools/guest/899-w7b2-9-mustfail.json` and run by `vm-tools/guest/899-w7b2-9-vm.ps1 -Mode mustfail` on VM A at f74e650b1. Each sabotage was applied alone, the named test was run, and then the file was restored with git. "RESTORED-STATUS 0 changed files"; afterwards the classes passed, 351 of 351. **6 RED of 6.**

1. The button reveals the file: `OpenTheKeptFolderAsync` hands over the kept file instead of its folder. `OpenFolderOpensTheFolderThatHoldsTheKeptFileNeverTheFile`: "Assert.Equal() Failure: Collections differ".
2. The button reveals the file: the section window passes `FolderActions.ShowInFileExplorer`. `TheSectionWindowShowsTheKeptAlertWithOkAsTheDefaultAndOpensTheFolder`: "Assert.Contains() Failure: Sub-string not found".
3. The hidden-items sentence is missing. `TheKeptAlertNamesTheFileThenSaysHowToSeeHiddenItems`: "Strings differ … Expected: …orig\". To see it in File Ex…".
4. `keptGone` is not said. `AKeptFileGoneByThePressIsSaidAndNothingIsOpened`: "Collections differ | Expected: [\"“.index.md.plantoir-undo-1-apply-orig” is no longe…\"] | Actual: []".
5. Riding low L1, the straight apostrophe put back. `ReDateTests.AReDateWhoseTimetableIsAFolderQuotesNoWindowsWords`: "Strings differ". The first run named the wrong class (`TimetableTests`; the test is in `ReDateTests` in the same file) and matched nothing (NOT-RED, no totals). The row was corrected and run alone: RED.
6. Riding low L2, the trail line loses the kept file's place. `ThePartWayTrailLineNamesTheHiddenFileWhatThePageHeldIsKeptIn`: "Assert.Contains() Failure: Sub-string not found".

## Runs

All on Windows VM A, under `vm-tools/runs/VM.lock` (`winvm.sh lock w7b2-9`; the brief's "VM-A.lock" is called `VM.lock` by the skill and by `winvm.sh`). Each run followed `sync` and `refetch-runtime.ps1`. The VM was parked (suspended on 02) and unlocked at the end. The gate's Colima and `runs/gate-n25-2/` were not touched.

- **a. 72efffec0, classes.** The app built x64 (0 errors), the UI tests built (0 errors), and the tests built. The classes gave 350 of 351. The one failure was the new source test, which looked for `"\n    }\n"` in the VM's CRLF checkout. Fixed in f74e650b1 by normalising line ends.
- **b. f74e650b1, classes.** Both builds 0 errors. **351 of 351 passed.** The classes were TodaysClassContractTests, UndoTodaysClassStepTests, NamedGapLedgerTests, TimetableTests, ReDateTests, DialogFirstFocusTests, DialogTitleScanTests and QuestionDialogScanTests, plus every class that a grep of `Plantoir.Tests` for `SectionDetailView.xaml.cs` finds (UndoWriterScanTests, ClassesDatedLaterAtDeployTests, CourseBeingCopiedTests, the Obsidian route pair, the six Preview classes, PublishingDestinationsContractTests, the Reference pair, ScheduledRunAnnouncementTests, SectionDeployRunSourceTests, SectionDetailTeardownSourceTests, SectionProblemsSourceTests and StopQuestionsContractTests).
- **c. f74e650b1, must-fail:** six rows, five RED and row 5 not matched. **d.** Row 5 corrected and run alone: RED. Restored: 351 of 351.
- **Tests first:** the tests were written before the product, but no separate red run was made before the product went in. The red evidence is the must-fail rows, one per behaviour, each RED against its own test.
- **UI check:** no `Plantoir.UiTests` class drives Show on Front Page (`git grep` for "Show on Front Page", `TodaysClassOnTheFrontPage` and `ShowTodaysClass` there finds nothing), so no `[UiFact]` was added and there is no screenshot. The part-way stop cannot be reached from the window without a seam, which the UI harness does not have.

- **e. c00d4b852 (review 1), classes.** Both builds 0 errors; **356 of 356 passed.**
- **f. c00d4b852, must-fail: 15 RED of 15**; restored, 0 changed files, 356 of 356.

## Riding lows

- **W7b2-6 review 1 L1, fixed.** `TimetableMemory.cs` 331 to 332 and `TimetableTests.cs` 788: `'` became `’`, and no other character changed. Must-fail 5.
- **L2, fixed.** `ThePartWayTrailLineNamesTheHiddenFileWhatThePageHeldIsKeptIn` pins the whole line, word for word. Must-fail 6. The part-way seams in `UndoTodaysClassStepTests` are now one helper, `PartWay()`.
- **L3, fixed.** Nothing is held any more, so `Reason899W4cKeptAlert` and its `TodaysClassWording` row are removed. The U3c comment now says the keys went with W7b2-9.
- **L4, note only.** It is a harness seam, not a teacher's path, and the brief does not cover it.
- **Sweep LOW 1:** this is L1 above.
- **Sweep LOW 2, NOT fixed.** The start of the year's part-way sentence no longer names the backup. This brief puts "any other part-way sentence" out of scope, and the change needs a wording ruling: which noun to use, and whether to name the teacher's backup from the app's Go. See "For the director".
- **Sweep LOW 3, comment fixed, behaviour unchanged.** `PlantoirTools.PrepareForStartOfYear`: the comment now says that the not-Changed branch covers both a refusal and a part-way stop, and that the plan which follows is what is still left to do. Whether the plan should follow a part-way sentence at all is a question for the director (below).
- **Sweep LOW 4, fixed.** `Reason899W7b2` no longer says "(briefed from W7b1's branch)". That one phrase was removed and nothing else in the row changed.

## Left for the next piece

Nothing of this alert.

## For the director

1. **Class Dates' own kept-file line.** W7b1 put that sheet's kept-file sentence in its status line. Should it use this alert too? Recommendation: no change. The sheet stays open and its status line is where the teacher is already looking. Not built.
2. **Sweep LOW 2, the start of the year's part-way wording.** Options:
   - (a) A sentence of its own that names the backup, as `writeFailed` did, plus the kept files. **Recommended**, since from the app's Go the backup is the teacher's own way back.
   - (b) Keep `RefusalForAStepThatStopped` and change only the noun ("the classes put into draft" or similar).
   - (c) Leave it.
3. **Sweep LOW 3, `prepare_for_start_of_year` after a part-way stop.** Should the current plan follow the part-way sentence? Options:
   - (a) Keep it. **Recommended:** the plan is recomputed from disk and holds what is still to do, with a fresh code.
   - (b) Answer the sentence alone, as for Changed.
4. **Documentation 12 and PROGRESS corrections** that the fold did not carry: the `writeFailed` "in no contract" clause, and the straight apostrophe in the quoted held-timetable sentence. Both carried by the fold of this merge window (night25/integration-3), in documentation 12 and PROGRESS.
5. **Confirmed by Russell on 2026-11-26: the hidden-items sentence**, "To see it, open View in File Explorer and turn on Hidden items." (the director's wording, review 1 MEDIUM 2), built as given.
6. **The Mac gate comes back** for the `class-planning.json` change. The Mac's tests read `wording` (unchanged) and the section keys it lists (unchanged), so I expect the Mac to stay green, but the gate has not run on this change.

## Self-check

1. Broke each fix and watched its test fail: must-fail 15 RED of 15 (run f).
2. No timed waits in the product or the tests. The VM waits are `winvm.sh`'s own.
3. Every sentence is true. The alert says the page now shows the class, that what it held is kept hidden under its name, and how to see hidden items. Open Folder opens the folder (tested). A gone file says `keptGone` and nothing opens (tested).
4. `dev` 0a0fbe267 was merged before proving (a0c2567f1) and fetched again before hand-back: up to date.
5. No number was tuned by trial.
6. House style. The words are pinned to the contract. The changes are in `windows-app/`, in `contracts/class-planning.json` (stated on the first line), and in `vm-tools/guest/`.
7. No fixture row (no step changed). The ledger row is gone, and `Reason899W4cKeptAlert` is removed rather than left untrue.
8. Writer-scan count: unchanged, because no writer was added. Opening a folder writes nothing. UndoWriterScanTests is green.
9. Riding lows: L1, L2 and L3 fixed with tests and must-fail rows; L4 is a note; the sweep's lows are fixed or written above with the reason.
10. File order and the before: unchanged from W7b2-6 (one file, read at plan time).
11. The guidance was read today: both Microsoft pages and the HIG's Alerts, with URLs above.
12. No invisible control. Both buttons are visible ContentDialog buttons, and there is no key catcher. Escape is WinUI's own Close.
13. The file is still hidden. Nothing clears its attribute, and `OpenFolderOpens…` asserts the Hidden attribute on Windows.

Must-fail rows 7 to 15 (review 1), all RED in run f, each against its own test: 7 Open Folder made the default; 8 OK removed; 9 OK opening the folder; 10 the gone alert drops its sentence; 11 `offer.Shows` in the title; 12 the view maps the default the wrong way round; 13 the view never shows the gone alert; 14 the Windows-said apostrophe straight; 15 the hidden-items sentence says "file". Row 2 now sabotages the press line `ShowAlertAsync, FolderActions.OpenFolder);`.
