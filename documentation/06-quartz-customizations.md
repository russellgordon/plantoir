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

**The expression is `!(flag === false || flag === "false")`, and every word of
it is load-bearing.** The string comparison is EXACT, so `publish: "False"` is
a page students can see — one capital letter away from one they cannot. That is
not an oversight to tidy up, because of what feeds this filter: Quartz v4.5.0's
`FrontMatter` transformer parses with `gray-matter` using **`js-yaml` on
`JSON_SCHEMA`** (`quartz/plugins/transformers/frontmatter.ts`), a schema that
resolves only lowercase `true`/`false` and leaves everything else a string —
and the page reaching it has already been round-tripped through PyYAML by
`build_site.process_frontmatter`, which turns every real boolean into lowercase
`false`. So a value that is still mixed-case by the time this filter sees it is
one PyYAML declined to resolve, i.e. genuinely a string, i.e. not a flag. A
case-insensitive compare here would hide pages the build publishes, and both
apps' readers are written against this exact expression: see
[08 → Whether students see a page](08-course-config-reference.md#whether-students-see-a-page).
`scripts/check_visibility_against_the_site.py`, run by `verify.sh`, fails if
either this expression or that schema changes.

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
a configured call whose `filterFn` consults a marked set. This is version 2 of
that filter (issue #265, 2026-09-24), copied from `setup_course.EXPLORER_BLOCK`:

```ts
Component.Explorer({
    folderClickBehavior: "link",
    filterFn: (node) => {
      // CQ4T-OMIT-ANCHOR: do not remove this line; build script overwrites this Set
      const omit = new Set<string>([""]);
      // CQ4T-HIDE-RULE: v2 - stored names, top level only
      const hiddenNames = new Set<string>();
      for (const name of omit) {
        hiddenNames.add(String(name || "").normalize("NFC").toLowerCase());
      }
      const depth = node.slug.split("/").length;
      if (node.isFolder) {
        if (depth !== 2) {
          return true;
        }
        return !hiddenNames.has(String(node.fileSegmentHint || "").normalize("NFC").toLowerCase());
      }
      if (depth !== 1) {
        return true;
      }
      const filePath = node.data ? String(node.data.filePath || "").normalize("NFC").toLowerCase() : "";
      if (hiddenNames.has(filePath)) {
        return false;
      }
      const stem = filePath.endsWith(".md") ? filePath.slice(0, -3) : filePath;
      return !hiddenNames.has(stem);
    },
  })
```

At build time, layer C rewrites the `const omit = new Set([...])` line with
the course's actual hidden items. The `CQ4T-OMIT-ANCHOR` comment
("Containerized Quartz 4 Teachers") gives the rewrite a stable landmark, and
`build_site.py` contains a preflight that re-injects a default set if the
anchor has gone missing (e.g. someone hand-edited the file).

**The rule** (`contracts/file-formats.json` → `sidebarHiding.matchRule`): a
`hidden` entry is the STORED name of a TOP-LEVEL item — a file by its name with
`.md`, a folder by its name, which is exactly what Course Settings offers and
writes — matched ignoring case and Unicode normalisation; nothing below the top
level is hidden by a name; a name without `.md` still hides `<name>.md`, so no
older entry is un-hidden. **Version 1** matched a folder on
`fileSegmentHint` at ANY depth and a file on `node.data.title` — its page TITLE —
with the build stripping `.md` so a file name could stand in for the title. So a
page titled differently from its file name was never hidden, and a nested
`Portfolios/Tasks` was hidden because the top-level `Tasks` was ticked. Titles
were never the input (the list was file names from the first commit, where this
filter was Quartz's own documentation example); the title match worked only
because every shipped page has title == file name. Measured: old vs new over 8 real
courses, 38 payloads and 50 skeletons (13,457 items), 0 differences. The only
direction toward SHOWING is a nested item sharing a ticked name, which the switch
list never offered, and which is still published either way.

Three constraints the text must keep, each tested in `scripts/test_sidebar_hiding.py`:

- **No `}` followed by `)` before the block's end.** The patchers find a block with
  the non-greedy `Component\.Explorer\(\s*\{[\s\S]*?\}\s*\)`, which would stop early
  and leave a truncated filter. Hence `if` statements, not callbacks.
- **No named inner function or arrow.** `filterFn` is serialised with `.toString()`
  and rebuilt in the browser, and Quartz bundles with esbuild's `keepNames`, which
  wraps `const f = (x) => ...` in a `__name(...)` helper that does not exist once
  the text is rebuilt — the filter throws and the sidebar fails to draw. The first
  draft of v2 had exactly this; `scripts/check_sidebar_hiding_against_the_site.py`
  (verify.sh) caught it, because it rebuilds the function from its text the same
  way, through Quartz's own `FileTrieNode`.
- **No backslash.** The patchers pass the block to `re.subn` as a replacement,
  where a backslash is an escape.

`fileSegmentHint` is TypeScript-private but read at runtime, as v1 did; `slug`
is public (a folder's is `<path>/index`, so two segments means top level).
Existing sections are brought to v2 on their next build
([05 → Stage 4](05-build-pipeline.md#stage-4-configuration-patching)).

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
| C1-3 | **`defaultDateType: "created"`** | `quartz.config.ts` | Stock shows *modified* dates. A class website should show when material was posted/covered — the `created` date — not when a typo was last fixed. This pairs with the [date passes](05-build-pipeline.md#dates-drive-everything). Applied on the first build AND re-applied on every build, so a scaffold from an older toolchain picks it up. |
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
| C2-5 | **Sidebar omit set** | `quartz.layout.ts` | First brings the section's copy of the B1 filter up to the current version (`ensure_sidebar_hide_rule_current`), then rewrites the anchor's `const omit = new Set([...])` with the course's `hidden` list AS STORED — `.md` kept, each name a JSON string — plus `Media`, `Curriculum Coverage.md` and every other coverage map's file this build wrote (#128: one map per curriculum folder) (`names_the_sidebar_hides`, never written back). This is the moment "hide from sidebar" choices become real. |
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
| C2-22 | **Backlinks "structural pages" set** | `quartz/components/Backlinks.tsx` | Rewrites the `const structural = new Set<string>([…])` block behind the `// CQ4T-STRUCTURAL-ANCHOR` comment in `support/Backlinks.tsx`, inserting every mapped curriculum folder's name and every coverage map's title (#128 — `Curriculum Coverage` always among them) in both title and slug form. Those pages link to everything by nature, so without this every content page's backlinks panel is dominated by the curriculum index and the generated coverage map — noise that buries the pages a teacher actually wants to see listed. |
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
- **One coverage map per curriculum folder generated** (#128; when the
  course has curriculum pages and `include_curriculum_coverage` is not
  false — one switch covers every map). The primary folder's map is
  `Curriculum Coverage.md`, exactly as before; each further DECLARED
  folder holding expectation pages gets `<Folder> Coverage.md` (see
  "Curriculum maps" below and `documentation/05-build-pipeline.md` → "The
  curriculum coverage maps"). Each is a heat map of every
  specific expectation, coloured by how many pages TRANSCLUDE it, with
  assessed work marked and one chip per overall expectation. It is written
  into the assembled content, never into the teacher's vault, so it is
  rebuilt from the site's own links every time and cannot drift. The link to
  each is inserted into the BUILT copy of `Key Links`, directly under the
  entry pointing into its folder. The page is also added to the Explorer's omit set, so
  it never appears in the sidebar: it is a teacher's instrument, reached
  from Key Links, and it sits at the content root where it would otherwise
  be listed above every folder. **Only published pages count** — a page held back with
  `publish: false` is not on the site, so it leaves the map exactly where it
  was until the day it is published. **And only pages the course teaches
  count**: the page carrying the connection must be linked from a class
  page, or from a page a class page links to. A page written over the
  summer and never scheduled has addressed nothing yet. Both readings take
  every shape in `shared-rules.json` → `readingALink` — `![[A1.1#Examples|see]]`
  counts, and `[[Worksheet#Part A\|a]]` on a class page makes Worksheet taught
  ([#314](https://github.com/russellgordon/plantoir/issues/314); until then a
  heading followed by an alias was not read as a link). The map applies Quartz's own draft
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
curriculum indexes and the generated coverage maps out of every other page's
backlinks.

### Curriculum maps: a second curriculum, and the codes a map reads (#128)

A course has one coverage map per curriculum folder it DECLARES
(`curriculum_folders` in `course_config.json`) that holds expectation pages.
The first folder's map keeps the page every course has always had,
`Curriculum Coverage`; every other is `<Folder> Coverage` — `College Board
Curriculum Coverage`, say — so declaring a second folder never renames the
first map. A course that declares nothing gets the one map it always had,
from the folder whose name mentions the curriculum.

A page is an expectation when its whole name is a code in one of three
shapes: `A1.1` (Ontario, BC; either case), `1.A` (a College Board skill), or
`CRD-1.A` — two to four capital letters, a hyphen, a number, a dot and one
capital letter (a College Board learning objective, such as `AAP-2.B` or
`IOC-1.F`). `12.3`, `B2`, `1.A.1` and `CRD-1.A.1` are not. On the map,
Ontario's strands come first by letter, then the skills by number, then
the learning objectives in a column per prefix (`CRD`), ordered by number
and letter. Only Ontario-style strands carry the chips for overall
expectations; a map with none leaves out every sentence about them.

**Adding a second curriculum** — AP Computer Science Principles, say.
Nothing Plantoir ships contains the College Board's pages: the framework's
text is the teacher's to bring. A teacher makes a folder such as
`College Board Curriculum`, ticks it under Course Settings → "Curriculum
folders", and asks "Revise with Claude…" to draft one page per expectation
code from the framework they have — `1.A`, `CRD-1.A` and so on, one page
each, named by the code alone. The next preview or publish draws a second
coverage map for it, linked from Key Links under that folder's entry.

---

## F. Additions installed every build: printable pages (#454, v2.0.0)

A page whose settings say `printable: true` prints as a worksheet; a page that
says `printPdf: <file in Media>` hands out a PDF the teacher already has. The
rules are data in [`contracts/shared-rules.json`](../contracts/shared-rules.json)
→ `printablePages` and [`file-formats.json`](../contracts/file-formats.json) →
`pageOptIns`; this section says how the site does it and why.

**Compatibility, stated first because it is the promise.** A page that does
not opt in renders exactly as it did before #454: its HTML carries no print
markup at all — no wrapper, no button, no style, no `@page` — and its date
line is the plain `<p class="content-meta">` it always was. Measured on EXC2O
(implementation review, `origin/dev` 8178eeaac against the branch): **all 300
pages that do not opt in are byte-identical** once what Quartz already varies
between ANY two builds is set aside (the explorer's random list id, build-time
dates on curriculum pages, and the order of tag-list entries sharing one of
those dates); the only pages that differ are the 7 that opt in. Every new CSS
selector is scoped to a printable page or the handout frame, and nothing adds
an `@page`. ⌘P of a page that does not opt in prints the same pages with the
same text in Chrome for Testing 155 (13 and 3 pages, light and dark,
`pdftotext` identical) and in Safari 26.6. **verify.sh gates it on every
run**: section 5 plants "Printable Not Opted", the worksheet with only
`printable: true` taken out, and the 6h printable-pages check fails if that
page carries `plantoir-meta-line`, `plantoir-print`, `data-plantoir` or
`@page`, or if its date line is not the plain one straight after its title.
What every site DOES change is its two shared bundles, measured on EXC2O
against `origin/dev`: `postscript.js` 74,590 → 85,344 bytes (+10,754) and
`index.css` 35,386 → 41,045 (+5,659) on the final branch (the review measured
+10,525 and +5,659 at 4c587f670, before the light-page wait and the corner
change), every rule in them scoped so it cannot touch an ordinary page.

### F1. The files and how they reach a section

New files, not patches, live in `support/quartz/` at the path they take in a
section's Quartz copy, and `build_site.install_quartz_additions` copies them in
on EVERY build (ALWAYS section), so a section built before them picks them up
on its next preview:

| File | What it does |
|---|---|
| `components/PlantoirMetaLine.tsx` | Wraps the CONTENT layout's `ContentMeta()` only (folder and tag pages never get a button). Not opted in → renders the inner date line and nothing else. `printPdf` → a plain `<a … target="_blank">` to `Media/<Quartz slug of the file>`, built with Quartz's own `slugifyFilePath` so the address is the one the Assets emitter writes (measured with `&` and a space: `Media/plantoir-print-fixture--and--key.pdf`). `printable` → Print plus a `<details>` menu (Questions only, Answers only) at the TRAILING edge (`margin-inline-start: auto`, so right-to-left too), present even when the date line shows nothing (decision 6), and an inline `<style id="plantoir-print-page">` with the `@page` box and its four corners for ⌘P. Reads `quartz/plantoir_print.json` with `fs` rather than importing it, so a missing file costs the button, never the build. Forwards the inner component's `css`/`afterDOMLoaded` (review S7). |
| `components/scripts/printRules.ts` | The rules with no DOM and no imports — answer/question/unfold roles, labels, title cleaning, page labels — so `scripts/check_print_rules_against_the_site.py` can bundle it with the scaffold's esbuild and run every contract case in Node (verify.sh). |
| `components/scripts/print.inline.ts` | The button, the handout, ⌘P and the preview handoff (F3–F5). Bundled into every site; inert unless the page carries a printable meta line. |
| `components/styles/print.scss` | On-screen button styles, ⌘P rules under `@media print { html.plantoir-printable … }`, and handout rules under `html.plantoir-print-frame`. No bare `@page` anywhere (review B2: it cannot be scoped). |

Two marker edits wire them in (`wire_quartz_additions`, idempotent, ALWAYS):
`components/index.ts` exports `PlantoirMetaLine`, and `quartz.layout.ts`'s
content layout becomes `Component.PlantoirMetaLine(Component.ContentMeta())`.
**REJECTED: a third edit to `mermaid.inline.ts`** (an event saying diagrams are
drawn), in the first implementation: that script is INLINED into every page,
so it changed the HTML of every page on every site. The handout waits by
watching the diagrams instead (F3). Also rejected: `patches/` rows (nothing of
Quartz's is replaced), a meta tag in `Head.tsx`, appending to `base.scss`
(marker appends freeze, see C2), and resolving `support/quartz` from the
working directory as the Backlinks copier does (then `check_baked` would
compare the tree with itself). A file later REMOVED from `support/quartz`
stays in sections that have it; nothing imports it, so it is inert.

Every build also writes `quartz/plantoir_print.json` (`scripts/print_settings.py`):
the four corners composed from the course's `print_*` settings, the words, the
answer kinds and title words, and the default mode. Corners are Python
because they depend on the COURSE's settings, which the site cannot read.

### F2. The engine, gated per site

Paged.js 0.4.3 (`/opt/vendor/pagedjs`, see 02) is copied into a section's
`quartz/static/pagedjs` only when at least one page students can see opts in
and has no PDF of its own (`page_features.install_gated_assets`), and taken out
when none does — verify.sh 6c checks it is gone once the planted pages are.
So a course that never prints carries none of its 502,617 bytes. The gate runs
on the build's processed copies, before Quartz. **The live-preview edge:** a
page that gains `printable: true` while a preview is ALREADY running gets its
button on the next build of that preview but the engine only on the next
build that runs the gate — until then Print uses the fallback (F3).

### F3. The handout (Print)

On each page load the script stamps every callout in the article with its
role, read from what was folded WHEN THE PAGE LOADED (a student who opened an
answer toggles the same class; plan finding C). On Print:

1. Dark page → `saved-theme="light"` and a `themechange` (the reader's saved
   preference is never written). Then, on EVERY page, wait until every
   Mermaid diagram's OWN child is an `svg`, 8 s cap — at once when they are
   already drawn. Measured: Mermaid first draws into a temporary box, and
   taking the first `svg` found printed a blank space; and a LIGHT page opened
   from the preview (F5) starts printing before Quartz has drawn anything, so
   the first version, which waited only on dark pages, printed every diagram
   as its source text (implementation review B1: Safari's PDF read
   "flowchart LR / A[Expand] --> …"; Chrome had 0 of 5 drawn).
   `browser-checks/print_handout.mjs` prints the verify fixture that way in
   headless Chrome for Testing and fails on source text; verify.sh 6h runs it
   when a Chrome for Testing is on the Mac. Proven against the old code.
2. Await every function in `window.plantoirPrint.prepare` (the hook #485 E1
   and #455 register in).
3. Clone the title and article: answers lifted to an "Answers" section on a
   fresh page, labelled by their own title or by where they sit (numbered
   list item → "Question n", after the heading above the list when there is
   one — "Practice · Question 1", since the item's number alone repeated the
   fixture's heading "Question 1" (review N2), or "Question 3, part 1" when
   that heading is itself a question (fix review) — else nearest heading, else
   "Answer n");
   question callouts keep their title and send their body; every other folded
   callout opened in place; "(click to expand)" dropped; code longer than 25
   lines may split; an `svg` with a size and no `viewBox` gets one; code line
   numbers written out (Paged.js does not carry Quartz's line counter: every
   line printed "1").
4. An iframe ON SCREEN but invisible (`opacity:0`): off screen, Safari
   paginated about one page per 8 s (11 pages ≈ 90 s); on screen, 192 ms.
5. Paged.js paginates with `index.css` plus the page's `@page` text, its
   bottom-right corner replaced by a per-page `--plantoir-page-label`, PLUS
   the break rules spelled out unscoped — Paged.js decides breaks by matching
   selectors against the content BEFORE it sits under the frame's `<html>`,
   so `html.plantoir-print-frame .plantoir-answers { break-before: page }`
   matched nothing (measured: the answers began mid-page). Margin boxes use
   no-break spaces: "Page 1 of 3" wrapped onto three lines in Safari — except
   the top-left corner, which may take two lines: a long school name sharing
   it with the course code printed ON TOP of three blanks (review S3,
   measured with "St. Michael's Catholic Secondary School of the Arts ·
   EXC2O"; two clean lines after, handout and ⌘P). The top corners sit on
   their bottom edge, so the blanks line up with the name's last line.
6. Pages labelled "Page n of m" then "Answers n of m" (decision 3), and
   `print()`; restored again when `print()` returns, in case a browser never
   sends `afterprint` (review N4). That is right where `print()` waits for the
   dialog to close — Safari, Chrome and Edge, measured — and UNMEASURED in
   Firefox, where a `print()` that returned at once would take the frame away
   mid-print. `afterprint` restores the theme and removes the frame (measured
   in Safari: Cancel fires it too; the page came back dark with no frame).

**Fallback:** Paged.js missing or failing → the same frame printed by the
browser, corners where it prints margin boxes (Chrome, Edge), one count for
the whole document. Measured in Chrome: 3 pages, answers on a fresh page.

### F4. ⌘P on a printable page

Questions only, no pagination (decision 7): answers hidden, question bodies
hidden, everything else open, sidebars hidden, titles cleaned for the print
and restored after. A dark page prints light; Mermaid diagrams already drawn
dark cannot be redrawn between `beforeprint` and the print, so they keep the
dark colours they were drawn with and are inverted as a whole (review S5).
Measured: flipping only the page's colours left light words on light shapes.
**Safari limit, measured:** Safari lays a printed page out at the WINDOW's
width (`innerWidth` 1512 while printing from a 1512 px window) and shrinks it
onto the paper, so ⌘P in Safari prints the column at roughly half size — on
EVERY Quartz page, before #454 too. Scaling the page up by the window's width
was tried and REJECTED (it clipped both edges). The Print button is the path
that prints at full size in Safari. Also found, unchanged by #454: ⌘P of an
ordinary page in DARK mode in Safari printed eight blank pages (white text,
backgrounds dropped) — before and after.

### F5. Plantoir's own preview

A `WKWebView` inside the app shows no print dialog and opens no new windows
(review B1, measured). So when the page finds the app's `plantoirPrint`
message handler it says `printablePages.words.openingInBrowser` and posts
`{mode, url}`; the app opens the page in the default browser with
`#plantoir-print=<mode>`, and the page prints at once there. Measured in
Safari 26.6, light, real print sheet then Save as PDF: "All 3 Pages", the
diagram DRAWN (no source text — the first version printed it as text, B1),
the hash removed afterwards.
New-window links, the PDF link among them, open in the browser too. See 09.

### F6. Figures (decision 13, for #485 E1)

An engine's figure is `<figure class="pl-figure pl-<engine>">` with an SVG
that has a `viewBox` (or an `<img>` with its own size) and a `<figcaption>`.
On paper it never splits, is scaled to the width, keeps its own resolution,
and any dark-mode filter is removed. A browser-drawn engine registers in
`window.plantoirPrint.prepare`.

### F7. Measured matrix (macOS 26.6, M4 Pro), the verify fixture

| Browser | With answers | Questions only | Answers only | ⌘P | Press → print |
|---|---|---|---|---|---|
| Safari 26.6 | 3 (2 + 1) | 2 | 1 | 2, small (F4) | 760 ms |
| Chrome for Testing 155.0.8059.39 | 3 (2 + 1) | 2 | 1 | 2, corners | 131–214 ms |
| Edge 155.0.4283.45 | 3 (2 + 1) | 2 | 1 | 2, corners | 124–212 ms |

Light and dark gave the same page counts in every cell. Chrome and Edge were
driven by puppeteer-core 24.10.0 (handout: the frame's document as printed,
re-rendered by `page.pdf`; ⌘P: `page.pdf` with the page's `@page`). **Trap:**
Edge's first launch from a Homebrew cask waits on macOS's "downloaded from
the Internet" prompt, and until it is answered `requestAnimationFrame` never
fires, which made Paged.js hang and looked exactly like an Edge bug.
Not measured here: a site published to Netlify or Cloudflare (the files are
identical to the preview's), Windows browsers (the `windows` issue asks).

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

**One stock behaviour Plantoir's readers must match, not change: `%%`
comments.** Quartz's `ofm.ts` removes every `%%…%%` from the raw page
(`commentRegex = /%%[\s\S]*?%%/g`, line 130) in `textTransform` (lines
160–163), before callouts, wikilinks or remark see anything. So a link written
inside a comment is never drawn, and since
[#331](https://github.com/russellgordon/plantoir/issues/331) no reader in the
build, the installer, the linters or the mac app treats one as a link either —
comments are masked FIRST, and code is found in what is left, Quartz's order.
The rule, its cases and the trap it is built around (the curriculum markers
are comments) are in [10 → A comment is never a link](10-local-ai-assistant.md#a-comment-is-never-a-link-331)
and [05 → Which shapes are links](05-build-pipeline.md).

## Spelling a folder's new name inside a link

Renaming a course folder repoints the qualified links that name it, and the
question this section answers is a narrow one: how is the new name SPELLED
once it is inside a link? Getting it wrong does not fail — it writes a broken
link into a teacher's own page and says nothing.

**The defect, which was on both platforms.** `FolderPathRewriter` decided
whether to percent-encode the new name from whether the OLD path segment was
encoded. That is the obvious rule and it is wrong, because a Markdown link's
destination ends at the first SPACE. Renaming `Tasks` to `All Tasks` turned

    [q](Tasks/Quiz%201.md)   into   [q](All Tasks/Quiz%201.md)

which neither Obsidian nor Quartz can follow. The `%20` there belongs to the
FILE name; the folder segment `Tasks` carries no `%` at all, which is what made
it easy to miss by eye. Windows found this by adversarial review on 2026-09-06,
fixed it, and reported it to the mac as a shared defect rather than a port
error — which was the right call, and is why the mac took the rule unchanged:

> In a MARKDOWN link, escape when the NEW name needs it, whatever the old
> segment looked like. In a WIKILINK, keep the plain spelling.

The wikilink half is not an oversight. `[[All Tasks/Quiz 1]]` is exactly how
Obsidian writes a wikilink whose folder has a space in it, so escaping there
would be the mirror-image mistake. Both sides also kept the OLD rule as a
second reason to escape rather than replacing it: a segment that ARRIVED
percent-encoded goes back percent-encoded, in either style, so a link a teacher
already had keeps the shape it had.

### The escaping SET is measured, and `Uri.EscapeDataString` is the wrong tool

This is the part that is new to Windows, and the mac's first plan was to copy
`Uri.EscapeDataString` precisely so the two apps could not drift. An
adversarial review checked that against the real Quartz instead of reasoning
about it, and it would have REGRESSED the mac. The chain, read out of
`quartz/util/path.ts` in the running image on 2026-09-06:

1. `transformInternalLink` calls JavaScript's `decodeURI` on the link.
2. `decodeURI` **deliberately leaves the reserved set `; / ? : @ & = + $ , #`
   still encoded** — that is what distinguishes it from `decodeURIComponent`.
3. `sluggify`, in the same file, then maps `&` to `-and-` and `%` to
   `-percent` when it builds the address.

So a folder called “Tasks & Quizzes”:

| written as | after `decodeURI` | slug | matches the folder? |
|---|---|---|---|
| `Tasks%20&%20Quizzes` | `Tasks & Quizzes` | `Tasks--and--Quizzes` | ✅ |
| `Tasks%20%26%20Quizzes` | `Tasks %26 Quizzes` | `Tasks--percent26-Quizzes` | ❌ 404 |

`Uri.EscapeDataString` keeps only `A-Za-z0-9-._~`, so it produces the second
row. And the failure is the worst kind: Obsidian decodes `%26` perfectly well,
so the teacher's vault looks healthy and only students see the break. “Tests &
Quizzes” and “Q&A” are ordinary folder names, so this is not a corner case.

Measured in the container, not inferred:

    decodeURI("Tasks%20%26%20Quizzes/Quiz.md")  ->  "Tasks %26 Quizzes/Quiz.md"
    decodeURI("Tasks%20&%20Quizzes/Quiz.md")    ->  "Tasks & Quizzes/Quiz.md"
    decodeURI("Work%28new%29/Quiz.md")          ->  "Work(new)/Quiz.md"
    decodeURI("Top%2010%25/Quiz.md")            ->  "Top 10%/Quiz.md"
    decodeURI("Caf%C3%A9%20Notes/Quiz.md")      ->  "Café Notes/Quiz.md"
    decodeURI("C%2B%2B/Quiz.md")                ->  unchanged

The set that survives untouched is therefore what JavaScript's `encodeURI`
leaves alone, minus three — `(` and `)` close a destination, `#` starts a
heading — and minus `/` and `:`, which the rename sheet refuses anyway. It is written into the contract as a literal string rather than
described, so either side can test a character against it:

    contracts/shared-rules.json
      -> specialNames.renameFolder.linkRewriting.escapingSet.leaveUnescaped
      =  ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789;,@&=+$-_.!~*'?

(This line lost its trailing `?` when the correction two paragraphs down
was written, and said the wrong thing for a day. Copy the string from the
contract, never from here — or better, assert against it: Windows'
`TheEscapingSetIsTheContractsCharacterForCharacter` pins the code's copy
against the contract's, which is the only check that catches a character
quietly added to or dropped from either.)

Everything else — the space, `%`, the quotes and brackets, and every non-ASCII
letter — is percent-encoded as UTF-8 **once escaping runs at all**, and
`decodeURI` gives all of it back. That last clause matters more than it looks:
nothing is encoded unless the name needs it, so `Café` goes into a link as
`Café` and only `Café Notes` becomes `Caf%C3%A9%20Notes`. Reading
`leaveUnescaped` as "always encode everything else" is the way the two apps
would write different text for the same rename, so there is a case pinning it.

### Two things this section said first and got wrong

Both were caught by an adversarial review that measured the pipeline instead
of reasoning about `decodeURI` in isolation, and both are kept here because
the correction is the useful part.

- **A lone `%` does NOT need escaping, and `%` is not in the trigger set.**
  The argument for it was `decodeURI("10%/Quiz.md")` throwing. Quartz never
  sees a bare `%`: it parses with `remarkRehype`, and the Markdown parser
  normalises `%` to `%25` on the way to HTML long before the link transformer
  runs. Measured in the container — `[b](Top10%/Quiz.md)` arrives as
  `Top10%25/Quiz.md`, `[a](Top%2010%/Quiz.md)` as `Top%2010%25/Quiz.md`.
  `WouldBreakAMarkdownTarget` on Windows is already right; do not add `%`.
- **`?` belongs in `leaveUnescaped`, and this section twice said otherwise.**
  It first claimed a folder named with `#` or `?` loses whichever spelling is
  used — true for `#`, false for `?`, because `sluggify` STRIPS a `?` from the
  real folder's name. It then claimed both apps "escape `?` anyway", which the
  mac's code did not do: `?` is not a trigger, so `Why?` always went in
  unescaped. What that left was a rule where the folder resolved when it was
  called `Why?` and not when it was called `Why Not?` — the escaped
  `Why%20Not%3F` slugs to `Why-Not-percent3F` and 404s, while the real folder
  and the unescaped link both slug to `Why-Not`. `?` is now in the set. It
  cannot arise on Windows, where a folder name may not contain one, but the
  encoder is a pure string transform so the case still runs there.

### What Windows owed — ✅ done 2026-09-07

Kept as it was written, because the reasoning is the point of the section and a
deleted obligation takes its reason with it. Landed on branch
`issue/31-rename-link-escaping`, commit `2bed7c83`: `Spelled` calls a
`PercentEncoded` driven by `leaveUnescaped` in BOTH branches, and
`FolderPathRewriterTests` deserialises every case. 1125 passed, 2 skipped, 0
failed (1031 before).

**A TWELFTH case went in with the fix**, and it is the part worth reading even
now the work is done. `Spelled` has two reasons to escape — the new name would
break a Markdown destination, or the OLD segment arrived percent-encoded — and
NONE of the original eleven reaches the second. Eight take the first (a space or
a bracket in the new name); the other three reach no encoder at all, because
`Assignments` and `Café` need no escaping and the wikilink case is not a
Markdown link. A `Uri.EscapeDataString` left behind in the second branch alone
would have passed all eleven. The new case
(`[q](All%20Tasks/Quiz.md)`, "All Tasks" → `Q&A`, expecting
`[q](Q&A/Quiz.md)`) is the only one that reaches it. It is named in
Windows proposed it, and it should be green on the mac already.

**What was originally owed, and why:**

**Three** of the eleven cases failed on Windows, and they were a request
rather than damage:

- **“an ampersand is left as it stands”** — `Tasks` → `Tasks & Quizzes`,
  expecting `[q](Tasks%20&%20Quizzes/Quiz.md)`.
- **“a comma is left as it stands”** — `Tasks` → `Unit 1, Day 2`, expecting
  `[q](Unit%201,%20Day%202/Quiz.md)`. **This is the one that will actually
  happen.** `Unit%201%2C%20Day%202` slugs to `Unit-1-percent2C-Day-2` while
  the folder slugs to `Unit-1,-Day-2`, and “Unit 1, Day 2” is this project's
  own naming pattern.
- **“a question mark is left as it stands”** — unreachable on Windows, where a
  folder name may not contain `?`, but the encoder is a pure string transform
  so the case still runs.

All three were ONE change in
`windows-app/Plantoir.Core/Models/FolderPathRewriter.cs`: replace
`Uri.EscapeDataString` in `Spelled` with an encoder driven by `leaveUnescaped`
above — in BOTH of its branches, which is the half that reads as optional and
is not. It keeps only `A-Za-z0-9-._~`, so it over-encodes `&`, `,`, `+`, `'`,
`!` and `*` alike. **Not all eleven break, and this line said they did.** The
ones that 404 are the eight characters `decodeURI` leaves encoded and
`sluggify` then turns into `-percent…`: `; , @ & = + $ ?`. `?` is an ordinary
member of that set and not a special case — `Why%20Not%3F` slugs to
`Why-Not-percent3F` by the same mechanism as the rest. (What IS peculiar to `?`
is why the UNESCAPED spelling works: `sluggify` strips it from the real
folder's name too, so both sides land on `Why-Not`.) `%27`, `%21` and `%2A` decode back to `'`, `!` and
`*` and resolve fine, so over-encoding those three is noise rather than damage.
Corrected 2026-09-07 by an adversarial review of the fix; the encoder is
unchanged by the correction, because the eight that DO break include both of
the ones a teacher will actually type. Nothing else in the rule changes, and the
mac's version of it is `spelled(_:likeThe:in:)` in
`mac-app/QuartzTeachers/Models/FolderPathRewriter.swift`.

**And a second obligation that is easy to miss** — done in the same commit;
the file deserialises `linkRewriting.cases` now, keeps its five as named
anchors, and pins the code's copy of `leaveUnescaped` against the contract's
string directly. That last check is the one worth copying to the mac: a
behavioural walk over the set can only test the characters the CODE has, so a
character quietly ADDED to either app's constant is invisible to it.
`windows-app/Plantoir.Tests/FolderPathRewriterTests.cs` used to retype five
cases of its own rather than deserialising `linkRewriting.cases`, so **nothing
on the Windows side went red on its own** — the three failures above are invisible
there until the cases are wired in. `contracts/README.md`'s own rule is to
deserialise and never retype, and this file was one of the places that did not
— until 2026-09-07.

The per-cent case, “a per-cent sign is escaped” (`Top 10%` →
`[q](Top%2010%25/Quiz.md)`), **passes on Windows already** and is not work:
`Top 10%` triggers escaping on its SPACE, and `EscapeDataString` encodes the
`%` with everything else. It is in the contract to pin what encoding COVERS,
not what triggers it.

### What was rejected, so it is not proposed again

- **Copying `Uri.EscapeDataString` for parity's sake.** Parity with a rule
  that produces a 404 is not worth having; the measurement above is what
  settled it.
- **Escaping wikilinks the same way.** The mirror-image mistake — Obsidian
  writes `[[All Tasks/Quiz 1]]`, plain.
- **Widening the rename sheet's refusals to cover `#` and `?`.** Refusing
  more names is a product decision nobody has made. For `#` neither spelling
  resolves in Quartz anyway (`%23` survives `decodeURI` and slugs through
  `-percent`); for `?` see the correction above.
- **Angle-bracket destinations, `[q](<Tasks/Quiz 1.md>)`**, were left out of
  that piece as pre-existing on both sides. They are handled on the mac since
  #97 (2026-09-26) — see "Inside angle brackets: the third spelling (#97)"
  below — and Windows matched them on 2026-09-30 (#338, parity bundle 2:
  `FolderPathRewriter`'s `(?!<)` plain pattern, its own `AngleLink` pass with
  a lookahead `>`, the name spelled plain inside the brackets; the live
  web-address defect — `[h](<https://…/Tasks/…>)` repointed — went with it).

### Inside angle brackets: the third spelling (#97)

CommonMark lets a Markdown destination sit inside angle brackets,
`[q](<Tasks/Quiz 1.md>)`, which is how a space goes into a link without `%20`.
Obsidian's own links never use this form, so it appears only where a teacher
typed it — but where it does, a folder rename missed it. The plain pattern
`(\]\()([^)\s]+)` reads up to the first space, so (measured with
`NSRegularExpression` against the pre-fix pattern; Windows had the identical
one in `FolderPathRewriter.cs` until 2026-09-30):

| Link | Target read before #97 | What a rename of `Tasks` did |
|---|---|---|
| `[q](<Tasks/Quiz 1.md>)` | `<Tasks/Quiz` | nothing: the first segment is `<Tasks` — **the defect** |
| `[q](<Tasks/Quiz1.md>)` | `<Tasks/Quiz1.md>` | nothing, for the same reason |
| `[q](<Units/Tasks/Quiz1.md>)` | `<Units/Tasks/Quiz1.md>` | rewritten **by luck**, percent-encoded |
| `[q](<Units/Tasks/Quiz1.md)` (no `>`: not a link) | `<Units/Tasks/Quiz1.md` | **rewritten**, although it is plain text |

**What the site does with the form (measured).** Quartz v4.5.0 has no
angle-link code of its own: `remark-parse` reads the destination (CommonMark),
`remark-rehype` makes the `href`, and from there it is the path every Markdown
link takes (`links.ts`). Measured on 2026-09-26 with `remark-parse@11`,
`remark-rehype@11` and `rehype-stringify@10` from npm — the majors in Quartz's
`package.json`, not the image's exact lockfile — under node 22:

| Written | `href` produced |
|---|---|
| `[q](<All Tasks/Quiz 1.md>)` | `All%20Tasks/Quiz%201.md` |
| `[q](<Tasks & Quizzes/Quiz.md>)` | `Tasks%20&%20Quizzes/Quiz.md` — the same as the escaped form |
| `[q](<Unit 1, Day 2/Quiz.md>)` | `Unit%201,%20Day%202/Quiz.md` — the same |
| `[q](<Top 10%/Quiz.md>)` | `Top%2010%25/Quiz.md` — the same |
| `[q](<Work(new)/Quiz.md>)` | `Work(new)/Quiz.md` |
| `[q](<All%20Tasks/Quiz 1.md>)` | `All%20Tasks/Quiz%201.md` |
| `[q](<Tasks/Quiz 1.md> "t")` | `Tasks/Quiz%201.md`, with `title="t"` |
| `[q](<Unit 1 > Review/Quiz 1.md>)` | **not a link** — literal text |
| `[q](<Unit%201%20%3E%20Review/Quiz 1.md>)` | `Unit%201%20%3E%20Review/…`; `decodeURI` gives back `Unit 1 > Review` |
| `[q](<Units/Tasks/Quiz1.md)` | **not a link** — literal text |

So the third rule is: **inside angle brackets, write the new name PLAIN**,
unless it contains `<`, `>` or a line break — the only characters that end the
form — in which case it is percent-encoded with the existing encoder (`%3C` and
`%3E` are outside the reserved set `decodeURI` keeps, so they come back as the
real characters). The parser normalises the plain spelling to exactly the
`href` the Markdown rule's escaping would have produced, and plain keeps the
shape the teacher chose — the only reason to write the brackets is to avoid
`%20`. The older second reason to escape still holds: a segment that ARRIVED
percent-encoded goes back percent-encoded.

**How the mac does it** (`FolderPathRewriter.swift`): a third `LinkStyle`,
`angleBracketedMarkdown`, with the pattern `(\]\(<)([^<>\r\n]+)(?=>)`. Two
details in it are load-bearing:

- **The closing `>` is a lookahead.** The rewriter writes the opening group
  and the rewritten target, then copies on from the END of the match; a
  consumed `>` would be deleted from every rewritten link, leaving
  `[q](<All Tasks/Quiz 1.md)` — which looks right in a diff line and is not a
  link. (Must-fail M6 below.)
- **The plain pattern gained `(?!<)`**, `(\]\()(?!<)([^)\s]+)`, so a
  destination that opens with `<` is read by exactly ONE pattern. Without it
  the plain reader still rewrites a deeper segment (percent-encoded, which
  resolves and so passes by eye), counts the link twice, and rewrites the
  unterminated `](<…` that is not a link.

The passes run wikilink, then angle-bracketed, then plain.

**Known limits, deliberately not handled.** A CommonMark backslash escape
inside the brackets (`<a\>b.md>`) is not decoded: the match stops at the `\>`,
so a folder segment before it is still rewritten correctly, but a folder whose
OLD name contains `<` or `>` written that way is not recognised — rare of rare,
since Windows refuses those characters in names outright. And the pattern does
not check what FOLLOWS the `>`, so two shapes that are not links (measured:
literal text to remark) are read as one — a `>` inside the target,
`[q](<Tasks/a>b.md>)`, and an unterminated `](<…` followed later on the same
line by a stray `>`. The harm is a rewrite of text that already names the
folder; a tighter lookahead was considered and not taken. A `#` in a NEW name
is not handled here any more than in the rest of this rule: `<Unit #2/…>`
goes in plain and becomes a heading fragment on the site, where the escaped
`%23` would 404 anyway (see the `#` bullet under "What was rejected"), while
Obsidian — unmeasured — would read the two differently. Obsidian's reading of the
form was **not measured**; its help documents `[text](<Note with spaces.md>)`
as supported, and the site half above is the one that was.

**Contract.** Twelve cases in `shared-rules.json` →
`specialNames.renameFolder.linkRewriting.cases` (13 → 25), with the
measurements in `insideAngleBrackets`. Both suites already deserialise that
list, so nothing had to be wired. **Windows fails eleven of the twelve on
arrival** (all but the page-name guard), and that is the request.
**The web-address guard is red there because it is a LIVE Windows defect
today, not only a missing feature**: `FolderPathRewriter.cs`'s `Scheme`
test is anchored at the start of the target, and the plain pattern reads
`<https://example.com/Tasks/handout.pdf>` with its `<`, so the scheme is not
seen and a rename of `Tasks` repoints the link at a page on somebody else's
site — the 2026-09-01 bug again. The mac never had it: its test is "a colon
before the first slash", which `<https:` still passes. (The plan's "identical
pattern, so identical results" missed that the two apps' out-of-course tests
differ; found by the implementation review, via a line-for-line Python port of
the .cs, not under `dotnet`.) The mirrored fix clears it for free — the angle
target is then `https://…` and the anchored scheme matches — but a PARTIAL
port that adds `(?!<)` and forgets the angle pass turns that case green only by
accident, because the link is then read by nobody. `FolderPathRewriter.cs` owes `(?!<)` on `MarkdownLink`, the angle
pattern with its `>` as a lookahead, and a third branch in `Spelled`. The trap
that passes review is keeping the Markdown rule inside brackets: it writes
`<All%20Tasks/…>`, which resolves, and it fails five of the cases.

**Must-fails run on the mac** (each applied, seen red, reverted; counts are
contract cases): dropping the angle pass — 9 red; dropping `(?!<)` — the
unterminated case red and the link counted twice; spelling the angle style by
the Markdown rule — 6 red; never escaping inside brackets — the `>` case red;
dropping the arrived-encoded branch for this style — the `%20` case red;
consuming the `>` — 9 red, every rewritten link losing its `>`.

**Rejected:** applying the Markdown escaping inside the brackets (resolves, but
rewrites the teacher's spelling, and passes every guard); dropping the brackets
and converting the link (edits text beyond the folder segment); escaping `>` as
`\>` (remark accepts it, but it is a second escaping mechanism with Obsidian's
reading unmeasured); one pattern with an optional `<` (the `>` would have to be
consumed or re-appended, and the spelling has to know the style anyway).

**`PageReferences`, the copy's reader, reads the third spelling too** (since
[#325](https://github.com/russellgordon/plantoir/issues/325), 2026-09-26). Its
Markdown pattern used to be `\]\(([^)\s]+)`, which read `](<one pic.png>)` as
`<one` — a name that names nothing, so copying a page between courses silently
left such a picture behind. Each Markdown shape is now read by ONE pattern, and
both are REFERENCES to this section's constants (`markdownLinkPattern` with
its `(?!<)`, `angleBracketedLinkPattern` with its lookahead `>`), never copies.
A new `.angleBracketed` kind is read like `.encoded` — percent-decoded, the raw
text when it does not decode, because remark resolves `<a%20b.png>` and
`<a b.png>` to the same address — and written back through
`FolderPathRewriter.spelledInsideAngleBrackets`, this section's own rule:
PLAIN inside the brackets unless the name holds `<`, `>` or a line break, or
the old segment arrived encoded. All four of its shapes go through the code
and comment mask. Measured at 0 angle-bracket destinations in `support/`; it
is here because a teacher can type it. `copyingAPageBetweenCourses.cases`
carries two cases, and `PageReferencesTests` pins the rewritten text (which a
case's `expect` does not carry).

**The walks read Markdown-style page links too** (folded into #325 by the
director's ruling). Publishing, the unpublish referrer test, the links
question and check_section read wikilinks only until then, and never a
Markdown-style link in any spelling: a teacher with Obsidian's "Use
[[Wikilinks]]" turned off published classes without a page they use.
`AssistSectionGraph.everyLinkAsWritten` now reads both Markdown shapes,
through the same mask, resolving a destination by its last component the way
a wikilink resolves (`shared-rules.json` → `followingLinks.markdownStyleLinks`).
Measured: ONE local Markdown link in all of `support/` —
`ENL1W/shared/Concepts/Indigenous Storywork.md`, `["I Lost My Talk"](I%20Lost%20My%20Talk)`,
itself dead on the site (it resolved relative to `Concepts/` while the page is
in `Reading/`) — now a wikilink. **Not done:** a page RENAME does not rewrite a
Markdown-style link to the renamed page (a folder rename does, above).

---

[◀ Previous: The Build Pipeline](05-build-pipeline.md) · [Back to index](README.md) · [Next: Deployment ▶](07-deployment.md)
