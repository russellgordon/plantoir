# Plantoir roadmap

What is planned for Plantoir, release by release, in plain words. If you are a
teacher wondering "is that coming?", this is the page to read.

*Last updated: 12 November 2026. The current release is **1.9.3** on both the Mac and Windows.*

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

## Version 1.10.0

Mac first. The Windows app follows in its own update.

- **Unit planning beside Plantoir.** When Claude Code or Codex is installed,
  the course page gains a Planning tab: an assistant helps you plan a unit —
  a calendar across your sections, lesson cards, day materials, assessment
  drafts, a curriculum correlation — and the plan shows right there, with
  the files it links. ([#707](https://github.com/russellgordon/plantoir/issues/707),
  [#708](https://github.com/russellgordon/plantoir/issues/708))
- **Share a unit plan with a colleague.** Publish the plan as its own small
  website, kept well apart from your class sites, optionally behind a
  username and password, and stop sharing it when you're done.
  ([#709](https://github.com/russellgordon/plantoir/issues/709))
- **Reference courses, more flexible.** Add or import a course straight to
  your reference shelf — even for a course code you're already teaching —
  arrange the shelf in groups you make yourself, and replace a reference
  course with a newer version (with a backup kept first).
  ([#572](https://github.com/russellgordon/plantoir/issues/572))
- **GeoGebra sketches show that they are loading.** While GeoGebra itself
  is still arriving, the sketch's box says so, inside the box, instead of
  standing empty. ([#756](https://github.com/russellgordon/plantoir/issues/756))
- **Better guidance for an assistant writing your pages and handouts.**
  The notes Claude Code or Codex read before writing a page or a printed
  handout are brought up to date: copyable text that wraps, lettered parts
  that line up on quizzes and tests, and a settled shape for a lesson page.
  ([#758](https://github.com/russellgordon/plantoir/issues/758), [#754](https://github.com/russellgordon/plantoir/issues/754), [#765](https://github.com/russellgordon/plantoir/issues/765))
- **Guidance for writing tests, marking, and report comments.** Three more
  sets of notes for an assistant working beside Plantoir: writing a unit
  test with its solutions, marking guide and practice test; marking tests
  and coding assignments onto feedback sheets; and drafting report comments
  from the marks. Student names stay on your computer.
  ([#751](https://github.com/russellgordon/plantoir/issues/751), [#750](https://github.com/russellgordon/plantoir/issues/750), [#752](https://github.com/russellgordon/plantoir/issues/752))

## Version 1.11.0

Small fixes and conveniences. Mac first where it says so.

- **GitHub Copilot beside Plantoir.** When the Copilot command-line tool is
  installed, Plantoir offers it wherever it offers Claude Code or Codex
  today: revising a course, fixing a section's problems, planning a unit.
  GitHub offers Copilot at no cost to verified teachers, which would make
  this the first free way to work with a capable assistant beside Plantoir.
  (What GitHub offers can change; check GitHub Education when you sign up.)
  ([#783](https://github.com/russellgordon/plantoir/issues/783))
- **See, change or remove a saved Netlify or Cloudflare token** in
  Settings ▸ Deploying. ([#696](https://github.com/russellgordon/plantoir/issues/696))
- **Vimeo videos embed like YouTube ones**, from a plain link, with a
  privacy-friendly player. ([#692](https://github.com/russellgordon/plantoir/issues/692))
- **A plain explanation when Cloudflare will not make another site**
  because a free account has reached its limit of 100. ([#723](https://github.com/russellgordon/plantoir/issues/723))
- **The assistant:** "Open my website" opens it rather than deploying it
  ([#688](https://github.com/russellgordon/plantoir/issues/688)), and a course that could not be opened in Obsidian is
  reported as such ([#721](https://github.com/russellgordon/plantoir/issues/721)).
- **Mac fixes:**
  - the first Preview after the Mac wakes from sleep should start promptly
    ([#517](https://github.com/russellgordon/plantoir/issues/517));
  - menu-bar commands such as Publish Pages… should always work the first
    time ([#523](https://github.com/russellgordon/plantoir/issues/523));
  - the backups size in the sidebar should no longer get cut off
    ([#516](https://github.com/russellgordon/plantoir/issues/516)).
- **Change the time of a scheduled deploy on the Mac**, without cancelling
  it and scheduling again, as Windows already allows. ([#525](https://github.com/russellgordon/plantoir/issues/525))
- Behind the scenes: old build folders are cleared away
  ([#722](https://github.com/russellgordon/plantoir/issues/722)), and a handful of checks that the Mac and Windows apps behave
  the same way.

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
- **Archives you can browse.** Backups and archives stay two separate
  features, and archives gain what backups already have: a list, what each
  one holds, and a way to open, compare, restore or carefully delete one.
  Nothing you have today moves or is renamed.
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
- On Windows, a course you keep for reference will stop publishing on a
  schedule, as it does on the Mac ([#527](https://github.com/russellgordon/plantoir/issues/527)).
- **plantoir.app updates:** showing off the newer features
  ([#486](https://github.com/russellgordon/plantoir/issues/486)).
- Behind the scenes: fixes to how plantoir.app's pictures are made.

---
## Version 2.2

- **"Revise with…" in more places.** Use the Claude and Codex desktop apps,
  not just their command-line versions
  ([#507](https://github.com/russellgordon/plantoir/issues/507)).
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

## Version 2.3

- **Music notation on your pages**, written as text, with playback.
  ([#679](https://github.com/russellgordon/plantoir/issues/679))

---

## Version 2.4

- **More assistants for "Revise with…":** Google Gemini and Antigravity.
  Held for later, with no date.
  ([#508](https://github.com/russellgordon/plantoir/issues/508))

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
