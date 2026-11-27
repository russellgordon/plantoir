# #1055 M4: the door has no relinking move

Branch `issue/1055-M4-no-relinking-move`, stacked on M3's pushed head e6fd13c41. Touches `contracts/`: both gates (the director's). Merge window 2 with M3, M5 and M6.

## For PROGRESS

- Mac #1055 M4 (2026-11-27): the door knows no relinking move again. A `move` carrying `linkShaBefore`/`linkShaAfter` is `notReadable` (a barrier, never acted on, never a reason to clear), as before U4b3 relink-2. U4b3 relink-1 to -4 and the review D-E and review F fixes reversed hunk by hunk; every other commit's hunks in the same files kept. No teacher-visible wording changed.

## What was removed (each from the commit that added it)

- `UndoCheck.swift`: `UndoRelinkOutcome`, `UndoRelink`, a target's `relink`, `linkHolds`, `makeALink`, `removeALink`, `UndoStepLinks`, `UndoStepRelink`, the relink branch of the swap (6302984b3, 969a9ae99).
- `UndoFormat.swift`: `linkShaBefore`/`linkShaAfter` and their `CodingKeys`, `isARelink`, `linkText(isAtFrom:)`, the relink blob check, `relinkShapeIsKnown`, `UndoOp.relinkLink` (6302984b3, c5beb855a). Also `UndoOp.isALinksMove`, relink-1's helper: its callers read `linkSha != nil` again, as at 6302984b3^ (see "For the director").
- `UndoOpKinds.swift`: the `linkText` read (6302984b3).
- `JournaledWrite.swift`: the `relinkStaged`/`relinkRenamedIn` stop points and `relinkRenameInFails` (6302984b3, 969a9ae99).
- `UndoRecovery.swift`: `removeTheLinksJustMade` (its last part taken out by hand after the reversal), `isTheOneInFlight`, their call, the relink parts of `links(of:root:)` (969a9ae99, 03033c410, bf56a3c35, c5bb58f32).
- `JournaledStep.swift`: `relinkLink`, the `PlannedFolderMove` alias with `textBefore`/`textAfter`, `isALinksMove(_:)`, `isARelink(_:)`, `blobs(of:)`, `relinkGoingForward`, `isARelink(endingAt:)`, the relink blobs, the relink clause of `refusesAWrite` and the planned-move tuple back to 6302984b3^'s, M1's "(no teacher action does so now; #1055 M6 removes it)" comment kept (0a9cb7924).
- Tests: `UndoRelinkTests.swift` whole (M3's test 3, the case-and-normalisation one, moved first into `JournaledStepTests.swift`, its body byte for byte, with a scratch parent made in the test because that class has no `parent`); relink-4's six tests and their helpers `RelinkLeads`, `relinkTexts`, `outsideFolderOf`, `timesUnder`, `standsAnything` from `JournaledStepTests.swift` (`workingFolder` and `everythingUnder` kept, the M4 tests use them); `UndoContractReplay.swift` and `UndoContractReplayKinds.swift`: the relink stops, `withARelink` and its shapes, `linkTargetBefore`/`linkTargetAfter`; `UndoJournalContractTests` recovery count 85 to 72; `UndoWriterScanTests` `UndoCheck.swift` 19 to 17, with 6302984b3^'s sentence.
- `shared-rules.json`: 9 checkCases "U4b3 relink, …" rows; 7 "U4b3 relink-3 …", 3 "Review D of U4b3 …", 3 "Review F of U4b3 …" recoveryCases rows; `undo.rule.recovery`'s relinking-move passage ("A relinking move's swap (opKinds.move) killed …" to "… may be the teacher's."); `checkCasesHow`'s `linkTargetBefore`/`linkTargetAfter` clause and relink-2's "a link, read with lstat and readlink, which never ask its own permissions, by its folder's taken away" clause; `recoveryCasesHow` from "U4b3 relink-3: withARelink …" to its end. `stagedThenSwapped` held no relink clause on M3's head.
- `file-formats.json`: `opKinds.move`'s `linkShaBefore?, linkShaAfter?` keys, "or, for a relinking move, the pair …", "or else the pair … and none of those three", the whole "A link's move may change the text the link holds (U4b3 relink) …" passage to "Beyond a relinking move's two texts," (back to "The moved content is never a blob"); `wholeOps`' "or linkShaBefore and linkShaAfter". The plain link's move (`linkSha`) sentences stay. Compared word by word with 6302984b3^: the only differences left are M2's and mac-1's.
- Python: `make_undo_traces.py` back to 6302984b3^ but for mac-1's NFC comparison and kept-original-named (`visible_name`, `keep_pages_whose_place_is_taken`); `remove_the_links_just_made` and `stopped_part_way`'s relink branch gone. `test_make_undo_traces.py`: the relink model tests and the 101-kill table gone. `python3 scripts/test_make_undo_traces.py`: 39 tests OK (42 on M3's head); not stale, nothing regenerated.
- Notes kept, each with the top line "Removed by #1055 (2026-11-27): …": relink-1, -2, -3, -4, review D-E, review F.

Method: in a scratch worktree, each of the nine commits' Mac, contract and script hunks reverse-applied newest first (`git apply -R --3way`); every conflict kept the current text, and the relink parts inside it were then removed by hand; the JSON rows removed by name by script. A first try that took the reversed side of conflicts dropped later hunks (kept-original-named rows and sentences) and was thrown away.

## Kept (confirmed by grep in `mac-app/QuartzTeachers`)

`keepPagesWhosePlaceIsTaken` 3, `placeFilled` 6, `placeLeft` 6, `visibleName` 2, `keepUnderAVisibleName` 2, `renameToAVisibleName` 3, `undoKeptAPageUnderAVisibleName` 2, `UndoHandover` 9, `handovers(in:` 7, `isHandedOver` 2, `handsOverAsAMove` 6, `func moveLink` 2, `linkSha(at:` 2, `linkTarget(at:` 2. Rows: "move of a link" 4, "U4b3 door" 15, "createTree: a link inside the folder" 1, "move: a link where the moved copy is" 1.

## Row-count script

```text wrap
checkCases 147 -> 138 ; the kept rows in order and byte for byte the same: True
recoveryCases 85 -> 72 ; the kept rows in order and byte for byte the same: True
changed: /undo/rule/recovery
changed: /undo/checkCasesHow
changed: /undo/recoveryCasesHow
```

## Windows edit (the only Windows code file edited: `windows-app/Plantoir.Tests/UndoCheckContractTests.cs`)

The theory `ARelinkBarrierRowIsNotReadableForTheReasonItsNameGives` removed whole: its `/// <summary>` comment, `[Theory]`, both `[InlineData]` lines and the body to its closing brace, plus the blank line after it (31 whole lines; no line edited). Read back: the method before (`… flag.GetBoolean();` then `    }`) ends with its brace, one blank line, then `/// <summary>Every case held open by name …` of the next member. `JsonNode`, `JsonArray`, `JsonObject` and `CaseNamed` are still used elsewhere in the file. Nothing else references the method (`git grep` finds only W8b-21b2's notes).

- No `NamedGapLedger.cs` row names a removed row. `git grep "U4b3 relink\|Review D of U4b3\|Review F of U4b3" -- windows-app/Plantoir.Tests` still finds comments only: `NamedGapLedger.cs` 677, `UndoCheckContractTests.cs` 110 (the `OpOf` branch), `UndoRecoveryContractTests.cs` 42 and 153, `UndoRelinkTests.cs`: W2's.
- `UndoRecoveryContractTests` keeps `withARelink` in `KeysChecked` and its shapes; `UndoCheckContractTests.OpOf`'s `linkTargetBefore`/`linkTargetAfter` branch: unreached, never red; W2 removes them.
- Floors hold: checkCases 138 (at least 30), recoveryCases 72 (at least 41). The Windows suite stays at its six known failures.

## For documentation 12

Windows' relink (`UndoSwap.RelinkLink` and friends, the relink recovery, `UndoActionStep`'s relink) is dead until W2: no contract row reaches it, and the Mac reads the shape `notReadable`.

## Runs

- Tests first on M3's head e6fd13c41 (`run-red3.log`, 14:09): test 1 (`testALinksMoveThatChangesItsTextIsAShapeThisVersionCannotRead`) and test 2 (`testAStepLeftPartWayHoldingARelinkIsABarrierNotRecovered`) failed; tests 3 and 4 passed. Lines in `1055-M4-mustfail.log`. Two earlier runs were not red: the op lacked its `blobs` (so it was unreadable on the base too), and the begin line had no gone process (so recovery did not take it up); both fixed in the test before the red run.
- Test 2 lays the moment after the new link is renamed in (both links standing), the smallest relink-3 point where M3's head removes something; at the staged-name moment alone the base removes no link.
- Green after the removal (14:15, one run through `xlock.sh`): `JournaledStepTests`, `UndoJournalContractTests`, `UndoFilesContractTests`, `UndoWriterScanTests`, `UndoHandedOverPlaceTests` (it holds the kept-page tests), `UndoStoppedStepTests`, `UndoOpKindsTests`, `UndoDoorGuardTests`, `UndoSweepFindingsTests`, `SharedRulesContractTests`, `FileFormatsContractTests`: 266 tests, 0 failures. Then a plain Debug build: BUILD SUCCEEDED. Python model: 39 tests OK.
- `origin/dev` (99499d6b7) is already in the branch and M3's head had not moved at hand-back: no merge commit.

## COMMON's self-check

- Switch off; nothing offered; no UI class, never the app; every `xcodebuild` through `xlock.sh` with the 15-minute kill; one class list per run.
- House style over my Swift lines: no `map`/`filter`/`reduce`, no `$0`, no GCD, no timed waits, explicit types; MARK sections `#1055 M4` and `Helpers (#1055 M4)`.
- No teacher-visible wording changed; no new handling or edge case.
- The rename record kept; no `rm` with a wildcard; nothing committed in `vm-tools`.

## For the director

- The brief's empty-grep for `linkShaBefore\|linkShaAfter` over `mac-app` finds only test 1's own JSON keys and comment in `JournaledStepTests.swift` (the test must write the pair to prove it unreadable).
- `isALinksMove` is on the keep list, but it was relink-1's helper (absent at 6302984b3^); reversing relink-1 and -4 took both (`UndoOp.isALinksMove`, `JournaledStep.isALinksMove(_:)`), their callers back to `linkSha != nil`. The plain link's move is judged as today (test 3 green). Put back if M6 wants the name.
- `JournaledStep.markdownFiles`' comment (review E, 4af7595af) still says "a link the step moves or re-points" and "writing at a re-pointed link's new name is refused": stale, not a relink commit's hunk, left alone.
