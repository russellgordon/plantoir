#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# verify.sh — end-to-end verification of local toolchain changes (maintainer use)
#
# Builds a fresh local image (quartz-teacher:dev-test) from this repository,
# checks that everything baked into it matches the working tree, then drives
# the real launcher scripts against it so you can confirm that host-side and
# image-side changes work together — the same recipe every working
# folder builds from locally.
#
# What it does, in order:
#   0. Runs deploy.py's pure-Python unit tests (no Docker needed) so a broken
#      script fails in milliseconds rather than after a full image build.
#   1. Ensures the container runtime is up (shares an already-running Colima;
#      never stops it — safe to run alongside other Colima-based toolchains).
#   2. docker build -t quartz-teacher:dev-test .
#   3. Verifies 'export-scripts' emits launchers identical to the repo copies
#      (and that Windows launchers were converted to CRLF).
#   4. Verifies the Python scripts and Quartz patches baked into the image
#      match the working tree.
#   5. Removes this folder's existing container, then runs
#      ./preview.sh EXC2O 1 --image quartz-teacher:dev-test --full-rebuild --build-only
#      so the container is recreated FROM THE DEV-TEST IMAGE and a full static
#      build of the Example Course runs through the real launcher.
#   6. Confirms the built site exists, that it carries and links Plantoir's
#      own icon rather than Quartz's, and that the running container uses the
#      dev-test image, then prints a PASS/FAIL summary.
#
# Usage:
#   ./verify.sh [--no-cache] [--skip-build]
#
#   --no-cache     Build the image without Docker's layer cache.
#   --skip-build   Reuse an existing quartz-teacher:dev-test image (faster when
#                  only host-side scripts changed).
#
# Requires: courses/EXC2O (the Example Course) in this folder as the build
# fixture. courses/ is gitignored, so on a fresh clone install it first via
# ./setup.sh (answer 'y' to the Example Course prompt).
# ==============================================================================

cd "$(dirname "$0")"

DEV_TEST_IMAGE="quartz-teacher:dev-test"
# The launchers name their container after the working folder.
CONTAINER_NAME="teaching-quartz-$(pwd -P | shasum -a 256 | cut -c1-8)"
NO_CACHE=""
SKIP_BUILD="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-cache)   NO_CACHE="--no-cache"; shift ;;
    --skip-build) SKIP_BUILD="true"; shift ;;
    --help|-h)
      # Print the banner by finding its end rather than by a fixed line
      # number: the range used to be hard-coded, so every line added to the
      # comment above quietly truncated the help text from the bottom — the
      # part that says how to install the fixture this script requires.
      sed -n '4,/^# =\{10,\}$/p' "$0" | sed 's/^# \{0,1\}//' | sed '$d'
      exit 0 ;;
    *) echo "❌ Unknown option: $1 (see --help)"; exit 1 ;;
  esac
done

# -------------------- Result bookkeeping --------------------
RESULTS=()
FAILED="false"
pass() { RESULTS+=("✅ PASS  $1"); echo "✅ PASS  $1"; }
fail() { RESULTS+=("❌ FAIL  $1"); echo "❌ FAIL  $1"; FAILED="true"; }

# -------------------- 0. A real terminal is required --------------------
# The launchers run the toolchain with `docker exec -it`, which refuses to
# start without a terminal on stdin. Say so now rather than failing several
# minutes in with a Docker error about attaching stdin.
if [[ ! -t 0 ]]; then
  echo "❌ verify.sh must be run from a terminal."
  echo "   The launchers use 'docker exec -it', which needs a TTY on stdin."
  echo "   To run it from a script or CI, give it one:"
  echo "     script -q /dev/null ./verify.sh"
  exit 1
fi

