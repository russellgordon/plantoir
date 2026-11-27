Removed by #1055 (2026-11-27): symbolic links in course content are not supported.

# U4b3 relink-2 (#899): a relinking move is readable, and the contract says how it is judged and made

Brief `vm-tools/briefs/2026-11-26-899-u4b3-relink-2-a-relink-is-readable.md`, from relink-1's pushed head c2700e2c0 on `issue/899-u4b3-linked-class-page-moves-its-link`. `origin/dev` still 06e067fbe (already merged in) before proving and before handing back: no merge needed. **`contracts/` touched: both gates.**

## For PROGRESS

- `UndoOp.shapeIsKnown`: exactly one content form, `sha`, `listingSha`, `linkSha`, or the pair `linkShaBefore` and `linkShaAfter` counted as one. The pair's shape is `UndoOp.relinkShapeIsKnown`: a `move` only (never `moveApart`, `setAside` or a capitalisation-only move), both blob names, different, `blobs` exactly the two. Either key alone is unreadable. The comment says why the pair is not `linkSha` plus one new key (an older reader would Redo a plain link's move with the OLD text).
- `wholeOpsStandAlone` and the handed-over-place rule already ask `isALinksMove` (relink-1); checked by test (`UndoRelinkTests`, the leaver and filler tests, and `UndoHandedOverPlaceTests` green), nothing else changed.
- `contracts/file-formats.json`: `opKinds.move` gains one sentence for the relink (shape, two blobs, each side judged by its own text with lstat and readlink, both standing changed since, made as a new link beside the destination renamed in exclusively then the old removed, why not `linkSha`); "The moved content is never a blob" now opens "Beyond a relinking move's two texts". `opKinds.wholeOps`: "of a link (linkSha)" now "of a link (linkSha, or linkShaBefore and linkShaAfter)".
- `contracts/shared-rules.json`: `checkCasesHow` gives `linkTargetBefore` and `linkTargetAfter` (hashes, both blobs unless the case gives its own `blobs`), and `cannotBeRead` on a link side takes away its folder's permissions (a link's own are never asked by lstat or readlink, and chmod follows the link). Nine `checkCases` rows, "U4b3 relink, a link's move that changes its text: …", after the U4b2-14 link rows.
- Mac replay (`UndoContractReplay`): the two keys; a link side's `cannotBeRead` chmods its folder.
- Python: `move_state` judges each side by its own text; `is_a_links_move` used by `hands_over_as_a_move` and `move_carries`; the test's `readable_op` counts the pair as one (`relink_shape_is_known`), `prepared` takes the two keys; a direct test that `linkSha` beside the pair, and a `moveApart` with the pair, are not readable. Traces not stale (regenerated identical).

## Rows

Ten briefed, nine written. Dropped: "linkSha given as well: not readable" as a shared row (see "For the director"); its shape is pinned on the Mac by `UndoRelinkTests.testARelinkWithLinkShaGivenAsWellIsABarrier` and in Python by `test_a_relink_beside_link_sha_is_not_readable`. No two of the nine say the same thing for the same reason, so none else dropped (old text at `to` and new text at `from` are different sides, each a different misreading).

## For documentation 12

Windows' `UndoFormat.ReadOp` must read `linkShaBefore` and `linkShaAfter` (strings, blob names) and `ShapeIsKnown` count them as ONE content form beside `sha`, `listingSha`, `linkSha`: both present, different, a `move` only (not a capitalisation-only one), `blobs` exactly the two. With `linkSha` beside the pair it is not readable. The check-case harness (`UndoCheckContractTests.OpOf`) must turn `linkTargetBefore`/`linkTargetAfter` into the two hashes and `blobs` (unless the case gives `blobs`), and lay a link side with the case's own text (as `withItsTarget` does for `linkTarget`), and route such cases to the symbolic-link theory. Reason constant `Reason899W8RelinkedLink`, held under it in `UndoCheckCases`: seven rows (every new row whose verdict is not `notReadable`). Why each held row fails today: no `sha`, `listingSha` or `linkSha`, so `ShapeIsKnown` (UndoFormat.cs, the `case UndoOp.Move` count) is false and the op is `notReadable`, which differs from each row's verdict and is what the held check asks. The two barrier rows pass unheld for the same reason (`notReadable` is their verdict): "the two texts the same" and "one text missing from blobs" (raw `linkShaBefore`/`linkShaAfter`/`blobs`, which `ReadOp` ignores). Script check: each held name once in `shared-rules.json` and once in the ledger (7 of 7).

## Must-fail lines

RED 4 of 4: `899-u4b3-relink-2-mustfail.log` (M1 run-r2-mf1, M2 run-r2-mf2, M3 run-r2-mf3, M4 Python). M2 fails the Mac unit barrier test, not a row (no row; see below).

Red first: run-r2-red, `UndoFormat.swift` change taken out: the seven readable rows failed (`undo is notReadable`), `testARelinkFromTheJournalIsReadable`, `testARelinkStepIsMadeUndoneAndRedoneThroughTheList` (door refused notReadable) and `testARelinkWithLinkShaGivenAsWellIsABarrier` (the old count took `linkSha` beside the pair as a plain link's move: the misreading itself) failed; the two barrier rows passed, as they must.

## Runs (`.dd/`)

run-r2-red (31 tests, 30 failures), run-r2-green (UndoRelinkTests, UndoHandedOverPlaceTests, UndoJournalContractTests, UndoFilesContractTests, UndoWriterScanTests, SharedRulesContractTests, FileFormatsContractTests: 158, 0 failures), run-r2-mf1 to mf3; `python3 scripts/test_make_undo_traces.py` OK (39). No `UndoFormatTests` class exists. No test reads a changed file as source text but the writer scan (UndoFormat.swift writes nothing; count unchanged).

## Left for the next piece

- relink-3: recovery's both-standing moment, the two stop points, `recoveryCases` `withARelink`, Python recovery.
- relink-4: `JournaledStep.relinkLink`.

## For the director

1. **The "linkSha given as well" row cannot be a shared row yet.** The brief says Windows reads every shape barrier `notReadable` today; it does not for this one: `UndoFormat.ReadOp` reads `linkSha`, ignores the two unknown keys, and `ShapeIsKnown` counts one content form, so Windows reads it as a plain link's move (and the harness, seeing `linkTarget` and a `link`, judges it on the disk). Unheld it fails (a verdict, not `notReadable`); held, the held check's `Assert.False(op.Readable)` fails. Options: (a, recommended, done here) no shared row now; the shape is pinned on the Mac and in Python by unit tests; Windows' 21b adds the row with its own reading (it is then a row both pass). (b) Add the row now and accept a red Windows suite until 21b. (c) Change the Windows harness to allow "held, readable" rows (Windows code, out of this piece's scope).
2. The brief's Windows wording claimed every barrier is notReadable there; the ledger reason wording is the brief's verbatim and stays true for the seven rows it holds.

## Self-check

1 to 6 (NIGHT3): own classes only through `xlock.sh`, no gate, no Windows, no UI tests (none run after the director's no-screen notice either); red first and must-fail recorded; notes written. 7: house-style grep over added Swift lines empty; no new type (the test class's MARK sections kept, a `Readable (relink-2)` section added). 8: no riding lows. 9: switch off, rename record untouched. 10: every new row in the Mac replay and in Python; the seven Windows cannot read held by exact name, the two it passes unheld.
