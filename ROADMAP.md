# Plantoir roadmap

What is planned for Plantoir, release by release, in plain words. If you are a
teacher wondering "is that coming?", this is the page to read.

*Last updated: 17 October 2026. The current release is **1.7.2**.*

A few things to know before you read on:

- **Plans change.** Something listed here may move to a later release, be
  reshaped, or be dropped after it is tried. Nothing on this page is a promise
  or a date.
- **Your work is safe.** A course you have already built keeps building and
  publishing as it does today. Most new features are things you choose to use
  on a page; a few improve every site (for example, checklists becoming
  tickable), and those are named below.
- **Mac first, Windows soon after.** New features usually arrive in the Mac
  app first and reach the Windows app in a following update. Where a feature
  is Mac-only for now, it says so below.
- **Student progress stays on the student's device.** Features that track
  progress (ticked checklists, quiz scores) keep it in the student's own
  browser and send it nowhere. Plantoir is not, and will not become, a grade book.

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
  students run with their own input. The first time you use one, the Mac
  downloads a large one-time extra (about 1.3 GB).
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
- **Undoing a change Plantoir made for you works properly.** If only part
  of a change could be undone, pressing Undo again now finishes the job
  instead of getting stuck.
  ([#555](https://github.com/russellgordon/plantoir/issues/555))
- **plantoir.app has a new Code page** showing runnable programs and quizzes.
  ([#562](https://github.com/russellgordon/plantoir/issues/562))
- Behind the scenes: clearer records of when Plantoir opened and closed, to
  help look into problems you report.

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
  - why the first "Getting this folder ready" after an update can take about
    two minutes is being looked into
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
  course — wherever it can tell which note that is. ([#518](https://github.com/russellgordon/plantoir/issues/518))
- **Students can tick checklists.** A checklist on a class page becomes
  clickable, and each student's ticks are remembered in their own browser.
  Your notes are never changed.
  ([#519](https://github.com/russellgordon/plantoir/issues/519))
- **A "My progress" page for each student**, built from those ticks: what
  they've checked off under each page's success criteria, grouped by class.
  It counts ticks under headings such as "Success criteria" (you can set
  which headings in Course Settings). Only the student sees it, and this page
  is added to every section automatically.
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
- **GeoGebra on your pages.** Interactive maths with sliders, draggable
  points and constructions, written as a few lines in a note. Students tap
  to load it; nothing loads until then. (Graphs students can move, and TikZ
  diagrams, are already here.)
  ([#578](https://github.com/russellgordon/plantoir/issues/578))
- **Printing fixes:** Print should always open the print window, even on a
  long page with many code blocks (today it can stop silently in Safari)
  ([#576](https://github.com/russellgordon/plantoir/issues/576)), and a
  handout printed on Windows should look the same as one printed on a Mac
  ([#577](https://github.com/russellgordon/plantoir/issues/577)).
- **A course name with a colon works.** Naming a course "Physics: Mechanics"
  no longer stops its front page from being built.
  ([#575](https://github.com/russellgordon/plantoir/issues/575))
- **Diagrams and fonts served by your own site**, as maths already is in 1.8,
  so pages look right without reaching other websites.
  ([#566](https://github.com/russellgordon/plantoir/issues/566))

---

## Version 2.0 — interactive science

- **PhET science simulations on your pages**, from the University of
  Colorado's collection — projectile motion, gas laws, circuits, natural
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
  - the backups size in the sidebar should no longer get cut off
    ([#516](https://github.com/russellgordon/plantoir/issues/516)).
- **Changing a scheduled publish time — being decided.** Either both apps
  let you change the time directly, as Windows does today, or both ask you to
  cancel and schedule again
  ([#525](https://github.com/russellgordon/plantoir/issues/525)). On Windows,
  a course you keep for reference will stop publishing on a schedule, as it
  does on the Mac ([#527](https://github.com/russellgordon/plantoir/issues/527)).
- **plantoir.app updates:** showing off the newer features
  ([#486](https://github.com/russellgordon/plantoir/issues/486)), and
  correcting what it says about scheduled publishing when your computer is
  closed or asleep at the scheduled time
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
- **The rest of self-check quizzes**, building on what arrives in 1.8: an
  answer key when you print, and questions that use GeoGebra (1.9) and PhET
  (2.0).
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
- **When a release is tagged**, delete what it shipped — the release notes
  now say what it brought — and update the current release number at the top.
  On a Mac-only release, keep the Windows lines until the Windows download
  joins that release. `RELEASING.md` and the `cut-release` skill carry this
  as a step, including a check that every issue listed is still open on that
  milestone (or closed and waiting for the release).
- **When an issue moves milestone, or a new one is given a milestone**, move
  or add its line. The open issues and their milestones on GitHub are the
  source of truth; this page is the plain-words view of them.
- **Change the "Last updated" date on every edit**, not only at a release.
- Write for a teacher: what they will see or be able to do, never how it
  works inside. Internal-only work gets at most one "behind the scenes" line.