# -------------------- 0.5. Pure-Python unit tests (no Docker needed) --------------------
# Fast, dependency-free checks that don't need the image — run first so a
# broken script.py change fails in milliseconds instead of after a full
# Docker build.
if (cd scripts && python3 test_deploy_netlify_headers.py) >/tmp/verify_deploy_headers_test.log 2>&1; then
  pass "deploy.py: Netlify ad-badge suppression (scripts/test_deploy_netlify_headers.py)"
else
  fail "deploy.py: Netlify ad-badge suppression (scripts/test_deploy_netlify_headers.py)"
  cat /tmp/verify_deploy_headers_test.log
fi

if (cd scripts && python3 test_netlify_badge.py) >/tmp/verify_netlify_badge_test.log 2>&1; then
  pass "netlify_badge.py: shared ad-badge suppression module (scripts/test_netlify_badge.py)"
else
  fail "netlify_badge.py: shared ad-badge suppression module (scripts/test_netlify_badge.py)"
  cat /tmp/verify_netlify_badge_test.log
fi

if (cd scripts && python3 test_deploy_course_dir_resolution.py) >/tmp/verify_deploy_course_dir_test.log 2>&1; then
  pass "deploy.py: course directory resolution under a native build root (scripts/test_deploy_course_dir_resolution.py)"
else
  fail "deploy.py: course directory resolution under a native build root (scripts/test_deploy_course_dir_resolution.py)"
  cat /tmp/verify_deploy_course_dir_test.log
fi

# -------------------- 1. Container runtime (shared Colima) --------------------
# Maintainer variant: assumes Colima and the Docker CLI are installed (the
# teacher-facing launchers handle installation). Never stops a running VM.
if ! docker info >/dev/null 2>&1; then
  if ! command -v colima >/dev/null 2>&1; then
    echo "❌ No running Docker engine and Colima is not installed."
    echo "   Install with: brew install colima docker"
    exit 1
  fi
  echo "▶️  Starting Colima…"
  colima start
  for _ in $(seq 1 30); do
    docker info >/dev/null 2>&1 && break
    sleep 2
  done
fi
if docker info >/dev/null 2>&1; then
  pass "Container runtime is up (context: $(docker context show 2>/dev/null || echo '?'))"
else
  fail "Container runtime did not become ready"
  echo "   Try: colima status && colima stop --force && colima start"
  exit 1
fi

# -------------------- Preconditions --------------------
if [[ ! -d "courses/EXC2O" || ! -f "courses/EXC2O/course_config.json" ]]; then
  fail "Test fixture courses/EXC2O is missing"
  echo "   The Example Course is required. Install it via ./setup.sh (answer 'y'"
  echo "   to the Example Course prompt) or copy support/example_course/EXC2O to courses/."
  exit 1
fi

# -------------------- 2. Build the dev-test image --------------------
if [[ "$SKIP_BUILD" == "true" ]] && docker image inspect "$DEV_TEST_IMAGE" >/dev/null 2>&1; then
  pass "Reusing existing image $DEV_TEST_IMAGE (--skip-build)"
else
  echo ""
  echo "🧱 Building $DEV_TEST_IMAGE from ./Dockerfile ${NO_CACHE:+(no cache)}…"
  # The Dockerfile uses a BuildKit heredoc (RUN cat <<'EOF'), which the legacy
  # builder silently mishandles (it produced an EMPTY export-scripts file).
  # The launchers build with buildx, so verify must too, to stay representative.
  if docker buildx version >/dev/null 2>&1; then
    BUILD_CMD=(docker buildx build --load)
  else
    BUILD_CMD=(env DOCKER_BUILDKIT=1 docker build)
  fi
  if "${BUILD_CMD[@]}" $NO_CACHE -t "$DEV_TEST_IMAGE" .; then
    pass "Image built: $DEV_TEST_IMAGE (BuildKit)"
  else
    fail "docker build failed"
    exit 1
  fi
fi

