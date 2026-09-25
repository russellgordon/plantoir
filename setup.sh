#!/bin/bash
set -euo pipefail

# -------------------- Defaults --------------------
# The container publishes a small range so several previews can run at
# once — one per window in the app, each on its own port.
PREVIEW_PORT_RANGE="8081-8084"
# Each preview also uses a live-reload websocket on port + 1000.
PREVIEW_WS_RANGE="9081-9084"
# -------------------- Config (from flags) --------------------
declare -a PASSTHRU_ARGS=()      # ensure array is declared even on older bash
OVERRIDE_IMAGE=""                # full image override (mostly for verify.sh)
DOCKER_CONTEXT_OVERRIDE=""       # optional docker context override

# -------------------- Help text --------------------
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
_SETUP_HOST_OS="$(_detect_host_os)"
if [[ "$_SETUP_HOST_OS" == "windows" ]]; then
  SELF_CMD=".\\setup.bat"
else
  SELF_CMD="./setup.sh"
fi
# ----------------------------------------------------------------------
print_help() {
  cat <<EOF
Usage: ${SELF_CMD} [options] [-- <args passed to setup_course.py>]

Options:
  --image REF          Use a specific already-built image instead of building
                       from this folder's recipe (used by verify.sh).
  --context NAME       Use a specific Docker context (sets DOCKER_CONTEXT=NAME for this run).
  --no-backup          (Pass-through to setup_course.py) Skip creating a backup ZIP — you will be asked to confirm.
  --help               Show this help and exit.

Notes:
- The website builder image is built LOCALLY from this folder's recipe
  (.toolchain/, or the Dockerfile in a repository copy). The image tag is a
  hash of the recipe, so an updated recipe rebuilds automatically. The first
  build needs an internet connection and takes a few minutes; after that it
  is cached.
- Any arguments after a literal “--” are forwarded directly to setup_course.py.

Examples:
  ${SELF_CMD}
  ${SELF_CMD} --image quartz-teacher:dev-test
  ${SELF_CMD} -- --no-backup
EOF
}

