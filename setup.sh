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
  docker run -dit \
    --name "$CONTAINER_NAME" \
    -v "$HOST_COURSES":/teaching/courses \
    -p ${HOST_BASE}-$((HOST_BASE + 3)):8081-8084 \
    -p $((HOST_BASE + 1000))-$((HOST_BASE + 1003)):9081-9084 \
    "$IMAGE" \
    tail -f /dev/null
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
      docker start "$CONTAINER_NAME" >/dev/null
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