# ---- build_site.py: custom-domain resolution follows the primary destination ----
# Needs the real image, not a host run — build_site.py imports `frontmatter`,
# which lives only inside the container (see Dockerfile's `pip install`), so
# this cannot join the fast host-side pre-checks above. The test file itself
# is mounted in rather than baked into the image — it is dev-only, and the
# image should not carry test fixtures a teacher's build never needs.
echo ""
echo "🔎 Checking build_site.py's custom-domain resolution against the real image…"
if docker run --rm \
  -v "$(pwd)/scripts/test_build_site_domain_resolution.py:/opt/scripts/test_build_site_domain_resolution.py:ro" \
  "$DEV_TEST_IMAGE" python3 /opt/scripts/test_build_site_domain_resolution.py >/dev/null 2>&1; then
  pass "build_site.py: custom-domain resolution follows the primary destination (scripts/test_build_site_domain_resolution.py)"
else
  fail "build_site.py: custom-domain resolution follows the primary destination (scripts/test_build_site_domain_resolution.py)"
fi

# -------------------- 3. export-scripts fidelity --------------------
# NOTE: must live under $HOME — Colima's VM only shares the home directory,
# so a /var/folders/... temp dir would silently arrive empty in the container.

# ---- Every helper a launcher calls must be defined in that same file ----
# The launchers are three standalone scripts sharing copied helper blocks,
# so a helper added to two of them but not the third fails only at runtime
# — and only on the code path that calls it. (setup.sh once called
# run_container_with_mount while only preview.sh and deploy.sh defined it:
# exit 127 at the first fresh course creation, missed by every other check.)
echo ""
echo "🔎 Cross-checking helper functions in the launchers…"
ALL_HELPERS="$(grep -hoE '^[a-z_][a-z0-9_]*\(\)' setup.sh preview.sh deploy.sh | tr -d '()' | sort -u)"
HELPERS_OK="true"
for f in setup.sh preview.sh deploy.sh; do
  # Comments stripped, and only command-position uses count — a helper's
  # name inside an echoed sentence is prose, not a call.
  UNCOMMENTED="$(sed -e 's/^[[:space:]]*#.*$//' "$f")"
  for fn in $ALL_HELPERS; do
    if echo "$UNCOMMENTED" | grep -qE "(^[[:space:]]*(if |elif |while |until )?!?[[:space:]]*|\\$\(|&&[[:space:]]*|\|\|[[:space:]]*)${fn}([[:space:]]|;|\)|$)"; then
      if ! grep -qE "^[[:space:]]*${fn}\(\)" "$f"; then
        HELPERS_OK="false"
        fail "$f calls ${fn} but never defines it (would exit 127 at runtime)"
      fi
    fi
  done
done
if [[ "$HELPERS_OK" == "true" ]]; then
  pass "Every helper called in a launcher is defined in that launcher"
fi

EXPORT_TMP="$(mktemp -d "$(pwd)/.verify-export.XXXXXX")"
echo ""
echo "📤 Testing 'export-scripts' → $EXPORT_TMP"
if docker run --rm -v "$EXPORT_TMP:/out" "$DEV_TEST_IMAGE" export-scripts >/dev/null; then
  EXPORT_OK="true"
  for f in setup.sh preview.sh deploy.sh; do
    if ! cmp -s "$f" "$EXPORT_TMP/$f"; then
      EXPORT_OK="false"
      fail "Exported $f differs from repo copy (stale image?)"
    fi
  done
  for f in setup.bat preview.bat deploy.bat setup.ps1 preview.ps1 deploy.ps1; do
    if [[ ! -f "$EXPORT_TMP/$f" ]]; then
      EXPORT_OK="false"
      fail "Exported $f is missing"
    elif ! grep -q $'\r' "$EXPORT_TMP/$f"; then
      EXPORT_OK="false"
      fail "Exported $f lacks CRLF line endings (unix2dos step broken?)"
    fi
  done
  [[ "$EXPORT_OK" == "true" ]] && pass "export-scripts emits current launchers (CRLF intact on Windows files)"
else
  fail "export-scripts did not run"
