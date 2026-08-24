# Today's plan — GUI affordances for the folders that carry meaning

**Written 2026-08-24 for a FRESH session.** The chat that produced it had been
compacted several times; this file exists so the next agent needs none of that
history. Branch: `issue/special-folders-hardening`, off `dev`. It has been
adversarially reviewed twice; corrections are folded in.

Read in this order, then come back here:

1. [`CLAUDE.md`](CLAUDE.md) — the rules that override default behaviour.
   Rules 2–5 (write-ups, contract, trail) and rule 6 (never merge to `dev`
   without Russell saying so, in that session, about that piece) all bind here.
2. **Russell's MACHINE-WIDE Swift style rules**, which are NOT in this
   repository (that is deliberate; see project rule 8) — `~/.gemini/GEMINI.md`
   if you are Antigravity/Gemini, `~/.claude/CLAUDE.md` if you are Claude Code.
   The two are kept as identical copies. Piece 3 is substantial new Swift.
   Without these you will write `items.filter { $0 != name }` — the exact idiom
   `removeItem` was hand-written to avoid. No `map`/`filter`/`reduce`, no
   `ObservableObject`, `// MARK: -` sections, no `$0`. Antigravity also loads
   `.agents/rules/*.md` unconditionally; those are a GENERATED copy of
   `CLAUDE.md` and must never be hand-edited.
3. [`PURPOSE.md`](PURPOSE.md) — what this branch is for and what it has already
   shipped.
4. `GUI-IMPROVEMENTS.md` rows **354–373** — this branch's history. Those are row
   NUMBERS; they live at **file lines 746–765**. Read as history, not
   specification.
5. [`NEEDTOKNOW.md`](NEEDTOKNOW.md) — handover notes, a manual test guide, and
   one known-open defect.

---

## Who does what — read this before you start working

This piece is being built by THREE different agents in rotation, deliberately,
because Russell's Anthropic quota is limited. Know which one you are.

| Agent | Does |
|---|---|
| **Fable** | Revised THIS FILE once (2026-08-24), folding in Russell's answers to six product questions. Done; no code. |
| **Gemini, in Antigravity** | Implements one piece at a time, then adversarially reviews its OWN work before committing. |
| **Claude (Opus, medium effort)** | Reviews Gemini's committed work for that piece, in a fresh chat. Fixes what it finds, or says plainly that it is sound. |

Then the rotation repeats for the next piece. One piece per rotation, never two.

**Gemini commits its own work to the issue branch, and pushes it.** Do not hold
a piece uncommitted waiting for review. This branch's own history is already
built this way — "Item 1: …" followed by "Item 1 review: …" — and it is the
right shape here for three reasons: an unpushed change is invisible to the next
agent and to every other machine (learned the hard way on 2026-08-21); a
reviewer reading a commit can see exactly what changed and when; and work on an
issue branch costs nobody anything if it turns out to be wrong. The review lands
as a FOLLOW-UP commit, not as an amendment. **Merging to `dev` is still
Russell's call alone, every time.**

**Commit trailers differ by agent, and getting this wrong credits a stranger.**
An Antigravity or Gemini session must end its commit messages with
`Co-Authored-By: Antigravity <noreply@google.com>` — never
`antigravity@google.com`, which belongs to an unrelated person's GitHub account
and has already been credited on seven commits here by mistake. Claude sessions
use the trailer their harness supplies. See `CLAUDE.md` rule 6.

A `commit-msg` hook now rewrites the bad address automatically, but **hooks are
not installed by cloning**. Run `git config core.hooksPath .githooks` once per
clone, and check `git config --get core.hooksPath` before assuming you are
covered.

**What the reviewing Claude session should check**, in rough priority order.
It runs at MEDIUM effort — enough to reason about behaviour, not just to check
that things compile — so spend it on the first item before the others:

1. Every factual claim in the commit message and in any new comment or
   document — verify against the code, with file:line. Claims in this branch
   have been wrong before, repeatedly.
2. The piece's own acceptance criteria, run rather than assumed: the tests
   green, `./verify.sh` where the toolchain changed, and the bundle actually
   carrying the edit (see the traps).
