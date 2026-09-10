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
2. **The open `windows` issues — read these FIRST, before any of the prose.**
   They are the whole of what is outstanding on this side; nothing is tracked
   in a Markdown list any more. A milestone says which release an issue is
   pinned to, and `decision` means it needs Russell to choose rather than you
   to implement.

   ```powershell
   gh issue list --repo russellgordon/plantoir --label windows --limit 100
   gh issue view <number> --repo russellgordon/plantoir
   ```

   Pass `--limit`: `gh` shows 30 by default and silently hides the rest, which
   is the failure this whole arrangement was made to stop.
3. **[`documentation/`](documentation/README.md)** — reference, not a work
   list. Architecture, the config contract, the WSL2 background and the
   reasoning behind past decisions, numbered 01–13; each issue points at the
   page that explains it. Read the page an issue names rather than all of them.
   Write-ups for work that already shipped on this port are in
   `documentation/13-windows-port-archive.md` — history, not a specification.
4. **`contracts/README.md`**, then the ten JSON files. The coverage table
   there says what is shared and what deliberately is not. Three of the ten are
   GENERATED from the mac and must never be hand-edited; the other seven are
   authored and can be corrected from either side — `contracts/README.md` says
   which is which.
5. **`GUI-IMPROVEMENTS.md`**, newest rows first, for what changed recently and
   why. Read it as HISTORY: where a row and a contract disagree, the contract
   is what is true now.
6. **`windows-app/PROGRESS.md`** for where this app actually stands.

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

## 3. Then work the issues

**There is no ordered work list here any more, and putting one back is the
thing this replaced.** The five items that used to stand in this section had
all shipped, and one of them carried its own correction — *"Built: this was
true when it was written and has not been since"* — for weeks before anybody
noticed the other four were in the same state. Ordering lives on the issue now,
in its milestone and in what it says, where closing it removes it from the
list.

Two things from that old list are worth carrying forward, because they are
reasons rather than tasks:

- **When you stop a preview before deploying, AWAIT the stop.** A stop still
  running when the build starts kills the build, and what deploys is the site
  as it was before.
- **The activity trail came first for a reason.** Every feature after it owes
  a line (`CLAUDE.md` rule 5), and retro-fitting a trail onto a dozen finished
  features costs several times what having it from the start does.

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

- **Never hand-edit the generated keys** in `contracts/`. The mac overwrites
  them and the diff looks like vandalism. **Read which they are from each
  file's own `generated.keys`**, never from a list somebody typed into prose:
  this line named three of them until 2026-09-10 and had `toolSchemas` — where
  every tool's ARGUMENTS live — missing, which is why `back_up_course`'s
  arguments changing on the mac arrived here looking like it came from nowhere.
  Only `assist-cases.json` and `app-rules.json` carry that key, because they
  are the two MIXED files and it marks the boundary; `assist-wording.json` is
  generated in full and says so in its `note`, and the seven authored files
  have no generated half to mark.
- **A red contract test is usually a HANDOVER arriving, and the issue naming it
  is often already open.** The mac opens a `windows` issue in the session it
  changes a contract (`CLAUDE.md` rule 3), so a failure in
  `AssistCardCommandTests`, `AssistSurfaceContractTests` or `ContractTests`
  usually means the mac moved and this side has not followed yet. **Read the
  open `windows` issues before filing a new one** — issue #146 was written
  because two tests failed with a bare `Assert.NotNull() Failure: Value is
  null` and were read as nobody having said anything, when #70 had named all
  five phrasings the evening before. Those assertions say where to look now.
  **But check rather than assume**, because #146 was also half RIGHT: a third
  failure in the same run, `back_up_course` gaining a `section`, had no issue
  anywhere. When you find none, say so and open one labelled `mac` — that is
  the same courtesy in reverse, not a complaint.
