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
