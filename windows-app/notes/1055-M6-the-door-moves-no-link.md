# #1055 M6: the door moves no link as itself; the write-through stays

Branch `issue/1055-M6-the-door-moves-no-link`, from `origin/day27c/integration-1` (cc4ee3ab5: `origin/dev` plus M5). `origin/dev` merged in before proving and again before hand-back: "Already up to date" both times (it holds nothing past the base). M5's head is the base itself.

Settled by the director before the start (Russell's rule, last comment on #1055): question 1 (Insert Class past a linked later class) is left as each platform does it; question 2 (Rename Folder of a linked folder) gets no link move, the general guard stands.

## Commits

- `9e59d50db` test first: `JournaledStepTests.testALineCarryingALinksMoveIsAShapeThisVersionCannotRead` (replaces `testAPlainLinksMoveIsStillJudgedAsToday`, which pinned the opposite). RED on M5's head, lines in `1055-M6-mustfail.log`.
- `6717b27d3` the removal (product, tests, contract, Python, Windows tests), one commit so no commit has the Swift replay reading contract rows whose calls are gone.
- this notes file.

## Removed

- `JournaledStep.swift`: `moveLink`; `folderMoveOp`'s link branch (returns `UndoOp.moveFolder` only); the `linkSha` member of `plannedFolderMoves` (now `(from, to, listingSha: String)`) and its comment ("… #1055 M6 removes it"); `recordableFolderMoves`' link naming branch; `plannedLinkMove(endingAt:)`, `plannedLinkMove(startingAt:)`, `staysInItsFolder`, `refusesAWrite` and `refusedBeforeMaking` (their only trigger was a planned link move; this takes the "does not yet judge" comment, M5 review LOW 2, with it), and their calls in `make()`, `write(_:to:plannedFrom:)` and `plan`; the link-move branch at the top of `placeALinkLeadsTo`. `plan` and `placeALinkLeadsTo` now read byte for byte as at `35cc5ba87` (checked by `diff`).
- `UndoFormat.swift`: `linkSha`, its `CodingKeys` entry, decode and encode; `UndoOp.moveLink`; the `linkSha` blob check; the move shape back to "exactly one of `sha` and `listingSha`" (so a line carrying `linkSha` is unreadable, test 1); `moveCarries`' link branch.
- `UndoOpKinds.swift`: `UndoMoveSide.readLink`; `readNamingFoldersLeftOut`' link branch; the link branch of `UndoPlaces.staysInside(_:_:namedBy:)` (the function KEPT, as the brief says, now delegating to `staysInside(_:_:)` for every place).
- `UndoCheck.swift`: `op.linkSha == nil,` in the swap's own-files lookup. `isALinksMove` and `stateWhereTheLinkStands` were already gone (grep empty on the base); `UndoRecovery.swift` held nothing of the link move.
- Tests: `JournaledStepTests`' two MARK sections "a write after a link's move (U4b3)" and "a place a link's move leaves (U4b3)" (three tests and `linkedDay3`); `UndoOpKindsTests.testALinkItemIsReadWithoutFollowingIt` (it builds `UndoOp.moveLink`; not the listing's); `UndoContractReplayKinds`' `moveALinkToAFolder`, `stepEditingInsideALinksMove`, their constants and `linkedFolder(in:)`; `UndoContractReplay`'s `linkTarget` -> `linkSha` translation, the `linkedFolder` key and its check; `UndoRenameFolderStepTests`' ` link` suffix on an op line (read `op.linkSha`). Counts in `UndoJournalContractTests` and `UndoWriterScanTests` did not move (no counted writing call removed).
- `shared-rules.json`: 4 check rows, 3 stack rows, `stackCasesHow`'s U4b2-14 sentences (`moveALinkToAFolder`, `linkedFolder`, `stepEditingInsideALinksMove`), `checkCasesHow`'s two link-move clauses (`linkTarget`; "a link's move resolves only the folders above its link"), the `undo.rule.shadow` span. `knownLimits.linkBetweenTheCheckAndTheChange` and `laterPieces`: read, no clause names a link's move, unchanged. The sweep's `activityTrail` `carries` clause already read "nothing could be written beside it" on the base.
- `file-formats.json`: `opKinds.move`'s link sentences; it now says the door moves no link as itself and a move with another content key (an older build's `linkSha`) is unreadable. `createTree`'s "never followed" untouched. `contracts/README.md`: no line named a link's move.
- Python: `move_state`'s and `move_carries`' `linkSha` branches; the test's `linkSha` shape key, `linkTarget` translation, `moveALinkToAFolder`, `stepEditingInsideALinksMove`, `LINK_*`, `linked_folder`. KEPT: the model's generic `("link", sha)` reading of a link at a place (U4b2-2's rows and tree `links` use it). `python3 scripts/test_make_undo_traces.py`: 38 tests OK, traces not stale, nothing regenerated.
- `899-u4b2-14-a-moved-link-is-judged-by-its-bytes.md` gains the top line. U4b2-1's notes untouched.

## Kept (grep on the head, counts across `mac-app` and `contracts`)

`placeALinkLeadsTo` 8, `throughALink` 5, `fileALinkLeadsTo` 5, `testEveryWayOfPlanningAndReadingFollowsALink` 1, `testASettingsFileThatIsALinkIsSavedThroughTheLinkWithTheSwitchOff` 1, `keepPagesWhosePlaceIsTaken` 3, `placeLeavingTheFolder` 7, `staysInside(…, namedBy op:)` 1, `func linkTarget(at:` 1, `func linkSha(at:` 1 (called by the folder listing, `UndoOpKinds.swift` 967), "createTree: a link inside the folder" 1, "move: a link where the moved copy is" 1, six U4b2-2 rows; `undo.rule.shadow` still holds "One rule on both platforms", "written through too", "Recording still differs". The swap's "never through a link" listing guard (`UndoCheck.swift`, review 1 of U4b2-14) is a general guard and stays.

## LOW M2-1's three comments

- `JournaledStep.plannedFolderMoves`' "#1055 M6 removes it": gone with the member.
- `JournaledStep.moveLink`'s "#1055 M6 removes it": gone with `moveLink`.
- `UndoTreeReading.linkSha(at:)`: kept (folder listings call it), rewritten: "The SHA-256 of the bytes a link holds (`linkTarget`), never followed: what a folder's listing lists a link inside it by (its `link` line). Nil when it cannot be read."

## Script output

Rows and `rule.shadow` (scratchpad `check_rows.py`, before copy against the head):

```text wrap
checkCases 138 -> 134 down by 4 expected 4 others identical and in order: True
stackCases 126 -> 123 down by 3 expected 3 others identical and in order: True
no check op carries linkTarget*; no stack row calls the four link calls
floors: checkCases True stackCases True
once: True never follows the link and is refused before anyth
once: True saving a plain copy at the new name and deleting t
once: True held by name in UndoMakeRoomStepTests.ALinkedLater
absent: True not supported
absent: True #1055's W1
absent: True handed over
kept: True One rule on both platforms
kept: True written through too
kept: True Recording still differs
before span unchanged: True  after span unchanged: True
```

Done-means greps: `func moveLink|.moveLink(|isALinksMove|moveALinkToAFolder|stepEditingInsideALinksMove|M6 removes` in `mac-app/QuartzTeachers mac-app/Tests scripts contracts`: empty. `"move of a link|U4b2-14, ` in `contracts`: empty. `linkedFolder` in `contracts`: empty; in `mac-app/Tests` only `UndoDoorGuardTests`' local `linkedFolder` (the leads-out guard's), allowed.

