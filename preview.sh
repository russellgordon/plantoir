#!/bin/bash
# ---- Determine host OS for help text ---------------------------------
_detect_host_os() {
  local u
  u="$(uname -s 2>/dev/null || echo "")"
  case "$u" in
    Darwin) echo mac ;;
    MINGW*|MSYS*|CYGWIN*) echo windows ;;
    *) echo linux ;;
  esac
}
_PREVIEW_HOST_OS="$(_detect_host_os)"
if [[ "$_PREVIEW_HOST_OS" == "windows" ]]; then
  SELF_CMD=".\\preview.bat"
else
  SELF_CMD="./preview.sh"
fi
# ----------------------------------------------------------------------

# Ensure we're in the same directory as this script
cd "$(dirname "$0")"

# Arguments
COURSE="$1"
SECTION="$2"

# Shift COURSE and SECTION out of the way
shift 2


# -------------------- Image selection & options (parity with setup.sh) --------------------
# ---- The image is built HERE, from this folder's own recipe ----------
# The working folder carries the toolchain's build recipe (.toolchain/,
# kept current by the app) — or IS the repository, with a Dockerfile
# beside this script. The image tag is a hash of the recipe's contents:
# a changed recipe means a new tag, a fresh local build, and — via the
# image-mismatch check further down — a recreated container. No registry
# and no account are involved; the recipe travels with the app.
OVERRIDE_IMAGE="${OVERRIDE_IMAGE:-}"

# Parse the image flag only; every other flag is for the parser further
# down. Scan the WHOLE argument list — flags follow the course and
# section, so stopping at the first non-flag word would never see them
# (that is exactly how verify.sh's --image went unrecognized).
_SAVED_ARGS=("$@")
while [[ $# -gt 0 ]]; do
  case "$1" in
    --image)
      if [[ $# -lt 2 ]]; then echo "❌ --image requires a value"; exit 1; fi
      OVERRIDE_IMAGE="$2"; shift 2 ;;
    *) shift ;;
  esac
done
set -- "${_SAVED_ARGS[@]}"

resolve_build_context() {
  if [[ -f "./Dockerfile" ]]; then
    echo "."
  elif [[ -f "./.toolchain/Dockerfile" ]]; then
    echo "./.toolchain"
  else
    return 1
  fi
}

toolchain_hash() {
  # Hash only what the recipe is made of. In a working folder the context
  # (.toolchain/) contains nothing else, so the prunes change nothing —
  # but in the repository the context is the repo root, and without them
  # this walked (and checksummed) courses/, node_modules, and the app
  # sources: many minutes of hashing, and a tag that changed on every
  # build because build outputs were part of it.
  # One shasum per file meant one PROCESS per file. With the example
  # content and the subject skeletons inside the recipe that is ~5,700
  # files (and growing), and
  # the spawning alone took 35 seconds before anything appeared on screen.
  # xargs batches them into a handful of invocations: same lines, same
  # order, byte-identical hash, under a fifth of a second.
  local context="$1"
  (cd "$context" && find . \
      \( -path './.git' -o -path './courses' -o -path './mac-app' \
         -o -name node_modules -o -name '.merged_output' \
         -o -name '.verify-export.*' \) -prune \
      -o -type f -not -name '.DS_Store' -print0 \
    | LC_ALL=C sort -z \
    | xargs -0 shasum -a 256 \
    | shasum -a 256 | cut -c1-8)
}

BUILD_CONTEXT=""
if [[ -n "$OVERRIDE_IMAGE" ]]; then
  IMAGE="$OVERRIDE_IMAGE"
else
  BUILD_CONTEXT=$(resolve_build_context) || {
    echo "❌ This folder is missing the toolchain's build recipe."
    echo "   Open the folder in the app once to refresh it, or run from a"
    echo "   copy of the repository."
    exit 1
  }
  echo "🔎 Checking whether your website builder is up to date…"
  IMAGE="teaching-quartz:src-$(toolchain_hash "$BUILD_CONTEXT")"
fi


# Initialize flags
INCLUDE_SOCIAL=""
FORCE_NPM_INSTALL=""
FULL_REBUILD=""
BUILD_ONLY=""   # NEW: replaces --no-preview

# Normalize COURSE to uppercase (avoid 'o' vs 'O' issues)
COURSE="$(printf '%s' "$COURSE" | tr '[:lower:]' '[:upper:]')"

# Guardrail: catch 'Open' course codes mistyped with trailing zero (e.g., ICD20)
# Ontario course codes are 3 letters + digit + level letter (U/C/M/E/O). Open ends in 'O' (oh), not zero.
if [[ "$COURSE" =~ ^[A-Z]{3}[0-9]0$ ]]; then
  SUGGESTED="${COURSE%0}O"
  echo ""
  echo "🤔 It looks like you entered '${COURSE}' (ends with zero)."
  echo "   Ontario 'Open' level course codes end with the LETTER 'O' (oh)."
  # If a correctly-named course already exists, mention it to build confidence
  if [[ -f "courses/$SUGGESTED/course_config.json" && ! -f "courses/$COURSE/course_config.json" ]]; then
    echo "   I see setup data for '$SUGGESTED' on disk."
  fi
  read -rp "   Fix course code to '$SUGGESTED'? [Y/n]: " _ans
  _ans="${_ans:-Y}"
  if [[ "$_ans" =~ ^[Yy]$ ]]; then
    COURSE="$SUGGESTED"
    echo "✅ Using corrected course code: $COURSE"
  else
    echo "ℹ️  Continuing with: $COURSE"
  fi
  echo ""
fi

# Display help text if requested
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
  echo ""
  echo "🧰 Usage:"
  echo "  $SELF_CMD <COURSE_CODE> <SECTION_NUMBER> [options]"
  echo ""
  echo "📘 Required arguments:"
  echo "  <COURSE_CODE>               The course code (e.g., ICS3U)"
  echo "  <SECTION_NUMBER>            The TIMETABLE section number (e.g., 1, 3, 4)"
  echo ""
  echo "⚙️ Optional flags:"
  echo "  --include-social-media-previews    Enable Quartz CustomOgImages emitter"
  echo "  --force-npm-install                Force npm install even if dependencies are present"
  echo "  --full-rebuild                     Clear entire output folder and re-copy Quartz scaffold"
  echo "  --build-only                       Build the static site only (no local preview server)"
  echo "  --stop                             Stop this section's preview processes (build or server) and exit"
  echo "  --port N                           Serve the preview on port N (default 8081; 8081-8084 available)"
  echo "  --help, -h                         Show this help message"
  echo ""
  echo "📂 Output location (hidden in Obsidian Files pane):"
  echo "  courses/<COURSE_CODE>/.merged_output/section<SECTION_NUMBER>"
  echo ""
  echo "  That is a shortcut. The built website itself is kept OUTSIDE your"
  echo "  working folder, in:"
  echo "    ~/Library/Application Support/Plantoir/builds/"
  echo "  so that copying, zipping, backing up or syncing your course folder"
  echo "  no longer carries thousands of files that can be built again. Your"
  echo "  course notes are untouched, and the path above still works."
  echo ""
  echo "📝 Notes:"
  echo "  • Default behavior is to build-and-serve once via Quartz (no double build)."
  echo "  • Use --build-only if you only want the static 'public/' output without serving."
  echo "  • If your course code ends with '0' (zero), you'll be prompted to correct it to 'O' for Open-level courses."
  echo ""
  exit 0
fi

# Each preview serves on its own container port (8081-8084), so several
# can run at once. Declared before the parser and the validation that
# follow — a later default would stomp the flag, and a later declaration
# leaves the validation reading an empty value. Both happened.
PREVIEW_PORT=8081

# Parse optional flags
while [[ "$#" -gt 0 ]]; do
  case $1 in
    --include-social-media-previews)
      INCLUDE_SOCIAL="--include-social-media-previews"
      ;;
    --force-npm-install)
      FORCE_NPM_INSTALL="--force-npm-install"
      ;;
    --full-rebuild)
      FULL_REBUILD="--full-rebuild"
      ;;
    --build-only)
      BUILD_ONLY="--build-only"
      ;;
    --stop)
      STOP_MODE="1"
      ;;
    --port)
      if [[ $# -lt 2 ]]; then echo "❌ --port requires a value"; exit 1; fi
      PREVIEW_PORT="$2"
      shift
      ;;
    --image)
      # Already applied by the image pre-parser; consume the value here.
      shift
      ;;
    *)
      echo "❌ Unknown option: $1"
      echo "Use './preview.sh --help' to see usage instructions."
      exit 1
      ;;
  esac
  shift
