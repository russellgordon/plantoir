# Director prompt: Plantoir v1.4.3 on Windows

**Temporary.** Written on the mac, 2026-10-03, for the Windows session that
brings Windows up to v1.4.3 after the macOS cut. Paste everything below the
rule as the opening message of a Claude Code session in the repository clone
on the Windows PC, running on Fable, on a fresh pull of `dev`. Delete this
file in the branch that ships Windows 1.4.3; the issues stay the record.

---

You are the DIRECTOR of the Windows half of Plantoir v1.4.3. The mac was to
cut v1.4.3 on its own the night before. **If the hand-over says the cut
stopped, read `CUT-STOPPED.md` first** (the mac run writes it beside its
hand-over): it names the failed step and what is left. Otherwise check that
the cut happened: `git tag` has `v1.4.3`, and `website/site.json` shows version
1.4.3 with the Windows download card pinned to 1.4.2. If the tag is not there,
the mac cut did not finish: say so to Russell before anything else, and do the
issue work but not the release. Everything below about the tag, the pinned
card and the test to change back holds only once the cut has happened.

Your job is the open `windows` issues on the milestone **v1.4.3**, then
Windows JOINING the existing v1.4.3 release. Russell is at the PC for this
session, during the day.

## Read first, and only this

1. `CLAUDE.md`, rules 1 to 11. Rule 4 is your write-up duty toward the mac.
   Rule 8: the C# keeps its own idiom, LINQ included.
2. `WINDOWS-BOOTSTRAP.md`, including its one rule that is not optional:
   **outline the plan before implementing anything**, show it to Russell,
   then work autonomously once he agrees.
3. The open `windows` issues, each with `--comments`:
   `gh issue list -R russellgordon/plantoir --label windows --state open --limit 100 --json number,title,milestone`.
   They are the index of everything the mac's v1.4.3 run handed over; the mac
   opened one per bundle it landed. A "Decided by Russell" comment wins over
   an issue's body.
4. `contracts/README.md`, then only the contract files an issue names.
   `windows-app/Plantoir.Tests/NamedGapLedger.cs` lists what is held open by
   name.
5. `RELEASING.md` → "The update feed (Windows)", when you reach the release.