## Windows (edited by reading; not compiled)

- `UndoCheckContractTests.cs`: `EveryLinkMoveCheckCase` deleted (summary, `[SymbolicLinkTheory]`, `[MemberData(nameof(LinkMoveCases))]`, the method). `LinkMoveCases()` left for W4 (now 0 rows).
- `UndoStackContractTests.cs`: `EveryLinkStackCase` deleted the same way. `LinkCases()` stays (0 rows; read by the count and `StillNamed`).
- `UndoMakeRoomStepTests.cs`: the doc sentence now "The two platforms differ here by Russell's rule on #1055 (no link code beyond reading and writing through a link); this test holds the difference by name" (rewrapped over three `///` lines); `settle` reads "settle it (#1055)". Its three substrings are in the new clause (script above).
- Read back: every edited line, `///` prefixes, attributes and braces intact. `NamedGapLedger.cs` names no removed row (grep empty). `case "moveALinkToAFolder"` (651) and `case "renameAPerSectionFolderThatIsALink"` (658) in `UndoStackContractTests.cs` are unreached (no row calls them; W4 removes them). `[SymbolicLinkTheory]` still has 17 users. The Windows suite is expected to stay at its six known failures (not run here).

### For documentation 12

Windows still moves a linked folder as a link until W4, and writes a linked page through without the list (the switch off), which is the contract's "Recording still differs" sentence, U7's.

