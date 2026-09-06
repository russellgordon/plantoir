# Start here for Windows work

**This file is the brief.** Its mirror is
[`MAC-BOOTSTRAP.md`](MAC-BOOTSTRAP.md), which briefs a session on the macOS
side — read it if you want to know what they are obliged to send you, and what
they do with what you send back. It exists so a Windows session begins the same way
every time: the same reading, the same order of work, and the same obligations
back to the mac side. Read it top to bottom before touching anything, and
follow the plan rule below — it is the only step that is not optional.

The macOS app is further ahead. Your job is to bring Windows into sync **using
the shared contracts**, not by reading Swift.

---

## 0. Outline the plan before implementing

**Read everything in section 1, then stop and write the plan out for Russell.**
Do not start changing code until he has seen it. The plan should say, briefly:

- what you found already true on this side, and what is genuinely missing;
- what you intend to do, in order, and roughly how long each part looks;
- anything in the contracts that disagrees with what this app actually does —
  **say so rather than "fixing" the app to match**, because the mac side has
  twice found the contract to be the thing that was wrong;
- anything you think should be done differently on Windows, with the reason.

Once he has agreed, **work autonomously**: implement, test, and write up as you
go, without stopping to ask permission for each step.

---

## 1. Read these, in this order

1. **`CLAUDE.md`** — the rules that override default behaviour. Rules 2, 4
   and 11 bind you as much as the mac side (11's model names are Claude
   Code's; its last two clauses — handoff as you go, documentation before
   "ready" — are unconditional).
2. **`WINDOWS-HANDOFF.md`** — and inside it, **"Where Windows actually
   stands"** is the section to read FIRST. It was pruned on 2026-08-22 once a
   code-level pass confirmed most of the old work list had shipped; those
   write-ups moved verbatim to `WINDOWS-HANDOFF-COMPLETED.md`, so this file now
   holds only what is genuinely still open, plus architecture, the config
   contract, the WSL2 background and the reasoning behind past decisions:
   long, and the section headings are enough to navigate.
3. **`contracts/README.md`**, then the eight JSON files. The coverage table
   there says what is shared and what deliberately is not.
4. **`GUI-IMPROVEMENTS.md`**, newest rows first, for what changed recently and
   why. Read it as HISTORY: where a row and a contract disagree, the contract
   is what is true now.
5. **`windows-app/PROGRESS.md`** for where this app actually stands.

---

## 2. Wire the contracts into `Plantoir.Tests` FIRST

Before changing any behaviour. `contracts/*.json` are the cases the macOS suite
already runs; running the same ones here is what makes "in sync" a fact rather
than an opinion.

Deserialise them with `[Theory]` + `MemberData`. **Never retype a sentence or a
case into a test file** — a literal in a test is the copy that keeps passing
after the product's words change, which is the whole problem these files exist
to solve. Start with `assist-wording.json` and `file-formats.json`: both are
pure data and will show you the shape.

---

## 3. Then fix what the cases fail on, in this order

1. **Deploy** — `assist-cases.json` → scenarios *"deploy with a preview
   running"* and *"deploy while that section is already busy"*. This side never
   stops the preview before deploying, and `StartDeployForAutomation()` calls
   `Deploy_Click` directly, walking past the `DeployButton.IsEnabled = !IsBusy`
   guard. **Await the stop**: a stop still running when the build starts kills
   the build, and what deploys is the site as it was before.
2. **The working-folder path bar** — `shared-rules.json` →
   `workingFolderPathBar`, and its section in `WINDOWS-HANDOFF.md`. Reported
   missing in real use. Add the right-click menu with *Show in File Explorer*
   and *Open Folder* as two separate actions, double-click to open, and a
   full-path tooltip.
3. **The approval line** — `AssistAgent.AskFirst` builds it by
   underscore-swapping the TOOL NAME ("I'd like to run **deploy section**").
   Replace it with `wording.deployApproval` followed by `wording.deployQuestion`.
   Machinery must never appear in front of a teacher.
4. **The activity trail** — `shared-rules.json` → `activityTrail.mustRecord`.
   Nothing on this side writes `%LOCALAPPDATA%\Plantoir\Logs` yet, and it
   comes before the rest of the backlog for one reason: every feature after
   it owes a line, and adding a trail to a dozen finished features costs
   several times what having it first does.
5. **The local model** — move it out of the container onto a hardware-accelerated
   host backend, and add the two thinking flags when you add a Qwen3 tier.
   See "The requirement: pick whatever makes it FASTEST on Windows". Measure
   before choosing, and measure on **integrated graphics**, not only on your
   own machine.

Items 5 onwards — the 2026-08-16 assistant batch, re-dating's two
corrections, the schedule prompt, course renaming, the assistant-choice
panel, the token dialogs — are ordered with their reasoning in
`WINDOWS-HANDOFF.md` → "Where Windows actually stands". Do not re-derive that
order; it was chosen so each item makes the next one cheaper.

---

## 4. Two things to MEASURE rather than copy

- Whether **Edge** needs the `127.0.0.1` rewrite that Safari forces. Test it by
  hand; a measured "not needed here" is a finding worth writing down.
- Which **progress markers** are yours to write. `app-rules.json` →
  `markerOrigins`: 17 come from shared Python and must match to the character;
  7 come from the launchers and deliberately differ ("Setting up this Mac"
  against "Setting up this PC"). Read your own `.ps1` files rather than copying
  the mac's list — this fails silently, with the progress bar simply stopping
  part-way.

---

## 5. Rules while you work

- **Never hand-edit the generated keys** in `contracts/` — `cardPhrasings`,
  `tools`, `milestones`. The mac overwrites them and the diff looks like
  vandalism.
