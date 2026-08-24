# Today's plan — GUI affordances for the folders that carry meaning

**Written 2026-08-24 for a FRESH session.** The chat that produced it had been
compacted several times; this file exists so the next agent needs none of that
history. Branch: `issue/special-folders-hardening`, off `dev`. It has been
adversarially reviewed twice; corrections are folded in.

Read in this order, then come back here:

1. [`CLAUDE.md`](CLAUDE.md) — the rules that override default behaviour.
   Rules 2–5 (write-ups, contract, trail) and rule 6 (never merge to `dev`
   without Russell saying so, in that session, about that piece) all bind here.
2. **`~/.claude/CLAUDE.md`** — Russell's MACHINE-WIDE Swift style rules, which
   are NOT in this repository (that is deliberate; see project rule 8). Piece 3
   is substantial new Swift. Without these you will write
   `items.filter { $0 != name }` — the exact idiom `removeItem` was hand-written
   to avoid. No `map`/`filter`/`reduce`, no `ObservableObject`, `// MARK: -`
   sections, no `$0`.
3. [`PURPOSE.md`](PURPOSE.md) — what this branch is for and what it has already
   shipped.
4. `GUI-IMPROVEMENTS.md` rows **354–373** — this branch's history. Those are row
   NUMBERS; they live at **file lines 746–765**. Read as history, not
   specification.
5. [`NEEDTOKNOW.md`](NEEDTOKNOW.md) — handover notes, a manual test guide, and
   one known-open defect.

---

## The one-line problem

Plantoir hands a teacher scissors and never says what they are cutting.
`StringListEditorView.removeItem`
(`mac-app/QuartzTeachers/Views/CourseSettings/StringListEditorView.swift:128`)
removes a folder or file name with no warning and no notion that any name means
anything — the SAME component in the New Course Wizard
(`Views/Wizard/NewCourseWizardView.swift:765-768`) and in Course Settings
(`Views/CourseSettings/CourseSettingsView.swift:81-97`). It already REFUSES
`Media` on **add** (`StringListEditorView.swift:96-110`), so it has the concept;
it simply never applies it on **remove**.

Everything below follows from that.

---

## How this was found, and the evidence

Russell built a trial course on 2026-08-24: working folder
`~/Desktop/plantoir-trial`, course **ICS3U**, sections 1 and 4, **declined the
example content**, then removed `Tasks`, `Curriculum` and `All Classes` from
inside the wizard. He previewed. Plantoir said nothing.

His `courses/ICS3U/course_config.json` is the primary evidence and is still on
disk — read it rather than trusting this quote:

```
use_skeleton: False
include_curriculum_pages: False
include_curriculum_coverage: False      <-- the coverage map is OFF
graded_folders: []                      <-- explicitly empty
curriculum_folder: None
shared_folders: [Concepts, Examples, Exercises, Projects, Discussions, Setup, Style, Tutorials]
per_section_folders: []                 <-- EMPTY. No class folder at all.
```

The mac wizard seeded the shape from the computer-science skeleton
(`support/skeletons/computer-science/manifest.json`, whose `shared_folders` are
`[Concepts, Examples, Exercises, Projects, Discussions, Tasks, Setup, Style,
Tutorials, Curriculum]`). Comparing the two lists: he removed `Tasks` and
`Curriculum`, and emptied `per_section_folders` by removing `All Classes`. The
rest is the skeleton's own shape, unedited.

**Why the build-time dialog stayed silent, correctly.** Removing the curriculum
folder in the wizard switches the coverage map off
(`scripts/setup_course.py:2243-2245`), so `coverage_wanted` is false and both
coverage checks in `scripts/site_health.py:121-141` are skipped. Nothing was
broken, so nothing complained. **The health checks are not at fault.** The
missing warning belongs at the moment of removal — which is Piece 3, not
Piece 1. Read the doctrine at the top of `site_health.py` before touching it:
warnings a teacher cannot act on are the failure mode it was written to avoid.

---

## The policy that binds all three pieces — settle it before writing code

`graded_folders` has THREE states and the difference is load-bearing:

| State | Meaning | Build behaviour |
|---|---|---|
| key absent | never asked | historical rule applies: any folder whose name contains *task* |
| `["Tasks", …]` | asked and answered | exactly these count |
| `[]` | asked, answered "nothing" | **nothing counts as assessed** |

