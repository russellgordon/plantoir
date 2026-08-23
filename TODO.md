# To Do

Ideas and deferred work, in no particular order. Add items freely; remove
an item when it ships (finished behaviour is recorded in
[`GUI-IMPROVEMENTS.md`](GUI-IMPROVEMENTS.md), not here).

- **`CourseRenameInterfaceTests` crashes the whole unit run, intermittently —
  and it is PRE-EXISTING, not caused by the special-folders work.** Measured
  2026-08-23 on a clean `origin/dev` worktree with none of that branch's
  changes: **one crash in four full runs**, aborting the run partway
  (`Executed 419 tests` and an exit code of 65 with ZERO failed test CASES).
  The branch's own rate was about the same, one in three.

  **Two wrong diagnoses were recorded here before the right one**, and both are
  worth remembering because each looked convincing:

  1. *Busy-machine flakiness* — plausible because the interface tests host real
     SwiftUI views and adversarial-review agents were running builds at the
     time. Wrong.
  2. *An alert I had just added* — plausible because the crash report names
     `SwiftUI.AppKitDialogBridge.updateExistingAlert` during an `NSAlert` sheet
     close, and `SectionDetailView` had just grown to four `.alert` modifiers.
     Consolidating them to one made three consecutive runs pass, which read as
     confirmation. It was not: the crash came back afterwards, and then
     reproduced on `origin/dev`, which has none of it.

  The lesson is the measurement, not the guess: **a baseline needs SEVERAL runs
  on an unmodified tree, in a separate worktree.** One clean baseline run was
  taken early on and treated as exoneration; it was a coin toss landing the
  other way. And `git checkout <ref> -- path/` does NOT make a baseline — it
  leaves files the ref does not have, which is how the first attempt at this
  produced a build error instead of a measurement.

  What is actually known: `EXC_BAD_ACCESS` / SIGSEGV inside
  `AppKitDialogBridge.updateExistingAlert` → `NSSheetMoveHelper closeSheet`, in
  a suite where `SectionDetailView` and the `TaskProgressView` it embeds carry
  several alerts and a sheet between them. Both crashes named a
  `CourseRenameInterfaceTests` case, but that test hosts a sidebar ROW and is
  most likely the bystander that happened to be running.

  Where to start: `RemovalButtonTests` next door hosts its view differently and
  does not provoke it — the difference between the two is the cheapest lead.

- **Let a teacher rename a special folder from inside Plantoir** — deferred
  2026-08-23, while planning the hardening of the special folder and file names.
  Not `CourseRenamer`, which renames the course CODE and deliberately nothing
  else: this is renaming `Ontario Curriculum`, `Tasks` or `All Classes` in the
  app, so the app is the one performing the rename.

  **What exists today is thinner than it looks.** `StringListEditorView` edits
  the config LIST only — `addNewItem` appends a string, `removeItem` filters one
  out, and neither touches disk (there is no `createDirectory`, `moveItem` or
  `removeItem(at:)` anywhere under `Views/CourseSettings/`). So adding `Tests`
  to shared folders creates a config entry pointing at no folder; removing
  `Tasks` leaves the folder on disk, still full of the teacher's work, now
  unreferenced. Renaming is only possible in Obsidian or Finder — and then
  `preflight_update_course_config` in `scripts/build_site.py` discovers the new
  name and APPENDS it, with no removal path, so the config ends up listing both.

  **Why it was deferred rather than built.** The hardening work originally
  rested on recording each special folder's name in `course_config.json` so a
  check could tell DELETED from RENAMED. It cannot: the app never witnesses a
  rename, and the build's auto-discovery converts one into a duplicate. Rather
  than build the rename affordance as a dependency, the checks were rebased onto
  the FEATURE'S OUTPUT ("the coverage map found no expectations") instead of a
  folder's existence — which needs no recorded name, cannot be satisfied by an
  empty folder, and does not fire on a legitimate Obsidian rename. That made
  this a feature in its own right rather than a prerequisite, and bundling it
  would roughly have doubled the piece.

  **What it would still be worth.** It fixes the two foot-guns above (add
  creates nothing; remove orphans a folder), and it is the one place a rename
  could be observed. It needs its own design pass for what happens to wikilinks
  pointing into a renamed folder, and its own undo.

