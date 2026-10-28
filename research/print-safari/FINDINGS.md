# The Print button in real Safari (#576)

Measured 2026-10-23 by a read-only Claude Opus 5.5 planner, on Russell's Mac
(Apple silicon, macOS 26.6), **Safari 26.6**, with `safari_print.sh` and its
helpers beside this file, one run per row unless noted. Pages: a copy of
Russell's own build of ICS3U section 2 (1.8.x, `Concepts/Variables-and-Data-Types`:
18 code blocks, a table of contents, two 2800 x 1880 px PNGs) served by
`serve.mjs`, and the live site of the same section. Nothing here runs
automatically, and nothing here is a gate.

## Why not safaridriver

Remote automation was on (sessions start: Safari 26.6), but under automation
`print()` returns in 0 ms with no beforeprint, no afterprint and no sheet -
even a plain `window.print()` called synchronously from a WebDriver click with
`navigator.userActivation.isActive` true (System Events: 0 sheets). WebKit
skips printing for a page under automation, so a safaridriver pass or fail
says nothing about print. A real gesture turned out not to matter either: a
`print()` from a timer opened the sheet.

## Results

| Page / how reached | Path | print() called | Sheet? | Notes |
|---|---|---|---|---|
| local copy, direct | paged | +272 ms, 0/2 pictures pending | yes, "Page 3 of 6" | print() blocked 8.6 s until Cancel |
| local copy, from home (spaNavigate) | paged | +281 ms | yes | |
| pictures held 1.5 s, direct / from home | paged | +1,669 / +1,664 ms | yes / yes | |
| live site, direct / from home | paged | +1,009 / +472 ms | yes / yes | the live page prints today |
| faces (.otf) held 7 s, direct | paged | +35,305 ms | yes | slow, but prints |
| **fallback forced, pictures held 1.5 s, from home** | fallback | +91 ms, 2/2 pending | **no** | print() returned in 0 ms, frame removed 3 ms later |
| **fallback forced, pictures not held, from home** | fallback | +97 ms, fonts loading | **no** | the same |
| **fallback forced, a small page (no code, no pictures)** | fallback | +48 ms, fonts loading | **no** | page size does not matter |
| fallback forced, frame removal suppressed (`KEEP=1`) | fallback | +90 ms, fonts loading | **yes, 39 ms later** | the postponed print arrives if the frame survives |

In every run where a sheet opened (8), beforeprint and afterprint for the
frame's print fired on the TOP window, never on `frame.contentWindow` - so a
listener on the frame's window alone never hears Safari.

## Not measured

The event order of the `KEEP=1` run - whether the postponed print sends
beforeprint, and when - was not recorded: the re-run was stopped on
2026-10-23 at 03:15 (Russell was using Safari), and no Safari was driven
afterwards that night. The fix is built so it does not depend on it
(`documentation/06-quartz-customizations.md` F3).

## Running it again

Serve a site (`node serve.mjs <public folder> 8576 1500 nopaged` forces the
fallback with pictures held 1.5 s), then
`./safari_print.sh http://127.0.0.1:8576 fromhome <page path>`. On the code
before #576 a forced fallback says `NO SHEET after frame-removed`; the fix
must say `SHEET`. Run it once on a finished change to the print code and
record the result on its issue.

## Measured 2026-10-23 in real Safari

Measured 2026-10-23 (morning) by a Claude Opus 5.5 measurer, with Russell's
go-ahead to drive Safari, on the same Mac and **Safari 26.6**, with
`safari_print.sh`, `serve.mjs`, `instrument.js` and `cancel.applescript` as
committed at be3bd67a3. The page is the same copy of ICS3U section 2,
`Concepts/Variables-and-Data-Types` (18 code blocks, 2 pictures), with the
branch's print script (`print.inline.ts` at be3bd67a3, bundled with esbuild,
minified) spliced into `postscript.js` in place of the built one. The "old"
row splices origin/dev's `print.inline.ts` (cdea887b5) the same way. Every
sheet was cancelled through System Events; nothing was printed or saved.
Times are milliseconds from the press, read from the page's own event log.
The shell's "sheet seen" time is not used: it polls System Events every
0.5 s and that call sometimes took several seconds.

