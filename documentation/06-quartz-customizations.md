# 6. Quartz Customizations — the Complete List

[◀ Previous: The Build Pipeline](05-build-pipeline.md) · [Back to index](README.md) · [Next: Deployment ▶](07-deployment.md)

This document enumerates **every deviation from stock Quartz v4.5.0**
([source](https://github.com/jackyzha0/quartz/tree/v4.5.0)) made by the
toolchain, verified by diffing against a clean v4.5.0 checkout. Anything not
listed here is unmodified upstream Quartz.

Customizations are applied at four different moments, which is the key to
understanding the system:

| Layer | When applied | How | Where the change lives |
|---|---|---|---|
| **A** | Docker image build | Whole-file replacement (`COPY` in Dockerfile) | `patches/` → `/opt/quartz/quartz/{components,plugins/filters}/` |
| **B** | Course setup | Idempotent regex patch of `/opt/quartz` | `setup_course.py` |
| **C** | Site build (first build / every build) | Idempotent regex patch of the per-section output copy | `build_site.py` |
| **D** | Site build | Whole-file replacement from `support/` | `build_site.py` + `support/` |

Because every build starts from the layer-A/B scaffold and then applies C
and D, a teacher's output folder always contains the union of all four
layers.

---

## A. Components replaced at image build time

These five files in [`patches/`](../patches/) overwrite their stock
counterparts inside the image. The first three implement the **two-tier
sidebar**: some folders are *expandable trees*, others are *plain links*.
The last two (A4) replace Quartz's draft filter with a publish filter.

### A1. `Explorer.tsx` (sidebar component, server side)

Stock behaviour: every folder in the Explorer is a collapsible tree node.

Changes:

1. **Imports `course_config.json`** (copied into the Quartz source tree at
   build time) and reads its `expandable` list.
2. Adds an `isExpandable(name)` helper (case-insensitive comparison via
   `localeCompare` with `sensitivity: "base"`).
3. Emits the expandable list into the DOM as a `data-expandable` attribute
   on the Explorer's `<nav>`, for the client-side script (A2) to consume.
4. **Ignores the per-layout `title` option** — the heading always comes from
   the locale file, which layer D rewrites to "Navigate this site". This
   guarantees consistent, teacher-friendly wording regardless of layout
   config.

### A2. `explorer.inline.ts` (sidebar behaviour, client side)

This script builds the sidebar DOM in the browser from a trie of all content
files. Changes:

1. **Imports `course_config.json`** the same way and defines
   `isExpandableName()`.
2. **Non-expandable folders are stripped of tree UI**: their chevron icon
   and nested `<ul>` (the "folder outer" element) are removed, so the folder
   renders as a plain entry — clicking it navigates to the folder's index
   page rather than expanding children. This is the mechanism behind the
   *expandable vs. link* distinction chosen in the setup wizard.
3. **Two-tier top-level sort**: at the sidebar's root level, entries are
   re-ordered into (1) non-expandable folders A→Z, (2) expandable folders
   A→Z, (3) loose files. Rationale: plain-link folders (Tutorials as a
   simple page, say) read like top-level navigation items, while expandable
   trees (Examples, Exercises) form a second visual group; mixing them
   alphabetically felt random to students.
4. Minor type fix: `order: ("sort" | "filter" | "map")[]` (stock v4.5.0 has
   a mis-parenthesized type annotation).

### A3. `FolderContent.tsx` (folder listing page)

Stock behaviour: a folder page always renders "N items under this folder"
plus a listing of the folder's contents.

Changes:

1. **`showFolderCount` defaults to `false`** — the "N items under this
   folder" line is noise for students.
2. **New frontmatter flag `renderFolderPages`** on a folder's `index.md`:
   set it falsy (`false`, `"no"`, `"off"`, `0`) to suppress the automatic
   page listing entirely, leaving only the index page's own prose. This lets
   a teacher write a fully curated folder landing page without an
   auto-generated file dump below it.

### A4. `publish.ts` + `filters-index.ts` (which pages reach the site)

Quartz ships two filters and neither says what a teacher means. `RemoveDrafts`
publishes everything except `draft: true` — but "draft" reads as
"unfinished", not "not visible to students", and teachers say a page IS or
ISN'T published, never that it is or isn't a draft. `ExplicitPublish` uses the
right word but flips the default to publish-nothing: in the example course 60
pages carry no flag at all, including every curriculum page, and every one
would silently vanish.

`patches/publish.ts` defines a `PublishFlag` filter with the teacher's word
and today's default: **a page is published unless it says `publish: false`**.
Strings are accepted as well as booleans, because YAML quoting varies and a
quoted `"false"` plainly means false. `patches/filters-index.ts` exports it
alongside the stock filters.

Forgetting the flag therefore leaves a page visible, which is a far kinder
mistake than a page disappearing without anybody noticing. The switch itself
is C1-13 — the image carries the filter, the build points the config at it.

### A5. `Head.tsx` (open-graph metadata, base URL fallback & the site's icon)

Stock behaviour: `og:image` is constructed unconditionally as
`https://${cfg.baseUrl}/static/og-image.png`. When `baseUrl` defaults to
`quartz.jzhao.xyz`, preview cards point to Jacky Zhao's site; when `baseUrl` is
cleared, it emits an invalid `https:///static/og-image.png` URL.

Changes:

1. Checks `const hasBaseUrl = Boolean(cfg.baseUrl && cfg.baseUrl.trim().length > 0)`.
2. Uses `https://${cfg.baseUrl}/static/og-image.png` when `baseUrl` is
   configured, or falls back to page-relative `joinSegments(baseDir, "static/og-image.png")`
   when `baseUrl` is absent.
3. Guards `twitter:domain`, `og:url`, and `twitter:url` so they are emitted
   only when `hasBaseUrl` is true.
4. Replaces the single stock `<link rel="icon" href="static/icon.png">` with
   three tags, so the tab carries Plantoir's mark instead of Quartz's:

   ```html
   <link rel="icon" href="./static/favicon.ico" sizes="32x32"/>
   <link rel="icon" href="./static/icon.svg" type="image/svg+xml"/>
   <link rel="apple-touch-icon" href="./static/apple-touch-icon.png"/>
   ```

   Order is load-bearing — a browser takes the LAST icon it understands, so
   the `.ico` (older Safari, Windows shortcuts) goes first and the SVG wins
   wherever it is supported. All three paths stay page-relative via
   `baseDir`, the same way the og-image fallback does, so a site served from
   a subfolder still finds them. The files themselves arrive in C2-25.

---

## B. Patches applied at setup time to the scaffold

Applied by `setup_course.py` to `/opt/quartz` (the template each build
copies), so they exist before any site is built. Both are idempotent.

### B1. Explorer "omit anchor" in `quartz.layout.ts`

Stock `quartz.layout.ts` calls `Component.Explorer()`. Setup replaces it with
a configured call whose `filterFn` consults a marked set:

```ts
Component.Explorer({
    folderClickBehavior: "link",
    filterFn: (node) => {
      // CQ4T-OMIT-ANCHOR: do not remove this line; build script overwrites this Set
      const omit = new Set<string>([""]);
      if (node.isFolder) {
        return !omit.has(node.fileSegmentHint);
      } else {
        return !omit.has(node.data.title);
      }
    },
  })
```

At build time, layer C rewrites the `const omit = new Set([...])` line with
the course's actual hidden items. The `CQ4T-OMIT-ANCHOR` comment
("Containerized Quartz 4 Teachers") gives the rewrite a stable landmark, and
`build_site.py` contains a preflight that re-injects a default set if the
anchor has gone missing (e.g. someone hand-edited the file).

**Purpose:** implements the "hide from sidebar" feature — hidden pages still
build and remain reachable by link and search; they are only filtered out of
Explorer navigation.

### B2. Stable ID in `OverflowList.tsx`

Stock: `const id = randomIdNonSecure()` — a fresh random DOM id for the
sidebar's overflow list on *every build*, which changes every generated HTML
page even when content is untouched.

Patch: `const id = "j8p48f"` (an arbitrary fixed string).

**Purpose:** build determinism. Netlify's delta deploy uploads only files
whose SHA-1 changed ([details](07-deployment.md#why-determinism-matters));
a random id in the markup of every page would defeat that entirely.

---

## C. Patches applied at build time to the output copy

All are functions in `build_site.py`, applied with regexes tolerant of
re-application (each detects "already patched" and no-ops).

<a name="c1-applied-on-first-build--full-rebuild"></a>

### C1. Applied on first build / `--full-rebuild`

These target files a teacher's settings never change between builds, so they
only need to run when the scaffold is (re)created.

| # | Patch | File touched | What & why |
|---|---|---|---|
| C1-1 | **Remove the Graph view** | `quartz.layout.ts` | Deletes `Component.Graph(...)` from the right sidebar. The force-directed graph is Quartz's signature feature for personal wikis, but for a linear course site it is visual noise that confuses students more than it helps. |
| C1-2 | **Drop git from date priority** | `quartz.config.ts` | `Plugin.CreatedModifiedDate` priority `["git","frontmatter","filesystem"]` → `["frontmatter","filesystem"]`. The output folder is not a git repo, and even if it were, file copy times would be meaningless. Frontmatter `created` (written by setup, managed per-section) is the source of truth. |
| C1-3 | **`defaultDateType: "created"`** | `quartz.config.ts` | Stock shows *modified* dates. A class website should show when material was posted/covered — the `created` date — not when a typo was last fixed. This pairs with the [Curriculum date sync](05-build-pipeline.md#dates-drive-everything). Applied on the first build AND re-applied on every build, so a scaffold from an older toolchain picks it up. |
| C1-4 | **Folder page title = folder name** | `quartz/plugins/emitters/folderPage.tsx` | Title template `"Folder: X"` → just `"X"`. Cosmetic: "Exercises", not "Folder: Exercises". |
| C1-5 | **`showFolderCount: false`** | `quartz/components/pages/FolderContent.tsx` | Belt-and-suspenders re-application of A3's default (protects against the file being replaced by an upstream copy). |
| C1-6 | **Long-form dates** | `quartz/components/Date.tsx` | `formatDate` options `{year, month: "short", day}` → `{weekday: "long", year, month: "long", day: "numeric"}`. Lesson pages read "Friday, September 12, 2025" — teachers and students think in weekdays. |
| C1-7 | **Wider list-page meta column** | `quartz/components/styles/listPage.scss` | Adds `width: 240px` to `.meta` so the long-form dates from C1-6 fit on one line in folder listings. |
| C1-8 | **No highlight box on internal links** | `quartz/styles/base.scss` | Comments out `background-color: var(--highlight)` on `a.internal`. Course pages are dense with wikilinks; the tinted background on every one made pages look blotchy. |
| C1-9 | **Transclusion styles** | `quartz/styles/base.scss` (appended block) | Hides the "link to original" anchor (`a.transclude-src`), removes the blockquote border/indent from transcluded content, and sizes the page-header `h1` at 2 rem. Together these make `![[Other Page]]` embeds read as seamless parts of the host page — used to assemble daily lesson pages from reusable pieces. |
| C1-10 | **`transcludeTitleSize` frontmatter flag** | `quartz/components/renderPage.tsx` | Stock renders a transcluded page's title as a hard-coded `<h1>`. Patched to `page.frontmatter?.transcludeTitleSize ?? "h1"`, so a page can declare e.g. `transcludeTitleSize: h2` and nest correctly in the host page's heading hierarchy. |
| C1-11 | **Typography fonts** | `quartz.config.ts` | Writes the section's header/body/code font choices (from the setup wizard) into the `typography` block. |
| C1-12 | **`.netlify` link** | output root | Symlinks (or copies) an existing `.netlify` folder into the output so Netlify CLI tooling can diff, if present. Convenience only — the bundled deployer does not need it. |
| C1-13 | **Publish filter swap** | `quartz.config.ts` | `Plugin.RemoveDrafts()` → `Plugin.PublishFlag()`, activating the filter A4 baked into the image. Patched here rather than shipped as config because `quartz.config.ts` comes from Quartz's own repository at image build time. Idempotent: a config already naming `PublishFlag` is left alone. |

<a name="c2-applied-on-every-build"></a>

### C2. Applied on every build

These reflect settings a teacher may change at any time; running them every
build means a re-run of the setup wizard (or a hand edit of
`course_config.json`) takes effect on the next preview with no
`--full-rebuild` needed.

| # | Patch | File touched | What & why |
|---|---|---|---|
| C2-1 | **Local `course_config.json` + import rewiring** | `quartz/course_config.json`, `Explorer.tsx`, `explorer.inline.ts` | Copies the course config into the Quartz source tree and rewrites the A1/A2 imports to the correct relative path. Required because the patched Explorer *statically imports* the config: it must resolve at Quartz's own build time, including on Netlify-less machines. |
| C2-2 | **Reading time toggle** | `quartz/components/ContentMeta.tsx` | Sets `showReadingTime` (and its trailing comma display) in `defaultOptions` to match `show_reading_time`. |
| C2-3 | **Expand-on-navigate wiring** | `Explorer.tsx`, `explorer.inline.ts` | Injects `expandOnFolderClick` from course config as a `data-expand-on-navigate` attribute and gates the client script's "auto-open folders on the current page's path" logic behind it. Without the gate, navigating to a page inside a folder always sprang that folder open even when the teacher chose chevron-only expansion. |
| C2-4 | **Patched Backlinks component** | `quartz/components/Backlinks.tsx` | Whole-file replacement from `support/Backlinks.tsx` — see D below. |
| C2-5 | **Sidebar omit set** | `quartz.layout.ts` | Rewrites the B1 anchor's `const omit = new Set([...])` with the course's `hidden` list (with `Media` always appended). This is the moment "hide from sidebar" choices become real. |
| C2-6 | **Folder click behaviour** | `quartz.layout.ts` | Sets `folderClickBehavior` on every `Component.Explorer({...})` to `"collapse"` (name click expands) or `"link"` (name click navigates), per `expandOnFolderClick`. |
| C2-7 | **Custom footer** | `quartz.layout.ts`, `quartz/components/Footer.tsx` | Normalizes the layout to `Component.Footer()` and replaces the footer JSX with the teacher's raw HTML (via `dangerouslySetInnerHTML`, backtick-escaped). Typically a licence notice. |
| C2-8 | **Page title** | `quartz.config.ts` | Sets `pageTitle` to `"<emoji> <label> S<N>"` — per-section emoji, the uppercased course code (or the club's custom short label when the code has no grade digit), and the optional section marker. |
| C2-9 | **Locale** | `quartz.config.ts` | Sets `locale:` to the configured code (affects all UI strings via the layer-D locale files, plus date formatting). |
| C2-10 | **Colour scheme** | `quartz.config.ts` | Replaces the entire `colors: { lightMode: {...}, darkMode: {...} }` block with the section's chosen scheme from `colour_schemes.json` (brace-counting replacement, not regex, to handle the nested object safely). |
| C2-11 | **Social-media previews toggle** | `quartz.config.ts` | Comments/uncomments the `Plugin.CustomOgImages()` emitter line per the `--include-social-media-previews` flag. Generating Open Graph images roughly doubles build time, so it is opt-in and typically used only for deploys. |
| C2-12 | **Computed landing title** | `content/index.md` | The home page's frontmatter title is REPLACED with one computed from the current settings: `course_name`, the per-section grade toggle (`show_grade_in_title`), and the section-marker setting (which governs the ", Section N" suffix). Only the merged copy is written; the teacher's source file is never touched. |
| C2-13 | **Social sharing card** | `quartz/static/og-image.png` | `social_card.py` (Pillow) redraws the 1200×630 share image every build in the section's colour scheme and fonts — course name large, emoji + course code (+ marker) beneath. Replaces the stock Quartz card the site's head already links. |
| C2-14 | **Mermaid label hyphenation off** | `quartz/styles/base.scss` (appended) | Quartz hyphenates body text, and it leaked into diagram labels — WebKit acts on it, Chromium ignores it, so the same flowchart read "Ca-reers" in a preview and correctly in Chrome. `.mermaid, .mermaid *` now set `hyphens: none`. |
| C2-15 | **Mermaid waits for the code font** | `quartz/components/scripts/mermaid.inline.ts` | Mermaid sizes each box by measuring its label in the course's code font. It now calls `document.fonts.load()` for weights 400 and 700 and awaits `document.fonts.ready` before `mermaid.run()`, so boxes are never sized for a fallback face. |
| C2-16 | **Pie chart viewBox re-fit** | `mermaid.inline.ts` | Mermaid centres a pie title on the pie, which the legend pushes leftward, and never widens the chart — the overflow fell outside the viewBox and was clipped. Every pie's viewBox is re-fitted from `getBBox()` after render, so a long title widens the chart instead of losing its first words. |
| C2-17 | **Pie chart palette** | `mermaid.inline.ts` | Mermaid takes `pie1` from `primaryColor`, which Quartz sets to `--light` — the page background, so the first slice vanished, legend swatch and all. The palette is now SOLVED per colour scheme at render time from that scheme's own accents (contrast-filtered, then farthest-point selection), with `pieOpacity: 1`. Fixed fractions failed 74 of 86 scheme-and-mode combinations, which is why it must stay solved rather than tuned. |
| C2-18 | **Right sidebar column sharing** | `base.scss` (appended) | On a much-linked page the backlinks crowded out the table of contents. The contents are capped at 50% of the column (only when they have a sibling), the backlinks take the rest, and both lists scroll. |
| C2-19 | **Google Fonts request filtered** | `quartz/util/theme.ts`, `quartz/components/Head.tsx` | Quartz builds ONE stylesheet request from all three font choices, and this app offers system stacks. Google rejects the whole request if any family is unknown to it — HTTP 400, so NO fonts downloaded, including the code font mermaid measures in. System stacks and families are now filtered out, and an empty request is dropped entirely. |
| C2-20 | **mhchem enabled** | `quartz/plugins/transformers/latex.ts` | Adds `import "katex/contrib/mhchem"`, so `$\ce{CaCO3(s) <=> CaO(s) + CO2(g)}$` renders. KaTeX runs at build time here, and the `katex` package Quartz already installs ships the extension, so this downloads nothing. |
| C2-21 | **Curriculum coverage map styles** | `quartz/styles/base.scss` (appended) | The grid, chips, and the five-step red → orange → yellow → green → blue scale for the generated `Curriculum Coverage` page. The colours are deliberately NOT taken from the course's colour scheme — the map's whole meaning is that ordered reading, and a scheme that recoloured it would destroy that. The scale was SEARCHED rather than picked by eye: `scripts/choose_coverage_scale.py` scores candidates on CIEDE2000 separation and through deuteranopia and protanopia simulation, which is why the top step is blue rather than a darker green — the closest pair an ordinary-sighted reader now sees is ΔE 31, against ΔE 10 before. Cells carry the expectation's code and nothing else: a digit in every cell turned the map into a table of numbers, so the count now reaches a screen reader through the cell's label and a teacher through the hover preview. The legend is a vertical list below a rule, worded "addressed once", "addressed twice", and so on. The ring marking assessed work is two rings — white inside dark — so that it stays legible on all five cell colours; a single tone disappeared on either the yellow or the darkest step depending on which was chosen. The style block is REPLACED rather than skipped when it is already present, so a stylesheet surviving from an earlier build still picks up changes. |
| C2-22 | **Backlinks "structural pages" set** | `quartz/components/Backlinks.tsx` | Rewrites the `const structural = new Set<string>([…])` block behind the `// CQ4T-STRUCTURAL-ANCHOR` comment in `support/Backlinks.tsx`, inserting the course's curriculum folder name and `Curriculum Coverage` in both title and slug form. Those pages link to everything by nature, so without this every content page's backlinks panel is dominated by the curriculum index and the generated coverage map — noise that buries the pages a teacher actually wants to see listed. |
| C2-23 | **Page title text shrinking & navbar vertical centering** | `quartz/styles/base.scss` (appended) | Prevents the navbar course code and section number from wrapping onto a second line on mobile by dynamically scaling the page title font size (`clamp(0.875rem, 4.5vw, 1.75rem)`) down to 50% of its original size and setting `white-space: nowrap`, while vertically centering the course emoji, code, section, and the light/dark mode toggle button with the adjacent search field. |
| C2-24 | **Deploy domain & `baseUrl` sync** | `quartz.config.ts` | Sets `baseUrl` to the section's actual public domain (from advanced custom domains, `.netlify_sites/`, or `.cloudflare_sites/`), or clears it when unpublished. Ensures OpenGraph (`og:image`, `og:url`) and Twitter card tags point to the teacher's live site rather than the stock `quartz.jzhao.xyz` default. |
| C2-25 | **The site's icon** | `quartz/static/{favicon.ico,icon.svg,apple-touch-icon.png,icon.png}`, `content/favicon.ico` | `install_favicon()` copies the generated set from `/opt/support/favicon` (see `scripts/brand_images.py`, which draws it from `mac-app/Plantoir.icon`). `icon.png` is overwritten rather than merely unlinked, so a built site carries no Quartz logo even where nothing points at one. `favicon.ico` is installed TWICE on purpose: the `static/` copy is what the A5 tags link, while the CONTENT-ROOT copy is the only way to get a file to `public/favicon.ico` — Quartz's Assets emitter copies non-Markdown files out of `content/` unchanged, and the Static emitter cannot write above `public/static/`. That root copy is what answers the implicit `GET /favicon.ico` made by feed readers, link unfurlers and older browsers that never read the page. It runs after the content folder is rebuilt from scratch, because a copy made any earlier is deleted a few lines later — silently, since the page still looks correct. |

### C3. Content-level transformations (every build)

Not Quartz-code patches, but part of the same customization story — they
adapt *Obsidian conventions* to *Quartz expectations* and are detailed in
[the build pipeline](05-build-pipeline.md#stage-3-content-assembly):

- `publishForSectionN`/`createdSectionN` → `publish`/`created` collapse
  (per-section publishing from shared files), with the legacy `draftSectionN`
  read inverted.
- Aliased wikilinks containing `section<N>/` paths rewritten to alias-only
  form.
- Curriculum folders' `created` timestamps synced to the section's newest
  page.
- `content/Media` created as a symlink to the course-level media folder.
- **`Curriculum Coverage.md` generated** (when the course has curriculum
  pages and `include_curriculum_coverage` is not false): a heat map of every
  specific expectation, coloured by how many pages TRANSCLUDE it, with
  assessed work marked and one chip per overall expectation. It is written
  into the assembled content, never into the teacher's vault, so it is
  rebuilt from the site's own links every time and cannot drift. The link to
  it is inserted into the BUILT copy of `Key Links`, directly under the
  curriculum entry. The page is also added to the Explorer's omit set, so
  it never appears in the sidebar: it is a teacher's instrument, reached
  from Key Links, and it sits at the content root where it would otherwise
  be listed above every folder. **Only published pages count** — a page held back with
  `publish: false` is not on the site, so it leaves the map exactly where it
  was until the day it is published. **And only pages the course teaches
  count**: the page carrying the connection must be linked from a class
  page, or from a page a class page links to. A page written over the
  summer and never scheduled has addressed nothing yet. The map applies Quartz's own draft
  test, and per-section publishing is resolved before it counts, so a
  course whose sections are at different points gets an honest map for
  each one.

---

## D. Locale files replaced at build time

`support/locales/` contains all 27 Quartz locale files, installed over
`quartz/i18n/locales/` on first build. Each differs from stock in exactly
four strings, translated appropriately in every language:

| UI element | Stock (en-US) | Replaced with |
|---|---|---|
| Backlinks panel title | "Backlinks" | **"When did we do this?"** |
| Backlinks empty state | "No backlinks found" | **"Not yet addressed in class."** |
| Explorer (sidebar) title | "Explorer" | **"Navigate this site"** |
| Table of contents title | "Table of Contents" | **"Navigate this page"** |

**Rationale:** this is the toolchain's most pedagogically interesting
customization. In a course site, the pages that link *to* a concept page are
the daily lesson pages — so a concept page's backlinks panel is, in effect,
a record of **which classes covered this concept and when**. Renaming
"Backlinks" to "When did we do this?" turns a wiki feature into a student
catch-up tool, and the empty state "Not yet addressed in class." tells a
student reading ahead exactly what it means. "Explorer" and "Table of
Contents" are likewise renamed to plain-language labels.

### D1. Patched `Backlinks.tsx` (`support/Backlinks.tsx`)

Complements the locale change, and carries two changes. First, an
`excludeBacklinks: true` frontmatter flag that suppresses the backlinks panel
on a specific page — useful where "when did we do this?" makes no sense (a
style guide, a syllabus) or where the link graph would mislead. Second, the
`CQ4T-STRUCTURAL-ANCHOR` set that C2-22 rewrites each build, which keeps the
curriculum index and the generated coverage map out of every other page's
backlinks.

---

## E. Summary: what is *not* customized

Everything else is stock Quartz v4.5.0 — with five asset exceptions, all in
`quartz/static/` and all written every build: `og-image.png` is redrawn as the
section's social sharing card (C2-13), and `favicon.ico`, `icon.svg`,
`apple-touch-icon.png` and `icon.png` are the site's own icon (C2-25). Two of
those OVERWRITE files Quartz itself ships — `og-image.png` and `icon.png` —
which is deliberate: a built site should carry no Quartz artwork, including
where nothing links to it. (`quartz/util/og.tsx` reaches for `static/icon.png`
when it draws generated OG images, so it now picks up Plantoir's mark too.)
Beyond those: the Markdown/OFM transformer
pipeline, full-text search (FlexSearch), syntax highlighting, LaTeX
rendering, callouts, popovers, RSS/sitemap emitters, mobile layout, and
light/dark mode. The customizations are deliberately thin wrappers around
configuration and presentation; the content pipeline is untouched, which is
what makes tracking upstream Quartz plausible (the cost of an upgrade is
re-validating each patch's regex against the new source text — and replacing
the three layer-A components).

---

[◀ Previous: The Build Pipeline](05-build-pipeline.md) · [Back to index](README.md) · [Next: Deployment ▶](07-deployment.md)