# -------------------- Arg parsing --------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) print_help; exit 0 ;;
    --image)
      if [[ $# -lt 2 ]]; then echo "❌ --image requires a value" >&2; exit 1; fi
      OVERRIDE_IMAGE="$2"; shift 2 ;;
    --context)
      if [[ $# -lt 2 ]]; then echo "❌ --context requires a value (e.g., desktop-linux, default, colima)" >&2; exit 1; fi
      DOCKER_CONTEXT_OVERRIDE="$2"; shift 2 ;;
    --) shift; PASSTHRU_ARGS+=("$@"); break ;;
    *) PASSTHRU_ARGS+=("$1"); shift ;;
  esac
done

# -------------------- Pre-flight: context --------------------
if [[ -n "$DOCKER_CONTEXT_OVERRIDE" ]]; then
  export DOCKER_CONTEXT="$DOCKER_CONTEXT_OVERRIDE"
fi

# -------------------- Pre-flight checks --------------------
cd "$(dirname "$0")"

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
#
# One line can be lost: the app rewrites the whole file when it adds a line of
# its own, so an append landing between its read and its write disappears.
# That is one line, once, and worth less than the locking it would take.
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
    # If clearing failed — an unwritable subfolder under it — `mv` would put
    # the site INSIDE the surviving folder instead of at it, the link would
    # succeed, and the section would read as never built while the trail said
    # it had moved. Better to leave the built website where it is.
    if [ -e "$target" ]; then
      echo "⚠️  Could not move it; leaving the built website where it is."
      return 0
    fi
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

# >>> CONTAINER MOUNT BLOCK >>> — identical in setup.sh, preview.sh and
# deploy.sh, and extracted between these two markers by
# scripts/test_container_mount.sh, which also checks that all three ask for
# their folders through it. Keep the markers, and keep the three copies the
# same.
# ---- Naming the folders the workspace is given -----------------------
# A teacher who types "Comm Tech 26/27" into Finder gets a folder macOS
# stores as "Comm Tech 26:27" — a name cannot hold a slash, and a colon is
# what is written instead. `-v A:B` splits its argument on colons, so that
# folder cannot be expressed with it AT ALL: the daemon reads
# "/teaching/courses" as the mode and refuses with exit 125 — after first-run
# setup has downloaded its tools, started the virtual machine and built the
# website builder. 147 seconds, and then one line of daemon text, on the real
# report this comes from (GitHub issue #221). `--mount` takes key=value
# fields parsed as ONE CSV record instead, so a field may be QUOTED and a
# literal quote inside it doubled.
#
# MEASURED 2026-09-19 against Colima/virtiofs, on both the pinned Docker CLI
# 29.7.2 and Homebrew's 29.7.1, under /bin/bash 3.2.57 and under zsh:
#
#   with -v               only ':' fails
#   with a PLAIN --mount  ',' and '"' fail instead — strictly worse, since
#                         "Comm Tech 26,27" is just as ordinary a name
#   with the form below   colon, comma, double quote, backslash, dollar,
#                         leading dash, trailing space, semicolon, equals,
#                         emoji, NFC and NFD accents, a tab, a bare CR and a
#                         bare LF all mount
#
# So: every name a teacher can type in Finder. ONE name still fails, and it
# is written down rather than rounded off — a name holding a CR IMMEDIATELY
# FOLLOWED BY an LF. Go's encoding/csv rewrites CR LF to LF inside a quoted
# field, so the daemon then looks for a path that does not exist and refuses
# (exit 125, and the sentence below). `-v` mounted that name, so this is a
# real regression rather than a gap: it is accepted because Finder's rename
# field will not accept a Return — it takes a script or a restored archive to
# make such a name — and because the failure is loud rather than silent.
#
# The quote must open the FIELD — `"source=/x"` — and never the value:
# `source="/x"` is refused for EVERY path, ordinary ones included, which is
# the one trap in this shape.
bind_mount_argument() {
  # bind_mount_argument <host source> <container target>
  local source_path="$1"
  local target_path="$2"
  local quoted_source="${source_path//\"/\"\"}"
  local quoted_target="${target_path//\"/\"\"}"
  printf '%s' "type=bind,\"source=${quoted_source}\",\"target=${quoted_target}\""
}

# What a teacher is told when the workspace could not be made. TWO sentences,
# because there are two different situations here and only one of them is
# about something that happened to the folder recently.
#
# These exist because a refusal otherwise says nothing a teacher can use.
# setup.sh and deploy.sh run under `set -e`, so the script ends there with the
# daemon's own sentence as the last thing on screen — exactly what the teacher
# in issue #221 was left with. preview.sh has NO `set -e` (measured
# 2026-09-19 while proving this, and the opposite of what the plan for it
# assumed), so it did something worse: it carried straight on past the
# refusal, said "No such container" twice, announced that it was building,
# and produced nothing. Both roads want a sentence and a stop.

# (1) The folder is not on this Mac where it was. Nothing to reach, so
# nothing to explain about reaching it.
say_this_folder_is_not_there() {
  echo "❌ Plantoir could not get this folder ready for building."
  echo "   Check that it has not been moved or renamed, then try again."
}

# (2) The folder IS on this Mac and the builder still could not be given it.
# The commonest way to arrange that is to keep the working folder somewhere
# the builder cannot see: it can only reach the home folder, so an external
# drive, a second volume or /Users/Shared cannot be handed over at all.
#
# MEASURED 2026-09-19 (virtiofs, fresh paths the virtual machine had never
# been given, three of three, plus /Users/Shared): this form refuses such a
# path with "bind source path does not exist". `-v` did NOT — it created the
# folder inside the virtual machine and started, so the build ran against an
# EMPTY folder, said it had succeeded and produced nothing. Loud beats
# silent, and the sentence can now name the rule because something finally
# enforces it. (A path the VM has already been handed by an earlier `-v` run
# succeeds and still mounts empty, which is what made an earlier measurement
# of this read the wrong way round: test it with a path nothing has used.)
#
# The same words the app says for the same trouble — contracts/app-rules.json
# -> failureExplanations, the case matched on "bind source path does not
# exist" — so one sentence covers a teacher in Plantoir and a teacher at the
# command line, and there is one string to keep in step.
# scripts/test_container_mount.sh checks these lines against that case.
say_this_folder_cannot_be_reached() {
  echo "❌ Plantoir could not get this folder ready for building."
  echo "   Check that it is inside your home folder — on your Desktop or in"
  echo "   Documents, for example — and not on an external drive or in a"
  echo "   shared location, then try again."
}
# <<< CONTAINER MOUNT BLOCK <<<

# ---- The image is built HERE, from this folder's own recipe ----------
# The tag is a hash of the recipe's contents: a changed recipe means a new
# tag, a fresh local build, and a recreated container. No registry, no
# account — the recipe travels with the app (or the repository).
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
  echo "📦 Downloading ${label}…"
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
    _download "https://github.com/lima-vm/lima/releases/download/v${LIMA_VERSION}/lima-${LIMA_VERSION}-Darwin-${lima_arch}.tar.gz" "$lima_tgz" "what your website builder needs (1 of 4)"
    tar xzf "$lima_tgz" -C "$TOOLS_DIR"
    rm -f "$lima_tgz"
  fi

  if ! command -v colima >/dev/null 2>&1; then
    _download "https://github.com/abiosoft/colima/releases/download/${COLIMA_VERSION}/colima-Darwin-${arch}" "$TOOLS_DIR/bin/colima" "what your website builder needs (2 of 4)"
    chmod +x "$TOOLS_DIR/bin/colima"
  fi

  if ! command -v docker >/dev/null 2>&1; then
    local docker_tgz="$TOOLS_DIR/docker.tar.gz"
    _download "https://download.docker.com/mac/static/stable/${docker_arch}/docker-${DOCKER_CLI_VERSION}.tgz" "$docker_tgz" "what your website builder needs (3 of 4)"
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
  _download "https://github.com/docker/buildx/releases/download/${BUILDX_VERSION}/buildx-${BUILDX_VERSION}.darwin-${buildx_arch}" "$HOME/.docker/cli-plugins/docker-buildx" "what your website builder needs (4 of 4)"
  chmod +x "$HOME/.docker/cli-plugins/docker-buildx"
}

