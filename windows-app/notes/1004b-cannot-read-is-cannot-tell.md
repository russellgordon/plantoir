# #1004-b: what cannot be read is cannot tell (Mac Undo, #899)

Branch `issue/1004b-cannot-read-is-cannot-tell`. **Base: part a's pushed head `b3e298caa`** (`origin/issue/1004a-journal-files-judged-by-what-was-read`), not `origin/dev`: `-a` was not merged when this started, and the director ran the two side by side, so this branch is built on `-a` rather than merging it in (both add to `shared-rules.json`; there is nothing to conflict). `origin/dev` (`0e12bc8ac`) was already inside `b3e298caa` when proving began (no merge needed then); before hand-back `dev` had moved to `253f8915f` (#909) and was merged in: merge commit `682ed6dc8`, clean, then the six classes and the Python re-run green (see "Runs").

## For PROGRESS

- Mac #1004-b (2026-11-26): `UndoWebsite.readRecord(courseFolder:section:)` returns `[Fragment]?`: nil for a published-pages folder that is there and cannot be listed (listed with `UndoJournal.namesListed(in:)`, part a's `opendir`/`errno` reader: only `ENOENT`/`ENOTDIR` is not there), `[]` only for one that is not there. `UndoWebsite.answer(record:)` takes `[Fragment]?`; nil is cannot tell for a section that deploys anywhere now, no offer for one that deploys nowhere, exactly as Windows' `Answer` reads a null record. `readRecord` still has no caller (U6). Three agreements pinned by rows that passed on the base: `.MD` in any case, ASCII digits only (fragment stamp and segment number), an unreadable `madeAt` carrying the step before's time.
- Contract: `shared-rules.json` → `undo.rule.deployed` (one clause added to its CANNOT TELL list), `undo.deployedCasesHow` (`recordListed`), `undo.deployedCases` +3 (18 → 21: unlistable, `.MD`, fragment digits), `undo.stackCasesHow` (calls `aSegmentNamedWithOtherDigits`, `stepWithAMadeAtThatIsNotAMoment`), `undo.stackCases` +2; `file-formats.json` → `undoJournal.files["journal-NNNNNN.jsonl"]` "six ASCII digits (0 to 9; a name with any other digit is not a segment)". Held on Windows: 2 more `stackCases` rows under `Reason1004JournalReading` (text extended). `UndoWebsiteContractTests.cs` changed, test code only.

## For documentation 12

What Windows must do, without the Swift:

