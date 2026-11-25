# #806 and #816 on Windows: the GeoGebra browser check in headless Edge

One run of `browser-checks/geogebra_applet.mjs` covers both issues; each has
its own subsection so it can be closed on its own. #913's baseline
measurement and its candidate settings are at the end of this file ("#913:
what the preview's WebView2 contacts"), and part 2b, the two settings Russell
ruled on, after them ("#913 part 2b"). For #806 and #816 nothing in product
code, `scripts/`, `browser-checks/`, `support/` or `contracts/` changed.

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

# #913: what the preview's WebView2 contacts

Part 2a: the BASELINE only, on this branch at 22ae99c4c (`dev` 45be52fbf plus
the #806 and #816 notes; no product code differs from `dev`). Nothing in
product code changed in part 2a. The settings, their after-measurement and
their must-fail are part 2b, below ("#913 part 2b").

## The measurement

### Method (so it can be repeated)

- **Machine:** the FIRST Windows VM (`Windows 11`, Windows 11 Pro ARM64 in
  Parallels, Plantoir `win-x64` under emulation), behind
  `vm-tools/runs/VM.lock`, parked on its dev snapshot 02 after each turn.
- **Build:** `winvm.sh sync issue/806-win-webview` (22ae99c4c), then
  `refetch-runtime.ps1` and `build-app.ps1` (Debug, 0 errors).
- **Runtime:** the `msedgewebview2.exe` that ran for the preview reported
  ProductVersion **158.0.4370.33** on every run (read from the running
  process's file, the same number `GetAvailableBrowserVersionString` gives
  for the Evergreen runtime; that API itself was not called).
- **Driver:** `vm-tools/guest/913-measure.ps1` (vm-tools e7acdd5), run by
  `vm-tools/913-turn.sh <log> <ref> <steps>`; system half
  `vm-tools/guest/913-dns.ps1` (2ac5ae7, run as SYSTEM). Logs:
  `vm-tools/runs/913/turn2.log` (runs 1 and 2), `turn3.log` (run 3).
- **Profile:** a throwaway root under `%TEMP%` (`913c`, then `913d`) holding
  `--state-dir <root>\state` (so `WEBVIEW2_USER_DATA_FOLDER` is
  `<root>\state\WebView2`, new and empty on a first start, checked and
  printed) and a working folder `<root>\work` with EXC2O from the built app's
  own `setup.ps1 --install-example`. Nothing of a real course, no class list,
  no name.
- **Run:** `Plantoir.exe --state-dir <root>\state --auto-preview EXC2O 1`
  (the Preview button's code path).
- **Capture:** Chromium's net-log, turned on for the measurement only by
  `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--log-net-log=<root>\netlog-<label>.json --net-log-capture-mode=Default`
  in the launching shell (removed from the shell right after the start; no
  product code). Both flags are on Microsoft's flags page
  (https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/webview-features-flags);
  the format is Chromium's
  (https://www.chromium.org/developers/design-documents/network-stack/netlog/).
- **System half:** the Windows DNS Client operational log
  (`Microsoft-Windows-DNS-Client/Operational`, event 3006, a query asked)
  turned on and emptied before each run, then counted for the run's
  `msedgewebview2.exe` process ids only, then emptied and turned off.
- **Window (fixed before the first run, the same on every run):** from the
  app's start to **300 s after the preview pane reported its page loaded**
  (under `--state-dir` the app writes `loaded <status> <address>` to the
  Open in Browser button's ItemStatus on NavigationCompleted; the driver
  waits for `loaded 200` through UI Automation and never prints the
  address); then the app's window is closed as a teacher closes it and the
  browser processes are waited out, so the net-log covers the browser's whole
  life.
- **Reduction, in the VM:** the runtime's own Python reads the net-log and
  prints only: hosts, lookups asked and made, URL requests by scheme and
  method, uploads with their body size, whether a `Referer` beyond a bare
  origin or a local address in a query string rode on a request off the
  computer (yes or no), the request PATH for hosts off the computer
  (Microsoft's and the site's CDN paths, never the local site's, never a
  query), and TCP connection attempts by host and port. The raw net-log is
  deleted in the VM by explicit path (`raw net-log deleted: True` on each
  run), and the root and the preview's build folder are removed after the
  turn (`cleaned: True`, `build folder removed: True`).

### Runs on 22ae99c4c (runtime 158.0.4370.33, window 300 s from the page)

**Run 1, first start (empty profile)**, root `913c`: app 17:03:34, page shown
17:04:59 (85 s), window ended 17:09:59, net-log 4,056 events.

| host | where | lookups asked / made | URL requests | uploads | page address on it | path (off the computer) | what it is |
|---|---|---|---|---|---|---|---|
| 127.0.0.1 | this computer | 2 / 0 | http GET 8 | 0 | n/a | n/a | the preview's own server (the site) |
| localhost | this computer | 0 / 0 | ws GET 1 | 0 | n/a | n/a | the preview's live-reload socket |
| cdnjs.cloudflare.com | off | 3 / 1 | none | 0 | no | none | the site's (a lookup only, no request in the window) |
| fonts.googleapis.com | off | 6 / 1 | https GET 1 | 0 | no (Referer: bare local origin) | `/css2` | the site's (Google Fonts) |
| fonts.gstatic.com | off | 6 / 1 | https GET 2 | 0 | no (bare origin) | `/s/ibmplexmono/v23/….woff2` | the site's (Google Fonts) |
| config.edge.skype.com | off | 3 / 1 | https GET 2 | 0 | no (no Referer, no local address in a query) | `/config/v1/Edge/158.0.4370.33` | Edge's experiment and configuration fetch (named from its path; the WebView2 policy page describes the Experimentation and Configuration Service but does not name its host) |
| edge.microsoft.com | off | 9 / 3 | https POST 8 | 8 (13,807 bytes) | no | `/componentupdater/api/v1/update` | the browser's component updater (named from its path; no Microsoft WebView2 page describes it) |
| wpad | off (local network name) | 6 / 6 | none | 0 | no | none | proxy auto-detection (WPAD; Chromium's, not described on Microsoft's WebView2 pages) |

TCP connection attempts: this computer:8081 6, this computer:9081 2, an
address off the computer:443 5 (the reducer did not map those to names).

**Run 2, second start on the same throwaway profile**, root `913c`: app
17:10:30, page shown 17:12:58 (148 s), window ended 17:17:58, net-log 2,379
events.

| host | where | lookups asked / made | URL requests | uploads | page address on it | path (off the computer) |
|---|---|---|---|---|---|---|
| 127.0.0.1 | this computer | 2 / 0 | http GET 7 | 0 | n/a | n/a |
| localhost | this computer | 0 / 0 | ws GET 1 | 0 | n/a | n/a |
| cdnjs.cloudflare.com | off | 3 / 1 | none | 0 | no | none |
| fonts.googleapis.com | off | 4 / 1 | https GET 1 | 0 | no | `/css2` |
| fonts.gstatic.com | off | 6 / 1 | https GET 1 | 0 | no | `/s/ibmplexmono/v23/….woff2` |
| edge.microsoft.com | off | 2 / 1 | https POST 1 | 1 (5,239 bytes) | no | `/componentupdater/api/v1/update` |
| wpad | off (local network name) | 5 / 5 | none | 0 | no | none |

TCP connection attempts: this computer:8081 4, this computer:9081 2, an
address off the computer:443 1. **`config.edge.skype.com` was not contacted on
the second start** within the window.

DNS Client log, run 2 (17:10:30 to 17:18:11, 6 WebView2 process ids): names
asked by a WebView2 process: `wpad` 5. Queries by other processes in the
window (not named): 19. (Run 1's DNS half was lost: the reduction read the
process ids wrongly and printed 0 ids; fixed in 2ac5ae7 and run again as run
3.)

Run 3 (a second first start, root `913d`, `vm-tools/runs/913/turn3.log`) was made only for the DNS half of a first start; in brief, as printed: page shown 89 s after start; the same hosts as run 1, with `config.edge.skype.com` https GET 2 and `edge.microsoft.com` https POST 5 (9,831 bytes), no page address on any; DNS Client log (8 WebView2 process ids): `wpad` 6 and nothing else.

### What the measurement says, and what it does not

- **No request off the computer carried a page address of the teacher's
  site** in any run: no `Referer` beyond a bare origin and no local address in
  a query string. The bare local origin (`http://127.0.0.1:<port>`) did ride
  as `Referer` on the site's own Google Fonts stylesheet request in run 1.
- **Microsoft's contacts on a first start:** the configuration service (2
  GETs) and the component updater (8 POSTs, 13,807 bytes of request bodies);
  **on a second start:** the component updater only (1 POST, 5,239 bytes).
  The bodies' contents were not captured (Default capture mode records no
  body), so what they carry beyond their size is not measured.
- **The DNS Client log saw only `wpad`** from the WebView2 processes, while
  the net-log made lookups for every host above: the browser's other lookups
  did not reach the Windows DNS Client's log as a WebView2 process's query,
  so that log is not a complete second witness. A packet capture (`pktmon`
  filtered to the WebView2 processes) was not run.
- **Not measured:** SmartScreen (no SmartScreen host appeared in either log;
  the pages shown were on 127.0.0.1, and absence in a 5-minute window is not
  proof it never sends); the crash reporter (no crash happened, so nothing
  was sent; its sending is outside the net-log); Windows diagnostic data for
  WebView2 (sent by Windows' own services, outside both logs); the WebView2
  Runtime's own updater (Microsoft Edge Update, a separate service); anything
  after the window; a teacher clicking a link to a site off the computer.
- **An earlier run, not counted here:** on 2026-11-21 (2f50d1fa3, turn1.log)
  the same driver ran with two faults (the page-shown status was looked for
  under the wrong automation id, so the window ran 12 minutes from start, and
  the process ids were not found). It printed the same hosts, and one run with
  the `ExperimentationAndConfigurationServiceControl` policy set to 0 in HKLM
  printed no `config.edge.skype.com` row. That is an indication for the next
  writer, not a proof: it must be measured again by this method (invariant
  3).

## Candidate settings

Each read on Microsoft's page on 2026-11-25. "Reachable" says where it can be
given: per view (a `CoreWebView2Settings` value, in
`SectionDetailView.xaml.cs`), per environment (a
`CoreWebView2EnvironmentOptions` value passed to `EnsureCoreWebView2Async(env)`,
also in `SectionDetailView.xaml.cs`), process-wide (an environment variable set
in `Program.cs`), or per machine or user (a registry policy).

| contact | documented setting | page | reachable | what else it turns off |
|---|---|---|---|---|
| `config.edge.skype.com` (first start; 2 GETs) | WebView2 policy `ExperimentationAndConfigurationServiceControl` = 0 (RestrictedMode), DWORD under `SOFTWARE\Policies\Microsoft\Edge\WebView2` | https://learn.microsoft.com/en-us/deployedge/microsoft-edge-webview-policies | **per machine or user only** (a registry policy with no per-app value name; an IT administrator's setting, and `HKCU\Software\Policies` is normally not writable by a standard user: not tried). No documented browser argument or environment option exists for it. | every WebView2 app for that machine or user; Microsoft's configuration payload too, which "may also contain a list of actions to take on certain domains for compatibility reasons" (for example a User Agent override); "Microsoft doesn't recommend this setting". |
| `edge.microsoft.com/componentupdater` (8 POSTs first start, 1 second start) | **none found on Microsoft's WebView2 pages.** The Edge update policies (`UpdatesSuppressed`, the enterprise page) govern the runtime's updater, not this in-browser component updater. | https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/enterprise ; the flags page lists no component-update flag | n/a | n/a: the only route would be a Chromium switch Microsoft does not list (option A in the brief: may stop working silently in any runtime update). |
| `wpad` (5 to 6 lookups each start) | `no-proxy-server` or `proxy-server` on the flags page, which says "Apps in production shouldn't use WebView2 browser flags" | https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/webview-features-flags | process-wide (`WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS`) or per environment (`AdditionalBrowserArguments`) | a school network that hands out its proxy by WPAD: the site's fonts and cdnjs would stop loading. It asks the local network for a proxy; it sends nothing to Microsoft. |
| SmartScreen (not seen; not measured) | `CoreWebView2Settings.IsReputationCheckingRequired` = false | https://learn.microsoft.com/en-us/dotnet/api/microsoft.web.webview2.core.corewebview2settings.isreputationcheckingrequired and https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/data-privacy | **per view**, but applied to all WebViews on the same user data folder (on if any view leaves it true) | Microsoft Defender SmartScreen's check of pages and downloads shown in the preview. The data-privacy page: "If you don't disable SmartScreen, you must provide notice to all users that your software includes Microsoft Defender SmartScreen, and collects and sends the user's information to Microsoft". |
| crash reports (not seen; not measured) | `CoreWebView2EnvironmentOptions.IsCustomCrashReportingEnabled` = true ("Windows won't send crash data to the Microsoft endpoint") | https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/data-privacy and https://learn.microsoft.com/en-us/dotnet/api/microsoft.web.webview2.core.corewebview2environmentoptions | **per environment** (needs the preview to create its own environment; environments that differ cannot share a browser process: "WebView creation fails with `HRESULT_FROM_WIN32(ERROR_INVALID_STATE)` if the specified options does not match", from the `CreateCoreWebView2EnvironmentWithOptions` page) | nothing a teacher sees; Microsoft no longer gets the preview's crash dumps. |
| Windows diagnostic data for WebView2 (not measured) | none for the app: "governed by the ... Diagnostic data setting on Windows ... as a centralized switch"; required data is collected regardless | https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/data-privacy | the teacher's own Windows setting only | n/a: can only be documented. |

**Where a process-wide variable meets the Planning tab (790b).** From the
`CreateCoreWebView2EnvironmentWithOptions` page
(https://learn.microsoft.com/en-us/microsoft-edge/webview2/reference/win32/webview2-idl):
"If `additionalBrowserArguments` is specified in environment variable or in
the registry, it is appended to the corresponding values in
`CreateCoreWebView2EnvironmentWithOptions` parameters", while the user data
folder variable REPLACES the option. So an arguments variable set in
`Program.cs` would JOIN the Planning tab's own `AdditionalBrowserArguments`
(its dead proxy), never replace it; a proxy argument in that variable would
however be appended after the Planning tab's, which is a reason not to put
any proxy flag there. Since no contact above has a documented browser
argument, nothing process-wide is proposed.

**Recommendation.** Build `IsCustomCrashReportingEnabled = true` on the
preview's own environment (documented, costs the teacher nothing; now
reachable, since lane D's `SectionDetailView.xaml.cs` is merged), and prove it
by the measurement as far as a measurement can (it changes no contact in a
run without a crash, so its proof is the option read back from the
environment plus the documented behaviour; say so). `IsReputationCheckingRequired`
is documented and reachable per view but costs a security check, so it is
Russell's (turn off, or tell teachers as Microsoft requires).
`config.edge.skype.com` (first start only), the component updater (every
start), `wpad` and Windows diagnostic data can only be documented: no setting
on Microsoft's WebView2 pages turns them off for one app.

# #913 part 2b: the two settings, and what stays

Russell's rulings on #913 (2026-11-25): SmartScreen OFF on the preview's view,
crash reporting to Microsoft OFF on the preview's own environment; the
experiment configuration, the component updater and proxy auto-detection NOT
touched (no policy, no flag) and documented plainly. **#913 is done** with
this part, apart from the privacy wording, which is shared and is the
director's (below).

## What was built

- `windows-app/Plantoir/Views/PreviewBrowserEnvironment.cs` (new): one
  environment per process, made with `CoreWebView2EnvironmentOptions {
  IsCustomCrashReportingEnabled = true }` through
  `CoreWebView2Environment.CreateWithOptionsAsync(null, null, options)` (the
  user data folder still comes from `WEBVIEW2_USER_DATA_FOLDER`, set in
  `Program.Main`, which overrides the folder argument); a failure is not kept,
  so the next load asks again. `ApplyViewSettings` sets
  `core.Settings.IsReputationCheckingRequired = false`. The code comment cites
  both Microsoft pages.
- `SectionDetailView.xaml.cs`: `EnsurePreviewBrowserAsync()` is now the only
  place the pane's browser is made; `NavigateAsAppAsync` and `ReloadAsAppAsync`
  call it, so the settings are given before the first page is asked for.
- **Failure path:** if the environment cannot be made, the exception reaches
  the same `catch` as a failed `EnsureCoreWebView2Async()` did before, the
  diagnostic log gets `NavigateAsAppAsync: <message>` (or `ReloadAsAppAsync:`),
  and the pane shows no page, exactly as before; the teacher is told nothing
  new. No wording changed.
- **Other WebView2 views:** on `dev` (66c9853a8) the preview is the only
  WebView2 in the app (`SectionProblemsView.cs` draws over it and makes
  none). The Planning tab (`origin/issue/790b-planning-tab`, not on `dev`,
  not changed) makes its own environment on its own user data folder
  (`LocalPagesEnvironment.cs`); neither setting reaches it from here, since
  `IsReputationCheckingRequired` is shared only by views on the SAME folder and
  `IsCustomCrashReportingEnabled` is an option of each environment. Both would
  apply there the same way (its `CoreWebView2EnvironmentOptions` and each of
  its views) if Russell wants them; that is the Planning tab writer's.

## Tests

`windows-app/Plantoir.Tests/PreviewBrowserPrivacySourceTests.cs` (3 facts,
source text with comments stripped): the environment's options carry
`IsCustomCrashReportingEnabled = true` and are passed to
`CreateWithOptionsAsync`; `ApplyViewSettings` sets
`IsReputationCheckingRequired = false`; `EnsurePreviewBrowserAsync` passes
`PreviewBrowserEnvironment.GetAsync()` and applies the view settings, and it
is the only `EnsureCoreWebView2Async(` in the file. Run in the first VM by
`vm-tools/guest/913-tests.ps1` with the 19 other classes that read
`SectionDetailView.xaml.cs` as source text, each whole: **295 of 295 passed**
on 4792bb1a7 (`vm-tools/runs/913/turn4.log`). No contract file is involved.

## The measurement, after (same method and window as the baseline)

`vm-tools/runs/913/turn4.log`, branch at 4792bb1a7 (`dev` 66c9853a8 merged in),
runtime `msedgewebview2.exe` 158.0.4370.33, net-log in Default mode through
`WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS` in the launching shell, the DNS Client
log for the run's WebView2 process ids, window 300 s from the page shown,
throwaway root `913e` (removed: `cleaned: True`, `build folder removed:
True`, `raw net-log deleted: True` on both runs).

**After, first start (empty profile):** page shown 105 s after start, 4,094
events.

| host | where | lookups asked / made | URL requests | uploads | page address on it | path (off the computer) |
|---|---|---|---|---|---|---|
| 127.0.0.1 | this computer | 2 / 0 | http GET 8 | 0 | n/a | n/a |
| localhost | this computer | 0 / 0 | ws GET 1 | 0 | n/a | n/a |
| cdnjs.cloudflare.com | off | 3 / 1 | none | 0 | no | none |
| fonts.googleapis.com | off | 6 / 1 | https GET 1 | 0 | no (Referer: bare local origin) | `/css2` |
| fonts.gstatic.com | off | 6 / 1 | https GET 2 | 0 | no (bare origin) | `/s/ibmplexmono/v23/….woff2` |
| config.edge.skype.com | off | 3 / 1 | https GET 2 | 0 | no (no Referer) | `/config/v1/Edge/158.0.4370.33` |
| edge.microsoft.com | off | 9 / 3 | https POST 8 | 8 (13,812 bytes) | no (no Referer) | `/componentupdater/api/v1/update` |
| wpad | off (local network name) | 6 / 6 | none | 0 | no | none |

DNS Client log, 6 WebView2 process ids: `wpad` 6 and nothing else.

**After, second start (same profile):** page shown 33 s after start, 2,566
events.

| host | where | lookups asked / made | URL requests | uploads | page address on it | path (off the computer) |
|---|---|---|---|---|---|---|
| 127.0.0.1 | this computer | 2 / 0 | http GET 7 | 0 | n/a | n/a |
| localhost | this computer | 0 / 0 | ws GET 1 | 0 | n/a | n/a |
| cdnjs.cloudflare.com | off | 3 / 1 | none | 0 | no | none |
| fonts.googleapis.com | off | 4 / 1 | https GET 1 | 0 | no | `/css2` |
| fonts.gstatic.com | off | 6 / 1 | https GET 1 | 0 | no | `/s/ibmplexmono/v23/….woff2` |
| edge.microsoft.com | off | 2 / 1 | https POST 1 | 1 (5,238 bytes) | no (no Referer) | `/componentupdater/api/v1/update` |
| wpad | off (local network name) | 5 / 5 | none | 0 | no | none |

`config.edge.skype.com` not contacted within the window. DNS Client log, 6
WebView2 process ids: `wpad` 5 and nothing else.

**Against the baseline (runs 1 and 2):** the same hosts, the same request
kinds and counts; the component updater's bodies 13,812 against 13,807 bytes
(first) and 5,238 against 5,239 (second). The site's own hosts (Google Fonts,
cdnjs) were still reached; the page loaded (`loaded 200`) on the new
environment both times.

## What a run could not show

Neither setting changes anything a run of this kind can see, and no
measurement of either is claimed:

- **SmartScreen:** no SmartScreen host appeared in any baseline or after run
  (the pages shown are on 127.0.0.1), so there was no row to make disappear.
  It rests on the source test and on Microsoft's page
  (https://learn.microsoft.com/en-us/dotnet/api/microsoft.web.webview2.core.corewebview2settings.isreputationcheckingrequired).
- **Crash reports:** no crash happened in any run, and the crash reporter's
  sending is outside the net-log, so nothing was sent either way. It rests on
  the source test and on Microsoft's page ("Windows won't send crash data to
  the Microsoft endpoint",
  https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/data-privacy).
- **The must-fail is therefore the test's, not a measurement's** (below). A
  scratch build with the settings removed would print the same table as the
  baseline and prove nothing, so it was not run.
- Still not measured, as in the baseline: the request bodies' contents (only
  their sizes), Windows diagnostic data, the WebView2 Runtime's own updater
  (Microsoft Edge Update), anything after the 300 s window, a teacher
  following a link off the computer.

## Must-fail lines

Scratch branch `scratch/913-mustfail` (864d4e74e, local only, never pushed):
`IsCustomCrashReportingEnabled = true` taken out of the options, the
`IsReputationCheckingRequired` line removed, and `EnsurePreviewBrowserAsync`
back to a bare `Preview.EnsureCoreWebView2Async()`. Same 20 classes in the
VM: 292 passed, 3 failed, each on its own line, as printed:

```text wrap
Failed Plantoir.Tests.PreviewBrowserPrivacySourceTests.ThePreviewsEnvironmentKeepsCrashReportsOnTheComputer: Assert.Matches() Failure: Pattern not found in value / Regex: "new\\s+CoreWebView2EnvironmentOptions\\s*\\{[^}]*\" / Value: "{\r\n        if (_creating is { IsFaulted: false, "
Failed Plantoir.Tests.PreviewBrowserPrivacySourceTests.ThePreviewsViewHasSmartScreenTurnedOff: Assert.Matches() Failure: Pattern not found in value / Regex: "\\.Settings\\.IsReputationCheckingRequired\\s*=\\s" / Value: "{\r\n    }"
Failed Plantoir.Tests.PreviewBrowserPrivacySourceTests.EveryPlaceThePanesBrowserIsMadeUsesBoth: Assert.Matches() Failure: Pattern not found in value / Regex: "Preview\\.EnsureCoreWebView2Async\\(\\s*await\\s+P" / Value: "{\r\n        await Preview.EnsureCoreWebView2Async"
```

## Review 1 answered (2026-11-25)

Review: `vm-tools/briefs/2026-11-25-913-review-1.md`.

- MEDIUM 1, documentation 12: "with no Referer and no local address in a query: no page address went with them" (both paragraphs) became "The runs checked each request's address, its query string and its Referer, and found no page address there." The updater paragraph adds "The request bodies were not captured, only their sizes, so what they carry is not known."
- MEDIUM 1, privacy text: "Neither request carries the address of a page you are previewing." became "We checked the address of each of those requests, the extra details added to that address, and the address the request said it came from, and found the address of a page you were previewing in none of them. We did not see what the update requests sent, only how much." The "Where it lives" note on the help page now says the same, not "no page address went out".
- MEDIUM 2, privacy text: "the first time Preview opens ... each time Preview opens" became "In our tests, Plantoir was started twice with one preview each and watched for five minutes after the page opened: on the first start the engine fetched Edge's settings from Microsoft, and on the second start it did not within those five minutes; on both starts it asked Microsoft whether its built-in parts need an update."
- LOW 1 (notes only): "a crash's dump stays in the user data folder rather than going to Microsoft" became "crash reports are not sent to Microsoft" (Data and privacy in WebView2: "Windows won't send crash data to the Microsoft endpoint"). The code comment in `PreviewBrowserEnvironment.cs` was changed in 3eb916147 to quote the same Microsoft sentence.
- LOW 2: "Your Windows diagnostic data setting still applies, as it does to every app." removed.
- LOWs 3 and 4 (as numbered in this round's brief: the source test's order and the shared profile folder) not answered here.
