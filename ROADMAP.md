# Plantoir roadmap

What is planned for Plantoir, release by release, in plain words. If you are a
teacher wondering "is that coming?", this is the page to read.

*Last updated: 24 October 2026. The current release is **1.9.0** on the Mac and **1.8.7** on Windows.*

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

## Next: Windows catches up to 1.9.0

Plantoir 1.9.0 is out for the Mac. Windows stays on 1.8.7 until its own 1.9.0
download joins the release, with what 1.9.0 brought the Mac:

- **GeoGebra sketches on your pages** — a sketch saved beside the page, typed
  GeoGebra commands, or a sketch from geogebra.org kept once; in quiz
  questions too ([#687](https://github.com/russellgordon/plantoir/issues/687)).
- **Text blocks that wrap** at the window's width, with their line numbers
  kept ([#676](https://github.com/russellgordon/plantoir/issues/676)).
- **Open in Obsidian goes to the page you're looking at**
  ([#681](https://github.com/russellgordon/plantoir/issues/681)), and the
  assistant can do it when you ask
  ([#690](https://github.com/russellgordon/plantoir/issues/690)).
- **A quiz the website reads differently** is shown among your folder's
  problems ([#677](https://github.com/russellgordon/plantoir/issues/677)).
- **The newer, supported engine** that draws your sites
  ([#675](https://github.com/russellgordon/plantoir/issues/675)), with a
  record of known weaknesses in the parts Plantoir carries
  ([#685](https://github.com/russellgordon/plantoir/issues/685)).
- **Windows fixes of its own:** a preview that did not rebuild after an edit
  ([#671](https://github.com/russellgordon/plantoir/issues/671)); the line
  shown when the disk fills while Swift is being set up
  ([#672](https://github.com/russellgordon/plantoir/issues/672)); the Quizzes
  page pictures on plantoir.app
  ([#590](https://github.com/russellgordon/plantoir/issues/590)); and what a
  scheduled publish does when the computer is asleep
  ([#554](https://github.com/russellgordon/plantoir/issues/554)).
- **Behind the scenes:** a few checks that both apps behave the same way
  ([#659](https://github.com/russellgordon/plantoir/issues/659),
  [#660](https://github.com/russellgordon/plantoir/issues/660),
  [#661](https://github.com/russellgordon/plantoir/issues/661),
  [#666](https://github.com/russellgordon/plantoir/issues/666),
  [#673](https://github.com/russellgordon/plantoir/issues/673),
  [#680](https://github.com/russellgordon/plantoir/issues/680),
  [#682](https://github.com/russellgordon/plantoir/issues/682)).

---


## Version 2.0

- **PhET science simulations on your pages**, from the University of
  Colorado's collection — projectile motion, gas laws, circuits, natural
  selection and more. Students tap to open them; nothing loads until then.
  ([#674](https://github.com/russellgordon/plantoir/issues/674))
- **plantoir.app shows off science**, alongside the maths and coding it
  already shows ([#485](https://github.com/russellgordon/plantoir/issues/485)).
- **My Progress, settings and more.** A switch and the list of
  success-criteria headings in Course Settings, a way for students to narrow
  the page to a date or a unit, and a check that it prints well.
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
- **Printing on Windows:** a handout printed on Windows should look the same
  as one printed on a Mac
  ([#577](https://github.com/russellgordon/plantoir/issues/577)).
- **Diagrams and fonts served by your own site**, as maths and GeoGebra
  already are, so pages look right without reaching other websites.
  ([#566](https://github.com/russellgordon/plantoir/issues/566))
- Behind the scenes: a check before each release that every kind of diagram
  and interactive page really draws on the published test sites
  ([#597](https://github.com/russellgordon/plantoir/issues/597)).

---

## Version 2.1

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
## Version 2.2

- **"Revise with…" in more places.** Use the Claude and Codex desktop apps,
  not just their command-line versions
  ([#507](https://github.com/russellgordon/plantoir/issues/507)), and add
  Google Gemini and Antigravity
  ([#508](https://github.com/russellgordon/plantoir/issues/508)).
- **The rest of self-check quizzes**, building on what arrives in 1.8: an
  answer key when you print, and questions that use PhET (2.0). Questions
  with a GeoGebra sketch arrived with GeoGebra itself, in 1.9.
  ([#511](https://github.com/russellgordon/plantoir/issues/511))
- **Students choose their own colour scheme** on a published site
  ([#606](https://github.com/russellgordon/plantoir/issues/606)).
- Behind the scenes: trying the next major version of the engine Plantoir
  builds sites with, only if it is measurably faster
  ([#512](https://github.com/russellgordon/plantoir/issues/512)).

---

## Ideas being explored (no release yet)

- **Ready-made courses that show off the interactive features**, especially
  Ontario maths, science and Technological Education courses.
  ([#513](https://github.com/russellgordon/plantoir/issues/513))

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
