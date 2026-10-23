# Plantoir roadmap

What is planned for Plantoir, release by release, in plain words. If you are a
teacher wondering "is that coming?", this is the page to read.

*Last updated: 22 October 2026. The current release is **1.8.5** on the Mac and on Windows.*

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

## Version 1.9

- **Open in Obsidian goes to the page you're looking at.** While previewing a
  page, Open in Obsidian will open the note that page came from, not just the
  course — wherever it can tell which note that is. ([#518](https://github.com/russellgordon/plantoir/issues/518))
- **My Progress, settings and more.** The My Progress page arrived on the
  Mac in 1.8.2. Next: a switch and the list of success-criteria headings in
  Course Settings, a way for students to narrow the page to a date or a unit,
  and a check that it prints well.
  ([#595](https://github.com/russellgordon/plantoir/issues/595))
- **Reference courses, more flexible.** Add a ready-made course straight to
  your reference shelf — even for a course code you're already teaching —
  arrange the shelf in groups you make yourself, and replace a reference
  course with a newer version (with a backup kept first). Still being
  decided. ([#572](https://github.com/russellgordon/plantoir/issues/572))
- **Backups and archives, made clearer.** These two features overlap; the
  plan is to decide whether to combine them into one place for every kept
  copy of a course, or to give archives the same browsing that backups have.
  ([#573](https://github.com/russellgordon/plantoir/issues/573))
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
- **Diagrams and fonts served by your own site**, as maths already is in 1.8,
  so pages look right without reaching other websites.
  ([#566](https://github.com/russellgordon/plantoir/issues/566))

- **Decisions and measurements carried over from the Windows 1.8.5 catch-up:** what a
  scheduled publish does when the computer is asleep
  ([#554](https://github.com/russellgordon/plantoir/issues/554)), and a
  curriculum folder renamed to a name without "curriculum"
  ([#614](https://github.com/russellgordon/plantoir/issues/614)).
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
