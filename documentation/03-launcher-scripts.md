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
`/bin/pwd -P | shasum -a 256` — the disk's own spelling of the folder; see
"One folder, one spelling" below — so two folders (this year's courses and last
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
first folder on a Mac. Since #234 it then connects to that address before
building, and stops in about ten seconds if this Mac cannot reach it (see
"Before building, preview.sh makes sure this Mac can reach the builder"
below). `--build-only` asks neither question and is never stopped there,
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

The scripts then ensure a container runtime is available (section 3)
and build the image locally if the recipe's tag is missing — nothing is
ever pulled from a registry.

### One folder, one spelling (GitHub #189)

The same folder can reach a launcher spelled several ways: through a link, as
`/tmp` for `/private/tmp`, by the firmlink `/System/Volumes/Data/…`, in the
wrong case (a Mac's disk ignores case), or with an accented letter in the
other Unicode form — é stored as one character by Terminal, a zip or a
Windows PC, and as e + accent by Finder. The disk treats them all as one
folder. Until #189 the launchers hashed bash's BUILT-IN `pwd -P`, which keeps
the case and form it was HANDED, while the app hashed `realpath`, which
returns the disk's. And the app cannot hand a launcher the disk's bytes even
if it wants to: Foundation passes an accented name to a child process as
e + accent whatever the disk stores (measured, `Process.arguments`). So a
working folder with an accented name stored the Terminal way — or reached in
another case — had two workspaces and two builds folders, one the app's and
one the launchers', and each side cleared the other's builds as "a link that
is not mine".

**The fix is one line after each launcher's first `cd`**, identical in all
three and checked by `scripts/test_folder_spelling.py`:

```bash
FOLDER_ID_AS_HANDED="$(pwd -P | shasum -a 256 | cut -c1-8)"
cd "$(/bin/pwd -P)"
```

`/bin/pwd` asks the disk (`getcwd`), so after it `pwd`, `$(pwd)` and the id
are the disk's spelling, and the id, the container's name, the builds folder
and the `courses/` folder the container mounts all come from ONE spelling.
The id line itself became `/bin/pwd -P | shasum` too, and so did the builds
folder's `working-folder.txt` and `verify.sh`'s own derivations. The app asks
the same question with `FolderIdentity.canonicalPath`
([09](09-mac-app.md) → "One folder, however it is spelled").

What was measured on this Mac (macOS 26.6, APFS, case-insensitive), `/bin/bash`
3.2, against C `realpath` and `fcntl(F_GETPATH)`:

| Spelling handed in | bash built-in `pwd -P` | `/bin/pwd -P` |
|---|---|---|
| the disk's own | same | same |
| wrong case (`plantoircase`) | keeps the typed case | disk's case |
| through a link | target | target |
| `/tmp/…` | `/private/tmp/…` | `/private/tmp/…` |
| `/System/Volumes/Data/Users/…` | keeps the prefix | `/Users/…` |
| an NFC-stored name reached as NFD | NFD (typed bytes) | NFC (disk bytes) |
| an NFD-stored (Finder-made) name typed NFC, upper case | typed | disk's |

`/bin/pwd -P` and `F_GETPATH` agreed byte for byte on all 17 spellings tried
(the table's, plus iCloud Drive, `~/Library/CloudStorage/Dropbox` and an
external HFS+ disk, each in the right and the wrong case). `realpath`
agreed on all but the firmlink, where it keeps `/System/Volumes/Data`.

**Rejected:** `realpath(1)` and `python3 -c os.path.realpath` in the launcher
(the second measured in the issue not to fold case, and Python is not there
before setup has run); making the app imitate the built-in instead (the id
would then depend on how the folder was reached, which is the bug, and the
app's "typed" bytes are not even its own); `cd -P` (measured: also keeps the
spelling). A reviewer showed that switching only the id line to `/bin/pwd`
would have been worse than nothing: `HOST_COURSES="$(pwd)/courses"` would
still hold the typed spelling, one container would be told two mount sources
on alternate runs, and it would be stopped and recreated each time — a cold
workspace (about two minutes) instead of a second one. Hence the `cd`.

**The second copy is cleared away.** `clear_away_this_folders_other_spelling`,
in the PREVIEW PORT BLOCK and called by each launcher just before it looks at
its own workspace, handles what an old spelling left behind: if
`FOLDER_ID_AS_HANDED` differs from the folder's id, a STOPPED
`teaching-quartz-<that id>` is removed with a plain `docker rm` (never `-f`),
and `builds/<that id>` is removed when its `working-folder.txt` names THIS
folder (compared through `/bin/pwd -P`, since an old launcher wrote the typed
spelling; an EMPTY note names no folder, because `cd ""` stays put and would
read as this one) and no workspace, running or stopped, still mounts it. A RUNNING
copy is left alone and named on the console — it may be an older launcher's
publish in the middle of its work. Nothing is removed when Docker cannot be
asked, and the teacher's courses are never touched. The console says what was
cleared — the workspace, the built websites, or both, naming only what went —
and the trail gets one line (`contracts/shared-rules.json` →
`buildOutputLocation.aSecondSpellingIsClearedAway`, and
`activityTrail` → "built site moved out of the working folder" →
`launcherLineWhenASecondCopyIsClearedAway`). Rejected: doing it in the app at
launch — a publish launchd started with the OLD `deploy.sh` could be building
into that folder at that moment; moving the old folder's content to the new
id — adoption under another name, for a build nothing vouches for (the two
had been clearing each other), which `aBuildWithNoLinkIsNotAdopted` already
refuses.

**What a teacher pays, once.** Any launcher edit changes the image tag, which
recreates every folder's container on its next run — this one included; an
ordinary folder whose path is already in the disk's spelling keeps its id, its
builds folder and its built websites. A folder that had the split builds from
scratch once more (the builds folder the launchers now use is the app's, whose
link the last launcher run had cleared), and never again. Known limits: a
second copy that is RUNNING when the launcher looks keeps `docker ps` from
being empty, so the app's quit leaves the virtual machine running until it
stops ([09](09-mac-app.md) → "Quitting"); a spelling that is never used again
leaves its stopped copy behind, holding one of the forty preview blocks, which
the walk's second pass will take when nothing else is free; and one narrow
race is open — an OLD launcher (a launchd publish still on the pre-refresh
`deploy.sh`) that has made its builds folder but not yet started its stopped
workspace can lose that folder to a new launcher handed the same old spelling
at the same moment, costing that one publish a build
(`buildOutputLocation.aSecondSpellingIsClearedAway.knownLimits`).

### How a folder finds its ports, and when it cannot

GitHub #280, 2026-09-25. The rule is data in
[`contracts/app-rules.json`](../contracts/app-rules.json) → `previewPorts`
(`hostBlockCount`, `hostBlockProbe`, `hostBlockCases`, `hostBlockClash`,
`whenNoBlockIsFree`); the code is one marked block, `# >>> PREVIEW PORT BLOCK
>>>`, byte-identical in `setup.sh`, `preview.sh` and `deploy.sh`, and
`scripts/test_port_blocks.py` runs it against a pretend Mac (fake `lsof`,
`netstat` and `docker` on PATH) under `/bin/bash` 3.2 with `set -euo
pipefail`, plus one check of the real `netstat` half on the Mac it runs on.

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

- **listening on this Mac, in ANY account** — read from TWO listings, each
  once: the kernel's own list, `netstat -an -p tcp` (LISTEN rows only; port =
  what follows the LAST dot: `*.8081`, `127.0.0.1.8443`, `::1.8443`), and
  this account's `lsof -nP -iTCP -sTCP:LISTEN -Fn` (port = what follows the
  last colon: `n*:8081`, `n127.0.0.1:8443`, `n[::1]:8443`), joined. Until
  #310 (2026-09-26) it was `lsof` alone — see "Another account on the same
  Mac" below for why that was wrong. This check has to stay: a python server
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
| (#310, 2026-09-26) `netstat -an -p tcp` + awk, the whole list | **0.00–0.01 s** (3 runs); 17 listeners against `lsof`'s 13 — root's `kdc` on 88 and screen sharing on 5900 are the difference |
| (#310) `lsof` listing, for comparison | 0.06–0.07 s |

Each listing that cannot be read (missing or failing) counts as EMPTY on its
own, so the other one's answer stands: a `netstat` whose columns change in a
future macOS falls back to exactly the old `lsof` answer, never to "nothing
listening". Only when both fail does the walk count nothing as listening —
the old probe's answer too, pinned by a test so nobody changes it quietly; the
other workspaces are still skipped, and a clash with one is caught below.

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

**A preview looks before it starts one (#310).** Colima does NOT refuse a
start onto a port something else holds — `docker start` exits 0 and the
forward silently fails (measured with root's 5900) — so the refusal above
never comes. So when `preview.sh` is about to SERVE (`WORKSPACE_WILL_SERVE`,
which only `preview.sh` sets, and only without `--build-only`) and the engine
is Colima (`the_engine_forwards_from_this_account`), `start_the_existing_workspace`
first reads the workspace's own eight host ports from `docker inspect` and
looks for any of them in the listings. A stopped workspace listens on nothing
— its own forward is gone 0.011 s after the stop returns and back 0.011 s
after a start (5 of 5 each way) — so a listener there is somebody else's,
this account's own programs included. It then asks once more whether the
workspace is RUNNING (another launcher for the same folder started it a
moment ago: the listener is its forward, and it is used as it is), and
otherwise takes the same remake as a refusal: the two ♻️ lines, a plain
`docker rm`, `run_container_with_mount`, and — only once that has
succeeded — the marker
`PLANTOIR_PREVIEW_ADDRESS_HELD: before-start <port> <course>/<section>`,
which the app writes onto the trail as the `preview address held by another
account` event. If `docker rm` is refused and the workspace is not running,
the run stops with `saysWhenAStartIsRefused` — there was no start, so there
are no engine's words to print. `setup.sh` and `deploy.sh` never look: they
never serve, so a squatted forward costs them nothing, and a six o'clock
publish keeps its warm builder rather than pay a two-minute remake with a new
way to fail. The block stays byte-identical in all three launchers because
the look is switched on by that variable, not written in one copy only.

**Never `docker rm -f` in either path.** A failed start proves nothing runs in
that workspace, but two launchers on the same folder (a scheduled publish and
a Preview) can both find it stopped; the second one's `-f` would kill the
workspace the first had just remade, mid-publish — the shape GitHub #94 was
about. Plain `rm` refuses a running workspace, and the start path then uses it
as it is. Every OTHER remake, since #94, looks at what is running first and
removes by id: "Before a workspace is remade" below.

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

**Another account on the same Mac (#310, 2026-09-26).** Found in the #204
rehearsal: two macOS accounts signed in, each with Plantoir. `lsof` run as
the teacher lists only the teacher's own programs, so the second account's
walk saw 8081 as free while the first account's preview held it. Its
`docker run -p 8081…` exited 0; under Colima the forward is this account's
own `ssh`, and XNU refuses a port already bound by another uid, so the forward
failed with a warning in Lima's `ha.stderr.log` (`failed to set up forwarding
tcp port …`, ssh exit 255) and nowhere a launcher reads — `docker port` still
names the port. #234's reach check was then answered by the FIRST account's
forwarder, and the teacher's Preview opened somebody else's site. Measured
with root's screen sharing on 5900 standing in for another account (a
different uid, which is all XNU compares): `docker run -p 5900:8081` → exit
0, `docker port` → `0.0.0.0:5900`, curl to it reaches screen sharing.

Three layers now, each closing a hole the others cannot:

1. **The walk** reads the kernel's list too (above), so another account's
   listener, or root's, is stepped past like this account's own.
2. **Before a preview starts a stopped workspace** it looks at its ports
   (above). The walk cannot see another account's STOPPED workspace (its VM
   is not ours to ask), so two accounts can still both hold 8081 on paper;
   whichever starts second is caught here.
3. **Before `preview.sh` announces the address** it asks whose it is:
   "Before building, preview.sh makes sure the address is this account's
   own", in the `preview.sh` section below.

**Known limits, written down rather than fixed:**

- Another account's STOPPED workspace is invisible by construction, so this
  account can be handed its block while that account is logged out or its
  workspace stopped. That account then pays one remake (about two minutes)
  when it next previews. Documented, not a bug.
- The look before a start, and the look before the announcement, run under
  Colima only (`contracts/app-rules.json` → `previewPorts
  .whenAnotherAccountHasTheAddress.gate`). Docker Desktop refuses a start
  onto a held port itself ("Ports are not available"), which the refusal path
  handles; any other engine was never measured and must not pay a remake on
  a guess. A developer whose shell sets `DOCKER_HOST` to anything outside
  `~/.colima/` (or `$COLIMA_HOME`, for a Colima kept elsewhere) switches both off — `docker context show` then says `default`
  whatever the engine — and the preview says so on the trail (the
  `unchecked` outcome) rather than going quiet. The app never sets it.
- The look before a start can remake a workspace stopped a moment ago
  whose own forward has not gone yet: 0.011 s on the development
  Mac, unmeasured on a teacher's (#225's Mac took 0.10–0.24 s for a listener
  to APPEAR). The cost is one cold preview, never a wrong site.
- The likeliest follow-on on a two-account Mac looks like #225, not like
  this: the other account quits Plantoir while this account's broken
  workspace is still running, so nothing listens on the address at all and
  #234 says "restart your Mac". That remedy works (the forward is made again
  on the next start), but the diagnosis is #225's. Left alone deliberately:
  #234 rejected restarting the builder from a launcher.
- A root-owned or other-account server in the range is still found only by
  the kernel's list; if some future macOS changes `netstat`'s columns, the
  walk silently falls back to `lsof` alone, which is #310 again.
  `scripts/test_port_blocks.py` → `TheRealListings` checks the `netstat`
  half ON ITS OWN on whatever Mac runs the suite (non-empty whenever `lsof`'s
  list is, and holding every port `lsof` lists), so that fallback shows up
  as a red test rather than as a teacher's wrong site.

**What was rejected, and why:**

- **A workspace with no ports for a publish** (Russell's comment on #280: "a
  publish-only folder should not need a port block at all"). Rejected by the
  director on 2026-09-25, reversibly: the workspace is made once per folder
  and serves both, so the next Preview in that folder would have to remake it
  — which, when that was decided, stopped the workspace without asking what
  ran in it, so a scheduled publish of another section in progress would have
  been killed. Since #94 a remake waits for the publish instead, so the cost
  became a routine wait (or a refused preview) rather than a killed publish;
  and it still throws away the warm website builder (109 s cold). It also
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
- **A bind probe** (#310's first suggestion). It does see other accounts, even
  with `SO_REUSEADDR`, but it needs an interpreter: `/usr/bin/python3` on a
  Mac without the Command Line Tools is a stub that opens the "install
  developer tools" dialog, and one process per port cost 2.23 s for forty
  blocks. It also answers the wrong question both ways: without
  `SO_REUSEADDR` a port in TIME_WAIT (a preview closed a minute ago) reads as
  taken; with it, a same-account listener on another address reads as free
  (127.0.0.1 beside `*:5000`, measured).
- **A connect probe for the walk** — 0.66 s for 320 ports, sees only what
  answers on 127.0.0.1, and knocks on other people's servers.
- **`netstat` alone** — a future column change would fail open to "nothing
  listening", which is worse than before #310. Keeping `lsof` costs 0.06 s.
- **Reading Lima's `ha.stderr.log`** for the failed forward — the direct
  evidence, but an internal log in a Colima-version-specific place and shape,
  and a Docker Desktop teacher has none.
- **The look before a start in `setup.sh` and `deploy.sh` too** — neither
  serves; the look would give a scheduled publish a two-minute remake and a
  new way to fail for a clash that cannot hurt it.
- **A launcher line under `workspace was in use`** for the #310 remakes (the
  plan's first proposal) — that event is written by the app from its own
  marker and says a remake with nothing running writes nothing; the remakes
  got their own mac-only event instead.
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
   prints "🚀 First start: setting up your website builder…" (before GitHub
   #263, "building the virtual machine…" with its disk image), an existing one
   "▶️  Starting the website builder…" (before 2026-09-23, "Starting Colima…";
   GitHub #228). The downloads in step 2 print "📦 Downloading what your
   website builder needs (N of 4)…", where N is the TOOL's fixed number —
   Lima 1, Colima 2, the Docker CLI 3, buildx 4 — not a running count, so a
   Mac missing only buildx reads "(4 of 4)"; it said "Getting the container
   runtime…" and the like until #263. The app's `ScriptRunner.friendlyPhase` labels only the SECOND
   "Starting up (first time can take a few minutes)…", so that label shows on
   exactly the start that is not the first. Known and left alone: it is shown
   only when a runner has no milestones, which no launcher run lacks.
4. Poll `docker info` for at least a minute — 30 tries, two seconds apart,
   each try also waiting for `docker info` itself ("⏳ Waiting for the website
   builder to be ready…" — `friendlyPhase`'s "Starting up…" marker, which
   moved with the text in #263). If the VM claims to be running but
   the daemon never answers (a known Colima state after the Mac sleeps or
   shuts down uncleanly, where a plain `colima start` no-ops), force a clean
   `colima stop --force && colima start` cycle ("🔁 The website builder isn't
   answering yet — restarting it…") and wait at least two minutes more (60 tries) before
   giving up with "❌ The website builder did not start." and "Restart this
   Mac, then try again." The by-hand recovery a developer would use —
   `colima stop --force && colima start`, then re-run the launcher — is a
   COMMENT beside that line since #263, not output: a teacher cannot act on a
   `colima` command, and a restart is what cleared the wedged builder in
   GitHub #225.

   Every line this step and steps 2–3 print — the whole block from
   `_download()` to the bare `ensure_container_runtime` call, byte-identical
   in `setup.sh`, `preview.sh` and `deploy.sh` — is pinned by
   `AppRulesContractTests.testTheFirstRunLinesNameNoMachinery`: no Colima,
   Lima, Docker, buildx, container, image, script or toolchain on a printed
   line, and the three copies still identical. The rest of each launcher still
   names the machinery in places; that is its own follow-up issue.

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
Until GitHub #263 the launchers PRINTED that last point — "(Colima is shared
by any other Colima-based toolchains on this Mac; their containers restart
automatically afterwards if configured to.)" — beside the restart. It is a
comment now, and that is a trade-off, not a free improvement: the one reader
the printed note served was a DEVELOPER at the command line whose other
Colima containers (a Supabase stack, say) the force-cycle was about to take
down, and a comment is invisible at run time. It went because the console
is read by teachers, who have nothing else using Colima and for whom every
word of it was machinery (`CLAUDE.md` rule 1). Do not restore it as output
without a way to print it only to a developer.

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

Each launcher inspects the existing container before using it, and remakes
it for any of these reasons. **They are not the same in all three**, and this
section said "every launcher" until #94 counted them (2026-09-25):

| Reason to remake | `setup.sh` | `preview.sh` | `deploy.sh` |
|---|---|---|---|
| No `/teaching/courses` mount at all | yes | yes | yes |
| Mounted from a different host folder (a moved folder keeps its old name with a stale mount) | yes | yes | yes |
| No builds mount (`buildOutputLocation` — every container made before built sites moved out) | yes | yes | yes |
| Running a different image than the recipe resolves (a container keeps the version it was made from) | yes | yes | **no** |
| Missing the 9081–9084 live-reload ports (published ports cannot be added later) | yes | yes | **no** |
| `courses/` was created by this very run | yes | — | — |
| Mount correct but not writable (a probe file made and deleted inside; macOS permission/ACL oddities after a move or restore) — while running, and again after starting | yes | **no** | yes |
| The connection has gone stale (`getent hosts` of the destination fails; not for a folder publish) — while running, and again after starting | — | — | yes |

That is **twenty places** (8 + 5 + 7), plus the three that retired the old
shared `teaching-quartz` workspace. `deploy.sh` never checks the image or
the live-reload ports: a publish runs in whatever workspace the last preview
or build left, and the next preview remakes it. That is an inconsistency, not
a decision — written down here rather than fixed by #94, which is about what
a remake may END, not about when one is due. `preview.sh` has no writability
check and no comment in it says why.

Otherwise the container is started if stopped (`start_the_existing_workspace`
— which, only when the start is refused because its ports were taken,
recreates it on free ones; see "How a folder finds its ports" above), or
reused as it is.

Recreating the container loses nothing of the teacher's, because their
content lives in the bind mounts — but it is not free: the warm Quartz
scaffold and `node_modules` live in the container's own `/tmp/quartz-builds`,
so the next preview is a first preview again (109.3 s measured on a teacher's
Mac for #225). And removing it ENDS everything running inside it, which is
the next section.

### Before a workspace is remade: what is running in it (GitHub #94)

Until 2026-09-25 each of those twenty places ran `docker stop` and `docker
rm` (or `docker rm -f`) on the folder's workspace without looking. A preview
open in one window died when another launcher in the same folder remade the
workspace — after an update changed the recipe, once per folder for the
builds mount, on a publish whose connection had gone stale — and a build or a
publish half-way through its upload was killed. Now every one of them says
WHY in its own line and then calls one function, `remake_the_workspace`, in
the PREVIEW PORT BLOCK the three launchers share (byte-identical, checked by
`scripts/test_port_blocks.py`). The rule is data:
`contracts/app-rules.json` → `previewPorts.whenTheWorkspaceIsInUse`.

**What it looks at.** Measured on the development Mac, 2026-09-25:

| What | Result |
|---|---|
| An idle workspace, `docker top` | exactly one process, `tail -f /dev/null` — 6 of 6 running workspaces |
| A preview, from outside | `python3 … build_site.py --course=C --section=N … --port P` (no `--build-only`) and its `node … --serve` child and that one's `esbuild`, whole command lines in `CMD`, with PID and PPID |
| Cost of one look | 23 ms (10 looks, 0.233 s) |
| A STOPPED workspace | `docker top` exits 1 — so "stopped" is asked first, with `.State.Running` |
| `.State.Pid` | the same number `docker top` shows for the first process, so "its own first process" is found by pid, not by position |

One look answers one of three: **nothing** (stopped, gone, or only its first
process), **other work** (anything else — a build for publishing, a publish,
a course being set up, another launcher's probe — and a running workspace
`docker top` did not answer), or **a preview**. The app's quit path uses the
same count to decide whether a workspace is busy (documentation/09-mac-app.md),
so the two agree on what "running" means.

**A preview counts as open only while its launcher is running on this Mac.**
Measured by the plan review: killing the host side of `docker exec` leaves
the process running inside the workspace, parented to the engine's shim. So
a preview is left behind whenever the app is force-quit, a Terminal window is
closed or an assistant's client exits. Counted as open, it would refuse every
remake of that folder for ever with nothing a teacher could close. So each
`build_site.py` preview in the workspace is matched against the Mac's own
process table (`ps -Ao pid=,ppid=,args=`, read once) for a `preview.sh`
whose next two words are that course (either case — the launcher upper-cases
it) and that section; a `--stop` or `--build-only` run does not count, and
this run's own ancestors and descendants are left out, because a login shell
wrapping it carries the same words. A preview with no launcher is an orphan
and counts as nothing, with everything it started; so does a website builder
serving with no `build_site.py` above it (its parent waits on it for as long
as a preview is open, so its absence means the preview side is gone). A
process table that cannot be read counts the launcher as running — a refused
remake can be retried, a killed preview is what #94 was.

**What it does.** Nothing running: remade at once, as before. Otherwise one
line (`sentences.whileWaiting`), then a look every 2 s:

- **a build or a publish** is waited for up to **600 s**, then refused
  (`sentences.whenWorkDidNotFinish`, exit 1). Ten minutes is the wait a
  publish set for later already gives a busy course (#156), so a scheduled
  publish and the launcher it runs give up on the same horizon.
- **an open preview** is refused after **20 s**, naming it
  (`sentences.whenAPreviewIsOpen`, exit 1). Twenty seconds is the app's quit
  path's wait, for the same race: a preview closed a moment ago may still be
  ending (the Stop button does not wait for the stop). An open preview does
  not end on its own, so waiting longer only delays the same answer. An open
  preview wins over other work.

The time is counted in looks rather than read from a clock, as the app's quit
script counts its own — which is also what lets the test replace `sleep` and
run a ten-minute wait in a moment. A publish set for later meets the rule
like any other run: it WAITS for a build or a publish, and STANDS DOWN on an
open preview; it never ends one, consistent with #156.

**Then it stops and removes the workspace BY ID, never by name, never with
`-f`.** Two launchers started together after an update can both find the old
workspace idle; by name, the slower one's stop landed on the NEW workspace the
faster one had just made — #94's shape one step down. By id it lands on the
old one. A remove that fails because that id is already gone is no failure; one
that fails with it still there is tried once more two seconds later, then the
run stops with `hostBlockClash.saysWhenAStartIsRefused`. At the making, a
refusal because the NAME is taken (`is already in use by container`) waits two
seconds and uses that workspace if it is running, else tries once more — a
second such refusal stops with the same sentence. Until this, a name conflict
fell through to the mount refusal's advice to keep the folder inside the home
folder, which was never its trouble (plan review, F4).

**The old shared workspace** (`teaching-quartz`, from before each folder had
its own) is retired from the same block, only when nothing is running in it,
by id; otherwise it is left, silently — it holds nothing of the teacher's and
the port walk already steps round its addresses.

**On the trail.** When it waited or refused, the launcher prints one
`PLANTOIR_WORKSPACE_IN_USE:` line, which the console a teacher reads leaves
out, and the APP writes the `workspace was in use` event from it —
`ScriptRunner` from a run it started, `ScheduledDeploy` from the log of a
publish launchd ran, exactly as the build's `PLANTOIR_DATED` line reaches the
trail. The app writes it rather than the launcher so the event has one writer
for its words and a real call site (`ActivityTrailWiringTests`); the cost is
that a run typed at the command line leaves its console sentence and no trail
line. A remake with nothing running writes nothing.

**Tested** by `scripts/test_port_blocks.py` — every `whatCountsAsRunning` case
and every `sequences` case through the REAL block under `/bin/bash` 3.2, with
a pretend engine, `ps` and `sleep`, plus the id race, the retire, and a check
that no launcher stops or removes a workspace outside the block — and by
`verify.sh` §6c, which puts a pretend preview (`exec -a` renames `sleep`, and
`docker top` shows it exactly as a real one) inside a real workspace with a
pretend `preview.sh` on the Mac, and requires the remake to refuse after at
least 20 s, name the preview, and leave the workspace's id and the preview
untouched; then ends both and lets the section's own remake go ahead.

**Known limits, written down:**

- Between the last look and the stop — tens of milliseconds — another
  launcher can start something in the workspace, and it is ended. Narrowed,
  not closed. Closing it needs a lock every launcher and the app honour.
- The host launcher is matched on its words, not its folder: another working
  folder's `preview.sh` for the SAME course and section makes an orphan here
  count as open (a refusal, never a kill).
- A preview started through the assistant over MCP may meet its client's own
  tool timeout during a ten-minute wait for a build.
- Work that hangs inside the workspace costs a ten-minute wait and a refusal,
  every time, until this Mac is restarted. Quitting Plantoir does NOT clear
  it: the quit path stops a workspace only when it is idle, and one with hung
  work in it counts as busy and is left running (documentation/09-mac-app.md).

**What was rejected, and why:**

- **The #156 work leases as the signal.** A launcher's own caller already
  holds one — a publish takes its build and publish leases before its
  launchers run — so a remake would see its own run as busy, and telling the
  caller's lease from another's needs a pid the pty in between hides. A
  command-line run writes none. And a lease says "may be about to"; a remake
  ends only what EXISTS, which `docker top` sees directly in 23 ms. Leases
  stay the app's tool for "do not start a build"; this is "do not end a
  running one".
- **Refuse at once, no wait.** A publish and a build end by themselves;
  refusing a scheduled publish because another section's build had forty
  seconds left is a failure made out of nothing.
- **Wait for ever.** A serving preview never ends; a wedged daemon never
  answers.
- **Keep using the old workspace and remake later.** Fine for a missing
  live-reload port on a publish; wrong for the rest — a wrong mount or a
  missing builds mount builds into the wrong place, and an old image runs the
  OLD recipe while looking healthy.
- **Count every `build_site.py` preview as open** (the plan as first
  written). Orphans are real and common enough to have their own trail event
  (`section processes reclaimed`); counting them would refuse for ever.
- **Exempt this section's own preview** (the run would end it anyway). The app
  already waits for its own stop before starting a preview, so only a second
  command-line run of the same section meets it; one rule is easier to trust
  than two.
- **`docker rm -f` anywhere, and stop or remove by name** — the id race above.
- **A test-only knob for the waits** in a teacher's launcher — a pretend
  `sleep` does it without one.
- **The launcher writing the trail line itself**, as #280's and #189's lines
  do. It would cover command-line runs, but the event would have no app call
  site and two writers for one sentence.

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
program took the port after the workspace was made) answers too, so this
check cannot see it; since #310 the look below asks whose the listener is.
**Do not tighten this to require a real page**: nothing is served before the
build, so that would refuse every healthy Mac.

**Why a connection and not `lsof`.** Measured on the development Mac
(Apple silicon, Colima vz aarch64, 2026-09-25): curl to a forwarded port with
nothing inside answers 52 in 0.01–0.03 s; to a port nothing listens on, 7 in
0.01 s; `lsof -iTCP:<port> -sTCP:LISTEN` takes 0.228 s. Worse, `lsof` run as
the teacher sees only the teacher's own programs: a root-owned listener (:88,
`kdc`) is invisible to it and answers curl. A forwarder owned by anybody else
would read as missing and refuse a healthy Mac. All 48 host ports published by
six running workspaces had a listener. (Since #310 `lsof` is asked below, but
only for which listeners are THIS account's own, under an engine whose
forwarder always is.) `-q` comes first so the teacher's
`~/.curlrc` is never read, and `--noproxy '*'` so a proxy setting cannot
answer for this Mac.

**The retry is a bounded re-asking of the real question, not a settle-delay.**
A healthy Mac answers on the first try; #225 measured the listener appearing
0.10–0.24 s after the builder is created or started (0.15 s under load). The
bound is for the one case **nobody has measured: the first address after the
builder's virtual machine starts cold.** That is not rare — since #220,
quitting Plantoir stops the VM when nothing else uses it, so it is the first
preview of most days — which is why a run that started the VM
(`ensure_container_runtime` sets `THIS_RUN_STARTED_THE_BUILDER` on every
path past its "already running" return) allows 60 tries. The assignment, and
the `""` before the call, are in all THREE launchers' copies, although only
`preview.sh` reads the flag: the first-run code from `_download()` to the
`ensure_container_runtime` call is one text in all three, and #263's test
holds it identical — a line in one copy only would turn that red. Measuring it would have meant a throwaway second Colima
profile on Russell's Mac; the director ruled that out, so the number stays
unmeasured. Instead, **a run that needed more than one try says so in the
console** (`reachedAfterRetrying`, "…took N tries"), so the next transcript a
teacher sends carries the figure the bound rests on.

**No gate exercises the probe against a real forward.** Every `preview.sh`
that `verify.sh` runs is `--build-only` (or `--stop`), and `--build-only`
returns before the question is asked; `scripts/test_preview_reach.py` stubs
curl. A serving preview was checked by hand in the implementation review
(2026-09-25): `./preview.sh EXC2O 1 --image quartz-teacher:dev-test
--non-interactive` against a real Colima forward announced
`http://localhost:8241/` on the first try, with no "took N tries" line. Five
real Colima forwards with nothing inside answered curl 52 in 0.031–0.035 s;
a listener that accepts and closes answers 56, one that never answers 28 —
both go ahead.

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

#### Before building, preview.sh makes sure the address is this account's own (#310)

Right after the reach check passes, and before anything is announced or
built, `announce_the_preview_address` asks `held_by_someone_else <host port>`
— under Colima only (`the_engine_forwards_from_this_account`, the same gate
the look before a start uses). It reads ONE kernel list (`netstat -an -p
tcp`) and ONE list of this account's listeners (`lsof`), and the address is
somebody else's when **the kernel has more listening sockets on that port
than this account owns**, and this account's list is not empty. On a healthy
Colima Mac the counts are equal: the forward is this account's own `ssh`
(measured). The cases, with harness-readable fields, are
`contracts/app-rules.json` → `previewPorts.whenAnotherAccountHasTheAddress.cases`;
`scripts/test_preview_reach.py` → `WhoseAddressItIs` runs every one with
`netstat`, `lsof`, `docker` and the remake stubbed as shell functions (the
harness's PATH is the real one, so a program stub would let the real
`netstat` in), and `scripts/test_port_blocks.py` →
`TheLookBeforeTheAnnouncement` runs the real remake behind it.

When it is somebody else's: the ♻️ lines, `remake_the_workspace`, and only
after it RETURNS the marker
`PLANTOIR_PREVIEW_ADDRESS_HELD: remade <port> <course>/<section>` (a remake
#94 refuses exits inside it, so the trail gets #94's line and never a claim
of a rebuild that did not happen) — so #94's look applies, and an open preview of
another section from this folder refuses with #94's own sentence rather than
being ended. The remade workspace's walk reads the kernel's list, so its new
block is free when it is picked; the address is asked for, reached and
looked at AGAIN. Still somebody else's: `whenAnotherAccountHasTheAddress
.sentence`, the `refused` marker, exit 1 with nothing announced — #235's
shape, so the app needs no change. **Never a second remake**: rebuilding in a
loop against a listener that follows costs two minutes a turn and fixes
nothing. The remade workspace skips the earlier "Preflight: checking Quartz
sidebar anchor" look; it only warns, and the new workspace is made from the
image that was just looked at.

**Why counts, not "is one of them ours".** Colima's forward is IPv4 only
(`[::1]` refused, measured). A listener on `::1` alone in another account
sits BESIDE it — different family, no collision — and `localhost`, which the
app opens, tries `::1` first. Measured with a same-account stand-in on
18282: `curl http://localhost:18282/` reached the OTHER server, `curl
http://127.0.0.1:18282/` ours, and `lsof` listed our forward on the port.
Presence would have announced that address; counts catch it (two kernel
rows, one of ours). Only the SITE port is looked at: a shadowed live-reload
port costs only refresh, and #234 declined the same widening.

**It fails OPEN, like the reach check.** Not Colima, no kernel row on the
port, an unreadable kernel list, a missing `lsof`, or an EMPTY `lsof` list
(this account always owns `limactl`'s listeners under Colima, so empty means
`lsof` did not work) — each goes ahead as before #310. `DOCKER_HOST` naming
anything outside `~/.colima/` or `$COLIMA_HOME` switches the look off (a `tcp://` address at the Colima VM itself is still Colima, and is read as not — a developer-only corner) and prints the
`unchecked` marker once, so a developer's trail says the look was not made.

**Where "which account" is not said.** The sentence names both things the
check proves it could be — another account, or macOS itself — because the
kernel shows a listener and this account owns none. Telling them apart would
mean `netstat -v`'s `process:pid` column (it has moved between macOS
releases) and then `ps -o user=`, which puts another person's username a step
from this teacher's trail. Rejected.

**The trail.** All four outcomes (`before-start`, `remade`, `refused`,
`unchecked`) are one mac-only event, `preview address held by another
account`, written by the APP from the marker (`PreviewAddressHeldReport`,
read by `ScriptRunner` and hidden from the console by `TranscriptBuilder`), the
same arrangement as `workspace was in use` and for the same reason: one
writer for its words. A preview typed at the command line leaves the console
sentence and no trail line. A scheduled publish never prints the marker.

**No gate exercises this against a real second account** — nothing here can
sign in as one. `verify.sh` runs only `--build-only` previews, which ask
nothing. The acceptance is Russell's, in the rehearsal account: account 1
previews and holds 8081; account 2 sets up and previews and must announce
8091 and show ITS site. Then, for the look before a start: with account 2's
workspace stopped (quit Plantoir there), account 1 opens a second folder so
it listens on 8091, and account 2 previews again — expect the two ♻️ lines
and a site on a new address, not account 1's. Until that is done, the
other-account half rests on root as the stand-in (a different uid, which is
all XNU compares).

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
  `deploy.py` is entered — or, since #227, exits 1 when the copy did not
  finish, and makes a relative `--to-folder` a full path from the working
  folder first (see [`07-deployment.md`](07-deployment.md) → "A relative
  folder, and a copy that did not finish") — so a refusal written only in the
  shared Python would not run on it. Measured with the guard removed: the launcher published the
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
