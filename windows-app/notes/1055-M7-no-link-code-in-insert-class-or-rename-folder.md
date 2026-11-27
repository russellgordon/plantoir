# #1055 M7: Insert Class and Rename Folder carry no link code (Mac)

Brief: `vm-tools/briefs/2026-11-27-1055-M7-insert-class-and-rename-folder-carry-no-link-code.md`. Branch `issue/1055-M7-no-link-code-in-insert-class-or-rename-folder`, from M6's pushed head cd27c181a. Mac only, no `contracts/` or `scripts/`: the Mac gate, the window's. Questions 1 and 2 of ORDER answered "leave it" (the director's reading of Russell's rule): no link code, the door's general guards stand.

## For PROGRESS

Nothing a teacher sees changes. Insert Class and Rename Folder have no code or test that exists only because a page or folder may be a symbolic link.

## What was removed

- `SpecialFolderRenamer.swift`: `FolderRenamePlan.Move.isALink` and its doc comment, the planner's `let isALink … == .link` line and the `isALink:` argument (U4b2-5 review 1 L3, `a7d345d42`; kept by M2 `13c1b3024`); in `foldersAtTheirNewName`, `movedALinkHere` and its assignment, and `case .link:` joins `case .absent, .somethingElse:` (`continue`). Dead since the listing guard refuses a link before any `Move` is made.
- `Move(` callers: one passed `isALink: true`, the second half of `SpecialFolderRenamerTests.testALinkAtTheNewNameIsNotTheRenamedFolderUnlessALinkWasMoved` (a link the rename moved there counts as the renamed folder): removed, the test renamed `testALinkAtTheNewNameIsNotTheRenamedFolder`, first half unchanged, doc comment as briefed. One passed `isALink: false` (`testAStartRunAfterARecordWithoutItsPlacesCarriesThemForward`): argument dropped.
- `UndoRenameFolderStepTests.swift` (M2, `13c1b3024`): `testAPerSectionFolderThatIsALinkIsRefusedBeforeAnythingChanges`, `testASharedFolderThatIsALinkOutOfTheWorkingFolderIsRefusedAndWhatItLeadsToIsUntouched`, and the helpers only they used: `linkSectionTwosTasks`, `everything(under:leaving:)`, `assertThePlanRefuses`, `refusalSentence`, `stepsOnTheList`. `linkTarget` stays (the dangling-link test uses it); the section's MARK now names the dangling link. `testAPlainPerSectionRenameStillPlansTheSameMoves` read `move.isALink` in its planned lines: the ` link false` suffix is dropped from the line and from both expected lines; everything else, ops and listing shas included, unchanged.
- `UndoMakeRoomLinkedPageTests.swift` (M1, `839bbbce3`): the three link tests (`testALinkedLaterClassInsideTheWorkingFolderIsRefusedBeforeAnythingChanges`, `…OutsideTheWorkingFolder…`, `testDuplicateClassWithALinkedLaterClassIsRefusedBeforeAnythingChanges`) and helpers only they used: `makeALink`, `everything(under:)`, `everythingButTheBackups`, `checkRefused`. The file STAYS where it is (the generated `project.pbxproj` lists it, 4 entries), header rewritten to say it pins the plain Make Room step (#1055 M7). `testAPlainSectionStillPlansTheSameStep` unchanged in body.

## What stays (grep)

- `SpecialFolderRenamer.swift:640`: "A folder whose content cannot be read cannot be judged as a pair", word for word (U4b's general listing guard).
- `testAFolderHoldingASymbolicLinkIsRenamedWithTheLinkMovedAsALink` (UndoRenameFolderStepTests:704), `testADanglingLinkAtASectionsPlaceIsSkippedAsBeforeU4b` (:783), `testAPlainPerSectionRenameStillPlansTheSameMoves` (:806), `testAClassPageThatIsALinkCanBeCopied` (DuplicateAsNextClassTests:405), `testAPlainSectionStillPlansTheSameStep` (UndoMakeRoomLinkedPageTests:107).
- Empty: `git grep -n "isALink\|movedALinkHere" -- mac-app/QuartzTeachers/Models/SpecialFolderRenamer.swift mac-app/Tests`; `git grep -n "ThatIsALinkIsRefused\|ThatIsALinkOutOfTheWorkingFolderIsRefused\|LinkedLaterClass.*IsRefused" -- mac-app/Tests`.

## For documentation 12

Nothing for Windows here: Windows' renamer still moves a linked folder as a link (`step.MoveLink`, the `.Link` presence) until W4, and Windows never had M1's or M2's tests.

## Must-fail lines

Mutant (never committed): `foldersAtTheirNewName`'s `case .link:` appends the place. `SpecialFolderRenamerTests.testALinkAtTheNewNameIsNotTheRenamedFolder` RED at SpecialFolderRenamerTests.swift:894, `XCTAssertEqual failed: ("["Ideas"]") is not equal to ("[]") - a link was named as the renamed folder`; reverted. `1055-M7-mustfail.log`.

## Runs (through xlock.sh, one class list each)

The same eleven classes on the base and after: UndoRenameFolderStepTests, SpecialFolderRenamerTests, UndoMakeRoomLinkedPageTests, MakeRoomForClassesTests, DuplicateAsNextClassTests, RestoreDuringAFolderRenameTests, UndoStoppedStepTests, FolderPathRewriterTests, UndoJournalContractTests, UndoWriterScanTests, SectionVerbsTests.

- Base (cd27c181a): 227 passed, 0 failures. UndoRenameFolderStepTests 54, SpecialFolderRenamerTests 51, UndoMakeRoomLinkedPageTests 4, MakeRoomForClassesTests 9, DuplicateAsNextClassTests 19, RestoreDuringAFolderRenameTests 8, UndoStoppedStepTests 21, FolderPathRewriterTests 27, UndoJournalContractTests 19, UndoWriterScanTests 6, SectionVerbsTests 9. (A first base run raced my edits and failed to link; re-run on a stash, green.)
- After: 222 passed, 0 failures: UndoRenameFolderStepTests 52 (-2), UndoMakeRoomLinkedPageTests 1 (-3), the rest unchanged (SpecialFolderRenamerTests 51: renamed, not removed).
- Plain Debug build: succeeded.
- `origin/dev` merged before proving and before hand-back: up to date both times (no merge commit); M6's head unmoved at cd27c181a.

## Lows

Neither carried: S2 review 1's `contracts/shared-rules.json` sentences and M5 review 1 LOW 1 (`UndoKeptPageUnderAVisibleNameTests.swift`) are in files this piece does not touch (and `contracts/` is out of this piece's scope).

## Self-check

- Broke each change and watched a test fail: the one behaviour this leaves pinned (a link at the new name is never this rename's folder) was mutated and went RED; the rest are deletions of dead code and tests, proved by the plain tests passing unchanged before and after.
- Every sentence on the failure paths true: no product sentence or failure path changed; the general guard's comment is unchanged.
- Dev merged in: yes, up to date both times.
- Contract cases run from the JSON: UndoJournalContractTests (19) green; no contract touched.

## For the director

No parked questions.