1. **Segment names: ASCII digits only.** `windows-app/Plantoir.Core/Undo/UndoJournal.cs` line 57: `new(@"^journal-(\d{6})\.jsonl$", RegexOptions.CultureInvariant)`. .NET's `\d` matches any Unicode decimal digit (Arabic-Indic U+0660 to U+0669 included), so `journal-٠٠٠٠٠٢.jsonl` matches and `int.Parse` (line ~404's caller) then meets it. Change to `^journal-([0-9]{6})\.jsonl$` (or add `RegexOptions.ECMAScript`). The fragment pattern (`UndoWebsite.cs` line 64) already says `[0-9]`.
2. **Replay call `aSegmentNamedWithOtherDigits`** (`UndoStackContractTests.cs`, the call dispatch, beside `stepFromAnotherVersion:`, about line 483): write, in the list's folder, a file named `journal-` + U+0660 ×5 + U+0662 + `.jsonl`, holding a begin line and an applied line of the NEXT step number, the begin exactly as `StepFromAnotherVersion` writes it for a flip of p1 with no variant's change, and do NOT change p1. Row: `["step", "aSegmentNamedWithOtherDigits", "undo"]` → `undone`, head null, redo 1, onTheList [1]. With today's `\d` the file is segment 2, its step 2 is read, the undo meets p1 not holding step 2's after and is refused (changedSince), so the row is red on Windows until item 1 lands.
3. **Replay call `stepWithAMadeAtThatIsNotAMoment`**: `StepFromAnotherVersion` with no variant and the step's `madeAt` written as `"yesterday"` (begin raw, p1 flipped, applied). Row: `["step", "stepWithAMadeAtThatIsNotAMoment", "undo"]` → `notAvailable`, head 2, redo null, onTheList [1, 2], onTheDisk [1, 2], physicallyPruned []. Windows already behaves (`UndoFormat.cs` about 420 to 423 makes the step unreadable; `UndoOffer.StepTimes`, `UndoOffer.cs` about 56 to 80, carries the step before's time); only the call is missing.
4. Then drop both names from `Reason1004JournalReading` in `NamedGapLedger.cs` (and the reason, once the `-a` row's call lands too).
5. **No `deployedCases` row was left out.** Why each new row passes on Windows (the Windows gate is the proof; this Mac cannot build it):
   - *"a published-pages folder that is there and cannot be listed"* (`record: []`, `recordListed: false`, destinations [netlify], no marker → `cannotTell`): `EveryDeployedCase` now passes a null record when `recordListed` is false; `UndoWebsite.Answer` (UndoWebsite.cs ~110 to 117) with `newest is null` sets `deployedSomewhere` and `cannotTell` for every distinct destination, so one destination gives `CannotTell`. `EveryDeployedCaseThroughARealCourseFolder` passes the `listFiles` seam `_ => throw new UnauthorizedAccessException(...)` for that row; `Inputs` (~258 to 270) sees `Directory.Exists(folder)` true (`CourseFor` always creates it), calls the seam, catches the exception and returns a null record: same answer. The seam assertion on destinations and markers is unchanged ([netlify], []).
   - *"a page whose name ends .MD"* → `offerToDeploy`: `PlaceOf` (~192) uses `EndsWith(".md", OrdinalIgnoreCase)` and keeps the name before the last three characters, so `.../Day 1.MD` is `Section 1/Classes/Day 1`, shown by the newest fragment, visible before: offer. The existing `Proposed_APageWhoseNameEndsInUpperCaseMdIsAPageAsOnTheMac` already asserts the place.
   - *"a file whose moment is written in digits that are not ASCII"* → `noOffer`: `FragmentName` (~64) is `^([0-9]{8}T[0-9]{6}Z)-(.+)\.json$`, so the name does not match, `NewestFragments` skips it, netlify has no fragment and no marker: `deployedSomewhere` false, `NoOffer`. Through the real folder: NTFS holds the name; `Inputs` lists it, `NewestFragments` drops it, same answer.

## Must-fail lines

All in `windows-app/notes/1004b-mustfail.log`. Swift: 5 RED of 5 (run logs `run-M1.log` … `run-M4.log`, `run-M1b.log`).

- M1, `readRecord` back to `try? contentsOfDirectory` → `[]`: `UndoJournalCoreTests.swift:146 testAPublishedPagesFolderThatCannotBeListedIsNotNoFragments`: `XCTAssertNil failed: "[]"`.
- M1b, `answer` reading a nil record as `[]` (the base's answer): `UndoJournalContractTests.swift:127 testDeployedCases`: "deployedCases '#1004-b: a published-pages folder that is there and cannot be listed …': noOffer, not cannotTell".
- M2, `.md` matched case-sensitively: `UndoJournalContractTests.swift:127 testDeployedCases`: "'#1004-b: a page whose name ends .MD …': a move this replay cannot read" (and its answer).
- M3, `segmentNumber(inName:)` taking any `isNumber` character by `wholeNumberValue`: `UndoContractReplay.swift:1353` in `testStackCases`: `caught error: "couldNotRead"` (the odd file read as segment 2 beside segment 1 breaks the read). Red, though as a thrown error rather than the row's own message.
- M4, `effectiveTimes` giving a step with no readable `madeAt` `Date.distantPast`: `UndoJournalContractTests.swift:118 testStackCases`: "'#1004-b: a step whose madeAt is not a moment …': head nil" (and its list).

Red first: on the base behaviour (the new signature with `readRecord`'s old body, `try?` → `[]`, i.e. M1's state; run `run-base.log`), `testAPublishedPagesFolderThatCannotBeListedIsNotNoFragments` failed (`UndoJournalCoreTests.swift:146: XCTAssertNil failed: "[]"`). The unlistable `deployedCases` row cannot be run against the base's `answer`, which took no nil (it would not compile); M1b is that base, `nil` read as `[]`, and the row answers `noOffer` there. The `.MD`, digits and `madeAt` rows and `testAPublishedPagesFolderThatIsNotThereIsNoFragments` passed on the base, as the brief expects (they pin agreement); M2, M3 and M4 make each real.

Python (M5), each in place and restored with `git checkout` (`git status` clean after):
- M5a, `FRAGMENT` back to `\d`: `test_deployed_cases` on "#1004-b: a file whose moment is written in digits that are not ASCII is not a fragment": `'offerToDeploy' != 'noOffer'`. (Python's `\d` matched Arabic-Indic digits: the model was wrong before this piece; fixed to `[0-9]`.)
- M5b, `recordListed` ignored: `test_deployed_cases` on the unlistable row: `'noOffer' != 'cannotTell'`.
- M5c, `effective_times` giving a step with no time the oldest moment instead of carrying: `test_stack_cases` on the `madeAt` row: `None != 2`. (A first try that set the step's own time to minus infinity stayed green: a step's time is the latest so far, so an oldest moment is carried over anyway. Same on the Mac, which is why M4 sabotages `effectiveTimes`' result rather than `madeAt`.)
- `aSegmentNamedWithOtherDigits` is modelled as a call that changes nothing (the model has no segments; the rule is that such a file is not one), so it has no Python sabotage.

## Runs

All through `xlock.sh`, 15-minute kill, logs in `/Users/russellgordon/plantoir/wt-1004b/.dd/`.

- `run-base.log`: UndoJournalContractTests + UndoJournalCoreTests on the base behaviour: 37 tests, 1 failure (the unit test above), exit 65.
- `run-green.log`: UndoJournalContractTests, UndoJournalCoreTests, UndoFilesContractTests, FileFormatsContractTests, SharedRulesContractTests, UndoWriterScanTests: 124 tests, 0 failures. (`UndoShadowPublishTests` dropped: it does not read `UndoWebsite`.)
- `run-M1.log` … `run-M4.log`, `run-M1b.log`: the must-fail runs.
- `run-doc09.log`: every class that reads documentation 09 as text (AboutWindowLinksTests, AlertKeysTests, CloudSyncNoticeLayoutTests, CourseSettingsTeardownTests, ListTableGoldenTests, ProgressViewSizeTests, SharedRulesContractTests, TickTableTests, UnsavedSettingsNoticeLayoutTests, UpdateRemindersTests, WorkingFolderSelectionTests, DetailTabsLayoutTests, TodaysClassOnTheFrontPageTests): 162 tests, 0 failures, exit 0.
- `run-aftermerge.log`: after merging `origin/dev` 253f8915f (merge `682ed6dc8`), the same six classes as `run-green.log`: 124 tests, 0 failures; Python 36 OK; held names re-checked byte for byte.
- `python3 scripts/test_make_undo_traces.py`: 36 tests OK; it did not say the traces were stale (the model change touches only steps with no time, which no trace makes), so `make_undo_traces.py` was not re-run.

## Left for the next piece

- `UndoWebsite.siteMarkers(courseFolder:section:among:)` (`UndoWebsite.swift` about 243 to 258) asks `FileManager.default.fileExists(atPath:)`, so a site marker that cannot be looked at (its folder not searchable) reads as absent; Windows' `File.Exists` (`UndoWebsite.cs` `Inputs`, about 249) is the same. With no fragment, an unreadable marker turns cannot tell into no offer. Same family as gap 3; not changed here, per the brief.

## For the director

- **A `windows` issue is owed** for #1004's Windows half: none exists (`gh issue list -R russellgordon/plantoir --milestone v2.0.0 --search "1004"` shows only #1004 and #899). It should carry "For documentation 12" items 1 to 4 here and part a's replay call `newestSegmentGoesWhileRead`.
- `windows-app/Plantoir.Tests/UndoWebsiteContractTests.cs` changed (test code only: `RecordListed(c)`, a null record in the pure walk, the listing seam in the real-folder walk). Only the Windows gate proves it.
- No parked questions.

## Self-check

1. **Broke each fix and watched its test fail.** M1, M1b, M2, M3, M4 (Swift) and M5a to M5c (Python), each in place, run, failing line named above and in the log, restored with `git checkout` (status clean).
2. **No timed waits.** None added; the `chmod 000` test is synchronous and its folder's mode is given back in `tearDown` even when the test fails.
3. **Every sentence on the failure paths is true.** Nothing a teacher sees changes (the switch is off, `readRecord` has no caller). The contract's sentences (`rule.deployed`, `deployedCasesHow`, `stackCasesHow`, `files`) were checked against what the Mac and Windows code do; the enum's doc comment and documentation 09 say the same.
4. **`dev` merged in before proving**: `origin/dev` 0e12bc8ac was an ancestor of the base `b3e298caa` before proving (nothing to merge); before hand-back `origin/dev` 253f8915f was merged in, `682ed6dc8`, and the classes re-run green.
5. **No number tuned by trial.** None.
6. **House style and contracts.** Contract cases run from the JSON on both platforms (the Mac's replay reads `recordListed` and both calls; Windows' walkers read `recordListed`); nothing changed outside the brief's list.
7. **House style grep** (`DispatchQueue|\.map {|\.filter {|\.reduce(|\$0`) over the changed Swift lines: empty. MARK sections: `UndoJournalCoreTests` gained `Computed properties` and `Functions`.
8. **Riding lows**: none named in the brief.
9. **The rename record is still kept; the switch is still off.** Neither touched.
10. **Every new or changed contract row is in the Mac's replay** (`runDeployedCases`, the stack runner's two calls) **and, where Windows cannot run it, held by exact name** (the two `stackCases` rows; checked by script, byte for byte). The three `deployedCases` rows are not held (that test consults no ledger): each passes on Windows by the reasoning in "For documentation 12", item 5.