fi
rm -rf "$EXPORT_TMP"

# ---------- 3c. Superseded builder images are removed, and ONLY those ----------
# The launchers mint a new 'teaching-quartz:src-<hash>' tag on every recipe
# change, so without this the orphans accumulate forever. The danger is the
# opposite one: Docker here is SHARED with other projects, so a cleanup that
# reached past its own tags would delete somebody else's images. This drives
# the launcher's REAL function (extracted from preview.sh, not retyped) against
# four throwaway images that stand in for each case.
echo ""
echo "🔎 Checking that a new build removes superseded builder images…"
PRUNE_SRC="$(mktemp "${TMPDIR:-/tmp}/verify_prune.XXXXXX.sh")"
awk '/^prune_superseded_images\(\) \{/,/^\}/' preview.sh > "$PRUNE_SRC"
if [[ ! -s "$PRUNE_SRC" ]]; then
  fail "Could not extract prune_superseded_images() from preview.sh"
else
  # shellcheck source=/dev/null
  source "$PRUNE_SRC"

  PRUNE_KEEP="teaching-quartz:src-verifykeep"
  PRUNE_OLD="teaching-quartz:src-verifyold"
  PRUNE_INUSE="teaching-quartz:src-verifyinuse"
  PRUNE_OTHER="verify-other-project:latest"
  PRUNE_CONTAINER="verify-prune-inuse"

  # Distinct image IDs matter: tags sharing one ID cannot tell these cases
  # apart, because 'docker rmi <tag>' on a shared ID only untags.
  prune_fixture_image() {
    printf 'FROM scratch\nLABEL ca.russellgordon.verify=%s\n' "$2" \
      | docker buildx build --load -q -t "$1" - >/dev/null 2>&1
  }
  docker rm -f "$PRUNE_CONTAINER" >/dev/null 2>&1 || true
  prune_fixture_image "$PRUNE_KEEP"  keep
  prune_fixture_image "$PRUNE_OLD"   old
  prune_fixture_image "$PRUNE_INUSE" inuse
  prune_fixture_image "$PRUNE_OTHER" other
  # An explicit command is required even though this container never runs:
  # 'docker create' refuses an image with no entrypoint, and a container that
  # was never created would make the in-use case pass vacuously.
  if ! docker create --name "$PRUNE_CONTAINER" "$PRUNE_INUSE" /noop >/dev/null 2>&1; then
    fail "prune: could not create the fixture container — the in-use case was not exercised"
  fi

  prune_superseded_images "$PRUNE_KEEP"

  prune_image_exists() { docker image inspect "$1" >/dev/null 2>&1; }
  PRUNE_OK="true"
  if prune_image_exists "$PRUNE_OLD"; then
    fail "prune: superseded tag $PRUNE_OLD was NOT removed"
    PRUNE_OK="false"
  fi
  if ! prune_image_exists "$PRUNE_KEEP"; then
    fail "prune: the tag just built ($PRUNE_KEEP) was removed"
    PRUNE_OK="false"
  fi
  if ! prune_image_exists "$PRUNE_INUSE"; then
    fail "prune: $PRUNE_INUSE was removed while a container still referenced it"
    PRUNE_OK="false"
  fi
  if ! prune_image_exists "$PRUNE_OTHER"; then
    fail "prune: removed $PRUNE_OTHER — another project's image is not ours to delete"
    PRUNE_OK="false"
  fi
  [[ "$PRUNE_OK" == "true" ]] && pass "Superseded builder images are removed; the current tag, an in-use tag and another project's image are left alone"

  docker rm -f "$PRUNE_CONTAINER" >/dev/null 2>&1 || true
  for t in "$PRUNE_KEEP" "$PRUNE_OLD" "$PRUNE_INUSE" "$PRUNE_OTHER"; do
    docker rmi -f "$t" >/dev/null 2>&1 || true
  done
fi
rm -f "$PRUNE_SRC"