ensure_container_runtime() {
  # Fast path: any working Docker daemon means there is nothing to do —
  # beyond making sure BuildKit is present to build with.
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    ensure_buildx
    return 0
  fi

  # Set when this run starts the builder's virtual machine; preview.sh's
  # reach check reads it (GitHub #234). The same line is in all three
  # launchers so that their copies of this function stay identical.
  THIS_RUN_STARTED_THE_BUILDER=1

  # "Setting up this Mac" is a progress marker the app matches word for word
  # (contracts/app-rules.json → milestones); keep those four words. It is not
  # "a one-time step": quitting Plantoir stops this machinery when nothing else
  # is using it, so it happens again after such a quit (GitHub #228).
  echo "🐳 Setting up this Mac…"
  ensure_local_tools

  if [[ ! -d "$HOME/.colima/default" ]]; then
    # What is being set up here is Colima's Linux virtual machine; the
    # teacher is told only what it is FOR (GitHub #263, rule 1).
    echo "🚀 First start: setting up your website builder ($(_colima_cpus) CPUs · $(_colima_memory_gb) GB of memory)."
    echo "   About 600 MB is downloaded once; this can take several minutes."
    # vz is macOS's own virtualization — no extra software needed, unlike
    # the qemu default.
    colima start --cpu "$(_colima_cpus)" --memory "$(_colima_memory_gb)" --vm-type vz
  else
    # The app's friendlyPhase matches "Starting the website builder" (#228).
    echo "▶️  Starting the website builder…"
    # shellcheck disable=SC2046  # deliberate word splitting: these are flags
    colima start $(_colima_growth_flags)
  fi

  # The app's friendlyPhase matches "Waiting for the website builder" (#263).
  echo "⏳ Waiting for the website builder to be ready…"
  _wait_for_docker 30 && return 0

  # Colima can report the VM as running while its Docker daemon is dead
  # (common after sleep or an unclean shutdown); a plain start no-ops in
  # that state. Force a clean restart and wait again.
  #
  # For a developer: Colima is shared by any other Colima-based toolchains on
  # this Mac, so this restart takes their containers down too; they come back
  # afterwards only if configured to. This used to be printed; since #263 the
  # console speaks to a teacher, who has nothing else using it
  # (documentation/03-launcher-scripts.md).
  echo "🔁 The website builder isn't answering yet — restarting it…"
  colima stop --force >/dev/null 2>&1 || true
  colima start >/dev/null 2>&1 || true
  _wait_for_docker 60 && return 0

  # For a developer, the by-hand recovery is
  #   colima stop --force && colima start
  # then re-run this launcher. A teacher is told to restart, which is what
  # cleared the wedged builder in #225.
  echo "❌ The website builder did not start."
  echo "   Restart this Mac, then try again."
  exit 1
}

