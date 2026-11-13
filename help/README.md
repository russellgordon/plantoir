# Plantoir Help: the source, for builders

This folder is the one source of Plantoir Help (#839). It is built into the
Mac's Help book, into a plain web copy for plantoir.app at `/help/`, and later
into the Windows app's Help. This file is for whoever builds or checks Help.
It is not read by teachers, and it is not where Help's words are written:
every page, caption and alt text is written by Fable from a fact sheet
(decision 5 on #839).

## For the writers: read this first

1. **Steps and pictures.** Number steps `1.`, `2.`, `3.` in order; writing
   `1.` for every step is refused. A picture, a note, a table, a code block or
   a run (`{{mac}}`, `{{assistant}}`) may sit between two steps: number the
   step after it as the next one (`3.`), and the steps count on. A run may
   hold numbered steps of its own, numbered on from the steps above; when the
   web copy leaves an `{{assistant}}` run out, it renumbers the steps after
   it, so a web page never shows 1, 2, 4. Writing `1.` after such a block is
   refused, and so is a gap. A heading, or a paragraph outside a run, between
   two lists starts new steps at `1.`; a sentence that belongs between two
   steps goes in a `> [!note]` or on an indented line under its step. Mark
   list items with `1.` or `-` only, indented with spaces; `*`, `+`, `1)` and
   tabs are refused.
2. **A picture's `alt:` line** goes on the very next line after
   `{{picture:<scene>}}`, with no blank line between, and says in one
   sentence what is shown and what matters in it.
3. **Name what the app shows with a token**: `{{menu:}}` for a menu path,
   `{{control:}}` for a button or label, `{{key:}}` for a shortcut,
   `{{say:}}` for a sentence the app shows. A token is checked against the
   app and is searchable on the web; a label typed by hand is neither.
   **Retyping the app's sentences.** A sentence of yours that IS, as a
   whole, a sentence the app shows (five words or more) is refused: write
   `{{say:key}}`. A longer sentence that holds one, or a phrase that shares
   its words ("ready for the start of the year"), is ordinary prose and
   passes. A label the app shows (no full stop) is never checked when typed,
   so always name a button or label with `{{control:}}` and a menu with
   `{{menu:}}`: a typed label goes stale silently.
4. **Publish and deploy: a person is the check.** Deploy sends a section's
   site somewhere (a folder, Netlify, Cloudflare Pages). Publish marks a page
   for inclusion, so students see it once the section is next deployed.
   Right: "Publish the pages, then deploy the section." "Published pages
   appear on the site after you deploy." "Deploy your site to Netlify." "You
   do not deploy a page: you publish it, then deploy the section."
   Wrong: "Publish your site to Netlify." "Your site is now published."
   "Deploy only the pages you changed." "Deploy Monday's class." No pattern
   tells these apart reliably (three reviews tried), so the build never
   fails on them: `--check` lists the sentences that may misuse either word
   under "For the page's reviewer: publish and deploy", with file and line,
   and counts them in its summary line. The reviewer reads each one.
5. **Counts.** A digit within four words of "course" or "code" is refused as
   a typed count, including grade and unit numbers: "a Grade 9 course",
   "Section 2 of the course", "Unit 1, Day 1 belongs to the course", "the
   course code MPM2D for Grade 10". The advice the build prints (use
   `{{count:}}`) fits only a real count; for anything else rephrase so the
   digit is more than four words from "course" and "code", or ask for a
   `tone.json` exemption of the exact phrase on that page (`class-pages` and
   the twelve subject pages will want one). Step numbers are not counted.
6. **Machinery words in their teaching sense** are refused too: "model",
   "script", "feed", "worker", "container", "Python". A page that needs one
   (Drama's script, a Science model) gets a `tone.json` exemption for that
   phrase on that page, with its reason.
7. **Do not write `{{windows}}` runs yet.** A token inside one fails until the
   Windows side fills its columns.
8. **Assistants, unit planning and Coverage on ordinary pages.** The web copy
   may not mention an assistant (Claude, Codex, GitHub Copilot, the
   assistant features), unit planning or the Coverage tab outside the
   assistant section yet (#804). Put such a sentence or block in an
   `{{assistant}}` … `{{/assistant}}` run, each marker on a line of its own:
   it stays in the Mac Help book and is left out of the web copy. The check
   reads the page as the web shows it, so a `{{menu:}}`, `{{control:}}` or
   `{{say:}}` token that names one (Revise With ▸ Claude…), a code span, a
   link's address and `pages/index.md` all count: wrap the token in a run.
   An unmarked mention, or a link to a page the web leaves out, stops `--web`
   with its file and line (`withheld-on-the-web.json` holds the list).
9. **Banned**: an em dash, "!", "just", "simply", "easy", "quick" (except in
   "Quick start"), "best", and the rest of `tone.json`. A quoted run of more
   than three words in double quotes is refused. En dashes, single-quoted runs
   and `TODO(fact)` pass the build, but a reviewer flags the first two and F
   refuses the third at a release.
10. **Reading the output.** A finding in a paragraph names the paragraph's
    first line. Each finding is printed once. The "number this one N" hint
    after a numbering error can be wrong when several steps are misnumbered;
    renumber all of them in order.
11. **The words around the pages** (the stub box, "Picture to come", the
    search box) are in `interface-words.json`, by key: reword them there.
12. **Search on the web** folds plurals and endings ("classes" finds class
    pages, "scheduled" finds schedule, "quizzes" finds quiz) and ranks a page
    whose title, question or keywords hold the words above one whose body
    only mentions them. Keywords still help: put the words a teacher would
    type in `keywords:`, a common misspelling included ("Cloudfare"), since
    the search does not guess at spelling. A keyword of two or more words
    that a query says outright ("snow day") counts extra.
    **Two searches.** The web copy (plantoir.app/help, Windows) runs this ranking;
    Help Viewer on the Mac runs Apple's own index, which we do not control.
13. **Step numbers in prose.** Do not refer to a step by its number ("in
    step 4") on a page with an `{{assistant}}` run among its steps: the web
    copy renumbers the steps, and nothing checks numbers in prose. Say "the
    step above", or name the step's action.
14. **"Coverage" and "assistant" in any sense** ("curriculum coverage", "an
    assistant principal") are refused on the web copy outside an
    `{{assistant}}` run. Choose other words, or use the run.
15. **Front matter** is `id`, `checked: 2.0.0`, `covers`, `keywords` and
    `description`, plus `indexed`, `factsChecked` and `authority` where they
    apply. Never `title`, `question`, `anchor`, `section` or `assistant`:
    the outline owns them and the build refuses them. `pages/index.md` (the
    introduction above the contents) needs front matter holding only
    `id: index`; its body is the introduction.
16. **Run `--web` as well as `--check`** before handing a page over: a
    mention the web copy may not carry is only a warning under `--check`.
17. **A written page shows its title and not its question.** Only a stub
    prints the outline's question, so a page's first sentence must stand
    without it.
18. **`{{say:}}` in quotation marks.** Never type quotation marks around a
    `{{say:}}` token: Help sets every sentence the app shows in its own
    curly quotation marks, the same on every page.
19. **Dated facts.** A page whose facts come from someone else's
    documentation (GitHub's education benefits, a vendor's plans) carries
    `factsChecked: YYYY-MM-DD` and `authority: https://…`. The build prints
    them at the foot of the page, in both the Mac book and the web copy
    (`interface-words.json` → `factsChecked`, `factsCheckedAgainst`), so do
    not also write the date or the link in prose. `authority` without
    `factsChecked` is refused.
20. **Keywords: give both forms** of a word a teacher might type either way,
    and always where a word doubles its consonant ("quiz", "quizzes").
21. **A heading inside an `{{assistant}}` run**: keep everything under that
    heading inside the same run, up to the next heading, so the web copy
    never shows a section without its heading or a heading with nothing
    under it.
22. **Scene entries come first.** `{{picture:}}` fails until the batch's
    integrator has committed that page's scenes to `help/scenes.json`. Pages
    whose outline lists scene ids without picture descriptions take `shows`
    and labels from the fact sheet.

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
| `interface-words.json` | The fixed words Help shows around the pages (stub box, placeholder heading, search box and results), by key; checked like page text. |
| `withheld-on-the-web.json` | What an ordinary page may not say on the web copy while `assistantOnTheWeb` is false (#804), as patterns with reasons; the director may shorten it. |
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
  awaiting capture, warnings, publish/deploy notes for the reviewer, failures.
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
fixed "being written" box (`interface-words.json` → `stubSentence`). That sentence and the placeholder
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
| `{{assistant}}…{{/assistant}}` | lines that name an assistant: kept in the Mac book, left out of the web copy while `assistantOnTheWeb` is false | may not nest |

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
3. **Links and lists.** `page:` names an outline id; `https://` is well formed
   (never fetched). A link from an ordinary page to an assistant page must sit
   in an `{{assistant}}` run (below). Numbered steps count up by one, and the
   steps after a picture, note, table, code block or run carry on from the
   steps above, rendered `<ol start="3">`; a list that restarts at 1 there is
   refused. Each form counts the steps it shows: the web copy, which leaves
   an `{{assistant}}` run out, renumbers from 1, wherever the left-out steps
   were (first, last, all of them, or in two runs). The review of P2a found the old behaviour: steps after a picture
   silently restarted at 1, the shape of most how-to pages. Allowing a picture
   inside a list item was rejected: it needs indentation rules writers get
   wrong, and the refusal makes the wrong state impossible instead.
4. **Words** (`helpbook/words.py`, which #840's P6 will make the site import):
   - `contracts/shared-rules.json` → `userFacingLabelWords.forbidden`, whole
     word and any case, as the app's `UserFacingLabelWordsTests` matches it;
   - the site's `MACHINERY` pattern, copied from `website/build.py`;
   - `tone.json`'s banned words and shapes;
   - **publish and deploy, for the reviewer.** Sentences where publish may be
     used for sending a site, or deploy for a page (`PUBLISH_DEPLOY_MISUSE`
     in `words.py`), are listed by `--check` under "For the page's reviewer:
     publish and deploy" and counted in the summary line. They are never a
     failure: three rounds of review measured every pattern tried as wrong
     both ways (the third: 6 of 12 correct sentences flagged, 7 of 12 misuses
     missed), so a person reads them.
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
5. **No whole contract sentence retyped.** Its purpose is narrow: a sentence
   the app shows, retyped in a page, goes stale silently when the app's words
   change. So it refuses only a COMPLETE sentence of five words or more (one
   that ends with . ! ? or …) from `contracts/assist-wording.json` (all of
   `wording`) or the `sentences`, `wording` and `words` values of the other
   `contracts/*.json` (a value of several sentences gives each), found in a
   page's RUNNING PROSE (paragraphs, list items, table cells, alt text, the
   description, `pages/index.md`), and only when one of the page's sentences
   IS, as a whole, a contract sentence. It compares words: case, curly or
   straight quotes, dashes, punctuation and line breaks are ignored, and a
   placeholder (`{name}`, `%@`) stands for a name or a number: one to four
   words, the first a capital or a digit ("Section 2"), so "Put back as they
   were, the pages show again." is not taken for "Put back as they were:
   {pages}.". A shorter string, a label without a full stop, a fragment, or a
   longer sentence that holds a contract sentence is ordinary prose and
   passes. Three earlier forms were rejected: matching every five-word run cut
   out of the contract, and then matching a whole contract sentence anywhere
   inside a paragraph, both refused ordinary prose ("a folder on this
   computer", "If it fails, try again in a moment and it usually works.");
   per-page exemptions would have been needed on nearly every page. Titles,
   questions, headings and keywords are NAMES and are not read; a name in
   prose is kept true by writing it as a token.
6. **Head fields** of written pages, as above; stubs are exempt. A keyword
   holds no comma (it would split in `<meta name="keywords">`), and a page's
   `section` field in the outline is the section that holds it.
7. **The web copy and the assistant** (`--web` and `--release-web` only; a
   warning under `--check` and `--mac`, so no Xcode build fails on it). The
   terms of `withheld-on-the-web.json` are looked for in the RENDERED web
   page: text after every token is filled, code, alt text, titles, the page
   head, link addresses, the introduction and the contents page. An ordinary
   page that names one outside an `{{assistant}}` run, or links to a page the
   web leaves out, stops the web copy with its file and line. The file's
   `pages` are ordinary pages left out altogether (`coverage`). Ruled by
   Russell on 2026-11-12 (#804): plantoir.app never presents Plantoir as
   needing a paid assistant, and shows unit planning and the Coverage tab
   only after GitHub Copilot support has shipped and he has judged it
   reasonable; the director edits the file on that ruling. With
   `assistantOnTheWeb` true, the runs are kept (`data-assistant="true"`), the
   withheld pages are included and the check is off. Reading the source
   text instead was rejected by review: tokens, code and the introduction
   were ways round it.

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
- The real 104 stubs (outline revision 4) build into a 142 KB book.
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
the contents); only the contents page loads `search-index.js`. The index holds
each page's question from the outline (checked for withheld words on every
page, since it is searchable) and its text as RENDERED, so menu paths, control labels, shortcuts and
`{{say:}}` sentences are searchable; hidden Windows runs and the interface
words are left out. The search stems words (-s, -ies, -ed, -ing, and a
final e on both sides, so "classes" meets "class" and
"scheduled" meets "schedule"), drops small words ("how", "do", "I", "my",
"after"), lets the last word match as the start of a word, and matches a key
symbol inside a shortcut (⌘P finds ⇧⌘P). Pages need not hold every word. Each query word scores by
where the page holds it (title 5, question 4, keywords 4, description 2, body
1) times how rare it is across the pages, so a word nearly every page holds
("page", "student") carries almost nothing; the best keyword phrase the query
says outright adds its words' weight again; a page whose id and short title
the query covers gains a share of the query's weight. Pages scoring below 0.4
of the best are dropped, and at most ten results are shown with a line
counting the rest (`interface-words.json` → `searchMore`). The first ranking
(how many words a page held, then title and id) was tuned on stubs, whose
text was little more than the question; on the 73 written pages it put
`page-settings` above `missing-page` for "my students can't see the new page"
(common words in long bodies decided it) and returned 26 pages for a snow-day
question, so it was replaced. `test_build_help.py` holds twelve queries
measured on the stubs and twenty-seven written against the written pages
(misspellings, plurals, symptoms, menu item names), each with the page that
must come first. Rejected: a floor by count of words held (a long query of
common words kept dozens of pages), and counting every matching keyword
phrase (a page listing "answer key" and "answer keys" scored twice). Fuzzy matching of misspellings was not built: it is a
product choice for Russell. The assistant section, its pages and its contents heading are
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