| Bundle | Path, how reached | Held back | print() called | Sheet? | beforeprint (top window) | print() returned | Frame removed, status "" | afterprint (top window) |
|---|---|---|---|---|---|---|---|---|
| #576 | fallback, from home | pictures 1.5 s | +1,623, 0/2 pending, fonts loaded | **yes**, "Page 3 of 5" | +1,760 | on Cancel (+10,582) | +10,583 | +10,603 |
| #576 | fallback, from home | pictures 1.5 s | +1,599, 0/2 pending, fonts loaded | **yes**, "Page 3 of 5" | +1,617 | on Cancel (+16,333) | +16,334 | +16,349 |
| #576 | fallback, from home | nothing | +115, 0/2 pending, fonts loaded | **yes**, "Page 3 of 5" | +129 | on Cancel (+8,598) | +8,598 | +8,614 |
| #576 | fallback, from home | print faces (.otf) 1.5 s | +3,100, fonts loaded | **yes**, "Page 3 of 5" | +3,132 | on Cancel (+11,767) | +11,768 | +11,776 |
| #576 | Paged.js, direct | nothing | +275 | yes, "Page 3 of 6" | +291 | on Cancel (+8,610) | +8,611 | +8,627 |
| #576 | Paged.js, from home | nothing | +266 | yes, "Page 3 of 6" | +281 | on Cancel (+8,769) | +8,770 | +8,784 |
| old (cdea887b5) | fallback, from home | nothing | +88, **fonts loading** | **no** | never | at once (+88) | +89 | never |
| old, `KEEP=1` | fallback, from home | nothing | +74, fonts loading | yes, 32 ms after print() returned | +106 | at once (+74) | (suppressed) | +8,662, on Cancel |
| old, `KEEP=1` | fallback, from home | nothing | +77, fonts loading | yes, 36 ms after print() returned | +113 | at once (+77) | (suppressed) | +8,756, on Cancel |

What this settles:

- **The fallback prints in Safari now: 4 of 4** (2 with pictures held, 1 with
  nothing held, 1 with the print faces held), against **0 of 1** on the old
  code today and 0 of 3 the night before. Because the frame has settled before
  the call (fonts loaded, 0 pictures pending, every time), WebKit does not put
  the print off: `print()` blocks with the sheet up, exactly as on the
  Paged.js path. The status reads "Preparing to print…" until the sheet
  closes, then clears, and the frame is removed on Cancel.
- **The Paged.js path is unchanged: 2 of 2**, `print()` at +275 and +266 ms
  (the night before: +272 and +281).
- **The KEEP question is answered.** A print WebKit puts off (old code, frame
  kept, 2 of 2) DOES send beforeprint, on the TOP window, 32 to 36 ms after
  `print()` has returned, and afterprint on the top window when the sheet is
  cancelled. Neither event ever arrived on `frame.contentWindow`, in any of
  the 8 runs with a sheet. So the design's "neither event seen at the return:
  wait for beforeprint" branch hears a postponed print in Safari, and
  `words.couldNotPrepare` is not shown after a print that happened.
- **afterprint fires on Cancel, and after `print()` returns** (9 to 21 ms
  later, top window), in every run. For a print that blocks, beforeprint
  arrives inside `print()` (+14 to +137 ms after the call) and afterprint
  only after it returns, so the code's "beforeprint seen: restore at the
  return" branch is the one Safari takes.
- Not separable here: whether the status was cleared at beforeprint or at the
  return. The log's MutationObserver delivers only after the blocking
  `print()` returns, so both read as the moment of the return.
