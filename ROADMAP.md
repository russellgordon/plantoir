# Plantoir roadmap

What is planned for Plantoir, release by release, in plain words. If you are a
teacher wondering "is that coming?", this is the page to read.

*Last updated: 17 October 2026. The current release is **1.7.2**.*

A few things to know before you read on:

- **Plans change.** Something listed here may move to a later release, be
  reshaped, or be dropped after it is tried. Nothing on this page is a promise
  or a date.
- **Your work is safe.** Every change below is designed so that a course you
  have already built keeps working exactly as it does today. New features are
  things you choose to use on a page; they do not change pages that don't
  use them.
- **Mac first, Windows soon after.** New features usually arrive in the Mac
  app first and reach the Windows app in a following update. Where a feature
  is Mac-only for now, it says so below.
- **Nothing about your students leaves their browser.** Features that track
  progress (ticked checklists, quiz scores) keep it on the student's own
  device. Plantoir is not, and will not become, a grade book.

Each item links to its GitHub issue, if you want the full detail. You don't
need to read those to use Plantoir.

---

## Next: version 1.8

### Already finished, waiting for the release

These are done and will arrive when 1.8 is released.

- **Programs students can run on the page.** Put Python code on a page and
  students can edit it and press Run in their browser, with nothing to
  install. The ready-made ICS3U course uses these throughout.
  ([#455](https://github.com/russellgordon/plantoir/issues/455),
  [#561](https://github.com/russellgordon/plantoir/issues/561))
- **Swift programs too** (Mac only for now): read-only Swift programs that
  students run with their own input.
  ([#493](https://github.com/russellgordon/plantoir/issues/493))
- **Self-check quizzes.** Multiple choice, select all that apply, short
  answer and fill in the blank, written right in your notes. Students get
  instant feedback; answers can include maths, graphs, diagrams and runnable
  code. ([#563](https://github.com/russellgordon/plantoir/issues/563))
- **Maths shows up even without an outside service.** The maths on your
  pages is now served by your own class site rather than borrowed from
  another website.
  ([#494](https://github.com/russellgordon/plantoir/issues/494))
- **Curriculum pages:** the overall expectations now show "When did we do
  this?" links, as the specific expectations already did.
  ([#505](https://github.com/russellgordon/plantoir/issues/505))
- **Undo works properly after a partial undo.** Pressing Undo again now
  finishes the job instead of getting stuck.
  ([#555](https://github.com/russellgordon/plantoir/issues/555))
- **plantoir.app has a new Code page** showing runnable programs and quizzes.
  ([#562](https://github.com/russellgordon/plantoir/issues/562))

### Still to do for 1.8

- **Obsidian add-ons installed for you.** Some features look best in
  Obsidian with an add-on (for example, to see a diagram while you write).
  Plantoir will offer to install it into your course with one yes, rather
  than asking you to do it by hand.
  ([#495](https://github.com/russellgordon/plantoir/issues/495))
- **A shared folder added later appears on the site.** Today, a folder you
  add to an existing course in Course Settings doesn't show in the sidebar
  and has no page to copy. It will behave like a folder made with the course.
  ([#506](https://github.com/russellgordon/plantoir/issues/506))
- **Windows catches up** on runnable Python, self-check quizzes and the
  Undo fix above
  ([#568](https://github.com/russellgordon/plantoir/issues/568),
  [#571](https://github.com/russellgordon/plantoir/issues/571),
  [#564](https://github.com/russellgordon/plantoir/issues/564)), and a
  decision on how Swift programs will ever work on Windows
  ([#570](https://github.com/russellgordon/plantoir/issues/570)).
- **Windows fixes:**
  - a window can no longer reopen off screen after a monitor is unplugged
    ([#558](https://github.com/russellgordon/plantoir/issues/558));
  - the first "Getting this folder ready" after an update should take seconds,
    not two minutes
    ([#559](https://github.com/russellgordon/plantoir/issues/559));
  - clubs see "meeting" rather than "class" when publishing
    ([#556](https://github.com/russellgordon/plantoir/issues/556));
  - an honest answer to what happens to a scheduled publish when the computer
    is asleep at that time
    ([#554](https://github.com/russellgordon/plantoir/issues/554)).

---

## Version 1.9

- **Open in Obsidian goes to the page you're looking at.** While previewing a
  page, Open in Obsidian will open the note that page came from, not just the
  course. ([#518](https://github.com/russellgordon/plantoir/issues/518))
- **Students can tick checklists.** A checklist on a class page becomes
  clickable, and each student's ticks are remembered in their own browser.
  Your notes are never changed.
  ([#519](https://github.com/russellgordon/plantoir/issues/519))
- **A "My progress" page for each student**, built from those ticks: what
  they've checked off under each page's success criteria, grouped by class.
  Only the student sees it.
  ([#545](https://github.com/russellgordon/plantoir/issues/545))
- **Reference courses, more flexible.** Add a ready-made course straight to
  your reference shelf — even for a course code you're already teaching —
  arrange the shelf in groups you make yourself, and replace a reference
  course with a newer version (with a backup kept first). Still being
  decided. ([#572](https://github.com/russellgordon/plantoir/issues/572))
- **Backups and archives, made clearer.** These two features overlap; the
  plan is to decide whether to combine them into one place for every kept
  copy of a course, or to give archives the same browsing that backups have.
  ([#573](https://github.com/russellgordon/plantoir/issues/573))
- **Curriculum page fixes:** a table of contents appears when you ask for one
  ([#520](https://github.com/russellgordon/plantoir/issues/520)), and an
  unusual character in a file name no longer stops the site from building
  ([#569](https://github.com/russellgordon/plantoir/issues/569)).
- **Problems with runnable code are shown in the app**, alongside the other
  things Plantoir tells you about a folder, rather than only on the page.
  ([#567](https://github.com/russellgordon/plantoir/issues/567))
- **Diagrams and fonts served by your own site**, as maths already is in 1.8,
  so pages look right without reaching other websites.
  ([#566](https://github.com/russellgordon/plantoir/issues/566))

---

## Version 2.0 — interactive science and maths

- **GeoGebra and PhET on your pages.** Interactive maths with sliders and
  draggable points (GeoGebra), and science simulations from the University of
  Colorado's PhET collection — projectile motion, gas laws, circuits, natural
  selection and more. Students tap to open them; nothing loads until then.
  ([#485](https://github.com/russellgordon/plantoir/issues/485))
- **A live circuit simulator** with real schematic symbols, for physics and
  Technological Education. Lower priority than the rest.
  ([#487](https://github.com/russellgordon/plantoir/issues/487))
- **Mac fixes:**
  - the first Preview after the Mac wakes from sleep should start promptly
    ([#517](https://github.com/russellgordon/plantoir/issues/517));
  - menu-bar commands such as Publish Pages… should always work the first
    time ([#523](https://github.com/russellgordon/plantoir/issues/523));
  - the backups size in the sidebar no longer gets cut off
    ([#516](https://github.com/russellgordon/plantoir/issues/516)).
- **Changing a scheduled publish time** without cancelling and scheduling
  again — Windows already offers this; the Mac may get it too
  ([#525](https://github.com/russellgordon/plantoir/issues/525)). On Windows,
  a course you keep for reference will stop publishing on a schedule, as it
  does on the Mac ([#527](https://github.com/russellgordon/plantoir/issues/527)).
- **plantoir.app updates:** showing off the newer features
  ([#486](https://github.com/russellgordon/plantoir/issues/486)), and
  correcting what it says about scheduled publishing: if your laptop is
  closed at the scheduled time, the site is not published
  ([#509](https://github.com/russellgordon/plantoir/issues/509)).
- **Being looked into: a completely opt-in usage count**, so we can learn
  roughly how many teachers use Plantoir and how. Nothing would be sent unless
  you choose to turn it on.
  ([#510](https://github.com/russellgordon/plantoir/issues/510))
- Behind the scenes: a handful of checks that the Mac and Windows apps
  behave the same way, and fixes to how plantoir.app's pictures are made.

---

## Version 2.1

- **"Revise with…" in more places.** Use the Claude and Codex desktop apps,
  not just their command-line versions
  ([#507](https://github.com/russellgordon/plantoir/issues/507)), and add
  Google Gemini and Antigravity
  ([#508](https://github.com/russellgordon/plantoir/issues/508)).
- **The rest of self-check quizzes**, building on what arrives in 1.8 — for
  example, questions that use the GeoGebra and PhET interactives from 2.0.
  ([#511](https://github.com/russellgordon/plantoir/issues/511))

---

## Ideas being explored (no release yet)

- **Ready-made courses that show off the interactive features**, especially
  Ontario maths, science and Technological Education courses.
  ([#513](https://github.com/russellgordon/plantoir/issues/513))
- **Faster site building**, by trying the next major version of the engine
  Plantoir builds sites with. Only worth doing if it is measurably faster.
  ([#512](https://github.com/russellgordon/plantoir/issues/512))

---

## Keeping this page current

*For whoever maintains Plantoir.* This page is trimmed, not appended to:

- **When an issue closes**, move its line into "Already finished, waiting for
  the release" for that version, or delete it if a teacher would never notice.
- **When a release is tagged**, delete its whole section — the release notes
  now say what it brought — and update the "Last updated" line and the current
  release number at the top. `RELEASING.md` and the `cut-release` skill carry
  this as a step.
- **When an issue moves milestone, or a new one is given a milestone**, move
  or add its line. The open issues and their milestones on GitHub are the
  source of truth; this page is the plain-words view of them.
- Write for a teacher: what they will see or be able to do, never how it
  works inside. Internal-only work gets at most one "behind the scenes" line.