# Set by ensure_container_runtime when this run starts the builder (#234).
THIS_RUN_STARTED_THE_BUILDER=""
ensure_container_runtime
# ====================================================================

CURRENT_CONTEXT=$(docker context show 2>/dev/null || echo "unknown")
HOST_ARCH=$(docker info --format '{{.Architecture}}' 2>/dev/null || echo "unknown")
HOST_OS=$(docker info --format '{{.OSType}}' 2>/dev/null || echo "unknown")
echo "🔌 Docker context: ${CURRENT_CONTEXT}"
echo "🧭 Host detected by Docker: ${HOST_OS}/${HOST_ARCH}"
echo "🖼️  Using image: ${IMAGE}"

# -------------------- Folders & permissions --------------------
CREATED_COURSES_DIR="false"
if [[ ! -d "courses" ]]; then
  echo "📁 Creating 'courses' directory on host..."
  mkdir -p courses
  CREATED_COURSES_DIR="true"
fi
if [[ ! -d "courses/_backups" ]]; then
  echo "📦 Creating 'courses/_backups' directory on host..."
  mkdir -p courses/_backups
fi
# Relax perms so container user can write even if UID/GID differ; strip odd ACLs on macOS (no-op elsewhere)
chmod -R u+rwX,go+rwX courses || true
chmod -R -N courses 2>/dev/null || true

# Compute the desired host mount path for this run
HOST_COURSES="$(pwd)/courses"

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

# >>> PREVIEW PORT BLOCK >>> — identical in setup.sh, preview.sh and
# deploy.sh, and extracted between these two markers by
# scripts/test_port_blocks.py, which checks that the three copies are the
# same and runs them against a pretend Mac. Keep the markers, and keep the
# three copies the same: the three launchers must create a folder's
# workspace IDENTICALLY — the same two folders, the same eight addresses —
# or two of them would recreate it away from each other on alternate runs.
# The rule is data in contracts/app-rules.json -> previewPorts, which
# preview.ps1 follows too; the reasoning is in
# documentation/03-launcher-scripts.md, "How a folder finds its ports, and
# when it cannot" (GitHub issue #280).
#
# ---- Where this folder's previews are served on this Mac ---------------
# Every working folder's workspace publishes a BLOCK of eight host ports: four
# for previews (base … base+3 -> 8081-8084 inside) and their four live-reload
# websockets (base+1000 … base+1003 -> 9081-9084). A workspace keeps its
# block for as long as it EXISTS — running or stopped, preview or no preview,
# across restarts — and nothing removes another folder's workspace, so the
# number of blocks spoken for is the number of working folders this Mac has
# ever used (moved and deleted ones included), not the number of previews.
#
# The walk starts at 8081 and steps by 10 through FORTY blocks (8081 … 8471).
# Until 2026-09-25 it tried six and stopped, and a Mac with six working
# folders' workspaces alive could make no seventh, preview or publish (#280).
# Forty is a CHOSEN number, not a measured one: any number up to 99 would
# keep the site ports clear of block one's websockets (block 100 starts at
# 9081), forty keeps the walk under 8888, and a ceiling at all keeps the
# refusal below reachable, so it can be tested and its sentence stays true.
#
# A block is taken if ANY of its eight ports is
#   - listening on this Mac, by anybody — one `lsof` listing, parsed once
#     (0.12 s measured, against 0.123 s PER PORT for the old one-call-per-port
#     probe: 9.8 s for forty blocks). Docker cannot see a program on the Mac
#     holding a port and publishes over it anyway (measured: exit 0), so this
#     is the only guard against another app. A listing that cannot be read
#     counts as nothing listening, which is what the old probe did too.
#   - published by ANOTHER working folder's workspace, stopped ones included
#     — one `docker inspect` over every teaching-quartz-* workspace. A stopped
#     workspace listens on nothing, so without this a new folder would take
#     its block and the stopped one could not start again (quitting Plantoir
#     stops workspaces since #220, so that is an everyday path).
#
# TWO PASSES. The first counts all of that. Only when it finds nothing does a
# second walk count what is actually IN USE — listening on this Mac, or
# published by a RUNNING workspace — and take a block a STOPPED workspace was
# keeping. That workspace is remade on free ports the next time its own
# folder starts it (start_the_existing_workspace), at the cost of one slow
# preview. Without the second pass a block would be kept for ever by a
# folder that was moved, renamed or deleted — its workspace's name is a hash
# of its path, so it can never be started again — and neither remedy the
# refusal names (close the other folders' windows, restart the Mac) would
# free anything, since both only STOP workspaces. With it, both do.
FIRST_HOST_BLOCK=8081
HOST_BLOCK_STEP=10
HOST_BLOCK_COUNT=40

