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
| `<CODE>/.merged_output/section<N>/` | Generated Quartz site for the section (scaffold + merged content + `public/`). Safe to delete; rebuilt on demand. |
| `<CODE>/.netlify_sites/section<N>.json` | Netlify site marker (site id/URL) so re-deploys target the same site. |
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
| `draft` / `draftSection<N>` | any page | **Legacy, still read.** The same idea with the opposite polarity (`draft: true` hides). Used only when no `publish` key is present; rewritten to `publish` the first time anything edits the page. |
| `renderFolderPages: false` | a folder's `index.md` | Suppresses the auto-generated file listing on that folder page ([A3](06-quartz-customizations.md#a3-foldercontenttsx-folder-listing-page)). |
| `excludeBacklinks: true` | any page | Hides the "When did we do this?" backlinks panel on that page ([D1](06-quartz-customizations.md#d1-patched-backlinkstsx-supportbacklinkstsx)). |
| `transcludeTitleSize: h2` | a transcluded page | Heading level used for the page's title when embedded via `![[…]]` ([C1-10](06-quartz-customizations.md#c1-applied-on-first-build--full-rebuild)). |

---

[◀ Previous: Deployment](07-deployment.md) · [Back to index](README.md) · [Next: The macOS App ▶](09-mac-app.md)
