# #899 W6: the Mac's U2b op kinds, on Windows

Notes for the director to fold into `windows-app/PROGRESS.md` and
`documentation/12-windows-app.md` at the merge window (NIGHT3-COMMON: writers
do not edit either file). Plan: `vm-tools/reference/899-w6-plan.md`.

## For PROGRESS

## 2026-11-20 — Undo and Redo, W6: the six op kinds U2b defines (#899, #949)

Branch `issue/899-w6-op-kinds` (on W4 with its review fixes, `dev` 2ba8490e7 in it). Lenovo 20QES70500 (i5-8365U, 16 GB, Windows 11 Pro 26200) over SSH. Nothing a teacher sees changed; the switch stays off; no action goes through the door yet (W7 on).

- Reader (`UndoFormat`): `replaceText`, `editJSON`, `move`, `createTree`, `removeTree`, `external` read with the mac's shapes (`shapeIsKnown`), `opKinds.wholeOps` on the step, places compared without case, `element` and `heldBy` unreadable, a listing's hash among the blobs kept, a step of external ops alone needs no working folder.
- `UndoJson.cs` (any JSON, compared as the contract says, exactness beyond 2^53, the compact spelling), `UndoOpKinds.cs` (`UndoHunk`, `UndoJsonMember` with its byte scanner, `UndoTreeListing`/`UndoTreeReading`, `UndoLinks`, move sides, `IUndoExternalPlaces` and the app's `UndoAppSettingsPlaces`).
- Check, plan, swap and recovery for each kind (`UndoCheck.WholeStateOf`, `UndoSwapChange`, `UndoSwap.SwapAWholeOp`, `TidyLeftovers` putting a folder set aside back or keeping it as `<name> (kept by Undo)`, `-gone` before a delete, `UndoRecovery.FoldersKeptAside`, the `undo found a folder set aside` trail line).
- Contract from the JSON: all 110 `checkCases` (move sides, trees, links, preferences placed on the disk), the 5 `listingCases` and 16 `editJSONCases` (new, `UndoOpKindsContractTests`; 8 added by the fix round), U2's 19 `stackCases`, the 15 traces holding a `move`, U2's 21 `recoveryCases`. Every W6 entry left `NamedGapLedger`, `undo found a folder set aside` with them.
- PC `899w6-c3` (head 400083f60): the Undo classes 665 passed, 1 not run (the `[DenyBitesFact]` that cannot bite over SSH), 0 failed. Must-fail (`vm-tools/guest/899-w6-mustfail.json`, 20 sabotages): all red (`899w6-c1`, and `899w6-c3` for three made real: the contract's link rows and its key-written-twice row pass a reader that follows links or picks the first duplicate only because the content they lead to differs or the read-back refuses, so `AJunctionToTheVeryContentIsStillNeverFollowed` was added and the duplicate sabotage picks the last one). Killed-step harness (`Plantoir.UndoHarness kinds-kill`): 132 runs, every one whole, outside and inside OneDrive: `documentation/12-windows-app.md` → "What Windows has built: W6, the op kinds".

- **Fix round (the first review of W6, NOT CLEAN; and the final sweep of W3 and W4).** MEDIUM: `UndoAppSettingsPlaces` reads `settings.json` as it is on the disk and sets one member by replacing it exactly (lists and dictionaries whole), checked before a temporary file and one rename, nothing written on a mismatch, the running copy then given the member; the kill harness's preference is now `AcceptedSyncedFolders` in the real store (`UndoAppSettingsPlacesTests`, 6). LOW 1: editJSON byte for byte with the mac (`UndoMacKeyOrder`, `UndoJson.SpellNumber`, `UndoJson.ReadAsTheMacReads`), measured through the mac's own code and pinned as 8 new contract rows the mac's `UndoJournalContractTests` passes (this piece now touches `contracts/`). LOW 2: a file starting with a byte-order mark judged as on the mac. LOWs 3 and 4 and W4's front-page note: "For W7" below. The sweep: pruning stops at a step kept for a re-deriving recovery; the launch-call comments say W4; the owed-pieces table's corrections are below. PC `899w6f-a3` (head 6c5d2281a, `dev` 6b2a48a99 merged in): the Undo classes 681 passed, 1 not run (the `[DenyBitesFact]`), 0 failed; must-fail (`vm-tools/guest/899-w6f-mustfail.json`, 14 sabotages) all red, restored green; `kinds-kill` 132 runs, every one whole, the settings file's other member kept and no `settings.json.undo-writing` left in all 132 (no kill point falls inside the settings write itself, so this says nothing about a kill between its temporary and its rename: see fix round two), outside and inside OneDrive (settled as before: done 26, undone 22, rolled back 14, failed 4 in each place; 0.6 to 2.0 s a run). Mac (this Mac, macOS 26.7.3, Xcode 27.0): `UndoJournalContractTests` 17 of 17 with the 16 editJSON rows, and red when one new row's result is changed.

- **Fix round two (the second review of W6, NOT CLEAN: two MEDIUMs, three LOWs).** The rule now is: for an editJSON op, Windows writes exactly the bytes the mac would write, proven by a contract row run on both, or it writes nothing. M1: a key beyond printable ASCII (a new value's, a key path part, or any key of an object the path passes through) and text starting with a byte-order mark are refused (`UndoJson.IsMeasured`, `UndoJsonMember.PathIsMeasured`): cannot tell when judged, never written. M2: a file's number spelled with an exponent and more than 17 digits, or more than 38 without, makes the whole file cannot tell (`UndoJson.SpellingIsMeasured`). Also measured and matched: a negative number beyond a double's range is minus infinity on the mac (cannot tell when it is the member, judged as usual beside it); a positive one, and text holding half a surrogate pair, make the file unreadable on both (half a pair used to throw out of Windows' reader). 18 contract rows (7 `editJSONCases`, 11 `checkCases`), every result and verdict measured through the mac's own code; 13 of them carry what the mac does and Windows refuses, held by name in `NamedGapLedger` (`UndoEditJsonCasesRefusedHere`, `UndoCheckCasesRefusedHere`), where each must be REFUSED. The Python reference model (`scripts/make_undo_traces.py`) follows the same rules and holds the same 13: its test had failed on round one's 8 rows since that round (ordinal keys, Python's shortest numbers, no read-back), unseen because only the Undo classes ran. LOWs 2 and 3: tests for a stale `settings.json.undo-writing` (never read, gone after the next set) and a rename refused while the file is held open (nothing changed). LOW 1 is W8's ("For W8" below). Runs on the PC (LENOVO i5-8365U, Windows 11 Pro 26200): `899w6g-a1` at 6e3743a94 (classes, then the 26 sabotages of `vm-tools/guest/899-w6f-mustfail.json` each alone, then `kinds-kill`): all 26 sabotages red (build 0, test failed); `kinds-kill` 66 of 66 whole outside OneDrive and 66 of 66 inside it, 0 failures, A and B the same at every point; its class run had 1 failure of 726 (`WhatCanBeUndoneCanThenBeRedone` running a held row), the same 1 after the sabotages were restored. `899w6g-a2` at 901241af6 (the Undo classes): 716 passed, 0 failed, 1 skipped, 717 in all. The 9 fewer than a1's 726 are a different filter, not a lost test (review 3 compared the two `results.trx`): a1 was started with a wider `-Filter`, which took in the 8 `NamedGapLedgerTests` facts and `PythonToolchainTests.SharedPythonTestFilePasses("test_make_undo_traces.py")`, all 9 green there; a2 ran the script's default `FullyQualifiedName~Plantoir.Tests.Undo`, which matches none of them.

- **Fix round three (the third review of W6, NOT CLEAN: one MEDIUM, three LOWs).** M1: an exponent the mac does not read (more than 4 characters after the `e`, sign included, measured) makes the file not JSON on both platforms, by one rule in the contract (`undo.numberSpellingRule`, 37 `numberSpellingCases`, one `checkCases` row for `1e-0001`), held in `UndoJson` and `scripts/make_undo_traces.py` and checked against the contract by both (documentation 12 section below). L3: the 9-test gap is explained in the round-two paragraph. L1 (the Mac's runners on round two's 18 rows and this round's row) needs the Mac gate: no xcodebuild in this piece. L2 (the 13 held rows) is Russell's ruling, carried by the director. `dev` 5cf38d656 merged in (1aaa6577e; the ledger keeps W6's built rows gone and takes dev's U3b and U3c holds). PC `899w6h-a1` at 5be9984b3 (filter: the Undo classes, `NamedGapLedgerTests`, `test_make_undo_traces.py`): 814 passed, 0 failed, 1 skipped, 815; the 37 new rows, the limits fact, the 8 ledger facts and the Python file all passed. Sabotages (`vm-tools/guest/899-w6h-mustfail.json`): 1 (exponent check out) red, 13 of 37 `EveryNumberSpellingCase`; 2 (the same) red, 1 of 129 `EveryCheckCase`; 3 and 4 went red too (confirmed by the director after hand-back). On this Mac `python3 scripts/test_make_undo_traces.py`: 26 OK, and with the Python check taken out red on the `1e-0001` check case and the notJSON spelling rows.

## For documentation 12

### What Windows has built: W6, the op kinds (#899, #949)

Piece W6 (branch `issue/899-w6-op-kinds`, on W4, 2026-11-20) reads, checks,
moves and recovers every op kind the mac's U2b gave the journal. Nothing a
teacher sees changed: the switch is off, and no action writes these kinds
before W7 (U3) and W8 (U4).

- **Whole ops.** A move, a tree and an external op are judged and changed as
  a whole against the disk, never folded into another op's file
  (`opKinds.wholeOps`); a step where two ops share a place is a barrier. A
  move is judged as a PAIR: an undo after a deploy wrote a new marker where a
  rollover's was takes nothing back and keeps both. A move is one
  `MoveFileEx` WITHOUT `MOVEFILE_REPLACE_EXISTING`, the pair re-read just
  before it. A move that changes only case (`a.json` to `A.json`) is a step
  this version cannot read, because places compare without case: NTFS would
  otherwise see both places as one.
- **Links on Windows.** The mac's `lstat` is three questions here
  (`UndoLinks`): a reparse point whose tag is a NAME SURROGATE (a junction,
  a symbolic link, WSL's links) is a link, never followed, "something
  else"; a reparse point that is not (OneDrive's Files On Demand files and
  folders) is the teacher's own and is read like any other, so a folder in
  OneDrive is not a change since merely for being in OneDrive (rejected: any
  `FILE_ATTRIBUTE_REPARSE_POINT` as a link, which would have read every
  OneDrive folder as changed and cleared the list). A placeholder whose
  content is not on the disk fails its read, which is cannot tell.
- **Trees.** A folder to make is built beside its place under its staged
  `-new` name and renamed in, never over anything. A folder to take out is
  renamed aside to `-orig` FIRST and its listing checked there, then, once
  every change is in, renamed to `-gone` and deleted, so a delete cut short is
  finished by recovery and never put back half emptied. Files inside are
  removed by handle with the read-only attribute ignored (a file may be a hard
  link to a page elsewhere). A folder with a file another program holds open
  cannot be renamed on Windows: taking it out is refused `fileIsInUse`, the
  folder whole in its place, the list kept (`UndoOpKindsContractTests`).
- **A folder set aside by a stopped step** is never deleted: put back when its
  place is free, otherwise kept as `<name> (kept by Undo)`, `(kept by Undo 2)`
  and on, the trail line `undo found a folder set aside` written just before
  the rename. A pruning hold has no trail sink, so a folder it puts back says
  nothing there; recovery and the closed-step tidy say it.
- **editJSON** changes only the member's bytes (the mac's byte scanner, ported):
  a new value spelled byte for byte as the mac's `JSONSerialization` writes it,
  a key written twice on the path, or a whole number of 2^53 or more, refused.
  Values are compared through doubles as on the mac, not with
  `JsonNode.DeepEquals` (exact decimals would disagree with the mac at 2^53+1).
  Three things were measured on the mac (macOS 26.7.3, 2026-11-20) through the
  mac's own code (`vm-tools/guest/899-w6-mac-editjson-runner.swift`: the mac's
  `UndoJSON`, `UndoJSONMember` and `UndoJSONBytes` verbatim, run as its contract
  runner runs them) and are now contract rows (`undo.editJSONCases`, 8 new, 16
  in all, the mac's `UndoJournalContractTests` green on them and red on a
  changed row):
  - **Key order** (`UndoMacKeyOrder`) is not ordinal: a key is read as pieces
    (a run of digits, or one character); punctuation first in a fixed order (a
    space, then `_ - , ; : ! ? . ' " ( ) [ ] { } @ * / \ & # % ` ^ + < = > | ~ $`),
    then digit runs by their number (9 before 10), then letters ignoring case;
    keys equal so far are told apart at the first piece that differs, a
    lowercase letter before its capital and a run with fewer zeros in front
    first (`1A`, `01a`; `ab`, `aB`, `Ab`). 6,000 random sets of printable ASCII
    keys came out in exactly this order. Rejected: ordinal (`"10","9","B","a"`
    where the mac writes `"9","10","a","B"`). A key with anything beyond
    printable ASCII is refused (fix round two, below).
  - **Numbers** are C's `%.17g` (`UndoJson.SpellNumber`): 0.1 is
    `0.10000000000000001`, 1e-07 `9.9999999999999995e-08`, a whole number below
    2^53 its digits, negative zero `0`. Rejected: .NET's shortest round trip
    (`"R"`), which wrote `0.1` and `1E-07`.
  - **The read-back** goes through the mac's reader, which reads a spelling in
    fixed notation with more than 17 digits (leading zeros of the whole part
    dropped) as an `NSDecimalNumber` whose double is its digits summed in 16-bit
    pieces and then divided by ten once per place (`UndoJson.ReadAsTheMacReads`:
    1,729 of 1,729 such spellings bit for bit, and 4,244 of 4,244 others the
    nearest double). So a member set to 0.0001234 (spelled
    `0.00012339999999999999`, read back there as `0.00012340000000000002`) is
    refused on both platforms, as changed since; 0.08129913717470501 is written.
    A file's numbers are read the same way when a member is judged. A spelling
    past the measured digits is refused (fix round two, below).
- **A file starting with a UTF-8 byte-order mark** is read as the mac reads it
  (Foundation passes over the mark; measured), so its member is judged as on
  the mac (the verdict before a write), and it is never moved, as on the mac,
  whose scanner starts at the mark: refused as changed since. A space before
  the mark is not JSON on either. No contract row can carry it: the mac's
  runner reads each case through `JSONSerialization`, which drops a mark at the
  start of a string (measured), so `UndoOpKindsContractTests` pins it.
- **external.** `preference:<name>` is a member of the app's own settings
  (`UndoAppSettingsPlaces`), read from `settings.json` as it is on the disk now
  (following `--state-dir`), as the app's typed settings read it, never from a
  process's copy, which may be older (`plantoir-mcp.exe` holds its own). A set
  replaces exactly that member with exactly the value (a list or a dictionary
  replaced whole), into the file as it is now: read, the one member changed,
  the result checked to read back as the value, then written whole by a
  temporary `settings.json.undo-writing` and one rename that replaces, so it
  happened or did not; on a mismatch (a number for a text setting) nothing is
  written and the set is refused couldNotWrite, the file byte for byte as it
  was. A file the app's own reader cannot read is never written over. The copy
  the process runs on is then given the same member, so its next save keeps
  it. Rejected (the first review of W6, MEDIUM): `PopulateObject` on
  `AppSettings.Current` and its `Save()`, which appended to lists, merged
  dictionaries, saved before checking, and wrote a process's older copy of
  every other setting over the file. A name the store does not have is cannot
  tell; a typed setting cannot be set to "not set" (refused couldNotWrite).
  **Owed by W8**, which decides which settings a step records: a set made by
  one process is not seen by another process's copy until that process loads
  again, so a set recovery makes in `plantoir-mcp.exe` is undone by the app's
  next save of its own copy unless W8 has the app re-read the member (or keeps
  every external op in the app's process). Nothing writes an external op
  before W8.
- **The front page's runner** (`UndoSectionFrontPage`, from W4's review)
  serves the recovery cases' re-derivations.

**Measured, `899w6-b2`, Lenovo 20QES70500 (i5-8365U, 16 GB, Windows 11 Pro
26200).** One step of every kind (two pages' lines, a hunk, a member, a
preference in the app's real settings store (since the fix round: `AcceptedSyncedFolders`, a list), a folder removed, a folder made, a marker moved:
8 swaps), its apply, its undo and its redo, each made by a child process
killed at every step (its begin, before each of the 8 swaps, while a folder
taken out was being deleted, before its closing: 33 points), then recovered
by a second process, and again with that recovery killed before its first
put-back swap (42 of the 66 were killed there) and a third recovering:

| Place | Runs | Every place wholly before or after, all one way, as the list says | Nothing staged left | A and B agree |
|---|---|---|---|---|
| `C:\vm-setup\…\scratch` | 66 | 66 | 66 | 33 of 33 |
| `%OneDrive%\plantoir-w6-scratch-…` (OneDrive running) | 66 | 66 | 66 | 33 of 33 |

Settled as, in each place: done 26, undone 22, rolled back 14, failed 4 (no step was left in flight or interrupted). A run's
three processes took 0.5 to 1.3 s end to end. The scratch folders were
removed after the run.

### editJSON refuses what is not measured to match the mac (fix round two)

The rule: **for an editJSON op, Windows either writes exactly the bytes the mac
would write, proven by a contract row run on both platforms, or it does not
write at all.** `UndoMacKeyOrder`, `SpellNumber` and `ReadAsTheMacReads` are
re-implementations of Foundation, so anything they have not been MEASURED to
match is refused before a byte is written: "cannot tell" when the member is
judged (the list is kept), and no bytes when it is moved. Measured on this
Mac (macOS 26.7.3, 2026-11-20) through the mac's own code
(`vm-tools/guest/899-w6-mac-editjson-runner.swift`, the mac's `UndoJSON`,
`UndoJSONMember` and `UndoJSONBytes` verbatim, and `JSONSerialization` itself):

- **Keys beyond printable ASCII.** The mac sorts them by Unicode collation
  (`😀, 9, 10, １０, a, A, Ａ, a<tab>b, ab, e, E, é, f, ss, ß, z, Ω, 日本`: an
  emoji first, `é` between `E` and `f`, a full-width `Ａ` beside `A`, `ß` after
  `ss`, a tab passed over). It takes canonically equivalent keys for one (`é`
  as one character and as `e` with a combining accent; the Kelvin sign and
  `K`), so a key path part can find a member Windows would call missing and add
  beside it; and it reads a key starting with a byte-order mark as the key
  without it. So Windows refuses a new value holding such a key, a key path
  part holding one, and any object on the path holding one (the top level
  included). The app's own `settings.json` (`external`), which the mac never
  touches, still takes them.
- **Text starting with a byte-order mark.** The mac's reader drops the mark
  (escaped or not; one inside the text stays), so the mac reads such a member
  as the text without it and refuses to write such text (its read-back
  disagrees). Windows answers cannot tell, and refuses to write it, which is
  what the mac does there. No row can carry a new value with the mark (the
  mac's runner drops it when it reads the contract), so a Windows test pins it.
- **Numbers.** With an exponent: at most 17 digits read as the nearest double
  (fix round two measured 4,000 random spellings whose exponents' values ran
  from -330 to 310, but the code then accepted ANY exponent, which was more
  than was measured; fix round three measured the exponent itself, below),
  and more than 17
  are a decimal number there (`1.2345678901234567890123e-5` is
  `1.2345678901234573e-05`, not the nearest). Without an exponent: 18 to 38
  digits agree with `ReadAsTheMacReads` (30,000 random spellings, every one);
  from 39 they disagree, and with 120 or more digits after the point the mac
  cannot read the file at all. Digits are counted from the first that is not a
  leading zero of the integer part. A spelling past those counts makes the
  whole file cannot tell, because the mac may not read the file at all. A
  negative number beyond a double's range (`-1e400`, `-1.8e308`) is minus
  infinity on the mac, which is not exact: cannot tell as the member, and
  judged as usual beside it, the same here. A positive one (`1e400`) and text
  holding half a surrogate pair (`\ud800`) make the file unreadable on both:
  changed since.

18 contract rows, every result and verdict measured: 7 in `undo.editJSONCases`
(the six refusals below and one pinning how new text is written: UTF-8, a
control character escaped as `\b`, `\f`, `\u0001`, DEL and the line and
paragraph separators as they are) and 11 in `undo.checkCases`. **13 rows carry
what the mac does and Windows refuses**, held in `NamedGapLedger` by name
(`UndoEditJsonCasesRefusedHere`: 6, each must be refused, never bytes of its
own; `UndoCheckCasesRefusedHere`: 7, each must be answered cannot tell both
ways), with the reason that Windows refuses these until its key order and
number reading are measured to match. The Python reference model holds the
same 13 (`REFUSED_HERE_EDIT_JSON`, `REFUSED_HERE_CHECK` in
`scripts/test_make_undo_traces.py`). They are held on v2.0.0 like every #899
entry; closing them means measuring Foundation's collation and decimal reading
on Windows, or a ruling that Windows may refuse them in the release.

One limit of the mac's own runner, found while proving the rows: it compares a
row's result with Swift's `!=` on strings, which is canonical equivalence, so
it cannot tell the Kelvin sign from `K` or a decomposed `é` from a precomposed
one (a sabotaged Kelvin row stayed green). Those rows' exact bytes come from
the scratch runner, which prints them through `JSONSerialization` with every
scalar kept; the mac's runner went red on a changed collation row and on a
changed verdict.

**What a teacher on Windows would meet** (from W7 and W8 on, when actions
record editJSON steps): an Undo or Redo of a settings change refused as
"cannot tell", the list kept and the file untouched, where the mac would undo
it, when the course's settings file holds such a key or number. **Which of
Plantoir's own files could hold one:** the editJSON targets the mac's U4 plans
are `course_config.json` (Course Settings, Set School Year, renames, New
Course, Keep a Copy for Reference). Every key its schema names
(`contracts/file-formats.json` → `courseConfigKeys`) is printable ASCII, the
keys of its maps included (`section1` and on; `shared`, `per_section`;
destination types), and the apps write whole numbers and booleans there,
never an exponent. So no file Plantoir writes holds one: only a file a person
or another tool edited by hand (an accented key added, a number pasted with 20
digits, a mark in front of a value) can. Folder, page and course names with
accents are values there, never keys, so they are unaffected.

### An exponent the mac cannot read (fix round three)

The third review of W6 found the same kind of hole as review 2's M2, for the
exponent: Windows read `1e-0001`, `1.5e+0010` or `0e99999` and judged or moved
the member beside it, while the mac cannot read such a file at all and answers
changed since. **The rule now, on both platforms:** Windows judges and
rewrites a member only where the mac's `JSONSerialization` reads the same file
to the same value; a spelling the mac cannot read makes the file not one JSON
object (changed since, every move refused). It is one rule in the contract,
`undo.numberSpellingRule` (`exponentCharactersAtMost` 4,
`digitsWithAnExponentAtMost` 17, `digitsWithoutAnExponentAtMost` 38), which
`UndoJson` (`MacExponentCharactersAtMost`, `TheMacReadsTheExponent`) and
`scripts/make_undo_traces.py` (`MAC_EXPONENT_CHARACTERS_AT_MOST`,
`_exponent_read_by_the_mac`) hold as constants that their tests compare with
the contract's (`TheNumberLimitsAreTheContractsRule`,
`test_the_number_limits_are_the_contracts_rule`), and 37 rows,
`undo.numberSpellingCases`, that both run (`EveryNumberSpellingCase`,
`test_number_spelling_cases`), plus one `checkCases` row, "another member
written 1e-0001": changed since both ways.

**Measured** on this Mac (macOS 26.7.3, Apple silicon), `swift` scripts
calling `JSONSerialization.jsonObject` on `{"a":<n>,"b":1}` (no xcodebuild;
the probe is `vm-tools/reference/899-w6-mac-json-exponents.swift`):

- The mac reads an exponent written with **at most 4 characters after the `e`
  or `E`, its sign and leading zeros included**, and cannot read the file when
  there are more, whatever the value or the digits before it: `1e0005`,
  `1e+005`, `1e-005`, `1e-999`, `0e9999`, `-1e9999` are read; `1e00005`,
  `1e+0005`, `1e-0001`, `1e-0500`, `1e-1000`, `0e99999` are not. 103,528 of
  103,528 random spellings with 5 to 7 such characters (mantissas of 1 to 22
  digits) could not be read.
- Within 4 characters, with at most 17 digits, every reading is the nearest
  double: every exponent string of 1 to 4 characters (13,330: with and without
  a sign, every leading-zero form) on 14 mantissas at a double's range's edges
  (`4.9406564584124654`, `2.4703282292062328` and `...27`, `1.7976931348623159`,
  `17976931348623157` and others), and 200,000 random spellings: 140,193
  nearest doubles, 121,381 above a double's range (not readable, as Windows
  already refused a positive infinity), negatives beyond it minus infinity, 0
  disagreements. With more than 17 digits the mac read a decimal number (6,044)
  or nothing (15,474): cannot tell here, as before, unless the exponent itself
  is too long, which is settled first (not JSON).
- So: `-1e999` is minus infinity, `1e-999` is 0, `2.4703282292062327e-324` is
  0 and `...28e-324` is `5e-324`, `1.7976931348623159e308` is not readable.

What is NOT measured: how Windows' own `double.Parse` rounds was not compared
with the mac outside the 37 rows (both are IEEE nearest; the rows pin the
edges); a lone `e` or `e+` with no digits is not JSON on any reader. The mac's
runner does not read `numberSpellingCases` (an `undo` key it does not know is
ignored there), so those rows are run by Windows and Python only; the new
`checkCases` row is run by the mac's replay too, and its verdict follows from
the measured fact that the mac cannot read the file and from the mac's own row
"editJSON: the file is not JSON": the Mac gate is what proves it (no
xcodebuild in this piece).

### For W8: the settings write and `AppSettings.Save` (the second review of W6, LOW 1)

`AppSettings.Save` is a plain `File.WriteAllText` that swallows every error,
called from about 24 places on the app's thread; the undo settings write
(`UndoAppSettingsPlaces.Write`) holds the undo lock, which `Save` does not
take. Three windows follow: an app save between the write's read and its
rename is lost on the disk until the app's next save; an app save between the
rename and the running copy being given the member writes the old member back
while the write says it succeeded (the file then disagrees with the journal's
`applied`, and an Undo of that step would read changed since and clear the
list); and while the write reads the file, an app `Save` cannot open it and is
silently dropped. None of this is reachable before W8 (no action writes an
external op, and recovery acts only on journal ops). **W8 owes one settings
lock taken by `AppSettings.Save` and by this write, or the write done on the
app's thread through the running copy**, together with the cross-process point
above. Also W8's: populating the running copy bypasses `ChangePreviewOpensAt`
and `ChangeCloudflareAccountId` and their events, so an open Settings pane or
a window title would not follow an undone preference. And a write killed
between its temporary and its rename leaves `settings.json.undo-writing`:
harmless (nothing reads it, and the next set writes over it and renames it in,
`UndoAppSettingsPlacesTests.ATemporaryLeftByAKilledWriteIsNeverReadAndGoesWithTheNextSet`),
but no harness kill point falls inside the write, so W8's harness adds one
there.

### For W7: shadow leftovers (the first review of W6, LOW 3)

In shadow, recovery never tidies a working folder and `TidyClosedSteps` runs
live only (the mac's rule, unchanged here). So a `removeTree` killed after its
folder went aside leaves the teacher's folder under its staged dot name
(`.<name>.plantoir-undo-<step label>-orig`), which Explorer does NOT hide (a dot name is
not hidden on Windows), and a `-gone` folder half deleted, until the switch
goes on; the same if the step is pruned before a put-back succeeds. Nothing
reaches this before W7, because no teacher action writes a tree op through the
door in shadow yet. Before any teacher action sends a tree op through the door
in shadow, W7 must prove, on the PC's disk and inside OneDrive, with the kill
harness: a take-out killed at every point, in shadow, leaves the teacher's
folder in its place or in a visible place the teacher is told about, never
under a staged name; a `-gone` remnant left in shadow is finished or reported
at the next live recovery; and pruning a shadow step never strands either.
Until W7 proves that (or the rule changes for both apps), tree ops stay out of
shadow writes.

### For W7: the "(kept by Undo)" folder is a real folder (LOW 4)

`<name> (kept by Undo)` (and `(kept by Undo 2)` and on) is an ordinary folder
beside its place, so under `courses/` it is part of the course: a build and a
deploy include its pages. That follows Russell's ruling of 2026-11-19 and the
mac; the director is telling him. No sentence on screen says it yet (the only
sentence is the trail line `undo found a folder set aside`, contract wording);
whatever sentence a teacher is first told about a kept folder (W7 on, with the
mac) must say plainly that it is a real folder that a build and a deploy
include, until a ruling says otherwise.

### For W7: the front page re-derived twice (from W4's re-review)

In shadow the door, not the action, re-derives the front page: a W7 action that
keeps its own front-page write and also routes a `recompute` through the door
writes the page twice. W7 keeps one: the action's own write, or the door's.

### For documentation 12: the owed-pieces table

In "The owed pieces" table (about lines 16931 and 16938 of
`documentation/12-windows-app.md` on `dev` 2ba8490e7):

- the **W4** row is marked BUILT (2026-11-20), as W2a, W2b and W3 are: where the
  list lives (following `--state-dir`), the writer scan, the switch (off), and
  recovery at every launch of the app and of `plantoir-mcp.exe`
  (`UndoAtLaunch.Recover`);
- its promise "`madeBy` from `AssistWorkspace.Surface` (L1)" is not built by W4
  and moves to the **W7** row: the PC's `plans/899-plan.md` puts `madeBy` (a
  `--door menu|builtIn` argument from the helper's role) beside the shadow
  recording of publish and hide, which the plan review's M1 moved to W7;
- "recovery at a windowed launch" is removed from the **W11a** row (W4 calls
  `Recover()` at every launch already).

### Pruning stops at a step it keeps (the final sweep of W3 and W4)

`UndoJournal.Prune` stopped writing for a step left in flight for a
re-deriving recovery (W3's review, LOW 2) but went on with the `pruned` lines
`UndoPruning.Decide` had queued behind it, so newer steps were pruned while an
older one was kept, against "one oldest run only, never a step newer in
sequence than one kept". The run now stops there
(`UndoRecoveryReviewFixesTests.PruningStopsAtAStepLeftForARederivingRecovery`).
The mac has no such hole: its `UndoRecovery.prune` has no arm that keeps a
step, and closes such a step `interrupted` as the contract's limits say. No
contract row covers a kept step (the stack cases have none), so the test pins it.