# -------------------- 4. Baked files match the working tree --------------------
echo ""
echo "🔬 Comparing files baked into the image against the working tree…"
BAKED_OK="true"
check_baked() {
  local repo_path="$1" image_path="$2"
  if ! docker run --rm -v "$(pwd):/repo:ro" "$DEV_TEST_IMAGE" cmp -s "/repo/$repo_path" "$image_path"; then
    BAKED_OK="false"
    fail "Image file $image_path differs from repo $repo_path"
  fi
}
check_baked scripts/setup_course.py       /opt/scripts/setup_course.py
check_baked scripts/build_site.py         /opt/scripts/build_site.py
check_baked scripts/deploy.py             /opt/scripts/deploy.py
check_baked scripts/netlify_badge.py      /opt/scripts/netlify_badge.py
check_baked patches/Explorer.tsx          /opt/quartz/quartz/components/Explorer.tsx
check_baked patches/FolderContent.tsx     /opt/quartz/quartz/components/pages/FolderContent.tsx
check_baked patches/explorer.inline.ts    /opt/quartz/quartz/components/scripts/explorer.inline.ts
# Head.tsx carries the <link rel="icon"> tags, so a stale copy in the image is
# how a site would quietly go back to wearing the Quartz logo.
check_baked patches/Head.tsx              /opt/quartz/quartz/components/Head.tsx
check_baked support/Backlinks.tsx         /opt/support/Backlinks.tsx
check_baked support/colour_schemes.json   /opt/support/colour_schemes.json
check_baked support/favicon/favicon.ico   /opt/support/favicon/favicon.ico
check_baked support/favicon/icon.svg      /opt/support/favicon/icon.svg
check_baked support/favicon/apple-touch-icon.png /opt/support/favicon/apple-touch-icon.png
check_baked support/favicon/icon.png      /opt/support/favicon/icon.png
[[ "$BAKED_OK" == "true" ]] && pass "Baked scripts, patches, and support files match the working tree"

# -------------------- 4b. The hide filter must be IN THE IMAGE --------------------
# The Explorer's filterFn is what makes a teacher's hidden pages hidden, and
# build_site.py can only rewrite the omit Set inside it — never create it. It
# used to be patched into a RUNNING container by setup_course.py, which meant
# any container recreation silently published Private Notes, Curriculum and
# Learning Goals. Asserted against the IMAGE on purpose: a check that ran in a
# long-lived container would have passed throughout the whole time this was
# broken.
echo ""
echo "🔎 Checking the Explorer's hide filter is baked into the image…"
ANCHOR_OK="true"
for layout in /opt/quartz/quartz.layout.ts /opt/quartz-site/quartz.layout.ts; do
  if ! docker run --rm "$DEV_TEST_IMAGE" grep -q 'CQ4T-OMIT-ANCHOR' "$layout" 2>/dev/null; then
    fail "The Explorer's hide filter is missing from $layout in the image — hidden pages would be published"
    ANCHOR_OK="false"
  fi
done
[[ "$ANCHOR_OK" == "true" ]] && pass "The Explorer's hide filter is baked into the image (both Quartz copies)"

# -------------------- 5. Drive the real launcher against the image --------------------
echo ""
echo "🧹 Removing existing '$CONTAINER_NAME' container so the launcher recreates it"
echo "   from ${DEV_TEST_IMAGE}…"
docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

STAMP_FILE="$(mktemp -t cq4t-stamp)"
echo ""
echo "🚦 Running: ./preview.sh EXC2O 1 --image $DEV_TEST_IMAGE --full-rebuild --build-only"
echo "   (full rebuild ensures the Quartz scaffold comes from the dev-test image)"
echo ""
if ./preview.sh EXC2O 1 --image "$DEV_TEST_IMAGE" --full-rebuild --build-only; then
  pass "preview.sh completed against $DEV_TEST_IMAGE"
else
  fail "preview.sh exited non-zero"