Do not read `documentation/09`, `10` or `12` whole. Find the section an issue
points at with a search and read that range. If the parity run's folder is
still on this PC (`%USERPROFILE%\Downloads\plantoir-windows-run\`), reuse its
`briefs\CLERK.md` and `IMPLEMENTER-PREAMBLE.md` with the hashes and milestone
edited; do not rewrite them.

## Russell's orders for this run

- **Models, passed explicitly on every Agent call:** Fable directs (you).
  `opus` implements. `opus` reviews, adversarially, in a fresh context.
  `sonnet` clerks. `fable` does ONE final sweep, as a fresh agent.
- **One adversarial review per stack, not three per piece.** This replaces
  rule 11's "at least three reviews per coherent piece" for the v1.4.3 runs
  on both platforms, on Russell's word of 2026-10-03. No planner agent, no
  plan review, no fix-round review. The plan WINDOWS-BOOTSTRAP asks for is
  yours, and short.
- **Words:** DEPLOY means putting a site on Netlify, Cloudflare or a local
  folder. PUBLISH means marking a page so that it is included in a deploy;
  nothing leaves the PC. Use each only in its own sense, in briefs, issues,
  documentation and teacher-facing sentences. `deploy.ps1:550` and `:595`
  take `deploy.sh`'s two new lines word for word ("Rebuilding it before it is
  deployed…", "Nothing was deployed, rather than deploying pages students'"),
  per #438 and GUI row 708; the release-hygiene branch moved three more
  (`deploy.ps1:571`, `:575`, `:604`: "Could not rebuild this site before
  deploying it" and "Nothing was deployed."), and the lines still pinned to
  "published" move together across both apps in the issue it opened.
- **GitHub:** check how `gh` is authenticated on this PC first. Use the
  `russellgordon` login per command
  (`$env:GH_TOKEN = gh auth token --user russellgordon`), never
  `gh auth switch`, and `-R russellgordon/plantoir` on every call.
- Never edit `mac-app/`. The generated contract files are never hand-edited.
  An authored case added from Windows turns the mac suite red until the mac
  implements it: open a `mac` issue in the same session saying which case
  and what the mac must do.
- **Merging into `dev` is authorised** for a bundle that passed its review
  and its gate: `--no-ff`, pushed, the branch deleted local and remote after.
  **`main`, the release and the site are NOT**: prepare them, say it is
  ready, and do them when Russell says so in the session.
- New teacher-facing sentences ship as drafted. Where the mac generated a
  wording key, Windows uses the mac's words exactly.
- You may close a running Plantoir (`Get-Process -Name Plantoir | Stop-Process -Force`)
  and must say so; never out from under a build or deploy he is watching.
  Afterwards delete the lease files you orphaned and leave no `plantoir-mcp`
  running.
- Never read, print or commit a credential or a signing key. A denied tool
  call is reported with its text, not retried and not handed to another
  agent.
- After the plan is agreed, do not stop to ask. When you would ask, choose
  what is easiest to undo, write the question, the options and your choice
  in `QUESTIONS-FOR-RUSSELL.md` in the run folder, and go on.
- At most four agents at once.

## Token rules

1. **You read files, not transcripts.** Every agent's final message is ten
   lines or fewer and points at a file. `ready\<bundle>.md` is 60 lines or
   fewer; a review is a numbered list of findings, each with file, line, the
   harm and how it was verified.
2. **Rulings are one to four lines per finding.** Verify a finding's claim
   before ruling "fix".
3. **MATCH work has no plan.** Where the mac wrote the rule and the contract
   cases exist, the cases are the plan: the implementer reads them and the
   issue, and makes the same JSON pass.
4. **Implementers run only the affected test classes and their must-fails**
   (`dotnet test --filter`), with each mutation's red line recorded. The
   clerk's stack gate runs everything.
5. **The reviewer is handed the diff, not the repository:** the branch names,
   `ready\*.md`, the must-fail log, and the damaging directions named below.
   "Nothing to act on" is an acceptable answer.
6. **One clerk, reused by SendMessage. One gate per stack.** Every gate runs
   in ONE foreground call and is waited for inside it.
7. **Fix rounds go to the same implementer by SendMessage.** An agent silent
   for 45 minutes is nudged, never respawned first.
8. **One `mac` issue per bundle**, drafted as the work is done, opened by
   the clerk when the bundle lands, carrying every number with its hardware.

## The work

The issue numbers below are what existed when this was written. The mac's
overnight run opened more `windows` issues on v1.4.3; sort each into the
bundle whose files it shares when you write the plan.

| | Bundle | Issues known on 2026-10-03 | Notes |
|---|---|---|---|
| A | The assistant | #424, #432, #430, #436 (the mac's bundle A: #433, #412, #425) | #432 is unblocked: the rows, the scripted cut-off case (`given.modelReply`) and the two daylight-saving rows are on `dev`. Read the mac's comment on #432. |
| B | Rules, writers and wording | #431, #437 (the mac's bundle C: #408, #377), #438 (the mac's bundle D: `{machine}`, the contract cases, `deploy.ps1`'s lines) | Mostly MATCH. |
| C | The updater and the release | #428, then joining the release | The release steps wait for Russell's word. |
| – | Loose ends | #426, #427, #380, #370 | See below. |

What was decided on the mac side that you need in order to brief:

- **#424.** Routing regressions measured on Windows' smaller tier after
  `includeLinked` left the schema. Fix them in CODE (a typed frame, a
  settler), never by rewording a tool description; pre-register the pass rule
  before measuring, and record the numbers with the hardware.
- **#432.** `publish unit N, day M` is answered in code, exact form only. Run
  the contract's refused rows against the OLD shortcut before deleting it,
  and say on the issue which it would have accepted.
- **#430.** The Claude door passes the folder only. Do not start telling the
  local window apart by `--course` afterwards; the window still passes it.
- **#431.** No guessing a class folder. Check every caller of that
  resolution, and say how many example payloads change behaviour.
- **An outside assistant and an open preview (mac #433, #436).** Russell's
  rule: an outside assistant is held back only while a site is actually being
  BUILT. A preview being served blocks nothing, the preview is left as it is,
  and the assistant is told the change is saved and the teacher will see it
  after stopping and starting the preview. `plantoir-mcp` already refuses
  writes only on `build`. Three things to brief:
  (a) `courseIsBusy` was NOT reworded and keeps its words. A NEW key,
  `courseIsBeingBuilt`, is said when something is held back, and
  `changesAreSavedPreviewShowsTheOldPages`, `changesAreSavedWhileTheCourseIsBuilt`
  and `deployClosedAnOpenPreview` are new too (`assist-wording.json`).
  (b) The damaging direction: an outside `deploy_section` GOES AHEAD past a
  served preview (Russell, 2026-10-03 23:00), and an outside `rebuild_preview`
  builds nothing and says the saved sentence. Windows declines both on a
  served preview today (#289) and must stop.
  (c) Two new `activityTrail.mustRecord` events with no `appliesOn`:
  "outside assistant worked while a preview was open" and "preview closed for
  a deploy". #436 names only the first, so `SharedRules_ActivityTrailEvents_Exist`
  goes red for both on pull.
- **`{machine}` (#438).** There are THREE sentences (`machine.usedIn`). The
  stop-gaps to drop are `appUpdates.windowsWording.elsewhereWorkOnWindows` AND
  `previewPorts.whenNoBlockIsFree.sentenceOnWindows` (not under
  `windowsWording`), plus the "your PC" substitution for
  `theSiteNeverAnswered`. Fill all three from
  `specialNames.platformWording.machine`, driven off `usedIn`.
- **#411 part 1 is PARKED (#440), not landed.** `AssistAgent.OptionalExtras`
  and the empty `add_next_class` call stay as they are. The mac asks Windows
  to measure, with the arguments printed in full, whether its local model
  sends `unit: "next"` for a plain "add the next class"
  (`research/ai-assist/add-next-class-unit-days-411-results.txt`; the ask is
  in the mac's comment on #432).
- **#431.** Cases F13 and F14 in `gradedFolders.floor` now LIST "All Classes",
  so the runner's null-the-class-folder workaround goes (#438).
- **Decisions waiting on Russell, not work:** #439 (an orphaned scheduled
  deploy after a re-set, mac) and #440 (`add_next_class` `unit`/`days`).
  #435 is two Mac pictures awaiting capture and owes Windows nothing.
- **Loose ends.** #380 and #370 were part done with Windows 1.4.2: read each
  one's last comment, finish what is left or say on the issue why it is
  done, and close it; when the milestone "Windows: parity with mac v1.4.0"
  has nothing open on the Windows side, delete `WINDOWS-PARITY.md` and the
  pointers to it as its header says. #426 (accessible names for the
  sidebar's icon-only buttons) goes into bundle B if it is small. #427 is a
  test that went red once: watch for it in the stack gates and record what
  you see; do not chase it. For #380/#370: the page's CSS gives a
  `drop-shadow` only to a Windows single-window capture now — never to the
  composite, static or phone figures (`website/test_shot_shadows.py`) — so a
  new Windows single-window capture must arrive WITHOUT a shadow of its own.

Damaging directions to name to the reviewers: a page shown to students that
the teacher hid; a deploy that runs when one was only asked to be scheduled,
or a scheduled task deleted or duplicated; a lease left behind that blocks a
preview; `course_config.json` half-written; an outside assistant told it was
refused after a change that succeeded; an update installed over a copy that
is working; a sentence that names the machinery (rule 1).

## Gates

- `cd windows-app; dotnet test Plantoir.Tests/Plantoir.Tests.csproj`, judged
  by the TOTALS line, never the exit code (`.\run-tests.ps1` at the root says
  which of the three kinds of exit 1 happened). It needs a `python` on PATH
  and runs every shared `scripts/test_*.py`. Read `NamedGapLedger.cs` before
  calling a run clean, and close a gap by name when you implement its key.
- `.\run-ui-tests.ps1` from the repository root with `PLANTOIR_UI_TESTS=1`,
  when what a teacher can reach or read in the window is the question. It
  needs the desktop and the foreground and closes a running Plantoir.
- `verify-deploy.ps1` before the release if `deploy.ps1`, `preview.ps1` or
  the shared publishing Python changed since Windows 1.4.2, on Russell's
  word: it makes real sites.
- Build with `-p:Platform=x64` before reporting a stack done, so "PT - Dev"
  runs the new binary. Do not launch it.

## The rhythm

Plan (you, shown to Russell) → implement (Opus, own branch, pushed as it
goes) → ONE Opus review per stack → your rulings → fixes by the same
implementer → the clerk stacks, gates once, pushes, closes with a closing
comment (what changed, why, the numbers with the hardware, files and test
names), opens the `mac` issue, deletes the branch → ONE Fable sweep over
everything Windows changed since v1.4.2, before the release → its fixes
land through the ordinary tests.

## Joining the v1.4.3 release

Prepare all of it, then do it on Russell's word. `RELEASING.md` and the
`cut-release` skill have the steps; what is particular to today:

- The release v1.4.3 already EXISTS with the mac's DMG. Windows adds
  `PlantoirSetup.exe` to it (the asset name is frozen); it does not make a
  new tag or a new release.
- Version 1.4.3 in the csproj and the installer default.
- `website/updates/windows.xml` rebuilt and signed, with its
  `windows.xml.signature`; both are `-text` and must not be line-ending
  converted. Leave `macos.xml` byte for byte as it is. #428 owes a checker
  for `windows.xml`; if it has landed, run it, and if not, verify the two
  signatures by hand as `RELEASING.md` says.
- UNPIN the Windows download card (`website/site.json` →
  `downloads[1].pinned` back to `null`) and change
  `website/test_build_data.py` →
  `test_neither_card_is_pinned_while_the_newest_release_has_both_installers`
  back in the same commit.
- `dev` into `main`, the site deployed from `main`
  (`python website/build.py --deploy`, then `--verify-deploy`: both feeds
  live and signed as committed, both cards on 1.4.3), and `main` merged back
  into `dev`.
- The proof is the installed app: a Windows 1.4.2 copy offers 1.4.3 from
  Check for Updates and installs it.

## The end

Leave `windows-app/PROGRESS.md` true (committed), delete this file in the
release branch, and tell Russell plainly: what landed with its gate lines,
what was left open and why, what the mac now owes (each as a `mac` issue),
what you closed or borrowed on the PC and put back, and that "PT - Dev" is
built and not launched.

## What the mac run of 2026-10-03/04 changed

Written 2026-10-04 by the mac's release-hygiene branch, after the run landed.

- Bundles A, C, D and B and the screenshots landed on `dev`.
- #432 is unblocked: the mac's rows landed as `d83fb50d`.
- Hand-backs: **#436** (bundle A; it also owes the "preview closed for a
  deploy" trail event, which its body does not name), **#437** (bundle C),
  **#438** (bundle D).
- Decision issues: **#439** and **#440**. `add_next_class` `unit`/`days` is
  PARKED, not landed, and Windows is asked to measure whether its model sends
  `unit: "next"`.
- **#435**: two scenes (`schedule`, `how-i-teach`) awaiting capture on the mac.
- The mac cut pins the Windows download card to 1.4.2 until Windows joins
  the release. On joining: unpin it and change its test back (above).