# Every TCP port something on this Mac is listening on, one per line. lsof
# writes `n*:8081`, `n127.0.0.1:8443` and `n[::1]:8443`; the port is what
# follows the LAST colon, whichever of the three it is. Prints nothing, and
# still succeeds, when lsof is missing or fails.
listening_ports_on_this_mac() {
  { lsof -nP -iTCP -sTCP:LISTEN -Fn 2>/dev/null || true; } \
    | sed -n 's/^n.*:\([0-9][0-9]*\)$/\1/p'
}

# Every host port published by another working folder's workspace, one per
# line: running or stopped, or with "running" as $1 only running ones. This
# folder's own workspace is left out: it is only ever made after the old one
# has been removed.
ports_held_by_other_workspaces() {
  local names which="-a"
  if [ "${1:-}" = "running" ]; then
    which=""
  fi
  # shellcheck disable=SC2086
  names="$(docker ps $which --filter 'name=^teaching-quartz-' --format '{{.Names}}' 2>/dev/null \
    | grep -Fxv -- "$CONTAINER_NAME" || true)"
  if [ -z "$names" ]; then
    return 0
  fi
  # Names are teaching-quartz-<8 hex digits>, so splitting on spaces is safe.
  # shellcheck disable=SC2086
  { docker inspect -f '{{range $p, $b := .HostConfig.PortBindings}}{{range $b}}{{.HostPort}} {{end}}{{end}}' $names 2>/dev/null || true; } \
    | tr ' ' '\n' | grep -E '^[0-9]+$' || true
}

# Prints the first free block's base, walking upward from $1 (default: the
# first block) to the fortieth; fails when none is free. $2 is the pass:
# "kept" (the first — stopped workspaces' blocks count as taken) or "in-use"
# (the second — only what is listening or running counts).
find_free_port_block() {
  local base="${1:-$FIRST_HOST_BLOCK}"
  local pass="${2:-kept}"
  local last=$((FIRST_HOST_BLOCK + (HOST_BLOCK_COUNT - 1) * HOST_BLOCK_STEP))
  local busy offset all_free held
  if [ "$pass" = "in-use" ]; then
    held="$(ports_held_by_other_workspaces running | tr '\n' ' ')"
  else
    held="$(ports_held_by_other_workspaces | tr '\n' ' ')"
  fi
  busy=" $(listening_ports_on_this_mac | tr '\n' ' ') $held "
  while [ "$base" -le "$last" ]; do
    all_free=true
    for offset in 0 1 2 3; do
      case "$busy" in
        *" $((base + offset)) "*|*" $((base + 1000 + offset)) "*) all_free=false; break ;;
      esac
    done
    if [ "$all_free" = true ]; then
      echo "$base"
      return 0
    fi
    base=$((base + HOST_BLOCK_STEP))
  done
  return 1
}