fi

# -------------------- 6. Post-flight checks --------------------
SITE_PUBLIC="courses/EXC2O/.merged_output/section1/public"
SITE_INDEX="$SITE_PUBLIC/index.html"
if [[ -f "$SITE_INDEX" && "$SITE_INDEX" -nt "$STAMP_FILE" ]]; then
  pass "Built site is present and freshly generated ($SITE_INDEX)"
else
  fail "Built site missing or stale at $SITE_INDEX"
fi
rm -f "$STAMP_FILE"

# -------------------- 6b. The site wears Plantoir's icon, not Quartz's --------------------
# Two halves that fail independently: the FILES have to be emitted (static/ by
# the Static emitter, the root copy by the Assets emitter out of content/), and
# the PAGE has to link them. A site can have all four files and still show the
# Quartz logo if Head.tsx did not make it into the image.
if [[ -f "$SITE_INDEX" ]]; then
  ICON_OK="true"
  for asset in static/icon.svg static/favicon.ico static/apple-touch-icon.png static/icon.png favicon.ico; do
    if [[ ! -f "$SITE_PUBLIC/$asset" ]]; then
      fail "Built site is missing $asset"
      ICON_OK="false"
    fi
  done
  # The root favicon.ico and quartz/static/icon.png must be OURS, byte for byte.
  # Note what this does NOT prove: build_site.py looks for support/favicon
  # relative to the container's WORKDIR before /opt/support/favicon, and when
  # verify.sh runs, that WORKDIR *is* this repo — so these two lines compare
  # the working tree with itself. What proves the IMAGE carries the right
  # bytes is the four check_baked lines above; a teacher's working folder has
  # .toolchain/support rather than support/, so it correctly falls through to
  # the baked copy.
  for pair in "favicon.ico:favicon.ico" "static/icon.png:icon.png"; do
    built="$SITE_PUBLIC/${pair%%:*}"
    source_file="support/favicon/${pair##*:}"
    if [[ -f "$built" ]] && ! cmp -s "$built" "$source_file"; then
      fail "$built is not $source_file — the site is carrying a different icon"
      ICON_OK="false"
    fi
  done
  for needle in 'static/icon.svg' 'static/favicon.ico' 'apple-touch-icon'; do
    if ! grep -q "$needle" "$SITE_INDEX"; then
      fail "index.html does not link $needle"
      ICON_OK="false"
    fi
  done
  [[ "$ICON_OK" == "true" ]] && pass "Built site carries and links the Plantoir icon (tab, root, Apple touch)"
fi

RUNNING_IMAGE="$(docker inspect -f '{{.Config.Image}}' "$CONTAINER_NAME" 2>/dev/null || echo '(none)')"
if [[ "$RUNNING_IMAGE" == "$DEV_TEST_IMAGE" ]]; then
  pass "Container '$CONTAINER_NAME' is running from $DEV_TEST_IMAGE"
else
  fail "Container '$CONTAINER_NAME' is running from '$RUNNING_IMAGE', not $DEV_TEST_IMAGE"
fi

# -------------------- Summary --------------------
echo ""
echo "==================== verify.sh summary ===================="
for line in "${RESULTS[@]}"; do echo "$line"; done
echo "==========================================================="
if [[ "$FAILED" == "true" ]]; then
  echo "❌ Verification FAILED — see items above."
  exit 1
fi
echo "✅ All checks passed."
echo ""
echo "ℹ️  Notes:"
echo "   • The '$CONTAINER_NAME' container was left running from $DEV_TEST_IMAGE"
echo "     so you can poke at it (e.g., ./preview.sh EXC2O 1 --image $DEV_TEST_IMAGE)."
echo "   • To return to the normal image, run:  docker rm -f $CONTAINER_NAME"
echo "     (the next ./setup.sh or ./preview.sh run recreates it automatically)."
echo "   • Colima was left exactly as it was found — never stopped by this script."
