# Why this branch exists

`issue/special-folders-hardening`, branched off `dev` on 2026-08-23, **merged
into `dev` on 2026-08-25**.

**Read this as the record of a finished branch.** It is kept because the
reasoning in it is still the reasoning behind the code — why the checks ask
what the FEATURE produced rather than whether a folder exists, why they live in
the Python rather than in either app, and why they must neither break a build
nor nag. The last two sections say what has happened since; where they and a
`GUI-IMPROVEMENTS.md` row disagree, the row is the history and `contracts/` is
what is true now.

## The problem, in one sentence

A handful of folder and file names inside a course carry BEHAVIOUR — `Tasks`,
the curriculum folder, `All Classes`, `Media`, `index.md`, `Key Links.md` — and
nothing stopped a teacher renaming or deleting one. The features they drive then
failed **silently**.

The Curriculum Coverage map is the worst case and the one that started this. Ask
for the map with the curriculum folder gone and it does not error, does not warn,
and does not disappear. It renders, it looks healthy, and it is **wrong** — which
is worse than missing, because a teacher will believe it. A course's folders look
like ordinary folders in Obsidian, so tidying them up is a reasonable thing for a
teacher to do, and it was a footgun with no trigger guard.

## What Russell asked for

Seven items, of which six are in this branch:

1. Make "counts for marks" folders **configurable** (default `Tasks`; a teacher
   can add `Tests`, or remove `Tasks`) instead of the hardcoded rule "any folder
   whose name contains *task*".
2. Keep `curriculum` as a keyword, but **warn at build time** if the folder is
   gone while the coverage feature is on.
3. The same protection for `All Classes`.
4. The same for `Media`.
5. The same for `index.md`, `Key Links.md`, `Curriculum Coverage.md`.
6. Allow renaming the `Unit` keyword — **deferred to `TODO.md`**, not in this branch.
7. Document these special files **inside the app**.

And one instruction that shaped everything: *"When I say 'warn at build time' I
mean not just something in the hidden console messages — I mean a full on dialog
box explaining in clear terms what the problem is."*

## The design, and why it is that way

**Every check asks whether the FEATURE produced anything, never whether a folder
exists.** Recreating an empty `Ontario Curriculum` folder does not bring back a
teacher's expectation pages, so an existence check with a Fix button would have
silenced the warning and left the map broken. A check that can be satisfied
without fixing the problem is worse than no check at all.

**The checks live in `scripts/site_health.py`, not in either app.** Two reasons.
Every check is defined over the MERGED content tree, which does not exist until a
build makes it — there is nothing to look at beforehand. And a check that only
guarded a GUI button would be bypassed by the assistant, by `--mcp-stdio`, by the
launchers, and by the scheduled deploy, which runs with the app CLOSED and is the
case that matters most.

**The words come from `contracts/shared-rules.json` → `siteHealth`,** read at run
time, so the two apps and the Python cannot word the same problem differently.
Making that possible was step 1 of the branch: `scripts/contracts.py` plus
`toolchain_paths.CONTRACTS_DIR`, with `contracts/` **baked into the image**,
because the container's only bind mount is `courses/`.

**The checks must never break a build.** `announce_or_stay_quiet` swallows every
error and says one plain line. A health check that destroys the build it was
checking is worse than the silent failure it replaces.

**They must not nag, either.** Each coverage check is gated on the OTHER half
existing. A brand-new course has an empty curriculum folder and an empty class
folder on day one, and an unconditional pair of warnings would fire on every
build of a course nobody has broken. A warning a teacher cannot act on is one
they learn to dismiss — and they will dismiss it when it counts.

## What the teacher actually sees

A real **dialog**, on both the preview and the deploy path, naming the problem in
plain words. Where the problem can be put right mechanically (a missing `Media`
folder, a missing section `index.md`) it carries a **Fix** button, then says what
it did, then offers **Preview Again** — and the section shows " — Edited"
afterwards, because a publish is now owed. Where it cannot (missing expectation
pages) it explains and gets out of the way.

Machinery travels from the Python to the apps as `PLANTOIR_HEALTH: {json}` lines
parsed out of the transcript, carrying the teacher-facing sentence itself rather
than a code each platform re-words.

## Work done alongside, because it was in the way

- **One rule for "where do this section's class pages live?"** — there were four
  disagreeing answers (`ClassFolder` in Swift, `ClassFolderRule` in C#,
  `class_folder_name`/`class_folder_names` in Python), pinned by a contract case.