`CourseConfiguration.swift:376-404` states it ("Nil is not empty, and that
distinction is the whole migration"); `build_site.py:3687-3726` implements it.

Pieces 1 and 3 are NOT independent, because both change what `[]` means. Fix the
policy once, up front, and apply it to both: **when may code write `[]`, and
when must it omit the key instead?** Doing Piece 1's write policy before Piece
3's meaning is settled risks `setup_course.py` writing the exact `[]` that
Piece 3 exists to prevent.

---

## Verified facts — read, not assumed

Cite these; do not re-derive them. Do re-check any you intend to change.

### The marks pool
* `graded_folders_for` (`setup_course.py:40-62`) is **wizard-only** (sole call
  site `:2285`). A manifest's declared list wins; otherwise it infers from
  folder names containing `task`.
* All **50** skeleton manifests and all **38** payload manifests declare
  `graded_folders`. `computer-science` declares `["Tasks"]`.
* `_is_graded_path` (`build_site.py:3764`) decides per page whether an
  expectation gets its border (`:3952`).

### The two curriculum switches
* `include_curriculum_pages` and `include_curriculum_coverage` are **separate
  keys**. The first is **install-time only** — written at `setup_course.py:2303`,
  read at `:2037/2057/2096`, and **never read by `build_site.py`** (confirmed by
  grep).
* The wizard has BOTH toggles (`NewCourseWizardView.swift:629-641`); Course
  Settings has only coverage (`CourseSettingsView.swift:49-53`).
* Conversely Course Settings has the marks picker
  (`CourseSettingsView.swift:107-111`) and **the wizard has none**.

### Removal in Course Settings does not stick
* `preflight_update_course_config` (`build_site.py:3311`, called `:4276`) scans
  disk before every build, **re-appends** anything missing from the lists
  (`:3334-3342`), and **un-hides it** (`:3346-3351`, printing "Un-hid newly
  discovered folder"). The un-hide fires only for folders it considers *newly
  discovered* — and a folder removed from `shared_folders` in Settings
  re-qualifies as new, which is exactly why the bug bites.
* So removing a deliberately HIDDEN folder in Settings today does not exclude
  it — it makes it appear in students' sidebars on the next build. A live bug,
  independent of this branch.
* Settings `save()` writes JSON only; `setup_course.py` is **not** re-run
  (`CourseSettingsView.swift:236-254`). All wizard-only logic is inert there.
* `deploy.py:146-153` shells `build_site.py --build-only`, the same entry point
  that calls preflight — so preview and deploy run the same preflight. (That
  does NOT settle where Piece 2's `index.md` note ends up; see Piece 2.)

### `hidden` is NOT exclusion
* `hidden` feeds only Quartz's Explorer omit list
  (`build_site.py:4604` → `update_quartz_layout`). Pages are still built,
  deployed, reachable by URL and searchable. Plantoir force-adds `Media`
  (`:4593-4594`) and the coverage page (`:4601-4602`) itself.
* Three states must be distinguishable in the UI: **published / hidden /
  excluded**. Neither existing list substitutes for the new one.

### "The curriculum folder" is not one thing
* `_find_curriculum_folder` (`build_site.py:3569-3598`) tries
  `config["curriculum_folder"]` first, then scans `sorted(content_root.iterdir())`
  for the first folder whose name contains `curriculum` AND holds a page
  matching an expectation code.
* `WizardDefaults.lcsSharedFolders`
  (`mac-app/QuartzTeachers/Catalogs/WizardDefaults.swift:20-24`) contains
  **two**: `Ontario Curriculum` and `College Board Curriculum`. Sorted, College
  Board wins. A blanket "the curriculum folder is protected" rule protects the
  wrong one.

### Contract mechanics — do not repeat a mistake this file used to contain
* `Plantoir --write-contracts` writes exactly **three** files:
  `assist-wording.json`, `assist-cases.json` (`AssistContract.swift:264-297`)
  and `app-rules.json` (`AppRulesContract.swift:122-146`).
* **`shared-rules.json` is entirely hand-authored — the generator never opens
  it.** There is no "preserve list" to register a new key in. Add `specialNames`
  freely.
* `site_health.py` reads its wording from `contracts/shared-rules.json` at RUN
  time (`site_health.py:35, 61-63`), inside the container.

---

## The two ways a teacher silently loses every mark

Both end in the same harm; a fix must cover both.

* **Path A — no payload, no skeleton** (Russell's actual case). The pool is
  inferred by the *task* substring. Remove `Tasks` and the wizard writes
  `graded_folders: []`, which reads as "asked and answered: nothing".
* **Path B — skeleton accepted.** The manifest declares `["Tasks"]` and that is
  written down **regardless of whether the teacher kept the folder**. The pool
  names a folder that does not exist, still reads as configured, and the
  historical fallback is permanently off.

---

## Decisions Russell made (2026-08-24) — do not relitigate

1. **Removal in Course Settings becomes a real exclusion**, recorded in the
   config and respected by the build. **Plus** a note written into that folder's
   `index.md` explaining why the folder is still there and that it will be
   ignored for previews and deploys from now on.
2. **A forbidden removal shows an ⓘ in place of the minus.** Clicking it
   explains what depends on the folder and **names the switch to turn off
   first**. Not a greyed-out button with no reason; not a dialog that offers to
   flip the switch for you.
3. **The graded-folder floor is enforced in the GUI *and* by a build-time
   check.**
4. **It must not be possible to remove the Curriculum folder while either
   curriculum switch is on.**

An adversarial review argued to cut item 1, the wizard half of 2, and the GUI
half of 3. Russell reviewed those arguments and **kept all three**, with three
amendments he agreed to:

* **The `index.md` note is written by Python at BUILD time, not by Swift at
  Save time.** Windows gets it free (rule 3), and it happens where exclusion is
  applied. Cost: the teacher sees it after the next preview, not instantly. The
  merge must **strip sentinel blocks from any `index.md` it copies**, so the
  note can never reach students even if the folder is later re-included.
* **Wizard blocking is computed from the EFFECTIVE switch value, never the raw
  `@State`.** This dissolves a real deadlock: `includesCurriculumPages` and
  `includesCurriculumCoverage` are `@State … = true` and never reset
  (`NewCourseWizardView.swift:91-92`), while the coverage toggle is
  `.disabled(!prepopulatesExampleContent || !includesCurriculumPages)` (`:640`).
  With pre-populating off the toggle is disabled *while still true* — an ⓘ
  would name a switch the teacher cannot click. Use
  `CourseConfiguration.curriculumCoverageEnabled(...)` (defined
  `CourseConfiguration.swift:665`, called `NewCourseWizardView.swift:1115`); an
  unreachable switch is effectively off and blocks nothing.
* **The graded floor materialises the inferred pool on first edit.** Blocking
  the last untick while the pool is nil would otherwise write the very `[]`
  being prevented (`CourseSettingsView.swift:342-370`).

---

## ASK RUSSELL BEFORE STARTING — these are product decisions, not agent calls

The repo's own rules make these his. Ask in one message, then work
autonomously.

**For Piece 1**
1. When reconciliation leaves the marks pool empty while the coverage map is
   ON, should `setup_course.py` write `[]`, omit the key (restoring the
   historical *task* rule), or refuse to proceed?
2. Does reconciliation apply only to a manifest-DECLARED pool, or also to one a
   teacher has edited?

**For Piece 2**
3. Is exclusion course-wide or per-section? One flat list of bare names is
   matched against both `discover_shared_items` (course root) and
   `discover_section_items` (section root) — `build_site.py:3244-3284` — so a
   per-section name excluded is excluded for EVERY section. Retrofitting shape
   onto a shipped key is the expensive version.
4. Does an exclusion expire when the folder disappears from disk and is later
   re-created in Obsidian? Discovery is name-based and top-level only, so there
   is no path identity distinguishing "the folder I excluded" from "the new
   folder I just made" — and Course Settings promises the opposite in so many
   words (`CourseSettingsView.swift:99`: "you can also simply create new folders
   in Obsidian — they're added to your site automatically").
5. Should the note CREATE an `index.md` in a folder that has none? That is a
   visible structural change to his vault, made by a build.

**For Piece 3**
6. The project's stated direction is wording authored in Swift and GENERATED
   into the contract ("if you are about to type one of the assistant's sentences
   into a document or a test, don't — name it instead"). Putting `specialNames`
   sentences directly in hand-authored `shared-rules.json` inverts that. Is the
   new precedent acceptable, or should the sentences live in Swift with the
   contract carrying only the rules?

---

## The work, in three pieces, in this order

Keep committing on `issue/special-folders-hardening`. **Do not merge to `dev`**
without Russell saying so in that session.

### Piece 1 — the marks pool (first)

Smallest, and the actual harm Russell hit.

* Reconcile `graded_folders_for` (`setup_course.py:40`) against the folder lists
  the teacher **actually ends with**: drop declared names no longer present.
  Covers path B.
* Apply the nil-vs-`[]` policy settled above, per Russell's answer to question 1.
* New `site_health.py` check: coverage map ON **and** the pool naming nothing
  that exists → warn that **nothing currently counts for marks**. Phrase it as
  the FEATURE producing nothing. Gate it so it cannot nag a course with no map —
  the existing checks are mutually gated at `site_health.py:121-141` for exactly
  this reason.
* Contract: add the check to `contracts/shared-rules.json` → `siteHealth.checks`
  so both suites run it.

**Acceptance, and note what it deliberately does NOT claim:**
- A course with the coverage map ON whose pool matches nothing on disk emits a
  `PLANTOIR_HEALTH:` line naming the new check, and the app raises its dialog.
- A course with the map OFF is told nothing. **Russell's ICS3U has the map off,
  so Piece 1 correctly stays silent on it.** His case is Piece 3's job — do not
  "fix" Piece 1 until it fires on his course, or you will build the nagging the
  doctrine forbids.
- `./verify.sh` green.

**"Python-only" is a trap.** Piece 1 still needs the contract edit, an app
rebuild to carry it, a `GUI-IMPROVEMENTS.md` row, and probably test fixtures.
It is not "no Xcode".

### Piece 2 — `excluded_items` and the preflight fix (alone)

Changes a file format both apps write, so it lands by itself.

* New config key, shaped per Russell's answer to question 3. Document in
  `contracts/file-formats.json`.
* `preflight_update_course_config` must not re-add and must not un-hide an
  excluded name — and must **print a line saying it is skipping it and why**.
* The `index.md` note: sentinel-delimited, idempotent, never touching the
  teacher's own text, removed on re-inclusion, and **stripped by the merge from
  any copied `index.md`**. Confirm by inspecting a built `public/` that the
  sentinel text is absent — preview and deploy both run preflight, but the note
  is written into the MERGED tree, so prove it does not ship rather than
  assuming it.
* Trail events for exclusion and re-inclusion, named in BOTH
  `ActivityTrail.Event` and `contracts/shared-rules.json` →
  `activityTrail.mustRecord` (rule 5). **Rule 5 also forbids recording what is
  written on a page, and any credential — see `LogRedactor`, whose rules are
  contract cases and which redacts on the way IN.** A folder NAME is fine; page
  content is not.
* Watch the write race: `graded_folder_names`' own comment
  (`build_site.py:3712-3718`) records why the build avoids writing back — an app
  holding a pre-build copy of the config overwrites it on the next Save.
  Preflight already writes (`:3362-3371`), and this key makes that write carry
  teacher intent.

**Acceptance:** remove a folder in Course Settings; preview; assert the folder's
pages are absent from `public/`, the name is still absent from the config after
the rebuild, nothing was un-hidden, the skip line appears in the console, and
the sentinel note is present in the vault and absent from `public/`.

### Piece 3 — the protection model (last)

Needs Piece 2's exclusion state to talk about.

* `StringListEditorView` gains a protection lookup supplied by the caller.
  Three row states: **blocked** (ⓘ, explains, names the switch) /
  **consequential** (minus, but confirm first) / **ordinary** (today's
  behaviour).
* `MembershipToggleListView`
  (`mac-app/QuartzTeachers/Views/CourseSettings/MembershipToggleListView.swift`)
  gains the same idea so un-ticking the **last** graded folder while the map is
  on is blocked, with materialise-on-first-edit.
* The wizard gains the marks control. **It applies only to the SKELETON and
  FROM-SCRATCH paths**: for a pre-populated course the manifest decides
  structure whole (`setup_course.py:2113-2121`) and the GUI hides the list
  editors (`NewCourseWizardView.swift:739-743`).
* Protect the folder `_find_curriculum_folder` would ACTUALLY resolve, not "any
  folder mentioning curriculum" — put that resolution rule in the contract so
  both apps compute the same name. Handle a protected name that is in no list
  (already removed, or created in Obsidian) without crashing or blocking an
  unrelated row.

**Acceptance:** in a fresh working folder, create ICS3U declining the example
content, and attempt to remove `Tasks`, `Curriculum` and `All Classes`. Each
either explains its cost and asks for confirmation, or shows the ⓘ naming the
switch. Assert the resulting `course_config.json` cannot reach
`graded_folders: []` with the map on, nor `per_section_folders: []`. Drive the
real app for this — no unit test covers it, and driving the app has already
caught bugs every test passed.

---

## How to run things

```bash
# Toolchain (launchers, scripts/, Dockerfile, patches, contracts/)
script -q /dev/null ./verify.sh      # needs a TTY; exits EARLY on a missing
                                     # courses/EXC2O fixture — an exit 0 from a
                                     # compound command's tail is NOT a pass

# macOS app — tests, then the LAST build must be a plain build
cd mac-app
xcodegen generate
xcodebuild -project Plantoir.xcodeproj -scheme Plantoir -configuration Debug \
  test -only-testing:QuartzTeachersTests
xcodebuild -project Plantoir.xcodeproj -scheme Plantoir -configuration Debug build
```

`dotnet test` is **not runnable on this Mac** — there is no dotnet here. Windows
parity is discharged by writing the contract cases and the handoff, not by
running the C# suite.

Test bed: use a THROWAWAY working folder. `~/Desktop/plantoir-trial` holds
Russell's evidence course — read it, but make a new folder for destructive
testing. `NEEDTOKNOW.md` has a step-by-step manual guide.

**"Adversarial review after each item"** means: commit the item, then launch a
subagent whose brief is to attack that specific diff and its claims with
file:line evidence, fold the findings back in, and commit again. Not a
self-review, and not batched at the end. That process has caught false claims in
this branch repeatedly — several `GUI-IMPROVEMENTS.md` rows exist only to
correct earlier rows.

## Traps that will cost you an afternoon

* **A toolchain edit does not reach a working folder until the app is rebuilt.**
  Edit → rebuild the app → relaunch → next preview refreshes `.toolchain/`.
  **`contracts/` is a bundled folder reference too**, and `site_health.py` reads
  its wording from it at runtime — so a contract edit that is not rebuilt into
  the bundle produces a check with a missing sentence, which looks exactly like
  a Python bug. Verify the right file for what you changed:
  ```bash
  grep -c <something-from-your-edit> \
    ~/Library/Developer/Xcode/DerivedData/Plantoir-*/Build/Products/Debug/Plantoir.app/Contents/Resources/scripts/site_health.py
  grep -c <something-from-your-edit> \
    ~/Library/Developer/Xcode/DerivedData/Plantoir-*/Build/Products/Debug/Plantoir.app/Contents/Resources/contracts/shared-rules.json
  ```
  `0` means the resource copy was skipped and you are testing the old toolchain.
* **Xcode may not copy your edit at all.** These are folder references; editing
  a file inside one does not change the directory mtime. Always `xcodegen
  generate` before `xcodebuild`.
* **Do not check the bundle with `strings`/`nm` on `Contents/MacOS/Plantoir`** —
  that is a ~59 KB stub. Check `Plantoir.debug.dylib`.
* **Rebuild before reporting done, and leave the app QUIT.** Russell launches
  from the Dock. `xcodebuild test` leaves a test-host bundle behind and
  terminates any running copy, so a plain `build` must be the LAST build.
* **The mac suite runs test classes serially on purpose.** Classes that reset
  process-wide statics corrupt each other in parallel.
* **`xcodebuild` can exit 65 with ZERO failed cases.** Grep `^Failing tests:`
  before believing a failure. There is a pre-existing intermittent crash in
  `CourseRenameInterfaceTests` that also reproduces on `origin/dev` (measured: 1
  in 4 runs) — do not attribute it to your change without measuring both.
* **Never `colima stop`** unless `docker ps -q` is empty; it is shared with his
  other projects.

## Obligations before any piece is "done"

Per `CLAUDE.md` rules 2–5, as you go — not batched at the end:

* A row in `GUI-IMPROVEMENTS.md` whose **"Notes for Windows port" column says
  something usable**. An empty cell is never acceptable.
* A section in `WINDOWS-HANDOFF.md` for anything architectural — the exclusion
  key, the preflight change, the protection model, the `index.md` note.
* Contract cases so the Windows suite runs the identical data.
* Trail events named in both places, with redaction respected.
* Commit as you go and `git push -u origin issue/special-folders-hardening` in
  the same session.

## Known open, deliberately not in scope

* **A section with no `index.md` cannot be published at all.**
  `_sync_public_to_host` (`build_site.py:3131-3138`) only copies back when
  `public/index.html` exists, and with no `index.md` Quartz emits none — so the
  build succeeds, the sync is silently skipped, and `deploy.sh` then says "Built
  site not found — build first". Shared Python, so Windows has it too. Written
  up in `WINDOWS-HANDOFF.md` with two one-line fixes available.
* **Renaming the `Unit` keyword** — deferred, in `TODO.md`.
