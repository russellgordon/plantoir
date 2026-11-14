# Plantoir roadmap

What is planned for Plantoir, release by release, in plain words. If you are a
teacher wondering "is that coming?", this is the page to read.

*Last updated: 14 November 2026. The current release is **1.9.3** on both the Mac and Windows.*

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

## Version 2.0.0

On the Mac and Windows together: neither download is released until both are
ready.

- **Unit planning beside Plantoir.** When Claude Code, Codex or GitHub Copilot is
  installed,
  the course page gains a Planning tab: an assistant helps you plan a unit —
  a calendar across your sections, lesson cards, day materials, assessment
  drafts, a curriculum correlation — and the plan shows right there, with
  the files it links. ([#707](https://github.com/russellgordon/plantoir/issues/707),
  [#708](https://github.com/russellgordon/plantoir/issues/708))
- **Share a unit plan with a colleague.** Share the plans as their own small
  website for the school year, kept well apart from your class sites,
  optionally behind a username and password, and stop sharing them when
  you're done.
  ([#709](https://github.com/russellgordon/plantoir/issues/709))
- **See your curriculum coverage in the app.** Each section gains a Coverage
  tab: the map of which curriculum expectations your pages cover, as it
  would be if every page were published.
  ([#793](https://github.com/russellgordon/plantoir/issues/793))
- **Reference courses, more flexible.** Add or import a course straight to
  your reference shelf — even for a course code you're already teaching —
  arrange the shelf in groups you make yourself, and replace a reference
  course with a newer version (with a backup kept first).
  ([#572](https://github.com/russellgordon/plantoir/issues/572))
- **GitHub Copilot beside Plantoir.** When GitHub Copilot is installed on
  your Mac, Plantoir offers it wherever it offers Claude Code or Codex, listed
  after them: revising a course (Revise With ▸ GitHub Copilot…), fixing a
  section's problems (Fix with GitHub Copilot…) and planning a unit (Plan a
  Unit with GitHub Copilot…). It asks you in its own window before it changes
  anything, as the other two do, unless you have set it not to ask. GitHub has its own plans and an education
  programme for teachers; Help will say what they include, with the date it
  was checked.
  ([#783](https://github.com/russellgordon/plantoir/issues/783))
- **Plantoir can set up an assistant for you.** If you want to use an
  assistant beside Plantoir and it is not installed yet, Plantoir sets it up
  when you ask. Plantoir itself needs no assistant.
  ([#855](https://github.com/russellgordon/plantoir/issues/855))
- **Undo and Redo for what you do in Plantoir.** Publish or hide pages, add a
  class, restore a backup: Edit ▸ Undo takes the last change back, one step
  at a time, and Redo puts it back. The list is still there after you quit.
  A deploy is never a step; if you undo something that was already
  deployed, Plantoir offers to deploy so your website matches.
  ([#899](https://github.com/russellgordon/plantoir/issues/899))
- **Everything the built-in assistant can do is also in the menus.**
  Section ▸ Add Class… adds the next class in this unit, the first class of a
  new unit, or a copy of an earlier class; Section ▸ Roll Over to a New Year…
  starts a section's new year; a single section can be put back from a
  backup; and Publish Pages… and Hide Pages… gain a box for each unit, so a
  whole unit can be ticked at once.
  ([#897](https://github.com/russellgordon/plantoir/issues/897), [#900](https://github.com/russellgordon/plantoir/issues/900))
- **Help inside the app.** A quick start, and a page for each thing you do,
  with pictures of the app, in the Help menu.
  ([#839](https://github.com/russellgordon/plantoir/issues/839))
- **GitHub Pages as a place to deploy your class site**, beside Netlify,
  Cloudflare Pages and a folder. ([#669](https://github.com/russellgordon/plantoir/issues/669))
- **Sites that stand on their own.** Diagrams and fonts are served by your
  own site, as maths and GeoGebra already are, so pages look right without
  reaching other websites.
  ([#566](https://github.com/russellgordon/plantoir/issues/566))
- **Only what your pages link to is put on your website.** A built site
  carries the pictures and files your published pages link to, and nothing
  else. A file that sits in the course folder with no published page linking
  to it, an answer key for example, is no longer on the website.
  ([#901](https://github.com/russellgordon/plantoir/issues/901))
- **Backups that take far less space.** The backups Plantoir makes on its
  own stop keeping a fresh copy of every picture, video and PDF each time.
  Backups you make yourself, and everything you have today, stay as they
  are. ([#785](https://github.com/russellgordon/plantoir/issues/785))
- **A safer Restore from Backup.** Restoring a whole course is done so that
  an interruption (a crash, a closed lid) leaves the course as it was. If
  you keep a course under Git, a restore no longer removes its history.
  ([#909](https://github.com/russellgordon/plantoir/issues/909))
- **Music notation on your pages**, written as text, with playback. The
  sounds are kept with your site, so nothing is fetched from another website
  when a student presses play.
  ([#679](https://github.com/russellgordon/plantoir/issues/679))
- **A live circuit simulator** with real schematic symbols, for physics and
  Technological Education.
  ([#487](https://github.com/russellgordon/plantoir/issues/487))
- **3D models on your pages**, such as a part to be 3D printed in
  Technological Education: students turn it and look at it from every side.
  ([#691](https://github.com/russellgordon/plantoir/issues/691))
- **A ready-made Music course.**
  ([#852](https://github.com/russellgordon/plantoir/issues/852))
- **Deploying you can count on.** A deploy always carries your latest
  changes, a deleted page included, and reuses the last build only when
  nothing has changed, even if the computer's clock was wrong when you made
  a change. Deploy waits, and says why, while another program is already
  deploying that section, a deploy typed in Terminal included. Plantoir says
  beforehand when the first scheduled deploy after an update will take
  longer than usual.
  ([#768](https://github.com/russellgordon/plantoir/issues/768), [#729](https://github.com/russellgordon/plantoir/issues/729), [#829](https://github.com/russellgordon/plantoir/issues/829), [#836](https://github.com/russellgordon/plantoir/issues/836), [#800](https://github.com/russellgordon/plantoir/issues/800))
- **A plain explanation when Cloudflare will not make another site**
  because a free account has reached its limit of 100. ([#723](https://github.com/russellgordon/plantoir/issues/723))
- **Tips that point out what is new**, and one that points a first-time
  teacher at the quick start.
  ([#851](https://github.com/russellgordon/plantoir/issues/851))
- **plantoir.app, rewritten in plain words**, showing what Plantoir can do,
  printable pages, runnable Python, maths and science included; the notes for every
  past release are rewritten the same way. Help is on the website too, with
  a switch between the Mac's steps and Windows'.
  ([#840](https://github.com/russellgordon/plantoir/issues/840), [#486](https://github.com/russellgordon/plantoir/issues/486), [#841](https://github.com/russellgordon/plantoir/issues/841))
- **My Progress, settings and more.** A switch and the list of
  success-criteria headings in Course Settings, a way for students to narrow
  the page to a date or a unit, and a check that it prints well.
  ([#595](https://github.com/russellgordon/plantoir/issues/595))
- **A course that could not be opened in Obsidian is reported as such** on
  the Mac, where a failed open used to read as one that worked.
  ([#721](https://github.com/russellgordon/plantoir/issues/721))
- **The rest of self-check quizzes**, building on what arrived in 1.8: an
  answer key when you print, and questions that use a PhET simulation.
  ([#511](https://github.com/russellgordon/plantoir/issues/511))
- **Mac fixes:**
  - the first Preview after the Mac wakes from sleep should start promptly
    ([#517](https://github.com/russellgordon/plantoir/issues/517));
  - menu-bar commands such as Publish Pages… should always work the first
    time ([#523](https://github.com/russellgordon/plantoir/issues/523));
  - the backups size in the sidebar should no longer get cut off
    ([#516](https://github.com/russellgordon/plantoir/issues/516)).
- **Change the time of a scheduled deploy on the Mac**, without cancelling
  it and scheduling again, as Windows already allows. ([#525](https://github.com/russellgordon/plantoir/issues/525))
- **PhET science simulations on your pages**, from the University of
  Colorado's collection: projectile motion, gas laws, circuits, natural
  selection and more. Students tap to open them; nothing loads until then,
  and the simulation is kept with your site.
  ([#674](https://github.com/russellgordon/plantoir/issues/674))
- **Vimeo videos embed like YouTube ones**, from the address the Share
  button gives, and both use the video site's privacy setting. ([#692](https://github.com/russellgordon/plantoir/issues/692))
- **See, change or remove a saved Netlify or Cloudflare token** in
  Settings ▸ Deploying. ([#696](https://github.com/russellgordon/plantoir/issues/696))
- **Shorter questions.** When Plantoir asks you something, it says it in one
  sentence and lists the facts beneath it, each with a label.
  ([#834](https://github.com/russellgordon/plantoir/issues/834))
- **GeoGebra sketches show that they are loading.** While GeoGebra itself
  is still arriving, the sketch's box says so, inside the box, instead of
  standing empty; and the reset icon puts a sketch back to how it opened.
  ([#756](https://github.com/russellgordon/plantoir/issues/756), [#792](https://github.com/russellgordon/plantoir/issues/792))
- **Better guidance for an assistant writing your pages and handouts.**
  The notes Claude Code, Codex or GitHub Copilot read before writing a page or a printed
  handout are brought up to date: copyable text that wraps, lettered parts
  that line up on quizzes and tests, and a settled shape for a lesson page.
  ([#758](https://github.com/russellgordon/plantoir/issues/758), [#754](https://github.com/russellgordon/plantoir/issues/754), [#765](https://github.com/russellgordon/plantoir/issues/765))
- **Guidance for writing tests.** Notes for an assistant working beside
  Plantoir on writing a unit test with its solutions and practice test. ([#751](https://github.com/russellgordon/plantoir/issues/751))
- **Grove Colours for everyone.** The colour scheme once named for one
  school is now called Grove Colours and is offered to every teacher, and a
  switch that only that school used is gone.
  ([#891](https://github.com/russellgordon/plantoir/issues/891))
- **A more thorough privacy check on problem reports.** Plantoir does not
  put your passwords or what is written on your pages into a problem report.
  As a safeguard, it also checks the report for anything that looks private
  before you send it, and that check now covers more cases.
  ([#853](https://github.com/russellgordon/plantoir/issues/853), [#876](https://github.com/russellgordon/plantoir/issues/876))
- **Windows fixes:** a handout printed on Windows should look the same as one
  printed on a Mac ([#577](https://github.com/russellgordon/plantoir/issues/577)), and a course you keep for reference will stop
  deploying on a schedule, as it does on the Mac ([#527](https://github.com/russellgordon/plantoir/issues/527)).
- Behind the scenes: a check before each release that every kind of
  diagram and interactive page really draws on the published test sites
  ([#597](https://github.com/russellgordon/plantoir/issues/597)); old build folders are cleared away
  ([#722](https://github.com/russellgordon/plantoir/issues/722)); fixes to how plantoir.app's pictures are made; and a
  handful of checks that the Mac and Windows apps behave the same way.

---

## Version 2.1

- **Archives you can browse.** Backups and archives stay two separate
  features, and archives gain what backups already have: a list, what each
  one holds, and a way to open, compare, restore or carefully delete one.
  Nothing you have today moves or is renamed.
  ([#573](https://github.com/russellgordon/plantoir/issues/573))
- **The assistant:** "Open my website" opens it rather than deploying it
  ([#688](https://github.com/russellgordon/plantoir/issues/688)).
- Behind the scenes: a move to the newer version of the engine Plantoir
  builds sites with, made only once built sites are compared before and
  after ([#512](https://github.com/russellgordon/plantoir/issues/512)).

---

## Version 2.2

- **"Revise with…" in more places.** Use the Claude and Codex desktop apps,
  not just their command-line versions
  ([#507](https://github.com/russellgordon/plantoir/issues/507)), and look into doing
  the same with GitHub Copilot's desktop app
  ([#784](https://github.com/russellgordon/plantoir/issues/784)).
- **Possibly more assistants for "Revise with…":** a look at supporting
  Google Gemini and Antigravity.
  ([#508](https://github.com/russellgordon/plantoir/issues/508))
- **Students choose their own colour scheme** on a published site
  ([#606](https://github.com/russellgordon/plantoir/issues/606)).

---

## Ideas being explored (no release yet)

- **Ready-made courses that show off the interactive features**, especially
  Ontario maths, science and Technological Education courses.
  ([#513](https://github.com/russellgordon/plantoir/issues/513))

---

## Keeping this page current

*For whoever maintains Plantoir.* This page is trimmed, not appended to:

- **When an issue closes**, leave its line where it is until the release
  ships. This page says what has shipped and what is planned, never how
  far along the work is: no "finished", "in progress" or "waiting".
  Delete the line only if a teacher would never notice the change.
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