3. The obligations — `GUI-IMPROVEMENTS.md` row with a real "Notes for Windows
   port" cell, `WINDOWS-HANDOFF.md` where architectural, contract cases, trail
   events with redaction respected.
4. Whether the piece quietly widened or narrowed its scope.

**Piece 2 is the one to slow down on.** It changes a file format both apps
write, and a shape decision retrofitted later is expensive. Expect that review
to cost more than Pieces 1 and 3 together, and do not shorten it because the
diff looks small — both adversarial reviews that shaped this file found
BLOCKING errors, and both were reasoning errors rather than anything a
mechanical pass would catch.

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

**Settled (Russell, 2026-08-24): code may write `[]` when the teacher has been
asked; only a course that has never been asked omits the key.** Concretely:

* `setup_course.py` **writes `[]`** when reconciliation (Piece 1) leaves the
  pool empty — even with the coverage map ON. Removing the folder in the wizard
  IS being asked and answering "nothing", so `[]` is the honest state. Omitting
  the key would be the wrong lie: the table reads absent as *never asked*, and
  on a new course absent means the *task*-substring rule, which matches nothing
  either once the folder is gone — the same silent zero marks, now disguised as
  an untouched legacy course. `graded_folders_for`'s own docstring
  (`scripts/setup_course.py:50-53`) says the point of writing the key at
  creation is that a new course has no marks to lose and can be explicit.
  Refusing was rejected because `setup_course.py` aborting mid-install over a
  choice the wizard already accepted puts the refusal in the wrong place — the
  GUI is where a refusal belongs, and that is Piece 3.
* What makes `[]` SAFE to write is that it is exactly the input Piece 1's new
  health check is defined on (map ON, pool names nothing on disk), so the
  teacher is told rather than left silent. Piece 3 then stops the GUI reaching
  it in the first place. The two pieces are therefore not in tension: Piece 1
  writes the honest state and warns; Piece 3 prevents it.
* **Reconciliation in `setup_course.py` applies to BOTH a manifest-declared
  pool and an inferred one**, because at wizard time there is no difference:
  `graded_folders_for` (`setup_course.py:55-62`) returns either the declared
  list or one inferred from the final folder lists, and the fix is simply to
  filter whatever it returns against the lists the course actually ends with.
  A pool a teacher edits LATER in Course Settings never passes through
  `setup_course.py` at all (`save()` writes JSON only,
  `CourseSettingsView.swift:236-254`), so that case belongs to Piece 3's
  `MembershipToggleListView`, not to Piece 1.

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

## The work, in three pieces, in this order

Keep committing on `issue/special-folders-hardening`. **Do not merge to `dev`**
without Russell saying so in that session.

### Piece 1 — the marks pool (first)

Smallest, and the actual harm Russell hit.

* Reconcile `graded_folders_for` (`setup_course.py:40`) against the folder lists
  the teacher **actually ends with**: drop declared names no longer present.
  Covers path B.
* Apply the nil-vs-`[]` policy settled above: an empty result is written as
  `[]`, never omitted — and reconciliation covers declared and inferred pools
  alike.
* New `site_health.py` check: coverage map ON **and** the pool naming nothing
  that exists → warn that **nothing currently counts for marks**. Phrase it as
  the FEATURE producing nothing. Gate it so it cannot nag a course with no map —
  the existing checks are mutually gated at `site_health.py:121-141` for exactly
  this reason.
* Contract: add the check to `contracts/shared-rules.json` → `siteHealth.checks`
  so both suites run it.
  Its sentence is hand-authored THERE, not in Swift — see the wording decision
  under Piece 3, which this check is the first instance of.

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