## Runs (all through `xlock.sh`, 15-minute kill)

- `run-base` on M5's head with test 1 added: test 1 RED (3 failures: `XCTAssertFalse failed - a link's move is read`; Undo `undone(seq: 1 …)` not `notAvailable`; Redo `redone(seq: 1 …)`). Test 2's classes green: `UndoSweepFindingsTests` 18, `UndoCourseSettingsStepTests` 18, `UndoDoorGuardTests` 19, `UndoOpKindsTests` 40 (807, 823, 845, 862 among them), `UndoJournalContractTests` 13 (it replays the two named check rows), `UndoRenameFolderStepTests.testAFolderHoldingASymbolicLinkIsRenamedWithTheLinkMovedAsALink` 1.
- `run-after` on the head: 16 classes, 364 tests, 0 failures: `JournaledStepTests`, `UndoSweepFindingsTests`, `UndoCourseSettingsStepTests`, `UndoOpKindsTests`, `UndoDoorGuardTests`, `UndoRenameFolderStepTests` (whole; the link-inside-a-folder test needed no `moveLink`), `SpecialFolderRenamerTests`, `UndoMakeRoomLinkedPageTests`, `DuplicateAsNextClassTests`, `UndoKeptPageUnderAVisibleNameTests` (M5's four guard tests), `UndoJournalContractTests`, `UndoFilesContractTests`, `UndoWriterScanTests`, `UndoStoppedStepTests`, `SharedRulesContractTests`, `FileFormatsContractTests`. `UndoOpKindsContractTests` was named in the order but no such class exists (`-only-testing` ran nothing for it).
- Plain Debug build (`-derivedDataPath ../.dd`): succeeded.
- `python3 scripts/test_make_undo_traces.py`: 38 OK.

## Self-check (COMMON), item by item

1. Broke each change and watched a test fail: the one behaviour change (a line carrying `linkSha` is unreadable) was seen RED on the base, which is the change broken; the removals are deletions of code no teacher action reaches (shown by every named class green after). No mutant committed.
2. Every sentence on the failure paths true: the new `undo.rule.shadow` clause is the brief's text verbatim; `opKinds.move`'s new sentence matches `shapeIsKnown` (exactly one of `sha` and `listingSha`) and test 1; no refusal sentence was added or changed.
3. Dev merged in: yes, twice, "Already up to date".
4. No number tuned by trial: none introduced.
5. Contract cases run from the JSON: yes, the replays read `shared-rules.json`; no row retyped.
6. House rules: no `map`/`filter`/`reduce`, no `$0`, no GCD, no timed waits in anything written; the switch stays off; nothing a teacher sees changes.

## Parked

None.