- **You MAY propose an authored case** (`scenarios`, `nearMisses`,
  `promptHistory`, and the case lists in the other files). Doing so will make
  the **mac** suite fail until they implement it — that is the mechanism
  working. Name the case so it reads as a proposal and open a GitHub issue
  labelled `mac` saying which case you added and what the mac has to implement
  to make it pass — otherwise the red suite over there reads as damage.
- **Do not run `--write-contracts`.** That is macOS-only.
- **Anything the MAC must now do is a GitHub issue labelled `mac`, opened in
  the same session.** Standing instruction, `CLAUDE.md` rule 4. Those issues
  are the mac's to-do list from you, exactly as the `windows` ones are yours
  from them — an obligation that lives only in prose inside a long file is one
  nobody picks up. Something the mac need only KNOW is not an issue; that goes
  in the `documentation/` page that owns its subject.

  ```powershell
  gh issue create --repo russellgordon/plantoir --label mac --milestone v1.2.0 `
    --title "..." --body-file issue-body.md
  ```

  Labels: `mac`, `windows`, `toolchain`, `assistant` for where it lands (more
  than one is fine), and `decision` when it needs Russell to choose rather than
  somebody to implement. **Plain `gh` is right here** as long as `gh auth
  status` shows one account. `MAC-BOOTSTRAP.md` prefixes every call with
  `GH_TOKEN=$(gh auth token --user russellgordon)` because THAT machine has
  several accounts and `gh auth switch` is global — it would change every other
  session running on it. Copy that form only if this machine grows a second
  account; with one account, `--user russellgordon` naming nothing configured
  fails confusingly.
- **Write every change up before moving on**, to the template in
  `CLAUDE.md` rule 4: what changed, why,
  what you rejected, and — for anything measured — the numbers **with the
  hardware they came from**. "The Vulkan
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

**Read the TOTALS line, not the exit code.** `dotnet test` exits 1 for a failing
test, for a test host that DIED underneath the run, and for a project that did
not compile; only the output tells them apart, and a dead host prints no totals
line at all. `.\run-tests.ps1` (repo root) runs the same command and says which
happened — a convenience, not a gate, so the raw command stays correct.
`documentation/12-windows-app.md` → "Reading a test run" has the measured
output of each, and why getting this wrong cost the mac a fortnight.

**There is a second suite, and it is opt-in.** `run-ui-tests.ps1` (repo root)
drives the REAL app through UI Automation, for the things `dotnet test` cannot
see: whether a control can be REACHED, whether clicking it opens anything,
whether what is RENDERED matches what the model said, whether a scrolling
panel is cut off at the bottom, and whether a view follows the course a
teacher selected rather than going stale. Run it when you change any of those
things about a view. It needs a desktop session and the foreground, takes a
few minutes, and CLOSES a running Plantoir (saying so, and not reopening it).
It touches nothing of the teacher's: `--state-dir` moves the whole state
folder for the run. See the testing table in `CLAUDE.md` and "Driving the real
interface" in `documentation/12-windows-app.md`.

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

`verify.sh` does **not** run here (bash, and it expects `docker` on PATH), but
"no automated gate" — what this said until 2026-09-07 — is no longer true.
Split it in two:

- **The shared Python IS gated here.** `dotnet test` runs every
  `scripts/test_*.py` through `PythonToolchainTests` — DISCOVERED rather than
  listed, so no count is kept in step by hand (fifteen when this was written on
  2026-09-07, eighteen later the same week) — the same files `verify.sh` runs on the
  mac, in about eight seconds with no Docker, network or credentials. Until then this side ran none of them, so a shared
  file could be broken from this machine with every gate on it green.
- **The IMAGE is not.** Nothing here builds the Docker image or checks the
  baked files. Verify those by driving a real publish through the app, and say
  so in a `mac` issue, so the mac re-runs `verify.sh` after the next sync.
  For publishing specifically that means `verify-deploy.ps1`, which
  `RELEASING.md` requires — with nothing skipped — for a release that changes
  the publishing path.
