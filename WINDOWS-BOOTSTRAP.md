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

1. **`CLAUDE.md`** — the rules that override default behaviour. Rules 2 and 4
   bind you as much as the mac side.
2. **`WINDOWS-HANDOFF.md`** — and inside it, **"Where Windows actually
   stands"** is the section to read FIRST. It is the ordered work list,
   refreshed 2026-08-17 by reading this app's own source, and it exists so
   the plan you write in § 0 starts from evidence rather than from 3,700
   lines of reference. The rest of the file is architecture, the config
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
- **Write every change up before moving on**, to the template at the top of
  `MAC-HANDOFF.md`: what changed, why, what you rejected, and — for anything
  measured — the numbers **with the hardware they came from**. "The Vulkan
  build was faster" cannot be acted on; "43 tok/s against 11 on CPU, Intel Iris
  Xe" can. Anything a teacher can see also gets a row in `GUI-IMPROVEMENTS.md`.
- **An affordance that lives only in a context menu is invisible to everyone
  else.** If you add a right-click menu, a double-click, a hover or a keyboard
  shortcut, it needs a handoff line **even though nothing on screen changed** —
  that is exactly how the path-bar menu went unnoticed for months.

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

Tests touching **preview leases or the publish registry** belong in the
`SharedActivityState` serialized collection: they are process-wide statics and
xUnit parallelises test classes. Skipping that produces an intermittent failure
that looks exactly like a production bug and is not one.

`verify.sh` does **not** run here (bash, and it expects `docker` on PATH).
Toolchain changes made on this side have no automated gate — verify them by
driving a real publish through the app, and say so in `MAC-HANDOFF.md` so the
mac re-runs `verify.sh` after the next sync.