* New config key `excluded_items`, **an object keyed by scope, mirroring the
  config's existing split**:
  ```json
  "excluded_items": {"shared": ["Tasks"], "per_section": ["All Classes"]}
  ```
  Decided 2026-08-24. Names in the two scopes are matched by different scans
  (`discover_shared_items` vs `discover_section_items`,
  `build_site.py:3244-3284`), and the same bare name can legitimately exist in
  both, so a flat list would conflate them. Exclusion is **course-wide within a
  scope**: a per-section name excluded is excluded for every section. A
  per-section-NUMBER exclusion was rejected for now because nothing can set
  it — Course Settings edits one course-wide `per_section_folders` list — but
  the object shape is additive, so a `"sections": {"4": [...]}` key can be
  added later without retrofitting; a flat array could not. Two top-level keys
  (`excluded_shared_items` / `excluded_section_items`) were rejected as
  scattering one concept across keys both apps must remember to write
  together. ABSENT (not `{}`) for a course that has excluded nothing, like
  `graded_folders` and `additional_deploy_targets`. Document in
  `contracts/file-formats.json`.
* **An exclusion does NOT expire when the folder is deleted and later
  re-created in Obsidian.** It persists until the teacher re-includes the name
  in Course Settings. Discovery is name-based, so the build cannot tell "the
  folder I excluded" from "the new folder I just made", and guessing "new"
  would re-publish something the teacher deliberately excluded — the same harm
  as today's un-hide bug. The build-time `index.md` note makes the persistence
  self-explaining: a re-created folder gets the note on its next preview.
  Amend the promise at `CourseSettingsView.swift:99` ("they're added to your
  site automatically") so it excepts names removed here; that sentence is now
  false without the exception.
* `preflight_update_course_config` must not re-add and must not un-hide an
  excluded name — and must **print a line saying it is skipping it and why**.
* The `index.md` note: sentinel-delimited, idempotent, never touching the
  teacher's own text, removed on re-inclusion, and **stripped by the merge from
  any copied `index.md`**. **It is written only into an `index.md` that already
  exists — the build never CREATES one.** A folder with no `index.md` gets the
  console skip line only. A build adding files to a teacher's vault is a
  precedent this project has avoided, and the note is a courtesy, not the
  mechanism of exclusion (the config key is). Confirm by inspecting a built `public/` that the
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
the sentinel note is present in the vault (where an `index.md` already existed) and absent from `public/`.

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
* **Where the new sentences live: hand-authored in `contracts/shared-rules.json`
  under `specialNames`, with tests and documents naming keys, never quoting
  text.** Decided 2026-08-24. This is not a new precedent: `siteHealth.checks`
  sentences already live there and `site_health.py` reads them at run time
  inside the container (`scripts/site_health.py:24-28, 61-63`). Python cannot
  read Swift, and two of this branch's sentences — Piece 1's health check and
  Piece 2's `index.md` note — are read by Python. Splitting (Python-read
  sentences in the contract, the ⓘ sentences in Swift-generated
  `assist-wording.json`) was rejected because it gives one feature two homes,
  the drift `CLAUDE.md`'s "one place per kind of truth" table exists to
  prevent. The "name it, don't quote it" rule stands as written: reference
  `specialNames.<key>`.
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

**"Adversarial review after each item"** means: attack that specific diff and
its claims with file:line evidence, fold the findings back in, and commit again.
Not batched at the end. Gemini does this on its own work before committing —
spawn a separate reviewer rather than re-reading your own diff in the same
breath, and give it the brief of finding what is WRONG, not of confirming the
work. The Claude session then reviews the committed result independently. That
double pass has caught false claims in this branch repeatedly — several
`GUI-IMPROVEMENTS.md` rows exist only to correct earlier rows, and this very
file needed two rounds before it was safe to hand over.

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
  the same session, with the right `Co-Authored-By` trailer for your agent
  (see "Who does what" above).

## Known open, deliberately not in scope

* **A section with no `index.md` cannot be published at all.**
  `_sync_public_to_host` (`build_site.py:3131-3138`) only copies back when
  `public/index.html` exists, and with no `index.md` Quartz emits none — so the
  build succeeds, the sync is silently skipped, and `deploy.sh` then says "Built
  site not found — build first". Shared Python, so Windows has it too. Written
  up in `WINDOWS-HANDOFF.md` with two one-line fixes available.
* **Renaming the `Unit` keyword** — deferred, in `TODO.md`.