# Whether Docker refused because a port was taken. The probe and the
# creation are two steps, so two launchers starting at the same moment (two
# folders opened together, two gates) can both see a block free. Three
# wordings, all three measured or quoted: Colima's "Bind for 0.0.0.0:N
# failed: port is already allocated" (a workspace already has it), and
# Docker Desktop's "Ports are not available: … bind: address already in use".
it_was_a_port_clash() {
  case "$1" in
    *"port is already allocated"*|*"Ports are not available"*|*"address already in use"*) return 0 ;;
  esac
  return 1
}

# The sentence when all forty blocks are taken. Pinned word for word in
# contracts/app-rules.json -> previewPorts.whenNoBlockIsFree. The old one
# told a teacher to "stop another preview", which frees nothing: a block is
# held by a workspace that EXISTS. Both remedies it names are true because
# of the walk's second pass: closing a folder's last window stops its
# workspace, a restart stops every workspace, and a STOPPED workspace's block
# is taken when nothing else is free.
# The trail line is the existing `preview did not appear` event's second
# launcher line (contracts/shared-rules.json -> activityTrail.mustRecord);
# WORKSPACE_TRAIL_PLACE is "<course>/<section>" where the launcher has one.
say_there_is_no_room_for_previews() {
  echo "❌ Every address Plantoir can use for a preview is taken."
  echo "   Close Plantoir's windows for your other working folders, or restart this Mac, then try again."
  note_on_the_trail "${WORKSPACE_TRAIL_PLACE:-setup} · stopped before starting — every address Plantoir can use for a preview was taken"
}

# Makes this folder's workspace on the first free block, walking on past a
# block that Docker says was taken in the meantime. The half-made workspace
# of a refused attempt is removed with a plain `docker rm` — never -f: it was
# never started, and -f is what would kill a workspace another launcher made
# under this name a moment ago, mid-publish (#94's shape).
create_the_workspace_on_free_ports() {
  local base="$FIRST_HOST_BLOCK"
  local next output
  while true; do
    next="$base"
    if ! base="$(find_free_port_block "$base" kept)" \
      && ! base="$(find_free_port_block "$next" in-use)"; then
      say_there_is_no_room_for_previews
      exit 1
    fi
    if output="$(docker run -dit \
        --name "$CONTAINER_NAME" \
        --mount "$(bind_mount_argument "$HOST_COURSES" /teaching/courses)" \
        --mount "$(bind_mount_argument "$BUILD_ROOT" "$BUILD_ROOT")" \
        -p "${base}-$((base + 3)):8081-8084" \
        -p "$((base + 1000))-$((base + 1003)):9081-9084" \
        "$IMAGE" \
        tail -f /dev/null 2>&1)"; then
      return 0
    fi
    if ! it_was_a_port_clash "$output"; then
      printf '%s\n' "$output"
      say_this_folder_cannot_be_reached
      exit 1
    fi
    echo "↪️  Those preview addresses were taken a moment ago; trying the next ones…"
    docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
    base=$((base + HOST_BLOCK_STEP))
  done
}