- **Let a teacher rename the `Unit` keyword** — deferred 2026-08-23, while
  planning the hardening of Plantoir's special folder and file names. Some
  teachers organise by "Module" or "Thread" rather than "Unit", and today the
  word is not a preference but a structural assumption: `_is_class_page` in
  `scripts/build_site.py:1402` matches `^Unit\s+\d+,\s*Day\s+\d+$`, and
  roughly 290 places in the Swift and 208 in the C# name it.

  **It is deferred because of the migration, not the parsing.** The parsing side
  is mechanical — one configured term threaded through the regexes and the
  title generators. The measurements that decided it (taken 2026-08-23):

  - **3,088 files** named `Unit N, Day N` under `support/example_content/`, and
    **3,143 files** containing a `Unit N, Day N` wikilink;
  - **600** skeleton files, which are generated and therefore cheap;
  - `contracts/class-planning.json` is authored end to end in Unit/Day;
  - the local assistant's routing was measured against sentences like "publish
    Unit 4" — a teacher who renamed to Thread will type "publish thread 4".

  **The split that makes it tractable.** Payloads are copied fresh at course
  creation, so a NEW course can pick its term at setup and one rewrite pass
  during the copy handles all 3,000-odd files and their wikilinks at once. That
  is cheap, contained, and delivers most of the value. Renaming an EXISTING
  course is the dangerous half: it means rewriting every wikilink pointing at
  every renamed page, across every shared folder and every section, and a
  half-finished rename leaves a broken site with no obvious way back.
  `WikiLinkRewriter` could do it, but it deserves its own design pass and its
  own undo — not a checkbox in settings.

  **Hold "Day" fixed.** A teacher who says "Thread" almost certainly still says
  "Day 3"; only the first term looks worth making configurable.

  Rejected: a display-only rename (the page would be titled "Thread 2, Day 3"
  while the file stayed `Unit 2, Day 3.md`), because Obsidian is the teacher's
  editor and they would see the old word every time they opened the vault —
  which is the place the rename was supposed to help.

- **The assistant's first turn does not wait for its warm-up** — measured
  2026-08-20, while qualifying the mac for v1.1.0. `AssistSession` sets
  `readiness = .ready` (which is all `canSend` checks) and only THEN awaits
  `warmUp`, so a teacher who types straight away queues behind the
  ~3,400-token priming request on the server's single slot. Same question,
  same model, same Mac: **1.7 s** warm against **3.1 s** racing the warm-up.

  It is an optimisation, not a fix — deliberately left out of 1.1.0 because
  changing it would have made an unchanged mac binary a behaviour change,
  and the failure Windows repaired (a first question ending in silence)
  cannot happen here: the timeout is 180 s, `AssistAgent.think()`'s catch
  surfaces every error as a message and a trail line, and the engine's
  output goes to `nullDevice` so no pipe can wedge. Windows already awaits
  its warm-up; see `MAC-HANDOFF.md` and GUI-IMPROVEMENTS row 295.

  The fix is small: hold `.ready` until the warm-up returns, or gate
  `canSend` on a separate `hasFinishedWarmUp`. **Pin it with a test** that
  a turn cannot start before the warm-up's request has come back — the
  measurement above is the evidence it is worth doing, not a substitute
  for one.

- **A mac problem report can carry nothing the engine said** — found the
  same day. `AssistServerHost` sends `llama-server`'s stdout and stderr to
  `FileHandle.nullDevice`. That is load-bearing (an unread pipe is what
  wedged the Windows server mid-request, and this is why the mac never
  had that bug) but it also means model-load errors, slot warnings and
  timing lines reach nobody — the one place they could matter is a report
  from a teacher whose assistant is misbehaving. Windows added
  `NoteServerLine` for this. Sample a BOUNDED tail into the trail rather
  than piping the firehose, and keep the no-blocking-read property that
  makes the current arrangement safe.

- **A preview's progress bar sits at 100% saying "Opening the preview…"
  for the entire build** — found 2026-08-19, while re-shooting the
  marketing screenshots; the "Building your site…" step is unreachable.

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

