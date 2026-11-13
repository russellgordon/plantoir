# Plantoir Help: the source, for builders

This folder is the one source of Plantoir Help (#839). It is built into the
Mac's Help book, into a plain web copy for plantoir.app at `/help/`, and later
into the Windows app's Help. This file is for whoever builds or checks Help.
It is not read by teachers, and it is not where Help's words are written:
every page, caption and alt text is written by Fable from a fact sheet
(decision 5 on #839).

## What is here

| Path | What it holds |
|---|---|
| `outline.json` | Every page: id, title, question, section, assistant flag, scenes, `indexed`. The pages' identity lives here only. |
| `pages/<id>.md` | A written page. A page with no file is built as a stub. |
| `menu-paths.json` | `{{menu:}}` ids: `entries` → `{"mac": "Section ▸ Deploy…", "windows": null}`, `"system": true` for a menu the golden does not list, `"windowsKey"` for Windows' shortcut. |
| `system-menus.json` | The few menu paths outside the golden (Plantoir ▸ Settings… and the like), each with the source file that makes it. |
| `controls.json` | `{{control:}}` ids: `entries` → `{"label": …, "mac": {"file"} or {"wording"} or {"say"}, "windows": null}`; `keys` for shortcuts that are not menu items. |
| `facts.json` | `{{fact:}}` ids with `value`, `read` (a date) and `source`; and `assistantOnTheWeb`, the one switch for the assistant section on the web (decision 12). |
| `scenes.json` | One entry per picture (schema below). |
| `tone.json` | The writing brief's banned words and shapes, and exemptions scoped to pages. |
| `assets/` | `tokens.css` (the one copy of the colour and type tokens), `help.css`, `search.js`. |
| `pictures/` | `<scene>-light.webp` and `<scene>-dark.webp`. |
| `build_help.py`, `helpbook/` | The build and its checks. Standard library only. |
| `tests/` | `unittest` files, each runnable as `python3 help/tests/test_x.py`, and an invented fixture repository. |

## Commands

```text wrap
/usr/bin/python3 -I -B help/build_help.py --check
/usr/bin/python3 -I -B help/build_help.py --mac <out>/Plantoir.help [--app-version 2.0.0]
/usr/bin/python3 -I -B help/build_help.py --web <out>
/usr/bin/python3 -I -B help/build_help.py --release-web <out>
/usr/bin/python3 -I -B help/build_help.py --serve <out>
```

Every command except `--serve` runs every check first and exits 1 on any
failure, so the Xcode build phase (piece P1) fails the Debug, test and Release
build on them. Warnings are printed and never fail a build: a dated fact older
than 60 days, an unused registry id, a sentence over 25 words, a scene with no
`shows`. Piece F adds `--release`, which refuses those too.

- `--check` writes nothing and prints one line: pages written, stubs, scenes
  awaiting capture, warnings, failures.
- `--mac` writes the book (below) and prints its size. No size is refused
  (decision 11).
- `--web` writes `index.html`, one `<id>.html` per page, `assets/` and the
  pictures pages use. `--release-web` does the same and refuses any stub or
  placeholder picture: it is what `website/build.py --deploy` will call when
  #840's P6 puts `/help/` on plantoir.app.
- `--serve` serves a built web copy on `127.0.0.1` at a free port and prints
  the address. It never opens a browser.

## A page

```text wrap
---
id: schedule-deploy
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/Views/Section/ScheduleDeploySheet.swift
keywords:
- schedule
- later
description: One sentence for search results.
---
The first sentence says what the page helps you do.

## Steps

1. Choose {{menu:scheduleDeploy}}.
2. Press {{control:scheduleButton}}.

{{picture:schedule-deploy-1}}
alt: One sentence saying what is shown and what matters in it.
```

Front matter carries only `id` (equal to the file name), `checked`, `covers`,
`keywords`, `description`, `indexed`, `factsChecked` and `authority`. The
title, question, section, assistant flag and scenes come from `outline.json`,
and front matter that restates any of them is refused, so the two can never
disagree. A written page needs `checked`, `description`, and `keywords` when it
is indexed. Every `covers` path must exist, because a typo there would quietly
switch off F's freshness check for that page.

A **stub** (an outline id with no file) renders its title, its question and a
fixed "This page is being written." box. That sentence and the placeholder
label are fixed strings, not Help prose; `--release-web` and F refuse every
stub and placeholder, so neither ships.

The **contents page** (`index.html`) shows section titles and page titles
only. The outline's section `purpose` strings are the planner's words, so they
never appear; an introduction appears once `pages/index.md` is written (W1).

### The Markdown subset

`##` and `###` headings (a `###` before any `##` is refused; the `h1` is the
outline title); paragraphs; numbered and bulleted lists, one level of nesting;
`**bold**`, `*italic*`, `` `code` ``; links `[words](page:<id>)` and
`[words](https://…)`; fenced blocks with a language (`text wrap`, `swift`,
`python`; a bare `text` is refused, the house rule for text blocks); pipe
tables with a header row (rendered with a full border and `<th scope="col">`);
one callout, `> [!note]`. Raw HTML, images in Markdown syntax, `#` headings,
horizontal rules and other quote blocks are refused with the file and line.

### Tokens

| Token | Renders | Checked against |
|---|---|---|
| `{{menu:<id>}}` | the path in bold | `mac-app/Tests/Goldens/menu-bar.txt`, or `system-menus.json` for a `system` entry |
| `{{control:<id>}}` | the label in bold | a Swift string literal in `mac.file`; the literal of `static let`/`var` `mac.wording` (`Type.member`) under `mac-app/QuartzTeachers`; or `mac.say` |
| `{{say:<file>#<key path>}}` | a sentence the app shows | `contracts/<file>.json`, dotted path with `[n]` for list items; the value must be a string |
| `{{fact:<id>}}` | the value | `facts.json` |
| `{{key:<id>}}` | the shortcut | a menu id's key in the golden, or `controls.json` → `keys` |
| `{{count:<name>}}` | a number | counted from `support/` by `helpbook/counts.py` |
| `{{picture:<scene>}}` + `alt:` line | a picture or its placeholder | the page's outline `sceneIds` and `scenes.json` |
| `{{mac}}…{{/mac}}`, `{{windows}}…{{/windows}}` | a run for one platform | may not nest |

The golden is parsed as `MenuBarTreeTests` writes it: `== <Menu>` opens a
menu, two spaces of indent per level, tags after two or more spaces (`[⇧⌘N]`
is the key, `[if …]` and `(alternate)` are dropped), `----` is a divider. The
Mac shortcut of a menu item is read from the golden, never typed.

The Mac book keeps the Mac runs. The web copy wraps each run in
`data-platform="mac"` or `data-platform="windows"`, marks a page's Mac run
`data-shared="true"` when the page has no Windows run, and hides Windows runs
with CSS, so a later Mac/Windows switch on the site (question 2 on #839) is
added without rebuilding the pages.

### Scenes

`scenes.json` → `scenes` → `<scene id>`: `page`, `shows`, `labels` (the red
word labels), `expectText` (OCR words, filled by P3 and CF), `awaiting_capture`,
`waiting_on` (`"#<issue>"` or absent), `setup`, `windows` (null until Windows),
`raw` (true when the site also needs an unannotated copy,
`<scene>-<light|dark>-raw.webp`). Scene ids are `<page id>-<n>` and are never
renumbered: a new picture takes the next number. A scene awaiting capture, or
whose two files are not both present, renders as a placeholder: a grey box the
column's width with the scene id, what it shows and its labels as words, so
nothing depends on colour. A real picture renders as `<picture>` with a dark
`<source>`, `width` and `height` at half the pixel size read from the WebP
header.

## The checks, and why

1. **Identity.** Outline ids are unique, `anchor` equals `id`, `pageCount` and
   `sceneCount` match the lists, each page's `scenes` matches its `sceneIds`, a
   page is `assistant: true` exactly when its section is. Each page file's id
   is an outline id and equals its file name.
2. **Tokens and registries.** Every token resolves; every registry entry is
   true (its menu path is in the golden, its label is in its Swift file). An
   id no page uses is a warning: the integrator of a writing batch commits the
   registry entries before the pages that use them.
3. **Links.** `page:` names an outline id; `https://` is well formed (never
   fetched). A link to a page the web copy leaves out keeps its words and
   loses its link there.
4. **Words** (`helpbook/words.py`, which #840's P6 will make the site import):
   - `contracts/shared-rules.json` → `userFacingLabelWords.forbidden`, whole
     word and any case, as the app's `UserFacingLabelWordsTests` matches it;
   - the site's `MACHINERY` pattern, copied from `website/build.py`;
   - `tone.json`'s banned words and shapes;
   - **Help's own publish rule.** PUBLISH marks a page for students; DEPLOY
     sends a section's site somewhere. "publish…" followed within five words
     (in the same sentence) by site, website, online, Netlify, Cloudflare,
     GitHub Pages, a folder, or "to a section", is refused; so is "deploy…"
     followed within five words by page or pages ("GitHub Pages" and
     "Cloudflare Pages" are destinations, not pages). Only the words after
     the verb count, so "publish the pages, then deploy the section" passes.
     The site's rule (every "publish" must be on an allowed list) was
     rejected for Help: "publish" is Help's correct verb and a real menu item,
     and that rule failed five approved titles (plan review H1).
   - a count typed by hand (a digit within four words of course or code, the
     rule of `website/build.py` → `typed_count_problems`): write
     `{{count:ready_made_ontario}}`;
   - a run of more than three words in double quotes, which is either a
     sentence the app shows (use `{{say:}}`) or should be described, unless
     `tone.json` → `quotes` exempts it for that page with a reason;
   - a sentence over 25 words is a warning.

   The check reads titles, questions, descriptions, keywords, headings, body
   text, table cells, alt text and placeholder labels, stubs included. It
   never reads code spans, fenced blocks or the text of tokens. An exemption
   in `tone.json` is an exact phrase scoped to page ids, with its reason:
   "Python" on `code` and `subject-computer-studies`, "3D model(s)" on
   `models-3d`.
5. **No contract sentence typed by hand.** Every run of five or more words in
   `contracts/assist-wording.json` (all of `wording`), and in the `sentences`,
   `wording` and `words` values of every other `contracts/*.json`, that appears
   in a page outside a `{{say:}}` token is refused. A placeholder (`{name}`,
   `%@`) splits a sentence into the runs around it.
6. **Head fields** of written pages, as above; stubs are exempt.

## The Mac book

`Plantoir.help/Contents/Info.plist` holds exactly the keys of decision 2
(`CFBundleIdentifier` `ca.russellgordon.Plantoir.help`, `HPDBookType` `3`,
both index paths, `HPDBookKBProduct` `plantoir`, the version from
`--app-version`). `Contents/Resources/en.lproj/` holds `index.html` (anchor
`plantoir-help`, `robots: anchors`), one `<id>.html` per page, and
`InfoPlist.strings`; `Contents/Resources/assets/` the CSS (no JavaScript);
`Contents/Resources/pictures/` only the pictures pages use; and
`Contents/Resources/anchors.json`, the page anchors for P1's `HelpBookTests`.
The language folder and the pages' `lang` (`en-CA`) come from one constant in
`helpbook/__init__.py`, so a second language is added, not retrofitted.

Each page's head is, in order, `charset`, `title`, `keywords`, `description`,
`robots` (`index, anchors`, or `anchors` when not indexed) and
`color-scheme: light dark`. `<a name="<id>"></a>` is the first thing in
`<body>`, before the `h1`. Sub-headings carry `id`s for the web copy only.

The build runs, inside `en.lproj`, `hiutil -I corespotlight -Caf
Plantoir.cshelpindex -vv .` and `hiutil -I lsm -Caf Plantoir.helpindex -vv .`,
then reads the result back: `hiutil -I corespotlight -Af` must list every page
id, and `hiutil -I corespotlight -Df` must map each id to `/<id>.html#<id>`.
The `.helpindex` cannot be inspected, so it is checked for existence and size.

It builds into `<out>.building` (a stale one is removed first, and a failed
build removes its own), hard links an unchanged picture from the old book
(same size and SHA-256), and swaps the new book in by renaming, so a deleted
page never lingers and pictures are not rewritten.

### Measured (2026-11-13, macOS, hiutil 2.0)

- **One anchor a page.** Every anchor on a page resolves to that page's FIRST
  anchor: a page with `<a name="first-one">` before `<a name="twice">` maps
  `twice` to `/twice.html#first-one`. Hence the anchor first in `<body>`, and
  the `-Df` read-back that fails the build when an id maps elsewhere.
- `-Af` without `-I corespotlight` prints "Index format no longer supported"
  and exits 5; every inspection passes `-I corespotlight`.
- Index bytes differ between two runs over identical pages, so they are never
  compared across builds.
- A `robots: anchors` page is listed with no title or description.
- The real 100 stubs build into a 136 KB book in 0.36 s.
- `/usr/bin/python3` is 3.9.6, the Python an Xcode build phase gets. `-I`
  takes the script's own folder off `sys.path`, so `build_help.py` inserts it
  explicitly, and it finds the repository as its own folder's parent, never
  the current directory, because the build phase runs it from elsewhere. The
  code keeps to 3.9 syntax (a test parses every file with
  `feature_version=(3, 9)`), so it also runs on the Windows runtime's 3.14.

### Rejected

- **A third-party Markdown module.** Xcode's Python has none, the Windows
  runtime would need it too, and a full Markdown passes raw HTML through. Our
  subset refuses what it does not know.
- **`id` anchors for pages.** Help Viewer resolves `<a name>`; sub-heading
  `id`s are not anchors, which is why they are safe on the web copy.
- **A fetched search index.** `fetch()` fails from `file://`, which is how
  Windows will open the copy; `search-index.js` is a script that sets
  `window.PLANTOIR_HELP_INDEX`.
- **A size cap.** Ruled out on 2026-11-13 (decision 11): the size is printed.
- **Importing `website/build.py`.** It uses 3.10 syntax. `counts.py` and two
  lists in `words.py` are copies that name their source until #840's P6 moves
  the site onto these modules.

## The web copy

Flat `<id>.html` files with relative links, so the copy works from `file://`
and in a folder on the web alike. Once deployed at plantoir.app/help/, each
`/help/<id>.html` is an address that must never move: a renamed page keeps its
id. Every page has a search form that sends `?q=` to the contents page, which
lists the matches with `assets/search.js` (without scripts, the form lands on
the contents). The assistant section, its pages and its contents heading are
left out, and absent from the search index, while `facts.json` →
`assistantOnTheWeb` is false. The site's integration (`website/build.py`
writing `site/help/` and calling `--release-web` before `--deploy`) is #840's
P6, not this folder's.

## Tests

`help/tests/test_*.py`, standard library `unittest`, green under `python3` and
`/usr/bin/python3 -I -B`. They copy `tests/fixtures/repo/` (an invented
repository: no names, nothing real) to a temporary folder, change one thing,
and run `build_help.py` against it with `-I -B`. The `hiutil` tests skip off a
Mac; the search test runs `search.js` with `node` and skips without it.
`verify.sh` runs each file. Windows' `PythonToolchainTests` discovers only
`scripts/test_*.py` today, so wiring these in is a Windows obligation.
