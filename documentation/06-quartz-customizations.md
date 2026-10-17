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
counterparts inside the image. The explorer's STYLES are not among them:
`explorer.scss` is Quartz's own, and the one thing added on top of it — the
page marker — comes from `support/quartz` (H). The first three implement the **two-tier
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
| C2-22 | **Backlinks "structural pages" set** | `quartz/components/Backlinks.tsx` | Rewrites the `const structural = new Set<string>([…])` block behind the `// CQ4T-STRUCTURAL-ANCHOR` comment in `support/Backlinks.tsx`, inserting every mapped curriculum folder's name and every coverage map's title (#128 — `Curriculum Coverage` always among them) in both title and slug form — the slug being Quartz's own (`_quartz_segment_slug`: `Q&A Curriculum` is `Q-and-A-Curriculum`; until #569 only spaces were replaced, so a folder named with `&` stayed in every panel). Those pages link to everything by nature, so without this every content page's backlinks panel is dominated by the curriculum index and the generated coverage map — noise that buries the pages a teacher actually wants to see listed. |
| C2-22b | **Backlinks overall-expectation map (#505)** | `quartz/components/Backlinks.tsx` | Rewrites the one `const overallChildren = new Map<string, string[]>([…])` line behind the `// CQ4T-OVERALL-ANCHOR` comment, on every build and with or without a coverage map (`set_backlinks_overall_children`, called right after C2-22): each overall expectation page's slug, mapped to its specific expectations' slugs (`overall_backlink_children`). See D1. |
| C2-23 | **Page title text shrinking & navbar vertical centering** | `quartz/styles/base.scss` (appended) | Prevents the navbar course code and section number from wrapping onto a second line on mobile by dynamically scaling the page title font size (`clamp(0.875rem, 4.5vw, 1.75rem)`) down to 50% of its original size and setting `white-space: nowrap`, while vertically centering the course emoji, code, section, and the light/dark mode toggle button with the adjacent search field. |
| C2-24 | **Deploy domain & `baseUrl` sync** | `quartz.config.ts` | Sets `baseUrl` to the section's actual public domain (from advanced custom domains, `.netlify_sites/`, or `.cloudflare_sites/`), or clears it when unpublished. Ensures OpenGraph (`og:image`, `og:url`) and Twitter card tags point to the teacher's live site rather than the stock `quartz.jzhao.xyz` default. |
| C2-25 | **The site's icon** | `quartz/static/{favicon.ico,icon.svg,apple-touch-icon.png,icon.png}`, `content/favicon.ico` | `install_favicon()` copies the generated set from `/opt/support/favicon` (see `scripts/brand_images.py`, which draws it from `mac-app/Plantoir.icon`). `icon.png` is overwritten rather than merely unlinked, so a built site carries no Quartz logo even where nothing points at one. `favicon.ico` is installed TWICE on purpose: the `static/` copy is what the A5 tags link, while the CONTENT-ROOT copy is the only way to get a file to `public/favicon.ico` — Quartz's Assets emitter copies non-Markdown files out of `content/` unchanged, and the Static emitter cannot write above `public/static/`. That root copy is what answers the implicit `GET /favicon.ico` made by feed readers, link unfurlers and older browsers that never read the page. It runs after the content folder is rebuilt from scratch, because a copy made any earlier is deleted a few lines later — silently, since the page still looks correct. |
| C2-26 | **KaTeX from the site itself (#494)** | `quartz/plugins/transformers/latex.ts`; `quartz/static/katex/` | Quartz v4.5.0's `externalResources` linked `cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.css` and `contrib/copy-tex.min.js` on EVERY page (400 links each on a built ICS3U site), while its own lockfile installs **0.16.21** and rehype-katex renders every formula with that at build time — so sites were rendered with one version and styled with another, and the maths depended on a third party and a network. `patch_katex_local` (marker `PLANTOIR-KATEX-LOCAL`, idempotent, independent of C2-20's import) replaces that block with two `additionalHead` functions: `<link rel=stylesheet href="<pathToRoot>/static/katex/katex.min.css" spa-preserve>` and `<script src=".../static/katex/contrib/copy-tex.min.js" defer spa-preserve>`, relative to each page so a site served under a folder finds them, kept across the site's page changes like `index.css`; the 404 page, served at any depth, links from the `baseUrl`'s path (review N6, Head.tsx's own rule). `install_katex_assets` copies the files from Quartz's own `node_modules/katex` every build (05 → Runnable code, step 4): the stylesheet (23,352 bytes), copy-tex (1,673), the **20 woff2 faces** (259,792) and the MIT licence — 284,817 bytes on EVERY site, woff2 only because every browser that can run a site's code takes woff2 first. Netlify's CSP loses `https://cdn.jsdelivr.net` by itself (07). **Rejected:** gating it per site on maths (Python cannot tell maths the way remark-math does — `$` in prose, currency — and a wrong guess breaks every formula silently; the cost is about 2% of Pyodide, uploaded once by content hash); all three font formats (1.10 MB); inlining the CSS into index.css (a generated SCSS file from node_modules every build); absolute `/static/katex/` (breaks a folder published under a subpath). **The print path had to follow** (#455 review S1): a link kept across page changes keeps its RELATIVE href, which then resolves against the new page — one folder off. print.inline.ts now takes every stylesheet for the print frame from the address the sheet was really fetched from (`link.sheet.href`), which fixed the same latent fault in its `index.css` lookup; measured by `browser-checks/maths_offline.mjs`: with the old code a handout printed after a page change from the top of the site to a page one folder down got a 404 KaTeX stylesheet (0 rules), now 249 rules. **The regression the plan expected did not happen:** a folder publish OPENED AS A FILE was expected to lose KaTeX's faces in Chrome (an opaque origin); measured 2026-10-17, Chrome for Testing 155 and Safari 26.6 both loaded `KaTeX_Main` and `KaTeX_Math` from `static/katex/fonts/` beside a page opened from disk, so the maths keeps its look offline from a file too (it used to need the network for the CDN). |
| C2-27 | **A folder page's table of contents (#520)** | `quartz.layout.ts` | `_wire_list_page_toc`, one of `wire_quartz_additions`' edits, puts `Component.DesktopOnly(Component.TableOfContents())` — the content layout's own — in `defaultListPageLayout`'s right column, which is `[]` in v4.5.0, and touches nothing else. Quartz renders every `folder/index.md` with that layout (and the tag pages), so a curriculum folder's index with `enableToc: true` and five headings of its own showed no table of contents: the data was computed and placed nowhere. Quartz's own rule then decides, as on any page — shown by default, `enableToc: false` hides it, and only with two or more headings of depth 3 or less on the page itself — so tag pages and folder pages with no headings of their own are unchanged. Measured on the #520 plan by editing a built layout and re-running Quartz: the curriculum index showed "Navigate this page" with its strand headings, while `Concepts/index`, `tags/A1` and the front page stayed at 0; expectation pages had shown a table of contents all along. Idempotent, every build; a list layout of another shape warns and is left alone. **Chosen** (ruling Q2 on the plan): on every folder page with the headings, as Quartz does on every other page — 49 of 1,009 folder index pages across `support/` show one, 9 of them without having asked. **Rejected:** only on folder pages that say `enableToc: true` (a wrapper component of our own, and a rule unlike every other page's). `scripts/test_folder_page_toc.py` drives it through `wire_quartz_additions`; verify.sh 6h reads EXC2O's built `Curriculum/index.html`. |

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

Complements the locale change, and carries three changes. First, an
`excludeBacklinks: true` frontmatter flag that suppresses the backlinks panel
on a specific page — useful where "when did we do this?" makes no sense (a
style guide, a syllabus) or where the link graph would mislead. Second, the
`CQ4T-STRUCTURAL-ANCHOR` set that C2-22 rewrites each build, which keeps the
curriculum indexes and the generated coverage maps out of every other page's
backlinks. Third, the `CQ4T-OVERALL-ANCHOR` map that C2-22b rewrites each
build, which makes an overall expectation's page list the lessons that did
its specific expectations (#505, below).

#### An overall expectation lists its specific expectations' lessons (#505)

**The rule** (`contracts/shared-rules.json` → `curriculumRules.overallBacklinks`,
run by `scripts/test_overall_backlinks.py`): "When did we do this?" on an
overall expectation's page (B1) lists every page that links B1 **or** any of
its specific expectations (B1.1, B1.2, `b1.3`) in the same curriculum folder.
One unlabelled list, each page once, in Quartz's order: the component runs
ONE filter over `allFiles` with `targets = [slug, ...overallChildren.get(slug)]`,
which de-duplicates for free. A specific expectation's page is unchanged
(direct links only), and structural pages stay out exactly as before.

**Why the overall page was empty.** Not the embed form and not Quartz skipping
the page: the data. Classes connect to SPECIFIC expectations. Measured on the
MPM2D example course: the only page linking "B1. Using Linear Systems to Solve
Problems" was the Curriculum index, which is structural; across all example
content, 44 pages outside a curriculum folder link an overall page directly,
almost all of them a Learning Goals page. Built with this change (MPM2D,
section 1 and section 2 alike), every one of the ten overall pages went from 0
listed pages to between 4 and 15 (B1: 13), each list equal to the union of the
direct links to the overall page and its specific expectations, while all
specific expectation pages list exactly their direct links (B1.3: 2, as
before).

**How.** `overall_backlink_children(content_root, plan)` reads each mapped
folder with `_collect_expectations` and groups specific expectations under
`overall_of(code)` — the coverage map's own rule, so the panel and the map's
overall chips count the same work. It is built PER FOLDER (two curriculum
folders can each have a B1, and each gathers only its own), and slugs are
written as Quartz v4.5.0's `sluggify` writes them (white space to `-`, `&` to
`-and-`, `%` to `-percent`, `?` and `#` dropped) by `_quartz_page_slug`,
which applies `_quartz_segment_slug` to each folder and to the page's name.
A digit-first or College
Board code has no overall expectation, so it gathers nothing. The map is a
JavaScript `Map`, not an object literal, so a page whose slug is
`constructor` finds nothing rather than a function.

**The coverage map's links use the same slug (#569).** They used an older
helper, `_quartz_slug`, that replaced only spaces. Measured on the #569 plan
with the ICS3U example course: renaming `Curriculum/A3. Subprograms.md` to
`A3. Subprograms 100% Done.md` stopped the build — Quartz said `URI malformed
at decodeURI … transformInternalLink` on `Curriculum Coverage.md`, then a
traceback and exit 1, with no sentence for the teacher. With the map's cells
and chips on `_quartz_page_slug` the same course built (exit 0) and the chip
linked `./Curriculum/A3.-Subprograms-100-percent-Done`, the page Quartz had
emitted. A `#` ("A3. C# Basics") made the rest of the old href a fragment, and
a folder named `Q&A Curriculum` gave links to `Q&A-Curriculum/…`, which Quartz
does not serve. The same plan measured the backlinks side: with that folder,
the structural set held `Q&A Curriculum` and `Q&A-Curriculum`, so its index
(slug `Q-and-A-Curriculum/index`) was listed on every expectation — the noise
#505 removed; it now holds `Q-and-A-Curriculum`. The slug is taken from the
whole segment, never `Path.stem` (a folder `Gr. 9 Curriculum` would lose
`. 9 Curriculum`). Measured on the #569 review: the new rule and the old one
agree on all 13,998 file and folder names under `support/`, so no existing
link moves. **Escaping was chosen over refusing** such a name with a folder
problem: Quartz already serves the page at its slug and only our href was
wrong, so a refusal would have given the teacher a sentence to act on where
nothing needs doing. **Not de-duplicated:** a name with nothing to slug is
still written twice into the structural set, as before, so the component's
bytes for every existing course are the ones `scripts/test_coverage_maps.py`'s
goldens hold. Cases: `curriculumRules.coverageMapLinks` (run by
`test_coverage_maps.py`) and a fifth `overallBacklinks` case; verify.sh 6h
plants `Curriculum/Z1. Planted 100% Overall.md` in the Example Course and reads
the built map.

**Rejected.** Direct links only (the panel would say "Not yet addressed in
class." for work the coverage map counts). Two lists — direct links first,
then the specific expectations' pages — or a labelled second list ("through
B1.3"): a page linking B1 and B1.3 would appear twice, and the label draws a
distinction the coverage map does not make. A map keyed by code across every
folder: two folders' B1 pages would each collect the other's lessons.

**Checked** by `verify.sh` 6h (continued), on a real EXC2O build: a page
embedding only `![[A2.1]]` must be listed once on the A2 page (it is listed
nowhere there on the old component — measured), and a page embedding both
`![[A2.1]]` and the A2 page must be listed once on A2 and once on A2.1.
Windows builds with the same `build_site.py` and the same component, so it
inherits this unchanged; `PythonToolchainTests` discovers the test.

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
folders", and asks Revise With ▸ Claude… to draft one page per expectation
code from the framework they have — `1.A`, `CRD-1.A` and so on, one page
each, named by the code alone. The next preview or publish draws a second
coverage map for it, linked from Key Links under that folder's entry.

---

## F. Additions installed every build: printable pages (#454, v1.6.0)

A page whose settings say `printable: true` prints as a worksheet that reads
like the teacher's LaTeX handouts (#499, F8); a page that says
`printPdf: <file in Media>` hands out a PDF the teacher already has. The
rules are data in [`contracts/shared-rules.json`](../contracts/shared-rules.json)
→ `printablePages` and [`file-formats.json`](../contracts/file-formats.json) →
`pageOptIns`; this section says how the site does it and why.

**Compatibility, stated first because it is the promise.** A page that does
not opt in renders exactly as it did before #454 (its sidebar aside, since
#515: below): its HTML carries no print
markup at all — no wrapper, no button, no style, no `@page` — and its date
line is the plain `<p class="content-meta">` it always was. Measured on EXC2O
(implementation review, `origin/dev` 8178eeaac against the branch): **all 300
pages that do not opt in are byte-identical** once what Quartz already varies
between ANY two builds is set aside (the explorer's random list id, build-time
dates on curriculum pages, and the order of tag-list entries sharing one of
those dates); the only pages that differ are the 7 that opt in. Every new CSS
selector is scoped to a printable page or the handout frame — or to figure
markup (`.pl-figure`, G, #485) — with TWO exceptions: #501's print block,
below, and since #515 the sidebar's page marker (H), which is NOT print-scoped and changes every page's on-screen
sidebar — and nothing adds an `@page`. So a page that does not opt in still
has byte-identical HTML, but since #515 its sidebar does not RENDER exactly as
it did before #454: page rows inside an open folder carry a dot. **verify.sh gates
it on every run**: section 5 plants "Printable Not Opted", the worksheet with
only `printable: true` taken out, and the 6h printable-pages check fails if
that page carries `plantoir-meta-line`, `plantoir-print`, `data-plantoir` or
`@page`, or if its date line is not the plain one straight after its title.

**Its HTML is unchanged; its PRINT is not, since #501 (v1.7.0, F9).** The
shared `index.css` carries one `@media print` block scoped
`html:not(.plantoir-printable):not(.plantoir-print-frame)` that hides the
sidebars and caps the column under ⌘P (`printablePages.everyOtherPage`). So
every page's stylesheet changed (`index.css` +316 bytes, measured on EXC2O in
the dev-test image) while its HTML stayed byte-identical (237 of 304 pages
once Quartz's random list ids are set aside — the explorer's AND a table of
contents' `<ul class="overflow">`; the other 67 differ only in the build-time
`<time datetime>` on Curriculum and tag pages and the order of list entries
sharing one, the variances named above), and
`postscript.js` identical but for the explorer id. The 6h check also looks
for the block's text in `index.css`, and `browser-checks/print_plain_page.mjs`
prints a page that does not opt in and reads its ink back. **WITHDRAWN:** this
paragraph used to say "⌘P of a page that does not opt in prints the same pages
with the same text" (Chrome for Testing 155, `pdftotext` identical, and Safari
26.6). True, and blind: the words Quartz's folder list covered on paper stayed
in the PDF's text layer, so a text comparison found them all (F9).
What every site DOES change is its two shared bundles, measured on EXC2O
against `origin/dev`: `postscript.js` 74,590 → 85,344 bytes (+10,754) and
`index.css` 35,386 → 41,045 (+5,659) on the final branch (the review measured
+10,525 and +5,659 at 4c587f670, before the light-page wait and the corner
change), every rule in them scoped so it cannot touch an ordinary page.
Those are history, as #501's +316 above is: since #515 (v1.7.2) `index.css`
also carries the sidebar's page marker, 454 bytes, which DOES touch every page's
sidebar on screen (H); `postscript.js` is unchanged by it.

### F1. The files and how they reach a section

New files, not patches, live in `support/quartz/` at the path they take in a
section's Quartz copy, and `build_site.install_quartz_additions` copies them in
on EVERY build (ALWAYS section), so a section built before them picks them up
on its next preview:

| File | What it does |
|---|---|
| `components/PlantoirMetaLine.tsx` | Wraps the CONTENT layout's `ContentMeta()` only (folder and tag pages never get a button). Not opted in → renders the inner date line and nothing else. `printPdf` → a plain `<a … target="_blank">` to `Media/<Quartz slug of the file>`, built with Quartz's own `slugifyFilePath` so the address is the one the Assets emitter writes (measured with `&` and a space: `Media/plantoir-print-fixture--and--key.pdf`). `printable` → Print, the summary of a `<details>` menu (#499, decision 29: Portrait / Landscape radios, then Questions only, Answers only, Both — nothing prints until a choice), at the TRAILING edge (`margin-inline-start: auto`, so right-to-left too), present even when the date line shows nothing (decision 6), and an inline `<style id="plantoir-print-page">` with the Latin Modern `@font-face` rules, the `@page` box (margins, NO size — F4) and its four corners for ⌘P, and the code box. The page's `title` and `description` travel in `data-settings` for the footer and the subtitle. Reads `quartz/plantoir_print.json` with `fs` rather than importing it, so a missing file costs the button, never the build. Forwards the inner component's `css`/`afterDOMLoaded` (review S7). Both the Print button and the PDF link open with a printer glyph (#497): an inline `<svg>` stroked in `currentColor`, 1em square, `aria-hidden` so the button is still read as its label alone, drawn the way Quartz draws its search and dark-mode icons — no image file, hidden on paper with the button, and nothing on a page that does not opt in. |
| `components/scripts/printRules.ts` | The rules with no DOM and no imports — answer/question/unfold roles, labels and answer places, question numbering, part letters and columns, title cleaning, page labels, the paper box, the footer, which callouts keep a box, the code box, the completeness decision, and the `@page`/`@font-face` text both ⌘P and the handout write — so `scripts/check_print_rules_against_the_site.py` can bundle it with the scaffold's esbuild and run every contract case in Node (verify.sh). `PlantoirMetaLine.tsx` imports it too, so ⌘P's page box and the handout's cannot drift. |
| `components/scripts/print.inline.ts` | The button, the handout, ⌘P and the preview handoff (F3–F5). Bundled into every site; inert unless the page carries a printable meta line. |
| `components/styles/sidebarPageMarker.scss` | Not print: the sidebar's page dot (#515, H). Rides on `PlantoirMetaLine`'s `concatenateResources` as `figures.scss` does, so no wiring edit; reaches every page's `index.css`. |
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
answer kinds and title words, and the Curriculum connection's heading words.
No default mode since #499: nothing prints until the teacher chooses. Corners are Python
because they depend on the COURSE's settings, which the site cannot read.

### F2. The engine, gated per site

Paged.js 0.4.3 (`/opt/vendor/pagedjs`, see 02) — and, since #499, the six
Latin Modern faces beside it in `fonts/` (631,940 bytes, F8) — is copied into
a section's `quartz/static/pagedjs` only when at least one page students can see opts in
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
3. Clone the title and article; the page's Curriculum connection is taken
   out of the copy first, in every mode (#498, below in F4). The questions
   are numbered in page order (`printablePages.questionItems`, F8); answers
   are lifted, with their place (`answerPlace`: "7.", "3. a)",
   "Practice · 3.", the nearest heading, else "Answer n"), into an answer key
   headed "Title — Answers" on a fresh page — their bodies only, never the
   callout around them, the parts of one question gathered under its number
   in columns; question headings and question callouts become numbered items,
   and an ordered list inside one becomes lettered parts; every other folded
   callout opened in place; "(click to expand)" dropped; code longer than 25
   lines may split and flows rather than scrolls; an `svg` with a size and no
   `viewBox` gets one; code line numbers written out (Paged.js does not carry
   Quartz's line counter: every line printed "1") with each block's digit
   count, so the number box is as wide as "110".
3a. Every picture decoded and given `width`/`height` from its NATURAL size
   (a `|300` width kept) — never from the screen, where Quartz's
   `content-visibility: auto` measures every picture below the fold 0 × 0
   (#499 review B1). Then every element that carries words or a picture is
   stamped for the completeness check (step 6a).
4. An iframe ON SCREEN but invisible (`opacity:0`): off screen, Safari
   paginated about one page per 8 s (11 pages ≈ 90 s); on screen, 192 ms.
5. Paged.js paginates with `index.css` plus a page box written by
   `printRules.pageBoxRules` with the chosen paper's `size` and the corners,
   the bottom two being per-page `--plantoir-footer-left` and
   `--plantoir-page-label`, PLUS the break and overflow rules spelled out
   unscoped, by classes the handout adds rather than `:has()` — Paged.js decides breaks by matching
   selectors against the content BEFORE it sits under the frame's `<html>`,
   so `html.plantoir-print-frame .plantoir-answers { break-before: page }`
   matched nothing (measured: the answers began mid-page). Margin boxes use
   no-break spaces: "Page 1 of 3" wrapped onto three lines in Safari — except
   the top-left corner, which may take two lines: a long school name sharing
   it with the course code printed ON TOP of three blanks (review S3,
   measured with "St. Michael's Catholic Secondary School of the Arts ·
   EXC2O"; two clean lines after, handout and ⌘P). The top corners sit on
   their bottom edge, so the blanks line up with the name's last line.
6. Pages labelled "Page n of m" then "Answers n of m" (decision 3), the
   footer naming the page ("Title · CODE", "Title — Answers · CODE").
6a. **Completeness (#499, review B2):** every stamped element must be on a
   page and none may run more than 1.5 px past its page's content box (or be
   a loaded picture laid out 0 px tall). Otherwise NOTHING prints, the button
   says `printablePages.words.incomplete`, and the console names what ran
   off (`149 span.katex-display 137px`). Measured: it refused the verify
   fixture's 30-line displayed formula on LANDSCAPE paper (taller than the
   6.85 in content box; a formula is one line box and cannot split) and
   passed it on portrait; the fixture now carries 20 lines.
6b. `print()`; restored again when `print()` returns, in case a browser never
   sends `afterprint` (review N4). That is right where `print()` waits for the
   dialog to close — Safari, Chrome and Edge, measured — and UNMEASURED in
   Firefox, where a `print()` that returned at once would take the frame away
   mid-print. `afterprint` restores the theme and removes the frame (measured
   in Safari: Cancel fires it too; the page came back dark with no frame).

**Fallback:** Paged.js missing or failing → the same frame printed by the
browser, corners where it prints margin boxes (Chrome, Edge), one count for
the whole document. Measured in Chrome: 3 pages, answers on a fresh page.
Since #499 the frame's `<html>` says which path ran
(`data-plantoir-print-path="paged"|"fallback"`, with the counts beside it)
and the console warns once, and the browser check FAILS if the fixture takes
the fallback. The fallback still prints everything, so it shows no sentence
to the reader: one telling Safari users their page numbers are missing would
be wrong in Chrome, which prints them (review S6 considered; REJECTED).

### F4. ⌘P on a printable page

Questions only, no pagination (decision 7): answers hidden, question bodies
hidden, everything else open, sidebars hidden, titles cleaned for the print
and restored after. Since #499 in the handout's look (Latin Modern, no
callout boxes but the example's, code in its hairline box), and its page box
writes margins and NO `size`, so the browser's own dialog chooses portrait or
landscape in every browser — measured with Chrome's printer asked for
landscape: 792 × 612 now, 612 × 792 before (the page's `size: letter` won).
Not restructured: no numbered items or lettered parts, which the handout
builds from a copy. A dark page prints light; Mermaid diagrams already drawn
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

**The Curriculum connection is never printed (#498, v1.6.0, Russell
2026-10-09)** — not in the handout in any mode, not under ⌘P on a printable
page. It says which expectations a page addresses, for the teacher and the
coverage map; on a worksheet it is noise. The rule and its cases are
`printablePages.curriculumConnection`: a heading reading "Curriculum
connection(s)" in any capitals (closing colon allowed; one that merely
contains the words is the teacher's and prints), and everything after it to
the next heading of the same or a higher level — or to the page's footnotes,
which Quartz puts after the LAST section as a sibling (`section[data-footnotes]`)
and which must print: the first version left them off the PDF of a page
ending in a Curriculum connection (review finding, measured; the fixture now
carries a footnote and a second, final Curriculum connection). **The build emits no hook,
and none was added:** measured on the verify fixture, the skeleton
templates' `%%curriculum-start%%` markers are comments Quartz strips, and the
section arrives as a bare `<h2 id="curriculum-connection">` followed by its
siblings (an empty `<p>`, the transcluded expectation's `blockquote.transclude`,
a deeper heading) directly in the article. So `print.inline.ts` marks those
siblings `data-plantoir-curriculum` on load — printable pages only, by
`printRules.leftOffPaper` — ⌘P's stylesheet hides them and the handout
removes them before lifting answers, so no heading of it ever labels one.
REJECTED: a wrapper class added by `build_site.py` (it would change the HTML
of every page with the block, opted in or not, against the compatibility
promise above, for a section only printing needs to find); a pure-CSS sibling
selector on `#curriculum-connection` (the id gains a suffix when a page has
two, and CSS cannot stop at "the next heading of the same level" without
enumerating levels). Measured, Chrome for Testing 155: the verify fixture's
section is on screen, in none of the three handouts and not in the ⌘P PDF
(`pdftotext`: 0 lines of it, "Practice" after it still printed); the same
block on the page that did not opt in prints under ⌘P as before; the old code
printed it in both handouts and under ⌘P (`browser-checks/print_handout.mjs`,
verify.sh 6h, proven against the old build). Cost: `postscript.js` +1,068
bytes and `index.css` +59 against the figures above; no page that does not
opt in changes.

### F5. Plantoir's own preview

A `WKWebView` inside the app shows no print dialog and opens no new windows
(review B1, measured). So when the page finds the app's `plantoirPrint`
message handler it says `printablePages.words.openingInBrowser` and posts
`{mode, paper, url}`; the app opens the page in the default browser with
`#plantoir-print=<mode>&paper=<paper>` (#499), and the page prints at once there. Measured in
Safari 26.6, light, real print sheet then Save as PDF: "All 3 Pages", the
diagram DRAWN (no source text — the first version printed it as text, B1),
the hash removed afterwards.
New-window links, the PDF link among them, open in the browser too. See 09.
**Windows depends on the check's exact shape (#496, #539).** WebView2 has no
`window.webkit`, so Windows' preview INJECTS exactly
`window.webkit.messageHandlers.plantoirPrint` (`PreviewBrowserHandoff.PrintShim`)
and forwards the message to the app. Keep `print.inline.ts`'s check and the
`{mode, paper, url}` message as they are: a renamed handler, a wider
`window.webkit` feature test or a Safari sniff breaks Print in Windows' preview
SILENTLY, and Windows' `PreviewBrowserHandoffTests.TheShimGivesThePageTheShapeItsPrintCodeLooksFor`
goes red — say so in that change's `windows` issue.

### F6. Figures (decision 13, for #485 E1)

An engine's figure is `<figure class="pl-figure pl-<engine>">` with an SVG
that has a `viewBox` (or an `<img>` with its own size) and a `<figcaption>`.
On paper it never splits, is scaled to the width — and since #499 to the
page's height too, `object-fit: contain`, the same cap as every picture and
Mermaid diagram — keeps its own resolution, and any dark-mode filter is removed. A browser-drawn engine registers in
`window.plantoirPrint.prepare`.

E1 conforms (v1.7.0): `pl-tikz` and `pl-functionplot`, with three additions
of its own that hold on EVERY page, not only printable ones — see G4.

### F7. Measured matrix (macOS 26.6, M4 Pro), the verify fixture

| Browser | With answers | Questions only | Answers only | ⌘P | Press → print |
|---|---|---|---|---|---|
| Safari 26.6 | 3 (2 + 1) | 2 | 1 | 2, small (F4) | 760 ms |
| Chrome for Testing 155.0.8059.39 | 3 (2 + 1) | 2 | 1 | 2, corners | 131–214 ms |
| Edge 155.0.4283.45 | 3 (2 + 1) | 2 | 1 | 2, corners | 124–212 ms |

Light and dark gave about the same page counts in every cell. Chrome and Edge were
driven by puppeteer-core 24.10.0 (handout: the frame's document as printed,
re-rendered by `page.pdf`; ⌘P: `page.pdf` with the page's `@page`). **Trap:**
Edge's first launch from a Homebrew cask waits on macOS's "downloaded from
the Internet" prompt, and until it is answered `requestAnimationFrame` never
fires, which made Paged.js hang and looked exactly like an Edge bug.
Not measured here: a site published to Netlify or Cloudflare (the files are
identical to the preview's). Windows, after #499's look (so not comparable
row for row with this table): `print_handout.mjs` OK in headless Edge 155 on
a native build, questions only 12 / answers only 1 / both 13 pages portrait,
14 / 2 / 16 landscape (#496, 2026-10-15; `12-windows-app.md` → "Printable
pages", which since 2026-10-15 also has the headed measurements: the
browser's print window after the hand-over, 1 sheet questions only).
These counts are from before #499's look; F8 has the counts after it.

### F8. On paper: the look of a handout, and nothing lost (#499, v1.6.0)

Russell's print of a real page, MVVM Review, on 2026-10-09 (Safari,
landscape chosen in its dialog): 18 pages of 792 × 612, every page clipped —
no footers or page numbers, 18 lines of code, three questions and two steps
of the instructions lost, every answer in a tinted box under a coloured icon,
code line numbers reading "1, 6, 1, 7". Decisions 26, 28, 29 and 30 and the
director's rulings 499-1 to 499-6 set the target: his LaTeX handouts
(`Get Ready for Linear Systems`, 11pt article, lmodern).

**What prints (contract: `questionItems`, `paper`, `footer`, `paperLook`,
`completeness`, `labels`, `modes.menu`).** Letter paper, 0.75 in margins and
0.9 in at the bottom; Latin Modern Roman 10.95 pt, the title in LM Sans bold
17.28 pt, section headings 12 pt, the page's `description` as a grey
subtitle; questions numbered "1." in a 2.2 em margin (from `### Question n`
headings and `question` callouts), an ordered list inside a question
lettered a), b), c) in 3, 2 or 1 columns by length (a formula's characters
count 1.5 — counted plainly, question 4's parts were squeezed into three
columns and wrapped); answers in a key headed "Title — Answers" with the
same numbers, parts gathered in columns; no box behind any text except an
`[!example]` (the peach tcolorbox) and fenced code (a 0.5 pt #999 hairline
box, no fill, its numbers counting on across a page break, the box drawn on
each piece — DECISIONS 30); header corners as decision 4; footer "Title ·
CODE" left and the page label right, centred in the bottom margin.

**Measured against the LaTeX** (Chrome for Testing 155, `pdftotext -bbox`,
`pdffonts`; the side-by-side is `scratchpad/499-side-by-side-linear.png` of
the session): left ink at 54.0 pt in both, right 556.8 against 558.0; word
widths "Get" 28.48 against 28.38 pt, "Evaluate" 47.09 against 46.91 (the
plan review's warning held: glyph HEIGHTS differ because Chrome embeds Type
3 and LaTeX Type 1C, so widths are what to compare); footer baseline 765.5
against 767.4 pt; faces LMRoman10-Regular/-Bold and LMSans10-Bold in both.
The visible differences left: no strand headings in our key, and the Name /
Date header (decision 4), which the LaTeX warm-up has not.

**MVVM Review, Chrome for Testing 155 (the scratch site: the real page, and
— since the review — its real RocketSim screenshot, 1368 × 2730, which
prints at its full resolution; the first counts below used a placeholder):**

| | Before (dev) | After |
|---|---|---|
| Questions only, portrait | 6 pages, 79 of 113 code lines missing, 2 pages 6,250 px over | 4 pages |
| Answers only, portrait | 7 pages | 3 pages |
| Both, portrait | 13 (6 + 7) | 7 (4 + 3) |
| Questions only / Answers only / Both, landscape | — (not offered; Safari clipped 18 pages) | 7 / 3 / 10 |

After, in all six, every one of the 14 question stems, 113 non-empty code
lines and 23 answer paragraphs of the source page is in `pdftotext`'s text
(a checker that ignores hyphenation, smart quotes and the page corners),
and every page has 0 px of overflow.

**After the implementation review (Opus):** the guard measured a displayed
formula's box, which is always the column's width, so a 59-term formula
(724 px box, 4,342 px of formula) printed to "+ a12" and was called complete.
The guard now reads the formula's scroll width, and before the layout each
over-wide formula is measured in the frame at the paper's width: set smaller
when it keeps at least 70% of its size (`paperLook.formulas`), otherwise
broken between its terms as KaTeX breaks one in a line of text — the
fixture's 59 terms print whole on five lines, its 11 terms at 80%; a single
unbreakable term 2,839 px too wide is refused (measured). Quartz's 75 px
minimum cell width made a nine-column timetable refuse on portrait: cells
now have none and break between words (`anywhere` printed "Scien / ce"),
and tables of eight columns or more print in 9 pt (`paperLook.tables`) — a
12-column timetable prints whole on both papers. Under ⌘P the code number
box was still Quartz's, so "100" printed as "10" over "0": the digit rule is
in the shared mixin now and the page writes the digits on load, and the
browser check reads ⌘P's numbers 1–110. Formulas print black, not the site's
grey-green, and Escape in the menu no longer hands focus to Search.

**How each fault was fixed, measured by turning the fix off alone:**
pictures had no height when Paged.js measured (natural sizes written, and
`content-visibility: visible` — the screen's box is 0 × 0 below the fold,
review B1); code scrolled, and Paged.js 0.4.3 will not split a scrolling box
(`overflow: visible` on code, by class); a 3,134 px Mermaid diagram under
the same rule printed three pages of arrows and stopped the layout (review
B2 — diagrams keep their box and are capped with every picture at the
content height less 0.45 in); Quartz's code `<figure>` kept whole stranded
"Source Code" on its own page (exempted when the code splits, review S2);
`<section>` is tinted in Quartz (no backgrounds on paper, S3);
`.katex-display` clipped (S4); the number box `width: 1rem` broke "100" into
three lines (sized by digits, `nowrap`); the corners sat at the paper's edge
(S5: centred in the margins now, 0.37 in up).

**REJECTED, so they are not proposed again:**
- Orientation by `@media print and (orientation: …)` with both layouts made
  — Chrome picked the right set, Safari evaluated the WINDOW's orientation
  and printed the landscape set on portrait paper (measured in the plan).
- Dropping Paged.js so the dialog's orientation is honoured — Safari then
  prints no margin boxes: no page numbers, no blanks, no separate counts.
- Stripping every box, the worked examples included — the LaTeX handouts
  keep the peach example box (499-2); code keeps a box by DECISIONS 30.
- Computer Modern from KaTeX's CDN — no bytes, but the network at the moment
  of printing, and no sans or mono. Latin Modern comes from Debian's
  `fonts-lmodern` (not GUST's site: a font host that is down must never
  fail a teacher's first build), unmodified OTF; woff2 (283,148 against
  631,940 bytes) would change the files, which the GUST Font License asks be
  renamed when changed.
- Numbering an untitled `question` callout after the HIGHEST number so far —
  page order is what the reader sees; a page that mixes "Question 3"
  headings after an untitled self-check can show two 3s, and the agent
  guidance tells authors to label questions.

**Safari, measured after the review (Safari 26.6, the scratch site, Safari driven
on the Mac with `print()` intercepted, then once with the real
print window):** the completeness check first REFUSED MVVM Review in Safari
on both papers while Chrome printed it — three shapes, each a WebKit
difference in how Paged.js's page-as-a-column measuring leaves things:
(1) a line of code Paged.js split before its words leaves an empty piece
whose box reaches into the column the layout throws away (the rest prints on
the next page) — such an EMPTY split piece (no words, no picture) is not a loss
and is not counted, while every other split piece is measured and what it
loses is lost (the first version of this fix skipped EVERY split piece, and
the fix review measured a 60-line formula and a 90-line table row printing
half-missing while the check said nothing was lost; the verify fixture's
"Printable Too Tall" page now has to be refused on both papers, proven
against that version, which printed it "5/5"); (2) a blank code line holds only a space, which Paged.js does not
break before, so it straddled the page's foot with its number cut off —
blank lines now hold a zero-width space and break like any other; (3)
WebKit honours `table { break-inside: avoid }` itself and moved a 40-row
table's first rows into the thrown-away column, a real loss — in the
handout tables may now split (⌘P keeps them whole). The check also counts an
UNSPLIT element cut off only if no unsplit copy of it sits whole on a page,
measures each piece rather than the union box, and allows a line 3 px of
hanging leading. Over-wide formulas are measured only after KaTeX's own
faces have loaded (`document.fonts.ready`): measured before, a 13-term
formula read 799 px for 896, was not shrunk enough and was refused.
After: all six prints of MVVM Review and of the verify fixture lay out every
piece in Safari (`scratchpad/i499/safari-sweep.txt`). **Safari does NOT take
its orientation from the page:** asked for landscape, its print window opened
on Portrait and showed the 11 in pages shrunk onto portrait sheets; choosing
Landscape there printed them right, footers included. A first version
said `printablePages.words.landscapeInDialog` beside the button while the
print window was open, but that window covers the page and the sentence was
never seen (fix review S2), so it shows in the Print MENU, under the papers,
while Landscape is chosen (review S6's fallback; Chrome and Edge follow the
page, and the sentence is conditional, so it is true there too).

**Not done / open:**
the answer key has no strand headings; a displayed formula taller than the
page, or one unbreakable term wider than it, cannot print (refused, with the
sentence). The Windows app's share (Course Settings → Printing, the
`settings saved` clause, the guidance for assistants, the preview pane's
hand-over to the browser) landed on 2026-10-15 under #496:
`12-windows-app.md` → "Printable pages", with its browser measurements
(headless, and on 2026-10-15 the pane and the hand-over on an unlocked
desktop: the fragment survives ShellExecute and Edge prints at once).

### F9. ⌘P on every other page (#501, v1.7.0)

Found in passing by #485 E1's implementer: ⌘P on a page that is NOT
printable lost words under the folder list. It predates #454 and E1 —
**Quartz ships no print rules**, so ⌘P laid out the screen's page:

- **Chrome and Edge** print letter paper with their default margins at 739 px
  wide, under Quartz's 800 px breakpoint, so the page printed in the PHONE
  layout. On a page loaded at desktop width the explorer is not `collapsed`,
  and its mobile rule makes `.explorer-content` an opaque panel (`absolute`,
  `z-index: 100`, `var(--light)`, `100dvh`) drawn OVER the article. On a long
  test page it covered paragraphs 03–13 across pages 1–2.
- **The covered words stayed in the PDF's text layer.** `pdftotext` found
  every one, which is why #454's "pdftotext identical" check could not see
  this. Two things do: the INK under a word, and the folder list read INTO
  the paragraphs (5 of 68 no longer matched whole).
- **Safari 26** lays out at the window's width (1512 px): the three-column
  desktop grid, so the left sidebar printed on page 1 and the column's RIGHT
  edge ran off the paper, visibly cut ("the class ta"). Not in the issue.

**The fix** is one block in `support/quartz/components/styles/print.scss`,
"⌘P on every other page", data in `contracts/shared-rules.json` →
`printablePages.everyOtherPage`:

```scss
@media print {
  html:not(.plantoir-printable):not(.plantoir-print-frame) {
    .page > #quartz-body > .sidebar { display: none !important; }
    .page > #quartz-body { display: block !important; }
    .page { max-width: 8.5in !important; margin: 0 !important; }
  }
}
```

- `:not(.plantoir-printable)`: a printable page's ⌘P (F4) is untouched by
  construction — 0 pixels differ, measured, though specificity alone gave
  that too.
- **`:not(.plantoir-print-frame)` is LOAD-BEARING.** The handout's frame has
  a `.page` and Paged.js applies `@media print`; without this, both landscape
  handouts were refused as `printablePages.words.incomplete`
  (`print_handout.mjs` FAILED). Proven again by the implementer: drop only
  that `:not()` and the check fails on landscape.
- 8.5 in never narrows Chrome's portrait page, and keeps Safari's column on
  the paper.

**Before → after** (planner's measurement, Chrome for Testing 155 headless at
a 1512 × 900 window, and Safari 26 by script — ⌘P, Save as PDF — macOS 26):

| | Chrome, light and dark | Safari, light and dark |
|---|---|---|
| A 62-paragraph plain page | 6 → 6 pages; words with no ink 346 → 0; sidebar text on paper → none | 4 → 4 pages; words past the edge 98 → 0; 62/62 sentinels |
| What This Site Can Do | 13 → 13; no ink 195 → 0 (dark 224 → 28, all labels of Mermaid drawn dark — out of scope) | 8 → 8; past the edge 29 → 0 |
| Printable Not Opted | 21 → 21; no ink 86 → 0; "Search" gone | 10 → 10; past the edge 14 → 0 |
| The plain page, landscape | 8 → 8; the tablet layout's sidebar gone | — |
| Printable pages, portrait and landscape | **0 pixels differ** at 72 dpi; text identical | **0 pixels differ** |
| Handout, 3 modes × 2 papers | `print_handout.mjs` OK; **0 pixels differ** | — |

The Safari column was re-taken by the implementer from the planner's saved
PDFs (`pdftotext -bbox` against the paper's width less 18 pt; `pdfinfo`; a
72-dpi pixel comparison) and holds, and measured again by script on the
implementer's run (Safari 26, a 1512 × 948 window opened for the purpose,
⌘P → PDF → Save as PDF): the 62-paragraph page, light and dark, 4 → 4 pages,
words past the edge 100 → 0, the sidebar's "Search" and "EXC2O S1" on paper →
gone, sentinels inked 61/62 → 62/62; Printable Fixture 12 → 12 pages, 0
pixels differ.

**Gated on every run** where Chrome for Testing is present (verify.sh 6h,
SKIPPED otherwise, with the handout check): section 5 plants "Plain Long
Page", 40 paragraphs each starting `plantoir-plain-para-NN`, under headings
and with list items, and `browser-checks/print_plain_page.mjs` loads it in a
1512 px window and prints it portrait and landscape with ⌘P's defaults (no
backgrounds). It asserts no line of any element `everyOtherPage.hidden` names
is on paper, every paragraph is whole in the text, the darkest pixel under
every sentinel (`pdftoppm -gray -r 100`, read as PGM by hand) is at most 200,
and no word is within 18 pt of the paper's edge. The 6h static check also
requires the block's minified text in `index.css`, built from
`everyOtherPage.scope` and `.hidden`. **Must-fail, proven by copy-and-restore
of `print.scss` through full verify.sh runs:** with the block taken out, both
6h checks FAILED — portrait, the sidebar's words on paper ("🔬 EXC2O S1",
"Search", "All Classes", …), 6 of 44 paragraphs not whole, 7 paragraphs with
no ink (page 2, 11–17); landscape, the sidebar's words — and with only
`:not(.plantoir-print-frame)` taken out, `print_handout.mjs` FAILED: Questions
only and Both on landscape were refused with `printablePages.words.incomplete`.

**REJECTED, all measured:** sidebars only (Safari kept the grid's tracks and
printed 7 pages in a quarter-width column); the block with no cap (Safari
clipped 50 words); a 7 in cap as on printable pages (Chrome clipped more of
the wide table and formulas); hiding only the folder panel (Safari still
clipped, and printed the folder list).

**Found, not fixed:** in Chrome, ⌘P on a page that is not printable clips
Quartz's horizontal scroll boxes — the wrapped code comment, the wide
formulas and the 12-column timetable of the verify fixture are missing from
the text both before and after the fix; a printable page's ⌘P and the
handout handle them (F8). Mermaid drawn dark prints near-white labels (28
words on What This Site Can Do).

**Windows inherits it free** — the block is in `support/quartz`, installed by
`build_site.py` on every build. It owed one measurement, taken on #496
(2026-10-15, headless Edge 155 by `print_plain_page.mjs` unchanged, Intel
i5-8365U, Windows 11 Pro 26200): Plain Long Page 4 pages portrait, 5
landscape, 40/40 sentinels inked, 0 past the edge, no sidebar on paper,
light and dark — the same result as Chrome here. Ctrl+P in the preview
pane (WebView2, 2026-10-15) printed *Similar Triangles Practice* on 2 sheets
with its corners; a headed Edge run of the checks themselves is not possible
(`Page.printToPDF` is headless only), and Chrome is not installed there. The measurement as asked was: ⌘P → Save as PDF in
Edge and Chrome on a long page that is not printable, portrait and landscape,
light and dark, because Windows' DPI and default margins can put the paper
width on the other side of 800 px.

---

## G. Diagrams and graphs (#485 E1, v1.7.0)

A ` ```tikz ` fence is drawn when the site is built and placed in the page as
an inline SVG; a ` ```functionplot ` fence is drawn in the reader's browser
from function-plot served by the site itself. The build half is
[05 → Diagrams and graphs](05-build-pipeline.md#diagrams-and-graphs-what-the-build-does-485-e1-v170);
the rules are `contracts/shared-rules.json` → `figureFences`.

### G1. The files (all in `support/quartz/`, installed every build)

- `plugins/transformers/figureRules.js` — plain JavaScript shared with the
  build's helper: `tidy`, `keyOf`, `altOf`, `parseFunctionPlot`,
  `texProblem`. An ES module, as Quartz is; esbuild bundles the `.js` import
  from TypeScript without complaint.
- `plugins/transformers/plantoirFigures.ts` — the transformer, wired by
  `build_site.wire_quartz_additions` straight AFTER `Plugin.Description()` in
  `quartz.config.ts` and exported from `plugins/transformers/index.ts`
  (both idempotent).
- `components/scripts/figures.inline.ts` and `components/styles/figures.scss`
  — carried by `PlantoirMetaLine` (the component every content page already
  has), so no layout edit was needed.

### G2. Two stages, and why the second comes after Description

The **markdown stage** turns the fence into
`<figure class="pl-figure pl-<engine>">` holding only a hidden figcaption
(the description a screen reader reads). The **html stage**, which runs after
Quartz's `Description`, then puts the drawing in. In that order the page's
summary — its search card and its social card — is made from the words and
the description, never from the drawing's lettering, which is hundreds of
single glyphs (`A B C 3 4 . 5`; seen in the spike, and checked in verify.sh).
No manifest means the stage does nothing at all, so a site without figures
is untouched. A failed figure is `pl-figure-failed` with the contract's
sentence (ruling E1-7: students see "This diagram couldn't be drawn." rather
than a gap); a graph keeps its own text, shown until it is drawn and kept if
it cannot be. A second copy of the same drawing on a page has its element ids
renamed (`-pl2`): node-tikzjax names ids after the drawing, and a first copy
folded away in a callout would otherwise take the second's clip paths with
it (review N5). The first drawing on a page links `static/tikz/fonts.css`
once; Paged.js keeps that link, and the faces are loaded in the handout's
frame when it prints (measured: cmmi10, cmr10, cmsy10 all `loaded`).

### G3. Colour, on screen (no filter)

Black and white in a drawing follow the theme, as obsidian-tikzjax's own
dark-mode setting does: CSS on the drawing's own attributes,
`[stroke="#000"]`/`black` → `currentColor` with `color: var(--dark)`, and
`#fff`/`white` → `var(--light)`, so a label box behind text takes the page's
background. **Labels need one more step:** Quartz's own `base.scss` gives
EVERY svg `<text>` `fill: var(--darkgray)`, which beats an SVG's `fill`
attribute — found by verify.sh's first run: a label drawn red came out grey,
and black lettering printed #4e4e4e. So the transformer writes each label's
own colour (worked out from its ancestors, as SVG inherits) as an inline
style, leaves black to `figures.scss` (`text { color: inherit; fill:
currentColor }`), and turns white into the page's background. A teacher's
own colours are kept; pure blue is dim on a dark page, exactly as in
Obsidian.
A graph's text, axes and grid take `--darkgray`, `--gray` and `--lightgray`.
**Rejected:** `filter: invert()` (it inverts the teacher's colours too, and
would have to be undone on paper).

### G4. Graphs, zoom, and print

- **Loaded only where needed.** On a page with a graph, the script loads
  `static/function-plot/function-plot.js` at once (`spa-preserve`, so a page
  change does not drop it) — eagerly, because ⌘P's `beforeprint` gives no
  time to wait — and draws each graph when a tenth of it is visible, at the
  figure's width and 0.62 of it in height, again after a resize. function-
  plot gives its drawing a size and no viewBox, so one is added after every
  draw. A page without a graph fetches nothing and adds no listener.
- **A page's own ids (#502, measured in Chrome for Testing).** A browser
  makes every element with an id a property of `window`, and function-plot
  1.25.4 reads two such names once, as its file runs, keeping what it found
  for the whole visit: `math` (its evaluator — a heading "Math", id
  `math`, became the evaluator and every graph said `graphCouldNotBeDrawn`)
  and `exports` (where it puts itself — a heading "Exports" left it nowhere
  and every graph said `graphNeedsPreview`). Because the engine is loaded
  once and kept across page changes, the FIRST page with a graph decided
  every graph for the rest of the visit: measured on a built site, a `# Math`
  page opened first failed there and on the next graph page Quartz's page
  change reached; the reverse order drew both. The script gives `window` an
  own property of each name, `undefined`, for the moment the file runs (only
  where `window` has none of its own) and deletes it on `load`/`error`, so the
  page's ids answer as before. `module` and `define` were measured too and
  break nothing on their own, so they are left alone. Rejected: handing
  function-plot its evaluator (it copies the one it found into a table that
  cannot be reached afterwards), renaming the ids at build (it would break
  every `[[Page#Math]]` link), and leaving the names hidden (the page's ids
  would stop answering for the visit). `figureFences.pageIds`;
  `browser-checks/graphs_draw.mjs` in verify.sh 6h's browser checks. plantoir.app's
  Visualizations page (`/visualizations/`, Interactive until v1.7.0's
  renaming) loads the same file its own way and avoids the trap by
  having no such id (`website/assets/interactive.js` says so).
- **Zoom (review B2, measured in Chrome for Testing).** function-plot
  attaches d3-zoom to the graph's surface even with `disableZoom: true`
  (that option only ignores the result), and while it is attached a scroll
  or a finger drag starting over a graph moves the graph instead of the
  page. Measured on the fixture: a 400 px wheel over a graph scrolled the
  page **0 px** without the fix and **400 px** with it; a 300 px touch drag
  (touch emulation, 820 × 1180) **0 px** without and **286 px** with — both
  proved by putting the old behaviour back in the built script and measuring
  again. So the script detaches the `.zoom` listeners (through d3's own
  `__on` list, so nothing re-adds them) when the teacher wrote
  `disableZoom: true` and on every touch screen (`(pointer: coarse)`); with a
  mouse or trackpad dragging still moves the graph, and the wheel zooms only
  with ⌘ or Ctrl held (Chrome and Edge also send a trackpad pinch that way;
Safari does not, and there a pinch zooms the page) — so a plain scroll
  always scrolls the page. That answers the review's open question about the
  desktop "map trap" by the safe default; Russell may prefer click-to-zoom.
  The Obsidian plugin keeps the trap; that is not Plantoir's to change.
- **Print (decision 13).** The handout awaits a function in
  `window.plantoirPrint.prepare` that draws every graph; ⌘P's
  `beforeprint` draws every graph at the teacher's bounds whatever was
  zoomed. `figures.scss` holds, on EVERY page: a `@media print` block that
  sets the figure's own colours light (`--light #fff … --dark #000`), so ⌘P
  from dark mode prints black on white with white label boxes (review B1 —
  #454's light flip covers printable pages only, and before this a figure
  printed near-white with black boxes); `break-inside: avoid`; and a cap of
  **8 in on portrait paper, 6 in on landscape**, with `width: auto` (review
  B3 — a 1,400 px figure split over four pages with the text after it printed
  twice). The cap sits inside `:where()`, with no specificity, because the
  handout has its own per-paper cap that must win: the first version's 8 in
  beat it and a landscape handout with a tall figure refused to print, and
  ⌘P in landscape split it (E1 implementation review B1). Measured after the
  fix, a 30 cm TikZ ladder in Chrome for Testing: the handout prints on both
  papers (854 px and 614 px tall, whole, 5 of 5 pieces), and ⌘P keeps all 29
  rungs on one page in portrait and landscape. **Safari not measured**: it
  needs "Allow remote automation", which only `safaridriver --enable` (an
  administrator's password) and a restart of the running Safari turn on. Measured: the handout of a
  printable fixture with 11 figures, from dark mode, in all three modes and
  both papers: every piece laid out (29 of 29), none split, lettering
  rgb(0, 0, 0), the 530 px tree whole.

**Found in passing, not E1's, and fixed in the same release:** Quartz's own ⌘P on a page that is NOT
printable used to overlay the sidebar's folder list on page 2 of the paper and
lose what was under it — measured on `Style/What This Site Can Do` with no
figure at all, so it predated E1. #501 (v1.7.0) fixes it with one print-only
block in the shared stylesheet; see the #501 section of F for what it does and
what it leaves pixel-identical.

### G5. What every site carries, figures or not

The figures' styles and script are bundled into every site's `index.css`
and `postscript.js`, like #454's print code: every rule is under
`.pl-figure` and the script returns at once on a page without a graph, so
no page that has no figure changes — its HTML is byte-identical, which
verify.sh checks (a page built with figures elsewhere in the site against
the same page once they are gone). The site-wide bundle grows by the
script's and the styles' size; a site without figures carries neither
`static/function-plot` nor `static/tikz`.

### G6. Teacher note: "Graphs and diagrams"

Write ` ```functionplot ` for a graph students can explore and ` ```tikz `
for a precise diagram; preview, and anything that cannot be drawn is named
with its page and line. In Obsidian, a fence shows as a picture only with
its add-on installed and switched on in that course: **TikZJax** for
` ```tikz `, and **Functionplot** 1.2.1 for ` ```functionplot ` — which is no
longer in Obsidian's plugin directory (review S1, checked 2026-10-09 against
`community-plugins.json` and the removed list), so it cannot be installed
from Obsidian itself. Without them the fence shows as its text; the site
draws it either way. **On the Mac, Plantoir carries both and offers to add
them** when a course with figures is opened in Obsidian from Plantoir (#495,
09 → "Obsidian's add-ons for diagrams and graphs (#495)"); Obsidian then asks
once per course whether the teacher trusts its author — "Trust author and
enable plugins". On Windows, until its issue lands, TikZJax comes from
Obsidian's directory and functionplot fences stay text in Obsidian. If
Obsidian updates TikZJax past 0.5.2, a diagram may draw differently there
from the site, whose engine is 0.5.2's (`obsidianAddOnsForFigures.knownLimits`).
The skill `plantoir-math-graphs` (support/agent_guidance) carries the whole
syntax for an assistant.

**Rejected** (with the reasons in 05 and 02): TikZJax in the browser;
`<img>` SVGs; every Computer Modern face on every site (140 faces, 20–33 KB
each — a site carries only the ones its drawings name, ~30 KB a face);
carrying function-plot in every site; a CDN.

## H. The sidebar's page marker (#515, v1.7.2)

**What it does.** Inside an OPEN folder of "Navigate this site", every page
row starts with a small dot, and a title that wraps hangs: its second line
starts under its first letter, not under the dot. Before it, a long title
that wrapped ("Solving Linear Systems Graph-ically", on MPM2D) read as two
pages, because nothing marked where one page ended and the next began.
Folder rows keep their chevron and get no dot, at any depth; pages at the
TOP level of the sidebar get none (they sit among folder rows, next to
chevrons, not among other pages); a folder with no chevron gets none; the
dot does not change colour on the current page or on hover (Russell's
rulings 1-4 and 8, 2026-10-16).

**Where it lives: one stylesheet, no markup.**
`support/quartz/components/styles/sidebarPageMarker.scss`, imported by
`components/PlantoirMetaLine.tsx` and added to its `concatenateResources`
beside `figures.scss`, the same ride figures took (G1), so there is no layout
edit and no third wiring edit. Quartz writes ONE `index.css` for every page,
so the rule reaches content, folder and tag pages alike; it depends on
`wire_quartz_additions` having wired `PlantoirMetaLine` into the layout (F1),
and if that wiring ever failed, print and the dot would go together. The file
is NOT called `explorer.scss`: `install_quartz_additions` copies
`support/quartz` over Quartz by path, so that name would replace Quartz's own
explorer styles in every section (the shared test asserts no such file).

**The selector, and why it is exactly a page row.**
`.explorer .explorer-content .folder-outer > ul > li:has(> a)`. The sidebar's
rows are built in the browser from `<template>`s (A2): a page row is
`<li><a>`, and a folder row is `<li><div class="folder-container">…`, whose
link (when `folderClickBehavior: "link"` gives it one) is two levels down,
never a direct child, chevron or not. A folder's `index.md` becomes the
folder's own data, not a child row. `.folder-outer > ul` keeps it to the
inside of a folder. The rule sets `position: relative` and
`padding-left: .8em` on the row, so every line of the title starts .8em in,
and draws the dot as an absolutely positioned `::before` in that padding:
`left: 0`, .32em round, `top: calc(.5lh - .16em)` — half the row's OWN line
height less half the dot, so it is level with the first line whatever the
scheme's font and line height (`top: .5em` first, for a browser without `lh`;
Safari 16.4+ and Chrome 109+ have it, within macOS 15 and WebView2). Under
`forced-colors: active` the dot is `CanvasText`.

**It wins by specificity, so do not shorten it.** Plantoir's CSS comes BEFORE
the explorer's in `index.css` (component CSS follows the layout's order, and
`beforeBody`, where PlantoirMetaLine sits, precedes `left`; measured: print at
offset 3,180, figures at 3,948, the stock `.explorer-content ul{` at 30,277),
so the rule beats Quartz's only by being more specific. No stock rule sets
`padding-left` or `position` on a sidebar `li` today; a Quartz upgrade that
adds one has to be checked against this.

**What it leaves unchanged.** Nothing styles the link: its colour (`--dark`
at .75), the current page's (`--tertiary` at 1) and hover (`--tertiary`) stay
Quartz's own rules, and because the dot is on the ROW it does not follow
them. Every page's HTML is unchanged by construction — the change is a
stylesheet and no `.tsx` render changed, and Quartz links `index.css` by a
fixed name — and `postscript.js` gains nothing (no script). The sidebar is
`display: none` on paper (print.scss's printable and every-other-page blocks;
the handout frame clones the article only), so print is untouched.
**Measured** in the verify build (EXC2O section 1): the rule's minified text
is **454 bytes** of `index.css` (57,824 bytes in all), ahead of the stock
`.explorer-content ul{` (92 for the row, 215 for its `::before`, 147 for the forced-colours block, from offset 23,010; the stock rule is at 30,731). (The first, inline-dot form measured
473 bytes: dev's 57,370 → 57,843.) **HTML, measured by the implementation
review:** the branch's final verify build (plants removed) against the
scheduled deploy's EXC2O build of the same day (a different image and base
URL, so not a clean dev-vs-branch pair): across 299 pages `<head>` identical
once URLs and og/twitter/rss metas are set aside, `<body>` identical once the
random list id and dates are, but for 5 pages (`Curriculum/index`,
`tags/index`, `tags/A1`, `strand-a`, `strand-b`) that differ only by
same-date list order, Quartz's known variance. verify.sh's 6h check also
holds the row templates to `<li><a>` and `<li><div class="folder-container">`.

**Contrast, measured.** The target is WCAG 2.2 SC 1.4.11, non-text contrast,
**at least 3:1** against the sidebar's `--light`. The dot's effective colour
is `--dark` at .75 blended over `--light` (the title's own tone, ruling 1).
Over all 43 schemes in `support/colour_schemes.json`
(`scripts/test_sidebar_page_marker.py`, which prints these): **light at least
5.45:1** (vintage-sepia; standard 6.09), **dark at least 8.37:1**
(lakefield-college-school; standard 8.90), none of 86 under 3:1. Off the BUILT
verify fixture in Chrome for Testing (EXC2O section 1 is forest-moss): **light
5.63:1, dark 9.45:1**, the sidebar's own computed background, the
dot's computed colour and opacity. The alternatives, same method:

| Dot colour | Light min | Dark min | Under 3:1 |
|---|---|---|---|
| **`--dark` at .75 (chosen)** | **5.45** | **8.37** | **0 / 86** |
| `--darkgray` at .75 | 3.49 (desert-sandstone) | 7.30 | 0 / 86 |
| `--darkgray` at .5 | 2.16 | 3.90 | 43 light: REJECTED |
| `--gray` | 1.72 | 2.52 | 47: REJECTED |
| `--secondary` / `--tertiary` | 1.74 / 1.46 | 1.06 / 2.59 | 6-17 schemes: REJECTED, and they already mean "link" and "here" |

**Why the dot is out of the line (the first implementation's limit, gone).**
The first implementation drew the dot as an inline-block `::before` with a
`text-indent: -.8em` hang. An inline-block is an atomic inline with a
line-break opportunity after it, so a title whose FIRST WORD is wider than the
sidebar less .8em left the dot alone on line one (implementation review,
measured with "Electroencephalographicallycounterrevolutionarily debate": a
four-line row, the link starting on line two). The absolute dot is not in the
line at all, so nothing can strand it; verify.sh plants that title, and the
check holds every row's dot level with its own title's first line.

**Gated, in two places.**

- `scripts/test_sidebar_page_marker.py` (verify.sh step 0; Windows'
  `PythonToolchainTests` discovers it): reads the `background-color: var(--…)`
  and `opacity` of the `::before` rule from the stylesheet and holds the blend
  to 3:1 in every scheme and mode; asserts no rule's SUBJECT (the selector's
  last compound, `:has()` arguments removed) is a link, `:hover` or `.active`,
  so `li:has(> a)` passes and `li > a` would not; asserts PlantoirMetaLine
  imports the file AND hands it to `concatenateResources`; asserts there is no
  `support/quartz/components/styles/explorer.scss`.
- `browser-checks/sidebar_page_marker.mjs` (verify.sh 6h, beside the print and
  graph checks, Chrome for Testing at 1512 × 900): verify.sh plants
  `Discussions/Marker Fixture Long.md` (a title that wraps to three lines) and
  `Discussions/Tasks/` (its own `index.md` and one page). The folder is
  called Tasks because the sidebar gives a chevron to a folder whose NAME is
  in `expandable`, at any depth, and Tasks already is; the check finds it by
  its path, Discussions then Tasks, never by the name alone. **Adding a new
  name to `expandable` was the first implementation and verify.sh caught it:**
  `Explorer.tsx` writes that list into every page's `data-expandable`, so it
  changed every page's HTML for the build with the plants, and 6c's #485
  check (Help Sessions byte for byte against the build after the plants are
  gone) failed. The check opens both folders with a click on the
  chevron — only if not already open, since Quartz saves the sidebar's state
  in `localStorage` across loads — and waits by polling for the list's height
  to settle. Then, in order: every page row in both folders has a drawn
  `::before` box (from CDP `DOM.describeNode` and `DOM.getBoxModel`, the
  browser's own layout); no folder row at any depth and no top-level page has
  one, and the folders kept their chevrons; the long title has at least two
  lines, line two starts at line one's left (±0.5 px) and at the row's content
  edge, and the dot is left of line one and level with it; on EVERY page row
(the too-wide first word included) the dot's middle is inside the title's
first line and left of it; the current page's
  link is `--tertiary` at 1, a hovered link (CDP mouse move, read until two
  reads agree, since Quartz eases colour over .2 s) is `--tertiary`, and the
  dot is the same on the current, hovered and a plain row; contrast as above.
  All again in dark mode (emulated, reloaded, `saved-theme` asserted), on the
  folder's own folder page (`Discussions/index.html`), and under emulated
  forced colours, where every dot must be at least 3:1 against its row (a
  drawn box is not enough: Chrome forces a background to Canvas and keeps its
  alpha, so without the `CanvasText` block the dot is still "there", Canvas on
  Canvas, 1:1). The fixture's `Discussions/Tasks` is planted only if the course
  has none, with a marker file, and removed only while the marker is in it.
  A static 6h check also finds the minified selector in `index.css`.
- **Must-fail, each failing for its OWN reason** (copy-and-restore, on a copy
  of a built EXC2O site served over HTTP with the fixture rows added to its
  `contentIndex.json` and the rule placed before the explorer's, as the build
  places it): no rule → `page rows carry no marker` for all seven rows, first;
  the selector widened to `.folder-outer>ul>li` → `folder row carries a
  marker: "Tasks"`; the padding cut to .2em → `the dot (to 62.9 px) is not
  left of the title (from 61.0 px)`; opacity .3 → `the dot is 1.78:1 … under
  3:1`; the forced-colours block deleted → `forced colours: 6 of 6 page rows
  have no dot that can be seen (lowest 1.00:1 …)` (with it: 10.41:1); the
  first implementation's inline dot → `the dot of
  "Electroencephalographicallycounterrevolutionarily debate" (middle 413.3 px)
  is not beside its first line (428.2-446.2 px …)`. The restore guard: an
  unmarked `Discussions/Tasks` with a teacher's `index.md` survives the restore
  block; a marked one is removed. The Python test: opacity .3
  fails the contrast test (every scheme listed), a `> a:hover` rule fails the
  link test, and the import left out of `concatenateResources` fails the
  carrier test.

**On Windows** (#546, 2026-10-16): the same check, unchanged, against a
native build gave the same `OK: light 5.63:1, dark 9.45:1, forced colours
10.41:1`; the dot was looked at in the app's preview pane, light and dark,
and under a REAL High Contrast Black theme in Edge and in the pane
(`forced-colors` true, the dot CanvasText, 9.64:1 against that theme's
Canvas) — `12-windows-app.md` → "The sidebar's page dot on Windows".

**Tuned by eye** in Chrome for Testing, light and dark, at 1512 × 900 and at
phone width (390 × 844, the explorer opened from its button): `.8em` hang and
`.32em` dot kept. The hang is compact on purpose (ruling 4): a hang as wide as
a folder's chevron (17 px) would line page titles up with sibling folder
titles, and make more titles wrap, which is the problem being fixed.

**REJECTED, so they are not proposed again.**

- `list-style: disc` / `::marker`: the hang comes free, but the gap and the
  marker's size are the browser's own and differ between Chrome, Safari and
  Edge; `::marker` takes no opacity and no size short of `font-size`; and it
  lands against the folder's border line, inside `.folder-outer > ul`'s .8rem.
- An inline-block `::before` with a `text-indent` hang (the first
  implementation): it strands on a too-wide first word, above. The planner had
  rejected the absolute dot as drifting with the line height; `top:
  calc(.5lh - .16em)` follows the row's own line height, so it does not.
- The "•" glyph: its size and height change with the scheme's font (43
  schemes, several faces). The drawn dot is the same everywhere.
- A class on page rows from `patches/explorer.inline.ts`, or the styles in
  `patches/Explorer.tsx`: a layer-A change and a change to every site's
  `postscript.js`, for nothing the selector cannot already tell apart.
- Appending to `custom.scss`/`base.scss`: marker appends freeze (C2; F1
  rejected it too).
- A new component or a layout edit: a third regex edit, nothing gained.
- `--gray`, `--darkgray` at .5, `--secondary`, `--tertiary`: the table above.
- A contract key (`shared-rules.json`, as #501 did for ⌘P): the CSS is in
  shared `support/quartz`, so both apps carry the same bytes, and the shared
  test holds the contrast rule; a key would copy the stylesheet's values into
  a second place (ruling 6). No trail line either: nothing the app does
  changes (ruling 7).

**Screenshots.** Every plantoir.app shot that shows a class site's sidebar
(`hero`, `preview`, `site-eng2d`, `print-page`, `site-mcv4u`,
`site-sch3u-chemistry`, `site-sch3u`, `coverage`, `search`, `colour-schemes`,
`light-and-dark`, `both-curricula`, `site-phone`, and their `-windows` pairs)
has every folder CLOSED, and the dot appears only inside an open one, so none
is expected to change by a pixel; the cut spot-checks them rather than
retaking (ruling 5).

## I. Runnable code (#455, v1.8.0)

A page whose settings say `codeRunner: true` turns each ` ```python run `
block into a small program students edit and run in their own browser, with
nothing installed: an editor, an input box when the program reads input,
**Run**, **Stop** and **Reset**, a status line and the output, and their edits
kept in the browser. The rules are data in
[`contracts/shared-rules.json`](../contracts/shared-rules.json) →
`codeRunnerBlocks` and [`file-formats.json`](../contracts/file-formats.json) →
`pageOptIns`; the build's half is
[05 → Runnable code](05-build-pipeline.md#runnable-code-what-the-build-does-455-v180),
the engine's layer [02](02-docker-image.md#optvendorpyodide-455-v180-and-katexs-pin-494).

**Compatibility.** A page that does not opt in, and every block that is not
runnable, comes out exactly as before: the transformer acts only on a page
whose frontmatter is the boolean `true`, and wraps only runnable blocks.
verify.sh 6j checks a page with every contract fence that does NOT opt in
has no runner markup and its code blocks come out byte for byte as the same
code in plain ` ```python ` fences (the word `run` changes nothing the
highlighter does). The page's script and styles are in every site's shared
`postscript.js` and `index.css` (every rule under `.plantoir-runner`, B2;
the script returns at once without a wrapper), so those two files grow on
every site — I8 has the numbers.

### I1. The files (all installed every build)

| File | What it does |
|---|---|
| `support/quartz/plugins/transformers/codeRunnerRule.ts` | The rules, with nothing of Quartz's: the language table (`LANGUAGES`, the literal mirror of `codeRunnerBlocks.languages`), `runnerFor` (the fence rule), `runnerId`, `findRunners` (document order, per-language numbering, and the nested-container skip below), the `{language}` filler and FNV-1a. `check_runner_rules_against_the_site.py` bundles it with Quartz's own parser and runs every case in Node. |
| `support/quartz/plugins/transformers/codeRunner.ts` | `CodeRunnerFences`, wired straight BEFORE `Plugin.SyntaxHighlighting(` in `quartz.config.ts`: on a `codeRunner: true` page it wraps each runnable block, at the MARKDOWN stage, in `<div class="plantoir-runner" data-runner-id data-runner-flags data-runner-language data-runner-runtime data-runner-engine data-original>`. A wrapper rather than attributes because rehype-pretty-code 0.14 drops every property on `<pre>` and `<code>` (measured 2026-10-09); the wrapper survives at the top level, in lists, in quotes and in folded callouts, and the block inside is highlighted exactly as before (the meta is left alone). `data-original` is mdast's `value`, the teacher's code exactly. Reads `quartz/plantoir_code_runner.json` with `fs` (mtime-cached) for the engines the site carries (I6). |
| `support/quartz/components/CodeRunner.tsx` | Renders NOTHING. Placed at the head of `sharedPageComponents.afterBody` (Quartz renders `page-footer` on every page whatever it holds, so no page's HTML changes), it carries the script and styles into the site's one `postscript.js` and `index.css`. |
| `support/quartz/components/scripts/codeRunner.inline.ts` | Everything in the browser (I2–I5). Imports `quartz/plantoir_code_runner.json` (words and limits; bundled by esbuild, as the patched explorer imports `course_config.json`). |
| `support/quartz/components/styles/codeRunner.scss` | Every rule under `.plantoir-runner`; the editor's font is the site's code font at `max(16px, …)`; touch targets 44 px. |
| `support/gated/pyodide/plantoir-worker.js` | The thread a page's Python runs in, laid over `VENDOR_DIR/pyodide` by the gate, so it reaches a site only beside the engine it starts (I3). |

### I2. The block on the page

Built on Quartz's `nav` event, for every `.plantoir-runner` without
`data-built` (elements, never one looked up by id: an embedded page brings
its blocks with their ids, N1). In this order (Q3): the editor (or, for
`readonly`, the highlighted code as it is); the input box, shown when the
block has the `stdin` flag or its CURRENT code matches the row's
`inputPattern` (`\binput\s*\(`), filled before Run, one line per `input()`,
never stored; Run, Stop, Reset (Reset only when editable); a status line
(`role="status" aria-live="polite"`); the output (`<pre aria-label>`,
stderr in `span.plantoir-runner-err`). The highlighted copy is put away by a
CLASS (`.plantoir-runner-original`), never `hidden` or an inline style, so
the print rules can bring it back (N2). Popovers, a page without script and
a page opened from a feed show the highlighted code alone.

**The editor** is a `<textarea>` in the site's code font, at least 16 px
(iPadOS zooms the page on focus below 16 px), spellcheck, autocapitalise,
autocorrect and autocomplete off, `wrap=off`. It grows with its code up to
24 lines, then scrolls; growing (and the editor replacing the shorter
highlighted copy) lifts an OPEN ancestor callout's inline `max-height`,
which Quartz's `callout.inline.ts` fixed when the callout opened and would
otherwise clip it (2026-10-09 finding D). Tab inserts four spaces or indents
every selected line, Shift-Tab takes up to four off; Escape then Tab leaves
the editor (the keyboard-trap rule); nothing while an input method is
composing; Enter is never intercepted. Cmd/Ctrl-Enter runs (from the editor
or the input box). Edits go through `execCommand("insertText")` so they can
be undone, with `setRangeText` where a browser refuses.

### I3. The thread, the harness and the language table's seam

`RUNTIMES = { pyodide: … }`; a block's `data-runner-runtime` picks one, and
`PyodideRuntime` is the only class. It starts
`<pathToRoot>/static/<engine>/<worker>` — from the CURRENT page's slug, so an
embedded block works at any depth — as a **module worker** on the first Run
on a page (#455 review B1: Pyodide 314's `pyodide.js` probes
`importScripts("data:…")` and throws "Classic web workers are not
supported" wherever no CSP blocks `data:`: the preview, Cloudflare, a folder
publish, the app's pane). It is kept warm for the rest of the page's visit
and ended by `addCleanup` when the page changes. **One program per page**
(Q2): Run on another block ends the thread (`words.stoppedForAnother`) and
starts a fresh one; an `autorun` block that comes into view while another
program runs waits its turn (N4). **Stop** ends the thread — without
cross-origin isolation (which a folder publish cannot send) there is no
other way to interrupt Python — and the next Run starts a new one. Online
that costs a few `304`s (Netlify's and Cloudflare's default `cache-control`
is `max-age=0, must-revalidate`); OFFLINE it fails with `couldNotLoad`
(measured by the implementation review: a warm Run offline finished; Stop,
then Run, failed in 53 ms). So the page works without a connection only
until a program is stopped, another block runs (that ends the thread too),
the output cap is reached, or the page changes; the skill says so.

The worker imports `./pyodide.mjs` and calls `loadPyodide` with `indexURL`,
`lockFileURL`, `packageBaseUrl` and `cdnUrl` all its own folder; nothing is
ever fetched for an `import`. Its harness (`codeRunnerBlocks.harness`):
`compile(source, "main.py", "exec")` with fresh globals and the source in
`linecache`, the traceback trimmed to start at the first `main.py` frame, so
its line numbers are the editor's and its wording CPython's (measured:
`File "main.py", line 3, in <module>` for a NameError on the editor's third
line); a SyntaxError prints without the Traceback header, as CPython does;
SystemExit is silent. **Before every run** (review S3, measured: one block's
`builtins.print = lambda *a: None` silenced the next run on the page) the
builtins are restored from a copy taken at load, the three streams and the
recursion limit reset, and the program starts in a fresh empty folder that
is removed after. stdout and stderr are `isatty` writers decoded with a
streaming `TextDecoder`, so output arrives line by line as CPython's would in
a terminal (a `time.sleep(0.3)` loop arrived at 0, 300 and 600 ms in Node);
`print("a", end="")` waits for its line, as in a terminal.

**Adding a language** is: a row in `codeRunnerBlocks.languages` and in its
two mirrors (`LANGUAGES` here, `RUNNER_LANGUAGES` in `page_features.py`; the
tests pin both field for field), a runtime class in `RUNTIMES`, a vendor
layer in the Dockerfile (and `fetch-runtime.ps1`), and a pin in
`toolchain.json`. Nothing else: the fence rule, the ids, the gate, the words
and the print rules read the table, never the word "python" (Russell,
2026-10-09). **Swift (#493) tested that sentence.** For a language the
browser runs as written, it holds as stated. A language compiled ahead of
time needed more, and the honest list is: a table row (`prebuilt: true`,
`editable: false`); a runtime class (`SwiftWasmRuntime`), which widened the
`CodeRuntime` interface (`run(…, program)`, an optional `started`, and
`done(error, said)` for its crash and exit-code words); a compile layer in
place of a vendor folder (`support/swift/` and `scripts/swift_blocks.py`:
the launcher's plan-and-compile step in `preview.sh`, and a `build_site`
call that prepares the programs); a folder problem of its own
(`swiftCouldNotBePrepared`); a pin (`toolchain.json` → `swiftImage`); and
two generic `prebuilt` rules - the gate takes the overlay as the whole engine
(`page_features.OVERLAY_IS_THE_ENGINE`), and the transformer looks a
prebuilt block's key up in `quartz/plantoir-runners/<engine>.json` (I10).
The fence rule, the ids, the gate's count and Python's gate were not
touched (implementation review N4 asked for this list instead of "that is
all").

### I4. Input, output and the words

`input()` takes the box's lines in order; each line read is echoed into the
output straight after its prompt (Q4: `Name? Ada`, not `Name? Hello Ada`),
and past the last line `input()` raises `EOFError` (measured: `EOFError: EOF
when reading a line`). Output is gathered once per animation frame; at
100,000 characters the program is stopped and `words.outputTooLong` shown
(Q5), and only what was left of the allowance reaches the page — one
`print("x" * 50_000_000)` used to be painted whole (implementation review
S1, measured: 50 million characters in the `<pre>`); now at most 100,000. The words are `codeRunnerBlocks.words` with `{language}` and
`{inputCall}` filled from the table row; none names the engine, WebAssembly,
a worker or a thread (`test_page_features.py` sweeps them).

### I5. Loading, and the hosts that break it

Nothing is fetched until Run: verify's browser check counts zero requests
under `static/pyodide/` on page load. A site opened as files: Safari 26.6
and Chrome for Testing 155 run NONE of a Quartz page's scripts from
`file://` (its `postscript.js` is a module script, which a file's opaque
origin may not load — measured 2026-10-17: no block built, no SPA), so the
blocks show as their highlighted code with no Run button; a browser that did
run the script would start nothing and say `words.needsWebAddress`. A 45 s watchdog after the thread starts ends in
`words.couldNotLoad` (review S1: a server that sends `.wasm` as
`application/octet-stream`, or a CSP with no wasm permission, otherwise
leaves "Loading Python…" for ever — measured in Chrome for Testing 155 as a
silent hang in BOTH cases, caught at 45 s by the watchdog). A thread that
fails to start is classified by ONE `HEAD` request for the worker file: 404
→ `words.engineMissing`, anything else → `words.couldNotLoad` (a worker
error event carries no reason, and a wrong type looks exactly like a 404).

### I6. When the build and the site disagree (review S2)

The build counts runnable blocks with the toolchain's fence reader; the site
reads them with Quartz's parser. Measured with remark against
`markdown_code.fenced_blocks`: callouts, folded callouts, tab-indented list
items and `%%` in code read alike; a fence opened on a line that opens a
list item holding another container (`- - ```python run`) was a block to the
site and nothing to the build, and a lazy line in a list item ends the block
on the site and not in the build. Russell's ruling (2026-10-17): the site
never shows "isn't on this site yet" for ever because of it. So:

- the build's reader now opens the nested-container block too (`nested`),
  and neither side makes it runnable (`findRunners` skips a block whose
  opening line opens a list item followed by another container on that
  line), so it stays plain highlighted code and the fences after it are read
  alike;
- the lazy line gives one runner on both sides (the site's body runs);
- and the SAFETY NET: the transformer leaves any runnable block whose
  engine the site does not carry as plain code and prints
  `plantoir: error: <page>.md: python block <n>: ` +
  `words.blockNotPrepared`, or `words.blockAfterUnclosedFence` when a fenced
  block above it on the page was never closed (the likeliest cause, review
  N3: the site closes such a fence at the end of its list item, the build's
  reader carries on) — never for a page students cannot see (the
  transformer applies `patches/publish.ts`'s test). The line is in the
  build's output only: the transformer runs after the folder checks are
  said, so it is not a folder problem in the app (a gap recorded on #455).
- both sides split the info string on the SAME separators (`INFO_SPACE`:
  tab, space and Unicode's space separators, NBSP — Option-Space — among
  them; review N2: micromark leaves `python<NBSP>run` all in `lang`, and the
  build used to call it a runner the site did not).

**Fuzzed** (review N2's generator, 2026-10-17): 856 random pages over 28
placements (428 with Unicode separators, 428 ASCII), each read by
`findRunners` over Quartz's parser and by `runner_fences`. 38 disagree, all
in known groups: the build alone counts a fence indented four spaces at the
top of a page or inside an HTML block (the site carries the engine for
nothing); the site alone decodes a character reference in the info string
(`&#114;un`), keeps a fence inside `$$` as maths, rejects a backtick in a
backtick fence's info string differently, and reads a few deeper
quote-and-list nestings differently — each of those shows as plain code
with the line above; and a lazy line that leaves a list fence open makes the
build's reader carry on and count a block the site shows as code text (the
fixes review's second fuzz, 1,284 pages, met it 3 times; bytes only)
(`knownLimits`). `blockAfterUnclosedFence` tells a teacher to close the open
block with a line like the one that opened it, indented the same: a closer at
column 0 under a list item or callout closes nothing on the site (measured
by the review; `pageShapes` pins the indented close).

`check_runner_rules_against_the_site.py` runs every `pageShapes` case
through both readers, and the transformer itself with the engine carried,
not carried, and on an unpublished page.

### I7. Saved edits, and print

**Storage** (`codeRunnerBlocks.storage`): `localStorage` key
`plantoir:runner:<base>:<id>`, `<base>` the site root's path as this page
resolves it (N5: previews reuse ports and folder publishes share a host),
holding `{originalHash, code}` (FNV-1a 32 of the teacher's code — not
`crypto.subtle`, which a preview reached over a school network's plain http
lacks). Written 400 ms after the last keystroke and at once on `pagehide`,
`beforeprint` and `addCleanup` (an edit then a link within 400 ms is kept).
Code equal to the teacher's removes the key. When the teacher's code has
changed since (the hash differs) the saved value moves to `<key>:set-aside`,
the live key is removed, the new code is shown and `words.teacherChangedIt`
said — once, because the live key is gone (S4); set-aside work is NOT
offered back. Ids are positional, so a block inserted ABOVE others sets aside
the edits on every block below it (knownLimits; the skill says to add blocks
after existing ones). `readonly` stores nothing.

**Print** (decision 8, `codeRunnerBlocks.print`): a synced
`<pre class="plantoir-runner-print" aria-hidden="true">` holds the current
code and the wrapper is `.plantoir-runner-edited` while it differs from the
teacher's (a textarea's typed value is not part of a printed or cloned
page). `@media print` hides the editor, input, buttons, status and output;
an unedited block prints its highlighted code, an edited one the student's
code. Paged.js promotes the same rules for the Print button, which awaits a
flush-and-sync pushed onto `window.plantoirPrint.prepare` (and removed in
`addCleanup`). print.inline.ts's code numbering sees the print copy as a
`pre` without `data-line` and counts its text lines.

### I8. Measured (2026-10-17, M4 Pro, macOS 26.6)

Against the verify fixture and a measuring page in EXC2O, served by
Plantoir's own preview unless the row says otherwise. "First Run" is the
press of Run to the first program's last line, Python loading included;
nothing of the engine was fetched on page load in any of them.

| Browser | First Run | Second Run | After Stop | `time.sleep(0.5)` lines arrived | Other |
|---|---:|---:|---:|---|---|
| Safari 26.6 | 954 ms | 25 ms | 887 ms | 15, 501, 1,001 ms | editor 16 px; on Netlify 1,509 ms, on Cloudflare 1,368 ms (6.1 and 6.3 MB brotli) |
| Chrome for Testing 155 (headless, verify.sh) | 1,077 ms | 159 ms | — | — | the whole of `browser-checks/code_runner.mjs` |
| Microsoft Edge 155.0.4283.45 (headless) | 1,069 ms | 255 ms | — | — | the whole of `code_runner.mjs` |
| iPad (A16) simulator, iOS 18.6, Safari by WebDriver | 1,040–1,050 ms | 21 ms | 990–1,056 ms | 4, 500, 1,000 ms | no zoom on focus (`visualViewport.scale` 1 → 1); Tab, Shift-Tab and Escape-then-Tab as I2 says (Escape-then-Tab only after the fix below) |
| WKWebView, the preview pane's configuration (an off-screen window) | 1,718 ms | 999 ms | 999 ms | all at once at the end | works end to end; its times are not comparable — macOS throttles timers and animation frames in a window nobody can see |

In Chrome and Edge the three broken servers end as I5 says: worker missing
→ `engineMissing` in 0.1 s; `.wasm` as octet-stream and a CSP without wasm →
`couldNotLoad` at the 45 s watchdog (both silent hangs otherwise). Five page
changes leave at most one worker (CDP `Target.setAutoAttach`). A simulator
can drive neither the on-screen keyboard nor a real iPad's Wi-Fi: those are
Russell's smoke test (Q6).

**Found by measuring, and fixed:** in the iPad simulator, Escape then Tab did
NOT leave the editor. Quartz's own Escape handler (`search.inline.ts` →
`hideSearch`) moves the focus to the search button on EVERY page, so the next
Tab (which in Safari visits form controls only) came straight back to the
editor. The editor now keeps its Escape (`stopPropagation`), and
`code_runner.mjs` checks that Escape alone leaves the focus in the editor —
red against the earlier script, green now.

**Print** (Chrome for Testing 155, `pdftotext`): ⌘P of an unedited block
prints the teacher's code and no button, input box or output; of an edited
one the student's code and not the teacher's; the Print button's handout,
after the edit, the student's code. ⌘P of pages that do not opt in, built
before and after this branch: Help Sessions 1 page and Building Series and
Parallel Circuits 3 pages each time, identical text.

**What every site's bundles cost** (EXC2O built with `origin/dev` 1f29ff04a's
image and with this branch's): `postscript.js` 106,596 → 121,277 bytes
(+14,681), `index.css` 57,824 → 60,812 (+2,988). Of 299 pages, 293 are
identical once the two KaTeX lines in the head (C2-26) and Quartz's own build
variance (the explorer's random id) are set aside; the other 6 (Curriculum
and tag listings) differ only in the order of entries that share a
build-time date — the variance F names.


### I9. Teacher note: "Writing a runnable block"

Add `codeRunner: true` to the page's settings and `run` after `python` on the
block's first line; add `readonly`, `stdin` or (sparingly) `autorun` after
it. Tell students what to type in the input box, one line per `input()`.
Preview and press Run on each block; a block that shows as plain code is
named on a `plantoir: error:` line. The skill `plantoir-runnable-code`
(support/agent_guidance) carries the whole of this for an assistant.

**Rejected** (with the reasons above and in 02 and 05): Skulpt; Custom
Frames or JupyterLite; SharedArrayBuffer for input and interrupts (a folder
publish cannot send COOP/COEP); window.prompt for input; CodeMirror (a large
editor per page for indentation); a Blob worker (Netlify's CSP has no
`worker-src`, so `blob:` is refused there); a classic worker (B1); an html-
stage plugin after pretty-code (the properties are gone by then); the
transformer's `externalResources` (inlined into every page); auto-indent on
Enter (it fights the iPadOS keyboard and IME); a `# plantoir: run` first
line (Obsidian takes only the info string's first word, so ` ```python run `
is an ordinary Python block there — verified from Obsidian 1.12.7's and
1.13.7's own code, 2026-10-08).

### I10. Swift (#493)

A ` ```swift run ` block on a page that opts in runs as a WebAssembly program
compiled ahead of time by the build's launcher ([05 → Runnable
Swift](05-build-pipeline.md#runnable-swift-what-the-launcher-and-the-build-do-493-v180),
[02 → The Swift image](02-docker-image.md#the-swift-image-493-v180)) -
Swift has no interpreter a browser can carry. Path A of the Phase 0 report on
#493: Embedded Swift per block (about 12-110 KB), and the full standard
library (about 3.4 MB, 0.9 MB brotli) for a block Embedded Swift cannot
compile or would print `(cannot print value in embedded Swift)` for.
Rules: `codeRunnerBlocks.swift`.

**Read-only, and why.** The student changes the input box, never the code:
editing would need a compiler somewhere other than the student's browser -
the compile service of #493 §7 (SwiftFiddle's runner), specified and
deliberately not built, so a service outage can never block a lesson. The
row's `editable: false` makes every Swift block keep its highlighted code
with Run and Stop only (no Reset, nothing stored), and `words.cannotEdit`
says so once, quietly, under the code (`.plantoir-runner-note`, hidden in
print). `readonly` is therefore not a Swift flag; `stdin` and `autorun` are.

**On the page.** The transformer wraps a Swift block like any runnable block
and, because the row is `prebuilt`, computes the block's key from the code
Quartz's parser read (`programKey`: SHA-256 of `normaliseProgram`, node's
crypto - not in `codeRunnerRule.ts`, which the page's script bundles too)
and looks it up in `quartz/plantoir-runners/swift.json`, which the build
wrote: `data-runner-wasm="static/swift-wasm/<key>.wasm"` when the program
exists, `data-runner-unready="<reason>"` when the build said why not (then
Run is off and `words.notReady` shows), and when the key is not listed at
all - the build's reader and Quartz's read the block differently, or the
page changed under a running preview - plain code and a `plantoir: error:`
line with `words.blockNotCompiled` (review S2's safety net, extended).

**The thread** is `static/swift/plantoir-swift-worker.js`, a module worker
like Python's, with the hand-rolled WASI shim beside it
(`plantoir-wasi.mjs`, the same file verify.sh's gate runs in Node). It
starts at once - there is no engine to load - and each Run sends the
program's address and the input lines. The program is fetched once per
visit and compiled from its BYTES (`WebAssembly.compile`, not
`compileStreaming`, which refuses a `.wasm` sent with the wrong type -
review N4: a self-hosted folder often sends `application/octet-stream`), and
every Run is a FRESH instance (a Swift program runs once; its globals cannot
be reset). Fetching is watched like an engine's loading: past 45 s,
`words.couldNotLoad`. Stop ends the thread, as for Python; the next Run
starts another, and the program comes from the browser's cache.

**The shim** answers what the compiled programs import - eight calls for
Embedded Swift, fourteen for the full library (Phase 0 and the spike
measured the same lists; any other import answers ENOSYS, so a toolchain
that adds one never fails to link). Three rules in it were each measured
into place:

- **fds 0-2 are a terminal**: `fd_fdstat_get` says CHARACTER_DEVICE AND
  leaves FD_SEEK and FD_TELL out of the rights. wasi-libc's `isatty()` needs
  both; with only the file type, stdout went fully buffered after its first
  line (the spike counted 2 writes for 01 instead of 5), and Embedded
  Swift's `Fatal error:` line - which goes to stdout - was LOST on a trap
  (spike G5, correcting Phase 0). verify.sh runs the must-fail: with every
  right set, fragment 10's line is lost; with the shim's, it is kept.
- **One stdin line per read, echoed as it is taken** (review S6), so the
  transcript reads `What is your name?` / `Ada` / `Hello, Ada!` as Python's
  does; past the last line, 0 bytes, and `readLine()` is `nil`. A prompt
  printed with `terminator: ""` would still sit in stdout's buffer when the
  program reads, and the echoed line came FIRST (measured 2026-10-17); so
  readLine() flushes stdout before reading - `ReadLineShim.swift` for
  Embedded Swift, `FlushBeforeRead.c` linked with
  `--wrap=swift_stdlib_readLine_stdin` for the full library (swift-gate 13
  and 14 pin both).
- **stdout and stderr decoded per stream**, holding a character split
  across two writes until it is whole (review N4).

**Int is 32 bits** (wasm32): `Int.max` is 2,147,483,647 here and
9,223,372,036,854,775,807 natively, so `13!` overflows and the program
traps with `words.crashed` and NO `Fatal error:` line, in both libraries -
even `-Onone` (7.4 MB) prints none, because an overflow check compiles to a
bare trap (measured 2026-10-17; implementation review S1; swift-gate 15
pins it). The skill and `knownLimits` tell teachers to use `Int64` for
factorials and large totals.

**Traps.** An index out of range, a `nil` unwrapped with `!`, or the 256 MB
memory cap ends in `WebAssembly.RuntimeError`; a recursion past the
browser's own stack ends in `RangeError`, which is NOT a RuntimeError
(review S5, Chrome 155 and Safari 26.6) - both are `words.crashed`. The
`Fatal error: ...` line is already in the output when the program printed
one (stdout under Embedded Swift, stderr under the full library); a stack
overflow prints none. `exit(n)` with n ≠ 0 is `words.exitCode`. The memory
cap is a link flag (`--max-memory=268435456`): without it a list that grows
for ever reached 2 GB in a tab before trapping (review S5); with it, 0.06 s
in Node. Embedded Swift then says `Fatal error: Unexpectedly found nil while
unwrapping an Optional value` - misleading, measured, in `knownLimits`.

**The S4 finding, and why reproducibility does not matter.** A one-call
`swiftc` puts a random temporary path into a 16-byte module-hash segment, so
the same code compiled twice gave different bytes (spike G4); compiling to a
fixed object path per key (`/tmp/plantoir-swift/<key>/main.o`) makes one
image give the same bytes every time (verify.sh checks two fragments), but
the macOS and Linux toolchains still differ in that segment, and parallel
compiles in different folders would too (review S4, measured with three
folder names). None of it matters, because NOTHING keys on the program: the
cache key is the code's hash plus the recipe's (the toolchain id), and a
program is only ever produced from that pair and served by that key. The
reproducible-bytes requirement the spike's correction implied was dropped
(review S4 ruling); the fixed path stays because it costs nothing.

**Measured** (2026-10-17, M4 Pro, macOS 26.6), on verify's planted Swift
Playground (a greeting reading two lines, a loop that never ends, an index
out of range, `exit(3)`, a block that does not compile, and swift-gate 05,
which needs the full library), served from the Mac with no compression.
"First Run" is the press of Run to the status saying it ended, the thread
and the program's fetch included; nothing of Swift was fetched on page load
in any of them.

| Browser | Embedded, first Run | Embedded, again | Full library, first Run | Full, again | Stop | Everything else |
|---|---:|---:|---:|---:|---:|---|
| Chrome for Testing 155 (headless, verify.sh's `swift_runner.mjs`) | 57 ms | — | 54 ms | — | 2 ms | the whole check: read-only with the note, input echoed after each prompt, changed input changes the output, Run after Stop, the trap's `Fatal error: Index out of range` line and `words.crashed`, `words.exitCode` with 3, `words.notReady` with Run off |
| Safari 26.6 (AppleScript, the page's own script) | 25 ms | 11 ms | 21 ms | 15 ms | 0 ms | the same, all as expected |
| iPad (A16) simulator, iPadOS 18.6, Safari | 35 ms | 12 ms | 32 ms | 12 ms | 0 ms | the same, all as expected (driven by a measuring script the page loads and posts back - safaridriver's remote automation was off on this Mac) |

**What a student downloads on the first Run of a block**: its program -
the Embedded greeting 62,347 bytes (28,144 gzip, 23,951 brotli), the
full-library block 3,453,463 bytes (1,238,667 gzip, 927,100 brotli) - plus
the thread and the shim once per visit (10,925 bytes). Later Runs of the
same block come from the thread's own compiled copy; after Stop, from the
browser's cache. A real iPad on school Wi-Fi is Russell's smoke test, and
so is a real iPad's recursion depth (review S5 measured Safari 26.6 on the
Mac at about 2,000 calls).

**What every site's bundles cost** for the Swift runtime (EXC2O, against
#455's numbers in I8): `postscript.js` 121,277 → 125,230 bytes (+3,953),
`index.css` 60,812 → 60,949 (+137).

**Rejected:** Path B (one module per course, every block an entry point:
the full library is 0.9 MB brotli per block, not the 17 MB once feared, and
Path B would rewrite top-level code into functions, changing what
`main.swift` means); editing (the compile service, §7); `@bjorn3/browser_wasi_shim`
(the hand-rolled shim is about 220 lines and does exactly what the programs
import); `compileStreaming` (N4); one long-lived instance (a Swift program
runs once); mapping only RuntimeError to the crash words (S5); a dedicated
"called itself too many times" word (considered; one crash sentence, and the
known limit tells teachers how deep is safe); stopping the build on a compile
error (ruling Q1).

## J. Self-check quizzes (#563, v1.8.0)

The first half of #511. A `> [!quiz]` callout at the left edge of a page
becomes a question a student answers and checks in the browser: multiple
choice (one box ticked), select all that apply (two or more), short answer
and fill in the blank (an `[!answer]` inside the quiz, one line per blank),
each with an optional `[!explain]` revealed after the first Check or Show
answer, and `[!quiz|shuffle]` to shuffle the choices. Self-check only: no
accounts, no network, nothing reaches the teacher. The rules are data in
[`contracts/shared-rules.json`](../contracts/shared-rules.json) →
`quizCallouts`; the build's half is
[05 → Self-check quizzes](05-build-pipeline.md#self-check-quizzes-what-the-build-does-563-v180).
Format and syntax are #511's (decided 2026-10-11, not reopened); the eight
rulings of 2026-10-17 (Q1-Q8) and the plan review's ten should-fixes are in
the closing comment of #563.

**Compatibility.** A page with no `[!quiz]` outside fenced or indented
code comes out exactly as before: the text hook returns it untouched
(checked in Node for every `untouched` case - quiz syntax shown in a fence
(review S2) and in indented code at the page's level, inside a callout and
under a list item (the implementation review's S1: a `>` four or more
columns past its container's content opens nothing, in both readers) - and
by verify 6k on a planted `Quiz Code Shown`, which is also named in no
folder problem), and the two later stages act only on a page whose text
holds `[!quiz`. `[!question]`, and `[!answer]` and `[!explain]`
outside a quiz, are untouched and stay searchable. The script and styles are
in every site's shared `postscript.js` and `index.css` (ruling Q2; every
rule under a `plantoir-quiz` class, the script returns at once with no
quiz). Measured on EXC2O (no quiz): `postscript.js` 122,138 → 136,068 bytes
(+13,930; gzip 40,867 → 45,378, +4,511), `index.css` 60,812 → 65,787
(+4,975; gzip +700), and 297 of 302 pages and feeds identical (05 has the
other five, which differ between two builds of the same image).

### J1. The files (all in `support/quartz/`, installed every build)

| File | What it does |
|---|---|
| `plugins/transformers/quizRules.ts` | The ONE implementation of the rules, pure (no DOM, no imports): `parseAnswerLine`, `splitAlternatives`, `parseNumber`, `normalise`, `accepts`, `shuffledOrder`, `verdict`, `isBlank`, and the text hook `nestedTitlesOwnTheirLine`. The transformer decides what each quiz is with it; the page's script checks answers with it. `scripts/check_quiz_rules_against_the_site.py` bundles it and runs every parse, check and shuffle case in Node (110 on 2026-10-17). The Python mirror, `scripts/quizzes.py`, parses and decides but never checks an answer. |
| `plugins/transformers/plantoirQuizzes.ts` | `PlantoirQuizzes`, wired straight after `Plugin.PlantoirFigures(),` (so after Description; anchored on the figures line so a fresh site and an old one stand in the same order, review N7). Three hooks, below. |
| `components/scripts/quiz.inline.ts` | Check, Show answer, feedback, the shuffle, keyboard folds, the score (J4). Imports `quartz/plantoir_quiz.json` (the words only). Works out the page's slug and root itself: importing `util/path` put a second copy of that module into `postscript.js` (3,266 bytes, measured). |
| `components/styles/quiz.scss` | Every rule under `.plantoir-quiz` (or `.plantoir-quiz-score`); 16 px boxes (no zoom on focus), 44 px targets, the theme's colours with dark-mode marks, `@media print` (J5). |
| `components/PlantoirMetaLine.tsx` | Carries the script and styles, as it carries the figures' (no new component or layout edit). |

### J2. Three stages, and why

* **Text** (before parsing). ObsidianFlavoredMarkdown gives a callout's
  title line a paragraph of its own only at the page's left edge (its
  `calloutLineRegex` is `^> *\[!…`), so in `> > [!answer]-` then `> > $2^7$`
  the answer went INTO the title (measured, plan M2: the title read "Answer
  2^7", the body empty; an explanation's first line likewise). Inside a quiz
  only (ruling Q1 - the general fix would change existing sites and the
  printing skill's empty-`>` advice; a separate issue), after any nested
  callout's first line, the hook adds one line holding just its `>` markers.
  Line endings are made LF first (review S1: Windows writes every build copy
  in text mode, CR LF, and the hook did nothing there), fences are skipped
  at every depth (S2), and a page with no quiz outside fenced code comes
  back as it came - CR LF included.
* **Markdown** (after GitHubFlavoredMarkdown; a task item's `checked` is set
  at parse time, M1). Every quiz that is a CHILD OF THE PAGE becomes the
  markup below; one inside a list or callout (ruling Q3) is rendered not
  ready with `notAtTopLevel`. Answer lines are read from the page's own
  text by the `[!answer]` blockquote's lines (two `>` markers off, trimmed),
  never from the parsed tree, which has already turned "quotes" curly and
  `\|` into `|` (M3). Every task box's tick is taken off the page (M7: a
  task list renders `<input checked disabled>`, the answer key on screen).
  A `$...$` answer is shown through the page's own parser (`this.parse`):
  only a parsed formula node carries what rehype-katex renders (review S9;
  measured, the revealed answer holds `.katex`).
* **HTML** (after Description, before Latex). The question's id, the
  choices' `aria-labelledby` and `aria-describedby`, blanks
  (`<code>____</code>`, M4) made into boxes, and the page's search text and
  summary made again WITHOUT the quizzes' answers and explanations
  (ruling Q5; review S3: Description had put "Answer 42" into the meta
  description, og:description, the RSS item and contentIndex.json). The
  summary is recomputed only when the page names no description of its
  own, with Description's own rules copied (150 / 300 characters, its link
  rule); a blank reads as `…` in both ("Fill … and …." - pinned by 6k).

### J3. The markup, and what a screen reader hears

Quartz's callout stays (colours, title, fold) and gains `plantoir-quiz`,
`data-quiz-n` (place among the page's top-level quizzes), `data-quiz-source`
(the slug of the page it was written on), `data-quiz-kind`,
`data-quiz-shuffle`, `data-quiz-hash` (FNV-1a 32 of its source) and
`data-quiz` (the correct places, or the answer lines - a self-check, so the
page's source showing answers is accepted, knownLimits). Not ready:
`data-quiz-kind="notReady"` and `data-quiz-problem`, the question and its
choices with every box empty, and `words.site.notReady` (ruling Q6).

* Choices are a `<fieldset>` labelled by the question; each is a real radio
  button or checkbox inside a `<label>` with the choice's first line.
  Anything after it - a graph, an image, code to run - sits OUTSIDE the
  label (pressing Run never ticks it; measured) and describes the box
  (`aria-describedby`, review S7), so "Graph A" is read with the graph's
  description. A box needs words after it on its line to be a box at all
  (measured), so a choice with no words of its own is named
  `choiceNumber` and the figure's description when it happens.
* No `name` is set when the site is built: the script gives each quiz on
  the page its own, and renames an id a transclusion has duplicated.
* Blanks are text boxes labelled "Blank n of count"; a short answer's box
  `answerLabel`. Autocomplete, autocapitalize, autocorrect and spellcheck
  off.
* Feedback is a polite live region; a blank is marked in words and a sign
  (✓ Right / ✗ Not right) and `aria-invalid`, never colour alone.
* Folds (review S6): Quartz's fold titles listen for clicks only, and a
  folded callout's content stays focusable. Inside a quiz, each fold title
  is `role=button tabindex=0 aria-expanded` and opens with Enter or Space;
  folded content is `inert` until opened; a revealed explanation is opened
  (its height recomputed - Quartz measured it while hidden, M9).

### J4. Checking, the shuffle, and the score

`accepts` (contract `answers`): alternatives on ` | ` with a space or tab on
both sides; numbers by value (decimals with or without a leading digit,
integer fractions, `+ - −`; not `1e3`, `0x10`, `Infinity`, a comma, `½`,
ruling Q7); `A ± T` only as a number ± a number not negative, so `±3` and
`x = ±3` are answers and `+-` typed matches `±` (review S8); `$...$`
compared inside; NFKC then `toLowerCase()` with no locale (STRASSE is not
straße - pinned), curly quotes made straight (iOS Smart Punctuation).

The shuffle moves the choices (reading and Tab order follow what is seen;
CSS `order` was rejected, WCAG 1.3.2) with `shuffledOrder(n, Math.random)`
on every load; `beforeprint` puts Markdown order back for ⌘P and
`afterprint` the shuffle; the handout sorts its own copy by `data-choice`.

The score (ruling Q4, right on the FIRST Check): `localStorage`
`plantoir:quiz:<site root path>:<page slug>` = `{v: 1, quizzes:
{"<source slug>#<n>": {hash, firstTry}}}`, keyed by the quiz's SOURCE page
so a transcluded quiz keeps its own entry (review S5); a hash that no
longer matches is ignored; every call in try/catch. Shown after the page's
last quiz once one is answered, with Start again; a quiz shown twice on a
page (two transclusions) counts once, and each copy's ids are its own
(measured on the planted `Quiz Twice`).

**Transclusion (review S5), measured rather than limited:** Quartz copies
the source page's finished HTML into the host, so a transcluded quiz keeps
its own `data-quiz-source`, ids and answers; on `Quiz Host` (its own quiz 1
and `![[Quiz Source]]`'s quiz 1) the two have distinct ids, labels and
radio groups, and the transcluded one is scored as `Quiz-Source#1`. So it is
interactive, not the not-ready fallback the ruling allowed.

### J5. On paper (ruling Q8)

A quiz prints as its question: buttons, feedback, score, answer, explanation,
marks and the not-ready line hidden; native boxes hidden and an empty ○ (one
answer) or □ (select all) drawn; a blank an empty line. `print.inline.ts`
gives callouts INSIDE a quiz no role (a folded `[!answer]` there would have
been lifted into the handout's key, M10), and its handout copy removes what a
quiz holds back, sorts the choices back and draws the boxes (a copy keeps
what a student ticked or typed). Measured: `Quiz Printable`'s handout holds
both quizzes' questions, the page's own folded answer in its key, and
neither quiz's answer nor its explanation. The answer key for quizzes is
#511's.

### J6. Measured (2026-10-17, M4 Pro, macOS 26.6, Chrome for Testing 155)

`browser-checks/quiz_check.mjs` on the verify fixture's `Quiz Playground`
(eight quizzes: every kind, a shuffle, a folded quiz of graphs, code to run
and a picture in choices, graphs and code in explanations), `Quiz Host` and
`Quiz Printable`: every kind wrong then right in the contract's words; an
empty answer never checked; the explanation's TEXT visible after a Check and
its graph drawn; Show answer's badge, and its formula set by KaTeX; Enter in
a box checks it; a folded quiz's title opens with Enter and its content was
inert; Run in a choice does not tick it; Swift (#493) runs in a choice and in a revealed explanation, printing `6` from each (measured after merging #493, the compile through preview.sh's Swift image); answering asks no website and the
site for nothing; the shuffle in 19 orders over 20 loads; print media hides
every held-back part and draws ○ and □; the score kept across a reload and
cleared by Start again, and every quiz still checks with `localStorage`
throwing; five page changes leave one listener set per quiz and one for
printing; the transclusion above; the handout. Light and dark screenshots
read cleanly (marks and badges have dark-mode colours). NOT measured here:
Safari, iPadOS, VoiceOver, the mac preview pane, Netlify (#563's closing
comment lists them as owed).

### J7. Teacher note: "Writing a self-check question"

Start a callout at the left edge with `> [!quiz]` and the question; tick the
right choice with `- [x]` (two or more for select all), or put the answer
inside on its own line under `> > [!answer]-` (one line per `` `____` ``
blank); add `> > [!explain]- Why` for the reason. Separate accepted answers
with ` | `; `3.14 ± 0.01` for a range. Preview and answer each question; one
that cannot be checked is named in the folder problems with its line. The
skill `plantoir-quizzes` (support/agent_guidance) carries the whole of this,
with patterns, for an assistant.

**Rejected** (with the reasons above and in the plan): a ```` ```quiz ````
fence (#511: no maths or graphs inside, and Obsidian shows a code block);
CSS `order` for the shuffle; a frontmatter key (a second switch that can
disagree with the page); a per-page `<script>` (Quartz's SPA head patch, and
a second loading mechanism); patching ObsidianFlavoredMarkdown for every
nested callout (Q1); Python checking answers (one implementation only);
`<label>` around a choice's blocks (Run would tick it); a radio `name` at
build time (a transclusion would join the page's group); one words-and-pages
JSON (the page's script bundles the words, so a file that changes with every
quiz problem would change `postscript.js` too).

**Departures from #563's wording**, recorded so they are not mistaken for
omissions: assets ride every site's shared bundle rather than "only on pages
that use a quiz" (ruling Q2, measured above), and a malformed quiz is a
folder problem with page and line rather than "build fails" (the ruling for
#493: a build is never stopped by one page).

## E. Summary: what is *not* customized

Everything else is stock Quartz v4.5.0 — the explorer's STYLES included,
except the page marker H adds on top of them from `support/quartz` — with six asset exceptions, all in
`quartz/static/` and all written every build: `og-image.png` is redrawn as the
section's social sharing card (C2-13), and `favicon.ico`, `icon.svg`,
`apple-touch-icon.png` and `icon.png` are the site's own icon (C2-25); since
#494 every site also carries `static/katex/`, KaTeX's own stylesheet, copy-tex
and faces, which its maths was linked to on a CDN before (C2-26). Two of
those OVERWRITE files Quartz itself ships — `og-image.png` and `icon.png` —
which is deliberate: a built site should carry no Quartz artwork, including
where nothing links to it. (`quartz/util/og.tsx` reaches for `static/icon.png`
when it draws generated OG images, so it now picks up Plantoir's mark too.)
Beyond those (and the gated engines F, G and I carry only where a page asks):
the Markdown/OFM transformer
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
