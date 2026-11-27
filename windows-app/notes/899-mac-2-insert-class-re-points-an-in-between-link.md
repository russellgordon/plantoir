# mac-2 (#899 Undo): Insert Class re-points an in-between link where it stands

Brief `vm-tools/briefs/2026-11-27-899-mac-2-insert-class-re-points-an-in-between-link.md`. Base `origin/day27b/integration-2` 35b54c40a (dev 454ef4c6f + mac-1), as the director said. `origin/dev` merged before proving: "Already up to date". **`contracts/` touched (one `undo.rule.shadow` sentence): both gates.** Stopped at the brief's stop figure: the invariant and the three riding lows are built and proven; the contract rows, replay call, Python model, held ledger rows and must-fail log are left (below).

## For PROGRESS

- `ClassInsertionPlanner.apply`: the refusal block and `firstLinkThatCannotBeMoved` are gone (`grep -n firstLinkThatCannotBeMoved mac-app` empty). Rename loop: `.aRenamedPageThrough(hop, newPlace)` with the hop inside the working folder moves the class's link as itself (`moveLink`, text kept) and re-points the hop where it stands (`rePointWhereItStands`: `relinkLink(hop, to: hop, textAfter:)`, the hop's text with only its last path part replaced, planned once per hop). Only the folders above the hop are tidied: `standardizedFileURL` on a path holding `..` resolves the link itself (it turned the hop into the lesson's page and refused the lesson's own removal, cannotTellNow, on the first green run). New step 1b after the rename loop: each re-date-only class whose link reaches a renamed page is re-pointed where it stands (own text; hop inside; own link straight at the page's new place when the hop is outside). The dates loop still skips such a class (unchanged).
- Re-date-only shapes all occur in a numbered course (Week 1 to 3, Week 5 a link whose date is read through it as Week 2's; room at Week 2 renames Week 2 and 3 and only re-dates Week 5): all three tested.
- Riding LOW 1 (review 3 LOW 5): `UndoSwap.relinkLink`'s two-place pre-clean settles its own staged name by `settleUnderARelinksStagedName` with `givingBack: false` (new parameter): the teacher's item is kept visible beside `to` and said; never given back onto `to` (this swap never moves anything into that name, and the relink is about to fill `to`). Unreadable: `cannotTellNow`; would not move: `couldNotWrite`.
- Riding LOW 2 (review 4): after the exchange, an item that cannot be settled is exchanged back unread (it was at the place, so it is never the step's) and the swap's own link removed by its text, refused changedSince; if the exchange back is refused too, new outcome `UndoRelinkOutcome.leftUnderTheStagedName` and the refusal names the hidden name (`cannotTellNow` or `couldNotWrite`). The caller's comment now says what stands where.
- Riding LOW 3 (review 4): `killAChain` returns its faults; `testChainedLinkMovesKilledAtEveryStopPointLoseNoLink` gathers them and asserts once on the main actor. F-J's recorded "5 of 20"/"6 of 20" were XCTest's count; review 4 measured 7 of 20 every run; the test comment now says 7 (not re-measured here: left, see below).
- The director's extra shape: a teacher's page under the two-place relink's own staged name beside Day 5 of a chain (`testATeachersPageUnderAChainedRelinksStagedNameIsNeverDeleted`, live and killed before each swap). The Mac never deleted it: before the fix, live left it hidden with "in use" (red), after a kill recovery already kept it; now live keeps it visible and said too.

## For documentation 12

W8b piece 22b no longer copies "the Mac's two remaining refusals": it builds this re-pointing after 21b's one-place relink. Replacement sentence for the bullet near 18086 and the section "What the Mac's U4b3 leaves for Windows" (18360): "Insert Class never refuses for where a later class's link leads: a renamed class reaching a renamed class page through an in-between link inside the working folder is renamed as itself and the in-between link re-pointed where it stands (its text with only the last path part changed, once per link); a class only re-dated is re-pointed where it stands (its own text, the in-between link inside, or its own link straight at the page's new place when the link in between is outside)." For piece 22: the comment above `UndoMakeRoomStepTests.cs` line 290 still says "the title and date written into the file it leads to" (day27-1 sweep LOW 4). No trail event, `folding.moves` row, wording key or `file-formats` reason changed.

## Must-fail lines

Not run (stop figure). Owed: M1 refusal put back; M2 the class's own link re-pointed instead of the hop; M3 the hop planned twice; M4 the re-date-only loop removed; M5 Python. The tests that would catch each were seen red first (Runs 1).

## Runs (`.dd/`)

1. run-red (tests only, d2bbca211): 70 tests, 17 failures: all 6 new Insert Class tests (refused cannotTellNow) and the 3 riding-low tests plus the chained staged-page test red.
2. run-green1: UndoRelinkTests 38 of 38; 4 Insert Class red (the `..` hop key, above). run-green2: UndoMakeRoomLinkedPageTests 32 of 32.
3. run-classes (UndoMakeRoomLinkedPageTests, MakeRoomForClassesTests, UndoRelinkTests, JournaledStepTests, DateKeyByTheTargetsPlaceTests, UndoJournalContractTests, SharedRulesContractTests, UndoSweepFindingsTests, UndoStoppedStepTests, UndoRolloverStepTests, RestoreRecoveryTests, ClassPlanningContractTests): 331, 0 failures, after the contract and documentation edits.
4. `python3 scripts/test_make_undo_traces.py`: OK, traces current.

## Left for the next piece

- `undo.stackCases` rows "mac-2, Insert Class with a later class linked through a link inside the working folder: …" (one step; undone; undone and redone) and one per re-date-only shape; replay call `makeRoomWithALaterClassLinkedThroughALinkInside` and a key reading the hop's text in `UndoContractReplay.swift`; `stackCasesHow`; the Python model's hop re-point; each row held under `Reason899W8bLinkedClassPage` with the constant reworded (brief's "What Windows must hold"). Each will fail on Windows because its call is unknown to the replay.
- The must-fail log (M1 to M5) and a re-measure of F-J with the gathered faults (expected 7 of 20).
- Doc 12's two sentences (the clerk, from the text above).

## For the director

Nothing parked.

## Self-check

1 Must-fail not run (left). 2 No timed waits. 3 No new sentence a teacher reads; existing refusals. 4 dev merged before proving (up to date); again before hand-back. 5 No number tuned. 6 Contract checks run from the JSON (the three `UndoMakeRoomStepTests.cs` substrings each once, by script). 7 House-style grep over the added Swift lines empty; no new type. 8 Review 3 LOW 5 and review 4's two LOWs fixed with tests seen red first; day27-1 LOW 5 (the refusal) and LOW 6 (the "own text cannot be read" sentence) fixed. 9 Switch off, rename record untouched. 10 No new contract row (left).

## Finished by the second writer (2026-11-27)

`origin/dev` merged before proving and again before hand-back: "Already up to date" both times (dev 454ef4c6f; mac-1 is already in this branch's base). **`contracts/` touched (stackCases rows, `stackCasesHow`, one new trail event, one event's `carries`; `file-formats.json` opKinds.move's two pointers): both gates.**

### What was owed, and what was done

1. **Must-fail M1 to M5 and F-J**: see "Must-fail lines (second writer)" below.
2. **The contract.** Three `undo.stackCases` rows, "mac-2, Insert Class with a later class linked through a link inside the working folder: …" (one step, undone; undone and redone; made and kept), new replay call `makeRoomWithALaterClassLinkedThroughALinkInside` (`UndoContractReplay.swift`, `UndoContractReplayKinds.makeRoomWithALaterClassThatIsALink(…, throughAHopInside:)`) and new key `hopLink` (the text `courses/TST1O/elsewhere/hop.md` holds as a link, `notALink`, or `nothing`), both named in `stackCasesHow`. Re-date-only shapes have NO stackCases row: the replay's linked course is a dated course with no numbered plan, and a numbered-course fixture in the replay is a piece of its own; the three shapes are proven by `UndoMakeRoomLinkedPageTests` (`testAReDateOnly…`, three tests) on the Mac. Left for the next piece if the director wants them as contract rows. Python model: the call and `hop_link` in `scripts/test_make_undo_traces.py` (46 tests OK, traces current: `test_make_undo_traces.py` reports no staleness, nothing regenerated).
3. **Documentation 12**: the two sentences replaced (the "Only two arrangements are still refused" sentence near 18086, and the end of the "Insert Class and Duplicate Class move a linked later class as a link" bullet in "What the Mac's U4b3 leaves for Windows"), both with the replacement sentence above; the pointer near 18421 now says `contracts/file-formats.json`. Its recovery bullet (about 18425) names the new trail line.
4. **The kept-item trail line (sweep finding 1).** No wording in the contract was true of the live case (the kept-page and kept-folder lines both say a change that stopped removed, moved or set the item aside). ONE new line, event `undo kept an item found where a link was being changed` (`ActivityTrail.Event.undoKeptAnItemFoundWhereALinkWasChanged`, `activityTrail.mustRecord`, `UndoTrail.keptAnItemFoundWhereALinkWasChangedLine`, hook `UndoTrailHook.keptAnItemFoundWhereALinkWasChangedLine`): "ICS3U/1 · an item that was not Plantoir's was found where a link was being changed, at courses/ICS3U/section1/Unit 1, Day 4.md, and is kept as courses/ICS3U/section1/Unit 1, Day 4 (kept by Undo).md". `UndoRecovery.tellingWhatIsKept` (live swap and recovery tidies alike, page, folder or link) says it and never the kept-page or kept-folder line. The kept-page and kept-folder events keep their stopped-step meaning (their `why`s are now true: no relink keep reaches them). `file-formats.json` opKinds.move's two "(the kept-page or kept-folder line)" now name the new line; documentation 09's two mac-1 sentences likewise.
5. **The exchange refusal's reason (sweep point 3).** The only "(the disk may be full)" on the Mac is the trail line `undo refused for a change left part way` (`UndoTrail.leftNewestLine`), whose `couldNotWrite` clause was "nothing could be written beside X (the disk may be full)". It now reads "X could not be changed in its folder, which may be full or may not allow the change", true of a full disk, a folder that will not take a new file and a volume that refuses the exchange; the event's `carries` says so. What a teacher reads when Insert Class meets such a volume is unchanged and true: "Nothing was changed: The file “hop.md” couldn’t be saved." (the system's sentence for `couldNotWrite`, `JournaledStepError.errorDescription`), refused before anything changed, the step closed failed, nothing on the list. Tested through `relinkRenameInFails` (`UndoRelinkTests.testAVolumeThatRefusesTheExchangeIsSaidTruly`, `UndoMakeRoomLinkedPageTests.testInsertClassOnAVolumeThatRefusesTheExchangeIsRefusedWithATrueReason`).

### What Windows must hold (complete)

- Three new `stackCases` rows held in `NamedGapLedger.cs` by exact name under `Reason899W8bLinkedClassPage` (each name once in the contract and once in the ledger, checked by script); the reason reworded: no arrangement is said to be refused; it adds "a later class reaching a renamed class page through an in-between link inside the working folder is renamed as itself and the in-between link re-pointed where it stands (mac-1's relink, Reason899W8RelinkedLink first; …); a class only re-dated is re-pointed where it stands (…)" and names the new call and the key `hopLink`. No unescaped double quote in the C# string (checked by script). Each new row fails on Windows today at its first call: `makeRoomWithALaterClassLinkedThroughALinkInside` is unknown to Windows' stack replay, and the key `hopLink` is not in its checked keys.
- **New trail event** `undo kept an item found where a link was being changed` (`activityTrail.mustRecord`): Windows' W8b piece 21b says it, never the kept-page or kept-folder line, wherever its relink keeps an item found under a relink's own staged name (NEW or ASIDE) under `<name> (kept by Undo)`, live and in recovery. Windows' trail-event pin will fail until `ActivityTrail` gains the event: say so on the W8b 21b issue (the director's to file; this writer opened no issue).
- **Changed trail clause**: Windows' `UndoRecovery.cs` (about line 299) still says `nothing could be written beside {path} (the disk may be full)` for `CouldNotWrite` in the left-part-way refusal line; it owes "{path} could not be changed in its folder, which may be full or may not allow the change" (the event's `carries`). No contract case pins the clause, so nothing fails on Windows today: piece 22 (or 21b) copies it.
- No `folding.moves` row, wording key or `file-formats` reason changed. `file-formats.json` opKinds.move: two parenthesised pointers now name the new trail line (text only).
- For piece 22: the comment above `UndoMakeRoomStepTests.cs` line 290 still says "the title and date written into the file it leads to" (day27-1 sweep LOW 4).

### Must-fail lines (second writer; `windows-app/notes/899-mac-2-mustfail.log`)

Each sabotage applied by script, built, run, restored from a copy and compared equal (source `git diff` clean after the last). 6 of 6 RED.
- M1, the refusal put back (a `cannotTellNow` throw in the in-between branch): RED `testALinkReachingARenamedPageThroughALinkInsideIsRePointedWhereTheHopStands` (caught refused cannotTellNow).
- M2, the class's own link re-pointed instead of the hop inside: RED, same test, 2 failures (Day 6 holds `Unit 1, Day 5.md`, not its own text; the hop not re-pointed).
- M3, the hop planned twice (the once-per-hop check bypassed): RED `testTwoRenamedClassesReachingOneHopRePointItOnce` (the step refused notReadable: two ops at one place).
- M4, the re-date-only loop removed (step 1b skipped): RED, the three `testAReDateOnly…` tests, 6 failures.
- M5 (Python), the model without the hop re-point: RED `test_stack_cases`, 2 failures (hopLink still Day 3's).
- F-J re-measured (mac-1's sabotage: `tidyLeftovers` judges by the one rule every staged name beside any relink's from or to): RED `testChainedLinkMovesKilledAtEveryStopPointLoseNoLink`, one gathered assertion naming exactly **7 of 20** kills of `aNewClassWrittenAtTheRelinksFrom` (apply beforeSwap(0), relinkStaged(0), relinkRenamedIn(0); undo relinkRenamedIn(1); redo beforeSwap(0), relinkStaged(0), relinkRenamedIn(0)), matching the test's comment.

### Runs (second writer, `.dd/`)

1. run-red2 (tests first, 6206caedd): 164 tests in 5 classes, 10 failures: the 4 relink keeps said on the kept-page line (`untrue: …`) or unsaid, the exchange-refusal clause (3 asserts) in `UndoRelinkTests`; the clause (2) and the step-on-the-list count in `UndoMakeRoomLinkedPageTests` (that last was the test's own fault: a step refused at the swap is closed failed, so the test now counts the list, not the records). The three new stackCases rows passed at once (the product was already built).
2. run-green3 (8c62ef2a6): 398 tests in 16 classes (`UndoRelinkTests` whole, `UndoMakeRoomLinkedPageTests`, `MakeRoomForClassesTests`, `JournaledStepTests`, `DateKeyByTheTargetsPlaceTests`, `UndoJournalContractTests`, `SharedRulesContractTests`, `UndoSweepFindingsTests`, `UndoStoppedStepTests`, `UndoRolloverStepTests`, `RestoreRecoveryTests`, `ClassPlanningContractTests`, `ActivityTrailWiringTests`, `UndoShadowPublishTests`, `FileFormatsContractTests`, `UndoOpKindsTests`), 0 failures.
3. `python3 scripts/test_make_undo_traces.py`: 46 tests OK, traces current.
4. Must-fail runs (above), then a plain Debug build: BUILD SUCCEEDED.

### Self-check (second writer)

1. Must-fail: 6 of 6 RED (M1 to M5, F-J), each restored and compared equal. 2. No timed waits; the new seam is a trail hook. 3. One NEW sentence (a trail line support reads): "an item that was not Plantoir's was found where a link was being changed, at <place>, and is kept as <visible name>", in the contract with its event; one CHANGED clause: "<path> could not be changed in its folder, which may be full or may not allow the change". No sentence on a sheet or in a reply changed; no interface change, so no HIG section applies. 4. `origin/dev` merged before proving and before hand-back (up to date both times). 5. No number tuned. 6. Contract checks run from the JSON: the new trail line compared with `mustRecord`'s `line`; each held name once in each file and no unescaped quote, by script. 7. House-style grep over every added Swift line empty; no new type; MARK sections unchanged. 8. The sweep's three points fixed with tests seen red first (the doc-12 pointer by reading); M1 to M5 as the brief names. 9. Switch off, rename record untouched. 10. Every new contract row is in the Mac's replay (green) and the Python model, and held on Windows by exact name.

### Left for the next piece (second writer)

- `stackCases` rows for the three re-date-only shapes: need a numbered-course fixture in the replay and the Python model (see point 2 above); Mac unit tests cover all three.
- Windows' trail clause in `UndoRecovery.cs` about 299 and the new trail event (above): W8b 21b or 22, the director to put on its issue.