- **You MAY propose an authored case** (`scenarios`, `nearMisses`,
  `promptHistory`, and the case lists in the other files). Doing so will make
  the **mac** suite fail until they implement it — that is the mechanism
  working. Name the case so it reads as a proposal and log it in
  `MAC-HANDOFF.md` under "Contract cases waiting on the mac".
- **Do not run `--write-contracts`.** That is macOS-only.
- **Anything the MAC must now do goes in `MAC-HANDOFF.md`'s "Open — what the
  mac still owes", at the TOP of that section, in the same session.** Standing
  instruction, `CLAUDE.md` rule 4. That section is the mac's to-do list from
  you, exactly as `WINDOWS-HANDOFF.md`'s numbered list is yours from them —
  both files are read top-down and abandoned partway, so an obligation that
  lives only in prose lower down is one nobody picks up. Move it to the ledger
  when it is done rather than deleting it.
- **Write every change up before moving on**, to the template at the top of
  `MAC-HANDOFF.md`: what changed, why, what you rejected, and — for anything
  measured — the numbers **with the hardware they came from**. "The Vulkan
  build was faster" cannot be acted on; "43 tok/s against 11 on CPU, Intel Iris
  Xe" can. Anything a teacher can see also gets a row in `GUI-IMPROVEMENTS.md`.
- **An affordance that lives only in a context menu is invisible to everyone
  else.** If you add a right-click menu, a double-click, a hover or a keyboard
  shortcut, it needs a handoff line **even though nothing on screen changed** —
  that is exactly how the path-bar menu went unnoticed for months.
- **Get each logical chunk looked at by something that is not the thing that
  wrote it** — the plan (after Russell has agreed it, per §0), then the
  implementation, then the fixes. `CLAUDE.md`
  rule 11 names Claude Code's models (Opus, Fable) because that is what the
  mac side runs; on your harness it means the most capable model you have,
  plus a genuinely independent review. A
  review of the finished thing arrives too late to change its shape, and the
  shape is usually what is wrong. Verify what a review claims rather than
  acting on it; reviewers are wrong often enough to matter.
- **Finish with a documentation pass, before you say it is ready.** Rule 11's
  last clause, and it is unconditional on both platforms. Grep for what you
  changed rather than trusting your memory of where it is described, and fix
  every place the change made WRONG — starting with `documentation/`, which
  is the folder nothing in the daily rhythm points at. `GUI-IMPROVEMENTS.md`
  rows and completed `TODO.md` entries are the exception: append-only records
  of what was true on their day, never edited.

---

## 6. Build and test

```powershell
cd windows-app
dotnet build Plantoir/Plantoir.csproj -c Debug
dotnet test  Plantoir.Tests/Plantoir.Tests.csproj
```

**Quit any running copy of Plantoir first**, or the build fails with
`MSB3027 … locked by "Plantoir"`, which reads like a corrupt build rather than
an open app. **You may do that without asking** — standing instruction, see
`CLAUDE.md` § "Setting up on a new machine":

```powershell
Get-Process -Name Plantoir -ErrorAction SilentlyContinue | Stop-Process -Force
```

Say that you closed it, do not close it out from under a build or deploy he can
watch happening, and leave relaunching to him.

**Standing order, added 2026-08-22: build for `x64`, not AnyCPU, so the
Desktop shortcut picks it up.** The plain `dotnet build` above lands in
`Plantoir\bin\Debug\net9.0-windows10.0.19041.0\win-x64\` — but the **"PT -
Dev" shortcut on Russell's Desktop** points at
`Plantoir\bin\x64\Debug\net9.0-windows10.0.19041.0\win-x64\Plantoir.exe`, a
sibling folder MSBuild only writes to when the `x64` platform is explicit.
Building the plain way leaves that shortcut pointing at a stale binary — he
launches "PT - Dev" expecting today's fix and gets yesterday's. Build:

```powershell
dotnet build Plantoir/Plantoir.csproj -c Debug -p:Platform=x64
```

**When you believe a round of changes is done and are about to report back —
not after every edit — rebuild this way**, the same moment macOS rule 10 in
`CLAUDE.md` names for that side. This makes the fresh build available at the
shortcut; it does **not** mean launching it — relaunching is still his call
(see above, and mac rule 10). Say plainly that the build is ready at "PT -
Dev" when you report back; a "done" that leaves that shortcut stale is not
done, the same way a stale Dock icon is not done on the mac.

**And clean up after the kill.** `Stop-Process` is not Quit, so the app's own
tidying never runs. Two things it would have done:

```powershell
# Lease files whose owner you killed — WorkLease writes them, a clean quit removes them.
Remove-Item "<working folder>\courses\.internal\activity\*.lease"

# Any plantoir-mcp you started to probe a tool over stdio. A stray one holds
# Plantoir.Core.dll open, so the NEXT build fails with the same MSB3027 the
# running app produces — and the message sends you looking for an app that is
# not there.
Get-Process -Name plantoir-mcp -ErrorAction SilentlyContinue | Stop-Process -Force
```

Say what you cleaned up. `CLAUDE.md` has the reasoning.

Tests touching **preview leases or the publish registry** belong in the
`SharedActivityState` serialized collection: they are process-wide statics and
xUnit parallelises test classes. Skipping that produces an intermittent failure
that looks exactly like a production bug and is not one.

`verify.sh` does **not** run here (bash, and it expects `docker` on PATH).
Toolchain changes made on this side have no automated gate — verify them by
driving a real publish through the app, and say so in `MAC-HANDOFF.md` so the
mac re-runs `verify.sh` after the next sync.