# Starts this folder's stopped workspace. When Docker refuses because another
# folder's workspace has taken its block — mainly because the walk's SECOND
# pass took it on purpose when nothing else was free, or for a workspace
# made before #280 — the workspace is made again on free ports. That throws away the warm copy of
# the website builder kept inside it (a first preview again: 109 s measured
# on a teacher's Mac for #225), so it happens ONLY for a port refusal, and
# the console says what it costs. Any other refusal stops here with Docker's
# own words: setup.sh and deploy.sh used to end on the bare `docker start`
# under `set -e` with only those words, and preview.sh carried on past it and
# failed later at a step that could not say why.
start_the_existing_workspace() {
  local output
  if output="$(docker start "$CONTAINER_NAME" 2>&1)"; then
    return 0
  fi
  if ! it_was_a_port_clash "$output"; then
    printf '%s\n' "$output"
    echo "❌ Plantoir could not start this folder's workspace. Try again, or restart this Mac if it happens again."
    exit 1
  fi
  echo "♻️  Something else is now using this folder's preview addresses, so Plantoir is setting this folder up again on free ones."
  echo "   The next preview will be slower than usual — about two minutes — while it gets ready."
  if docker rm "$CONTAINER_NAME" >/dev/null 2>&1; then
    run_container_with_mount
    return 0
  fi
  # Refused: another launcher got here first and it is running again. Use it.
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -Fxq -- "$CONTAINER_NAME"; then
    return 0
  fi
  printf '%s\n' "$output"
  echo "❌ Plantoir could not start this folder's workspace. Try again, or restart this Mac if it happens again."
  exit 1
}
# <<< PREVIEW PORT BLOCK <<<

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
  echo "🔗 Binding host courses to container: $HOST_COURSES ➜ /teaching/courses"
  # The builds folder is mounted at its OWN absolute path, unconditionally,
  # so that courses/<CODE>/.merged_output — a symlink to a path under
  # $HOME — resolves to the same place inside the container as it does
  # outside. Mounting it anywhere else would leave the link dangling in
  # here, and every build would fail on a path the teacher can plainly see
  # working in Finder. It is created before this runs: a bind mount whose
  # source does not exist is REFUSED ("bind source path does not exist"),
  # and the run stops with say_this_folder_cannot_be_reached rather than
  # building into a folder nobody can find.
  ensure_build_root
  # The source of a bind mount has to EXIST. `-v` quietly CREATED a folder at
  # whatever path it was handed; the form the PREVIEW PORT BLOCK uses refuses,
  # and refusing is the
  # better answer — a working folder renamed or deleted while this was
  # running would otherwise be silently re-made, empty, at a path nobody is
  # looking at any more. Nothing ordinary reaches this with no courses
  # folder: setup.sh makes it itself, and preview.sh and deploy.sh have both
  # already refused, for better reasons, when the course is not there.
  if [ ! -d "$HOST_COURSES" ]; then
    say_this_folder_is_not_there
    exit 1
  fi
  create_the_workspace_on_free_ports
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

# -------------------- Writability probe helper --------------------
probe_container_write() {
  # Returns 0 if we can create & delete a file inside /teaching/courses
  docker exec "$CONTAINER_NAME" sh -lc \
    'mkdir -p /teaching/courses &&
     echo ok >/teaching/courses/.write_probe &&
     rm -f /teaching/courses/.write_probe'
}

# A container keeps running the version it was created from, so an update
# only takes effect once the container itself is recreated.
DESIRED_IMAGE_ID=$(docker image inspect --format '{{.Id}}' "$IMAGE" 2>/dev/null || echo "")
RUNNING_IMAGE_ID=$(docker inspect -f '{{.Image}}' "$CONTAINER_NAME" 2>/dev/null || echo "")

