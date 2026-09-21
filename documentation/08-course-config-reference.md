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
| `unit_word` | string | setup (new courses); Course Settings → Rename… (a course in use — mac; Windows: [#158](https://github.com/russellgordon/plantoir/issues/158)) | build, both apps | What this course calls the first half of a class page's name — `Unit 2, Day 3`, or `Module 2, Day 3`. **Absent means `Unit`**, and so does an empty string; unlike `graded_folders`, the two are not distinguished, because there is no sensible reading of "the teacher cleared the word". Chosen when the course is made, where the ready-made pages are written in that word as they are poured; changed later from Course Settings → Rename…, which renames every class page and follows the links before writing the key (see [09-mac-app.md](09-mac-app.md) → "Renaming a course's word for a unit"). `Day` is deliberately fixed. |
| `excluded_items` | object with `shared` and/or `per_section` arrays | Course Settings | build | Folder and file names the teacher removed in Settings, kept out of previews and deploys. **Authoritative at build time**: preflight drops an excluded name it finds back in the folder lists rather than re-adding it, and never un-hides it. Keyed by scope because the same bare name can legitimately exist in both, and the two are found by different scans. An exclusion does NOT expire when the folder is deleted and re-created — discovery is name-based, so the build cannot tell "the folder I excluded" from "the new folder I just made". |
| `graded_folders` | array of strings | setup, and the Marks checklist in Course Settings | build, both apps | The folders whose work counts for marks, which is what makes an expectation "assessed" on the coverage map. **Absent is not empty.** Absent means the teacher has never been asked, so the historical rule applies (any folder whose name contains `task`) and an existing course keeps exactly the marks it had; `[]` means they were asked and cleared it. Seeding existing courses would not have been safe — the mathematics skeleton ships `Thinking Tasks`, which the old rule counted and a pool of `["Tasks"]` does not. **The first tick FREEZES the pool**: the moment a teacher touches the checklist, the key is written with everything the course was already counting, and the historical rule stops applying to it. **A REMOVAL does not** — taking a folder out of the course in Settings is not an answer to the marks question, so a never-asked course is left with the key ABSENT rather than frozen to the historical answer minus that folder (which, on the ordinary course whose only marked folder is `Tasks`, would be `[]`: nothing counting for marks, permanently, from a gesture the teacher was told would do one narrow thing). The rule, its second exception and what it deliberately leaves unpinned are `gradedFolders.removingAFolder`, seven cases, run on both platforms (six since 2026-09-18, the seventh since 2026-09-19). The second exception — a name the checklist STILL OFFERS keeps its place — is asked CASE-INSENSITIVELY, the way the build asks it, since 2026-09-19 ([#172](https://github.com/russellgordon/plantoir/issues/172), raised from Windows): the checklist returns names as they are spelled on disk, so an exact test drops a pooled `Tasks` when `Portfolios/tasks` survives while the build goes on counting that folder. What remains unpinned is the DROP's own comparison, which the mac makes exactly and Windows with `OrdinalIgnoreCase`. Which is why what the checklist OFFERS matters as much as what it writes — the build matches a folder at any depth, so the apps offer the two folder lists plus every folder found inside the course, four levels deep. That rule, its skip list and what it deliberately leaves out are in [`contracts/shared-rules.json`](../contracts/shared-rules.json) → `gradedFolders.choices`, and both apps run its 14 cases. Two parts of it are easy to leave out and cost a teacher their marks: a folder named in `excluded_items` is NOT offered (it is still on disk, so the walk hands back a folder they just removed unless it is told not to), and each folder's children are sorted ORDINALLY and case-insensitively — see [`04-course-setup.md`](04-course-setup.md) for the measured table of which comparison, because the natural call on each platform is a different one. |
| `include_coverage_notes` | bool (default `true`) | setup | build | Whether that page carries its explanatory sections ("What counts", "Reading it honestly") or the map alone. |
| `kept_for_reference` | bool (default `false`) | app (Keep a Copy for Reference…, Import Courses for Reference…) | the app, `scripts/reference_course.py`, `deploy.sh`, `deploy.py` | `true` marks a REFERENCE COURSE: last year's course, or a course full of example content, kept in this year's sidebar to be read and never deployed. **Absent means false** — the only safe direction, since the reverse would make a live course silently undeployable. See "Reference courses" below. |
| `reference_school_year` | integer or null | app (Keep a Copy for Reference…, Import Courses for Reference…, Set School Year…) | the app (sidebar grouping, the MCP course listing) | Which school year a reference course was taught in, as the calendar year it STARTED in: `2025` means 2025–26. The label is derived, never stored. Absent, null, or anything that is not a whole number within the offered range reads as **Other**. |
| `use_lcs_terminology` | bool | setup | setup (starting folder and file names) | A school-specific mode: swaps the factory shared-folder and shared-file lists for one school's own words — "College Board Curriculum", "SIC Drop-In Sessions.md" and "Grove Time.md" in place of "Extra Help.md". Affects the names a new course starts with, nothing after that. |

### Publishing destination

| Key | Type | Written by | Read by | Meaning |
|---|---|---|---|---|
| `deploy_target` | string (default `netlify`) | app only (Course Settings → Publishing; the wizard preserves it but never writes it) | the app, which translates it into the launcher's `--target cloudflare` / `--to-folder <path>` flags — neither the launcher nor `deploy.py` reads the key | Where this course's sections publish: `netlify`, `cloudflare_pages`, or `local_folder`. Absent means `netlify`, so every existing course keeps working untouched. See [deployment](07-deployment.md). |
| `deploy_folder_path` | string | app (Publishing, folder mode) | the app, which passes it as `--to-folder <path>`; the launcher does the host-side copy from that flag | Only for `local_folder`: the folder sections are mirrored into, one `sectionN` subfolder each. Validated live in the app — a missing, unwritable, or file-not-folder path blocks Save rather than failing at publish time. |
| `scheduled_deploy_may_run_late_days` | integer (default `7`; only `1`, `3`, `7` or `14` mean themselves) | app (Course Settings → Deploying). **Not the wizard**, deliberately: a course that has never been deployed cannot be scheduled at all, so the question would have no consequence at the moment it is asked | the app, at the moment a scheduled deploy FIRES — read straight out of this file by a process with no `CourseConfiguration` loaded, so changing the setting after scheduling changes what a job already set will do. Nothing in `scripts/` reads it | How late a deploy set to happen on its own may still go ahead. The Mac may have been off or asleep at the chosen time; past this window the run stands down, deploys nothing and tells the teacher. **Absent means 7, and so does anything that is not one of the four offered values** — an older build's number, a value hand-edited in — because honouring a stored `0` would stand every scheduled deploy down. There is deliberately no "always". See [deployment](07-deployment.md) → "A scheduled deploy that outlived its course", and `contracts/shared-rules.json` → `scheduledDeployCancellation`. |
| `additional_deploy_targets` | array of `{type, path}` objects | app (Publishing, "Also publish to, for redundancy") | the app — currently config/UI only; nothing yet triggers a second deploy from it (see below) | Extra destinations this course ALSO publishes to, beyond `deploy_target` (the primary), for redundancy against one host having a bad day. `type` uses the same spellings as `deploy_target`; `path` is only present for a `local_folder` entry. **Absent entirely** (never written as `[]`) for the overwhelming majority of courses that have not opted in, so an untouched course writes the exact same file it always has. At most one entry per known type, and never a type that is already the primary — `CourseConfiguration.deployTarget`'s own setter enforces this, dropping a type from this list the moment it becomes the primary. |

### Reference courses: kept, never deployed

A reference course is last year's course — or a course full of example content
— sitting in this year's sidebar so the teacher can read it, and which Plantoir
never deploys. Two keys carry it, and the rules they obey are
[`contracts/shared-rules.json`](../contracts/shared-rules.json) →
`referenceCourses`, run as cases by both test suites.

**Read STRICTLY: a real JSON `true` and nothing else.** Not through the
ordinary boolean accessor, and the reason is measured: `JSONSerialization`
hands back an `NSNumber` for `1`, and `NSNumber` conditionally bridges to
`Bool` for 0 and 1 — so `as? Bool` read `"kept_for_reference": 1` as TRUE
while all three launchers read the same file as an ordinary course and
DEPLOYED it. Both directions of the fault at once: the app froze and locked a
course, with no way back to live, that the launchers then published.
`CFBooleanGetTypeID` is the only reading that tells a JSON boolean from a
number. Every other spelling somebody plainly MEANT — `"true"`, `1`, `True`, a
key written with backslash-u escapes — makes the launchers refuse with "cannot
tell", which publishes nothing and freezes nothing, while this app treats the
course as ordinary. The four readers and the twenty-six inputs they are
asserted to agree on are `shared-rules.json` → `referenceCourses.markerAgreement`.

**The marker is not the defence on its own, and that is the part worth
knowing.** Whatever makes a course a reference course also writes
`deploy_target: "local_folder"` with an empty `deploy_folder_path`, removes
`additional_deploy_targets` and `custom_domains`, and renames the
`.netlify_sites/` and `.cloudflare_sites/` markers aside. The reason is a
teacher with their working folder in iCloud Drive and an OLDER Plantoir on a
second Mac: that copy has never heard of `kept_for_reference` and would show a
working Deploy button. A folder deploy with no folder is refused by every
shipped version, in sentences it already has —
`MultiDestinationDeployRunner.refusalReason` and `ScheduledDeploy.problem`.

Measured on a real previous-generation working folder (four courses,
`/Users/…/Class Websites`, read-only): those configs carry **no
`deploy_target` at all**, and an absent `deploy_target` reads as `netlify`
([`CourseConfiguration.swift`](../mac-app/QuartzTeachers/Models/CourseConfiguration.swift),
`build_site.py:119`) — so a plain copy really would have arrived ready to
deploy over last year's live class site, whose id is sitting in
`.netlify_sites/`. That measurement is the whole justification for
neutralising rather than trusting the marker.

**The folder name and `course_code` are allowed to disagree here, and
nowhere else.** The folder is `ICS3U-2025`; `course_code` stays `ICS3U`. The
folder is IDENTITY — the launcher argument, the built-site folder, the preview
lease, the backup zip's name and the scheduled-deploy identifier are all built
from it, so two ICS3Us never collide — while `course_code` is what a teacher
reads, and what keeps the preview's site title, grade label and social card
right. `CourseConfiguration.setCourseCode`'s own warning about a disagreeing
pair still holds for every other course: its second half ("a deployed page
saying another") cannot happen here, because there is no deployed page.

*Rejected: a separate `display_code` key.* A third spelling of one fact, and
it would leave `build_site.py` writing `ICS3U-2025` into the site title of a
course whose preview a teacher is reading. *Rejected: a lower-case suffix
(`ICS3U-examples`).* `preview.sh:143` and `deploy.sh:376` put the course
argument through `tr '[:lower:]' '[:upper:]'`, so the folder would be looked
for as `ICS3U-EXAMPLES` and not found.

**The school year is stored as an integer and labelled by rule.** `2025` →
"2025–26", with an EN DASH (U+2013), so the dash never reaches the file format
and the two apps cannot render the same year two ways. A new school year
appears on **1 August** — inherited from Windows'
`Timetable.AcademicYearStarting`, which already ships that rule rather than
invented a second one here — and the list runs newest-first down to a floor of
2022–23, with the top end derived from today so it grows by itself. Anything
stored that is not a whole number within that range reads as "Other": a
hand-edited `2019`, a `2031` from a Mac with a wrong clock, a word, a `true`.
That errs toward a group the teacher can see and change, rather than a group
labelled "0000–01" built out of a value that coerced to zero.

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
| `_backups/<CODE>/<timestamp>.zip` | Full course backups made by the setup wizard before re-runs. It shares this folder with the app's own archives (`<CODE>_<timestamp>.zip`) and backups (`<CODE>_backup_<timestamp>.zip`), which are told apart from it and from each other by NAME alone — `contracts/course-management.json` → `zipNames`. |
| The `<timestamp>` in all three | `yyyy-MM-dd_HHmmss`, in the **Gregorian** calendar and local time, on every machine whatever calendar it is set to. Python's `strftime` is Gregorian always and Windows pins `CultureInfo.InvariantCulture`; the mac pins `en_US_POSIX` (`ArchiveStamp`) and, since 2026-09-10, also reads the spellings an earlier build wrote on a machine whose calendar was not Gregorian — see [09-mac-app.md](09-mac-app.md#what-an-archive-or-a-backup-is-called-and-the-calendar-it-is-stamped-in). |
| `.internal/profile.json` | Teacher profile (last name for Netlify site naming). |
| `.gitignore` | Auto-maintained to exclude `.internal/` and `_backups/`. |

## Frontmatter conventions recognized in content

These are read from individual Markdown files rather than the config, but
belong in the same mental model:

| Frontmatter key | Where | Effect |
|---|---|---|
| `publishForSection<N>` / `createdSection<N>` | shared content | Per-section publication state; collapsed to `publish`/`created` when building section N ([mechanism](05-build-pipeline.md#frontmatter-processing)). |
| `publish` | any page | `false` keeps the page out of the built site. Anything else — including no key at all — publishes it. **"`false`" is not the same as "looks false"**: see [Whether students see a page](#whether-students-see-a-page) below, which is the measured table and the one both apps are written against. |
| `created` | any page | The displayed and sort date ([C1-3](06-quartz-customizations.md#c1-applied-on-first-build--full-rebuild)). |
| `draft` / `draftSection<N>` | any page | **Legacy, still read.** The same idea with the opposite polarity (`draft: true` hides). Used only when no `publish` key is present. Editing such a page's visibility rewrites the key to `publish` / `publishForSection<N>` on the same line and removes the old one (decided 2026-09-07; `contracts/file-formats.json` → `pageVisibility.writingRules`). The build reads both spellings either way. |
| `renderFolderPages: false` | a folder's `index.md` | Suppresses the auto-generated file listing on that folder page ([A3](06-quartz-customizations.md#a3-foldercontenttsx-folder-listing-page)). |
| `excludeBacklinks: true` | any page | Hides the "When did we do this?" backlinks panel on that page ([D1](06-quartz-customizations.md#d1-patched-backlinkstsx-supportbacklinkstsx)). |
| `transcludeTitleSize: h2` | a transcluded page | Heading level used for the page's title when embedded via `![[…]]` ([C1-10](06-quartz-customizations.md#c1-applied-on-first-build--full-rebuild)). |

<a name="whether-students-see-a-page"></a>

## Whether students see a page

The single most consequential field in the product, and the one where reading
the line is not the same as knowing the answer. Settled 2026-09-18 (GitHub
issue #140, `decision`, Russell): **an app's answer must be the BUILT SITE's
answer.** The governing rule underneath that is narrower and matters more —
*Plantoir must never call a page hidden while students can read it.*

### Why a hand-rolled reader gets this wrong

**The build never shows Quartz what the teacher typed.** Every page copied into
a section's content goes through `build_site.py` → `process_frontmatter`, which
loads it with `frontmatter.load` (python-frontmatter → PyYAML, **YAML 1.1**),
resolves this section's per-section keys onto a plain `publish:`, and writes it
back with `frontmatter.dumps`. Quartz then parses THAT with `gray-matter` using
`js-yaml` on its **`JSON_SCHEMA`** (`quartz/plugins/transformers/frontmatter.ts`
in v4.5.0 — the schema matters: it resolves only lowercase `true`/`false`, so
everything PyYAML did not already turn into a boolean arrives as a string), and
`patches/publish.ts` drops the page only when the value it gets is **the
boolean false or the exact string `"false"`**.

Three things fall out of that round trip, each of them a page a line reader
gets wrong:

* **YAML 1.1's spellings are real booleans.** `publish: no` and `publish: off`
  HIDE the page; `publish: yes` and `publish: on` publish it. Nine spellings
  each, and exactly nine: all lower, Initial, ALL CAPS.
* **Comments are gone, and so is anything that is not a boolean.** An inline
  `# comment` is stripped by the round trip, so `publish: true # covered
  Tuesday` publishes. Anything PyYAML cannot resolve becomes a STRING, and a
  string that is not `"false"` is published — `maybe`, `y`, `n`, `0`, `oN`.
* **Case matters, in opposite directions on either side of the round trip.**
  `publish: FALSE` hides (PyYAML resolves it and writes lowercase `false`),
  while `publish: "False"` does NOT (the quotes keep it a string, and
  `publish.ts` compares strings exactly). Quoting cuts both ways: `publish:
  'no'` is published where the unquoted spelling hides.

### The rule, in two predicates

The build consults four keys **in one order on every page it copies**,
regardless of which folder the page came from:

```
publishForSection<N>  >  publish  >  draftSection<N>  >  draft
```

A key naming another section is deleted unread. When the same key appears
twice, the LAST one wins — that is what PyYAML keeps.

**PUBLISH family** (`publish`, `publishForSection<N>`). Hidden if and only if
the value is one of the nine spellings of false, *or* is the quoted string
`false` spelled exactly that way. Everything else — including null, an empty
value, `~`, and every other string — publishes.

**DRAFT family** (`draft`, `draftSection<N>`), the legacy spelling with the
opposite polarity. The build asks `build_site._as_bool`: a real boolean counts
as itself, and anything else is turned into text, trimmed, lowercased and
compared with `"true"`. So an unquoted `yes` HIDES the page and a quoted
`"yes"` does not, while `TrUe` hides it either way. That asymmetry is why there
are two predicates and not one.

### Three answers inside, two outside

Each app's reader — `PageVisibilityReader` on the mac, `PageVisibilityReader`
in `windows-app/Plantoir.Core/Models/` (which `PageFrontmatter.IsDraft`,
`StoredDraft` and `Visibility` are collapses of), and `page_visibility.py` in
the shared Python — answers **three ways**: `visible`, `hidden`, and
`cannotTell` for a handful of forms it will not guess at (a value on the line
BELOW the key — over a blank line as happily as not, and **whatever is on the
key's own line**; see "A writer must take a value's CONTINUATION lines with the
key" below for why the second half of that sentence is the dangerous one — a
tag such as
`!!str false`, a block scalar, an anchor or alias, a flow collection, an escape
inside double quotes, an indented key, a value that starts with a character
YAML reserves (`%`, `@`, a backtick, `- `) or carries its own `key: value`, and
frontmatter the build cannot parse at all — tab indentation or an unclosed
fence, which stop the whole build so there is no site verdict to mirror).

Two shapes are NOT `cannotTell` and are worth naming, because both were read
the dangerous way round before they were measured:

* **`publish:false`, with no space after the colon, is not a key at all.** YAML
  needs a space, a tab or the end of the line after the colon to make a mapping
  — so that line is one plain scalar, the page reaches Quartz with no keys, and
  it is PUBLISHED. (With another key beside it the same line stops the build.)
  Reading everything after the first colon called this page hidden.
* **YAML's whitespace is a space and a tab, and nothing else.** The
  non-breaking space Option-Space types on a Mac is not whitespace to YAML, so
  `publish: false<NBSP>` is the STRING "false\u{00A0}" and the page is
  published. Swift's `trimmingCharacters(in: .whitespaces)` and Python's
  `str.strip()` both strip it; both readers trim space and tab by hand instead.

  **One exception, measured and accepted, and the trigger is not the obvious
  one.** python-frontmatter's `YAMLHandler.export` ends with
  `yaml.dump(...).strip()`, and `yaml.dump` SORTS the keys — so the trailing
  non-breaking space survives only while something else sorts after `publish`.
  `publish: false<NBSP>` on its own comes out as `publish: false` and the page
  is HIDDEN, where these readers say visible; `title: x` beside it (or `zzz:`,
  or anything sorting after `publish`) leaves the space in place and the page
  is published, which is what they say. Not "when it is last in the block" —
  when it sorts last in the RE-DUMPED block. It is the mild direction, it is
  the only place the readers knowingly differ from the site, and the alone-form
  is pinned in `scripts/check_visibility_against_the_site.py` so the day the
  library stops doing this, the difference fails rather than quietly becoming
  something else.

  It is deliberately NOT a shared reading case. An invisible character in a
  JSON file that two platforms must match character for character is a trap
  laid for whoever next edits the list.

What happens to `cannotTell` depends on who asked, and this is the part to get
right:

* **Anything REPORTING to a teacher collapses it to VISIBLE.** The section
  graph (`AssistSectionGraph`; `AssistWorkspace.Plan` on Windows), the
  scheduled deploy's "classes students cannot see yet"
  (`ScheduledDeploy.unpublishedClasses`, `ScheduledDeploy.UnpublishedClassesIn`
  — so a page whose flag cannot be read is NOT listed there as one students
  cannot see, on either platform), the index pointer, the dangling-link check,
  the "N linked pages stay visible" sweep (`AssistWorkspace.cs:692`), and the
  re-date planner. (No VIEW reads a page's flag — a sentence here said "the
  sidebar" until 2026-09-18 and there is no such reader; the sidebar lists
  courses.) Never to hidden: listing a live page among the ones still to
  publish costs a second look, while calling a page hidden when students are
  already reading it is the failure that reports success.
* **Anything DECIDING WHETHER TO WRITE needs certainty, not a match.** A page
  whose flag cannot be read is not "already the way you asked" — it is a page
  to write. `AssistSectionPage.visibilityIsCertain` carries that on the mac and
  `PlannedPage.VisibilityIsCertain` on Windows, and every place that skips a
  page because it already matches requires it: the publish plan's "already
  right" list (both the NAMED pages and the LINKED ones on Windows), the
  nothing-to-do sentence, the whole-unit count of what would move, and the date
  a linked page inherits from the class that brought it. Without it, "publish
  this page" on such a page answered *It's already been published* and wrote
  nothing while the build was holding the page back — reporting success about
  the exact failure this rule exists to remove. **The honest way to find these
  is to grep for every place a collapsed "visible" decides to SKIP a write**,
  rather than to trust a count: the number differs between the platforms
  because the plan layers are not the same shape.
* **Anything WRITING to a teacher's file never collapses it at all.**
  `AssistPageVisibility.setting` on the mac and `PageFrontmatter.SetDraft` on
  Windows: the "already right, change nothing" shortcut fires only on a
  CONFIDENT reading that already matches; on `cannotTell` it writes the flag
  out in full, in whichever direction was asked for. A writer that believed the
  reporting collapse would decline to publish a page on the strength of a
  guess, and tell the teacher it had published it.

  **The gate reads all four keys; the write goes to one.** Which key is written
  is decided by where the page lives, and that is the only thing a page's
  folder decides — so `SetDraft` takes a section NUMBER as well as a key, and
  it is required rather than optional. An optional one would make a second
  rule: omitted, the gate would judge the page on that key alone, while the
  build reads `publishForSection<N>` FIRST on every page, so a section-local
  page carrying a stray per-section key could have its write skipped in the
  dangerous direction. (The mac's `setting` has the same asymmetry, taking
  `forSection` and `isSectionLocal` separately.)

The forms that read `cannotTell` are pinned in each platform's OWN tests
(`PageVisibilityReadingTests` on the mac, `Plantoir.Tests/PageVisibilityReadingTests.cs`
on Windows), not in the shared contract. A shared case says what the SITE does;
writing `expectVisible: true` for a form the site HIDES would oblige the other
platform to be wrong in the same direction rather than merely allow it.

**With one deliberate exception, added 2026-09-19 with issue #176.** The test
is not "can the reader read it" but "does the REPORTING answer match the site",
and for two continuation forms it does: `publish: false` with an indented
`false` under it, with or without a blank line between them, is PUBLISHED by
the site — the fold is the string `"false false"`, which is not `"false"` —
and both readers answer `cannotTell`, which reporting collapses to visible.
Those two are in `readingCases`, and they earn the place because the reader
that got them wrong got them wrong CONFIDENTLY, which is what let a writer's
already-right gate turn "hide this page" into a no-op. The polarity siblings
(`no`, `off`, `FALSE`, `true`, `maybe` with a value below) are equally honest
and add nothing the two do not, so they stay in each platform's own tests.

### What a WRITER does with an odd value

Four rules, all deliberate. The first two are about the VALUE; the last two are
about finding the line, and are the ones a writer gets wrong by being written
separately from the reader:

* **A page that already SAYS what was asked is left alone**, however oddly it
  says it. `publish: maybe` publishes the page, so "publish this page" is
  answered "It's already been published." and the file is not touched. Tidying
  the value to `true` would be an edit nobody asked for, in a file Obsidian very
  likely has open, and it would throw away whatever the word meant to the
  teacher. Asked to HIDE the same page, it changes and the odd value goes —
  the only way to say the opposite of what it says is to say it plainly.
* **A value being carried to another section is copied character for
  character.** `SectionAdder` (both apps') and
  `setup_course.per_section_frontmatter` copy a
  `publish`-family value exactly, comment and quotes and all: whatever the
  build makes of the original it makes of the copy, so no reader standing
  between the two can invert it. The exception is a value that runs onto the
  NEXT line (a block scalar, or a key with the value indented beneath it),
  which cannot be copied to another key's line at all; that, and a DRAFT value
  the reader cannot read, are written as HELD BACK — and the continuation
  lines are taken WITH the key, because an indented scalar left behind lands
  under whatever key follows and stops the build. A key with nothing after it
  is the one exception: that is a null, which PUBLISHES the page, so the copy
  keeps it a null rather than deciding for the teacher. A page wrongly held back is
  one a teacher notices and fixes; a page wrongly published is one nobody
  notices at all.

  **The carry asks the one reader, so correcting the reader moved it** (issue
  #176, 2026-09-19). `SectionAdder.publishValue` / `PublishValue` now reads a
  legacy `draftSection1: false` or `: no` with a line under it as `cannot tell`
  rather than off the key's own line, so both are carried HELD BACK where the
  mac used to carry them as published; Windows had already moved. Measured,
  **neither app reproduces the site here and neither is trying to.** The site
  PUBLISHES `draftSection1: false`, `: no`, `: true` and `: yes` each with an
  indented `x` under them — the fold is `"false x"`, `"no x"` and so on, which
  `_as_bool` cannot make a boolean of, so `process_frontmatter` writes
  `publish: true` — while `draftSection1:` over an indented `true` is the
  boolean and the page is HIDDEN. Both apps err HELD BACK on all five; the mac
  in four rows now, as Windows does. Uniformly held back is the documented
  preference and it is what `setup_course.per_section_frontmatter` writes.
* **A writer takes the LAST line naming a key, because the reader does and the
  build does.** PyYAML keeps the last of two identical keys. A writer that set
  the first left `publish: true` above a `publish: false` the build still
  obeys, and a carry that read the first took the value PyYAML throws away.
* **A writer finds the line with the READER's own matcher, never a prefix
  test.** `publish : false` and `"publish": false` are the same key to YAML and
  were invisible to `hasPrefix("publish:")` (and to C#'s `StartsWith(key)` plus
  a colon test) — so publishing such a page INSERTED a second `publish: true`
  above it, PyYAML kept the last, and the page stayed hidden while the teacher
  was told it had been published. `PageVisibilityReader.valuePart` is that
  matcher on the mac, `PageVisibilityReader.ValuePart` on Windows, and
  `page_visibility`'s key pattern in the Python. **Leaving the reader ahead of
  the writer is its own bug class**, and it is the one to check first in any
  new writer.

  The mac rebuilds the line in the plain spelling; Windows rewrites the value
  after the colon and keeps whatever the teacher wrote before it, including an
  inline `# comment`. Both end with the page really saying what was asked,
  which is what the contract pins — `pageVisibility.writingCases` stays inside
  the subset where the two agree and says so.

* **A writer must find the BLOCK the way the reader finds it, too.**
  python-frontmatter's fence is `^-{3,}\s*$` — three dashes OR MORE — and it
  tolerates blank lines before the opening one. A writer that insisted on
  exactly `---` at line 0 decided a page fenced with `----` had no frontmatter
  and PREPENDED a block of its own, leaving the teacher's real frontmatter
  behind it as body text, printed to their students. One fence finder serves
  the reader and the VISIBILITY writers on both platforms. (`...` is not a
  closing fence: python-frontmatter does not accept one, and Windows'
  `Block.Parse` did until 2026-09-19, which read a block as ending early.)

  **Two other finders are still hand-rolled, and knowing which is which
  matters more than unifying them.** `SectionAdder`'s (`frontmatterLines` /
  `FrontmatterLines`) is strict on BOTH platforms — the very first line
  exactly `---` — so the section carry agrees with itself across the two apps;
  that is parity, and it is recorded here rather than filed. `CourseRestorer`'s
  is strict on Windows and, since the mac's `PageFrontmatter.block` was
  loosened for the reason above, lenient on the mac — so a restore reaches
  different pages on the two platforms, which is
  [issue #177](https://github.com/russellgordon/plantoir/issues/177) and needs
  a decision. The trap to avoid is reading "one fence finder" and making the
  MAC strict, which puts the second-block bug straight back.

* **A writer must take a value's CONTINUATION lines with the key.**
  Replacing a key's line alone orphans the indented line below it onto the new
  value, so `publish: >-` with `  false` under it, asked to be HIDDEN, becomes
  the multi-line plain scalar `"false false"` — a string that is not
  `"false"`, so the page is PUBLISHED while the teacher is told it was hidden.
  When the orphan is a MAPPING it is a `ScannerError` and the whole build
  stops instead. Both measured, python-frontmatter 1.3.0 / PyYAML 6.0.3.

  The rule is `setup_course.per_section_frontmatter`'s, which has done this
  since 2026-09-18, and it is the same stepping the reader's
  `firstNonBlankLine` does: walk forward from the key, STEP OVER blank lines
  and `# note`s **at any indent** rather than stopping at them, stop at the
  first line that is not indented, and take everything up to the last indented
  line that was not a comment. So a complete value followed by an indented note
  keeps the note — nothing is taken, because no value line was found below it —
  while a note with a real value under it goes with the value, which is what
  the reader sees through it anyway. Do not try to PARSE the block scalar;
  only find where the value ends.

  **"At any indent" is the half that drifts, and it has drifted twice.**
  Windows' first `ContinuationLines` stepped over a comment only when it was
  indented, and `setup_course.per_section_frontmatter` did the same until
  2026-09-19 — so a note at COLUMN 0 between a key and its value ended the
  walk. Measured for the splitter: `publish:` / `# note` / `  false` is HIDDEN
  before the split and **VISIBLE in section 1** after it (section 2 gets the
  value and is hidden), and with a single section it happens to survive, which
  is why nothing noticed. On the mac the two halves now share one predicate,
  `PageVisibilityReader.isSteppedOverLookingForAValue`, used by
  `firstNonBlankLine` and by `continuationLineIndices`, precisely so a reader
  and a writer cannot step differently again.

  **A value below a key is a value below a key however complete the key's own
  line looks — and the READER has to be the one that says so.** Measured,
  `publish: false` with an indented `false` under it is the string
  `"false false"` and the page is PUBLISHED; so are `no`, `off` and `FALSE`
  (`'no false'`, `'off false'`, `'FALSE false'`). A reader that consults the
  next line only when the key's line is EMPTY calls all of those `hidden`, and
  calls it CONFIDENTLY — which is the part that bites, because the writer's
  "already right, change nothing" gate then returns before the writer or its
  continuation sweep ever run. Asking to hide such a page was a NO-OP: the
  file untouched, the teacher told it was already hidden, students still
  reading it. **The sweep cannot save a page the writer is never asked to
  write.**

  So the reader answers `cannot tell` whenever the first line that could be
  a value is indented, whatever is on the key's own line. Reporting then says
  visible — which is what the site does — and the writer writes the flag out
  in full and sweeps. Measured after that write: `False` → HIDDEN. It changes
  none of the 54 shared `readingCases` that existed before it.

  **"Whatever is on the key's own line" is closed; "the first line that could
  be a value" has one pre-existing exception, and it is the one that reaches
  this same fault.** A line of INDENTED DASHES — `publish: false` over
  `  ---` — never reaches the rule above, because `isFence` trims leading
  whitespace before testing for dashes and so takes `  ---` for the CLOSING
  fence. python-frontmatter's own boundary is `^-{3,}\s*$`, which allows no
  leading whitespace at all, so the build reads that line as part of the value
  and the site PUBLISHES the page (`"false ---"`), while the reader says
  `hidden` — confidently — and "hide this page" is a no-op, exactly the shape
  this section exists to close. `publish: no` over `  ---` behaves the same;
  `publish: >-` and `publish:` over `  ---` are written but the `  ---` is
  left behind, because `continuationLineIndices` is bounded by
  `block.closeIndex`, which is the fake fence. All measured; `origin/dev` and
  Windows produce byte-identical output on every row, so this is pre-existing
  and shared rather than anything this piece introduced. It is NOT fixed here
  on purpose: `isFence` is the fence finder that the reader, both visibility
  writers and `PageFrontmatter` all share, so changing it is its own piece
  rather than a ride-along.
  [Issue #188](https://github.com/russellgordon/plantoir/issues/188).

  **Windows fixed all of this — everything above except that one indented-dashes
  shape — on 2026-09-19** — `PageVisibilityReader
  .ReadScalar` for the reading, `PageFrontmatter.ContinuationLines` for the
  sweep, used by both of `SetDraft`'s branches; tests in
  `PageVisibilityReadingTests` →
  `AValuesContinuationLinesGoWithIt` (14 rows),
  `AValueBelowACompleteLookingOneIsStillAValueBelow` (6) and the two beside
  them. **The mac followed the same day**, issue
  [#176](https://github.com/russellgordon/plantoir/issues/176), implementing
  Windows' design unchanged:
  `PageVisibilityReader.reading(ofValue:followedBy:)` for the reading,
  `PageVisibilityReader.continuationLineIndices` for the sweep, called from
  both branches of `AssistPageVisibility.setting`, with the stepping shared
  through `isSteppedOverLookingForAValue`. Tests:
  `PageVisibilityReadingTests.testAValuesContinuationLinesGoWithIt` (16 rows —
  Windows' 14 plus two of the mac's own),
  `testAValueBelowACompleteLookingOneIsStillAValueBelow` (6),
  `testABlankLineDoesNotEndAValueEither`, the two guards and the CRLF test.
  The two apps agree at the three-way level again.

  Two continuations are not indented and are swept anyway, both measured, both
  a stopped build if left: a column-0 `# note` between a key and its value
  (the reader steps over a comment at any indent, so the sweeper must too),
  and a column-0 block SEQUENCE directly under a key with an empty value
  (`publish:` over `- a` is the list `['a']`). A sequence under a key that
  HAS a value is left alone — that page is a `ParserError` before anything is
  written, so there is nothing to rescue and sweeping a teacher's list on that
  guess would be the larger mistake. `keyValueWasEmpty` is therefore asked
  BEFORE the key's line is rewritten: the rewrite always puts a value there,
  so asking afterwards always answers false and the sequence is never swept.

  **What was REJECTED, with the reasons, so they are not proposed again.**

  * *Gating the sweep on `isCompleteOnItsOwnLine`* — the obvious shape, and
    it is wrong: it would leave `publish: false` / `  false` published after a
    hide, which is the dangerous row.
  * *Fixing the sweep and leaving the reader* — the fix the first Windows
    round made, and it buys nothing on the dangerous path, because `setting`'s
    "already right" gate returns BEFORE the writer runs. The generalisable
    lesson: when a reader and a writer are fixed in the same piece, check
    which of the two the early return lives in.
  * *Tidying `build_site._first_non_blank` to step over comments too* — it
    steps over blank lines but not comments, unlike every other stepping in
    this family. Measured consequence: `publish: false` / `# note` /
    `  false` is a page the build cannot parse, and `_is_draft` calls it
    hidden. **Left alone deliberately.** It is not unreachable —
    `process_frontmatter` CATCHES the YAML error, prints `⚠️ Could not read
    frontmatter from …` and leaves the file byte-identical
    (`build_site.py:1976-1979`), so such a page reaches the merged tree with
    its comments intact and `_is_draft` reads raw text. But every page that
    can reach it is a page that stops the Quartz build anyway, so the gap has
    no teacher behind it; and `scripts/build_site.py` is inside
    `.githooks/pre-commit`'s publishing closure, which engages `RELEASING.md`'s
    rule that a release changing the publishing path needs a full
    `verify-deploy` run. Twenty minutes and three credentials for a two-line
    tidy in a function production never reaches. If it is ever changed, change
    it with something else in that file.
  * *Putting the sweeper in `PageFrontmatter`, where Windows keeps theirs* —
    on the mac `PageFrontmatter` is the date and title writer and
    `PageVisibilityReader` is "the one place that knows the rule". Finding
    where a value ENDS is reading, and it has to step identically to
    `firstNonBlankLine` two functions above it.

  **`verify-deploy.sh` is NOT owed for this change, and the argument is a
  measurement rather than a file list.** `scripts/page_visibility.py` is
  imported by `scripts/build_site.py`, which IS in the publishing closure, and
  the hook matches literal paths — so "nothing in the closure changed" is a
  fact about a list, not a reason. What was measured, over every shipped page
  in `support/example_content` and `support/skeletons`: **9,553 pages; 387
  hidden before the change and 387 after; 0 `publish` lines followed by an
  indented line; 0 coverage-map verdicts moved.** And over the same trees for
  the splitter change: **11,891 pages, 0 whose split output moves.** Nothing
  the build does changes.

  **Three of this app's own write paths still orphan a continuation**, and
  they are named here rather than left to be discovered:

  * `SectionAdder.extendFrontmatter` inserts the new section's
    `createdSection<N>` / `publishForSection<N>` pair after the last
    per-section KEY LINE, so on a page whose value continues below it the pair
    lands between the key and its value — measured, a page HIDDEN in section 1
    becomes VISIBLE in both sections.
    [Issue #181](https://github.com/russellgordon/plantoir/issues/181).
  * `CourseRestorer.settingPerSectionKeys` swaps this section's key line for
    the backup's without either side's continuation lines — measured, a live
    `publishForSection1:` / `  a: 1` whose backup had no such key is left as
    `  a: 1` alone and the build stops.
    [Issue #182](https://github.com/russellgordon/plantoir/issues/182).
  * **`setting`'s own INSERT branch** — the third branch of the very function
    the sweep was added to, and the surprising one. It CREATES an orphan
    rather than leaving one: a block whose first line is indented gets the new
    key inserted above it at `openIndex + 1`, and that indented line becomes
    the new key's value. Measured, `---` / `  a: 1` / `---` is VISIBLE (no
    flag at all) and after a hide it STOPS the build — `bad indentation of a
    mapping entry (3:4)`. There is nothing to SWEEP there; the fix is where to
    insert, which is a decision about a teacher's hand-edited YAML rather than
    a mechanical one.
    [Issue #186](https://github.com/russellgordon/plantoir/issues/186).

  All three are pre-existing, all three are shared with Windows (which inserts
  at `open + 1` too), and none is worsened by this piece. The first two are not
  reached by the fixed reader or writer at all — neither calls `setting`. The
  rule above is the app's rule; these three are where it is not yet kept.

* **A `#` inside quotes is not a comment**, wherever a writer looks for one.
  Windows' `ReplaceValue` split the line at the first `#` on it, so hiding a
  `publish: "false # why"` page left an unbalanced quote — frontmatter the
  build cannot parse at all, written by an ordinary request. It uses the
  reader's quote-aware scan now.

### What this replaced, and what was rejected

Until 2026-09-18 the mac accepted only `true`/`yes` after stripping quotes and
lowercasing, and BRANCHED its reading on where the page lived — so a
course-level page carrying a plain `publish: false` was reported visible while
the build hid it. Windows read it differently again until 2026-09-19
(`Block.BoolValue` returned null for anything but `true`/`false`, and `IsDraft`
fell through to `?? false`), so `publish: no` read VISIBLE there while the site
HID it — the same class of bug pointing the other way. It also fell THROUGH an
unreadable key to the next one, which the build never does, and it branched on
where the page lived in the other direction: `StoredDraft` took a KEY, so a
course-level page's plain `publish: false` was never looked at. It takes a
section now. Three real inversions were fixed along the way:
`SectionAdder.publishValue` (mac), `SectionAdder.PublishValue` (Windows) and
`per_section_frontmatter` (Python) each compared a legacy draft value with the
literal string `"true"`, so `draftSection1: yes` was carried into a new section
as PUBLISHED while the build went on hiding the original.

Rejected, with reasons:

* **Option 1 — strip an inline comment and accept `on`/`off`, and leave the
  rest.** The smallest change that fixes every case a teacher plausibly types,
  and it was rejected because it leaves genuine junk (`publish: maybe`) reading
  as HIDDEN, which is the dangerous direction. Half a rule is a rule nobody can
  reason about.
* **Option 3 as a teacher-facing state — say "Plantoir cannot tell" in the
  sidebar and leave the page out of a publish plan.** The only option that
  surfaces the teacher's mistake rather than quietly picking a side, and the
  right long-term answer. Deferred past v1.2.0: it is new UI, in every surface
  that lists pages, on both platforms. The three-way answer now exists INSIDE
  the reader, so adopting it later is a presentation change rather than a
  re-derivation. **What it would ADD is a teacher being told**; what it is no
  longer needed for is correctness. The first version of this work left a
  residue — asked to publish a page whose value reads `cannotTell`, the
  assistant answered that it was already published and wrote nothing, because
  the plan layer took the reporting collapse at face value. That was found in
  review, and it is CLOSED: `visibilityIsCertain` makes such a page always a
  change, so the flag is written out in full and the page really is published.
  What a teacher still does not get is the SENTENCE — nothing says "the value
  on this page was one Plantoir could not read", it simply writes a plain one.
  That is what option 3 would add.
* **Erring VISIBLE everywhere, writers included.** It makes the reader one line
  shorter and silently publishes pages: a writer that trusts the collapse
  declines the edit and reports success.
* **Carrying a legacy `draftSection<N>` value across as a literal `true`.**
  This is what produced the inversion above. Inverting the ANSWER rather than
  the text is the fix; copying the text is only safe for the key that is not
  being inverted.
* **A Python test that SKIPS when python-frontmatter is missing.** The Windows
  machine has no python-frontmatter, and `PythonToolchainTests` judges by exit
  code — a loud skip there is green having run nothing. So the rule lives in
  `scripts/page_visibility.py`, stdlib only, and `scripts/test_page_visibility.py`
  runs everywhere; the round trip that genuinely needs the image is
  `scripts/check_visibility_against_the_site.py`, run by `verify.sh`.

### What was measured, and how to re-measure it

Everything above was run through the real image on 2026-09-18 —
**python-frontmatter 1.3.0, PyYAML 6.0.3**, then `gray-matter` with `js-yaml`
on `JSON_SCHEMA` out of `/opt/quartz/node_modules`, then `patches/publish.ts`'s
own expression. Not reasoned: this issue was once opened on a claim about
`publish: no` that was read off two plausible-looking files and never run, and
the claim was backwards.

`contracts/file-formats.json` → `pageVisibility.readingCases` carries **56** of
those measurements as the list both app suites run (54 until 2026-09-19, when
issue #176 added the two continuation forms the site publishes), and
`scripts/check_visibility_against_the_site.py` re-runs every one of them down
the real chain on each `verify.sh` — along with **25** more it carries
itself, the forms each reader REFUSES to answer about. Those cannot be shared
cases (a shared case states what the SITE does, and both readers report these
as visible whatever it does) but the refusals are only justified while the
measurement holds, so the measurement is pinned where it can fail. Since
2026-09-19 it also carries `CONTINUATIONS_A_WRITER_MUST_SWEEP` — **9** rows,
three pages each: the page before the write, the page it becomes if the value's
lines are LEFT, and the page it becomes when they go with the key. That list
pins the ARGUMENT for the sweep, not the sweep itself: nothing in `verify.sh`
runs Swift or C#, so deleting `continuationLineIndices` leaves every row green
and only the app suites go red. Its own comment says so. That check also asserts that Quartz still
parses with `JSON_SCHEMA` and that `publish.ts` still compares against `false`
and `"false"` — because if either moves, the whole table moves with it and
every suite would otherwise stay green.

**The Dockerfile pins python-frontmatter, PyYAML and Pillow** for the same
reason: `publish: no` hides a page ONLY because PyYAML reads YAML 1.1, and
PyYAML 7 is expected to move to YAML 1.2, where `no` is the string "no" and
that page would be published. An unpinned upgrade would flip real pages in a
teacher's course with nothing failing anywhere. The pins are the versions the
image already had, read off `pip freeze` rather than chosen, so they changed
nothing about what is installed — but they DO change the build-context hash, so
every working folder rebuilds its image once after updating.

**There are TWO fetch paths, and the second one is the one a Windows teacher's
site is really built by.** `windows-app/Vendor/fetch-runtime.ps1` builds the
native Windows runtime; nothing on that machine builds the Docker image at all.
It did an unpinned `pip install python-frontmatter Pillow` until 2026-09-19 —
PyYAML arriving as a dependency, unnamed. It carries the same three pins now,
and each pin in `contracts/toolchain.json` names both places it must appear
(`dockerfileContains`, `windowsRuntimeContains`), with a test on each side
holding its own file against them, so the two cannot drift apart again. Neither
test RUNS a fetch — the Windows one is ~600 MB — so both assert the recipe.

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