done

# Validate course and section
if [ -z "$COURSE" ] || [ -z "$SECTION" ]; then
  echo "❌ Missing required arguments."
  echo "Use './preview.sh --help' to see usage instructions."
  exit 1
fi

# Ensure SECTION looks like a positive integer
if ! [[ "$SECTION" =~ ^[0-9]+$ ]]; then
  echo "❌ SECTION must be a positive integer (the timetable section number)."
  exit 1
fi

# The chosen port must be one the container publishes.
if ! [[ "$PREVIEW_PORT" =~ ^808[1-4]$ ]]; then
  echo "❌ --port must be between 8081 and 8084."
  exit 1
fi

OUTPUT_PATH="courses/$COURSE/.merged_output/section$SECTION"

# Preflight: ensure this course has been set up (host-side)
COURSE_CFG="courses/$COURSE/course_config.json"
if [[ ! -f "$COURSE_CFG" ]]; then
  echo "⚠️  $COURSE_CFG not found."
  echo "   It looks like you haven't completed setup for '$COURSE' yet."
  echo "   Run: ./setup.sh"
  echo "   (Then select or create the course '$COURSE' when prompted.)"
  exit 1
fi

# Preflight: the section folder should exist (setup_course.py creates 'section<N>')
if [[ ! -d "courses/$COURSE/section$SECTION" ]]; then
  echo "⚠️  courses/$COURSE/section$SECTION does not exist."
  echo "   If this is one of your timetable sections, run './setup.sh' again and include section $SECTION."
  echo "   Otherwise, choose one of YOUR assigned sections when running this command."
  # don't exit here yet; we'll validate against section_numbers below
fi

# -------------------- Mount-aware container handling --------------------
# ---- One container per working folder --------------------------------
# The container's name is derived from THIS folder, so two working folders
# (this year's courses and last year's, say) each get their own container
# and never repoint each other's mounts. The same derivation is used by
# the macOS app; the trailing newline from pwd is part of the hashed
# input, so keep `pwd -P | shasum` exactly as written.
WORKDIR_ID="$(pwd -P | shasum -a 256 | cut -c1-8)"
CONTAINER_NAME="teaching-quartz-${WORKDIR_ID}"