- **Hosting options for teachers who can't use Cloudflare or Netlify** —
  researched 2026-08-12, for the documentation above. **The most useful
  finding reframes the question: the "a folder on this PC" destination is
  already the universal answer.** Any teacher with web space of any kind —
  board-provided, a university account, cPanel shared hosting, a NAS —
  can publish to a folder and upload it however they like. No new
  integration is needed for the "my board gives me space" case, and the
  documentation should say so prominently rather than implying Netlify or
  Cloudflare are the only ways.

  That leaves two narrower cases. *Can't create an account with a US
  service* (board policy, privacy rules): the honest answer is that most
  alternatives are also US-hosted, so the realistic options are the folder
  route or a jurisdiction-specific host — **Codeberg Pages** (run by a
  German non-profit) is the notable non-US free option, though it is
  git-based like GitHub Pages. *Wants something free and simpler*:
  **Neocities** is the interesting one — free tier, ad-free, explicitly
  education-friendly, a privacy pledge including no AI training on user
  content, and, unusually for a small host, a documented HTTP API plus a
  CLI with a recursive directory push, which is exactly the shape
  Plantoir needs. Its free tier is small (~1 GB, no custom domain
  without paying) and its branding is hobbyist, so it suits a class site
  more than a department site.

  Ranked for *integration* effort, ignoring what is already built:
  Cloudflare (done), GitHub Pages (deferred above, subpath question
  open), Neocities (small, API-shaped, needs verification), Codeberg
  (git-based, EU). **Vercel stays ruled out** — its Hobby plan forbids
  commercial use in terms broad enough to cover a salaried teacher's
  work; see the earlier assessment. Low-cost rather than free, if a
  teacher will pay a little: Bunny.net storage plus CDN is about a dollar
  a month, and any cPanel host at a few dollars a month already works
  today through the folder route.

  **Caveat on the numbers:** much of the comparison material online is
  affiliate SEO content of low reliability. The Cloudflare, Netlify and
  GitHub figures cited elsewhere in this file were verified directly
  against the vendors; the Neocities and Codeberg specifics were not, and
  need checking before either is documented as a recommendation, let
  alone integrated.

- **GitHub Pages as a third publishing destination** — deferred 2026-08-12.
  Requested by CLI-era users (summer 2025). Feasible and well-bounded, but
  not now. What's known: the Quartz-docs GitHub-template route (build stock
  Quartz in Actions CI) does NOT fit — Plantoir builds patched Quartz
  v4.5.0 locally, so the right route is push-the-built-output to a branch
  Pages serves, written once in the shared `deploy.py` (git is already in
  the container). Videos are fine: GitHub Pages serves 206 Partial Content
  with proper Content-Range (verified empirically 2026-08-12), which is
  what Safari's `<video>` needs; limits are 100 MB/file (hard), ~1 GB/site,
  100 GB/month soft bandwidth — same soft cap as Netlify free. Token story
  parallels Netlify: fine-grained PAT (`contents: read/write`, one repo);
  repo creation + Pages enablement automatable via API. The UI seam already
  exists from rows 101–102 (`deploy_target` picker, milestones, launcher
  flag). Open questions, answerable with a one-session hand-run spike
  (push a built Test 3 section to a throwaway repo) BEFORE any UI work:
  (1) subpath hosting — each section would live at
  `username.github.io/<repo>`, and our patched build has never carried a
  path component in `baseUrl`; (2) Quartz's trailing-slash caveat on Pages
  (`file.html`, no redirect — mostly bites hand-written external links);
  (3) deploy latency (~a minute to go live — milestone wording should say
  "on its way", and the output needs a `.nojekyll`). Shared work: deploy.py
  plus both GUIs — write a proposal note for the mac side (like
  research/ai-assist/HISTORY.md, part 3) when picking this up.

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
    first — while the tool's own help text says “timetable.xlsx”.
  * **Which lesson lands on which day is still the model's call.**
    `plan_re_date_classes` takes matching `pages`/`meetings` lists and
    falls back to an even spread, which the description itself calls a
    starting point rather than an answer. That mapping is planning, and
    planning is where the measurements say the local model fails; it has
    not been measured on real phrasings.

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

## Assistant replies "deployed" before the deploy finishes (Windows)

Found 2026-08-19 during the deploy-during-preview adversarial review.
`MainWindow.DeployForAsync` resolves its completion source the moment
`StartDeployForAutomation()` returns — i.e. at `Deploy_Click`'s first await,
minutes before the outcome — so the assistant words `AssistWording.Deployed`
unconditionally, success or not. The mac awaits `deployAndWait()` and words
the actual result, including destination refusals. Fix is to thread the
deploy's real outcome back through `DeployForAsync` (a TaskCompletionSource
resolved in `EndPublishActivity`/failure paths, or `Deploy_Click` returning a
result the automation wrapper awaits). Contract case "deploy with a preview
running" expects `wording.deployed` only on success; today Windows says it
regardless. The scenario test is also blind to this — it injects its own
`SectionIsBusy`/deploy stubs rather than the production wiring
(`AssistScenarioTests.cs:80`), so wiring the real lambdas into a testable
seam is part of the fix.
