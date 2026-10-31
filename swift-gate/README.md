# swift-gate: the fragments every Swift toolchain must pass (#493)

Fifteen small Swift programs, written the way a Grade 11 or 12 student writes
them, that the Swift image (`support/swift/`) must compile and the site's own
WASI shim (`support/gated/swift/plantoir-wasi.mjs`) must run correctly. They
are the gate for runnable Swift blocks: `verify.sh` compiles all fifteen in the
image it builds and runs them through `browser-checks/wasi_run.mjs`, which
checks each against `expected.json`.

This folder is OUTSIDE the recipe (`contracts/toolchain.json` →
`recipeFolders` is patches, scripts, support and contracts), so editing a
fragment changes neither the website builder's image nor the app bundle.

Fragments 01–10 are the ten #493's Phase 0 measured, re-authored to its table
on 2026-10-17 (the originals were in a scratchpad that was lost); 01 and 05
are the spike's. 11 and 12 were added by the plan review (S5): a recursion
that never stops and a list that grows for ever. 13 and 14 were added while
implementing: a prompt printed with `terminator: ""` before `readLine()`,
whose echoed answer came BEFORE the prompt until readLine() was made to
flush stdout - 13 in Embedded Swift, 14 in the full library. 15 was added
by the implementation review (S1): `Int` is 32 bits on wasm32, so `13!`
overflows, and the trap prints NO `Fatal error:` line in either library
(even `-Onone` prints none).

| # | Fragment | What it exercises |
|---|---|---|
| 01 | greeting | `readLine()`, `isEmpty`, `count`, `Int(String)`, interpolation |
| 02 | average | `while let readLine()`, `guard`/`continue`, `Double` division, printing a `Double` |
| 03 | palindrome | `lowercased`, `Character.isLetter`, `reversed`, `==`, `contains(Character)`, **`contains(String)`**, `uppercased`, `hasPrefix` |
| 04 | optionals | `[String: Int]`, `if let`, `??`, `guard let`, an `Int?` parameter |
| 05 | arrays | `split(separator:)`, `Int(Substring)`, `sorted`, `append`, an index loop, **interpolating an `[Int]`** |
| 06 | struct | stored and computed properties, a `mutating` method, value copies |
| 07 | inheritance | classes three deep, `override`, `super`, a polymorphic `[Shape]`, `rounded()` |
| 08 | enum | associated values, `split(maxSplits:)`, `switch` with bindings |
| 09 | errors | an `Error` enum with payloads, `throws`, `do`/`catch` patterns, **`"\(error)"`** |
| 10 | out-of-range | an array index past the end: a trap, with its `Fatal error:` line |
| 11 | recursion | a function that calls itself for ever: a crash, not a hang |
| 12 | growth | a list that grows for ever: a trap at the 256 MB memory cap |
| 13 | prompt | `print(..., terminator: "")` then `readLine()`: the prompt before the echoed answer (Embedded) |
| 14 | prompt-full | the same in a program that prints an array (the full library) |
| 15 | overflow | `13!` in an `Int`: a silent trap (`expected.json` → `noFatal`) |

Each fragment is `NN-name.swift` with `NN-name.stdin` (the input box's lines)
and `NN-name.expected` (what it prints, without the echoed input). For the
four that trap, `.expected` is what it prints before the trap. Every
`.expected` for 01–09 was checked against a native macOS build (Swift 6.4.0,
`swiftc -O -swift-version 5`) on 2026-10-17.

## Measured (2026-10-17, the Swift image on Colima, Apple M4 Pro)

Compiled by `support/swift/compile.py` in `teaching-quartz-swift`, all
fifteen in parallel in 13 s (verify.sh at d9bd64330), then run by
`wasi_run.mjs` in Node 22:

| # | Library | Bytes | Imports | Result |
|---|---|---|---|---|
| 01-greeting | embedded | 62,347 | 8 | MATCH |
| 02-average | embedded | 70,906 | 8 | MATCH |
| 03-palindrome | full | 4,260,695 | 14 | MATCH |
| 04-optionals | embedded | 100,660 | 8 | MATCH |
| 05-arrays | full | 3,453,463 | 14 | MATCH |
| 06-struct | embedded | 69,784 | 8 | MATCH |
| 07-inheritance | embedded | 70,570 | 8 | MATCH |
| 08-enum | embedded | 109,442 | 8 | MATCH |
| 09-errors | full | 3,446,053 | 14 | MATCH |
| 10-out-of-range | embedded | 49,243 | 8 | trap (RuntimeError) with `Fatal error: Index out of range` |
| 11-recursion | embedded | 12,697 | 8 | crash (RangeError) |
| 12-growth | embedded | 15,168 | 7 | trap (RuntimeError) in 0.07 s at the cap, with Embedded Swift's misleading `Fatal error: Unexpectedly found nil while unwrapping an Optional value` |
| 13-prompt | embedded | 49,252 | 8 | MATCH, and the transcript with the prompt before the answer |
| 14-prompt-full | full | 3,442,011 | 14 | MATCH, and the transcript too |
| 15-overflow | embedded | 39,652 | 8 | trap (RuntimeError) after `12! = 479001600`, no Fatal error line |

The verdicts for 01-10 are Phase 0's: Embedded Swift runs seven of them
correctly, refuses 03 at compile (`String.contains(String)` is not in its
library), and compiles 05 and 09 into programs that would print `(cannot
print value in embedded Swift)` - so compile.py falls back to the full
standard library for those three, and they run correctly; 14 falls back for
the same reason as 05. The same fragments compiled with the macOS 6.4.0
toolchain give programs of exactly these sizes (the bytes differ only in the
16-byte module hash, which names the host: spike G4), and one image
compiles the same code to the same bytes every time.

The shim's own checks, in the same run: each input line is echoed straight
after its prompt; and the **must-fail** - with every right on fds 0-2, seek
and tell included, fragment 10's `Fatal error:` line is lost, and with the
shim's rights it is kept (spike G5). Without readLine()'s flush, 13 and 14
printed the answer first (`Ada`, then `What is your name? Nice to meet you,
Ada.`) in both libraries - the must-fail for the flush, measured by taking it
out and putting it back.

## When the toolchain moves

A new Swift release, SDK or binaryen means new pins in
`support/swift/Dockerfile` and `contracts/toolchain.json` → `swiftImage`,
which changes the toolchain id and compiles every block again. Before that
lands, run `./verify.sh` and read its Swift gate: Embedded Swift is still an
experimental feature and its library changes between releases, so a
verdict in `expected.json` can move (a fragment that used to need the full
library may compile Embedded, or the reverse). Update `expected.json` and the
table above from what the gate measured, never from the release notes.

To try a toolchain on a Mac without the image, point compile.py at it:

```bash
export PLANTOIR_SWIFTC=~/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swiftc
export PLANTOIR_SWIFT_SDK=~/Library/org.swift.swiftpm/swift-sdks/swift-6.4.0-RELEASE_wasm.artifactbundle/swift-6.4.0-RELEASE_wasm/wasm32-unknown-wasip1
export PLANTOIR_WASM_OPT=/opt/homebrew/bin/wasm-opt
mkdir -p /tmp/gate/jobs && cp swift-gate/*.swift /tmp/gate/jobs/
python3 support/swift/compile.py /tmp/gate/jobs /tmp/gate/out
node browser-checks/wasi_run.mjs swift-gate /tmp/gate/out
```
