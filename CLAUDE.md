# Working on Plantoir

**Start here.** This file is the entry point for anyone — human or AI — working
in this repository. It carries the rules that override default behaviour, the
traps that cost real time, and a map of where everything else lives. Deep dives
are in [`documentation/`](documentation/README.md); nothing here repeats them.

## What this is

A teacher writes course notes as Markdown in Obsidian. This project turns that
into a website per class section, using a patched [Quartz
v4.5.0](https://github.com/jackyzha0/quartz/tree/v4.5.0) inside a container the
teacher never sees. There are three surfaces over the same toolchain:

| Surface | Where | What it is |
|---|---|---|
| Launchers | `setup.sh` / `preview.sh` / `deploy.sh` (+ `.ps1`, `.bat`) | The command line. Everything else drives these. |
| macOS app | `mac-app/` — SwiftUI, product name **Plantoir** | The GUI most teachers use. Carries the toolchain inside its bundle. |
| Windows app | `windows-app/` — .NET 9 / WinUI 3 | The same product, built by somebody who cannot read the Swift. |

Shared logic lives in `scripts/*.py` and runs identically on both platforms.
Neither app contains toolchain logic of its own: they write the same
`course_config.json` and run the same scripts.

## Rules that override default behaviour

1. **The GUI never mentions the machinery.** No "toolchain", "script",
   "Docker" or "container" in user-facing text — plain words only ("Building
   your website builder…", "Getting this Mac ready…"). That includes the
   assistant's own plumbing: no model names, parameter counts, tokens, context
   windows or GPU talk. It says "the small assistant" and "the larger
   assistant", and a test enforces it.
2. **A new behaviour goes into the SHARED test suite, or its intent goes into
   the other side's handoff. Never neither.** Every feature and every changed
   behaviour lands in one of two places, and which one is a judgement about
   portability, not about effort:
   - **It belongs in [`contracts/`](contracts/README.md)** if it is a sentence
     a teacher reads, a rule with inputs and expected outputs, or a sequence
     that must happen in order. Add the case, run it here, commit the diff —
     the other side then runs the identical case. Adding to `AssistWording` or
     to a contract's authored half is part of writing the feature, not a
     follow-up.
   - **It belongs in the other side's handoff** — `WINDOWS-HANDOFF.md` for
     work done on the mac, `MAC-HANDOFF.md` for work done on Windows — if it
     cannot be expressed as data: anything visual, anything with platform
     mechanics (WSL2, ConPTY, Colima, port leases), anything measured rather
     than asserted. Then write the INTENT and the desired behaviour, not just
     that it exists. `WINDOWS-HANDOFF.md` keeps the list of what the contract
     cannot carry; if your change is on that list, the handoff is where it goes.

   The failure this prevents is the quiet one: a behaviour that exists in one
   app, is described nowhere the other app's tests can reach, and is discovered
   months later as a difference nobody chose. **It binds both ways** — see
   rules 3 and 4 — and "the other side will notice" is not a plan: they will
   notice the sixth time a teacher reports it.
3. **Every macOS improvement is written up for Windows, as you go.** The
   Windows app is built from what this side learns, by somebody who cannot read
   the Swift or watch it being tested, so a change that exists only in Swift is
   one they will re-derive from scratch — usually after shipping the same bug
   once. A change is not finished until:
   - **`GUI-IMPROVEMENTS.md` has an entry whose "Notes for Windows port" column
     says something usable** — what to do differently, what is inherited
     unchanged, or the trap that would pass review. "Shared Python, nothing to
     mirror" is fine when true; an empty cell never is.
   - **anything architectural also has a section in
     [`WINDOWS-HANDOFF.md`](WINDOWS-HANDOFF.md)**. A log row records a decision;
     the handoff explains it well enough to implement.
   - **guidance the change made WRONG is corrected there too.** Stale advice is
     worse than none, because it gets followed.

   Say what you measured, not just what you decided — numbers travel, taste does
   not. Write down the **reasoning**, not only the behaviour: a behaviour can be
   read off the code, the reason for it cannot, and a rule whose reason has been
   lost gets "simplified" back out by the next person who reads it. Record the
   options REJECTED and why, or they get proposed again and cost the same
   afternoon twice. This applies to decisions reached by discussion as much as by
   code, and it is not contingent on being asked.
4. **Every Windows improvement is written up for the mac, as you go — the
   same rule, pointing the other way.** This is not the smaller half. Windows
   has already been first on things the mac then copied: handing `deploy_section`
   back to the app's own button was their design, and the mac ran its own
   invisible script runner for weeks afterwards because nobody wrote it down
   here. A change made on Windows is not finished until:
   - **[`MAC-HANDOFF.md`](MAC-HANDOFF.md) has an entry**, written to the
     template at the top of that file: what was done, what it fixed, and — the
     part that travels — WHY, including what was rejected. Entries are marked
     `✅ DONE` in place rather than deleted, so the ledger keeps its own
     history, and a proposed contract case is named in that file's
     "Contract cases waiting on the mac" section so a red mac suite reads as a
     request rather than as damage.
   - **`GUI-IMPROVEMENTS.md` gets a row for anything a teacher can see**, so
     the log stays the record of the product rather than of one platform.
   - **anything measured is written with its NUMBERS and the hardware they
     came from.** The mac side cannot find out what a Windows teacher's
     machine does; "the Vulkan build was faster" is not usable, "43 tok/s
     against 11 on CPU, Intel Iris Xe" is.

   **The contract has a direction, and this is the one asymmetry to know.**
   `Plantoir --write-contracts` runs on the MAC, so Windows cannot regenerate
   the derived halves — but the AUTHORED halves (`scenarios`, `nearMisses`,
   `promptHistory`, and every case list in the other files) are preserved by
   the generator and can be proposed from either side. A case added on Windows
   will make the MAC suite fail until the mac implements it, and that is the
   feature working, not a break: say so in `MAC-HANDOFF.md` so the failure is
   read as a request rather than as damage.
5. **A feature a teacher can see leaves a line on the trail — new or
   CHANGED.** Plantoir keeps a breadcrumb trail (`~/Library/Logs/Plantoir/
   activity.txt`; `%LOCALAPPDATA%\Plantoir\Logs` on Windows) so that a problem
   reported next week can be looked into without asking the teacher to
   reproduce it. Adding to it is part of writing the feature, not a follow-up:

   - **Name the event** in `ActivityTrail.Event` AND in
     [`contracts/shared-rules.json`](contracts/shared-rules.json) →
     `activityTrail.mustRecord`, with what it carries and WHY. A test pins the
     two lists against each other, so a missing event fails the suite on both
     platforms rather than being noticed months later.
   - **A changed behaviour changes its line too.** A line describing what the
     feature used to do is worse than no line, because it will be believed.
   - **Write the sentence a teacher would recognise**, not a function name:
     "started preview.sh COMP 1", never "runScript(preview.sh)".
   - **Never record what is written on a page**, and never a credential — see
     `LogRedactor`, whose rules are contract cases and which redacts on the way
     IN, so what is on disk is already safe to hand over.

   The failure this prevents has already happened here: a teacher built a
   preview, opened the assistant, asked for a report and was told there was
   nothing to report, because neither of the two things they had just done was
   among the things anybody had thought to record.

6. **Commit straight to `main`.** Do not open a feature branch first, even
   though general guidance says to branch when on the default branch. Russell
   is the sole developer here and the history is linear; a branch only adds a
   merge he has to undo. (The "for now" is his — if this project gains other
   contributors, a later instruction to branch supersedes this rather than
   contradicting it.) End every message with the `Co-Authored-By` trailer.

   **When a session is ITERATING on something — a run of changes each building
   on the last, the shape this project's work usually takes — commit as you
   go, without being asked each time.** Finish a coherent piece, get its tests
   green, rebuild, and commit it; then start the next. This is a standing
   order, not a per-session permission.

   The failure it prevents is one session's worth of unrelated work sitting in
   one working tree: forty files changed, a dozen decisions tangled together,
   and no way to read back what was done for which reason — or to undo one
   piece without unpicking the rest. A commit per piece is also the only thing
   that makes `GUI-IMPROVEMENTS.md` rows and the code agree, since each row
   then has a commit behind it.

   "A coherent piece" is one thing a teacher could notice, with its tests and
   its write-up. Not one file, and not a whole afternoon. Outside an iterative
   run — a one-off question, an experiment, something half-finished — the
   older rule still holds: ask first.

7. **Colima is shared with other projects** on this machine (Supabase local dev,
   among others). Never `colima stop` unless `docker ps -q` comes back empty.
   The app's quit path and the scripts already enforce this; keep it that way.
   The Colima VM only mounts `$HOME`, so a working folder outside the home
   directory bind-mounts as an empty folder inside the container.
8. **Swift follows the project style rules; the C# deliberately does not.**
   The Swift in `mac-app/` avoids `map`/`filter`/`reduce`, uses `@Observable`
   (never `ObservableObject`) and `// MARK: -` sections, and prefers clarity
   over concision. Those rules live in Russell's MACHINE-WIDE instructions
   (`~/.claude/CLAUDE.md`, mirrored to `~/.gemini/GEMINI.md`), not in this
   repository, because they govern his Swift everywhere rather than this
   project in particular.

   **A Windows session is therefore not missing a rule set** — decided
   2026-08-17, when it turned out that machine has no global instructions
   configured and the agent there could see only a rule about a language it
   never touches. `windows-app/` is ordinary idiomatic C#, LINQ included
   (`Where`, `Select` and friends appear about 105 times in product code
   today), and that is the intended state, not drift to be tidied up. Do not
   "bring the C# into line" with the Swift rules, and do not propose it: the
   two apps are written by different hands in different languages, and one
   house style stretched across both would buy nothing a teacher can see.
9. **Driving the interface leaves the machine as you found it — and gives the
   terminal back.** Written for **macOS sessions**, where the setup is known:
   Russell works at this Mac with the session running in iTerm. (A Windows
   session owes the same courtesy to whatever terminal it was launched from,
   by whatever means that platform offers.)

   Verifying a change by driving the real app — activating it, sending
   keystrokes through System Events, taking screenshots — is encouraged: it
   has already caught bugs that every unit test passed. But when that stretch
   of work is done, not merely at the end of the whole task, **bring the
   terminal back to the front**:

   ```bash
   osascript -e 'tell application "iTerm" to activate'
   ```

   Russell watches progress at a glance from across the room, and an app left
   frontmost hides the transcript, so he has to walk over to find out what is
   happening. The same rule covers everything else a test borrowed: put the
   system appearance back if you toggled Dark Mode, restore another
   application's state if you changed it (Obsidian's vault registry, say —
   back it up first, and check afterwards that it matches), and leave no
   half-finished edit open in the app. Say what you touched and that you put
   it back.

10. **When you think the work is done, rebuild the app before you say so.**
    Not after every edit — at the point you believe the change addresses what
    was asked and you are about to report back. That is the moment Russell goes
    to test it, and his Dock icon points at the Debug build in DerivedData
    (`~/Library/Developer/Xcode/DerivedData/Plantoir-*/Build/Products/Debug/Plantoir.app`,
    the same bundle `xcodebuild` writes), so "rebuild it" and "make it ready to
    test" are the same act:

    ```bash
    cd mac-app
    xcodegen generate     # if files were added or removed, or project.yml changed
    xcodebuild -project Plantoir.xcodeproj -scheme Plantoir -configuration Debug build
    ```

    Then say plainly that it is ready. The cost of forgetting is not a wasted
    rebuild: he launches from the Dock, tests the OLD binary, and reports
    behaviour that was fixed an hour ago — which then gets investigated as a new
    fault. A report of "done" that leaves a stale binary behind is not done.

    Three things make this go wrong quietly, all of them met in practice:

    - **`xcodebuild test` is not a build you can leave behind.** It rebuilds the
      bundle as a TEST HOST, with XCTest frameworks inside it, and it TERMINATES
      any running copy — the test host is the app. So a plain `build` has to come
      *after* the last test run, not before it, and an app that was running when
      you started testing is not running when you finish.
    - **Do not verify the bundle with `strings` or `nm` on
      `Contents/MacOS/Plantoir`.** That file is a ~59 KB stub; the code is in
      `Plantoir.debug.dylib` beside it. Checking the stub reports zero matches
      for everything — including sentences that have shipped for weeks — which
      reads exactly like a build that did not take. Check the dylib, or check
      nothing.
    - **Rebuild, then LEAVE IT QUIT — do not relaunch it for him.** The reason
      is the same one behind rule 9: `open` ACTIVATES, so relaunching makes the
      app jump in front of whatever he is doing and steals focus from the window
      he was typing in. He opens it from the Dock when he is ready, and that
      launch is his. (This reverses an earlier standing authorisation to quit
      and relaunch every time; `MAC-BOOTSTRAP.md` step 5 and the `mac-app` skill
      have been corrected to match.) Quit any copy you were driving — but only
      after a build that SUCCEEDED and with the bundle confirmed present, since
      quitting his working copy to replace it with nothing is the one genuinely
      damaging move available here.

    The [`mac-app` skill](.claude/skills/mac-app/SKILL.md) carries the rest —
    when a plain rebuild is not enough, how to clean without leaving the Dock
    icon pointing at nothing, and what to tell him he must do to see the change.
    Invoke it rather than reconstructing its steps. Toolchain edits have a
    second, separate chain to travel besides ("Editing the toolchain: two traps
    that cost real time", below); rebuilding the app is the first link of it,
    not a substitute for it.

## Setting up on a new machine

The command-line toolchain needs nothing built — the launchers download any
tools they are missing and build the Docker image locally on first run.

**macOS app.** The Xcode project file is generated, not committed, so a fresh
clone has no `.xcodeproj`: `mac-app/project.yml` is the committed source of
truth, and generated project files churn and merge badly.

```bash
brew install xcodegen
cd mac-app
./Vendor/fetch-llama.sh     # REQUIRED before generating — see below
xcodegen generate
open Plantoir.xcodeproj
```

Re-run `xcodegen generate` whenever `project.yml` changes, or when files are
added or removed (the file lists are directory-based).

`fetch-llama.sh` fetches the assistant's engine: 25 MB of llama.cpp build
output, macOS arm64, pinned to build `b10435`, deliberately not committed — this
repository ships recipes, not binaries. It is **not optional**: `project.yml`
declares `Vendor/llama` as a resource folder, so `xcodegen generate` fails with
"missing source directory" without it. Model weights are a separate matter
again; nothing in the repo or the bundle carries them, and the app downloads
them to `~/Library/Application Support/Plantoir/models` on a teacher's explicit
yes.

Debug builds are signed with a real "Apple Development" identity
(`DEVELOPMENT_TEAM` in `project.yml`) rather than ad-hoc — an ad-hoc signature
changes every rebuild, so macOS forgets permission grants (like Desktop access)
and re-asks every time. On a machine without that team's certificate, point
`DEVELOPMENT_TEAM` at your own or set `CODE_SIGN_IDENTITY: "-"` and live with
the prompts.

**Windows app.** Nothing is generated, the solution is committed, and the only
prerequisite is the **.NET 9 SDK**. It targets `net9.0-windows10.0.19041.0` /
`win-x64` and ships self-contained, Windows App SDK included, so a teacher
installs no runtime.

```powershell
cd windows-app
dotnet build Plantoir/Plantoir.csproj -c Debug
dotnet test  Plantoir.Tests/Plantoir.Tests.csproj
```

The solution also holds `PtyDriver` (the ConPTY host the app shells launchers
through) and `Plantoir.Mcp`, a standalone MCP server; `publish.ps1` builds,
bundles and signs `plantoir-mcp.exe` beside the app. **Stop any running copy
before building** — a running app holds `Plantoir.Core.dll` open and the build
fails with `MSB3027 … file is locked by: "Plantoir"`, which reads like a corrupt
build rather than the app simply being open.

**An agent working on Windows may close a running Plantoir without asking, and
should.** Standing instruction from Russell, 2026-08-18: stopping to ask about
it every time has been a hassle, and the alternative — reporting a build failure
that is only an open window — is worse. It is his own development copy, it holds
no unsaved state of its own, and he relaunches it himself when he is ready.

```powershell
Get-Process -Name Plantoir -ErrorAction SilentlyContinue | Stop-Process -Force
```

Two conditions on it, and only two. **Say that you closed it**, in the same
message as the result, so he is not left wondering where his window went. And
**do not close it out from under work he can see happening** — a build, a
preview or a deploy running in the app's own console is work he is watching;
wait for it, or ask. Relaunching afterwards is HIS, the same way it is on the
mac (rule 10): a rebuild that reopens the app steals focus from whatever he has
moved on to.

### Clean up after yourself, because a force-kill skips the app's own tidying

`Stop-Process` is not Quit. The app never runs its shutdown path, so anything
it would have released on the way out is still on disk — and the next agent, or
the next build, meets it as a fault with no obvious cause. Both of these have
already happened here, in one session:

- **Delete the lease files whose owner you killed.** Plantoir and
  `plantoir-mcp` announce what they are doing by writing
  `<COURSE>.<kind>.<pid>.lease` into
  `<working folder>/courses/.internal/activity/` — see `WorkLease`. A clean
  quit deletes them; a kill does not. They are *designed* to survive it (a
  lease whose process is gone is ignored, so nothing locks up), but a stale
  `preview` lease is still litter, and a recycled process id whose name happens
  to match is the one case the staleness check cannot see through. Remove the
  ones you orphaned:

  ```powershell
  Remove-Item "<working folder>\courses\.internal\activity\*.lease"
  ```

- **Leave no `plantoir-mcp` running.** Driving the server over stdio to check
  something — a genuinely good way to verify a tool's output without the GUI —
  leaves the process alive unless you close its stdin and wait for it to exit.
  A stray one holds `Plantoir.Core.dll` open, so the next build fails with the
  SAME `MSB3027 … file is locked by` error the running app produces. It reads
  as "the app is open" when the app is not open at all, and the fix is not the
  one the message suggests:

  ```powershell
  Get-Process -Name plantoir-mcp -ErrorAction SilentlyContinue | Stop-Process -Force
  ```

This is the Windows half of rule 9 — **driving the interface leaves the machine
as you found it**. Say what you cleaned up, the same way you say what you
closed.

## App name vs. module name

The user-facing name is **Plantoir** (bundle, binary, Dock, window title,
identifier `ca.russellgordon.Plantoir`). Internally the Swift module, source
folder and test imports are still **QuartzTeachers** — `PRODUCT_NAME: Plantoir`
plus `PRODUCT_MODULE_NAME: QuartzTeachers` in `project.yml`. Don't "fix" it:
renaming the module breaks every `@testable import QuartzTeachers` and buys
nothing a user can see. On first launch the app migrates preferences from the
old `ca.russellgordon.QuartzTeachers` domain.

## How the toolchain ships

There is no Docker Hub. The full build recipe (Dockerfile, `patches/`,
`scripts/`, `support/`, launchers) is bundled inside the app and mirrored into
each working folder's `.toolchain/`. The launchers:

- tag the image `teaching-quartz:src-<hash>`, where the hash covers every file
  in the build context — a changed recipe means a new tag, a rebuild and a
  recreated container, with no update checks anywhere;
- build with BuildKit (`docker buildx build --load`) — the legacy builder
  corrupts a layer, so don't remove that;
- name containers `teaching-quartz-<hash of pwd -P>`, one per working folder.
  The Swift side derives the identical name via POSIX `realpath` — Foundation's
  `resolvingSymlinksInPath()` strips `/private` where `pwd -P` keeps it, so
  don't swap one for the other;
- probe a free host port block per container (8081/8091/8101…), mapping to
  fixed container ports 8081–8084 for sites plus 9081–9084 for Quartz's
  live-reload websockets (`--wsPort` = port + 1000 — without it, concurrent
  previews collide on the websocket even with distinct site ports).

The image carries **wrangler**, Cloudflare's own deploy CLI, used by
`scripts/deploy.py` for the Cloudflare Pages destination (their upload protocol
— BLAKE3 hashing, short-lived JWT, batched uploads — is undocumented enough that
reimplementing it would break teachers' publishing whenever Cloudflare changed
it). It is pinned *below* 4.100 deliberately: from that version wrangler needs
Node 22, while the image ships Node 20 because that is what Quartz v4.5.0 is
known-good against. **If you raise Node, revalidate Quartz before chasing a
newer CLI.**

First-run bootstrap: if Docker isn't available, the launchers download pinned
static binaries (Colima, Lima, the Docker CLI, buildx) into `~/Library/
Application Support/Plantoir/tools` — no Homebrew, no admin rights. The image
lives inside the Colima VM's disk (`~/.colima`).

### Editing the toolchain: two traps that cost real time

A change to `scripts/`, `support/`, `patches/` or a launcher does **not** reach
a working folder until it has travelled through the app bundle. The app mirrors
its bundled copy into `.toolchain/` whenever it touches a folder, and the
launchers hash that folder to name the image. The chain is: edit → **rebuild the
app** → relaunch → next preview refreshes `.toolchain/`, changes the image tag,
recreates the container, and finally runs your change. Skip the rebuild and
everything downstream keeps running the old toolchain while looking perfectly
healthy.

**Trap 1 — Xcode may not copy your edit.** These are declared in `project.yml`
as folder references (`type: folder`), and Xcode tracks a folder reference by
the **directory**. On macOS, editing a file *inside* a directory does not change
that directory's modification time; only adding, removing or renaming an entry
does. An incremental build therefore decides the folder is unchanged and skips
the copy — the build succeeds and the app still carries the previous script.
Force it:

```bash
cd mac-app
xcodegen generate     # rewrites the project, so resources are re-copied
xcodebuild -project Plantoir.xcodeproj -scheme Plantoir -configuration Debug build
```

**Trap 2 — quit the running app first.** Xcode's Run only terminates an instance
*it* launched. If Plantoir is already running, ⌘R gives you a **second** instance
beside the first — and both rewrite `.toolchain/` whenever they touch a folder,
so a stale instance can overwrite the good scripts the new one just wrote.

```bash
osascript -e 'quit app "Plantoir"'; sleep 2
open ~/Library/Developer/Xcode/DerivedData/Plantoir-*/Build/Products/Debug/Plantoir.app
```

**Ask the app what it is actually carrying** rather than assuming — this settles
both traps in one line:

```bash
grep -c <something-from-your-edit> \
  ~/Library/Developer/Xcode/DerivedData/Plantoir-*/Build/Products/Debug/Plantoir.app/Contents/Resources/scripts/build_site.py
```

`0` means the resource copy was skipped and you are testing the old toolchain.
The same check works against a working folder's `.toolchain/`.

**A related rule for the build scripts.** Patches in `build_site.py` fall into
two groups: those inside `if full_rebuild or not output_dir.exists():` run only
when the Quartz scaffold is first copied; those in the ALWAYS section below it
run on every build. A fix that existing course folders must pick up has to go in
the ALWAYS section and be idempotent — otherwise it reaches new courses only,
and every folder built before the fix stays broken until someone passes
`--full-rebuild`.

## The local assistant

Plantoir has an on-device assistant: the teacher types "publish tomorrow's
class" and the pages are published. It is on `main` in both apps and in no
released version, because no release has been tagged yet.

One sentence explains the architecture — **the model never does anything.** It
reads a sentence and answers with the name of a function and its arguments;
every rule, safety check and file written is ordinary code that would behave
identically if the model were replaced by a dropdown menu. The deep dive is
[`documentation/10-local-ai-assistant.md`](documentation/10-local-ai-assistant.md).
Code: `mac-app/QuartzTeachers/Models/Assist/` (with `Views/Assist/`), and
`windows-app/Plantoir.Core/Assist/` (with `windows-app/Plantoir/Views/AssistWindow.xaml.cs`).

**Both macOS and Windows run the model natively on the host.** Colima on macOS
and WSL2 on Windows are Linux VMs with no access to host GPU acceleration, where
a 3,411-token prompt took **~175 seconds in a container vs a few seconds natively**.
The mac spawns the bundled `llama-server` from `Resources/llama/` with Metal.
Windows spawns the bundled `llama-server.exe` from `llama\` with Vulkan GPU
offload (`--n-gpu-layers 999`), falling back to multi-threaded CPU. Neither
runs the model in a container. Do not put the local model back in Colima or WSL2.

Four things that cost a day each if you do not know them:

- **Thinking must be off, and that takes two flags.** `--reasoning-budget 0`
  alone does NOT stop a Qwen3 chat template opening a `<think>` block; it only
  caps how long the thinking runs once opened. Same prompt, same server: budget
  alone 16.08 s and 512 completion tokens, `--reasoning off` 8.35 s and 44.
  Across the 29-probe suite the identical weights score **97% with thinking off
  and 39% with it on**. `AssistServerHost.serverArguments` passes both flags and
  `AssistModelTierTests.testThinkingIsTurnedOff` asserts both. This shipped wrong
  for days because llama.cpp parses the thinking OUT of `message.content`: the
  answer looks clean and is merely slow, so the honest check is the
  completion-token count and the clock, never the text.
- **The tier ladder was measured, and two candidates were vetoed.** There is no
  3B rung. Qwen2.5-3B inverted polarity on 9 of 10 trials of one hide request;
  Llama-3.2-3B on 10 of 10 — two unrelated families, the same sentence, both
  publishing a page the teacher asked to hide. Zero inversions is a veto rather
  than a tiebreaker, because an inversion is the one failure that reports
  success. Changing a model, quant or context size means re-running the suite.
- **Steer the model with code, not with tool descriptions.** Adding one
  clarifying sentence to `publish_pages`' description, to fix a single typo
  probe, took the promise-card score from 110/110 to 90/110 and broke three
  probes that had been perfect. A small model reads a sentence naming another
  tool as a recommendation, not a boundary. The rule went into Swift instead.
- **Adding a tool is a routing change.** The local model is shown 13 of the 20
  tools that exist (`AssistToolRunner.localTools`); an MCP client is shown 23
  (`.mcpTools`, the 20 plus three that ask for judgement about meaning). More
  choices is the classic way a router degrades.

On the mac the MCP server IS the app: `Plantoir --mcp-stdio <working-folder>`
serves the same tools to Claude Code, so there is no second binary to sign or
forget. Windows ships `plantoir-mcp.exe` instead.

## Example content and skeletons

`support/example_content/<CODE>/` holds ready-made course content, one folder
per Ontario course code (ADA1O is the template to copy; **37 codes** have
payloads today — count the folders rather than trusting a number). Each payload
is `manifest.json` plus `shared/` and `per_section/` trees, and the manifest is
the course's ENTIRE structure when a teacher pre-populates: the wizard asks no
structure questions, so a payload must be complete. Conventions the installer
relies on are in
[`.claude/skills/example-content/SKILL.md`](.claude/skills/example-content/SKILL.md)
— use that skill for any payload work rather than reasoning from scratch.

Adding a course code is pure content: drop in a payload, no code changes. The
wizard discovers it by the manifest's existence, and the payload automatically
retires that code's skeleton.

Every other Ontario code (~1,900 of them) gets a **skeleton** from
`support/skeletons/<family>/`: `families.json` maps 499 three-letter prefixes to
50 families, with a generic fallback. The skeletons are **generated, never
hand-edited** — `.claude/skills/example-content/generate_skeletons.py` holds
eleven shapes and writes ~1,950 pages; `lint_skeletons.py` is the gate. A
mistake there is a mistake in nineteen hundred courses.

## Testing — what gates what

| Change | Gate |
|---|---|
| Toolchain (launchers, `scripts/`, Dockerfile, patches) | `./verify.sh` — builds a fresh `quartz-teacher:dev-test` image from the working tree, checks the baked files match, drives the real launchers. Needs a TTY; from a non-interactive shell: `script -q /dev/null ./verify.sh` |
| macOS app | `cd mac-app && xcodebuild -project Plantoir.xcodeproj -scheme Plantoir -configuration Debug test -only-testing:QuartzTeachersTests` |
| Windows app | `cd windows-app && dotnet test Plantoir.Tests/Plantoir.Tests.csproj` |
| Assistant routing | **Nothing.** Measured by hand — see below. |

`verify.sh` **does not run on Windows** (bash, and it expects `docker` on PATH;
in the normal Windows setup Docker Engine lives inside WSL2). Toolchain changes
made on Windows have no automated gate: verify them by driving a real publish
through the app, and re-run `verify.sh` from the mac after the next sync.

**The mac suite runs its test classes one at a time, and that is load-bearing.**
The scheme sets `parallelizable = "NO"` on the test target. `PreviewLeaseTests`
and `CourseActivityTests` both reset process-wide statics
(`PreviewLeases.reset()`, `CourseActivity.reset()`) around individual methods,
so turning parallel testing on would let one class wipe the state another is
mid-assertion on — an intermittent failure that looks exactly like a
production bug and is not one. Windows hit precisely this, one run in three.
If you ever flip that setting, put those classes in a serialised group first.

**Windows tests touching process-wide state must not run in parallel.** Preview
leases and the publish registry are statics and xUnit parallelises test
*classes*, so any class touching them belongs in the shared serialized
collection (`SharedActivityState` in `ModelTests.cs`). Skipping that produces an
intermittent failure that looks exactly like a production bug and is not one.

**Assistant changes** are covered by the mac unit suite for everything provable
without a model — the tier ladder, the server flags, the tool surface, the
approval gate. Nothing gates ROUTING: whether the model still picks the right
tool is measured by hand against a local `llama-server`, with the suites and
results in [`research/ai-assist/`](research/README.md).

**Launchers are snapshots.** Working folders copy them at setup; the app
refreshes any that differ from its bundled copies. A launcher fix reaches folders
through the app bundle — rebuild the app to test it end to end.

## Where the truth lives, per kind of truth

The same rule used to be written in four places at once, and three of them
would drift — a sentence in the Swift that says it, in the test that pins it,
in the log row that specified it, and in the handoff telling Windows to copy
it. So each kind of truth now has **one** home, and everywhere else points at
it rather than restating it:

| The question | The one place that answers it |
|---|---|
| What does the assistant SAY to a teacher? | `AssistWording` in the mac app → generated into [`contracts/assist-wording.json`](contracts/assist-wording.json). |
| What must HAPPEN, and in what order? | [`contracts/assist-cases.json`](contracts/assist-cases.json) — run by both test suites. |
| What is the launcher asked to do, what is a teacher told about what they typed, which progress markers are shared? | [`contracts/app-rules.json`](contracts/app-rules.json). |
| How is a teacher's list of class dates read? | [`contracts/schedule-rules.json`](contracts/schedule-rules.json). |
| Which page titles carry numbers, what is the next class called, what happens when room is made for one? | [`contracts/class-planning.json`](contracts/class-planning.json). |
| What are the backup and archive files called, and what section number is offered next? | [`contracts/course-management.json`](contracts/course-management.json). |
| What does a scheduled deploy refuse, what does the sidebar filter show, what is stripped from console output, what counts as a curriculum expectation, what is taken out of (and kept in) a problem report, **which events every feature must record on the trail**, when the report asks about the local AI assistant, and **which local assistant a teacher may choose (and when one may be removed)**? | [`contracts/shared-rules.json`](contracts/shared-rules.json). |
| What keys does `course_config.json` carry, and what decides whether students see a page? | [`contracts/file-formats.json`](contracts/file-formats.json) — a FORMAT rather than a behaviour, and the one both apps write and the Python reads. |
| WHY is it that way, and what was rejected? | [`WINDOWS-HANDOFF.md`](WINDOWS-HANDOFF.md) for anything an implementer needs; a code comment for anything a reader of that file needs. |
| WHAT changed, WHEN, and what it cost | [`GUI-IMPROVEMENTS.md`](GUI-IMPROVEMENTS.md) — a dated log. **Append-only history, not a specification**: a row records what was true that day, and is not edited when the behaviour changes again. Never quote a row as the current wording. |
| How does the whole feature work? | [`documentation/10-local-ai-assistant.md`](documentation/10-local-ai-assistant.md). |
| What did we MEASURE? | [`research/`](research/README.md) — routing accuracy, model tiers, preview staleness. Never asserted in a test; each file states its own conditions. |
| Which rules override default behaviour? | This file. |

The practical rule that falls out of it: **if you are about to type one of the
assistant's sentences into a document or a test, don't — name it instead.**
`AssistWording.deployWasCancelled`, or `wording.deployWasCancelled` in the
contract. A quoted copy is the one that keeps passing after the product's
words change.

## The two handoff documents, and where a Windows session begins

There are exactly **two**, and they point in opposite directions:

- [`WINDOWS-HANDOFF.md`](WINDOWS-HANDOFF.md) — mac → Windows. Everything this
  side learned, written for somebody who cannot read the Swift.
- [`MAC-HANDOFF.md`](MAC-HANDOFF.md) — Windows → mac. Work that originated
  over there and needs attention here; entries are marked `✅ DONE` in place
  rather than deleted.

(The old `AI-ASSIST-HANDOFF.md` is gone: it was a record of how the assistant
was built, and it now lives in
[`research/ai-assist/HISTORY.md`](research/ai-assist/HISTORY.md).)

**Starting work on the macOS app? Open
[`MAC-BOOTSTRAP.md`](MAC-BOOTSTRAP.md)** — how to add a feature here so it
reaches Windows as data rather than as a surprise, and how to take work that
came from Windows.

**Starting work on the Windows app? Open
[`WINDOWS-BOOTSTRAP.md`](WINDOWS-BOOTSTRAP.md) first** — it is the brief for
that session: what to read, what to do in what order, and the obligations back
to this side. It also carries the one rule that is not optional there: **outline
the plan before implementing anything**, then work autonomously once it is
agreed. What follows is the same reading order, in short:

1. **This file**, for the rules that override default behaviour.
2. **[`WINDOWS-HANDOFF.md`](WINDOWS-HANDOFF.md)** — architecture, the config
   contract, and the reasoning behind the decisions. Long, and the section
   headings are enough to navigate.
3. **[`contracts/README.md`](contracts/README.md)**, then the JSON files — its coverage table says what is shared and what deliberately is not.
   These are the acceptance list: wire them into `Plantoir.Tests` and the
   assistant's behaviour is tested rather than eyeballed. **Do not retype the
   sentences or the scenarios into your test files** — deserialise them.
4. **[`GUI-IMPROVEMENTS.md`](GUI-IMPROVEMENTS.md)**, newest rows first, for
   what changed recently and why. Read it as history; where a row and the
   contract disagree, the contract is what is true now.
5. **[`windows-app/PROGRESS.md`](windows-app/PROGRESS.md)** for where that app
   actually stands.

Two known-failing cases are waiting in `contracts/assist-cases.json` — "deploy
with a preview running" and "deploy while that section is already busy" — and
they are a fair first task: implementing them fixes a real bug on that side.

## Where everything else lives

| Read this | When |
|---|---|
| [`documentation/`](documentation/README.md) | How the toolchain works, numbered 01–10: overview, image, launchers, course setup, build pipeline, Quartz customizations, deployment, config reference, mac app, local AI assistant. |
| [`GUI-IMPROVEMENTS.md`](GUI-IMPROVEMENTS.md) | The dated log of every GUI change, with a required "Notes for Windows port" column. Append here for any GUI change — and read it as HISTORY: it used to be described as "the spec", and `contracts/` is what a test should be written against now. |
| [`MAC-BOOTSTRAP.md`](MAC-BOOTSTRAP.md) | **The brief for a macOS session**: adding a feature responsibly here, and taking work that arrived from Windows. |
| [`WINDOWS-BOOTSTRAP.md`](WINDOWS-BOOTSTRAP.md) | **The brief for a Windows session**: what to read, the order of work, the rules while working, and the plan-first rule. Point a Windows agent at this file. |
| [`WINDOWS-HANDOFF.md`](WINDOWS-HANDOFF.md) | Architecture, the config contract, platform notes, and the WSL2 background — the reference a Windows session reads second, and where architectural decisions are written. |
| [`contracts/`](contracts/README.md) | **The Plantoir contract**: what the two apps must agree on, as data both test suites run — the assistant's sentences and behaviour, launcher arguments, validation wording, failure explanations, date reading, class naming, file names, progress markers, preview ports. Generated from the macOS app; never hand-edited. Its coverage table says what is deliberately NOT shared, and why. |
| [`MAC-HANDOFF.md`](MAC-HANDOFF.md) | The mirror: work that originated on Windows or in shared `scripts/` and needs the mac's attention. Ordered by STATUS — contract cases waiting, then what is still owed, then awareness, then the finished ledger — so it can be read top-down and abandoned at any point. |
| [`RELEASING.md`](RELEASING.md) | Cutting a release: signing, bundling, and the frozen asset names both platforms depend on. |
| [`website/`](website/README.md) | **plantoir.app.** The marketing site's SOURCES — a layout, a stylesheet, one file per page, and the screenshot harness. `python3 website/build.py` writes `site/`, which is what Netlify deploys: `site/` is a build output and hand-edits to it are overwritten. The release version line lives in `website/site.json`. Screenshots are captured from the real app and the real class sites by `website/shots/capture.py`, in both colour schemes. |
| [`TODO.md`](TODO.md) | Deferred work, with the research already done so picking one up is cheap. |
| [`AGENTS.md`](AGENTS.md) · `.agents/rules/` | How this file reaches an agent that reads `AGENTS.md` rather than `CLAUDE.md` — Google Antigravity, among others. `.agents/rules/*.md` is a GENERATED copy of THIS file, split into parts because Antigravity silently truncates a rule file that is too long. **After changing CLAUDE.md, run `python3 .agents/sync-rules.py`** or the copy goes stale. |
| [`research/`](research/README.md) | Measurement records the code cites as evidence — the assistant's model choices, the preview-staleness findings. Not an automated gate; each file states its own conditions. |
| [`mac-app/README.md`](mac-app/README.md) · [`windows-app/PROGRESS.md`](windows-app/PROGRESS.md) | Per-app build, test and layout notes. |
| [`README.md`](README.md) | The teacher-facing introduction. Written for them, not for us — it deliberately says nothing about the assistant until a release ships it. |
| `.claude/skills/` | Task-specific procedures: `example-content` (payloads and skeletons), `mac-app` (building so it can actually be run), `cut-release`. Invoke the skill rather than reconstructing its steps. |