# -------------------- Create/start container (mount-aware, with refresh-on-new-courses) --------------------
if docker ps -a --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}$"; then
  # Container exists. Check its current /teaching/courses mount.
  CURRENT_MOUNT_SRC=$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/teaching/courses"}}{{.Source}}{{end}}{{end}}' "$CONTAINER_NAME" 2>/dev/null || echo "")
  if [[ -z "$CURRENT_MOUNT_SRC" ]]; then
    echo "🧯 Existing container has no /teaching/courses mount; recreating with correct mount…"
    if docker ps --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}$"; then docker stop "$CONTAINER_NAME" >/dev/null; fi
    docker rm "$CONTAINER_NAME" >/dev/null || true
    run_container_with_mount
  elif [[ "$CURRENT_MOUNT_SRC" != "$HOST_COURSES" ]]; then
    echo "🔀 Detected different working directory:"
    echo "   • Existing mount: $CURRENT_MOUNT_SRC"
    echo "   • Desired mount:  $HOST_COURSES"
    echo "♻️  Recreating container '$CONTAINER_NAME' to point at the new folder…"
    if docker ps --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}$"; then docker stop "$CONTAINER_NAME" >/dev/null; fi
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
    # An older container publishes only 8081; published ports cannot be
    # changed after creation, so recreating is how the range arrives.
    echo "♻️  Rebuilding your workspace so several previews can run at once…"
    if docker ps --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}$"; then docker stop "$CONTAINER_NAME" >/dev/null; fi
    docker rm "$CONTAINER_NAME" >/dev/null || true
    run_container_with_mount
  else
    # Mounts match; only start if not already running
    if docker ps --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}$"; then
      # If courses/ was freshly created, refresh to ensure a clean, writable mount
      if [[ "$CREATED_COURSES_DIR" == "true" ]]; then
        echo "🔁 'courses/' was created just now; refreshing container to ensure a clean, writable mount…"
        docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
        run_container_with_mount
      else
        # Probe writability; if not writable, recreate
        if ! probe_container_write; then
          echo "🛑 Mounted 'courses/' is not writable from the container — recreating it…"
          docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
          run_container_with_mount
        else
          echo "✅ Container $CONTAINER_NAME is already running with correct, writable mount."
        fi
      fi
    else
      echo "▶️  Starting existing container $CONTAINER_NAME..."
      start_the_existing_workspace
      # After start, probe writability just in case
      if ! probe_container_write; then
        echo "🛑 Mounted 'courses/' is not writable from the container after start — recreating it…"
        docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
        run_container_with_mount
      fi
    fi
  fi
else
  echo "🆕 Creating a new container named $CONTAINER_NAME (image: $IMAGE)…"
  run_container_with_mount
fi

# -------------------- Backup confirmation (pass-through option) --------------------
HOST_TZ_OFFSET=$(date +%z)
echo "🕒 Detected host timezone offset: $HOST_TZ_OFFSET"
echo "🛟 Backups will be written to: $(pwd)/courses/_backups"

# Only test for --no-backup if there are any passthrough args
if ((${#PASSTHRU_ARGS[@]})) && printf '%s\n' "${PASSTHRU_ARGS[@]}" | grep -q -- "--no-backup"; then
  echo "⚠️ You are running with --no-backup."
  echo "   This will skip creating a safety ZIP before modifying course folders."
  read -p "❓ Are you sure you want to proceed without a backup? (yes/no) " CONFIRM
  case "$CONFIRM" in
    yes|y|Y) echo "Proceeding without backup...";;
    *) echo "❌ Cancelled."; exit 1;;
  esac
fi

# -------------------- Run setup inside container --------------------
echo "📚 Running setup_course.py inside the Docker container..."
# Ensure the container knows the host OS (mac). Users never need to pass this.
# If someone did pass --host-os already, strip it and override to mac.
if ((${#PASSTHRU_ARGS[@]})); then
  _cleaned=()
  _skip_next=0
  for _a in "${PASSTHRU_ARGS[@]}"; do
    if (( _skip_next )); then _skip_next=0; continue; fi
    if [[ "$_a" == "--host-os" ]]; then _skip_next=1; continue; fi
    if [[ "$_a" == --host-os=* ]]; then continue; fi
    _cleaned+=("$_a")
  done
  PASSTHRU_ARGS=("${_cleaned[@]}")
fi
PASSTHRU_ARGS+=("--host-os" "mac")

docker exec -e HOST_TZ_OFFSET="$HOST_TZ_OFFSET" -it "$CONTAINER_NAME" \
  python3 /opt/scripts/setup_course.py ${PASSTHRU_ARGS+"${PASSTHRU_ARGS[@]}"}

# The wizard may have made a course, or several. Point each one's built
# website at the builds folder outside the working folder, so a teacher who
# only ever runs setup.sh is in the same state as one who opens the app —
# and so this launcher's container mount matches what it is for. Done AFTER
# the wizard, because a course that did not exist a minute ago cannot be
# linked before it does.
for _course_dir in courses/*/; do
  [ -d "$_course_dir" ] || continue
  link_course_build_output "$(basename "$_course_dir")"
done