# >>> BUILD OUTPUT BLOCK >>> — identical in setup.sh, preview.sh and
# deploy.sh, and extracted between these two markers by
# scripts/test_build_output_link.sh, which runs the real thing against the
# states an existing teacher's folder can be in. Keep the markers, and keep
# the three copies the same.
# ---- Built websites live OUTSIDE this folder -------------------------
# A built site is DERIVED: every file in it comes from the teacher's notes
# and can be made again. It used to be written to
# courses/<CODE>/.merged_output, INSIDE the working folder — where a cloud
# service uploads every build and charges it to the teacher's quota, Time
# Machine backs it up, a zip or a Finder copy carries it, and Get Info
# counts it. It lives here instead, for EVERY working folder rather than
# only the synced ones: the benefit is not confined to syncing, and one
# code path is one code path.
#
# courses/<CODE>/.merged_output becomes a SYMLINK to this folder, so every
# script, every scheduled publish and every teacher at the command line
# still names the same path and still finds the site. Under $HOME on
# purpose: the container VM mounts only the home folder, so a builds
# folder anywhere else would appear EMPTY inside the container and every
# build would seem to vanish. It is bind-mounted into the container at the
# SAME absolute path, so the link resolves to the same place on both sides.
#
# The identical rule is in the app (BuildOutputLocation.swift) and written
# down in contracts/shared-rules.json -> buildOutputLocation. It is here as
# well because a teacher at the command line, and a publish scheduled with
# launchd, have no app to do it for them.
# ${HOME%/} rather than $HOME: a trailing slash would make this path differ
# from the one Docker stores (it cleans a mount destination), and the "does
# this container have the builds mount" check below would then be false on
# every run and recreate the container every time.
BUILD_ROOT="${HOME%/}/Library/Application Support/Plantoir/builds/${WORKDIR_ID}"

# Makes the folder the container mounts, and writes down which working
# folder it belongs to — the id is a hash and cannot be read backwards, so
# without this a builds folder left behind by a deleted working folder
# could never be recognised as abandoned.
ensure_build_root() {
  mkdir -p "$BUILD_ROOT" 2>/dev/null || true
  printf '%s\n' "$(pwd -P)" > "$BUILD_ROOT/working-folder.txt" 2>/dev/null || true
}

# Adds one line to the breadcrumb trail the app keeps, so that a move done by
# the command line — or by a publish launchd ran at six in the morning, weeks
# before the app is next opened — leaves the same line the app would have
# left. Without this the trail would record only the moves the GUI happened to
# make, which is the half a teacher never asks about.
#
# Same file, same shape as ActivityTrail: "YYYY-MM-DD HH:MM:SS · sentence".
# The app trims the file when it grows; nothing here needs to. Carries a
# course code and nothing else — never a path, never a credential.
note_on_the_trail() {
  local trail="${HOME%/}/Library/Logs/Plantoir"
  mkdir -p "$trail" 2>/dev/null || return 0
  printf '%s · %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$trail/activity.txt" 2>/dev/null || true
}

