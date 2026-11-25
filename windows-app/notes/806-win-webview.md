# #806 and #816 on Windows: the GeoGebra browser check in headless Edge

One run of `browser-checks/geogebra_applet.mjs` covers both issues; each has
its own subsection so it can be closed on its own. #913 is not in this file
(another writer measures it later). Nothing in product code, `scripts/`,
`browser-checks/`, `support/` or `contracts/` changed.

## The run (method, so it can be repeated)

- **When and where:** 2026-11-25, 16:56 to 16:58, the FIRST Windows VM
  (`Windows 11`, Windows 11 Pro ARM64 under Parallels, Plantoir `win-x64`
  under emulation), behind `vm-tools/runs/VM.lock`, parked on its dev
  snapshot 02 afterwards.
- **Tree:** `dev` 45be52fbf (synced by `winvm.sh sync`, then
  `refetch-runtime.ps1` and `build-app.ps1`, Debug, 0 errors).
- **Browser and runtime:** Microsoft Edge 158.0.4370.33, headless
  (`--headless=new`, as the check starts it); the runtime's Node v22.23.4
  and Python 3.14.10 (`windows-app\Vendor\runtime`).
- **Edge profile:** the check's own: `mkdtempSync(tmpdir(),
  "plantoir-geogebra-check-")` with `--user-data-dir=<that>\profile`, removed
  by the check when it ends. Confirmed after the run: 0 such folders left in
  `%TEMP%`.
- **Fixture:** a temp working folder under `%TEMP%` with EXC2O made by the
  built app's own `setup.ps1 --install-example`; `verify.sh`'s plants
  (about lines 3747 to 3916) written into it the same way: GeoGebra Fixture
  with its lines sketch and the contract's `geogebraFences.commands.cases`
  in order, GeoGebra Second with the 150-point lines sketch and the
  `material_id: https://www.geogebra.org/m/plantoirvrfy578` fence, Quiz
  GeoGebra; the saved copy of `plantoirvrfy578` seeded through
  `geogebra.SavedCopies(...).put` under the fence's key in
  `%LOCALAPPDATA%\Plantoir\builds\<working folder id>\EXC2O\.geogebra-cache`
  (the id as `preview.ps1` computes it), so no geogebra.org fetch was
  needed.
- **Build:** `preview.ps1 EXC2O 1 --build-only --non-interactive` with the
  bundled runtime: exit 0 in 62 s.
- **Site:** a clone of the built section's `public` folder, its `_headers`
  removed and written again by the publish's own two writers
  (`isolation_headers.publish_headers(site, "netlify")` then
  `netlify_badge.write_netlify_headers_file(site)`, as `verify.sh` about line
  6383), served on `[::1]` by the check itself.
- **Command** (from `C:\dev\plantoir`):
  `node browser-checks\geogebra_applet.mjs "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" <site> /Investigations/GeoGebra-Fixture.html /Discussions/GeoGebra-Second.html "<course>\Investigations\GeoGebra Fixture Lines.ggb" /Investigations/Quiz-GeoGebra.html`
  : exit 0 in 33 s.
- **Helper:** `vm-tools/guest/806-geogebra.ps1` (fe0035c), run by
  `vm-tools/806-turn.sh <log> <ref>`, which takes the lock, syncs, builds,
  runs the helper, parks and gives the lock back. Everything it made (the
  temp root, the builds folder) is removed by explicit path; it printed
  `cleaned: root True | builds folder True`. Log:
  `vm-tools/runs/806/turn2.log`.
- **An earlier turn (turn1, 16:49) did not run the check:** the helper's
  `_headers` writer, given as a `python -c` string, lost its quoting through
  PowerShell, so no `_headers` was written and the check stopped before
  starting a browser with
  `FAIL: <root>\site\_headers has no single ad-badge policy line - run write_netlify_headers_file on the site first`.
  That was the helper's fault, not Edge's; the helper now writes the two
  writers' call to a script file and prints its output. Turn 2 is the run.
- **The line as printed.** The console's code page dropped the `×` in the
  box sizes: the check writes `640×360`, the log reads `640360`. Nothing else
  differs. Verbatim:

```text wrap
OK: policy: the first sketch pressed for real, its card saying the contract's two lines while its engine was held (contrast 12.13 and 7.24 with the theme set to light, 16.27 and 13.28 with it set to dark; box 640360 under a 640360 card), the figure 433.58 px tall throughout (60 readings), then 1080 ms and 8,917,131 bytes in 16 requests, 2,835,242 gzipped (its loader frame under <html>, kept across both page changes), from commands 57 ms (4 of its lines refused, as the contract says; slider a dragged 3 to 0 (0 shades left), and 0 to 0 after a dialog removed the old way, the reset icon pressed for real on both, each back as it opened (5 objects and a = 3; A,B,f,m) and dragged again, 393 presses of Shift+Tab and Space while a 150-line sketch ran left all 150 of its points, and its reset brought back all 150), after a page change 280 ms, the geogebra.org sketch's saved copy 280 ms, back again 263 ms, on the quiz page 0 requests at load and 0 once the explanation was shown, its sketch 556 ms after the tap, the question's 265 ms, the same applet after a print, and the explanation's the same applet at 652408 after Start again and a second answer, 0 refusals, 0 requests off the site, beforeprint fired by printToPDF; isolated: the first sketch pressed for real, its card saying the contract's two lines while its engine was held (contrast 12.13 and 7.24 with the theme set to light, 16.27 and 13.28 with it set to dark; box 640360 under a 640360 card), the figure 433.58 px tall throughout (80 readings), then 964 ms and 8,918,491 bytes in 16 requests, 2,835,242 gzipped (its loader frame under <html>, kept across both page changes), from commands 56 ms (4 of its lines refused, as the contract says; slider a dragged 3 to 0 (0 shades left), and 0 to 0 after a dialog removed the old way, the reset icon pressed for real on both, each back as it opened (5 objects and a = 3; A,B,f,m) and dragged again, 388 presses of Shift+Tab and Space while a 150-line sketch ran left all 150 of its points, and its reset brought back all 150), after a page change 260 ms, the geogebra.org sketch's saved copy 260 ms, back again 256 ms, on the quiz page 0 requests at load and 0 once the explanation was shown, its sketch 575 ms after the tap, the question's 260 ms, the same applet after a print, and the explanation's the same applet at 652408 after Start again and a second answer, 0 refusals, 0 requests off the site, beforeprint fired by printToPDF; the sketch is on the site once (\Investigations\GeoGebra-Fixture-Lines.ggb)
```

