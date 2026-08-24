# Why this branch exists

`issue/special-folders-hardening`, branched off `dev` on 2026-08-23.

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

## Known open, deliberately

- **A section with no `index.md` cannot be published at all.** The build succeeds,
  `_sync_public_to_host` skips the copy because Quartz emitted no root
  `index.html`, and `deploy.sh` then says "Built site not found — build first"
  immediately after a successful build. Shared Python, so Windows has it too.
  Written up in `WINDOWS-HANDOFF.md` with two one-line fixes available. Not fixed
  here because it is a separate piece.
- **Item 6** (renaming the `Unit` keyword) is in `TODO.md`.

## What is being worked on right now, and is NOT yet done

Russell tried the branch by hand on 2026-08-24 and found the hole the rest of
this work does not cover: **he removed `Tasks`, the curriculum folder and
`All Classes` from inside the New Course Wizard, and Plantoir said nothing.**

That is a fair hit. `StringListEditorView.removeItem`
(`Views/CourseSettings/StringListEditorView.swift:128`) drops a name with no
warning and no notion that any name means anything — the same component in the
wizard (`NewCourseWizardView.swift:765-768`) and in Course Settings
(`CourseSettingsView.swift:81-97`). It already refuses `Media` on **add**, so it
has the concept; it just never applies it on **remove**. The build-time dialog
then correctly stayed silent, because removing the curriculum folder in the
wizard switches the coverage feature OFF (`setup_course.py:2243-2245`) — nothing
was broken, so nothing complained, and he was never told what he had given up at
the moment he gave it up.

Tracing what removal actually costs turned up a second, separate defect: in
**Course Settings** removal does not stick at all. `preflight_update_course_config`
(`build_site.py:3311`, called at `:4277`) re-adds on the next build anything it
finds on disk, AND **un-hides it** (`:3346-3351`) — so removing a deliberately
hidden folder in Settings can make it appear on the student-facing site.

Neither is fixed yet. No plan has been agreed.