# Points courses/<CODE>/.merged_output at this course's folder under
# BUILD_ROOT, moving an existing built site out of the working folder on
# the way. Safe to run every time: when the link is already right this
# touches nothing.
#
# A course with NO link is a course whose build cannot be trusted.
# Archiving a course, restoring one from a backup, and replacing a course's
# contents all remove the link along with everything else in the folder —
# and each of them leaves content whose timestamps may be OLDER than the
# site standing outside. Reusing that build would let a restored course
# publish last month's pages while every check said it was up to date. So a
# build folder with no link pointing at it is CLEARED, never adopted.
link_course_build_output() {
  local course="$1"
  local course_dir link target current
  # A course code, not a path. Checked here rather than trusted, because
  # this runs before deploy.sh has validated its argument and `..` would
  # otherwise put a link at the top of the working folder and aim a
  # deletion at the builds root's own parent.
  case "$course" in
    ""|*/*|.|..) return 0 ;;
  esac
  course_dir="$(pwd)/courses/$course"
  [ -d "$course_dir" ] || return 0
  # A COURSE, not just any folder in courses/. `_backups` lives there too,
  # and setup.sh links every folder it finds — a link inside the backups
  # folder would be litter at best and a place to build into at worst.
  [ -f "$course_dir/course_config.json" ] || return 0
  link="$course_dir/.merged_output"
  target="$BUILD_ROOT/$course"
  ensure_build_root

  # EVERY step below may fail without stopping the run, and that is
  # deliberate: setup.sh and deploy.sh run under `set -e`, so an unguarded
  # ln, mv or mkdir would turn "the built website could not be moved" into
  # "publishing is broken", with no message. Whenever anything here fails
  # the course is left exactly as it was and the build writes a real
  # .merged_output folder inside it — which is what it did before any of
  # this existed, so the fallback is the old behaviour rather than a
  # broken one.
  if [ ! -d "$BUILD_ROOT" ]; then
    echo "⚠️  Could not use $BUILD_ROOT for built websites; keeping them inside your course folder."
    return 0
  fi

  # -L first: `-d` is true for a symlink pointing at a directory, so asking
  # the other way round would take every already-linked course down the
  # migration path and move the builds folder into itself.
  if [ -L "$link" ]; then
    current="$(readlink "$link" 2>/dev/null || true)"
    if [ "$current" = "$target" ] && [ -d "$target" ]; then
      return 0
    fi
    # A link pointing somewhere else: a course renamed outside the app, or a
    # course folder synced from ANOTHER Mac, where the path names a different
    # home folder.
    #
    # ADOPTING a build already sitting here was proposed and rejected. It
    # looks better — a teacher switching between two Macs would keep each
    # machine's build instead of rebuilding after every switch — but the
    # second Mac cannot tell "the folder came back unchanged" from "the
    # folder was archived and restored while I was shut", and in the second
    # case the pages it adopts a build for are OLDER than that build, so the
    # freshness check says up to date and the teacher publishes what they
    # undid. Clearing costs one rebuild, which is cheap and visible.
    rm -f "$link" 2>/dev/null || return 0
  elif [ -d "$link" ]; then
    echo "📦 Moving ${course}'s built website out of your working folder…"
    rm -rf "$target" 2>/dev/null || true
    if ! mv "$link" "$target" 2>/dev/null; then
      echo "⚠️  Could not move it; leaving the built website where it is."
      return 0
    fi
    if ln -s "$target" "$link" 2>/dev/null; then
      echo "✅ Built websites for this folder are kept in: $BUILD_ROOT"
      note_on_the_trail "moved ${course}'s built website out of the working folder, so it is no longer copied, synced or backed up with the course"  # contracts/shared-rules.json -> activityTrail.mustRecord."built site moved out of the working folder".line
    else
      # The move worked and the link did not. Put it back: a course with
      # its built site in the old place still builds and still publishes,
      # while a course with neither has lost its website for no reason.
      mv "$target" "$link" 2>/dev/null || true
      echo "⚠️  Could not move it; leaving the built website where it is."
    fi
    return 0
  elif [ -e "$link" ]; then
    rm -f "$link" 2>/dev/null || return 0
  fi

  rm -rf "$target" 2>/dev/null || true
  mkdir -p "$target" 2>/dev/null || return 0
  ln -s "$target" "$link" 2>/dev/null || true
}
# <<< BUILD OUTPUT BLOCK <<<
PREVIEW_PORT_RANGE="8081-8084"
# Each preview also uses a live-reload websocket on port + 1000.
PREVIEW_WS_RANGE="9081-9084"
HOST_COURSES="$(pwd)/courses"  # desired host mount for this run

# ==================== Container runtime (Colima) ====================
# Docker Desktop is no longer required. This script uses Colima
# (https://github.com/abiosoft/colima), a free, open-source container
# runtime for macOS, and installs/starts it automatically as needed.
# Any already-working Docker engine (including Docker Desktop) is used as-is.

_wait_for_docker() {
  local tries="${1:-30}"
  local i
  for ((i=0; i<tries; i++)); do
    docker info >/dev/null 2>&1 && return 0
    sleep 2
  done
  return 1
}

# ---- Tools install themselves; nothing is asked of the teacher --------
# Everything the toolchain needs on the host — Colima, Lima, the Docker
# CLI, and BuildKit — downloads as static binaries into the app's own
# space under Application Support. No Homebrew, no administrator rights.
# Tools already on the machine (Homebrew installs included) are used
# as-is; downloads happen only for what is missing.
TOOLS_DIR="$HOME/Library/Application Support/Plantoir/tools"
export PATH="$TOOLS_DIR/bin:$PATH"

# -------------------- Stop mode ----------------------------------------
# ./preview.sh CODE N --stop : kill this section's preview processes
# INSIDE the container. Ending the host-side script (closing the app's
# preview, Ctrl+C at the wrong moment) leaves the container-side build
# or server running — idle for a server, but a mid-flight build keeps
# burning CPU. This mode reclaims those resources. It must never start
# anything: no engine bootstrap, no image build, no container creation —
# if nothing is running, there is nothing to stop.
#
# Processes are found by WORKING DIRECTORY, not port: everything a
# preview runs (python3, npm, node, esbuild) lives in the section's
# .merged_output folder, so this catches builds as well as servers and
# can never touch another section's processes.
if [[ -n "${STOP_MODE:-}" ]]; then
  if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
    echo "✅ Nothing to stop — the website builder isn't running."
    exit 0
  fi
  if ! docker ps --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}$"; then
    echo "✅ Nothing to stop — no container is running for this folder."
    exit 0
  fi
  echo "🧹 Stopping preview processes for ${COURSE} section ${SECTION}…"
  docker exec -i -e TARGET_DIR="/teaching/courses/${COURSE}/.merged_output/section${SECTION}" "$CONTAINER_NAME" python3 - <<'PY'
import os
import signal
import time

target = os.environ["TARGET_DIR"]
alt_target = target.replace("/teaching/courses/", "/tmp/quartz-builds/").replace("/.merged_output/", "/")
# .merged_output is a SYMLINK to the builds folder outside the working
# folder, and /proc/<pid>/cwd is the REAL path a process is sitting in —
# never the spelling it used to get there. Without the resolved form this
# sweep matched nothing at all the moment the build output moved, so
# --stop would report success and leave the build running.
targets = []
for candidate in [target, alt_target]:
    if not candidate:
        continue
    if candidate not in targets:
        targets.append(candidate)
    resolved = os.path.realpath(candidate)
    if resolved not in targets:
        targets.append(resolved)
own_pid = os.getpid()

def preview_pids():
    """PIDs whose working directory is inside this section's output."""
    found = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        pid = int(entry)
        if pid == own_pid:
            continue
        try:
            cwd = os.readlink(f"/proc/{entry}/cwd")
        except OSError:
            continue
        if any(cwd == t or cwd.startswith(t + "/") for t in targets):
            found.append(pid)
    return found

victims = preview_pids()
for pid in victims:
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
if victims:
    time.sleep(1)
for pid in preview_pids():
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
print(f"✅ Stopped {len(victims)} process(es).")
PY
  exit 0
fi

# Everything below builds, so this is the point the built website's home has
# to be settled — after stop mode, which must never create anything.
link_course_build_output "$COURSE"

# Pinned versions, bumped deliberately with toolchain updates.
COLIMA_VERSION="v0.10.3"
LIMA_VERSION="2.2.0"
DOCKER_CLI_VERSION="29.7.2"
BUILDX_VERSION="v0.36.1"
# Colima's size, computed from this Mac rather than pinned.
#
# The old fixed 2 CPUs / 4 GB was chosen for an 8 GB machine and then applied
# to every machine, so a 48 GB Mac built its site with the same sliver as a
# laptop. These are deliberately NOT the whole machine: the teacher is using
# the Mac while a build runs, so half the cores and a third of the RAM, with
# the old values as the floor — an 8 GB Mac gets exactly what it gets today.
_colima_cpus() {
  local host_cpu cpus
  host_cpu=$(sysctl -n hw.ncpu 2>/dev/null || echo 2)
  cpus=$(( host_cpu / 2 ))
  [ "$cpus" -lt 2 ] && cpus=2
  [ "$cpus" -gt 6 ] && cpus=6
  echo "$cpus"
}

_colima_memory_gb() {
  local host_bytes host_gb mem
  host_bytes=$(sysctl -n hw.memsize 2>/dev/null || echo 8589934592)
  host_gb=$(( host_bytes / 1073741824 ))
  mem=$(( host_gb / 3 ))
  [ "$mem" -lt 4 ] && mem=4
  [ "$mem" -gt 12 ] && mem=12
  echo "$mem"
}
# Colima may already exist, sized by an earlier Plantoir or by another
# toolchain that shares it. Two rules keep that civil:
#
#   1. Only ever ASK FOR MORE. A teacher (or another tool) who gave Colima
#      extra room keeps it; we never shrink somebody else's VM.
#   2. Only while it is STOPPED. Resizing means recreating the VM, which
#      would take down containers that other toolchains are using.
#
# Prints the flags to add to `colima start`, or nothing when it is already
# big enough.
_colima_growth_flags() {
  local current_cpus current_memory_gb wanted_cpus wanted_memory_gb
  read -r current_cpus current_memory_gb <<< "$(
    colima list 2>/dev/null | awk '$1=="default" { gsub(/GiB/, "", $5); print $4, $5 }'
  )"

  # No VM yet: the caller's first-start path handles sizing.
  [ -z "${current_cpus:-}" ] && return 0

  wanted_cpus=$(_colima_cpus)
  wanted_memory_gb=$(_colima_memory_gb)

  # Non-numeric memory (a MiB-sized VM, say) counts as smaller than anything.
  case "$current_memory_gb" in
    ''|*[!0-9]*) current_memory_gb=0 ;;
  esac
  case "$current_cpus" in
    ''|*[!0-9]*) current_cpus=0 ;;
  esac

  [ "$wanted_cpus" -le "$current_cpus" ] && wanted_cpus="$current_cpus"
  [ "$wanted_memory_gb" -le "$current_memory_gb" ] && wanted_memory_gb="$current_memory_gb"

  if [ "$wanted_cpus" -gt "$current_cpus" ] || [ "$wanted_memory_gb" -gt "$current_memory_gb" ]; then
    echo "--cpu $wanted_cpus --memory $wanted_memory_gb"
  fi
}



_download() {
  local url="$1" destination="$2" label="$3"
  echo "📦 Getting ${label}…"
  if ! curl -fsSL --retry 3 -o "$destination" "$url"; then
    echo "❌ Could not download ${label}."
    echo "   An internet connection is needed for this one-time setup."
    exit 1
  fi
}

ensure_local_tools() {
  mkdir -p "$TOOLS_DIR/bin"
  local arch lima_arch docker_arch buildx_arch
  arch="$(uname -m)"
  if [[ "$arch" == "arm64" ]]; then
    lima_arch="arm64"; docker_arch="aarch64"; buildx_arch="arm64"
  else
    arch="x86_64"; lima_arch="x86_64"; docker_arch="x86_64"; buildx_arch="amd64"
  fi

  if ! command -v limactl >/dev/null 2>&1; then
    local lima_tgz="$TOOLS_DIR/lima.tar.gz"
    _download "https://github.com/lima-vm/lima/releases/download/v${LIMA_VERSION}/lima-${LIMA_VERSION}-Darwin-${lima_arch}.tar.gz" "$lima_tgz" "the virtual machine manager"
    tar xzf "$lima_tgz" -C "$TOOLS_DIR"
    rm -f "$lima_tgz"
  fi

  if ! command -v colima >/dev/null 2>&1; then
    _download "https://github.com/abiosoft/colima/releases/download/${COLIMA_VERSION}/colima-Darwin-${arch}" "$TOOLS_DIR/bin/colima" "the container runtime"
    chmod +x "$TOOLS_DIR/bin/colima"
  fi

  if ! command -v docker >/dev/null 2>&1; then
    local docker_tgz="$TOOLS_DIR/docker.tar.gz"
    _download "https://download.docker.com/mac/static/stable/${docker_arch}/docker-${DOCKER_CLI_VERSION}.tgz" "$docker_tgz" "the container tools"
    tar xzf "$docker_tgz" -C "$TOOLS_DIR"
    mv -f "$TOOLS_DIR/docker/docker" "$TOOLS_DIR/bin/docker"
    rm -rf "$TOOLS_DIR/docker" "$docker_tgz"
  fi

  ensure_buildx
}

# BuildKit is what builds the image. Without the plugin the build silently
# degrades to the legacy builder, which corrupts the export-scripts layer.
ensure_buildx() {
  if docker buildx version >/dev/null 2>&1; then
    return 0
  fi
  local arch buildx_arch
  arch="$(uname -m)"
  if [[ "$arch" == "arm64" ]]; then buildx_arch="arm64"; else buildx_arch="amd64"; fi
  mkdir -p "$HOME/.docker/cli-plugins"
  _download "https://github.com/docker/buildx/releases/download/${BUILDX_VERSION}/buildx-${BUILDX_VERSION}.darwin-${buildx_arch}" "$HOME/.docker/cli-plugins/docker-buildx" "the image builder"
  chmod +x "$HOME/.docker/cli-plugins/docker-buildx"
}

ensure_container_runtime() {
  # Fast path: any working Docker daemon means there is nothing to do —
  # beyond making sure BuildKit is present to build with.
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    ensure_buildx
    return 0
  fi

  echo "🐳 Setting up this Mac — a one-time step that runs on its own…"
  ensure_local_tools

  if [[ ! -d "$HOME/.colima/default" ]]; then
    echo "🚀 First start: building the virtual machine ($(_colima_cpus) CPUs · $(_colima_memory_gb) GB RAM)."
    echo "   Its disk image (~600 MB) is downloaded once; this can take several minutes."
    # vz is macOS's own virtualization — no extra software needed, unlike
    # the qemu default.
    colima start --cpu "$(_colima_cpus)" --memory "$(_colima_memory_gb)" --vm-type vz
  else
    echo "▶️  Starting Colima…"
    # shellcheck disable=SC2046  # deliberate word splitting: these are flags
    colima start $(_colima_growth_flags)
  fi

  echo "⏳ Waiting for the container runtime to be ready…"
  _wait_for_docker 30 && return 0

  # Colima can report the VM as running while its Docker daemon is dead
  # (common after sleep or an unclean shutdown); a plain start no-ops in
  # that state. Force a clean restart and wait again.
  echo "🔁 Docker isn't responding yet — restarting Colima…"
  echo "   (Colima is shared by any other Colima-based toolchains on this Mac;"
  echo "    their containers restart automatically afterwards if configured to.)"
  colima stop --force >/dev/null 2>&1 || true
  colima start >/dev/null 2>&1 || true
  _wait_for_docker 60 && return 0

  echo "❌ Colima did not become ready."
  echo "   Try running 'colima stop --force && colima start' by hand, then re-run this script."
  exit 1
}

ensure_container_runtime
CURRENT_CONTEXT=$(docker context show 2>/dev/null || echo "unknown")
HOST_ARCH=$(docker info --format '{{.Architecture}}' 2>/dev/null || echo "unknown")
HOST_OS=$(docker info --format '{{.OSType}}' 2>/dev/null || echo "unknown")
echo "🔌 Docker context: ${CURRENT_CONTEXT}"
echo "🧭 Host detected by Docker: ${HOST_OS}/${HOST_ARCH}"
echo "🖼️  Using image: ${IMAGE}"
# ====================================================================

# ---------------- Remove superseded website-builder images ----------------
# The image tag is a hash of the build recipe, so every recipe change mints a
# new tag and orphans the previous one. Nothing used to remove them, and an
# orphan never comes back on its own: a school year of Plantoir updates would
# leave a teacher a pile of images they have never heard of, and no way to
# connect "my disk is full" to this app.
#
# Deliberately narrow, because Docker here is SHARED with other projects: only
# 'teaching-quartz:src-*' tags are ever considered, never a blanket prune, and
# any tag a container still references is left alone. Removing one of these
# costs a rebuild and not data — the recipe is bundled — so the only real risk
# is touching somebody else's image, which is what the filters are for.
#
# The build cache is deliberately NOT touched: 'docker builder prune' is global
# with no per-project filter, so it would throw away other projects' cache too.
# Clearing that stays a by-hand job.
prune_superseded_images() {
  local keep_tag="$1"
  local tag
  # Refuse to run unless the tag just built is itself one of ours. With
  # --image the caller can point $IMAGE at anything (verify.sh advertises
  # exactly that), and then "keep everything except $keep_tag" would mean
  # "delete every teaching-quartz tag on the machine", including the current
  # one of every other working folder.
  [[ "$keep_tag" == teaching-quartz:src-* ]] || return 0
  local age_text
  while read -r tag age_text; do
    [[ -z "$tag" ]] && continue
    [[ "$tag" == teaching-quartz:src-* ]] || continue
    [[ "$tag" == "$keep_tag" ]] && continue
    if [[ -n "$(docker ps -aq --filter "ancestor=$tag" 2>/dev/null || true)" ]]; then
      continue
    fi
    # Leave anything built in the last day alone. The container check above is
    # a point-in-time read, and a folder that is mid-recreate (container
    # removed, replacement not yet run) references nothing for a second or
    # two — long enough for a build finishing in ANOTHER folder to delete the
    # image it is about to start. It also stops two folders on different
    # recipes from deleting each other's image on every switch, which would
    # cost a multi-minute, network-dependent rebuild each time.
    # Docker's own age column decides this, and deliberately so. The obvious
    # alternative — inspect '{{.Created}}' and compare timestamps — is a trap:
    # that field comes back in LOCAL time WITH an offset ("...T14:17:14-04:00"),
    # not the UTC "...Z" it looks like, so comparing it against a UTC cutoff is
    # silently wrong by the offset, in whichever direction the machine sits
    # from Greenwich. ('docker images --filter since=' is no help either — it
    # takes an image NAME, not a duration; the duration filters belong to
    # 'docker image prune', the blanket command this must never use.)
    #
    # Anything still measured in hours or minutes is left alone. Docker says
    # "N hours ago" up to 48 hours, so the guard is at least one day and in
    # practice up to two — erring long, which is the safe direction.
    case "$age_text" in
      *day*|*week*|*month*|*year*) ;;
      *) continue ;;
    esac
    docker rmi "$tag" >/dev/null 2>&1 || true
  done < <(docker images --filter 'reference=teaching-quartz:src-*' \
             --format '{{.Repository}}:{{.Tag}} {{.CreatedSince}}' 2>/dev/null || true)
}

# -------------------- Build the image when it is missing --------------------
build_image_if_missing() {
  if docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "✅ Website builder is ready."
    return 0
  fi
  if [[ -z "$BUILD_CONTEXT" ]]; then
    echo "❌ Image '$IMAGE' is not on this machine."
    echo "   Build it first, e.g.: docker buildx build --load -t $IMAGE ."
    exit 1
  fi
  echo "🧱 Building your website builder — the first time takes a few minutes…"
  local build_cmd=(docker buildx build --load)
  if ! docker buildx version >/dev/null 2>&1; then
    # BuildKit either way: the legacy builder silently mangles the
    # export-scripts layer.
    build_cmd=(env DOCKER_BUILDKIT=1 docker build)
  fi
  if "${build_cmd[@]}" --progress=plain -t "$IMAGE" "$BUILD_CONTEXT"; then
    echo "✅ Website builder built."
    prune_superseded_images "$IMAGE"
  else
    echo "❌ Could not build the website builder."
    echo "   The first build needs an internet connection — try again once online."
    exit 1
  fi
}
build_image_if_missing



# Finds a free block of host ports for this container: four site ports and
# their four live-reload websocket ports. Different working folders get
# different blocks, which is what lets their previews run at the same time.
find_free_port_block() {
  local base offset
  for base in 8081 8091 8101 8111 8121 8131; do
    local all_free=true
    for offset in 0 1 2 3; do
      if lsof -nP -iTCP:$((base + offset)) -sTCP:LISTEN >/dev/null 2>&1; then all_free=false; break; fi
      if lsof -nP -iTCP:$((base + 1000 + offset)) -sTCP:LISTEN >/dev/null 2>&1; then all_free=false; break; fi
    done
    if [[ "$all_free" == "true" ]]; then
      echo "$base"
      return 0
    fi
  done
  return 1
}

# The one shared container from before working folders each had their own.
# Superseded: it holds no content (everything lives on the host), and left
# running it would shadow the per-folder containers' ports.
retire_legacy_container() {
  if docker ps -a --format '{{.Names}}' | grep -Eq '^teaching-quartz$'; then
    echo "♻️  Retiring the old shared workspace container…"
    docker rm -f teaching-quartz >/dev/null 2>&1 || true
  fi
}

run_container_with_mount() {
  retire_legacy_container
  local HOST_BASE
  HOST_BASE=$(find_free_port_block) || {
    echo "❌ Could not find free ports for this folder's previews."
    echo "   Stop another preview (or another app using ports 8081+), then try again."
    exit 1
  }
  echo "🔗 Binding host courses to container: $HOST_COURSES ➜ /teaching/courses"
  # The builds folder is mounted at its OWN absolute path, unconditionally,
  # so that courses/<CODE>/.merged_output — a symlink to a path under
  # $HOME — resolves to the same place inside the container as it does
  # outside. Mounting it anywhere else would leave the link dangling in
  # here, and every build would fail on a path the teacher can plainly see
  # working in Finder. It is created before this runs: a bind mount whose
  # source is missing gives the container an empty folder of its own
  # instead, and the built site would go nowhere.
  ensure_build_root
  docker run -dit \
    --name "$CONTAINER_NAME" \
    -v "$HOST_COURSES":/teaching/courses \
    -v "$BUILD_ROOT":"$BUILD_ROOT" \
    -p ${HOST_BASE}-$((HOST_BASE + 3)):8081-8084 \
    -p $((HOST_BASE + 1000))-$((HOST_BASE + 1003)):9081-9084 \
    "$IMAGE" \
    tail -f /dev/null
}

# Whether this container was created with the builds mount. Containers made
# before built sites moved out of the working folder do not have it, and a
# mount cannot be added to a container that already exists — recreating is
# the only way. Listed and matched whole rather than asked for by name in a
# Go template, because the path contains a space.
container_has_builds_mount() {
  docker inspect -f '{{range .Mounts}}{{.Destination}}{{"\n"}}{{end}}' "$CONTAINER_NAME" 2>/dev/null \
    | grep -Fxq "$BUILD_ROOT"
}

# A container keeps running the version it was created from, so an update
# only takes effect once the container itself is recreated.
DESIRED_IMAGE_ID=$(docker image inspect --format '{{.Id}}' "$IMAGE" 2>/dev/null || echo "")
RUNNING_IMAGE_ID=$(docker inspect -f '{{.Image}}' "$CONTAINER_NAME" 2>/dev/null || echo "")

echo "🚀 Starting container if needed..."
if docker ps -a --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}$"; then
  # Container exists — check its current /teaching/courses mount
  CURRENT_MOUNT_SRC=$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/teaching/courses"}}{{.Source}}{{end}}{{end}}' "$CONTAINER_NAME" 2>/dev/null || echo "")
  if [[ -z "$CURRENT_MOUNT_SRC" ]]; then
    echo "🧩 Existing container has no /teaching/courses mount; recreating with correct mount…"
    if docker ps --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}$"; then
      docker stop "$CONTAINER_NAME" >/dev/null
    fi
    docker rm "$CONTAINER_NAME" >/dev/null || true
    run_container_with_mount
  elif [[ "$CURRENT_MOUNT_SRC" != "$HOST_COURSES" ]]; then
    echo "🔄 Detected different working directory:"
    echo "   • Existing mount: $CURRENT_MOUNT_SRC"
    echo "   • Desired mount:  $HOST_COURSES"
    echo "♻️  Recreating container '$CONTAINER_NAME' to point at the new folder…"
    if docker ps --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}$"; then
      docker stop "$CONTAINER_NAME" >/dev/null
    fi
    docker rm "$CONTAINER_NAME" >/dev/null || true
    run_container_with_mount
  elif ! container_has_builds_mount; then
    # Built websites moved out of the working folder, which needs a second
    # mount this container was made without. A mount cannot be added to a
    # container that already exists.
    echo "♻️  Rebuilding your workspace so built websites can be kept outside your course folder…"
    if docker ps --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}$"; then docker stop "$CONTAINER_NAME" >/dev/null; fi
    docker rm "$CONTAINER_NAME" >/dev/null || true
    run_container_with_mount
  elif [[ -n "$DESIRED_IMAGE_ID" && -n "$RUNNING_IMAGE_ID" && "$RUNNING_IMAGE_ID" != "$DESIRED_IMAGE_ID" ]]; then
    echo "♻️  Your workspace was built from an older version; rebuilding it so the update takes effect…"
    if docker ps --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}$"; then docker stop "$CONTAINER_NAME" >/dev/null; fi
    docker rm "$CONTAINER_NAME" >/dev/null || true
    run_container_with_mount
  elif ! docker inspect -f '{{json .HostConfig.PortBindings}}' "$CONTAINER_NAME" 2>/dev/null | grep -q '9084/tcp'; then
    # An older container publishes only 8081, and published ports cannot
    # be changed after creation — recreating is the only way to add them.
    echo "♻️  Rebuilding your workspace so several previews can run at once…"
    if docker ps --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}$"; then docker stop "$CONTAINER_NAME" >/dev/null; fi
    docker rm "$CONTAINER_NAME" >/dev/null || true
    run_container_with_mount
  else
    # Mounts match; only start if not already running
    if docker ps --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}$"; then
      echo "✅ Container $CONTAINER_NAME is already running with correct mount."
    else
      echo "🚀 Starting existing container $CONTAINER_NAME..."
    docker start "$CONTAINER_NAME" >/dev/null
    fi
  fi
else
  echo "🚀 Creating new container named $CONTAINER_NAME..."
  run_container_with_mount
fi

# Preflight: nudge if quartz.layout.ts in the container wasn't initialized by setup.sh
echo "🔎 Preflight: checking Quartz sidebar anchor..."
if ! docker exec -i "$CONTAINER_NAME" bash -lc 'test -f /opt/quartz/quartz.layout.ts && grep -q "const omit = new Set" /opt/quartz/quartz.layout.ts'; then
  echo "⚠️  Sidebar omit anchor not found in container's Quartz layout."
  echo "   Did you run: ./setup.sh and complete setup for '$COURSE'?"
  echo "   (Continuing anyway; the build will attempt a safe fallback.)"
fi

# Validate that SECTION is one of the allowed timetable sections for this course
echo "📋 Checking allowed timetable sections for $COURSE..."
ALLOWED_SECTIONS="$(docker exec -e COURSE="$COURSE" "$CONTAINER_NAME" python3 - <<'PY'
import os, json, sys
course = os.environ.get("COURSE")
p = f"/teaching/courses/{course}/course_config.json"
try:
    with open(p, "r", encoding="utf-8") as f:
        cfg = json.load(f)
    secs = cfg.get("section_numbers")
    if isinstance(secs, list) and secs:
        print(",".join(str(int(x)) for x in secs))
    else:
        n = int(cfg.get("num_sections", 1))
        print(",".join(str(i) for i in range(1, n+1)))
except Exception as e:
    print("")
PY
)"

if [[ -n "$ALLOWED_SECTIONS" ]]; then
  echo "   Allowed sections: $ALLOWED_SECTIONS"
  IFS=',' read -ra ARR <<< "$ALLOWED_SECTIONS"
  FOUND=0
  for s in "${ARR[@]}"; do
    if [[ "$s" == "$SECTION" ]]; then
      FOUND=1
      break
    fi
  done
  if [[ "$FOUND" -ne 1 ]]; then
    echo "❌ Section $SECTION is not one of YOUR timetable sections for $COURSE."
    echo "   Choose one of: $ALLOWED_SECTIONS"
    exit 1
  fi
else
  echo "ℹ️ Could not read allowed sections from course_config.json (continuing)."
fi

echo "🔧 Building site for $COURSE, section $SECTION..."
echo "📂 Output will be written to: $OUTPUT_PATH"

# With the new build_site.py:
# - default (no flag) = serve once (no double build)
# - --build-only = build static site only
MODE_FLAG="$BUILD_ONLY"

# The container port maps to a host port block chosen for this folder, so
# the address to open is resolved from the container rather than assumed.
HOST_PREVIEW_PORT=$(docker port "$CONTAINER_NAME" "${PREVIEW_PORT}/tcp" 2>/dev/null | head -1 | sed 's/.*://')
if [[ -z "$HOST_PREVIEW_PORT" ]]; then
  HOST_PREVIEW_PORT="$PREVIEW_PORT"
fi
if [[ -z "$BUILD_ONLY" ]]; then
  echo "🌐 Preview will be available at: http://localhost:${HOST_PREVIEW_PORT}/"
fi

# A terminal is what makes the container's prompts and live progress work, so
# ask for one when there IS one. But `docker exec -t` refuses to start at all
# when stdin is not a terminal — from a script, from CI, or from Plantoir's
# MCP server — and it fails here, minutes into the build, saying only "the
# input device is not a TTY". Without a terminal, run python unbuffered so
# progress still arrives line by line. (verify.sh refuses up front for the
# same reason; this makes refusing unnecessary.)
if [[ -t 0 ]]; then
  _EXEC_TTY="-it"; _PY_UNBUFFERED=""
else
  _EXEC_TTY="-i";  _PY_UNBUFFERED="-u"
fi

docker exec $_EXEC_TTY "$CONTAINER_NAME" python3 $_PY_UNBUFFERED /opt/scripts/build_site.py \
  --host-os "$_PREVIEW_HOST_OS" \
  --course="$COURSE" \
  --section="$SECTION" \
  $INCLUDE_SOCIAL \
  $FORCE_NPM_INSTALL \
  $FULL_REBUILD \
  --port "$PREVIEW_PORT" \
  $MODE_FLAG
