# Screenshots on plantoir.app

How screenshots are captured, processed, and served across platforms on
[plantoir.app](https://plantoir.app).

---

## 1. Overview & Architecture

Every screenshot on plantoir.app is photographed directly from the real
application and live Quartz class websites in both **Light** and **Dark**
appearance — no synthetic mockups, placeholder illustrations, or headless
browser approximations.

Furthermore, **screenshots are platform-aware**:
- Visitors browsing from a **Windows** computer see native Windows WinUI 3
  screenshots.
- Visitors browsing from **macOS**, iOS, Linux, or Android see native macOS
  SwiftUI screenshots.

```
                  ┌────────────────────────────────────────┐
                  │          website/shots.json            │
                  │  (id, alt text, caption, shot type)    │
                  └──────────────────┬─────────────────────┘
                                     │
             ┌───────────────────────┴───────────────────────┐
             ▼                                               ▼
   ┌───────────────────┐                           ┌───────────────────┐
   │  macOS Capture    │                           │  Windows Capture  │
   │  (capture.py)     │                           │(capture_windows.py│
   │  XCUITest + Safari│                           │ Plantoir.exe CLI) │
   └─────────┬─────────┘                           └─────────┬─────────┘
             │                                               │
             ▼                                               ▼
   site/img/<id>-light.png                         site/img/<id>-windows-light.png
   site/img/<id>-dark.png                          site/img/<id>-windows-dark.png
   site/img/<id>-light.webp                        site/img/<id>-windows-light.webp
   site/img/<id>-dark.webp                         site/img/<id>-windows-dark.webp
             │                                               │
             └───────────────────────┬───────────────────────┘
                                     │
                                     ▼
                          ┌─────────────────────┐
                          │  website/build.py   │
                          │  (picture_element)  │
                          └──────────┬──────────┘
                                     │
                     ┌───────────────┴───────────────┐
                     ▼                               ▼
       <figure class="...-mac">        <figure class="...-windows">
       (Dark/Light <picture> & WebP)   (Dark/Light <picture> & WebP)
```

---

## The one rule: only macOS's own window capture, kept whole

Russell's rule, stated more than once and last on 2026-10-03/04: **every picture
on plantoir.app is made ONLY with macOS's built-in window capture** —
`screencapture -x -l <window id>`, never `-o` — which returns the window with
its own rounded corners and its NATURAL shadow, transparent round them, taken
while its app is active (an inactive window's shadow is smaller and lighter).
Figures made of several windows are built from those captures WHOLE, with
`Image.alpha_composite` so overlapping shadows blend:

- no crop that passes through a window or its shadow, no trim, and no
  re-rounding of a corner;
- no mask, corner or shadow drawn, generated, blurred or retouched — the
  shadow is exactly what `screencapture` wrote;
- no scaling of a Mac capture: it is served at its own pixel size (#434;
  until 2026-10-04 every picture was scaled to 1700 px, which gave pictures of
  different widths different shadows);
- if a figure must not show the browser's toolbar, the picture is taken in a
  window that never had one (`website/shots/webwindow.swift`: a class site in
  a plain macOS window drawn by WebKit), never cut out of a Safari capture.

The code that broke this is gone, with no fallback and no flag:
`composite.py`'s `rounded()`, `without_chrome()` and shape-drawn
`with_shadow()` (they cut Safari's toolbar off the `colour-schemes` and
`light-and-dark` parts and painted 18 px corners back on — the drawn corners
Russell saw on the live site), and the schedule scene's banner trim, which
cut the notification out of Notification Center's window and drew its
corners. A banner is now cropped only to the edge of its own shadow, which
never passes through the card.

The page adds none either: `.shot img` in `assets/style.css` has no
`border-radius`, no `box-shadow` and, since #434, no filter — the shadow is
the capture's own. Only a Windows capture (an img with `data-win-src`, on a
Windows visitor's page) keeps the `drop-shadow` filter, because those arrive
without a shadow of their own. (Until 2026-10-04 that filter was on every
shot; until 2026-09-27 a 10px rounded box-shadow was drawn round every shot,
and round each PAIR as one rectangle.)

**The shadow gate (#434):** `test_native_corners.py` also fails on any Mac
picture whose outermost 3 px carry alpha above 1 (a cut-off shadow; a whole
capture carries a few isolated pixels of alpha 1 there, its dithering), and
on any single-window picture whose shadow margin — edge to first opaque
pixel — is not `shadow.NATIVE_MARGINS`, the margin of an ACTIVE window's
`screencapture -x -l` at 2x: (112, 76, 112, 148) px left, top, right,
bottom, measured 2026-10-04 on Safari, Plantoir, Obsidian, iTerm and the
page window alike. `hero` and `schedule` are judged on their edge only (a
padded canvas; a banner above the window), and `site-phone` is a device
frame, not a window.

**The gate:** `website/shots/test_native_corners.py` opens every picture the
pages show a Mac visitor (from `shots.json` and the pages, PNG and WebP) and
fails on a corner that is square, or drawn tighter than any real macOS
window (radius under 0.0155 of the window's height; `corners.py` has the
measurements). `capture.py` runs the same check on each scene picture in
staging, so a failing one never reaches `site/img`, and over every picture
at the end of a run, exiting 1 and naming what not to commit. It failed on
the committed `colour-schemes` and `light-and-dark` before they were
retaken, and passes after. **It is a guard, not a proof:** a mask drawn at a
window's REAL radius reads like the real curve, which is why the code that
drew them is gone rather than merely checked. `schedule` was the one such picture
(its banner masked at the measured radius in 2e11471d); it was retaken the
same day from a native capture of Notification Center's window, and
`DRAWN_BUT_NOT_DETECTABLE` in the test is empty and must stay so.

**Windows keeps the same rule for every picture (#380, finished 2026-10-04).**
Every `-windows` picture is ONE real window photographed by
`website/shots/windowshot/` — a small program that asks
Windows.Graphics.Capture for one window by its handle and writes the frame
whole. The frame carries the window's own alpha, so the corners Windows 11
rounds are already transparent: nothing is cropped, masked or drawn, and a
single-window shot carries no shadow of its own (the page's stylesheet gives
a Windows single-window picture its drop-shadow; `website/test_shot_shadows.py`).
The figures (`hero`, `colour-schemes` and its dark version, `light-and-dark`,
`two-maps`) are such captures placed whole. **`schedule` on Windows is the
Schedule a deploy sheet in its window, alone** (Russell's ruling, 2026-10-04):
Windows' notification is not a window Windows.Graphics.Capture can be given.
Measured on Windows 11 26200 during a real scheduled deploy's toast
(2026-10-04 12:07, with #448's fix, which makes the toast appear at all),
polling every 0.3 s for nine minutes: EnumWindows showed no new, visible or
uncloaked window; FindWindowEx by `Windows.UI.Core.CoreWindow` and UI
Automation's desktop root showed no notification. A screen crop is what the
rule forbids. Its Windows alt (`windowsAlt`) says what the picture shows and
that Windows tells the teacher with a notification once the deploy has run;
the shared caption is true of both pictures, so it is not swapped. The gate judges every
`-windows` picture (`corners.images_the_pages_show(..., include_windows=True)`
in `test_native_corners.py` and in `build.py`'s `native_corners_refusal`);
the interim list of three retaken figures, `WINDOWS_FIGURES_RETAKEN`, is gone.

What was measured, on this project's Windows PC (Intel i5-8365U, UHD 620,
Windows 11 build 26200, a 3840-wide remote session at 200%):

- A window's corner pixels come back at alpha 7 to 40, rising to 255 along an
  antialiased curve; the 1 DIP border Windows 11 draws round a window is in
  the frame at about alpha 113 and is kept, being part of the window.
- A window that is not repainting sends ONE frame and then nothing, so
  `windowshot` keeps the newest frame that arrives within 0.7 s of the first
  rather than waiting for a third (the first version did, and timed out).
- The corner radius is 8 DIPs whatever the window's size, so as a fraction of
  the window's height it runs from 0.0142 (640 DIPs tall) down to 0.0083 for
  a page window 848 DIPs tall scaled to 1700 px — below the mac's floor of
  0.0155. `corners.py` therefore judges a `-windows` picture against
  `SMALLEST_REAL_WINDOWS_RADIUS` (0.004), and for those pictures the gate
  catches a SQUARE corner and little else: the masks this replaced measured
  0.0099 to 0.0128, inside the real range. The rule is kept by the code that
  no longer draws.

How each kind of Windows picture is made (`website/README.md`, "Capturing on
Windows", has the commands):

- **The class sites** are Edge `--app=<address>` windows — a title bar and the
  page — the counterpart of the mac's `webwindow.swift`, driven over the
  DevTools protocol in the very window photographed. An anchor is scrolled to
  only once the page has stopped moving, then CHECKED near the top of the page
  column (the mac's rule from its anchored-scenes branch, read from the page
  instead of by OCR), so `site-sch3u-chemistry` shows the reactions and ions
  and `site-sch3u` the flowchart. Measured on the first run: an `--app` window
  on a fresh profile drew its title bar dark and the page LIGHT in Windows'
  dark mode (`--force-dark-mode` changed nothing), so the scheme is handed to
  the page and the page loaded again with scroll restoration off — a plain
  reload kept its scroll and the site's own opening scroll ran again, putting
  `site-mcv4u` 300 px lower in one scheme than the other. `site-phone` is a
  narrow Edge window (390 x 844 DIPs), captured whole: Windows has no phone
  simulator, and the picture says so by being a window.
- **The app's windows** are staged by the app: `Plantoir.exe --stage-scene`
  (`MarketingShotCapturer.cs`) drives a REAL window to the caption's state and
  holds it; `app_scenes_windows.py` photographs it. The preview, the progress
  and the two coverage maps are real previews built by the launchers; the
  assistant's plan is the app's own answer to a promise-card phrasing; the
  schedule's picture is the real Schedule a deploy sheet (its notification
  cannot be captured whole, above). Rejected: `RenderTargetBitmap` of a window's content (what
  `--capture-marketing-shots` did until #380 — no window at all, so square
  corners and no title bar, and the assistant's bubbles and buttons typed by
  hand), and photographing the desktop region a window covers (desktop pixels
  in the corners, the reason a mask was ever drawn).

Rejected for the capture itself: `PrintWindow` and a screen-region grab (both
hand back a rectangle with the desktop in the corners, which is why the mask
existed); a Python binding for Windows.Graphics.Capture (none installs on the
Python 3.14 this PC runs, and the mac's helpers are small native programs
too).

**Words that fit only the Mac picture.** Only the image is swapped for a
Windows visitor, never the caption, so a Windows picture must show what the
shared words say. Where the words name something only a Mac has — `schedule`'s
alt says "a macOS notification" — `shots.json` carries a `windowsAlt`, which
`build.py` writes as `data-win-alt` and `layout/base.html` swaps in exactly as
it swaps the image. A Mac visitor's words never change.

---

## 2. The Capture Pipelines

### macOS Capture (`website/shots/capture.py`)

The macOS capture harness is driven by Python and Xcode UI tests:

```bash
python3 website/shots/capture.py            # captures app + published sites
python3 website/shots/capture.py --app      # app windows only
python3 website/shots/capture.py --sites    # class websites only
python3 website/shots/capture.py --scenes   # the v1.4.0 scenes, in ~/Plantoir Marketing
```

- **App Windows**: Driven by `MarketingScreenshotTests.swift` in
  `mac-app/Tests/QuartzTeachersUITests/`, and photographed with macOS's own
  window capture (`screencapture -x -l <window number>`, shadow included,
  the app active), which returns the real rounded corners and the natural
  shadow, transparent round them. (XCUITest's `window.screenshot()`
  was used once and baked the corners black; it is gone, with no fallback.)
- **The v1.4.0 scenes** are taken in a kept working folder of their own
  (`~/Plantoir Marketing`, ICS3U and ICS4U), moved to `~/Desktop/Teaching` for
  the run so every picture shows the same ordinary path (`capture.py`,
  `MarketingFolderShownAsTeaching`). `website/shots/scenes.py` lists
  the eleven — courses, new-course, schedule-sheet, notification-banner,
  reference, start-of-year, curriculum-settings, two-maps, both-curricula,
  how-i-teach, club — with the state each sets up, and every picture is read
  back with Vision (`ocr.swift`) against `shots.json → expectText`. Two figures
  are assembled per appearance from whole captures (`schedule` = the sheet with
  the notification banner over it; `two-maps` = the two coverage maps side by
  side), by placing them, never by cutting or redrawing them.
  How to run it and what it leaves behind: `website/README.md`, "Regenerating
  every image".
- **Class Sites**: Photographed in Safari on a real macOS display so native font
  rasterization, scrollbars, and window chrome are preserved. The two colour
  figures are the exception: their parts are the course home pages in a plain
  window with no browser round it (`webwindow.swift`), because their subject
  is the sites, and three toolbars read as three browsers.
- **Mobile View**: Photographed in the iOS Simulator using RocketSim to render
  the authentic device bezel.
- **Appearance Switching**: Machine appearance is toggled between Light and
  Dark through AppleScript / System Events, and restored when complete.

### Windows Capture (`website/shots/capture_windows.py`)

```powershell
python website/shots/capture_windows.py                  # every Windows picture
python website/shots/capture_windows.py --sites [ids]    # the class sites, in Edge windows
python website/shots/capture_windows.py --figures        # the hero and the colour figures
python website/shots/capture_windows.py --app [scenes]   # the app's scenes, How I Teach, the schedule
```

Each pass takes the desktop: it switches Windows between light and dark,
opens Plantoir, Edge and Obsidian in turn, and puts the colour mode,
Obsidian's list of vaults and every process it started back. It builds
`windowshot` the first time (.NET 9 SDK), and uses the newest Plantoir build
of the tree (`windows-app/Plantoir/bin/x64/Debug/...` after
`dotnet build -p:Platform=x64`). The scenes and what each sets up are
`SCENES` in `app_scenes_windows.py`; the working folders are made by the
app (`--stage-scene provision`). Windows has no text read-back yet, so each
picture is looked at; every scene refuses the wrong states it can detect.

---

## 3. Image Optimization & Format Strategy

Every captured PNG is processed by `website/shots/images.py`:

1. **Resolution & Sizing**:
   - Captures are taken at 2x HiDPI resolution (e.g. 2560×1600 for a 1280×800 window).
   - A Mac window capture is NOT scaled (`images.serve_as_captured`, #434): scaling would scale
     its shadow. Only the phone and the Windows pictures are scaled to `WIDEST_*_PIXELS`.
   - HTML `<img width="..." height="...">` attributes are set to **half the pixel dimensions**,
     reserving crisp 1x logical CSS dimensions while displaying sharp 2x bitmaps on high-DPI displays.
2. **WebP Generation**:
   - An optimized `.webp` file is generated beside every `.png`.
   - WebP files reduce transfer payloads by ~60–70% compared to PNG.
3. **Fallback Resiliency**:
   - The `<picture>` element lists WebP `<source>` elements first, falling back to PNG `<img>`
     tags for maximum client compatibility.

---

## 4. Platform-Conditional Serving

### HTML Generation (`website/build.py`)

When building the site, `picture_element()` in `website/build.py` inspects `site/img/`
for platform variants. When both Mac and Windows screenshots exist for an ID, it renders
two distinct `<figure>` blocks:

```html
<figure class="shot shot-platform-mac">
    <picture>
      <source srcset="./img/preview-dark.webp" type="image/webp" media="(prefers-color-scheme: dark)">
      <source srcset="./img/preview-dark.png" media="(prefers-color-scheme: dark)">
      <source srcset="./img/preview-light.webp" type="image/webp">
      <img src="./img/preview-light.png" alt="..." width="850" height="580" loading="lazy" decoding="async">
    </picture>
    <figcaption>The site, in the app, before anyone else has seen it.</figcaption>
</figure>

<figure class="shot shot-platform-windows">
    <picture>
      <source srcset="./img/preview-windows-dark.webp" type="image/webp" media="(prefers-color-scheme: dark)">
      <source srcset="./img/preview-windows-dark.png" media="(prefers-color-scheme: dark)">
      <source srcset="./img/preview-windows-light.webp" type="image/webp">
      <img src="./img/preview-windows-light.png" alt="..." width="850" height="531" loading="lazy" decoding="async">
    </picture>
    <figcaption>The site, in the app, before anyone else has seen it.</figcaption>
</figure>
```

### Client-Side Platform Switching (`website/layout/base.html` & `website/assets/style.css`)

1. **Zero-Flicker Detection**: An inline `<script>` in the `<head>` of `base.html` executes
   before the DOM body is parsed:
   ```javascript
   (function() {
     var isWin = /Win/i.test(navigator.platform || (navigator.userAgentData && navigator.userAgentData.platform) || navigator.userAgent);
     if (isWin) document.documentElement.classList.add('is-windows');
   })();
   ```
2. **CSS Rules**:
   ```css
   /* By default (macOS, Linux, mobile, or JS-disabled), show macOS screenshots */
   .shot-platform-windows {
     display: none;
   }
   /* On Windows visitors, show native Windows screenshots */
   html.is-windows .shot-platform-mac {
     display: none;
   }
   html.is-windows .shot-platform-windows {
     display: block;
   }
   ```

---

## 5. Summary of Captured Assets

Every screenshot on plantoir.app has both a macOS version (Safari / SwiftUI) and an authentic Windows twin (Microsoft Edge / WinUI 3 with native ClearType typography):

| ID | Subject | macOS Files | Windows Files |
|---|---|---|---|
| `preview` | Main window with live Quartz preview | `preview-light.png/.webp`<br>`preview-dark.png/.webp` | `preview-windows-light.png/.webp`<br>`preview-windows-dark.png/.webp` |
| `courses` | Main window course sidebar & detail | `courses-light.png/.webp`<br>`courses-dark.png/.webp` | `courses-windows-light.png/.webp`<br>`courses-windows-dark.png/.webp` |
| `new-course` | New Course wizard / modal | `new-course-light.png/.webp`<br>`new-course-dark.png/.webp` | `new-course-windows-light.png/.webp`<br>`new-course-windows-dark.png/.webp` |
| `progress` | Build / deploy milestone progress | `progress-light.png/.webp`<br>`progress-dark.png/.webp` | `progress-windows-light.png/.webp`<br>`progress-windows-dark.png/.webp` |
| `assistant` | Local AI assistant conversation & cards | `assistant-light.png/.webp`<br>`assistant-dark.png/.webp` | `assistant-windows-light.png/.webp`<br>`assistant-windows-dark.png/.webp` |
| `site-eng2d` | Rendered class website (English) | `site-eng2d-light.png/.webp`<br>`site-eng2d-dark.png/.webp` | `site-eng2d-windows-light.png/.webp`<br>`site-eng2d-windows-dark.png/.webp` |
| `site-mcv4u` | Rendered class website (Calculus math) | `site-mcv4u-light.png/.webp`<br>`site-mcv4u-dark.png/.webp` | `site-mcv4u-windows-light.png/.webp`<br>`site-mcv4u-windows-dark.png/.webp` |
| `site-sch3u-chemistry` | Rendered class website (Chemistry: reactions, states, ions) — added 2026-09-27; Windows since 2026-10-04 | `site-sch3u-chemistry-light.png/.webp`<br>`site-sch3u-chemistry-dark.png/.webp` | `site-sch3u-chemistry-windows-light.png/.webp`<br>`site-sch3u-chemistry-windows-dark.png/.webp` |
| `site-sch3u` | Rendered class website (Chemistry) | `site-sch3u-light.png/.webp`<br>`site-sch3u-dark.png/.webp` | `site-sch3u-windows-light.png/.webp`<br>`site-sch3u-windows-dark.png/.webp` |
| `site-phone` | Rendered class website on Mobile Viewport | `site-phone-light.png/.webp`<br>`site-phone-dark.png/.webp` | `site-phone-windows-light.png/.webp`<br>`site-phone-windows-dark.png/.webp` |
| `coverage` | Curriculum expectation tag browser | `coverage-light.png/.webp`<br>`coverage-dark.png/.webp` | `coverage-windows-light.png/.webp`<br>`coverage-windows-dark.png/.webp` |
| `search` | Quartz live search popover | `search-light.png/.webp`<br>`search-dark.png/.webp` | `search-windows-light.png/.webp`<br>`search-windows-dark.png/.webp` |
| `colour-schemes`| 3 course home pages, whole windows fanned out, own corners | `colour-schemes.png/.webp` | `colour-schemes-windows.png/.webp`, and `colour-schemes-windows-dark.png/.webp` for a dark page (2026-10-04) |
| `light-and-dark`| One course home page, light and dark, two whole windows side by side | `light-and-dark.png/.webp` | `light-and-dark-windows.png/.webp` (native captures since 2026-10-03, #380) |

Added for v1.4.0 (macOS first; every one has had its Windows picture since
2026-10-04, #370 — `app_scenes_windows.py`, scene names as below with the
Windows `--stage-scene` names `map-ontario`, `map-college-board` and
`schedule-sheet` for the parts; Windows' `schedule` is the sheet alone — see
"The one rule"):

| ID | Subject | Scene(s) |
|---|---|---|
| `schedule` | Schedule Deploy sheet with the "published on its own" notification over it | `schedule-sheet`, `notification-banner` |
| `reference` | Reference Courses in the sidebar, and Copy a Page into ICS4U | `reference` |
| `start-of-year` | Get Ready for the Start of the Year's plan | `start-of-year` |
| `two-maps` | The Ontario and College Board coverage maps side by side | `two-maps` |
| `curriculum-settings` | Course Settings with two curriculum folders ticked | `curriculum-settings` |
| `both-curricula` | A lesson's curriculum connection quoting both | `both-curricula` |
| `how-i-teach` | Obsidian on ICS3U's How I Teach page | `how-i-teach` |
| `club` | The New Course panel making a club | `club` |
