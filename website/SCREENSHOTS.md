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

Russell's rule, stated more than once and last on 2026-09-27: **every picture
on plantoir.app is made ONLY with macOS's built-in window capture** —
`screencapture -x -o -l <window id>`, the programmatic Option-click capture —
which returns the window with its own rounded corners, transparent outside
the curve. Figures made of several windows are built from those captures
WHOLE:

- no crop that passes through a window, and no re-rounding of a corner;
- no rounded mask, corner or shadow shape drawn in Pillow — a shadow, where
  there is one, is the capture's own alpha channel, blurred;
- scaling with Lanczos, of the whole image only;
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

**The gate:** `website/shots/test_native_corners.py` opens every picture the
pages show a Mac visitor (from `shots.json` and the pages, PNG and WebP) and
fails on a corner that is square or tighter than any real macOS window;
`capture.py` runs the same check (`corners.py`) before it promotes a scene
and at the end of every run. It failed on the committed `colour-schemes` and
`light-and-dark` before they were retaken, and passes after.

**Windows owes the same rule.** `capture_windows.py` builds
`light-and-dark-windows` and `colour-schemes-windows` with `composite.py`,
which now leaves Playwright's square page screenshots square, and
`hero_windows.py` still masks screen grabs with a drawn `rounded()`. Neither
was edited from the mac; the gate does not judge `-windows-` pictures until
Windows has an answer that keeps a window's own shape.

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
  window capture (`screencapture -o -l <window number>`), which returns the
  real rounded corners already transparent. (XCUITest's `window.screenshot()`
  was used once and baked the corners black; it is gone, with no fallback.)
- **The v1.4.0 scenes** are taken in a kept working folder of their own
  (`~/Plantoir Marketing`, ICS3U and ICS4U). `website/shots/scenes.py` lists
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

The Windows capture harness is driven by Python and a built-in CLI mode in
`Plantoir.exe`:

```powershell
python website/shots/capture_windows.py
```

Under the hood:
1. **Autonomous Invocation**: Executes `Plantoir.exe --capture-marketing-shots <output-dir>`.
2. **Demo Provisioning**: `MarketingShotCapturer.cs` (`windows-app/Plantoir/Services/MarketingShotCapturer.cs`)
   creates an isolated demo workspace in `Path.Combine(Path.GetTempPath(), "PlantoirMarketingWorkspace")`
   populated with `ENG2D`, `MCV4U`, and `SCH3U` from `support/example_content/`.
3. **Staged Rendering**: For each appearance (`ElementTheme.Light` and `ElementTheme.Dark`),
   the capturer configures and renders the exact visual states:
   - `courses`: Main window with multi-course sidebar and Section 1 detail.
   - `new-course`: `NewCourseDialog` populated with `ENG2D` and Ontario curriculum suggestions.
   - `progress`: `TaskProgressView` demonstrating deploy milestone progression.
   - `preview`: Live embedded Quartz preview container.
   - `assistant`: 560×760 `AssistWindow` with prompt suggestion shelf, teacher/assistant message bubbles, and actionable plan card.
4. **Direct WinUI 3 Capture**: Uses `RenderTargetBitmap` and `BitmapEncoder`
   to render the visual tree at 2x HiDPI resolution directly to PNG files,
   eliminating the need for desktop region cropping or OS-level theme changes.

---

## 3. Image Optimization & Format Strategy

Every captured PNG is processed by `website/shots/images.py`:

1. **Resolution & Sizing**:
   - Captures are taken at 2x HiDPI resolution (e.g. 2560×1600 for a 1280×800 window).
   - Images exceeding `WIDEST_WINDOW_PIXELS` (1700px) are scaled proportionally.
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
| `site-sch3u-chemistry` | Rendered class website (Chemistry: reactions, states, ions) — added 2026-09-27, macOS only | `site-sch3u-chemistry-light.png/.webp`<br>`site-sch3u-chemistry-dark.png/.webp` | none yet (`windows: false`) |
| `site-sch3u` | Rendered class website (Chemistry) | `site-sch3u-light.png/.webp`<br>`site-sch3u-dark.png/.webp` | `site-sch3u-windows-light.png/.webp`<br>`site-sch3u-windows-dark.png/.webp` |
| `site-phone` | Rendered class website on Mobile Viewport | `site-phone-light.png/.webp`<br>`site-phone-dark.png/.webp` | `site-phone-windows-light.png/.webp`<br>`site-phone-windows-dark.png/.webp` |
| `coverage` | Curriculum expectation tag browser | `coverage-light.png/.webp`<br>`coverage-dark.png/.webp` | `coverage-windows-light.png/.webp`<br>`coverage-windows-dark.png/.webp` |
| `search` | Quartz live search popover | `search-light.png/.webp`<br>`search-dark.png/.webp` | `search-windows-light.png/.webp`<br>`search-windows-dark.png/.webp` |
| `colour-schemes`| 3 course home pages, whole windows fanned out, own corners | `colour-schemes.png/.webp` | `colour-schemes-windows.png/.webp` |
| `light-and-dark`| One course home page, light and dark, two whole windows side by side | `light-and-dark.png/.webp` | `light-and-dark-windows.png/.webp` |

Added for v1.4.0, macOS only (a Windows visitor sees the mac picture until
`capture_windows.py` takes an id marked `windows: true`, and the section says
"On the Mac" while `site.json → availability` says so):

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
