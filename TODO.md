# To Do

Ideas and deferred work, in no particular order. Add items freely; remove
an item when it ships (finished behaviour is recorded in
[`GUI-IMPROVEMENTS.md`](GUI-IMPROVEMENTS.md), not here).

- **A preview's progress bar sits at 100% saying "Opening the preview…"
  for the entire build** — found 2026-08-19, while re-shooting the
  marketing screenshots; the "Building your site…" step is unreachable.

  **✅ Fixed on Windows, 2026-08-23** (`TaskMilestones.cs`, built and tested,
  664/664 green) — see `MAC-HANDOFF.md`'s "Open — what the mac still owes"
  for the full write-up. **Not yet fixed on the mac**: the matching Swift
  edit (`TaskMilestones.swift`) was made on Windows and has not been built,
  tested, or run through `Plantoir --write-contracts` on an actual mac —
  `contracts/app-rules.json`'s `milestones.preview` is still the stale,
  pre-fix readout until that happens. Leave this item here until the mac
  side is verified.

  Two facts combine. First, `build_site.py` prints "🚀 Launching Quartz
  preview on…" (the FINAL preview milestone's marker) *before* it runs
  `npx quartz build --serve`, because build and serve are one command.
  Second, `ScriptRunner.advanceMilestones` deliberately jumps to the
  highest marker seen (so varying output never stalls the bar) — so that
  early line completes every milestone at once. From then until the site
  appears, a teacher watches a full bar captioned "Opening the preview…
  still working… (Ns)". "Building your site…" (marker "Quartz v4") and
  "Preparing components…" (marker "Installing dependencies" — a line that
  no longer prints, since the image ships `/opt/quartz/node_modules` and
  the script copies it instead of running npm) never display at all. The
  old marketing shot showing "Building your site… still working… (4s)"
  dates from when npm install still ran.

  The fix: give the final preview milestone a marker that appears when the
  server is actually up — Quartz prints a "server listening" line once
  serving — instead of the pre-build launch line. **Verify the exact
  string against a real preview's transcript before pinning it**: a marker
  that never matches leaves the bar stuck one step short, which is the
  same defect wearing the other shoe. This is contract-carried data
  (`contracts/app-rules.json` milestone tables, mirrored in the Windows
  app's `TaskMilestones.cs`), so the change means `--write-contracts`, a
  `GUI-IMPROVEMENTS.md` row, and a Windows note — which is why it was
  recorded here rather than folded into the screenshot re-shoot that
  found it. Measured while pinning this down (instrumented 20 Hz polling of the
  milestone text during real previews): every step before "Opening the
  preview…" is gone before a first sample can be taken — the launcher's
  early output arrives in one buffered chunk — and the sentence then sits
  on a FULL bar for the whole build, observed at 100+ seconds. Until the
  fix ships, the marketing `progress` shot photographs that state, because
  it is the only one the app dependably shows;
  `MarketingScreenshotTests.test4Progress` documents the dependency and
  says to re-take the shot when the fix lands. Worth knowing when fixing:
  the label shows the step whose marker has NOT yet printed, so a marker
  is read in practice as "the previous step ended", whatever the struct
  comment says — and the on-screen sentence is the accessibility VALUE of
  `taskMilestoneLabel`; its label is empty.

- **A recreated container publishes pages the teacher HID** — found
  2026-08-17, while re-shooting the marketing screenshots. Highest-severity
  item on this list: it exposes material a teacher deliberately held back.

  The Explorer's hide list works through a `filterFn` in
  `quartz.layout.ts` carrying a `CQ4T-OMIT-ANCHOR` marker. That block is
  written by `setup_course.py`'s `ensure_quartz_explorer_anchor()`, which
  patches `/opt/quartz/quartz.layout.ts` **inside the running container**.
  It is NOT in the image: `docker run --rm <image> grep -c CQ4T-OMIT-ANCHOR
  /opt/quartz/quartz.layout.ts` returns 0. `build_site.py` only overwrites
  the CONTENTS of the `omit` Set; it cannot create the filter.

  So any container recreation loses it — and recreation is the documented
  design whenever the recipe hash changes, i.e. after most toolchain
  updates. The next preview then copies a pristine scaffold, and
  `ensure_quartz_layout_anchor()` injects a bare `const omit = new Set([])`
  "to unblock the build". The Set is then populated and **nothing consumes
  it**, because there is no filter. The build succeeds, and Curriculum,
  Learning Goals, Help Sessions, Key Links and Private Notes all appear on
  the class site.

  Reproduced: `docker rm -f` the working folder's container, then rebuild
  three courses. All three came back with `filterFn` absent and two
  warnings printed (`Expected omit set not found`, `Sidebar omit anchor not
  found`) — and a site that hides nothing. Running
  `ensure_quartz_explorer_anchor()` in the container fixed all three.

  The fix, in order of value: **bake the anchored Explorer block into the
  IMAGE** (the Dockerfile already copies `patches/Explorer.tsx`, so this
  belongs beside it) so every container has it from birth and setup's patch
  becomes a harmless no-op rather than the only source of truth; make the
  build's fallback inject the real block instead of a bare Set, so existing
  containers self-heal; and **stop treating a missing filter as a
  warning** — "about to publish pages the teacher hid" should refuse to
  build, not print a line. Gated by `verify.sh`.

- **Nothing verifies that a release actually reached plantoir.app** — noted
  2026-08-14. The `cut-release` skill ends by saying the push "redeploys
  plantoir.app automatically (Netlify watches `site/`)" and stops there. No
  check that Netlify's build succeeded, and no check that the live site
  serves the new version. The download links on that page are load-bearing
  for every teacher, so a cheap post-push fetch of `https://plantoir.app`
  confirming the `version-note` line matches the tag would be worth having.

- **Container recreation can kill live previews** — noted 2026-08-11.
  Every launcher "ensures" the working folder's container, and on a
  toolchain-recipe hash or mount mismatch it recreates it (`docker rm
  -f`) — taking any live preview servers down with it. In steady state
  hashes match and this never triggers; it can bite mid-session only in
  rare cases (e.g. an app update refreshing `.toolchain` while another
  window previews). A thorough fix would make the ensure-container step
  decline (or warn) when the container hosts running previews. Low
  priority — rare, and the next preview self-heals.

- **Write the publishing documentation for plantoir.app** — noted
  2026-08-12, once Cloudflare Pages shipped. The app now offers three
  destinations and the picker's captions can only carry so much; the
  website should explain the choice properly. Worth covering: which
  destination suits whom (Netlify as the default; Cloudflare Pages for
  unmetered bandwidth and a free per-section address; a folder for
  teachers whose board gives them their own web space); how to create a
  token for each, with the exact permission Cloudflare needs (Account →
  Cloudflare Pages → Edit) and the fact that a Pages token cannot list
  its own account, which is why the app asks for an Account ID once; and
  the 25 MB per-file limit — documents, images, and slide decks are
  comfortably under it, long-form video is not, and embedding from
  YouTube or Vimeo (what most teachers do anyway) sidesteps it entirely.
  The in-app orange note says the short version; the site should say the
  rest. Screenshots of the Publishing section would help.

- **Publish stops an active preview itself** — deferred 2026-08-11. The
  idea: the Publish button stays enabled while a preview runs; clicking it
  stops this section's preview, waits for it to end, then publishes —
  saving the teacher the Stop Preview click. A first attempt was rolled
  back: pressing Publish while a preview was still *building* (not yet
  serving) left the app in an indeterminate state. The tricky moment is a
  build-phase preview — the console's ownership, the preview lease, the
  waiting-for-server state, and the publish's own needs-rebuild decision
  are all in flight at once, so stopping and handing off needs a real
  design pass rather than a stop-and-wait bolted onto `startDeploy`. Not
  urgent.

- **AI Assist — the rest of it**, updated 2026-08-14 after a full
  live-tested day on the `ai-assist` branch, since folded into `main`
  (not yet in any tagged release). The
  Windows in-app assistant is now **working end to end**: approval gate
  (deploys only), embedded model with a verified once-ever prompt cache,
  the promise card handled as deterministic commands, page edits doing
  stop-edit-offer around the app's own preview, and the whole loop moved
  to `Plantoir.Core` with tests covering every promise —
  [`research/ai-assist/HISTORY.md`](research/ai-assist/HISTORY.md) part 2 §10 is the record, and
  `MAC-HANDOFF.md` carries the mac side's pickup entry. What remains:

  **(a) The CSV reschedule — built; what is left is around the edges.**
  It shipped in the plan-then-write shape this item asked for.
  `Plantoir.Core/Assist/Timetable.cs` reads a school's sheet without
  assuming its layout — which row is the header, which column holds dates,
  and how the dates are written are all worked out from the sheet itself —
  and `ReDatePlan.cs` produces the diff table shown before anything is
  written. The MCP surface is `read_timetable` → `plan_re_date_classes` →
  `re_date_classes`, plus `roll_over_section` for a new year, all in
  `Plantoir.Mcp/PlantoirTools.cs`, with tests in
  `Plantoir.Tests/TimetableTests.cs`. §5 of the handoff records 26 classes
  re-dated against a teacher's own spreadsheet, checked by an independent
  parser. Two things are genuinely left:

  * **Only CSV comes off disk.** `TimetableSource` reads a local file as
    plain text, or exports a shared Google Sheet by link. A teacher's
    `.xlsx` sitting in Downloads is neither, so they have to export it
    first — while the tool's own help text says “timetable.xlsx”. Not
    worth fixing — teachers export to CSV without friction, and reading
    `.xlsx` off disk buys little.

  **(b) The shared activity lease, finished.** `WorkLease` files under the
  working folder now let the GUI decline a preview while the assistant
  builds, but the full both-directions story (server honouring the GUI's
  claims across every operation, and the mac app reading the same files)
  is still a shared-design item — agree the remaining shape with the mac
  side first.

  **(c) Re-measure the conversational residue.** The card's fixed shapes
  no longer touch the model, but the conversational phrasings that still
  do were last measured at 72% overall after the system-prompt rewrite
  (`research/ai-assist/promise-card-results.txt`), with undo over-salient
  and the deletion probe's decline lost. A prompt tweak plus a re-run of
  `trimmed-surface-suite.py` is a contained afternoon; every change to
  prompt or schemas retires the cache by design, so batch them.

- **A "prepare for start of year" operation, and the audit behind it** —
  deferred 2026-08-13, from a real session on the `ai-assist` branch.

  A teacher asked for "every class past Unit 1, Day 1, and everything those
  link to, into draft". Applied exactly, that rule left **32 course-level
  pages in SNC1W still published** that no class page links to at all — a
  whole unit's concepts, plus unassigned tasks and portfolio pages. The teacher
  spotted one (`Concepts/Astronomical Phenomena`, reachable only from an
  investigation that is itself unreferenced) and the rest fell out of an
  audit script.

  **The lesson: link-reachability is a weak proxy for "not yet taught."** A
  link-following rule cannot see a page no class links to, and those are
  precisely the pages a teacher has written ahead. If Plantoir grows a bulk
  start-of-year operation, base it on unit number, date, or an explicit
  teacher-facing "not yet taught" flag — not on what is reachable.

  The audit half of this shipped, as the read-only `check_section` tool in
  `Plantoir.Mcp/PlantoirTools.cs`. It cross-references a section's pages
  against every wikilink and reports two of the three groups: links on
  visible pages that lead to a hidden one (a student clicks and finds
  nothing), and pages nothing links to — still published, still listed in
  Quartz's explorer, and invisible to any rule that follows links. That
  second group is what proved the *rule* incomplete.

  What is still missing is the third group, **linked-but-missed**: pages a
  class does link to that a bulk change should have caught and did not. Its
  being empty is what proved the job complete, and `check_section` cannot
  say so today. Missing too is the bulk start-of-year operation itself —
  worth having with or without any AI, and per the lesson above it should
  key off unit number, date, or an explicit "not yet taught" flag rather
  than reachability. (`LinkGraph.cs`'s doc comment quotes 50 unreachable
  course-level pages, but for a "sample course" it does not name — a
  different measurement from the 32 above, not a contradiction of it.)

## Docker build cache is never cleared (deliberately, for now)

`docker system df` on the dev mac, 2026-08-23: 1301 build-cache entries,
14.30 GB, 14.25 GB reclaimable — a bigger number than the images that were
leaking beside it (fixed 2026-08-23, `GUI-IMPROVEMENTS.md` 352).

**Not fixed on purpose, and this is the record of why so it does not get
re-proposed:** `docker builder prune` is GLOBAL. There is no per-project or
per-tag filter, so a launcher calling it would throw away the build cache of
every other project sharing this Colima VM (Supabase, among others) — the same
constraint that shaped the image cleanup, but with no narrow form available.
Clearing it stays a by-hand developer job:

```bash
docker builder prune          # global — read the size it offers first
```

A teacher's cache is also a fraction of this: the 14 GB here came from twelve
days of toolchain edits, where a teacher builds on install and then not again.
If this is ever revisited, the thing to find out first is whether BuildKit can
be given a scoped cache per build context — a filtered prune, not a bigger
hammer.

## ✅ Done on Windows — Assistant replies "deployed" before the deploy finishes

Found 2026-08-19 during the deploy-during-preview adversarial review; fixed
2026-08-23. `SectionDetailView.Deploy_Click`'s body now returns the real
outcome sentence on every exit path — success/partial/all-failed, or
`AssistWording.DeployDidNotFinish` when the deploy never actually ran —
threaded back through `MainWindow.DeployForAsync` to `AssistAgent.RunTool`,
instead of the old unconditional `AssistWording.Deployed`. An adversarial
review agent caught a hang in the first attempt (a single shared completion
field, overwritten by a concurrent busy-branch call, orphaning the first
caller's await with no timeout); rewritten to return the outcome per call
instead, closing the race structurally. Full suite: 667/667. Windows-only
bug — the mac's `deployAndWait()` already awaited the real result, so no mac
work is owed. Full write-up: `GUI-IMPROVEMENTS.md` row 356,
`MAC-HANDOFF.md`'s "Open" section (for awareness only).