- **Recipe folders became data** (`contracts/toolchain.json` → `recipeFolders`)
  after a FOURTH hand-maintained copy of the list in `website/shots/capture.py`
  shipped a demo workspace whose Dockerfile was not stale but **unbuildable**.
- **Payloads and skeletons declare `graded_folders`** so the configurable pool has
  a sensible default per course.
- Windows kept in step: `ClassFolderRule.cs`, `ClassFolderContractTests.cs`, the
  mirrored `contracts` folder, and write-ups in `WINDOWS-HANDOFF.md`.

## The honesty rule this branch was worked under

Russell asked for an adversarial review after **each** item, not batched at the
end, and the reviews found real things — including several claims I had written
that were **false**. `GUI-IMPROVEMENTS.md` is append-only, so rows 356, 364, 369
and 371 correct rows 355, 363, 368 and 370 **in place, with the wrong claim left
visible beside its correction** rather than quietly edited away. That is
deliberate: a log that silently rewrites itself cannot be trusted about anything.

## What Russell found by hand, and what it turned into

Russell tried the branch on 2026-08-24 and found the hole the first six items
did not cover: **he removed `Tasks`, the curriculum folder and `All Classes`
from inside the New Course Wizard, and Plantoir said nothing.**

That was a fair hit. `StringListEditorView.removeItem` dropped a name with no
warning and no notion that any name meant anything — the same component in the
wizard and in Course Settings. It already refused `Media` on **add**, so it had
the concept; it simply never applied it on **remove**. The build-time dialog
then correctly stayed silent, because removing the curriculum folder in the
wizard switches the coverage feature OFF — nothing was broken, so nothing
complained, and he was never told what he had given up at the moment he gave
it up.

Tracing what removal actually cost turned up a second, separate defect: in
**Course Settings** removal did not stick at all. `preflight_update_course_config`
re-added on the next build anything it found on disk, AND **un-hid it** — so
removing a deliberately hidden folder in Settings could make it appear on the
student-facing site.

**Both are fixed.** They became Pieces 2 and 3, planned in `TODAYS-PLAN.md` and
merged into `dev` on 2026-08-25: `excluded_items` made removal authoritative at
build time, and the protection model gave every row in the list editors one of
three states — blocked with an ⓘ naming the switch to turn off, consequential
with a confirmation, or ordinary. `GUI-IMPROVEMENTS.md` rows 375–380.

## What has happened since, and where the work stands

**Pieces 1–3 merged into `dev` on 2026-08-25** (rows 374–380). Everything in
"What Russell asked for" above is done except item 6, and item 6 is now half
done.

A follow-up branch, `issue/special-names-followups`, took the three things this
one deliberately left behind, and then grew well past them — it now carries a
recorded `class_folder`, a publishing harness, and the fixes from four
adversarial reviews and an overnight verification run. `GUI-IMPROVEMENTS.md`
rows **384–394** are the record, and rows 388, 389 and 394 are corrections of
earlier rows in that range, so read the range rather than any single row. The
three things this branch left behind became:

- **The `index.md` publishing hole below is closed** — and the fix found a
  worse defect beside it, where a publish after deleting a front page reported
  success and shipped the previous build's pages.
- **A teacher can rename a course folder from inside Plantoir**, on disk and in
  every section, which was the `TODO.md` item deferred while this branch was
  planned.
- **A course chooses its own word for "Unit"** when it is made, and both the
  build and the apps read that word rather than assuming it. That is item 6,
  in the half Russell chose: new courses, not renaming a course already in use.

## Known open when this branch merged — and what became of it

- **A section with no `index.md` cannot be published at all.** ✅ **Fixed
  2026-09-01.** The build succeeded, `_sync_public_to_host` skipped the copy
  because Quartz emitted no root `index.html`, and the deploy then reported a
  missing built site immediately after a successful build. The build now says
  why and stops, and the previous build's output is cleared so a publish cannot
  ship it as though it were current. What the teacher is told is
  `app-rules.json` → `failureExplanations`. Shared Python, so Windows inherits
  it.
- **Item 6** (renaming the `Unit` keyword). ✅ **Half done 2026-09-01** — a
  course picks its word when it is made, and the parsing follows it. Renaming
  an EXISTING course's word is still open in `TODO.md`, with the measurements
  that make it unattractive.
