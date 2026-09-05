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

### One container per working folder

Each working folder gets its own container, named
`teaching-quartz-<hash>` where the hash is the first eight characters of
`pwd -P | shasum -a 256` — so two folders (this year's courses and last
year's, say) never repoint each other's mounts, and can preview at the same
time. At creation the launcher probes for a free block of HOST ports
(bases 8081, 8091, 8101, 8111, 8121, 8131 — four site ports each, plus a
matching +1000 websocket block for Quartz's live reload) and maps it to
the container's fixed ports 8081–8084 and 9081–9084; `preview.sh` prints the
resolved address ("Preview will be available at: …"), which is what the app
and a terminal teacher should open. The old shared `teaching-quartz`
container is retired automatically the first time a per-folder container is
created. The macOS app stops a folder's container (a fast `docker stop`,
not a removal) when the last window using that folder closes, and on quit —
the container holds no content, and restarts in about a second on the next
preview.
- `--context NAME` (setup only) — select a Docker context.
- `--image REF` — use a specific already-built image instead of resolving
  one from the recipe (how `verify.sh` points the launchers at its
  `dev-test` build). In `preview.sh` the image pre-parser deliberately
  scans the whole argument list, since the flag follows the course and
  section.

The scripts then ensure a container runtime is available (next section)
and build the image locally if the recipe's tag is missing — nothing is
ever pulled from a registry.

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

## 4. Mount-aware container lifecycle

This is the most subtle part of the launchers. Each working folder has its
own long-lived container (see "One container per working folder" above),
started as:

```bash
docker run -dit --name "teaching-quartz-${WORKDIR_ID}" \
  -v "$(pwd)/courses":/teaching/courses \
  -p ${HOST_BASE}-$((HOST_BASE+3)):8081-8084 \
  -p $((HOST_BASE+1000))-$((HOST_BASE+1003)):9081-9084 \
  "$IMAGE" tail -f /dev/null
```

where `WORKDIR_ID` is the folder hash and `HOST_BASE` the probed port
block. Every launcher inspects the existing container before using it:

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
6. Otherwise, start the container if stopped, or reuse it as-is.

Recreating the container is cheap because all state lives in the bind mount.

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
  `--port N` (container port 8081–8084) and `--image REF`.
- Checks host-side that the course is set up (`course_config.json` exists)
  and that the section folder is there. The `section_numbers` check itself
  runs in the container once it is up (`docker exec … python3 -`), so a typo
  like section `2` in a course with sections `1,3,4` still fails before any
  build starts, with a helpful message.
- Runs `build_site.py`, which (by default) ends by serving the site on
  the requested container port (8081–8084), with Quartz's live-reload
  websocket on port + 1000 (`--wsPort`) — the reason the container
  publishes both ranges. The reachable HOST address is the folder's
  probed block; `preview.sh` prints it.

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

---

[◀ Previous: The Docker Image](02-docker-image.md) · [Back to index](README.md) · [Next: Course Setup ▶](04-course-setup.md)