## #806: the reset icon (items 11 and 12)

- **Item 11, OK in both phases** (plain Netlify policy and cross-origin
  isolated): "the reset icon pressed for real on both, each back as it opened
  (5 objects and a = 3; A,B,f,m) and dragged again".
- **Item 12, OK in both phases:** "393 presses of Shift+Tab and Space while a
  150-line sketch ran left all 150 of its points, and its reset brought back
  all 150" (policy); "388 presses ..." (isolated), the same result.
- The icon was where `geogebraFences.reset.icon` says in Edge: the press
  landed and the construction came back.
- Not possible in a VM: the issue's press on a touch laptop.
- **#806 can be closed on this run** for the Edge check it owed.

## #816: "opening" inside the box (item 13)

- **Item 13, OK in both phases:** the first sketch pressed with a real
  pointer, its card saying the contract's two lines while the engine's first
  request was held (`Fetch.requestPaused`, then `Fetch.continueRequest`):
  contrast 12.13 and 7.24 with the theme set to light, 16.27 and 13.28 with
  it set to dark; the applet's box 640×360 under a 640×360 card; the figure
  433.58 px tall throughout (60 readings policy, 80 isolated); then drawn in
  1080 ms (policy) and 964 ms (isolated). The fourth sketch's `.ggb` refused
  with `Fetch.failRequest` is part of the same item: the check prints no
  numbers for it, and the OK line (rather than a FAIL) is its result.
- The `Fetch` domain behaved in Edge as in Chrome for Testing.
- **#816 can be closed on this run** for the Edge check it owed.

## For PROGRESS

```text wrap
- #806, #816: browser-checks/geogebra_applet.mjs run once in headless Edge 158.0.4370.33 on the first Windows VM (dev 45be52fbf, Node v22.23.4), on verify.sh's GeoGebra fixture planted into EXC2O and built by preview.ps1 --build-only, a clone with the publish's own _headers served on [::1]: OK in both phases. Item 11 (reset icon, both sketches back as they opened: 5 objects and a = 3; A,B,f,m, dragged again), item 12 (393 and 388 Shift+Tab/Space presses while a 150-line sketch ran: all 150 points, and after reset), item 13 (opening words inside the card while the engine was held, contrast 12.13/7.24 light and 16.27/13.28 dark, figure 433.58 px throughout, a refused file back to its button). The touch-laptop press is not possible in a VM. Notes: windows-app/notes/806-win-webview.md.
```

## For documentation 12

To go under "Node 22, GeoGebra's engine and the npm audit on Windows", after
the 2026-10-28 run by hand:

```text wrap
**Measured again, 2026-11-25** (#806 items 11 and 12, #816 item 13). The first Windows VM (Windows 11 Pro ARM64 in Parallels, the app win-x64 under emulation), Edge 158.0.4370.33 headless, `dev` 45be52fbf's x64 Debug build and its runtime (Node 22.23.4, Python 3.14.10). A temp working folder with EXC2O from `setup.ps1 --install-example`, verify.sh's GeoGebra Fixture, GeoGebra Second (with the 150-point lines sketch) and Quiz GeoGebra plants, and the saved copy of `plantoirvrfy578` seeded in the course's `.geogebra-cache` under its fence's key, so nothing was asked of geogebra.org; built with `preview.ps1 EXC2O 1 --build-only` (62 s). `browser-checks/geogebra_applet.mjs`, unchanged, on a clone with the publish's own `_headers`, served on `[::1]`, with the check's own throwaway Edge profile: OK in 33 s, in both phases. The reset icon pressed for real on the commands sketch and the file sketch brought each back as it opened (5 objects and a = 3; A,B,f,m) and took a drag again; 393 presses of Shift+Tab and Space (388 isolated) while the 150-line sketch ran left all 150 points, and its reset brought back all 150. While the first sketch opened, with the engine's first request held, its card said the contract's two lines at contrast 12.13 and 7.24 in light and 16.27 and 13.28 in dark, the 640 x 360 card lay on the 640 x 360 box, and the figure stayed 433.58 px tall throughout; it drew in 1,080 ms (964 isolated). A sketch whose file was refused went back to its button. 0 refusals by the policy, 0 requests off the site. The helper is `vm-tools/guest/806-geogebra.ps1`; the touch-laptop press is not possible in a VM.
```
