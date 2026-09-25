# 3. The Launcher Scripts

[◀ Previous: The Docker Image](02-docker-image.md) · [Back to index](README.md) · [Next: Course Setup ▶](04-course-setup.md)

The launchers are the only files that live on the teacher's computer. Each
task ships in three flavours:

| Task | macOS | Windows entry point | Windows implementation |
|---|---|---|---|
| Set up a course | `setup.sh` | `setup.bat` | `setup.ps1` |
| Preview a section | `preview.sh` | `preview.bat` | `preview.ps1` |
| Deploy a section | `deploy.sh` | `deploy.bat` | `deploy.ps1` |

The `.sh` scripts target macOS; the `.bat`/`.ps1` pairs are their Windows
peers. (`deploy.sh` enforces this explicitly — it depends on the macOS
Keychain and exits with a pointer to `deploy.ps1` on any other OS.)

The `.bat` files are thin wrappers: they locate the `.ps1` file sitting next
to them and run it with `powershell -NoProfile -ExecutionPolicy Bypass`
(`setup.bat` prefers PowerShell 7's `pwsh` when available). All real Windows
logic is in the `.ps1` scripts, which mirror the bash versions.

All launchers share the same responsibilities, in order:

## 1. Detect the host OS

A small `_detect_host_os` function (`uname -s` → `mac`/`windows`/`linux`)
determines which command syntax to show in help text and, crucially, is
passed into the container as `--host-os` so the Python scripts can print
copy-pasteable follow-up commands in the right dialect (`./preview.sh …` vs
`.\preview.bat …`).

## 2. Resolve which image to use

Every launcher derives the image from the folder's build recipe: the tag is
`teaching-quartz:src-<hash of the recipe>`, built locally when missing.

- `--image REF` — substitute a specific already-built image (this is how
  `verify.sh` drives the launchers against its own `dev-test` build).
- `--port N` (preview only) — serve on container port N (8081–8084), so up
  to four previews per working folder can run at once — the macOS app uses
  this to preview sections side by side in separate windows. Each preview
  only ever stops a server on its own port.

  A build for publishing (`--build-only`) also stops a preview, but matches
  the section's build DIRECTORY rather than a port — it is never given one,
  and guessing the default took down other sections' previews. See
  [the build pipeline](05-build-pipeline.md#a-build-for-publishing-stops-that-sections-preview).
- `--stop` (preview only) — end this section's leftover processes and exit.
  Ending the host-side launcher does not stop the build or server it started
  inside the container: idle for a server, real CPU for a mid-flight build.
  This reclaims them, and **must never start anything** — no engine
  bootstrap, no image build, no container creation, because if nothing is
  running there is nothing to stop. The app runs it behind Stop Preview,
  navigating away, closing a window, and cancelling a publish.

  It ships the rule INTO the container over stdin rather than running a copy
  baked into the image, and that is deliberate: stop mode runs against
  whatever container is already there, which right after an upgrade was built
  from the previous image and has no such file. Naming a baked path fails
  with a message nobody sees — both callers discard this launcher's output
  and neither checks its exit code — while the build it was asked to stop
  carries on.

### One container per working folder

Each working folder gets its own container, named
`teaching-quartz-<hash>` where the hash is the first eight characters of
`pwd -P | shasum -a 256` — so two folders (this year's courses and last
year's, say) never repoint each other's mounts, and can preview at the same
time. At creation the launcher walks upward for a free block of HOST ports
(bases 8081, 8091, 8101 … 8471 — forty blocks of four site ports each, plus a
matching +1000 websocket block for Quartz's live reload; see "How a folder
finds its ports, and when it cannot" below) and maps it to
the container's fixed ports 8081–8084 and 9081–9084; `preview.sh` prints the
resolved address ("Preview will be available at: …"), which is what the app
and a terminal teacher should open. It asks the container for that mapping
twice, and if both answers are empty it says it could not find out where the
preview will be and stops before building (exit 1) — since #235 it never
announces the container's own port in its place, which is right only for the
first folder on a Mac. `--build-only` asks nothing and is never stopped there,
so a publish is unaffected. The old shared `teaching-quartz`
container is retired automatically the first time a per-folder container is
created. The macOS app stops a folder's container (a fast `docker stop`,
not a removal) when the last window using that folder closes, and on quit —
but only once nothing is using it: no launcher for that folder running on the
host, and no process inside the container beyond its idle `tail`. The
container holds no content and restarts in about a second on the next preview.
The conditions, and what happens when they are not met, are in
[`documentation/09-mac-app.md`](09-mac-app.md) → "Quitting: what it frees, what
it refuses to free, and why".
- `--context NAME` (setup only) — select a Docker context.
- `--image REF` — use a specific already-built image instead of resolving
  one from the recipe (how `verify.sh` points the launchers at its
  `dev-test` build). In `preview.sh` the image pre-parser deliberately
  scans the whole argument list, since the flag follows the course and
  section.

The scripts then ensure a container runtime is available (next section)
and build the image locally if the recipe's tag is missing — nothing is
ever pulled from a registry.

### How a folder finds its ports, and when it cannot

GitHub #280, 2026-09-25. The rule is data in
[`contracts/app-rules.json`](../contracts/app-rules.json) → `previewPorts`
(`hostBlockCount`, `hostBlockProbe`, `hostBlockCases`, `hostBlockClash`,
`whenNoBlockIsFree`); the code is one marked block, `# >>> PREVIEW PORT BLOCK
>>>`, byte-identical in `setup.sh`, `preview.sh` and `deploy.sh`, and
`scripts/test_port_blocks.py` runs it against a pretend Mac (fake `lsof` and
`docker` on PATH) under `/bin/bash` 3.2 with `set -euo pipefail`.

**What went wrong.** The launchers tried six blocks (8081 … 8131) and gave up.
A block is held by a workspace that EXISTS — running `tail -f /dev/null`,
preview or no preview; its forwarders listen on all eight ports — so six
working folders' workspaces alive on one Mac left a seventh folder unable to
preview or publish. On the development Mac six agent worktrees did it, and
`verify.sh` failed five to seven launcher checks. A teacher gets there by
using six working folders on one Mac: a workspace exists until something
removes it, nothing removes another folder's (the app only STOPS them), and
it survives a restart as a stopped workspace — so the count is folders ever
used, moved and deleted ones included (the name is a hash of the path, so a
moved folder's old workspace can never be started again).
The refusal then said "Stop another preview (or another app using ports
8081+)", which is false: stopping a preview frees nothing.

**The walk.** Forty blocks, 8081 … 8471 (websockets 9081 … 9474), the first
whose eight ports are all free. **Forty is a chosen number, not a measured
one.** The arithmetic bounds it: block 100's first port is 9081, the first
block's websocket, so anything up to 99 works; forty keeps the walk under
8888, and the websockets land only on the x1–x4 of each ten, clear of 9090,
9200 and 9229. A ceiling at all keeps the refusal reachable, so it is tested
and its sentence stays true.

A block is taken when any of its eight ports is:

- **listening on this Mac, by anybody** — read from ONE `lsof -nP -iTCP
  -sTCP:LISTEN -Fn` listing, port = what follows the last colon (`n*:8081`,
  `n127.0.0.1:8443`, `n[::1]:8443`). This check has to stay: a python server
  on 127.0.0.1:18556 and then `docker run -p 18556:8081` → **exit 0**, both
  listening. Docker cannot see a host program on a port, so this is the only
  guard against another app (Supabase holds 8443 on the development Mac, so
  block 8441 is skipped there);
- **published by another working folder's workspace, stopped ones
  included** — one `docker inspect` of every `teaching-quartz-*` workspace's
  `HostConfig.PortBindings` (0.07 s for nine). A stopped workspace listens on
  nothing, so without this a new folder takes its block and the stopped one
  cannot start again; since #220 quitting Plantoir STOPS workspaces, so that
  is an everyday path, not a corner.

**Two passes** (`previewPorts.hostBlockPasses`). The first counts all of the
above. Only when it finds nothing does a second walk count what is IN USE —
listening on this Mac, or published by a RUNNING workspace — and take a block
a stopped workspace was keeping. Without it (review of the first
implementation, 2026-09-25, measured: nine workspaces on the development Mac,
four stopped, for 20 minutes to two weeks, uptime 56 days) a block would be
kept for as long as its workspace exists — for ever, for a folder that was
moved or deleted — and neither remedy the refusal names would free anything, since both
only stop workspaces. The folder whose block was taken pays one slow preview:
its workspace is remade on free ports by the path below when it next starts.

| Measured on the development Mac, 2026-09-25 | Result |
|---|---|
| The old probe: one `lsof -iTCP:<port>` per port, 80 calls for 40 blocks | **9.84 s** — 0.123 s a call |
| One listing, parsed once | **0.12 s** (0.121–0.153 s over three readings) |
| `docker run -p P` while a HOST program listens on P (Colima) | exit 0 — Docker cannot see it |
| Workspace X on P, stopped; Y made on P; `docker start X` | X: exit 1, "Bind for 0.0.0.0:P failed: port is already allocated" |
| The real walk on this Mac, six workspaces running and three stopped (all nine blocks among 8081 … 8131) | **8141**, in 0.25 s end to end (`lsof` + `docker ps` + `docker inspect`) |
| `verify.sh` with those workspaces alive, after this change | 148 PASS, "All checks passed" (it had failed 5–7 launcher checks) |
| A first preview after a workspace is remade (#225, a teacher's Mac) | **109.3 s** cold, against seconds warm |

A listing that cannot be read (`lsof` missing or failing) counts as nothing
listening — the old probe's answer too, pinned by a test so nobody changes it
quietly; the other workspaces are still skipped, and a clash with one is
caught below.

**A clash at the moment of making.** The probe and `docker run` are two steps,
so two launchers starting together can both see a block free. A `docker run`
refused in any of `port is already allocated` (Colima), `Ports are not
available` or `address already in use` (Docker Desktop, which the launchers
use as-is when it is what works) removes the half-made workspace with a
plain `docker rm` and walks on from the NEXT block, up to the same ceiling.
Any other refusal prints Docker's words (the app's failure explanations match
on them) and keeps `say_this_folder_cannot_be_reached`.

**A stopped workspace whose block was taken.** `start_the_existing_workspace`
replaces the bare `docker start` in all three launchers. Refused for a port —
only then — it removes the workspace (plain `docker rm`) and makes it again on
free ports, and says in the console that the next preview will be slower,
about two minutes: the warm copy of the website builder lives in the
workspace's own `/tmp/quartz-builds` and goes with it. Any other refusal stops
the run with Docker's words and a sentence. Before this, `setup.sh` and
`deploy.sh` ended at the bare `docker start` under `set -e` with Docker's
words alone, and `preview.sh` (no `set -e`) carried on to fail at `docker
exec` with nothing a teacher could read. With the stopped-workspace skip in
the first pass, this path is reached when the SECOND pass has taken a stopped
workspace's block, or for workspaces made before #280.

**Never `docker rm -f` in either path.** A failed start proves nothing runs in
that workspace, but two launchers on the same folder (a scheduled publish and
a Preview) can both find it stopped; the second one's `-f` would kill the
workspace the first had just remade, mid-publish — #94's shape. Plain `rm`
refuses a running workspace, and the start path then uses it as it is.

**When all forty are taken.** Exit 1, and
`previewPorts.whenNoBlockIsFree.sentence` word for word. It names the two
remedies that are true: closing Plantoir's windows for the other folders
(the app stops a folder's workspace when its last window closes, and at quit),
and restarting the Mac (workspaces are made with no restart policy, so after a
restart they come back stopped). Both are true because of the second pass,
which takes a stopped workspace's block when nothing else is free; what is
left after both is ports other apps are listening on. A publish that cannot get a
workspace prints it too, which is why it says "a preview". The trail gets the
existing `preview did not appear` event's second launcher line,
`launcherLineWhenEveryAddressIsTaken` in `contracts/shared-rules.json`, with
the course and section (or the word `setup`). A walk that FOUND a high block
writes nothing: the announced address already carries the port.

**Known limits, written down rather than fixed:**

- `lsof` run as the teacher cannot see listeners owned by root (unchanged from
  the old probe; `netstat -an -p tcp` would). A root-owned server in the range
  is found only when Docker refuses — under Docker Desktop, which then walks
  on; under Colima, not at all.
- A STOPPED workspace restarted onto a block a HOST program took while it was
  stopped starts anyway (Colima's `docker start` succeeds, as `docker run`
  did above), and on macOS a 127.0.0.1 bind wins over `*`, so the announced
  address could show the other program — the #235 hazard. Pre-existing;
  checking the workspace's block against the listing before `docker start`
  would close it.

**What was rejected, and why:**

- **A workspace with no ports for a publish** (Russell's comment on #280: "a
  publish-only folder should not need a port block at all"). Rejected by the
  director on 2026-09-25, reversibly: the workspace is made once per folder
  and serves both, so the next Preview in that folder would have to remake it
  — a remake stops the workspace without asking what runs in it, so a
  scheduled publish of another section in progress would be killed (#94 made
  routine), and it throws away the warm website builder (109 s cold). It also
  only moves the wall: that folder's next preview meets the same ceiling.
- **A throwaway `docker run --rm` workspace per publish.** A second workspace
  cannot see the first's processes, so a publish could no longer stop a
  preview of the same section before building (`shared-rules.json`, the
  `--stop` cases) — the regression that rule exists for.
- **A per-run image tag in `verify.sh`** (the issue's first idea). The tag is
  one of at least six things concurrent runs share (the image, 78 fixed
  `/tmp/verify_*.log` paths, `$HOME/.plantoir-verify-26:27` and its workspace,
  `$HOME/.plantoir-verify-locked`, the prune fixtures); a per-run tag fixes
  one, breaks `--skip-build`, and makes every document naming
  `quartz-teacher:dev-test` wrong. `verify.sh` takes a LOCK instead
  (`/tmp/plantoir-verify-<uid>.lock`, section 0.2): a second run names the
  holder and exits 1 rather than queueing silently; a lock whose holder is gone
  is taken over; a lock with no holder written yet is held; it is let go on
  every exit, Ctrl-C and hang-up included, and only by its own run.
  `scripts/test_verify_lock.py` proves each.
- **One `lsof` per port** (the old probe) — 9.8 s for forty blocks.
- **No ceiling** — the refusal would be unreachable and untestable, and past
  block 99 the site ports sit on the first block's websockets.

### Staying up to date

The image tag is a hash of the folder's build recipe, so staleness is
structural rather than checked-for: an updated recipe (delivered by an app
update refreshing `.toolchain/` — the full recipe folder the app mirrors
into every working folder) means a new tag, a local rebuild on the next
run, and a recreated container. The hash covers only recipe files: the
`find` prunes `.git`, `courses`, `mac-app`, `node_modules`,
`.merged_output`, and `.verify-export.*`, so build outputs never steer
the tag (from the repository root they once did, at the cost of minutes
of checksumming per run). The old pull-and-compare update machinery
(`--update-image`, digest checks, the update prompt) is gone.

`verify.sh` guards the launchers themselves: among its checks, every
helper function a launcher calls must be defined in that same launcher
file — the three scripts share copied helper blocks, and a helper missing
from one of them is exit 127 at runtime on the one path nobody tested.

<a name="container-runtime-bootstrap"></a>

## 3. Container runtime bootstrap (no Docker Desktop)

Docker Desktop is deliberately not required. Every launcher carries an
`ensure_container_runtime` (bash) / `Ensure-ContainerRuntime` (PowerShell)
step that runs before the first `docker` command and removes what used to be
a manual step ("open Docker Desktop and wait for the engine to start"):

**Fast path (both platforms).** If `docker info` already succeeds — any
working engine, including Docker Desktop or Rancher Desktop if a teacher
happens to have one — the launcher uses it as-is and does nothing else.

**macOS: [Colima](https://github.com/abiosoft/colima).** Colima runs a
lightweight Linux VM with a Docker engine inside, driven entirely from the
command line. The bash launchers:

1. Use whatever is already on the machine — Homebrew installs included —
   found by `command -v`. Nothing is installed over a working tool.
2. Download whatever is missing as a pinned static binary into
   `~/Library/Application Support/Plantoir/tools/bin` (buildx into
   `~/.docker/cli-plugins`): Colima `v0.10.3`, Lima `2.2.0`, Docker CLI
   `29.7.2`, buildx `v0.36.1`. **No Homebrew and no administrator rights** —
   a teacher cannot be asked for a password they may not have.
3. Start Colima (`--vm-type vz` when the VM is first created) — sized from the Mac it is running on rather than pinned.
   `_colima_cpus` takes half the cores (floor 2, cap 6) and
   `_colima_memory_gb` a third of the RAM (floor 4 GB, cap 12 GB), so an 8 GB
   laptop gets exactly the old 2 CPU / 4 GB default and a 48 GB desktop gets
   6 CPUs and 12 GB. Deliberately not the whole machine: the teacher is using
   it while a site builds.
   What it prints differs by path: a VM being created for the first time
   prints "🚀 First start: building the virtual machine…", an existing one
   "▶️  Starting the website builder…" (before 2026-09-23, "Starting Colima…";
   GitHub #228). The app's `ScriptRunner.friendlyPhase` labels only the SECOND
   "Starting up (first time can take a few minutes)…", so that label shows on
   exactly the start that is not the first. Known and left alone: it is shown
   only when a runner has no milestones, which no launcher run lacks.
4. Poll `docker info` for up to a minute. If the VM claims to be running but
   the daemon never answers (a known Colima state after the Mac sleeps or
   shuts down uncleanly, where a plain `colima start` no-ops), force a clean
   `colima stop --force && colima start` cycle and wait again before giving
   up with manual-recovery instructions.

One consequence worth knowing: Colima's VM mounts the teacher's home
directory by default, so the working folder containing `courses/` must live
somewhere under `$HOME` (Desktop and Documents both qualify) for the bind
mount to work.

**Colima is treated as shared infrastructure.** Other Colima-based
toolchains (for example, a local Supabase development stack) may be using
the same VM on the same machine, so the launchers are deliberately polite
about it: a running engine is always used as-is, the scripts *start* Colima
when needed but never shut it down, and the only disruptive action — the
force-restart in step 4 — happens exclusively when the Docker daemon is
already dead, i.e. when no Colima-based tool is functional anyway
(containers with restart policies come back automatically afterwards).
Whichever toolchain creates the VM first determines its CPU/RAM size, so the
launchers may find a VM somebody else built. `_colima_growth_flags` handles
that under two rules: it only ever asks for MORE (a VM another toolchain
sized up keeps its size — we never shrink somebody else's), and it only does
so on a start of a STOPPED VM, because resizing recreates the VM and would
take down containers other tools are using. A VM that is already big enough
is left completely alone. A teacher who wants a different size still sets it
by hand with `colima stop && colima start --cpu N --memory M`, and the
launchers will respect anything at or above their own figure.

**The APP does stop it, and a reader will take the paragraph above for the
whole product if this is not said beside it.** The launchers never shut Colima
down as an ORDINARY act — the force-restart above is the exception, and it
fires only when the daemon is already dead. Plantoir's quit path stops it as an
ordinary act, under four conditions at once — `colima` can
be found, the socket Colima owns is there, asking THAT socket what is running
SUCCEEDED and came back empty, and no launcher for any folder is running on the
host. An empty answer that came from a FAILED question does not count, which is
the part the old check got wrong: `DOCKER_CONTEXT=default docker ps -q` exits 1
and prints nothing, and so does a daemon that did not answer. Until 2026-09-19
none of this ever ran on a teacher's Mac at all — the quit path looked for
`docker` and `colima` without saying where, and they are not on any shell's
PATH there. The whole rule, what it refuses to do and what was rejected is in
[`documentation/09-mac-app.md`](09-mac-app.md) → "Quitting: what it frees, what
it refuses to free, and why"; the standing prohibition it implements is
`CLAUDE.md` rule 7.

**Windows: Docker Engine inside WSL2.** Colima does not support Windows, but
it is not needed there — WSL2 is itself a lightweight, Microsoft-supplied
Linux VM, i.e. exactly the role Colima plays on macOS. The PowerShell
launchers:

1. Check for a native working `docker` first (fast path above).
2. Verify `wsl` exists and a distribution is installed; if not, point the
   teacher at the one-time `wsl --install` + reboot.
3. Probe for a running engine inside WSL (as the default user, then as root).
4. If the engine is absent, offer to install it right there
   (`apt-get install docker.io` as root inside the distro, then add the
   default user to the `docker` group); if merely stopped, start it with
   `service docker start` and poll until it answers.
5. Once the WSL engine is up, define a PowerShell function named `docker`
   that forwards every call through `wsl -e docker …`. Because functions
   take precedence over external commands, the rest of the script (and its
   dozens of existing `docker` call sites) work unchanged. Bind-mount paths
   are translated with `wslpath` (`C:\Users\me\courses` →
   `/mnt/c/Users/me/courses`), since the WSL engine sees Windows drives
   under `/mnt`. Published ports still appear on `localhost` thanks to
   WSL2's automatic localhost forwarding, so the preview URL is unchanged.

### Which app macOS asks about when it protects the Desktop

**Met on a second Mac running v1.2.0, 2026-09-19** ([issue
#226](https://github.com/russellgordon/plantoir/issues/226)): macOS asked to
let **iTerm** read files on the Desktop, where the working folder was. Nothing
on that Mac was misconfigured. The label is the literal truth about who
started the virtual machine, and the paragraph above about the working folder
living under `$HOME` is why the virtual machine touches those files at all.

**The mechanism.** macOS decides a Desktop / Documents / Downloads prompt by
the code identity of the **responsible process** of whoever makes the syscall,
not by the process itself. Responsibility is fixed at spawn:

| How the process started | Responsible process | Who the prompt names |
|---|---|---|
| LaunchServices (`open`, the Dock, Finder) | itself | that app |
| launchd (a login item, `brew services`) | itself | that binary |
| spawned by anything else | **inherited from the parent** | the parent's responsible app |
| …and that responsible process later exits | **itself** | that binary, by its path |

It lands on the virtual machine's host process because, with `vmType: vz` and
`mountType: virtiofs`, there is no separate file server to blame: the VM runs
*inside* `limactl hostagent` through Virtualization.framework and the host side
of the share is served from that same process. Measured on the development
Mac: `~/.colima/_lima/colima/ha.pid` and `vz.pid` hold the **same** number. So
every file a build reads or writes in the working folder is read by that one
process, and macOS attributes all of it to whoever started it.

**Measured 2026-09-19, macOS 26.6 (Darwin 25.6.0)** — twice, independently,
with `responsibility_get_pid_responsible_for_pid` and throwaway
background-only apps:

- The development Mac's hostagent (`/opt/homebrew/bin/limactl`, **PPID 1**)
  answers *responsible pid 4498* — `/Applications/iTerm.app`. Being
  daemonised and reparented to launchd did **not** break the attribution.
- A test app → `/bin/bash launcher.sh` → `nohup sleep 900 &` — the same
  two-hop, reparented shape as Plantoir → `preview.sh` → hostagent — keeps the
  **app** as the responsible process of the daemonised grandchild.
- When that app exits, the orphan becomes its **own** responsible process.
- **Relaunching does not re-adopt it.** A second instance of the same binary
  with the same bundle identifier owns its own new descendants; the old orphan
  stays itself. Once orphaned, orphaned for that VM's lifetime.

So: a virtual machine Plantoir started carries Plantoir's name — **but only
while that Plantoir is running.** Afterwards the hostagent answers for itself,
and TCC stores a non-bundled client by absolute path rather than by bundle
identifier (measured: `client_type` 1, e.g. `/usr/bin/osascript`), so the name
in play becomes `…/Application Support/Plantoir/tools/bin/limactl` — meaningless
to a teacher, and tied to a path a tool-version bump rewrites.

**How [#220](https://github.com/russellgordon/plantoir/issues/220) changes the
picture.** Until that work, Plantoir's quit path could not stop the virtual
machine on a teacher's Mac at all, which made the orphaned state above every
teacher's normal state from the second launch onward rather than a developer's
edge case. #220 is what fixes it, and it landed as its own piece; its rule, the
conditions it refuses under and what it rejected are in
[`documentation/09-mac-app.md`](09-mac-app.md) → "Quitting: what it frees, what
it refuses to free, and why", and are deliberately not restated here.

**What this piece does about it: the four sentences.** The app declared no
`NS…UsageDescription` at all, so its own prompt — the one a teacher is
genuinely meant to see, raised when Plantoir writes `.toolchain/` and the
launchers into the folder the moment it is chosen — carried macOS's bare
default and not one word from us. `mac-app/project.yml` now carries
`NSDesktopFolderUsageDescription`, `NSDocumentsFolderUsageDescription`,
`NSDownloadsFolderUsageDescription` and `NSFileProviderDomainUsageDescription`,
all four with the same sentence: a teacher only ever sees one of them, and four
near-identical strings drift apart. The file-provider key is not decoration —
it is the TCC service for iCloud Drive, Dropbox, OneDrive and Google Drive
folders, which the app explicitly supports rather than refuses ("Use This
Folder Anyway"). **This does not fix the iTerm label and must not be sold as
doing so**; it fixes the prompt that does carry Plantoir's name.

`PrivacyUsageStringsTests` pins the keys, their emptiness and rule 1 against
the built bundle — which, because the tracked `QuartzTeachers/Info.plist` is
the build's input, also catches a `project.yml` edit made without re-running
`xcodegen generate`. It proves **plist content only**.

**Removable and network volumes were considered and rejected.** Nothing in the
Swift refuses a working folder outside `$HOME`, so
`NSRemovableVolumesUsageDescription` and `NSNetworkVolumesUsageDescription` are
genuinely reachable. They are still wrong: the sentence promises a class
website, and a folder on an external drive is the one place that cannot produce
one — the virtual machine is given only the home folder, so the workspace is
refused outright with the sentence in `contracts/app-rules.json` →
`failureExplanations` (§4 below). A prompt that promises what the next screen
refuses is worse than a bare prompt. Revisit only if such a folder ever becomes
buildable.

**The pin, and why it matters.** This is *Lima's* behaviour, not a macOS
guarantee — a parent may disclaim responsibility for a child at spawn, and some
do: `/usr/bin/osascript` and the `claude` CLI hold their own path-keyed TCC
rows on the development Mac despite normally being spawned by apps. What is
measured above is Lima `2.2.0` with Colima `v0.10.3`, the versions pinned in
`setup.sh`. **Re-measure on a bump**, or this section quietly becomes false.

**What stays UNMEASURED**, and should not be written down as if it were not:

1. **What the sheet actually renders**, with a usage string and without one, on
   macOS 26. Measuring it means making a real prompt appear and leaving a TCC
   row behind for a throwaway bundle identifier.
2. **Whether a self-responsible, non-bundled helper prompts under its own name
   or is silently refused.** This decides how bad the orphaned state is: a
   confusing dialog naming `limactl` is survivable, an unexplained "Operation
   not permitted" from inside the build is the worse product outcome.
3. **Whether `tccd` re-evaluates responsibility** for a long-lived process
   whose responsible process died mid-life, or serves a cached answer for that
   pid. If it caches, the symptom appears only after the VM restarts.
4. **Whether the folder picker alone carries enough user intent** to grant the
   folder without any prompt for a non-sandboxed app.

**Rejected — a Plantoir-owned VM profile (`colima -p plantoir`).** Colima
0.10.3 does support it, so it is possible; it is still wrong on four counts.

1. **It does not buy the name it is bought for.** Per the measurements above, a
   private VM carries Plantoir's name only until the first quit; after that the
   prompt names `limactl` by path. It trades "iTerm" for something no better.
2. **It costs every teacher who already has an engine a second VM** — a second
   disk image, a second RAM reservation, and a full rebuild of
   `teaching-quartz` inside it (132 s of a cold setup, measured on the second
   Mac).
3. **It contradicts rule 7's politeness about a shared VM**, doubling a
   machine's container overhead to avoid a prompt.
4. **It is a three-launcher, two-platform change**: `--profile` on every colima
   call, `--context` on every docker call, `_colima_growth_flags`, the quit
   path's emptiness check, `verify.sh`.

And the argument for it that is only half true, written down so it is not made
again: "riding on somebody else's virtual machine caused this". A per-session
VM helps against a *stale* foreign VM only if quitting stops it — fix the quit
path (#220) and a teacher's own VM is fresh daily; leave it broken and a
Plantoir-owned profile rots exactly the same way, because uptime accumulates
either way. **Revival trigger**: a *teacher*, not a developer, reporting a
prompt that names something other than Plantoir, or a teacher's preview failing
against an engine Plantoir did not start.

**Rejected — telling the teacher in the interface that something else was
already running the builder.** Rule 1 forbids naming the machinery, and the
plain-words version ("something else on this Mac is already running the part
that builds your websites") is frightening and actionable by nobody.

**Rejected — steering new working folders away from the Desktop.**
`WorkspacePickerView` suggests the Desktop today, and that is right: the
Desktop is where a teacher can *see* their folder. `~/Documents` is protected
by the same machinery, and a folder a teacher will never find in Finder without
being taught where it is trades discoverability for one Allow click. The
picker's wording stays exactly as it is.

**One caution for anyone reproducing this.** The confirming experiment — turn a
terminal's Desktop access off in System Settings, start the engine from
Plantoir instead, and watch whose name the next prompt carries — is safe on a
machine where no work lives on the Desktop. **It must not be run on the
development Mac**, where this repository sits at
`~/Desktop/folders-that-must-exist/plantoir`: revoking the terminal's Desktop
access cuts every session's access to the checkout. And never `tccutil reset`
anything — it clears grants for every app at once, with no undo. Toggling one
app's row in System Settings is reversible and is enough.

**Nothing here is owed to Windows.** There is no TCC: Windows does not ask
before a program reads a folder the user owns. The nearest thing, Defender's
Controlled Folder Access, is off by default and *blocks* rather than prompts,
so there is no sentence to mirror and no key to add — know the mechanism,
implement nothing.

## 4. Mount-aware container lifecycle

This is the most subtle part of the launchers. Each working folder has its
own long-lived container (see "One container per working folder" above),
started as:

```bash
docker run -dit --name "teaching-quartz-${WORKDIR_ID}" \
    --mount "$(bind_mount_argument "$HOST_COURSES" /teaching/courses)" \
    --mount "$(bind_mount_argument "$BUILD_ROOT" "$BUILD_ROOT")" \
    -p "${base}-$((base + 3)):8081-8084" \
    -p "$((base + 1000))-$((base + 1003)):9081-9084" \
    "$IMAGE" tail -f /dev/null
```

where `WORKDIR_ID` is the folder hash and `base` the walked port block. Since
#280 this is made in ONE place, `create_the_workspace_on_free_ports` in the
PREVIEW PORT BLOCK the three launchers share, so the mounts and ports cannot
drift apart; a refusal naming a taken port walks on to the next block (see
"How a folder finds its ports, and when it cannot" above), and any other
prints Docker's words and `say_this_folder_cannot_be_reached`. **Why
`--mount` and not `-v`** has its own section below; the short version is that
`-v` cannot name a folder called "Comm Tech 26:27" at all.

**The launcher's refusal is broader than the app's matcher, knowingly.** The
refusal branch speaks for any failure to create the workspace other than a
taken port (which, since #280, walks on instead), while the app's explanation
(`contracts/app-rules.json` → `failureExplanations`) matches only
`bind source path does not exist`. Measured 2026-09-19: an address already
in use and a name already taken also end in exit 125 with the folder safely
inside the home folder, and a command-line user then reads advice about the
home folder that is not their trouble. (The address-in-use half is no longer
reached: since #280 it walks on to the next block.) Accepted for now because both are
transient — the free-address probe sees the virtual machine's forwarder
0.11 s after `docker run` returns, so the window is about 0.2 s — and "then
try again" is the right next step for them; narrowing the launcher's
sentence to the daemon's text is tracked as its own issue.

Every launcher inspects the existing container before using it:

1. **No `/teaching/courses` mount at all?** Recreate the container.
2. **Mounted from a different host folder than the current one?** Recreate
   it pointing at `$(pwd)/courses` (rare now that names are per-folder,
   but a moved folder keeps its old name with a stale mount).
3. **Running a different image than the recipe resolves?** Recreate — a
   container keeps running the version it was created from, so a changed
   recipe only takes effect through recreation.
4. **Missing the 9081–9084 websocket ports?** (An older container
   published only 8081; published ports cannot be changed after creation.)
   Recreate.
5. **Mount correct but not writable?** (Checked by creating and deleting a
   probe file inside the container.) **`setup.sh` and `deploy.sh` only** —
   `preview.sh` implements the other four checks but not this one, and no
   comment in it says why. Recreate. This catches macOS
   permission/ACL oddities after folder moves or restores.
6. Otherwise, start the container if stopped (`start_the_existing_workspace`
   — which, only when the start is refused because its ports were taken,
   recreates it on free ones; see "How a folder finds its ports" above), or
   reuse it as-is.

Recreating the container loses nothing of the teacher's, because their
content lives in the bind mounts — but it is not free: the warm Quartz
scaffold and `node_modules` live in the container's own `/tmp/quartz-builds`,
so the next preview is a first preview again (109.3 s measured on a teacher's
Mac for #225).

### How a folder is NAMED to the container, and why it is not `-v`

A teacher typed **"Comm Tech 26/27"** into Finder on 2026-09-02. A name
cannot hold a slash, so macOS wrote a colon instead, and the folder on disk
was `Comm Tech 26:27`. `docker run -v A:B` splits its argument on colons, so
the argument became four fields, the daemon read `/teaching/courses` as the
MODE, and first-run setup died with `invalid mode: /teaching/courses` —
**after 147 seconds** of downloading tools, starting the virtual machine and
building the website builder. The teacher saw that one line of daemon text
and nothing else. GitHub issue #221; every Ontario teacher writes the school
year as "26/27", and it was the first folder this one had ever made.

All three launchers now build the argument with one shared helper,
`bind_mount_argument`, carried identically between `# >>> CONTAINER MOUNT
BLOCK >>>` markers and pinned by `scripts/test_container_mount.sh`:

```bash
type=bind,"source=<host path>","target=<container path>"
```

`--mount` takes key=value fields parsed as **one CSV record**, so a field may
be quoted (RFC 4180) and a literal `"` inside it doubled. The quote must open
the **field** — `"source=/x"` — and never the value: `source="/x"` is refused
for *every* path, ordinary ones included, which is the one trap in this shape
and the reason it cannot be discovered late.

**Measured**, 2026-09-19, against the shared Colima VM (virtiofs), on both the
pinned Docker CLI 29.7.2 and Homebrew's 29.7.1, under `/bin/bash` 3.2.57 and
under zsh, by creating each folder and running `ls /teaching/courses` inside
the container:

| Folder name | `-v` | plain `--mount` | field-quoted `--mount` |
|---|---|---|---|
| `plain 26-27` | OK | OK | **OK** |
| `Comm Tech 26:27` | **125** `invalid mode` | OK | **OK** |
| `Comm Tech 26,27` | OK | **125** `must be a key=value pair` | **OK** |
| `Say "hi" 26` | OK | **125** `bare " in non-quoted-field` | **OK** |
| `Both "q", and 26:27` | **125** | **125** | **OK** |
| `type=bind,source=/etc 26` | OK | **125** | **OK** — and mounts the real folder, not `/etc` |
| backslash, `$`, `;`, `=`, leading dash, trailing space, emoji, NFC/NFD accents, tab, bare CR, bare LF | OK | OK | **OK** |
| a name holding **CR immediately followed by LF** | **OK** | — | **125** |

So: **every name a teacher can type in Finder**, and that claim is worth
stating exactly rather than rounding up to "every name macOS can store",
because the last row is a real regression. Go's `encoding/csv` rewrites CR LF
to LF inside a quoted field, so the daemon then looks for a path that does not
exist and refuses. It is accepted rather than worked around: Finder's rename
field will not accept a Return, so making such a name takes a script or a
restored archive, and the failure is loud (exit 125, and the launcher's own
sentence) rather than silent. If a folder with the rewritten name also exists,
the wrong folder would mount — which is the part that would be unforgivable to
leave undocumented.

**What was REJECTED, and why:**

| Rejected | Why |
|---|---|
| A plain, unquoted `--mount` | Measured: strictly WORSE than `-v`, not better. It trades the colon failure for a comma failure and a double-quote failure, and "Comm Tech 26,27" is just as ordinary a name. It would have looked fixed until the day it wasn't. |
| Refusing colon names in the app | Refuses "26/27", the single commonest thing a teacher would type, and fixes nothing for the command line or for a publish launchd runs overnight. After the table above there is nothing left to refuse, and a validator with an empty true-set is a sentence that will eventually be shown for the wrong reason. |
| Keeping `-v` and mounting a colon-free symlink | Gives the folder a second name. `.Source` would then be the link's path, so `CURRENT_MOUNT_SRC != HOST_COURSES` on every run and every launcher would recreate the container every time — and the link's target still has the colon, so nothing is solved, only hidden. |
| Percent-encoding or backslash-escaping the source | `-v`'s parser has no escape at all; the colon count is what it splits on. |
| Mounting the working folder's PARENT | Same syntax, same split, and it would expose every sibling folder on the Desktop to the container. |
| Fixing only `setup.sh`, where it was seen to fail | `preview.sh` and `deploy.sh` create the container too, whichever runs first. A teacher whose setup succeeded would fail on their first preview instead. |
| `mkdir -p "$HOST_COURSES"` ahead of the run, to cover the behaviour change below | It puts a bare `mkdir` in front of the `docker run` and makes the sentence unreachable for the case it is FOR: a folder renamed or on a disconnected disk fails at the `mkdir`, and under `set -e` the teacher gets `mkdir: …: No such file or directory` and nothing else. It would also silently re-make the folder, empty, at a path nobody is looking at any more. A `test -d` and the sentence instead. |

**One behaviour genuinely changes, and it is bigger than it first looks.**
`-v` with a source the VM had never seen silently CREATED the directory
*inside the VM* and started; `--mount` refuses it (`bind source path does not
exist`). That is why `ensure_build_root` runs before the container is created
and why the courses folder is checked first. Nothing ordinary reaches that
check: `setup.sh` makes `courses/` itself, `preview.sh` has already refused
when `course_config.json` is missing and `deploy.sh` when the course folder is.

**A working folder OUTSIDE the home folder is the case that changes for a real
teacher.** The Colima VM mounts only `$HOME`, so an external drive, a second
volume or `/Users/Shared` is not there to be handed over:

| | before (`-v`) | after (quoted `--mount`) |
|---|---|---|
| outside `$HOME`, path the VM has never been given | rc=0, container starts, `/teaching/courses` is **EMPTY**, the build "succeeds" and produces **nothing** | **rc=125**, `bind source path does not exist`, and the launcher's own sentence |

**Measured 2026-09-19**, virtiofs, on three brand-new random paths under
`/private/tmp` and once under `/Users/Shared`, `--mount` FIRST every time:
125, 125, 125, 125; `-v` on the same paths afterwards: 0, 0, 0 — and the
folder inside the container was empty even though the host folder held a
marker file. **Order is everything in this measurement**: once `-v` has
created the path inside the VM, a later `--mount` to the same path succeeds
(and still mounts empty). An earlier round of this work measured `-v` first
and concluded the two forms behaved alike; they do not, and the write-ups
that said so have been corrected.

So this is not a regression to be apologised for. A teacher in that state was
already building nothing; they now find out, in one sentence, on the first
run. It is also why the refusal branch says something DIFFERENT from the
missing-folder branch — see below.

**Two situations, two sentences.** The launchers hold both, side by side in
the shared block:

- the folder is **not there** (`test -d` fails): *"Check that it has not been
  moved or renamed, then try again."* No contract case, because this check
  happens before anything is asked of the builder, so there is no output for
  the app to recognise.
- the folder **is** there and the workspace was still refused: *"Check that it
  is inside your home folder — on your Desktop or in Documents, for example —
  and not on an external drive or in a shared location, then try again."*
  This one IS a contract case, matched on `bind source path does not exist`,
  so the app's `FailureExplainer` says the same words — a teacher sees one
  sentence whether they are in Plantoir or at the command line.

Two rarer causes share that second output and are deliberately not named in
it: a folder that moved between the `test -d` and the moment the workspace is
made, and a builds folder that could not be created at all
(`ensure_build_root` swallows its own failure by design, so a full disk lands
here). Naming three causes in one sentence would help nobody; the commonest
one is named and the raw output is shown underneath it.

**No container is recreated for this change.** Measured: a container made with
`-v` and one made with `--mount` are indistinguishable in `.Mounts` (they
differ only in `HostConfig.Binds` vs `HostConfig.Mounts`, which nothing in this
repository reads), so an updated launcher accepts an existing container and an
old launcher accepts a new one. A doubled quote in the argument comes back
un-doubled in `.Source`, so the launchers' own `CURRENT_MOUNT_SRC` comparison
still compares like with like. A teacher's first run after the update recreates
anyway, because the launchers are inside the build context and a launcher edit
mints a new image tag — but that is the ordinary upgrade path and costs about
1.5 s of cached rebuild, not this change.

**What is gated.** `scripts/test_container_mount.sh` (pure shell, no Docker)
pins the block, the argument it produces for each name in the table, that all
three launchers actually USE it, and that the launcher's sentence is word for
word the contract's. `verify.sh` section **6e** builds a real site from a real
folder called `.plantoir-verify-26:27`, in a container it removes **before**
and after — before, because the launcher keeps a container it is happy with, so
a second run would never call `docker run` and would pass having tested
nothing. And a real `./preview.sh EXC2O 1` was SERVED from
`~/plantoir-scratch-C/Comm Tech 26:27` by hand on 2026-09-19: the server
reached `Started a Quartz server listening`, and `curl` fetched a 29,561-byte
page titled "Grade 10 Example Course, Section 1" off the host port. The colon
never crosses the mount — `pwd -P` inside the container is
`/teaching/courses/<CODE>` — so nothing in the image can see the folder's name
at all.

**Nothing to mirror on Windows.** There is no `docker` in `setup.ps1`,
`preview.ps1` or `deploy.ps1` (measured: zero occurrences in each), a Windows
path cannot contain a colon, and the native runtime replaced the container
there in 2026-08. The mount form is mac-only machinery and is deliberately
prose in `contracts/shared-rules.json` →
`buildOutputLocation.containerRecreate.mountForm` rather than a runnable
contract case: a shared case Windows cannot implement becomes a named gap
nobody can ever close. The one thing that side does owe is the new
`failureExplanations` case.

## 5. Per-task specifics

### `setup.sh`

- Creates `courses/` and `courses/_backups/` on the host if missing, and
  relaxes permissions (`chmod -R u+rwX,go+rwX`) so the container user can
  write regardless of UID mismatches.
- Captures the host timezone offset (`date +%z`) into `HOST_TZ_OFFSET` so
  frontmatter timestamps written inside the container match the teacher's
  wall clock ([why this matters](05-build-pipeline.md#dates-drive-everything)).
- If `--no-backup` is being passed through, demands explicit confirmation
  first.
- Finally: `docker exec -it "teaching-quartz-${WORKDIR_ID}" python3 /opt/scripts/setup_course.py …`

### `preview.sh`

- Takes `COURSE SECTION` as positional arguments, plus pass-through flags
  understood by `build_site.py`: `--include-social-media-previews`,
  `--force-npm-install`, `--full-rebuild`, `--build-only` — plus its own
  `--port N` (container port 8081–8084, which IS passed on to `build_site.py`),
  `--image REF`, `--non-interactive` (nobody is watching this build; refuse
  rather than ask — see `deploy.sh` below, where the flag is explained in
  full), and `--stop`. The last three are handled entirely by the launcher and
  never reach `build_site.py`.
- Checks host-side that the course is set up (`course_config.json` exists)
  and whether the section folder is there (it only warns if it is not). The
  requested section is checked against `section_numbers` by `build_site.py`,
  not by the launcher: `build_section_site` first looks for the
  `section<N>` folder and then calls `validate_requested_section`, and either
  way it prints what is wrong and builds nothing. It does NOT refuse in the
  sense of an exit code — `main()` returns normally, so the launcher exits 0.
  In practice a typo like section `2` in a course with sections `1,3,4` meets
  the folder check first ("Section folder 'section2' not found"). This is a
  command-line path only: the app offers only sections that exist.

  **`preview.sh` used to carry its own copy of that check, and it never
  ran.** It fed a heredoc to `docker exec … python3 -` WITHOUT `-i`, so
  docker discarded stdin, the program never arrived, and the command exited
  0 with no output (measured against a live container: without `-i`, rc 0
  and empty output; with `-i`, the expected list — and the same inside a
  pty, which is how the app runs launchers). The "allowed" list was
  therefore always empty and every preview on every Mac printed "Could not
  read allowed sections from course_config.json (continuing)", from
  2025-08-11 until it was removed on 2026-09-23 (GitHub #224). Removed
  rather than repaired: adding `-i` would have turned on a second copy of a
  check the build already makes, plus a new refusal sentence and contract
  case, for a path only a developer uses. `verify.sh` now fails if any
  launcher feeds a program to `docker exec` without `-i`, and if a real
  preview prints the old line.

  **`preview.ps1` still has its check, deliberately.** It is not the same
  shape: it reads `course_config.json` on the HOST, so it works — it prints
  the allowed list and, for a section the course does not list, warns and
  asks "Continue anyway? [y/N]" (refused under `--non-interactive`, the
  Windows-only entry in `contracts/app-rules.json` →
  `launcherFlags.nonInteractive.refusals`). Its "Could not determine allowed
  sections" line prints only when the config is missing or unreadable. The
  decision on #224 said to delete it in both launchers, on the premise that
  the twin had the same fault; measured by reading, it does not, so it was
  left as it is rather than removing a working question from Windows.
- Runs `build_site.py`, which (by default) ends by serving the site on
  the requested container port (8081–8084), with Quartz's live-reload
  websocket on port + 1000 (`--wsPort`) — the reason the container
  publishes both ranges. The reachable HOST address is the folder's
  probed block; `preview.sh` prints it.

#### Before building, preview.sh makes sure this Mac can reach the builder (#234)

Between finding the address and announcing it, `preview.sh`
(`announce_the_preview_address` → `this_mac_can_reach_the_builder`) opens a
connection to `127.0.0.1:<the announced HOST port>` —
`curl -q -s -o /dev/null --noproxy '*' --max-time 1`. Nothing is served inside
the builder yet, so a healthy Mac answers with an empty reply (curl exit 52)
and the preview goes on exactly as before. **Only a refused connection (exit
7) on every try stops it**: 20 tries 0.5 s apart, about ten seconds, or 60
tries (about thirty) when THIS run started the builder's virtual machine. It
then prints `previewPorts.whenThisMacCannotReachTheBuilder.sentence`, writes
`launcherLineWhenThisMacCannotReachTheBuilder` on the trail under the existing
"preview did not appear" event, and exits 1 before building. The numbers and
ten cases are in `contracts/app-rules.json` →
`previewPorts.whenThisMacCannotReachTheBuilder`; `scripts/test_preview_reach.py`
runs every case against the launcher's own functions, with docker, curl and
sleep stubbed.

**Why.** The fault is #225's (see `09-mac-app.md` → "A preview that never
appears"): a Mac whose builder has stopped handing NEW addresses through
(`ssh … -O forward` exit 255, fixed only by a restart) built a preview for
about two minutes (109 s on the Mac that met it) and the app then waited 45 s
more before its alert. Asked before the build, the same fault is found in
about ten seconds with nothing built. The app needed no change: an exit 1 with
no address announced is #235's shape, so the run ends with the launcher's
sentence in the window and `PreviewReachability` never starts a wait.

**It fails OPEN, deliberately.** Every answer but 7 goes ahead — a page (0), an
empty reply (52), a timeout (28), no curl at all (127), anything —
because none of them proves the forward is missing, and #225's check after the
build is still there behind it. A listener that is NOT the forwarder (another
program took the port after the workspace was made) also goes ahead; **do not
tighten this to require a real page**: nothing is served before the build, so
that would refuse every healthy Mac.

**Why a connection and not `lsof`.** Measured on the development Mac
(Apple silicon, Colima vz aarch64, 2026-09-25): curl to a forwarded port with
nothing inside answers 52 in 0.01–0.03 s; to a port nothing listens on, 7 in
0.01 s; `lsof -iTCP:<port> -sTCP:LISTEN` takes 0.228 s. Worse, `lsof` run as
the teacher sees only the teacher's own programs: a root-owned listener (:88,
`kdc`) is invisible to it and answers curl. A forwarder owned by anybody else
would read as missing and refuse a healthy Mac. All 48 host ports published by
six running workspaces had a listener. `-q` comes first so the teacher's
`~/.curlrc` is never read, and `--noproxy '*'` so a proxy setting cannot
answer for this Mac.

**The retry is a bounded re-asking of the real question, not a settle-delay.**
A healthy Mac answers on the first try; #225 measured the listener appearing
0.10–0.24 s after the builder is created or started (0.15 s under load). The
bound is for the one case **nobody has measured: the first address after the
builder's virtual machine starts cold.** That is not rare — since #220,
quitting Plantoir stops the VM when nothing else uses it, so it is the first
preview of most days — which is why a run that started the VM
(`ensure_container_runtime` sets `THIS_RUN_STARTED_THE_BUILDER` in
`preview.sh`'s copy only, on every path past its "already running" return)
allows 60 tries. Measuring it would have meant a throwaway second Colima
profile on Russell's Mac; the director ruled that out, so the number stays
unmeasured. Instead, **a run that needed more than one try says so in the
console** (`reachedAfterRetrying`, "…took N tries"), so the next transcript a
teacher sends carries the figure the bound rests on.

**Rejected:**
- *`lsof` as the probe* — above: slower, and blind to listeners the teacher
  does not own.
- *A check in `setup.sh`, at the builder's creation* (the issue title's literal
  reading) — it would not have fired on the night: all three previews met a
  builder that was already running, and `run_container_with_mount()` is reached
  only on create or recreate. Setup is also exactly the unmeasured cold start.
- *One probe* — the cold start is unmeasured, so one refusal is not proof.
- *Skipping the check when this run started the VM* (the fault is an OLD VM
  refusing NEW forwards) — a VM broken from birth would then build for minutes
  first; the longer bound covers both.
- *Asking inside the builder first* — before the build nothing is served
  there, so it proves nothing; that stays #225's question, after the build.
- *Checking the live-reload port (+1000) too* — a Mac that refuses new forwards
  refuses both, and stopping a preview over live-reload alone is a heavier
  answer than the fault.
- *A `failureExplanations` case or an app alert* — as for #280's
  `whenNoBlockIsFree`, the launcher's own sentence is what a teacher reads, and
  a case would turn Windows' suite red for a failure its app cannot produce.
- *Putting it in the shared PREVIEW PORT BLOCK* — only `preview.sh` announces
  an address; the block is left byte-identical across the three launchers.

**Windows** has nothing to mirror: `preview.ps1` serves on the PC itself, so
there is no forward to lose. If a preview there ever sits behind a forward
(WSL2's relay has the same failure class), probe with a CONNECTION, not a
listener list.

### `deploy.sh`

- Normalizes the course code to uppercase and includes a friendly guard for a
  classic Ontario data-entry error: a course code ending in the digit `0`
  where the letter `O` (an "Open" course) was intended, e.g. `ICD2O` typed as
  `ICD20`. If the `O` variant exists on disk it offers to correct it.
- Verifies the built site exists at
  `courses/<CODE>/.merged_output/section<N>/public/` and tells you to run
  preview/`--build-only` first if not.
- **Token handling** — the launcher, not the container, owns the Netlify
  Personal Access Token:
  - macOS: stored in the **macOS Keychain** under the service name
    `containerized-quartz-netlify` via `/usr/bin/security`.
  - Windows: stored in **Windows Credential Manager** under the same target
    name, accessed through P/Invoke (`CredRead`/`CredWrite`) from PowerShell.
  - Both migrate tokens from a legacy obfuscated file store
    (`courses/.internal/tokens.json`, XOR+base64 with a key file) into the
    OS credential store, then delete the legacy entry.
  - On first run the script opens the Netlify token-creation page, validates
    the pasted token against `GET /api/v1/user`, and saves it.
    `--reset-token` (or `--logout`) clears it.
  - The token is injected into the container by piping it to a root-only
    temp file (`umask 077`) and reading it inside the `docker exec` shell
    into the `NETLIFY_AUTH_TOKEN` environment variable — it never appears in
    a process argument list on the host.
- **`--non-interactive`** says nobody is at the computer, which is what a
  scheduled publish is. Every question the launcher can ask — the course-code
  correction, the Cloudflare Account ID, and both token prompts — becomes a
  refusal that names the question and exits **3**, a code meaning "a question
  went unanswered" and nothing else, so a caller can tell it from an ordinary
  failure. The flag is FORWARDED to `deploy.py`, which does the same for the
  questions it owns — including the one that matters most, what the website
  should be called. `deploy.sh` looks for the flag TWICE: once in a pre-scan
  before the course-code guard, which runs before the option loop, and once in
  the loop itself. `deploy.ps1` needs no pre-scan, parsing its flags first.
  A saved credential that fails its check is KEPT rather than cleared under
  this flag: the check is a network call, so an offline machine and a revoked
  token look identical from here, and discarding a working credential only a
  person can replace is the more expensive mistake. Only the app's SCHEDULED
  deploy passes it — pressing Deploy runs this same launcher through a
  pseudo-terminal so a question can come back as a dialog.

  **It is a PREVIEW flag too, as of 2026-09-09 (issue #124).** A scheduled
  publish BUILDS before it publishes, and the build runs `preview.sh` /
  `preview.ps1` — which ask questions of their own, at half six, of nobody.
  Both now take the flag and refuse with the same exit 3. `preview.sh` needs a
  pre-scan for the same reason `deploy.sh` does, its course-code guard running
  before the option loop; `preview.ps1` parses first and needs none.
  `preview.ps1` also asks one thing `preview.sh` does not — *"Continue
  anyway?"*, when a section is not listed in `course_config.json` — which is
  recorded in `app-rules.json` with `appliesOn: ["windows"]` so it reads as a
  deliberate difference rather than drift.

  **And both deploy launchers FORWARD it to that rebuild**, the one they run
  themselves when they find a preview-built site. `deploy.sh`'s pass-through
  of exit 3 was dead code until 2026-09-09, and **the line has now been got
  wrong twice**, which is why the launcher carries both shapes in a comment
  rather than just the right one:

  - `if ! CMD; then _rc=$?` — with `!` in front of a pipeline the status is
    the logical NOT, so `$?` is 0 and the `-eq 3` test could never fire.
  - `CMD` then `_rc=$?` on the next line, which was the FIX for the first and
    is worse: `deploy.sh` runs under `set -euo pipefail`, so the script aborts
    at `CMD` and the guard never runs at all — printing nothing, where the
    broken version at least printed "Could not rebuild this site for
    publishing." It propagated 3 by accident, which reads as working.

  `_rc=0; CMD || _rc=$?` is the shape that survives both: an `||` list is
  exempt from `set -e` and leaves `$?` readable. Measured on bash 5.3.15 and
  pinned by two tests in `scripts/test_deploy_non_interactive.py`, one of
  which RUNS all three behaviours rather than asserting a shape — because the
  test written for the first mistake passed against the second.

  What it refuses is
  listed in `contracts/app-rules.json` → `launcherFlags.nonInteractive`, and
  the flag itself is registered in `launcherFlags.deployExtras`.

  All four refusals are DRIVEN, not just described:
  `scripts/test_deploy_sh_questions.py` runs the real `deploy.sh` to each
  question — with `--image` so no build recipe is resolved and no container is
  needed, and a Keychain user that does not exist so the lookups come back
  empty — and checks the refusal is SAID as well as the exit code being 3. It
  also pins the other half, that a teacher at a keyboard is asked exactly what
  they were asked before and their answer is taken. It exists because this
  flag was written on a machine with no bash and the launcher had never been
  started; doing so found two bugs in `prompt_for_cf_account` that reading it
  had not (issue #129, written up in
  [publishing](07-deployment.md#asking-once-and-the-subshell-that-ate-the-question-2026-09-09)).

  **`preview.sh` takes it too**, and needs to: a scheduled publish BUILDS
  before it publishes, the mac's launchd agent runs `preview.sh --build-only`
  directly, and `deploy.sh` forwards the flag to its own rebuild. `preview.sh`
  has no `set -e`, so without the flag its own course-code guard reads at end
  of input, takes the `[Y/n]` DEFAULT, and rebuilds a DIFFERENT course — which
  is then published successfully against the wrong one. A refusal is the
  better failure. Registered in `launcherFlags.preview`.

  **And it is driven too**, by `scripts/test_preview_sh_questions.py` — added
  2026-09-09, because a launcher that has only ever been READ under a new flag
  is the state `deploy.sh` was in when running it found two bugs. It borrows
  the twin's harness rather than copying it, and it pins four things reading
  cannot: that the refusal exits 3 and says which question it could not ask;
  that the command the launchd wrapper actually writes — flag LAST, after
  `--build-only` — refuses the same way; that "Nothing was built" is TRUE,
  by looking at the folder afterwards; and that the flag's parser arm does not
  eat the argument following it, which it would if a `shift` were ever added
  there (the loop shifts once at the bottom already). The measurement the
  contract's reasoning rests on — that without the flag, at end of input, the
  default is taken and the build retargets — is run rather than remembered,
  because the Windows side found the equivalent claim about PowerShell was
  false the day they measured it.
- Finally runs `deploy.py` inside the container
  (see [Deployment](07-deployment.md)).

## A note on line endings

The repository stores every file with LF endings. At image-build time,
`unix2dos` converts the `.bat`/`.ps1` copies baked into the image's
`export-scripts` bundle to CRLF (Windows batch files can misbehave with
bare LF), and `verify.sh` checks the CRLF survives. Teachers normally
receive launchers via the app's `.toolchain/` mirror rather than
`export-scripts`, but the exported copies remain a supported escape hatch
and differ from the repo versions in line endings only.

## One rule for stopping a section's preview

New on 2026-09-05, and the closing of a `TODO.md` item. Read
`contracts/shared-rules.json` → `stopPreview` first; this explains why it is
shaped the way it is, and what was rejected.

**What was wrong.** One question — *which processes belong to this section's
preview?* — was answered in three places: `preview.sh --stop` (a `/proc` sweep
by working directory, run inside the container), `preview.ps1 --stop`
(`Win32_Process` by command line, plus a descendant walk, run natively), and
`build_site.py` (command line plus `--serve`, inside the container, written
because both of the others are HOST scripts and it is not). The reason for the
third is sound and has not gone away; the problem was never that it existed,
it was that nothing held the three to the same answer.

**The finding that changed the design, and the reason a straight refactor
would have been wrong.** They were not three copies of one rule. They were
three PARTIAL rules, and each saw something the others could not:

- A **working directory** catches a child launched by a RELATIVE path, which
  carries no directory to match on. `npm install` runs exactly that way, and
  so do the esbuild workers under it.
- A **command line** catches the Python driver. `build_site.py` never calls
  `os.chdir` — it passes `cwd=` to its CHILDREN — so the driver sits in the
  container's `/teaching` for the whole build. Through every in-process phase
  (copying the scaffold, copying content, social cards, the rsync mirror) it
  is the only process there is to find, and the mac's sweep found nothing and
  printed "Stopped 0 process(es)".
- Only **`preview.ps1`** walked descendants — Windows', and it was right.

So picking any one of the three as "the" implementation would have shipped
that one's blind spot to both platforms. The rule is a **disjunction of three
evidences, plus a walk down the process tree**, and it stops strictly more
than any of the three did alone.

**Why the cases are process SNAPSHOTS rather than single processes.** The
first design had each case describe one process — name, command line, working
directory — with an expected verdict. That cannot be run on both platforms,
for two independent reasons. `Win32_Process` exposes no working directory at
all, so every cwd case would be unanswerable there. And the descendant
walk is not a property of any single process: it is a rule over parent links
across the whole list. A case is therefore a small process TABLE with `pid`,
`ppid`, `name`, `commandLine` and `cwd`, and the expected answer is the list
of pids to stop. A platform that cannot see one kind of evidence must still
reach the same verdict — through the walk — and that is exactly the property
worth testing rather than assuming.

**Two modes, because there are genuinely two questions.** `everything` is the
launcher's `--stop`: reclaim the server, the build, the driver, and everything
under them. `servingOnly` is `build_site.py --build-only`: remove ONLY the
preview server that would otherwise overwrite the publish build a second later
through its own host mirror. A build must never be stopped in that mode,
because the build being protected is itself a build of this section — and the
process asking is the driver the rule would otherwise recognise.

**The version-independence trap, which is the one to carry if anyone ever adopts
`--match-stdin`.** `preview.sh` pipes the recipe's copy of the rule into the
container over stdin rather than running the copy baked into the image. Stop
mode must never build anything, so it runs against whatever container is
ALREADY there — right after an upgrade, one built from the previous image,
with no such file. Naming a baked path would make `docker exec` fail with a
message nobody sees (both callers send the launcher's output to the null
device and neither checks its exit code) while the build it was asked to stop
carried on burning CPU. This is exactly once per teacher per upgrade, and only
when something was running, which is the only time the mode matters at all.
`verify.sh` section 6d proves it by deleting the file from a running container
and stopping a preview anyway.

**Rejected: making `preview.ps1` call the shared Python.** It would leave one
implementation and two ports, which is better, and the `--match-stdin` entry
point exists so it can be. It was not done from the mac because `--stop` must never
start anything and whether Python is reliably resolvable on that path at that
moment is a question only a Windows machine can answer. Measure it there; say
what you find.

**Rejected: extracting `preview.ps1`'s matcher into a new `.ps1` file beside
the launchers.** A test could then dot-source it without running the script.
But a new file there has to be added to `ToolchainMirror.Launchers` and
`RecipeRootFiles`, the Dockerfile's `COPY … /opt/export/` and its `unix2dos`
line, `project.yml`, and the mac's own refresh lists — five hand-maintained
lists, which is the precise failure `contracts/toolchain.json` →
`recipeFolders` exists to record. The functions are defined inside
`preview.ps1`'s stop block instead. Making them dot-sourceable is a
real cost to weigh, not a free tidy-up.

**A case a platform may skip, and why that is not a loophole.** One case —
"a process is caught by its working directory alone" — can be decided ONLY
with a working directory, which `Win32_Process` does not expose. Rather than
delete it (it pins the evidence that catches `npm install`) or let it fail on
Windows, cases carry `needsEvidence`, and a runner without that evidence skips
it naming what was missing. The loophole this could obviously become is closed
by a test rather than by discipline: the mac's suite BLINDS every case — takes
the working directories away — and asserts that a marked case's verdict
changes and an unmarked case's does not. It caught a case wearing the marker
that did not need it on the first run, which is exactly the drift the marker
would otherwise invite.

**Three holes the second review found, all in the rule itself, all the same
family as the bug being fixed.** A blank or root build directory was evidence
for EVERY process, because an empty string is a prefix of everything — a
caller that lost track of which section it was asking about would have swept
the whole container rather than failed. A target that is a SUFFIX of a longer
absolute path matched as well, so `/x/tmp/quartz-builds/ADA1O/section1` was
evidence for `/tmp/quartz-builds/ADA1O/section1`. Both are the section1 /
section10 mistake pointed in different directions: one about where a path
ends, one about where it begins, one about whether it is a path at all. The
lesson worth keeping is that fixing a boundary bug in one direction is not
finishing it — check every edge of the match, and check that the thing being
matched is a real value.

**One harness lesson, learned twice in one afternoon.** A process that scans
other processes for a marker string finds ITSELF — the marker is on its own
command line. In `verify.sh` 6d this first inflated a count so that every
check in the section failed while the code under test was correct, and then,
in the cleanup, made the script SIGKILL itself part-way through: it printed
nothing, exited quietly, and left behind the very processes it was written to
collect. The second one was found only by checking the container afterwards
rather than trusting a green run. Exclude the harness's own process id, and treat
"scanning for a string I am myself carrying" as a shape worth recognising —
the same trap that `stop_preview.py` already guards against for the real rule.

**What was measured, not decided.** The two `preview.ps1` prefix bugs were
found by reading, and both are real: `$lower.Contains($sectionNeedle)` with a
needle ending `\section1` matches `\section10`, and
`$lower.Contains('--section=1')` matches `--section=10`. Each was reproduced
as a contract case, and each case was checked by putting the fault back into
the shared Python and watching that case — and only that case — fail. The same
was done for the descendant walk. A green suite proves nothing about a case
that cannot fail.


**Leases and this stop (#156).** Since 2026-09-25 the mac reads and writes the
work leases under `courses/.internal/activity/`. Because this stop ends BUILDS
as well as servers, by working directory, the order around it matters:

- **Deploy** takes its claim — its own `build` and `publish` leases, then a look
  at everyone else's — BEFORE it runs this stop. A refusal therefore stops
  nothing, and while the stop runs the window's `build` lease is up, so no other
  program (an outside assistant, another copy of Plantoir, a publish set for
  later) can be told the course is free and start a build that the stop then
  kills.
- **The in-app assistant** looks before it stops a window's preview, and
  declines without stopping anything when another program is in the way.
- **What is NOT covered:** the plain Stop button, the preview's and the
  deploy's Cancel buttons, a window closing, and the assistant's
  stop-then-start release the window's lease (its preview lease, or for a cancelled deploy its
  build lease) the moment the stop begins, while the stop itself runs on (waited up to 20 s). An outside
  build started in those seconds can be ended by it. Nobody builds twice — the
  outside program is told its build failed, and a retry works — and it is a
  known limit in `09-mac-app.md` rather than a guarantee.

The rule and its cases are `contracts/shared-rules.json` →
`workLeases.declining`; `09-mac-app.md` → "Two programs, one course" is the
manual.

## A course kept for reference is refused in the launcher, early

`deploy.sh` and `deploy.ps1` both read `courses/<CODE>/course_config.json`
before the flag loop and refuse, with a sentence, when it says
`"kept_for_reference": true`. The full reasoning is
[`07-deployment.md`](07-deployment.md) → "A course kept for reference is never
deployed"; three things belong here, beside the launchers themselves:

- **It is in the launcher because the FOLDER destination never reaches the
  container.** That branch copies with `rsync` on the host and exits 0 before
  `deploy.py` is entered, so a refusal written only in the shared Python would
  not run on it. Measured with the guard removed: the launcher published the
  frozen course and reported `✅ Published: 1 file(s) updated.`
- **Plain shell, not `python3`.** Nothing on that path needs a host
  interpreter today, and the launchers' whole first-run promise is that a
  teacher installs nothing. The check is a `grep` for the key and a second one
  for `course_code`, so the sentence names the code a teacher reads rather than
  the folder.
- **It fails CLOSED.** A settings file that exists and cannot be read refuses.
  A settings file that is absent is left to the course-folder check further
  down, which already says that in its own words.

**There are TWO refusals here, not one.** The second is "cannot tell": the
launchers refuse when the marker is present with a value that is neither
`true` nor `false` — `1`, `"true"`, `True` — and when any object KEY in the
settings carries a `\u` escape. Both are spellings somebody plainly MEANT and
neither is one the app reads as a reference course, so the launcher's refusal
is the only thing between them and a published frozen course; it publishes
nothing and freezes nothing. `app-rules.json` → `failureExplanations` turns
both halves of it back into the sentence a teacher reads when a deploy set to
happen on its own hits one.

The sentence is a constant (`REFERENCE_COURSE_REFUSAL`) rather than read from
the contract, because this runs before `BUILD_CONTEXT` is resolved and under
`--image` it is never resolved at all. `scripts/test_reference_course.py`
compares both launchers' constants with
`contracts/shared-rules.json` → `referenceCourses.refusal.sentence`, and
`verify.sh` greps both files for the guard — the same structural check the
live-reload guard has, for the same reason.

## `--image` is the mac's flag alone

Found 2026-09-06 while wiring the contract's case lists into the Windows suite.
`contracts/app-rules.json` → `launcherFlags.deployExtras` named `--diagnose` and `--image <tag>` as flags
the launchers must both accept. `deploy.sh` parses `--image`; `deploy.ps1`
does not, and cannot — Windows has had no image to name since it dropped
Docker on 2026-08-19. Recorded as `macOnly` rather than closed by adding a
dead flag to `deploy.ps1` so a test would go green, which is the shape of fix
`WINDOWS-BOOTSTRAP.md` §0 exists to forbid.

---

[◀ Previous: The Docker Image](02-docker-image.md) · [Back to index](README.md) · [Next: Course Setup ▶](04-course-setup.md)
