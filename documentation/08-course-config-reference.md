# 8. `course_config.json` Reference

[◀ Previous: Deployment](07-deployment.md) · [Back to index](README.md) · [Next: The macOS App ▶](09-mac-app.md)

`courses/<CODE>/course_config.json` is the single source of truth for a
course. It is **written** by the setup wizard
([`setup_course.py`](04-course-setup.md)), **read and auto-extended** by the
build ([`build_site.py`](05-build-pipeline.md) appends newly discovered
folders/files), and **statically imported** by the patched Explorer
components at Quartz build time
([customizations C2-1](06-quartz-customizations.md#c2-applied-on-every-build)).

A representative example:

```json
{
  "course_code": "ICS3U",
  "course_name": "Introduction to Computer Science",
  "custom_short_name": "",
  "locale": "en-US",
  "emojis": { "sections": { "section1": "🖥️", "section3": "🔬" } },
  "num_sections": 2,
  "section_numbers": [1, 3],
  "shared_folders": ["Concepts", "Examples", "Exercises", "Ontario Curriculum", "Tutorials"],
  "shared_files": ["Learning Goals.md"],
  "per_section_folders": ["All Classes"],
  "per_section_files": ["Key Links.md"],
  "hidden": ["Ontario Curriculum", "Learning Goals.md", "Media"],
  "expandable": ["Concepts", "Examples", "Exercises", "Tutorials"],
  "expandOnFolderClick": false,
  "footer_html": "…licence notice…",
  "show_reading_time": false,
  "fonts": {
    "default": { "header": "Montserrat", "body": "Lora", "code": "JetBrains Mono" },
    "sections": { "section1": { "header": "Montserrat", "body": "Lora", "code": "JetBrains Mono" } }
  },
  "show_section_marker": { "sections": { "section1": true, "section3": false } },
  "show_grade_in_title": { "sections": { "section1": true, "section3": false } },
  "color_schemes": { "section1": "nordic-frost", "section3": "mlb-toronto-blue-jays" },
  "custom_domains": { "sections": { "section1": { "netlify": "ics3u.myschool.ca" } } }
}
```

## Key-by-key

| Key | Type | Written by | Consumed by | Meaning |
|---|---|---|---|---|
| `course_code` | string | setup | build | Uppercased code, e.g. `ICS3U`. The 4th character, if a digit, encodes grade (1→9 … 4→12) and selects "course mode"; a non-digit (e.g. `CODING`) selects "club mode". |
| `course_name` | string | setup | setup (starting titles) + build (computed landing title, every build) | Human name. The build recomputes each section's landing title from it every time, so renames reach the site. |
| `custom_short_name` | string | setup (club mode only) | build | ≤ 12-char label shown beside the header emoji instead of the course code. Empty → fall back to title-cased code. |
| `locale` | string | setup | build → `quartz.config.ts` | One of Quartz's 27 locale codes; drives UI strings ([teacher-customized](06-quartz-customizations.md#d-locale-files-replaced-at-build-time)) and date formats. |
| `emojis.sections.section<N>` | string | setup | build (page title) | Single emoji per section, e.g. `"📚"`. Legacy `emojis.default` is honoured as a fallback. |
| `num_sections` | int | setup | setup (prompt default) + build and launchers (fallback when `section_numbers` is absent) | Count of sections; normalized to `len(section_numbers)`. |
| `section_numbers` | int[] | setup | launchers + build (validation) | The teacher's actual timetable section numbers, e.g. `[1,3,4]`. Only these sections can be built or deployed. |
| `shared_folders` | string[] | setup + build discovery | build | Course-root folders copied into every section's site. `Media` never appears here (symlinked instead). |
| `shared_files` | string[] | setup + build discovery | build | Course-root loose `.md` files copied into every section's site. |
| `per_section_folders` | string[] | setup + build discovery | build | Folder names expected inside each `section<N>/`, copied only into that section's site. |
| `per_section_files` | string[] | setup + build discovery | build | Loose `.md` files inside each `section<N>/`. |
| `hidden` | string[] | setup + build (auto-adds `Media`) | build → Explorer omit set | Items filtered out of the sidebar. Still built, linkable, and searchable. |
| `expandable` | string[] | setup + build discovery | patched Explorer (statically imported) | Folders rendered as collapsible trees; all other folders render as plain links to their index page. |
| `expandOnFolderClick` | bool | setup | build → `folderClickBehavior` + `data-expand-on-navigate` | `true`: clicking a folder name expands it. `false` (default): name navigates; only the chevron expands. |
| `footer_html` | string | setup | build → `Footer.tsx` | Raw HTML injected into every page's footer. |
| `show_reading_time` | bool | setup | build → `ContentMeta.tsx` | Show "N min read" on pages. |
| `fonts.default` / `fonts.sections.section<N>` | object | setup | build → `quartz.config.ts` typography | `header`, `body`, `code` font family names (Google Fonts or system stacks). Section entry wins over default. |
| `show_section_marker.sections.section<N>` | bool | setup | build (page title + computed landing title) | Whether the header shows `S<N>` and the computed landing title carries ", Section N". The build also accepts several legacy shapes (plain bool, flat map, alternate key names). |
| `show_grade_in_title.sections.section<N>` | bool (default `true`) | app (per-section settings) — the wizard never writes it, it only honours an existing value when generating a section's starting `index.md` title | build (computed landing title) | Whether the landing title leads with the grade ("Grade 11 …"). Deliberately literal — the switch alone decides; the app shows an orange warning when the name already contains the grade label. A legacy course-wide bool is honoured. |
| `color_schemes.section<N>` | string | setup | build → `quartz.config.ts` colors + social card | Scheme id from `support/colour_schemes.json` (43 available). The section's social sharing card is drawn in this scheme too. |
| `custom_domains.sections.section<N>` | object (per-destination-type map, e.g. `{"netlify": "…", "cloudflare_pages": "…"}`) | app (Advanced, per-section settings — one field per configured destination) | app (published-site links, per destination) + `build_site.py` (baseUrl, via the PRIMARY destination's own entry only — one build's sitemap/RSS/social-card links can only follow one domain) | The teacher's own domain for ONE destination of the section's published site. Links after a deploy swap that destination's own host for it (path preserved, https) — never another destination's. An OLDER shape (a bare string, from before a course could have more than one destination) is still read, as the domain for whichever destination is currently primary (`deploy_target`). The domain itself must already be configured with that host (Netlify/Cloudflare Pages) — this key only changes what Plantoir LINKS to. Entries are normalized (scheme and path stripped) on the way in. |
| `prepopulate_example_content` | bool | setup | setup (remembered on a re-run) | Whether the teacher took the ready-made payload for this course code. |
| `use_skeleton` | bool | setup | setup (remembered on a re-run) | Whether the teacher took the subject skeleton instead. Mutually exclusive with the key above — a course gets one starting content source or neither. |
| `include_curriculum_pages` | bool | setup | setup | Whether the curriculum folder was installed. Declining it strips the `%%curriculum-start%%`…`%%curriculum-end%%` passages from every payload page and unlinks inline expectation references. |
| `include_curriculum_coverage` | bool (default `true`) | setup | build | Whether the generated `Curriculum Coverage` map page is produced. |
| `curriculum_folder` | string or null | setup | build | What this course calls the folder holding one page per expectation. Declared by every payload and skeleton manifest. The build tries it FIRST and only then falls back to scanning for a top-level folder whose name contains `curriculum` — which is still the path a from-scratch course takes, but would never have found a folder called something else entirely. |
| `class_folder` | string or null | setup, and a rename in Course Settings | build, both apps | Which per-section folder holds this course's class pages. **Absent falls back to the GUESS** — the first per-section folder whose name contains `class`, else the first, else the literal `All Classes` — which is what every course made before 2026-09-01 relies on. The key exists because the guess quietly decided what a teacher was allowed to CALL the folder: somebody whose vocabulary is "Thread 2, Day 3" would sensibly call it `All Days`, and the guess would then point the next-class button and the coverage map at whatever folder happened to be first. **A rename writes this key even on a course that never had one**, because a rename is the one moment Plantoir witnesses the change. A stale name loses to the guess; a name differing only in case yields the folder LIST's spelling, because file paths are built from the answer. |
| `unit_word` | string | setup (new courses only) | build, both apps | What this course calls the first half of a class page's name — `Unit 2, Day 3`, or `Module 2, Day 3`. **Absent means `Unit`**, and so does an empty string; unlike `graded_folders`, the two are not distinguished, because there is no sensible reading of "the teacher cleared the word". Chosen when the course is made, and nowhere else: the ready-made pages are written in that word as they are poured, and renaming a course already in use is a separate and far more dangerous piece of work (see `TODO.md`). `Day` is deliberately fixed. |
| `excluded_items` | object with `shared` and/or `per_section` arrays | Course Settings | build | Folder and file names the teacher removed in Settings, kept out of previews and deploys. **Authoritative at build time**: preflight drops an excluded name it finds back in the folder lists rather than re-adding it, and never un-hides it. Keyed by scope because the same bare name can legitimately exist in both, and the two are found by different scans. An exclusion does NOT expire when the folder is deleted and re-created — discovery is name-based, so the build cannot tell "the folder I excluded" from "the new folder I just made". |
| `graded_folders` | array of strings | setup, and the Marks checklist in Course Settings | build, both apps | The folders whose work counts for marks, which is what makes an expectation "assessed" on the coverage map. **Absent is not empty.** Absent means the teacher has never been asked, so the historical rule applies (any folder whose name contains `task`) and an existing course keeps exactly the marks it had; `[]` means they were asked and cleared it. Seeding existing courses would not have been safe — the mathematics skeleton ships `Thinking Tasks`, which the old rule counted and a pool of `["Tasks"]` does not. **The first tick FREEZES the pool**: the moment a teacher touches the checklist, the key is written with everything the course was already counting, and the historical rule stops applying to it. Which is why what the checklist OFFERS matters as much as what it writes — the build matches a folder at any depth, so the apps offer the two folder lists plus every folder found inside the course, four levels deep. That rule, its skip list and what it deliberately leaves out are in [`contracts/shared-rules.json`](../contracts/shared-rules.json) → `gradedFolders.choices`, and both apps run its 14 cases. Two parts of it are easy to leave out and cost a teacher their marks: a folder named in `excluded_items` is NOT offered (it is still on disk, so the walk hands back a folder they just removed unless it is told not to), and each folder's children are sorted ORDINALLY and case-insensitively — see [`04-course-setup.md`](04-course-setup.md) for the measured table of which comparison, because the natural call on each platform is a different one. |
| `include_coverage_notes` | bool (default `true`) | setup | build | Whether that page carries its explanatory sections ("What counts", "Reading it honestly") or the map alone. |
| `use_lcs_terminology` | bool | setup | setup (starting folder and file names) | A school-specific mode: swaps the factory shared-folder and shared-file lists for one school's own words — "College Board Curriculum", "SIC Drop-In Sessions.md" and "Grove Time.md" in place of "Extra Help.md". Affects the names a new course starts with, nothing after that. |

### Publishing destination

| Key | Type | Written by | Read by | Meaning |
|---|---|---|---|---|
| `deploy_target` | string (default `netlify`) | app only (Course Settings → Publishing; the wizard preserves it but never writes it) | the app, which translates it into the launcher's `--target cloudflare` / `--to-folder <path>` flags — neither the launcher nor `deploy.py` reads the key | Where this course's sections publish: `netlify`, `cloudflare_pages`, or `local_folder`. Absent means `netlify`, so every existing course keeps working untouched. See [deployment](07-deployment.md). |
| `deploy_folder_path` | string | app (Publishing, folder mode) | the app, which passes it as `--to-folder <path>`; the launcher does the host-side copy from that flag | Only for `local_folder`: the folder sections are mirrored into, one `sectionN` subfolder each. Validated live in the app — a missing, unwritable, or file-not-folder path blocks Save rather than failing at publish time. |
| `additional_deploy_targets` | array of `{type, path}` objects | app (Publishing, "Also publish to, for redundancy") | the app — currently config/UI only; nothing yet triggers a second deploy from it (see below) | Extra destinations this course ALSO publishes to, beyond `deploy_target` (the primary), for redundancy against one host having a bad day. `type` uses the same spellings as `deploy_target`; `path` is only present for a `local_folder` entry. **Absent entirely** (never written as `[]`) for the overwhelming majority of courses that have not opted in, so an untouched course writes the exact same file it always has. At most one entry per known type, and never a type that is already the primary — `CourseConfiguration.deployTarget`'s own setter enforces this, dropping a type from this list the moment it becomes the primary. |

**Keys the wizard does not own survive a re-run.** `setup_course.py` builds
the config it owns, then copies through every key already in the saved file
that it did not write — the app's publishing choice, and anything a future
version adds. Without that, re-running the wizard on an existing course would
silently drop settings made in the app.

The Cloudflare **account ID** is deliberately *not* here: it identifies the
teacher rather than the course, so it lives in the app's own settings (and,
for direct launcher use, the OS credential store) and is entered once for
every course. The API tokens for Netlify and Cloudflare never touch this
file — or any file in the working folder.

## Files that travel alongside it

| Path (under `courses/`) | Purpose |
|---|---|
| `<CODE>/course_config.backup.json` | Automatic backup written before build-time discovery updates the config. |
| `<CODE>/.merged_output` | **A shortcut, not a folder** (since 2026-09-05): it points at `~/Library/Application Support/Plantoir/builds/<folder id>/<CODE>` on macOS, `%LOCALAPPDATA%\Plantoir\builds\<folder id>\<CODE>` on Windows. Built sites are derived and were moved out so that copying, zipping, backing up or syncing a course no longer carries them. Safe to delete; rebuilt on demand. |
| `<CODE>/.merged_output/section<N>/` | The section's built site as every script names it — `public/` and a copy of `course_config.json`. NOT the Quartz scaffold or `node_modules`: those live on the container's own fast storage and are never mirrored out. |
| `<CODE>/.netlify_sites/section<N>.json` | Netlify site marker (site id/URL) so re-deploys target the same site. |
| `<CODE>/.netlify_sites/section<N>.previous-<stamp>.json`<br>`<CODE>/.cloudflare_sites/section<N>.previous-<stamp>.json`<br>the built output's `section<N>/.netlify_site.previous-<stamp>.json` — **and where that is differs by platform**: `<CODE>/.merged_output/section<N>/` on macOS, `%LOCALAPPDATA%\Plantoir\builds\<folder id>\<CODE>\section<N>\` on Windows, because `merged_output_root()` returns `PLANTOIR_BUILD_ROOT/<CODE>` with no `.merged_output` level whenever the launchers set that variable, which on Windows is always | A marker set aside when a section was **rolled over onto a new website** — the assistant renames it rather than deleting it, because it holds the site id and admin address and is the only way back to last year's site. Inert: the scripts build exact marker paths and never scan the folder. See `contracts/file-formats.json` → `firstDeployMarkers.releasedWhenASectionRollsOver`. |
| `<CODE>/.cloudflare_sites/section<N>.json` | Cloudflare Pages marker (project name/id, subdomain, account) so re-publishing reuses the same project instead of creating a second one. |
| `<CODE>/Media/` | Shared binary assets; symlinked into every build, always hidden from the sidebar. |
| `<CODE>/.obsidian/` | Obsidian vault settings (seeded from `support/obsidian_defaults`). |
| `_backups/<CODE>/<timestamp>.zip` | Full course backups made by the setup wizard before re-runs. |
| `.internal/profile.json` | Teacher profile (last name for Netlify site naming). |
| `.gitignore` | Auto-maintained to exclude `.internal/` and `_backups/`. |

## Frontmatter conventions recognized in content

These are read from individual Markdown files rather than the config, but
belong in the same mental model:

| Frontmatter key | Where | Effect |
|---|---|---|
| `publishForSection<N>` / `createdSection<N>` | shared content | Per-section publication state; collapsed to `publish`/`created` when building section N ([mechanism](05-build-pipeline.md#frontmatter-processing)). |
| `publish` | any page | `false` keeps the page out of the built site. Anything else — including no key at all — publishes it. |
| `created` | any page | The displayed and sort date ([C1-3](06-quartz-customizations.md#c1-applied-on-first-build--full-rebuild)). |
| `draft` / `draftSection<N>` | any page | **Legacy, still read.** The same idea with the opposite polarity (`draft: true` hides). Used only when no `publish` key is present. Editing such a page's visibility rewrites the key to `publish` / `publishForSection<N>` on the same line and removes the old one (decided 2026-09-07; `contracts/file-formats.json` → `pageVisibility.writingRules`). The build reads both spellings either way. |
| `renderFolderPages: false` | a folder's `index.md` | Suppresses the auto-generated file listing on that folder page ([A3](06-quartz-customizations.md#a3-foldercontenttsx-folder-listing-page)). |
| `excludeBacklinks: true` | any page | Hides the "When did we do this?" backlinks panel on that page ([D1](06-quartz-customizations.md#d1-patched-backlinkstsx-supportbacklinkstsx)). |
| `transcludeTitleSize: h2` | a transcluded page | Heading level used for the page's title when embedded via `![[…]]` ([C1-10](06-quartz-customizations.md#c1-applied-on-first-build--full-rebuild)). |

## `course_config.json` has two writers, and they can erase each other

Fixed on the mac 2026-09-05; **half of it is shared Python both platforms inherit,
and half is each app's own.**

`preflight_update_course_config` reads the configuration, spends a while
scanning the course's folders, and writes what it computed. The APP writes the
same file inside that window — a folder rename does, and it writes at ONCE
rather than at Save, because the folder has really moved and a Cancel could not
undo it. Whoever wrote second won, and said nothing. The state that leaves is
the dead end in the next section: folders moved, configuration naming the old
name.

- **The Python half is shared.** Preflight now re-reads the file
  immediately before writing and, if it changed, redoes the whole discovery
  against the new contents — bounded at three tries, then it carries on with
  what is there rather than spinning. Redoing is safe because discovery is a
  pure function of (what is on disk, what the config says). It is not add-only
  — an `excluded_items` name is dropped from the copy lists (row 377) — but
  that is a function of the same two inputs, so the argument is unaffected.
  Corrected 2026-09-07; it said "and is add-only" until then.
- **The other writer is the app's.** Whatever writes `course_config.json` from the
  Windows app must do the same read-compare-write, or the race is only half
  closed. The mac's is `CourseConfiguration.recordOnDisk`; Windows' is
`CourseConfiguration.RecordOnDisk`. One
  deliberate asymmetry to copy: preflight backs off, the APP ends by writing
  anyway after three tries — a folder that has MOVED with a configuration that
  does not say so is the worse of the two states, so the app finishes by
  recording the truth rather than by giving up on it.

`scripts/test_config_write_race.py` forces the race with a scan that mutates the
file mid-flight, and it runs on both platforms — Windows reaches it through
`PythonToolchainTests`.

## A rename interrupted after the folders moved was a dead end

**This is an app-level problem, not a toolchain one** — it exists wherever a
rename moves folders before writing the configuration, which both apps do.

The state: the folders are under the new name, the configuration still says the
old one. The next build DISCOVERS the moved folder and appends it, so the list
holds BOTH names — and retrying the rename is then refused as a clash. If the
folder was the class folder it is unremovable as well, so there is no way out
of Settings at all; the teacher has to hand-edit `course_config.json`.

**The rule to copy is: RECORD the rename before moving.** The first version of
this on the mac decided from the disk alone — old folder gone, new one present
— and that was wrong in a way worth understanding, because it looks right. It
is also the state of a configuration entry whose folder was never created (or
was deleted in Obsidian) being renamed onto a genuine SECOND folder. Bypassing
there hands the real folder the phantom entry's attributes, `hidden` among
them, and takes its pages off the next publish with nobody told. The two cases
are indistinguishable on disk, so the disk cannot be the evidence.

So: write a small record before anything moves, delete it once the
configuration has been written, and relax the clash check only when BOTH the
record and the disk agree. The mac keeps it at
`courses/.internal/renames/<CODE>.json` — the `.internal` convention both apps
already share — and deliberately NOT as a `course_config.json` key, because the
failure being handled is that the configuration write did not happen. Carry the
TARGET in the record, not just a flag, so a teacher who opens the sheet and
types something else gets the ordinary refusal back; filling the field in with
it also makes finishing an interrupted rename one keypress.

Two more details that are not optional:

- **No section may still hold the old folder.** A per-section rename moves
  every section's copy, so a mixture means something other than an interrupted
  rename, and the ordinary refusal must stand.
- **De-duplicate the list when one finishes.** The starting state holds both
  names by definition, so a naive rename leaves the new name in twice — which
  on the mac renders two rows with one identity, and which no later rename can
  undo.

**One more thing a config writer must not do**, learned the same day:
when it loses the compare-and-swap race enough times to give up and write
anyway, it must recompute from the FRESHEST bytes. The mac's first version fell
through and wrote the computation derived from the read it had just proved
stale, clobbering the other writer's keys — the exact failure the loop exists
to stop.

## Config is the contract

`course_config.json` is shared between the app, the wizard, and the build.
The full key-by-key reference is above.
Keys the Windows settings UI must round-trip (per-section maps use
`{"sections": {"sectionN": value}}`):

- `course_code`, `course_name`, `locale`, `section_numbers`, `num_sections`
- `emojis.sections` — header emoji per section (system emoji panel: Win+.)
- `color_schemes` — flat map sectionN → scheme id (`support/colour_schemes.json`)
- `fonts.sections` — header/body/code display names (files in `support/fonts/`,
  name → file by stripping spaces; "Helvetica, Arial" means system default)
- `show_section_marker.sections` — the "S1" in the site header
- `show_grade_in_title.sections` — grade prefix on the landing title
  (legacy: a single course-wide bool; honour it). LITERAL behaviour: the
  switch alone decides; the UI shows an orange warning when the course
  name already contains the grade label, and the teacher resolves it.
- `custom_domains.sections` — the app swaps published-site links' host to
  this domain (path kept, https); entries are normalized (scheme and path
  stripped) on the way in
- `shared_folders`, `shared_files`, `per_section_folders`,
  `per_section_files`, `hidden`, `expandable`, `expandOnFolderClick`,
  `show_reading_time`, `footer_html`
- `deploy_target` ("netlify" default | "cloudflare_pages" | "local_folder") and
  `deploy_folder_path` (entries 101–102) — folder deploys pass
  `--to-folder <path>` to the launcher, which robocopy-mirrors each
  section into `<path>\sectionN`; completion is announced by a
  `PUBLISHED_FOLDER=` line the app turns into a Show-in-Explorer button.
  The Publishing choice appears in BOTH the settings form and the
  new-course wizard (share the control); an empty, missing, or
  unwritable folder blocks save/create with an inline message and is
  checked the moment a folder is chosen; folder-mode progress labels
  never mention Netlify; and the completion adds a note that the pages
  only render properly once uploaded to a web host
- `prepopulate_example_content`, `include_curriculum_pages` (entries
  92–93) — written by the new-course wizard, read by the shared Python
  wizard as its defaults; both forced false when no example content
  exists for the course code
- `use_lcs_terminology` (entry 94) — whether the factory structure
  defaults use LCS's own set-up; the two factory sets live as
  `DEFAULT_*` vs `LCS_*` constants in `scripts/setup_course.py` and the
  Windows equivalent of `WizardDefaults` must mirror them exactly
- `custom_short_name` — the ≤12-character label shown beside the header
  emoji instead of the course code, in club mode. Already implemented on
  Windows (`CourseConfiguration.cs`); listed here because this table is the
  contract and it was missing from it
- `include_curriculum_coverage` and `include_coverage_notes` (entries 125,
  130) — whether the generated `Curriculum Coverage` map page is produced, and
  whether it carries its explanatory sections or the map alone. Read by
  `build_site.py`, both defaulting true. **Implemented on Windows** (verified
  2026-08-22): both keys are read and written in `CourseConfiguration.cs` and
  surfaced as toggles in `NewCourseDialog.cs` and `CourseSettingsView.xaml.cs` —
  this note used to say "not yet implemented" and was stale.
- **Edit keys in place and preserve unknown keys** — the macOS app keeps
  the decoded JSON as a dictionary precisely so future toolchain keys
  survive a settings round-trip. The shared Python wizard does the same in
  the other direction: it copies through every key it does not own, which is
  what lets an app-written setting survive a wizard re-run.

---

[◀ Previous: Deployment](07-deployment.md) · [Back to index](README.md) · [Next: The macOS App ▶](09-mac-app.md)
