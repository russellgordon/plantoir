Partly reversed by #1055 M7 (Russell's rule of 2026-11-27, evening: no link code beyond reading and writing through a link).

# #1055 M1: Insert Class refuses a later class that is a link, before anything changes (Mac)

Brief: `vm-tools/briefs/2026-11-27-1055-M1-insert-class-refuses-a-linked-later-class.md`. Branch `issue/1055-M1-insert-class-refuses-a-linked-later-class`, from `origin/dev` 99499d6b7. Touches `contracts/`: both gates.

## For PROGRESS

Mac, #1055 M1 (2026-11-27): Insert Class (Make Room, and Duplicate Class through the same code) is refused before anything changes when a later class page it would rename is a symbolic link, "cannot tell now", said as "The file “Unit 1, Day 3.md” couldn’t be saved." (the door's existing words), as before U4b3. The planner's rename loop is again `4f228c923`'s; every link-moving, re-pointing and step-1b line is gone. A section with no link plans the same step, op for op.

## What was removed

- `ClassInsertionPlanner.swift`: now `4f228c923`'s text except #1048's lines (`classesBefore`, `tail` from `classesBefore`, the date comment ending "(`ClassPages.dateKey`)", the `ClassPages.dateKey` guard and the `isTheFirstClassLeadingToItsFile` block) and the five things `ClassPages` calls, each with the one doc line "Kept for `ClassPages` until #1055 S1.": `isALinkToNothing`, `reachOfALinkedClass`, `LinkedClassReach`, `ClassPagePlace`, `ResolvedFile`. Gone: the reach set-up (`classPagePlaces`, `workingFolder`), `hopsRePointed`, the link branches of the rename loop, step "1b", the two link skips in the dates loop, and the helpers `isALinkToAFile`, `spelledAsItsNewPlace`, `fileALinkLeadsTo`, `classPagePlaces`, `workingFolderURL`, `textAfterTheMove`, `relativeText`, `rePointWhereItStands`, `isInside`, and the type `HopEntry`. Each grepped first: none had a caller outside the planner (the other `fileALinkLeadsTo` is `CourseConfiguration`'s own; the other `isInside` is `PlanNavigation`'s; the `workingFolderURL` hits elsewhere are local names).
- Tests: every test of `UndoMakeRoomLinkedPageTests.swift` after the fixture (35, the three kill tests among them); the fixture helpers nothing calls now (`linkTarget`, `text`, `replaceWithALink`); in `DateKeyByTheTargetsPlaceTests.swift` the `makeRoom` helper and its four Insert Class tests.
- `contracts/shared-rules.json`: 13 `undo.stackCases` rows (4 "U4b3, Insert Class renaming a later class that is a link", 6 "U4b3 relink-5, Insert Class", 3 "mac-2, Insert Class"), checked by script: 148 to 135, every other row equal as parsed and in order, the sorted name lists differ only by the 13; the `undo.stackCasesHow` span from "U4b3 part 2: `makeRoomWithALaterClassThatIsALink` lays" to just before "`renameAFolderInCaseOnly` makes" (the six calls and the keys `linkedPage`, `laterLinks`, `hopLink`); the `undo.rule.shadow` span replaced with the brief's text, everything before and after it unchanged (checked), its three substrings once each (checked). Every other key of the file equal as parsed (checked).
- Mac replay: the six call branches, the three key checks and the three known-key names (`UndoContractReplay.swift`); the call-list entries, `makeRoomWithALaterClassThatIsALink`, `laidLinkedPageCourse`, `linkedPage(in:)`, `hopLink(in:)`, `laterLinks(in:)` and the constants `linkedPageClasses`, `linkedPageDates`, `linkedPageTarget`, `linkedPageFile`, `linkedPageDay`, `linkedPageText`, `hopLinkPath`, `hopLinkFromDay4`, `hopLinkBefore` (`UndoContractReplayKinds.swift`; each grepped: none used elsewhere).
- Python model (`scripts/test_make_undo_traces.py`): the six calls' model, the readers `hop_link`, `linked_page`, `later_links` with the constants and helpers only they reach (`LINKED_*`, `HOP*`, `linked_day`, `linked_text`, `linked_redated`), their asserts, the three keys, the six names. `scripts/make_undo_traces.py` has no Insert Class link code (grep empty).
- `UndoSweepFindingsTests.swift`: one doc comment only ("No writer makes such a step: Insert Class renames ... by MOVING the link" was no longer true; it now says Insert Class plans such a step for a linked later class and is refused so). No code changed.
- Notes kept, each with the top line "Removed by #1055 (2026-11-27): symbolic links in course content are not supported.": `899-u4b3-linked-class-page-moves-its-link.md`, `899-u4b3-part2-insert-class-moves-a-linked-class.md`, `899-u4b3-relink-5-insert-class-re-points-a-linked-class.md`, `899-mac-2-insert-class-re-points-an-in-between-link.md`.

## What was put back

The rename loop of `4f228c923` (lines 359 to 379, copied by script, `diff` against `git show 4f228c923:` empty): `fileExists`, `readText`, `settingTitle`, `step.write`, `step.remove`. The refusal is the door's, untouched: `JournaledStep.remove` plans the link's own place (`throughALink: false`) and the step refuses `cannotTellNow` naming the page. At `origin/dev` the door names the linked page itself (`Unit 1, Day 3.md`), as the brief expects.

## Tests (red first)

Commit 8c8f31f3f (tests only), run on the base planner (`.dd/run-red2.log`):

- `testALinkedLaterClassInsideTheWorkingFolderIsRefusedBeforeAnythingChanges`: RED, line 160 "Insert Class went ahead", 172 (the elsewhere file gained `createdSection1: 2026-09-16`), 173 (2 steps, not 1).
- `testALinkedLaterClassOutsideTheWorkingFolderIsRefusedBeforeAnythingChanges`: RED, 160 "Insert Class went ahead", 172 (the link moved to Day 4), 207 (a `wentAhead` line), 208 (the file outside re-dated).
- `testDuplicateClassWithALinkedLaterClassIsRefusedBeforeAnythingChanges`: RED, 236 ("Duplicated “Unit 1, Day 1” as “Unit 1, Day 2”."), 238 (a class at Day 4), 242 (the folder changed), 243 (a step recorded).
- `testAPlainSectionStillPlansTheSameStep`: green on the base (its three ops recorded from the base's first run, `.dd/run-red.log`, each op's JSON with sorted keys).

## Runs

- `origin/dev` fetched before proving and again before handing back: both times still 99499d6b7, so no merge commit was needed (already up to date).
- Green run (`.dd/run-green.log`), one class list through `xlock.sh`: `UndoMakeRoomLinkedPageTests`, `MakeRoomForClassesTests`, `DuplicateAsNextClassTests`, `ClassPlanningTests`, `NumberedCourseTests`, `ClubNounTests`, `AssistToolRunnerTests`, `DateKeyByTheTargetsPlaceTests`, `FirstClassKeepsASharedLessonTests`, `JournaledStepTests`, `UndoJournalContractTests`, `SharedRulesContractTests`, `UndoWriterScanTests`, `SectionVerbsTests`, plus `UndoOpKindsTests`, `ClassPlanningContractTests`, `UndoSweepFindingsTests` (they read the contract or a changed file): every class 0 failures except one line of the new Duplicate test, which compared the folder including the assistant's own backup zip (`courses/_backups/...`, taken before any action). Fixed by comparing without `courses/_backups` (`everythingButTheBackups`); `.dd/run-green2.log`: the class 4 of 4 green.
- Plain Debug build after the last test run: BUILD SUCCEEDED (`.dd/run-build.log`).
- `python3 scripts/test_make_undo_traces.py`: 46 tests OK; it did not say the traces are stale.

## Windows (edited by reading; not compiled)

- `windows-app/Plantoir.Tests/NamedGapLedger.cs`: the constant `Reason899W8bLinkedClassPage` and its blank line, and the whole `Owed(UndoStackCases, 899, V200, Reason899W8bLinkedClassPage, ...)` block (13 names) deleted, by script (asserted 13 lines, the last ending `"),`). The entry before still ends `"),`; the next line is a comment, then `Owed(`. No other line names the reason.
- `windows-app/Plantoir.Tests/UndoMakeRoomStepTests.cs`: `4f228c923`'s side of the one hunk put back with the brief's three changes: the method name `ALinkedLaterClassIsWrittenPlainlyWithTheLinkRemovedAndItsFileUntouched_WhereTheMacRefusesBeforeAnythingChanges` (declaration and `nameof`), "settle it (#1055 W1)", the doc comment's sentence "#1055's W1 brings the Mac's refusal to Windows and retires this test; until then it holds the difference by name". The first assert reads "never follows the link and is refused before anything changes" again. Read back: every quote balanced, no `\"` needed, every parenthesis closed. Test body untouched.
- What Windows still holds: that one test, by name, until W1. No Windows test runs the 13 rows (they were all held), so the suite stays at its six known failures.

## For documentation 12

W8b piece 22 is cancelled; #1055 W1 makes Windows refuse a linked later class as the Mac does (Insert Class and Duplicate Class refused before anything changes, "cannot tell now", naming the later class page that is a link), and retires `UndoMakeRoomStepTests.ALinkedLaterClassIsWrittenPlainlyWithTheLinkRemovedAndItsFileUntouched_WhereTheMacRefusesBeforeAnythingChanges` and the clause's Windows half in the same merge.

## Self-check (COMMON)

1 to 6 (NIGHT3): own classes only, through `xlock.sh` with the 15-minute kill; no gate, no UI test, no app, no Windows machine; no timed waits; no new or changed sentence a teacher reads (the refusal is the door's existing one); no number tuned; ledger strings removed only, by script.
7. House style: `grep -n "DispatchQueue\|\.map {\|\.filter {\|\.reduce(\|\$0"` over the added lines of every changed Swift file is empty; the kept types keep their MARK sections; the new tests sit under MARK sections.
8. No riding lows.
9. The switch is still off (`UndoSwitch.undoJournalIsLive = false`); the rename record untouched.
10. No new contract row; 13 removed from the contract, the Mac replay, the Python model and the Windows ledger together.

Done greps: the planner grep and `makeRoomWithALaterClass\|laterLinks\|hopLink` are empty; `Reason899W8bLinkedClassPage\|_WhereTheMacMovesTheLink_` is empty in `contracts` and `windows-app/Plantoir.Tests`, and hits only `windows-app/PROGRESS.md` (documentation, piece D's) and older notes files.

## For the director

- No parked question. Nothing a teacher reads changed: the refusal is the door's existing sentence.
- `windows-app/PROGRESS.md` line 2438 still names `Reason899W8bLinkedClassPage` and the U4b3 behaviour: piece D's (documentation), not edited here.
