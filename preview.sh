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

# ---- One spelling of this folder (GitHub #189) ------------------------
# Identical in setup.sh, preview.sh and deploy.sh, straight after the line
# above, and checked there by scripts/test_folder_spelling.py.
#
# The same folder can arrive here spelled several ways: through a link, as
# /tmp for /private/tmp, as /System/Volumes/Data/…, in the wrong case, or
# with an accented letter in the other Unicode form (the app hands a
# launcher é as e + accent whatever the disk stores). bash's own `pwd -P`
# keeps the case and the form it was HANDED; /bin/pwd asks the disk, and
# answers with the folder's own name — the same answer the app gets
# (FolderIdentity.canonicalPath). Moving into that spelling here means the
# folder's id, its workspace's name, the builds folder and the courses
# folder the workspace mounts all come from ONE spelling, whoever ran this
# and however they typed it. Without it, two spellings of one folder had
# two workspaces and two builds folders, and each cleared the other's.
#
# The id the spelling we were handed WOULD have had is kept, so the
# leftovers of that second copy can be cleared away (see
# clear_away_this_folders_other_spelling).
FOLDER_ID_AS_HANDED="$(pwd -P | shasum -a 256 | cut -c1-8)"
cd "$(/bin/pwd -P)"

# Arguments
COURSE="$1"
SECTION="$2"

# Shift COURSE and SECTION out of the way
shift 2

# A course code may not begin with a dot, and the refusal is here rather than
# in a comment claiming it cannot happen. Plantoir builds a reference course
# under a HIDDEN folder inside courses/ and renames it into place as the last
# act; handed that hidden name, this script used to treat it as an ordinary
# course — the uppercased name still resolves on a case-insensitive volume —
# and during the copy there is no marker yet to refuse it. The app can never
# pass such a name, but a person or another program can type one.
if [[ "$COURSE" == .* ]]; then
  echo ""
  echo "❌ A course code cannot begin with a dot."
  echo "   Choose one of your courses — the codes in Plantoir's sidebar."
  echo ""
  exit 1
fi



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
# --non-interactive is looked for HERE, before the main parser below, for the
# same reason deploy.sh pre-scans for it: the first question this script asks —
# the 'Open' course-code guard — comes before that parser. The parser also
# accepts the flag, so it is not reported as an unknown option; this only makes
# it visible early.
#
# preview.sh needs this even though it publishes nothing, because a SCHEDULED
# publish builds before it publishes and the mac's launchd agent runs
# `preview.sh --build-only` directly (ScheduledDeploy.oneShotCommand). Without
# it this script has no `set -e`: the read fails at end of input, `_ans` stays
# empty, `${_ans:-Y}` takes the DEFAULT, and the build quietly retargets a
# DIFFERENT course code — announcing it to nobody. That is a worse failure than
# the refusal, because the publish then succeeds against the wrong course.
NON_INTERACTIVE="false"
for _early_arg in "$@"; do
  if [[ "$_early_arg" == "--non-interactive" ]]; then NON_INTERACTIVE="true"; fi
done

# Called immediately before every question this script asks. Exit code 3 means
# "a question went unanswered" and nothing else, matching deploy.sh and
# deploy.py's NEEDS_AN_ANSWER.
assert_can_ask() {
  [[ "$NON_INTERACTIVE" == "true" ]] || return 0
  echo ""
  echo "This build was set to happen on its own, so nobody is here to answer:"
  echo "   $1"
  echo " $2"
  echo " Nothing was built."
  exit 3
}

_SAVED_ARGS=("$@")
while [[ $# -gt 0 ]]; do
  case "$1" in
    --image)
      if [[ $# -lt 2 ]]; then echo "❌ --image requires a value"; exit 1; fi  # never shown to a teacher: reached only with --image or --context, which the app never passes
      OVERRIDE_IMAGE="$2"; shift 2 ;;
    *) shift ;;
  esac
done
set -- "${_SAVED_ARGS[@]}"

resolve_build_context() {
  if [[ -f "./Dockerfile" ]]; then
    echo "."
  elif [[ -f "./.toolchain/Dockerfile" ]]; then
    echo "./.toolchain"  # never shown to a teacher: the answer $(resolve_build_context) captures
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
    echo "❌ This folder is missing the recipe for its website builder."
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
  assert_can_ask "Fix course code to '$SUGGESTED'? [Y/n]" "Preview this section once from Plantoir, where you can answer it."
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
  echo "  --non-interactive                  Refuse rather than ask, for a build nobody is watching"
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
    --non-interactive)
      # No `shift` here: the loop shifts once at the bottom for every case.
      # Shifting twice ate the NEXT argument, so `--non-interactive
      # --build-only` lost --build-only and a scheduled run would have
      # started a SERVER instead of building. Latent only because the
      # wrapper happens to put the flag last.
      NON_INTERACTIVE="true" ;;
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
  # don't exit here: build_site.py checks the section against the course's
  # section_numbers and says so.
fi

# -------------------- Mount-aware container handling --------------------
# ---- One container per working folder --------------------------------
# The container's name is derived from THIS folder, so two working folders
# (this year's courses and last year's, say) each get their own container
# and never repoint each other's mounts. The same derivation is used by
# the macOS app; the trailing newline from pwd is part of the hashed
# input, so keep `/bin/pwd -P | shasum` exactly as written — /bin/pwd, not
# bash's own `pwd -P`, for the reason given at the top of this file.
WORKDIR_ID="$(/bin/pwd -P | shasum -a 256 | cut -c1-8)"
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
  printf '%s\n' "$(/bin/pwd -P)" > "$BUILD_ROOT/working-folder.txt" 2>/dev/null || true
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
# The append waits for the lock the app holds on the Logs FOLDER while it
# trims the file (GitHub #238), so a line added here can never land in the
# instant the app replaces the file with a shorter copy and vanish with the old
# one. `lockf -k` on the folder takes the same lock the app's `flock` does and
# creates no file. Where there is no lockf, or the volume refuses locks, the
# line is appended unlocked rather than dropped.
note_on_the_trail() {
  local trail="${HOME%/}/Library/Logs/Plantoir"
  mkdir -p "$trail" 2>/dev/null || return 0
  local trail_line
  trail_line="$(date '+%Y-%m-%d %H:%M:%S') · $1"
  if [ -x /usr/bin/lockf ] && /usr/bin/lockf -k "$trail" /bin/sh -c 'printf "%s\n" "$1" >> "$2/activity.txt"' note "$trail_line" "$trail" 2>/dev/null; then
    return 0
  fi
  printf '%s\n' "$trail_line" >> "$trail/activity.txt" 2>/dev/null || true
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
# >>> PROCESS TABLE BLOCK >>> — identical in setup.sh, preview.sh and
# deploy.sh; scripts/test_port_blocks.py checks that the three copies match,
# and that nothing else in a launcher reads the process table. Keep the
# markers, and keep the three copies the same.
# ---- Who is running what: the ONE reader of the process table (#388) ----
# Two questions are asked of the live process table, and until #388 each had
# its own reader, which had already come to disagree:
#   - preview.sh's guard (#381): is this section being deployed right now?
#     (a_deploy_is_running_for, in the PREVIEW WHILE DEPLOYING GUARD);
#   - the look before a website builder is set up again (#378): has the
#     program that started this work gone? (the_owners_of_the_work, in the
#     PREVIEW PORT BLOCK).
# Both now ask the_launchers_running, below, and each keeps its own POLICY —
# what counts, and which way to fail — because the two fail-safes point
# opposite ways on purpose (see each caller). What they share is how the
# table is READ: how a launcher, its course and section and its flags are
# recognised, how a publish set for later is recognised by its script name,
# which processes are this run's own family, and when the table counts as
# unreadable.
#
# This is its own block, straight after the CONTAINER MOUNT BLOCK, rather
# than inside the PREVIEW PORT BLOCK where the second reader lived: bash
# defines a function only when it reaches it, the PREVIEW PORT BLOCK comes
# late in each launcher, and preview.sh asks its guard long before that —
# before anything is changed (#381). A guard calling a function not defined
# yet would get "command not found", read it as an unreadable table, and let
# every preview through without a word.
#
# the_launchers_running PLACES [NAME] [ID]
#   PLACES  the places asked about, ";"-joined (an awk -v value cannot hold a
#           newline), each "<course> <section>" with "+" for a space in the
#           course (CourseCodeRule refuses a "+"; the command-line setup
#           does not, and a course like "C++" is then misread — see
#           whatCountsAsRunning.knownLimits). The course may be empty. The
#           caller answers work holding ";" or "\" itself: either would
#           shift the places' numbers (the_owners_of_the_work).
#   NAME/ID a website builder by its name and its id: a `docker exec` aimed
#           at it is reported too. Left out, none is.
# Prints one record per line, every field one word:
#   <pid> <origin> <what> <program> <flags> <folder> <places>
#   what     preview.sh, deploy.sh or setup.sh (the FIRST launcher named on
#            the line), scheduled, or exec. One process can print up to
#            three records — a launcher, a publish set for later and an exec
#            are looked for independently, as they always were.
#   origin   who started it: scheduled, claude, codex, assistant, window or
#            terminal (the_owners_of_the_work says how it is read).
#   program  1 when the launcher is the PROGRAM — the first word, or the
#            script a shell was handed before any word starting with "-" —
#            and 0 when the line merely names it (a `claude -p` prompt, a
#            `bash -c` wrapper whose own child is the launcher).
#   flags    the launcher's OWN words among --stop, --build-only,
#            --builder-tag, --reset-token, --logout and --help (-h), without
#            their dashes, ","-joined; "-" when none.
#   folder   for a publish set for later, the folder id in its label, or "-"
#            when the label carries none; "-" for everything else.
#   places   the 1-based numbers of the PLACES this record is for,
#            ","-joined, or "-". A launcher is for a place when its own
#            words, upper-cased and one space between them, BEGIN with
#            "<COURSE> <SECTION> " — so section 1 is not section 12, and AP
#            CALC 1 is not CALC 1. A publish set for later is for a place
#            when its label, `ca.russellgordon.Plantoir.deploy.<CODE>.
#            section<N>[.<folder id>].sh` (ScheduledDeploy.agentLabel), holds
#            that place: <CODE> as ScheduledDeploy.sanitizedCode writes it —
#            upper case, anything not A-Z or 0-9 as "-", and COURSE for an
#            empty code. The name must end ".sh": a `tail -f` of the
#            scheduled deploy's .log is somebody READING about it, not it.
# Returns 0 when it read the table, and 2 — printing nothing — when it could
# not: `ps` failed, or answered with a table that does not list this very
# run (#378 review N6: a `ps` answering 0 with nothing in it would otherwise
# make every program look gone). What 2 MEANS is each caller's to decide.
#
# This run, its ancestors and its descendants never count: a login shell
# wrapping this run, or a shell running `./deploy.sh C S; ./preview.sh C S`,
# carries the same words.
the_launchers_running() {
  local table
  table="$(ps -Ao pid=,ppid=,args= 2>/dev/null)" || return 2
  printf '%s\n' "$table" | awk -v self="$$" '$1 == self { found = 1 } END { exit !found }' || return 2
  printf '%s\n' "$table" | awk -v self="$$" -v places="${1:-}" -v name="${2:-}" -v id="${3:-}" '
    function base(word,    parts, n) { n = split(word, parts, "/"); return tolower(parts[n]) }
    # A course code as ScheduledDeploy.sanitizedCode writes it into a label
    # (contracts/shared-rules.json -> previewWhileItsSectionDeploys.labelCodeCases).
    function label_code(course,    s) {
      s = toupper(course)
      gsub(/[^A-Z0-9]/, "-", s)
      if (s == "") s = "COURSE"
      return s
    }
    # Who started process p: the first answer found walking up from it — a
    # publish set for later first (the scheduled runner has no --mcp-stdio,
    # so it must not be read as a window), then an assistant serving another
    # app (claude or codex above it, if either is), then the Plantoir app
    # itself, then claude or codex running the launcher directly, and
    # otherwise a command typed in Terminal.
    function origin_of(p,    q, steps, sched, mcp, app, claude, codex, w, n, word) {
      q = p; steps = 0; sched = 0; mcp = 0; app = 0; claude = 0; codex = 0
      while ((q in args) && steps < 64) {
        if (args[q] ~ /\/Plantoir\/scheduled\// || args[q] ~ /--run-scheduled-deploy/) sched = 1
        if (args[q] ~ /--mcp-stdio/) mcp = 1
        else if (args[q] ~ /\/Contents\/MacOS\/Plantoir([ \t]|$)/) app = 1
        n = split(args[q], word, /[ \t]+/)
        for (w = 1; w <= n && w <= 2; w++) {
          if (base(word[w]) == "claude") claude = 1
          if (base(word[w]) == "codex") codex = 1
        }
        if (parent[q] == q || parent[q] < 1) break
        q = parent[q]; steps++
      }
      if (sched) return "scheduled"
      if (mcp) return claude ? "claude" : (codex ? "codex" : "assistant")
      if (app) return "window"
      if (claude) return "claude"
      if (codex) return "codex"
      return "terminal"
    }
    function joined(list, item) { return (list == "" ? item : list "," item) }
    function or_dash(list) { return (list == "" ? "-" : list) }
    {
      pid = $1; parent[pid] = $2
      line = $0
      sub(/^[ \t]*[0-9]+[ \t]+[0-9]+[ \t]+/, "", line)
      args[pid] = line
      order[++count] = pid
    }
    END {
      # The places asked about. The section is the last word; the course is
      # everything before it, "+" read back as a space. It is compared two
      # ways: as the words a launcher is given, runs of blanks as one space
      # (a course typed "AP  CALC" is the course AP CALC to the launcher);
      # and as its label code, written from the course exactly as given, as
      # ScheduledDeploy writes it.
      asked = (places == "") ? 0 : split(places, place, ";")
      for (j = 1; j <= asked; j++) {
        usable[j] = 0
        if (!match(place[j], / [^ ]*$/)) continue
        course = substr(place[j], 1, RSTART - 1)
        wanted_section[j] = substr(place[j], RSTART + 1)
        if (wanted_section[j] == "") continue
        gsub(/\+/, " ", course)
        wanted_code[j] = label_code(course)
        spaced = toupper(course)
        gsub(/[ \t]+/, " ", spaced)
        sub(/^ /, "", spaced)
        sub(/ $/, "", spaced)
        wanted_words[j] = spaced " " wanted_section[j] " "
        usable[j] = 1
      }
      # This run and its ancestors.
      mine[self] = 1
      p = self
      while ((p in parent) && parent[p] != p && !(parent[p] in mine) && parent[p] > 1) {
        p = parent[p]; mine[p] = 1
      }
      for (i = 1; i <= count; i++) {
        pid = order[i]
        if (pid in mine) continue
        # ... and its descendants.
        q = pid; ours = 0; steps = 0
        while ((q in parent) && steps < 64) {
          if (parent[q] == self) { ours = 1; break }
          q = parent[q]; steps++
        }
        if (ours) continue
        n = split(args[pid], word, /[ \t]+/)
        # A launcher: the first one named on the line.
        for (w = 1; w <= n; w++) {
          if (word[w] !~ /(^|\/)(preview|deploy|setup)\.sh$/) continue
          # The program: the first word, or the script a shell was handed (a
          # path with spaces splits into several words, none of them a flag).
          program = (w == 1)
          if (w > 1 && word[1] ~ /(^|\/)(ba|z|da|k)?sh$/) {
            program = 1
            for (v = 2; v < w; v++) {
              if (word[v] ~ /^-/) program = 0
            }
          }
          # Everything after the launcher name, one space between words, and
          # the flags among its own words.
          after = ""; flags = ""
          for (a = w + 1; a <= n; a++) {
            after = after " " word[a]
            if (word[a] ~ /^--(stop|build-only|builder-tag|reset-token|logout|help)$/) {
              flag = substr(word[a], 3)
              if (index("," flags ",", "," flag ",") == 0) flags = joined(flags, flag)
            } else if (word[a] == "-h" && index("," flags ",", ",help,") == 0) {
              flags = joined(flags, "help")
            }
          }
          after = toupper(substr(after, 2)) " "
          for_places = ""
          for (j = 1; j <= asked; j++) {
            if (usable[j] && index(after, wanted_words[j]) == 1) for_places = joined(for_places, j)
          }
          print pid, origin_of(pid), base(word[w]), program, or_dash(flags), "-", or_dash(for_places)
          break
        }
        # A publish set for later, by the name of the script launchd runs.
        if (match(args[pid], /ca\.russellgordon\.Plantoir\.deploy\.[A-Za-z0-9-]+\.section[0-9]+(\.[0-9a-f]+)?\.sh([ \t]|$)/)) {
          label = substr(args[pid], RSTART + 33, RLENGTH - 33)
          sub(/[ \t]$/, "", label)
          sub(/\.sh$/, "", label)
          k = index(label, ".section")
          code = substr(label, 1, k - 1)
          rest = substr(label, k + 8)
          dot = index(rest, ".")
          if (dot > 0) {
            label_section = substr(rest, 1, dot - 1); folder = substr(rest, dot + 1)
          } else {
            label_section = rest; folder = "-"
          }
          for_places = ""
          for (j = 1; j <= asked; j++) {
            if (usable[j] && wanted_code[j] == code && wanted_section[j] == label_section) for_places = joined(for_places, j)
          }
          print pid, origin_of(pid), "scheduled", 0, "-", folder, or_dash(for_places)
        }
        # A docker exec aimed at this website builder, by its name or its id.
        if (name != "" || id != "") {
          client = 0; asked_exec = 0
          for (w = 1; w <= n; w++) {
            if (base(word[w]) == "docker") client = 1
            else if (client && word[w] == "exec") asked_exec = 1
            else if (asked_exec && ((name != "" && word[w] == name) || (id != "" && (word[w] == id || word[w] == substr(id, 1, 12))))) {
              print pid, origin_of(pid), "exec", 0, "-", "-", "-"
              break
            }
          }
        }
      }
    }'
}
# <<< PROCESS TABLE BLOCK <<<
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
# CLI, and BuildKit — is installed as static binaries into the app's own
# space under Application Support: copied out of the Mac app when it carries
# them (Apple silicon, since GitHub #312), downloaded and checked otherwise.
# No Homebrew, no administrator rights. Tools already on the machine
# (Homebrew installs included) are used as-is.
TOOLS_DIR="$HOME/Library/Application Support/Plantoir/tools"
export PATH="$TOOLS_DIR/bin:$PATH"

# >>> PREVIEW WHILE DEPLOYING GUARD >>> — preview.sh only. Cut out between
# these two markers and run against a pretend process table by
# scripts/test_preview_while_deploying.py; keep the markers.
# ---- A section being deployed cannot be previewed (GitHub #381) --------
# Russell's decision 4 on #378: "a preview of a section cannot start AT ALL
# while that same section is being deployed", whoever started the deploy.
# The app refuses in the window (SectionDetailView.startPreview) and other
# programs are refused by their work leases (#156); this is the layer that
# sees the rest — a deploy.sh typed in Terminal, one a Revise with Claude
# session's own command line runs, and a preview started from a command
# line while any deploy runs. The rule and its cases are
# contracts/shared-rules.json -> previewWhileItsSectionDeploys.
#
# Asked on a SERVING run only, and here: after the arguments are checked,
# before anything is changed — no builds link, no website builder, no
# workspace looked at or set up again. A serving preview that remade the
# folder's workspace in a deploy's host-side stretch (a token being read,
# the moment between its two legs) would pull it out from under the deploy,
# which is the harm this exists for.
#
# What counts as a deploy of C/S, read from the LIVE process table — never
# a remembered process id, never a lease file:
#   - `deploy.sh C S …`, unless it only clears a saved token (--reset-token,
#     --logout) or prints its help; --diagnose DOES deploy. Only one working
#     in THIS folder counts: its working directory is asked of lsof, and one
#     that cannot be asked counts (a deploy of this very section is proved;
#     only its folder is not).
#   - a scheduled deploy of C/S: any process whose arguments name its script,
#     `ca.russellgordon.Plantoir.deploy.<CODE>.section<N>[.<folder id>].sh`
#     (ScheduledDeploy.agentLabel; <CODE> as ScheduledDeploy.sanitizedCode
#     writes it). launchd's `Plantoir --run-scheduled-deploy <script> …`
#     lives for the whole run, both legs, so the build leg counts too. A
#     label carrying ANOTHER folder's id is that folder's deploy.
# NOT a deploy: `preview.sh C S --build-only`. It is a publish's build leg,
# but it is also exactly what the assistant's "rebuild the preview" runs, and
# nothing on the command line tells the two apart — counting it would refuse
# every preview of a section while the assistant refreshed it, with a
# sentence that is false. The window refuses its own build leg from its
# publish record; a preview typed in Terminal during ANOTHER program's build
# leg is the one gap left, and the contract names it.
# How the table is read — which processes are launchers, for which course
# and section, with which flags; which name is a publish set for later; which
# processes are this run's own family — is the_launchers_running's, in the
# PROCESS TABLE BLOCK, shared with the look before a website builder is set
# up again (#388). What COUNTS as a deploy is decided here. A process table
# that cannot be read — `ps` fails, or its answer does not list this run —
# lets the preview THROUGH: the opposite of the look before a workspace is
# remade, on purpose: there, failing open costs a publish; here, failing
# closed would refuse every preview for as long as `ps` fails, which is
# "blocked until a restart" again. The window's check and the leases still
# stand when this one cannot see.
a_deploy_is_running_for() {
  local course="$1" section="$2" folder_id here records pid origin what program flags folder places cwd
  here="$(/bin/pwd -P)"
  folder_id="$(printf '%s\n' "$here" | shasum -a 256 | cut -c1-8)"
  # One place is asked about, so a record for it says "1".
  records="$(the_launchers_running "${course// /+} ${section}")" || return 1
  while read -r pid origin what program flags folder places; do
    [ "$places" = "1" ] || continue
    case "$what" in
      scheduled)
        # A label carrying ANOTHER folder's id is that folder's deploy.
        if [ "$folder" = "-" ] || [ "$folder" = "$folder_id" ]; then
          return 0
        fi ;;
      deploy.sh)
        # deploy.sh must be the PROGRAM, not merely named on a line.
        [ "$program" = "1" ] || continue
        case ",$flags," in
          *,reset-token,*|*,logout,*|*,help,*) continue ;;
        esac
        cwd="$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -n 1)"
        if [[ -z "$cwd" || "$cwd" == "$here" ]]; then
          return 0
        fi ;;
    esac
  done <<< "$records"
  return 1
}

# The sentence is contracts/shared-rules.json ->
# previewWhileItsSectionDeploys.sentences.launcher, and the trail line that
# entry's launcherLine — both checked by scripts/test_preview_while_deploying.py.
refuse_a_preview_while_its_section_deploys() {
  if a_deploy_is_running_for "$COURSE" "$SECTION"; then
    echo ""
    echo "❌ ${COURSE} section ${SECTION} is being deployed right now, so it cannot be previewed until that has finished."
    echo "   Nothing was changed."
    echo ""
    note_on_the_trail "${COURSE}/${SECTION} · the preview stopped before building — this section was being deployed"
    exit 1
  fi
}
# <<< PREVIEW WHILE DEPLOYING GUARD <<<

if [[ -z "$BUILD_ONLY" && -z "${STOP_MODE:-}" ]]; then
  refuse_a_preview_while_its_section_deploys
fi

# -------------------- Stop mode ----------------------------------------
# ./preview.sh CODE N --stop : kill this section's preview processes
# INSIDE the container. Ending the host-side script (closing the app's
# preview, Ctrl+C at the wrong moment) leaves the container-side build
# or server running — idle for a server, but a mid-flight build keeps
# burning CPU. This mode reclaims those resources. It must never start
# anything: no engine bootstrap, no image build, no container creation —
# if nothing is running, there is nothing to stop.
#
# WHICH processes belong to this section is not decided here. That rule
# lives once, in scripts/stop_preview.py, and is pinned by
# contracts/shared-rules.json -> stopPreview; it used to be written out
# three times (here, in preview.ps1, and in build_site.py) and the three
# had already drifted apart. This block's job is to deliver that rule to
# the right place and hand it the section's directories.
#
# The code is PIPED IN from the recipe rather than run from the image's
# own /opt/scripts, and that is not a style choice. Stop mode must never
# build anything, so it runs against whatever container is already there
# — which, right after an upgrade, is one built from the PREVIOUS image
# and has no such file. Naming a baked path would make `docker exec`
# fail with a message nobody sees (both callers discard this script's
# output and neither checks its exit code) while the build it was asked
# to stop carried on. Piping the host's copy works against any container
# old enough to have python3, which every image here has.
if [[ -n "${STOP_MODE:-}" ]]; then
  if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
    echo "✅ Nothing to stop — the website builder isn't running."
    exit 0
  fi
  if ! docker ps --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}$"; then
    echo "✅ Nothing to stop — this folder's website builder isn't running."
    exit 0
  fi
  echo "🧹 Stopping preview processes for ${COURSE} section ${SECTION}…"
  _STOP_RULE="$(resolve_build_context)/scripts/stop_preview.py"
  if [[ ! -f "$_STOP_RULE" ]]; then
    echo "⚠️ Cannot stop preview processes: the build recipe is incomplete."
    exit 0
  fi
  # Both spellings of the section's build folder. `.merged_output` is a
  # SYMLINK to the builds folder outside the working folder, and a
  # process's working directory is always the REAL path it is sitting in
  # — never the spelling it used to get there. The rule resolves each of
  # these as well, but it can only resolve what it was given, and the
  # symlink resolves correctly only INSIDE the container, which is where
  # it runs.
  docker exec -i "$CONTAINER_NAME" python3 - \
    --dir "/teaching/courses/${COURSE}/.merged_output/section${SECTION}" \
    --dir "/tmp/quartz-builds/${COURSE}/section${SECTION}" \
    --course "$COURSE" \
    --section "$SECTION" \
    --mode everything < "$_STOP_RULE"
  exit 0
fi

# Everything below builds, so this is the point the built website's home has
# to be settled — after stop mode, which must never create anything.
link_course_build_output "$COURSE"

# >>> GETTING-READY TURN BLOCK >>> — identical in setup.sh, preview.sh and
# deploy.sh, extracted between these two markers by
# scripts/test_getting_ready_turn.py, which checks the three copies agree and
# runs the real thing against every case in contracts/app-rules.json →
# builderWarmUp.turnCases. Keep the markers, and keep the three copies the same.
#
# ---- One launcher at a time gets the website builder ready -------------
# Starting the builder's virtual machine and building the website builder are
# the two slow, network-hungry steps, and two launchers doing either at once
# is never useful: two first starts fight over one virtual machine, and two
# builds of one recipe download the same ~340 MB twice. Since Plantoir began
# getting the builder ready in the BACKGROUND at first launch (bundle B), a
# teacher who clicks Create or Preview while that is still going is exactly
# this case, so the rule is structural here rather than something the app has
# to remember: whoever holds the turn goes first, and everyone else waits for
# it, then finds the builder ready and builds nothing.
#
# The turn is a folder, because `mkdir` either makes it or fails, atomically,
# on every Mac. Inside it is the holder's process id. A turn whose holder is
# no longer running — a launcher that was killed, a Mac that went to sleep
# and was restarted — is taken over rather than waited on for ever, and so is
# one whose id now belongs to a process started after the turn was taken, or
# one older than a ceiling; a turn with no id in it yet is given a minute. It is handed back as soon
# as the builder is ready (never held through a build or a publish), and on
# any exit. A waiting launcher says so once, after a couple of seconds, so a
# turn held for a moment says nothing at all.
READY_TURN="${HOME%/}/Library/Application Support/Plantoir/getting-ready.turn"
READY_TURN_IS_OURS=""
READY_TURN_SEEN_HOLDER=""
READY_TURN_PAUSE="${READY_TURN_PAUSE:-2}"

READY_TURN_CEILING="${READY_TURN_CEILING:-7200}"

# How many seconds a process has been running, from `ps -o etime=`
# ([[dd-]hh:]mm:ss), or nothing when there is no such process.
seconds_a_process_has_run() {
  local elapsed days=0 hours=0 minutes=0 seconds=0 rest first second third
  elapsed="$(ps -o etime= -p "$1" 2>/dev/null | tr -d ' ')"
  [[ -n "$elapsed" ]] || return 1
  rest="$elapsed"
  if [[ "$rest" == *-* ]]; then
    days="${rest%%-*}"
    rest="${rest#*-}"
  fi
  IFS=: read -r first second third <<<"$rest"
  if [[ -n "$third" ]]; then
    hours="$first"; minutes="$second"; seconds="$third"
  else
    minutes="$first"; seconds="$second"
  fi
  echo $(( 10#$days * 86400 + 10#$hours * 3600 + 10#$minutes * 60 + 10#$seconds ))
}

# True when the turn's holder has gone: its process is not running; or the
# process with its id STARTED AFTER the turn was taken, so the id has been
# reused by something else; or the turn is older than the ceiling (two hours
# by default — no builder takes that long to get ready); or it never wrote its
# id and the turn is more than a minute old. Without the middle two, a holder
# that died uncleanly and whose id a long-lived process later reused would be
# waited on for as long as that process lives — a scheduled publish included.
the_ready_turn_is_abandoned() {
  local made now age running
  made="$(stat -f %m "$READY_TURN" 2>/dev/null || echo 0)"
  now="$(date +%s)"
  age=$((now - made))
  READY_TURN_SEEN_HOLDER="$(cat "$READY_TURN/pid" 2>/dev/null || true)"
  if [[ -n "$READY_TURN_SEEN_HOLDER" ]]; then
    if ! kill -0 "$READY_TURN_SEEN_HOLDER" 2>/dev/null; then
      return 0
    fi
    if [[ "$age" -gt "$READY_TURN_CEILING" ]]; then
      return 0
    fi
    running="$(seconds_a_process_has_run "$READY_TURN_SEEN_HOLDER" || true)"
    if [[ -n "$running" && $((running + 5)) -lt "$age" ]]; then
      return 0
    fi
    return 1
  fi
  [[ "$age" -gt 60 ]]
}

take_the_ready_turn() {
  if [[ -n "$READY_TURN_IS_OURS" ]]; then
    return 0
  fi
  mkdir -p "$(dirname "$READY_TURN")" 2>/dev/null || true
  local waited=0
  while ! mkdir "$READY_TURN" 2>/dev/null; do
    if the_ready_turn_is_abandoned; then
      # Moved aside before it is removed, and only if it is still the one
      # just judged abandoned, so two launchers taking over at once cannot
      # remove a turn a third has just taken.
      if [[ "$(cat "$READY_TURN/pid" 2>/dev/null || true)" == "$READY_TURN_SEEN_HOLDER" ]]; then
        mv "$READY_TURN" "$READY_TURN.gone.$$" 2>/dev/null && rm -rf "$READY_TURN.gone.$$"
      fi
      continue
    fi
    if [[ "$waited" -eq 1 ]]; then
      # Carries the words the app's progress bar matches (TaskMilestones:
      # "Building your website builder"), so a waiting Create or Preview
      # shows the step it is really waiting on. Plain words only (rule 1).
      echo "⏳ Building your website builder — this Mac is already getting it ready, so this waits for that to finish…"
    fi
    waited=$((waited + 1))
    sleep "$READY_TURN_PAUSE"
  done
  printf '%s\n' "$$" > "$READY_TURN/pid"
  READY_TURN_IS_OURS=1
  trap give_back_the_ready_turn EXIT
}

give_back_the_ready_turn() {
  if [[ -z "$READY_TURN_IS_OURS" ]]; then
    return 0
  fi
  if [[ "$(cat "$READY_TURN/pid" 2>/dev/null || true)" == "$$" ]]; then
    rm -rf "$READY_TURN"
  fi
  READY_TURN_IS_OURS=""
}
# <<< GETTING-READY TURN BLOCK <<<
take_the_ready_turn

# >>> FIRST-RUN BLOCK >>> From this line to the bare `ensure_container_runtime`
# below, this text is IDENTICAL in setup.sh, preview.sh and deploy.sh.
# AppRulesContractTests (the three copies agree, and no printed line names the
# machinery) and scripts/test_helper_bootstrap.py (every case in
# contracts/app-rules.json → helperBootstrap, run for real) both read it from
# this line, so keep the line as it is.
#
# Pinned versions, bumped deliberately with toolchain updates. A bump reaches
# a Mac that already has Plantoir's copies too: the install stamp below
# records the versions it installed, and a different set is replaced on the
# next start of the website builder (GitHub #312).
COLIMA_VERSION="v0.10.3"
LIMA_VERSION="2.2.0"
DOCKER_CLI_VERSION="29.7.2"
BUILDX_VERSION="v0.36.1"
# What each download must hash to, for BOTH kinds of Mac (GitHub #312).
# Nothing was checked before #312. A download that does not match is deleted
# and treated as a failed download, so nothing half-verified is installed.
# Taken from the files themselves on 2026-09-26 and cross-checked against
# Lima's SHA256SUMS and Colima's .sha256sum (Docker publishes no checksums for
# these two). Bump each pair with its version; mac-app/Vendor/fetch-helpers.sh
# reads the Apple-silicon ones from here rather than keeping its own.
LIMA_SHA256_ARM64="bbdef91774885a0d05f7b048c4eb89ae2bcf3a0c252ae7ca7934e63df76d93c3"
LIMA_SHA256_X86_64="0d6f99c19f6e4bc3c92730c4c29d929e6927f0cb0a0ba1a84383367135a8ff31"
COLIMA_SHA256_ARM64="980ad8bf61a4ca370243f4cb41401a61276dcd2c2502bee7b9b86f9250169f34"
COLIMA_SHA256_X86_64="3082737fe8a98afda11cba7d9a20b6e56fe80c6153464beda04bec630758770b"
DOCKER_CLI_SHA256_ARM64="b8683ed19d1f06048a496f9b8429e2c71d0b088d475b7487c054ea3666c02a3c"
DOCKER_CLI_SHA256_X86_64="fb1f1aa7ac7af4364165b9eadfda92e96c8ced508fca74f53079719891367438"
BUILDX_SHA256_ARM64="214cdc36788602862dbc82b523d58648b4585c7b0ff95218b0817c44db5573d7"
BUILDX_SHA256_X86_64="52a39ee4012d18f83373656712102ebda55656121dcdabbbb1ccfbd41b7debe8"
# The website builder's starting disk, which the Mac app carries for Apple
# silicon (GitHub #312). It is the file COLIMA_VERSION itself downloads on a
# first start: Colima has its SHA-512 compiled in and refuses any other, so
# bumping Colima usually means bumping these four as well — fetch-helpers.sh
# refuses a pair that does not agree.
VM_IMAGE_RELEASE="v0.10.4"
VM_IMAGE_NAME="ubuntu-24.04-minimal-cloudimg-arm64-docker.raw.gz"
VM_IMAGE_SHA256="1fc0354f4f99734ce3886628cc7af8b0437c1a1d391b126bd09cba0df35ee53f"
VM_IMAGE_SHA512="32242674b046b5057e60c4aba334b51e3665f05412cda89ed081cc2de153ae5c41f6b105b5c442cbe48d78e2cc21e9ba1950e406b6fb4fc2fd1dd2259240abbd"
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




# ---- Where the helper programs come from (GitHub #312) ------------------
#
# The Mac app carries Apple-silicon copies of all four programs AND the
# website builder's starting disk, in Plantoir.app/Contents/Resources/helpers,
# and says where through PLANTOIR_BUNDLED_HELPERS. Nothing else sets it: a
# launcher typed at the command line, or run on an Intel Mac, downloads as it
# always has. The copies are INSTALLED into TOOLS_DIR and run from there,
# never from inside the app — the app can move, be renamed or be replaced by
# an update while the website builder is running, and anything written inside
# it would make every later update a full download instead of a small one.
# Why each rule is the way it is: documentation/03-launcher-scripts.md →
# "Where the helper programs come from".
#
# `.installed` in TOOLS_DIR is the install stamp: the pins line below, where
# the copies came from, and the SHA-256 of each program as installed. It is
# read as three separate questions, and ONLY for Plantoir's own copies — a
# program found anywhere else (Homebrew, a developer's own) is used as it is:
#   - different: the stamp's pins are not this launcher's, so a version
#     bump reaches a Mac that already has tools;
#   - damaged: a program no longer hashes to what was installed;
#   - unrecorded: no stamp at all (every Mac set up before #312). Replaced
#     from the app's copy when there is one; otherwise left exactly as it is,
#     which is the rule every launcher followed before the stamp existed.

# The line the stamp and the app's MANIFEST are compared on.
_helper_pins() {
  echo "pins ${COLIMA_VERSION} ${LIMA_VERSION} ${DOCKER_CLI_VERSION} ${BUILDX_VERSION} ${VM_IMAGE_SHA512}"
}

# The same versions as one word, for the line the app reads.
_helper_pins_word() {
  printf 'colima=%s,lima=%s,docker=%s,buildx=%s\n' "$COLIMA_VERSION" "$LIMA_VERSION" "$DOCKER_CLI_VERSION" "$BUILDX_VERSION"  # never shown to a teacher: a field of a PLANTOIR_ line the app reads
}

_helper_arch() {
  if [[ "$(uname -m)" == "arm64" ]]; then echo "arm64"; else echo "x86_64"; fi
}

# The pinned SHA-256 of one download for this Mac: `_helper_sha256 LIMA`.
_helper_sha256() {
  local name="${1}_SHA256_ARM64"
  if [[ "$(_helper_arch)" != "arm64" ]]; then name="${1}_SHA256_X86_64"; fi
  echo "${!name}"
}

# What each program brings with it, as paths inside TOOLS_DIR and inside the
# app's copy alike.
_helper_paths() {
  local tool
  for tool in "$@"; do
    case "$tool" in
      colima) echo "bin/colima" ;;  # never shown to a teacher: a path its caller captures with $( )
      limactl) echo "bin/limactl bin/lima share/lima" ;;  # never shown to a teacher: a path its caller captures with $( )
      docker) echo "bin/docker" ;;  # never shown to a teacher: a path its caller captures with $( )
      buildx) echo "cli-plugins/docker-buildx" ;;  # never shown to a teacher: a path its caller captures with $( )
    esac
  done
}

# The files the stamp vouches for: the programs themselves, not Lima's data.
_helper_stamped_paths() {
  local tool
  for tool in "$@"; do
    case "$tool" in
      colima) echo "bin/colima" ;;  # never shown to a teacher: a path its caller captures with $( )
      limactl) echo "bin/limactl bin/lima" ;;  # never shown to a teacher: a path its caller captures with $( )
      docker) echo "bin/docker" ;;  # never shown to a teacher: a path its caller captures with $( )
    esac
  done
}

# The "<sha256>  <path>" lines of a MANIFEST or stamp for the given paths; a
# directory path takes every file under it.
_helper_hash_lines() {
  local list="$1"
  shift
  awk -v wanted="$*" '
    BEGIN { count = split(wanted, prefix, " ") }
    length($1) == 64 && substr($0, 65, 2) == "  " {
      path = substr($0, 67)
      for (i = 1; i <= count; i++) {
        if (path == prefix[i] || index(path, prefix[i] "/") == 1) { print; next }
      }
    }' "$list"
}

# True when every one of the given paths has a line in the list, and the
# files under $1 still hash to what it says.
_helper_hashes_hold() {
  local folder="$1" list="$2" path lines
  shift 2
  for path in "$@"; do
    if ! grep -q "^[0-9a-f]*  ${path}\(/.*\)\{0,1\}$" "$list"; then
      return 1
    fi
  done
  lines="$(_helper_hash_lines "$list" "$@")"
  if [[ -z "$lines" ]]; then
    return 1
  fi
  (cd "$folder" && echo "$lines" | shasum -a 256 -c --status) >/dev/null 2>&1
}

# Why the app's own copy cannot be used for the given programs, as one word,
# or nothing when it can.
_bundle_problem() {
  local bundle="${PLANTOIR_BUNDLED_HELPERS:-}"
  if [[ -z "$bundle" || ! -f "$bundle/MANIFEST" ]]; then
    echo "none-in-app"
    return 0
  fi
  if ! grep -qx "arch $(_helper_arch)" "$bundle/MANIFEST"; then
    echo "other-arch"
    return 0
  fi
  # A copy of other versions is refused, even one that matches its own
  # MANIFEST: an app built before a re-fetch carries the old programs.
  if ! grep -qxF "$(_helper_pins)" "$bundle/MANIFEST"; then
    echo "bundle-check-failed"
    return 0
  fi
  if [[ $# -gt 0 ]]; then
    # shellcheck disable=SC2046  # the paths have no spaces, by construction
    if ! _helper_hashes_hold "$bundle" "$bundle/MANIFEST" $(_helper_paths "$@"); then
      echo "bundle-check-failed"
    fi
  fi
  return 0
}

# Copies the given programs out of the app into a staging folder, strips the
# browser's quarantine mark from the COPIES (never from the app), and checks
# the copies against the app's MANIFEST.
_stage_from_bundle() {
  local staging="$1" bundle="${PLANTOIR_BUNDLED_HELPERS:-}" path
  shift
  for path in $(_helper_paths "$@"); do
    mkdir -p "$staging/$(dirname "$path")"
    if ! cp -Rc "$bundle/$path" "$staging/$path" 2>/dev/null; then
      return 1
    fi
  done
  xattr -dr com.apple.quarantine "$staging" 2>/dev/null || true
  # shellcheck disable=SC2046
  _helper_hashes_hold "$staging" "$bundle/MANIFEST" $(_helper_paths "$@")
}

_download() {
  local url="$1" destination="$2" expected="$3" label="$4" actual=""
  echo "📦 Downloading ${label}…"
  if curl -fsSL --retry 3 -o "$destination" "$url"; then
    actual="$(shasum -a 256 "$destination" 2>/dev/null | awk '{ print $1 }')"
    if [[ -n "$expected" && "$actual" == "$expected" ]]; then
      return 0
    fi
  fi
  rm -f "$destination"
  echo "❌ Could not download ${label}."
  echo "   An internet connection is needed for this one-time setup."
  return 1
}

# Downloads the given programs into a staging folder, each checked against
# its pinned SHA-256 before anything is unpacked.
_stage_downloads() {
  local staging="$1" arch lima_arch docker_arch buildx_arch tool
  shift
  arch="$(_helper_arch)"
  if [[ "$arch" == "arm64" ]]; then
    lima_arch="arm64"; docker_arch="aarch64"; buildx_arch="arm64"
  else
    lima_arch="x86_64"; docker_arch="x86_64"; buildx_arch="amd64"
  fi
  mkdir -p "$staging/bin" || return 1
  # In the order the teacher is told about them: 1 of 4, 2 of 4, and so on.
  for tool in limactl colima docker buildx; do
    case " $* " in
      *" $tool "*) ;;
      *) continue ;;
    esac
    case "$tool" in
      limactl)
        _download "https://github.com/lima-vm/lima/releases/download/v${LIMA_VERSION}/lima-${LIMA_VERSION}-Darwin-${lima_arch}.tar.gz" "$staging/lima.tar.gz" "$(_helper_sha256 LIMA)" "what your website builder needs (1 of 4)" || return 1
        tar xzf "$staging/lima.tar.gz" -C "$staging" || return 1
        # The manuals and notes are not needed, and the notes hold a link
        # that moving file by file would follow.
        rm -rf "$staging/lima.tar.gz" "$staging/share/doc" "$staging/share/man"
        ;;
      colima)
        _download "https://github.com/abiosoft/colima/releases/download/${COLIMA_VERSION}/colima-Darwin-${arch}" "$staging/bin/colima" "$(_helper_sha256 COLIMA)" "what your website builder needs (2 of 4)" || return 1
        chmod +x "$staging/bin/colima" || return 1
        ;;
      docker)
        _download "https://download.docker.com/mac/static/stable/${docker_arch}/docker-${DOCKER_CLI_VERSION}.tgz" "$staging/docker.tar.gz" "$(_helper_sha256 DOCKER_CLI)" "what your website builder needs (3 of 4)" || return 1
        tar xzf "$staging/docker.tar.gz" -C "$staging" || return 1
        mv -f "$staging/docker/docker" "$staging/bin/docker" || return 1
        rm -rf "$staging/docker" "$staging/docker.tar.gz"
        ;;
      buildx)
        mkdir -p "$staging/cli-plugins" || return 1
        _download "https://github.com/docker/buildx/releases/download/${BUILDX_VERSION}/buildx-${BUILDX_VERSION}.darwin-${buildx_arch}" "$staging/cli-plugins/docker-buildx" "$(_helper_sha256 BUILDX)" "what your website builder needs (4 of 4)" || return 1
        chmod +x "$staging/cli-plugins/docker-buildx" || return 1
        ;;
    esac
  done
  # Every file each program brings is there: an archive laid out differently
  # after a version bump must not install half a program (#312 review L3).
  for tool in "$@"; do
    for path in $(_helper_paths "$tool"); do
      if [[ ! -e "$staging/$path" ]]; then
        echo "❌ Could not set up what your website builder needs."
        return 1
      fi
    done
  done
}

# Moves every file of a staging folder into place, one rename each, so a
# program that is running keeps the copy it started with.
_move_into_place() {
  local staging="$1" destination="$2" file
  for file in $(cd "$staging" && find . -type f); do
    file="${file#./}"
    mkdir -p "$destination/$(dirname "$file")"
    mv -f "$staging/$file" "$destination/$file" || return 1
  done
}

# Rewrites the stamp: the pins, where this install came from, and the hash of
# every program of Plantoir's that it can vouch for — the ones just installed,
# and the ones an up-to-date stamp already vouched for.
_write_stamp() {
  local how="$1" stamp="$TOOLS_DIR/.installed" next tool carried="" sources=""
  shift
  next="$TOOLS_DIR/.installed.next.$$"
  for tool in colima limactl docker; do
    case " $* " in
      *" $tool "*)
        sources="${sources}source ${tool} ${how}"$'\n'
        ;;
      *)
        if [[ -f "$stamp" ]] && grep -qxF "$(_helper_pins)" "$stamp"; then
          sources="${sources}$(grep "^source ${tool} " "$stamp" || true)"$'\n'
          # shellcheck disable=SC2046
          carried="${carried}$(_helper_hash_lines "$stamp" $(_helper_stamped_paths "$tool"))"$'\n'
        fi
        ;;
    esac
  done
  {
    _helper_pins
    # Where EACH program came from, so a report never calls a downloaded
    # program one from inside Plantoir because a later install was.
    printf '%s' "$sources" | grep -v '^$' || true
    printf '%s' "$carried" | grep -v '^$' || true
    # shellcheck disable=SC2046
    (cd "$TOOLS_DIR" && shasum -a 256 $(_helper_stamped_paths "$@"))
  } > "$next"
  mv -f "$next" "$stamp"
}

# Installs the given programs into TOOLS_DIR, from the app's copy or by
# downloading, and says so on the line the app reads. $1 is bundled or
# downloaded; $2 is the reason the app's copy was not used, when it was not.
_install_helpers() {
  local how="$1" why_not="$2" staging
  shift 2
  staging="$(mktemp -d "$TOOLS_DIR/.staging.XXXXXX")" || return 1
  if [[ "$how" == "bundled" ]]; then
    if ! _stage_from_bundle "$staging" "$@"; then
      rm -rf "$staging"
      return 1
    fi
  elif ! _stage_downloads "$staging" "$@"; then
    rm -rf "$staging"
    return 1
  fi
  if ! _move_into_place "$staging" "$TOOLS_DIR"; then
    rm -rf "$staging"
    return 1
  fi
  rm -rf "$staging"
  _write_stamp "$how" "$@"
  return 0
}

_note_helpers_installed() {
  local how="$1" why="$2" why_not="$3" which
  shift 3
  which="$(echo "$*" | tr ' ' ',')"
  if [[ "$how" == "bundled" ]]; then
    echo "PLANTOIR_HELPERS_INSTALLED: ${how} ${why} ${which} $(_helper_pins_word)"
  else
    echo "PLANTOIR_HELPERS_INSTALLED: ${how} ${why} ${which} $(_helper_pins_word) ${why_not}"
  fi
}

# Says, on the line the app reads, what one install did for each reason.
_note_helper_groups() {
  local how="$1" why_not="$2" missing="$3" different="$4" damaged="$5" unrecorded="$6"
  # shellcheck disable=SC2086  # word lists, by construction
  if [[ -n "$missing" ]]; then _note_helpers_installed "$how" missing "$why_not" $missing; fi
  # shellcheck disable=SC2086
  if [[ -n "$different" ]]; then _note_helpers_installed "$how" different "$why_not" $different; fi
  # shellcheck disable=SC2086
  if [[ -n "$damaged" ]]; then _note_helpers_installed "$how" damaged "$why_not" $damaged; fi
  # shellcheck disable=SC2086
  if [[ -n "$unrecorded" ]]; then _note_helpers_installed "$how" unrecorded "$why_not" $unrecorded; fi
  return 0
}

# True when the stamp has a line for every file the program brings.
_helper_stamp_lists() {
  local stamp="$1" path
  for path in $(_helper_stamped_paths "$2"); do
    if ! grep -q "^[0-9a-f]\{64\}  ${path}$" "$stamp"; then
      return 1
    fi
  done
  return 0
}

ensure_local_tools() {
  mkdir -p "$TOOLS_DIR/bin"
  local stamp="$TOOLS_DIR/.installed" tool where missing="" ours="" different="" damaged="" unrecorded="" why_not

  # Which programs are Plantoir's to look after: the ones not on this Mac
  # at all, and the ones in its own folder. Anything else is used as found.
  for tool in colima limactl docker; do
    where="$(command -v "$tool" 2>/dev/null || true)"
    if [[ -z "$where" ]]; then
      missing="${missing} ${tool}"
    elif [[ "$where" == "$TOOLS_DIR/bin/$tool" ]]; then
      ours="${ours} ${tool}"
    fi
  done

  # The stamp's three questions, program by program. A program the stamp
  # has no line for is unrecorded, not damaged: nothing says what it was.
  if [[ -n "$ours" ]]; then
    if [[ -f "$stamp" ]] && ! grep -qxF "$(_helper_pins)" "$stamp"; then
      different="$ours"
    else
      for tool in $ours; do
        if [[ ! -f "$stamp" ]] || ! _helper_stamp_lists "$stamp" "$tool"; then
          unrecorded="${unrecorded} ${tool}"
        # shellcheck disable=SC2046
        elif ! _helper_hashes_hold "$TOOLS_DIR" "$stamp" $(_helper_stamped_paths "$tool"); then
          damaged="${damaged} ${tool}"
        fi
      done
    fi
  fi

  # shellcheck disable=SC2086  # word lists, by construction
  why_not="$(_bundle_problem $missing $different $damaged $unrecorded)"
  if [[ -n "$unrecorded" && -n "$why_not" ]]; then
    # No copy of Plantoir's own to replace them with: keep what works.
    unrecorded=""
    # shellcheck disable=SC2086
    why_not="$(_bundle_problem $missing $different $damaged)"
  fi
  if [[ -z "${missing}${different}${damaged}${unrecorded}" ]]; then
    ensure_buildx
    return 0
  fi

  if [[ -z "$why_not" ]]; then
    echo "📦 Getting what your website builder needs ready…"
    # shellcheck disable=SC2086
    if _install_helpers bundled "" $missing $different $damaged $unrecorded; then
      _note_helper_groups bundled "" "$missing" "$different" "$damaged" "$unrecorded"
      ensure_buildx
      return 0
    fi
    why_not="bundle-check-failed"
    unrecorded=""
  fi
  if [[ -z "${missing}${different}${damaged}" ]]; then
    ensure_buildx
    return 0
  fi

  # shellcheck disable=SC2086
  if _install_helpers downloaded "$why_not" $missing $different $damaged; then
    _note_helper_groups downloaded "$why_not" "$missing" "$different" "$damaged" ""
  elif [[ -n "$missing" ]]; then
    exit 1
  else
    # Only a refresh failed: the copies already here still work.
    echo "   Carrying on with what is already on this Mac."
  fi

  ensure_buildx
}

# BuildKit is what builds the image. Without the plugin the build silently
# degrades to the legacy builder, which corrupts the export-scripts layer.
#
# Installed only when `docker buildx version` fails, and outside the stamp:
# it lives in ~/.docker/cli-plugins, which Docker Desktop and Homebrew share.
# A link there is theirs, and is never replaced (GitHub #312).
ensure_buildx() {
  if docker buildx version >/dev/null 2>&1; then
    return 0
  fi
  local plugins="$HOME/.docker/cli-plugins" staging="" why_not
  if [[ -L "$plugins/docker-buildx" ]]; then
    return 0
  fi
  if ! mkdir -p "$plugins" 2>/dev/null || ! staging="$(mktemp -d "$plugins/.staging.XXXXXX" 2>/dev/null)"; then
    echo "❌ Could not set up what your website builder needs."
    exit 1
  fi
  why_not="$(_bundle_problem buildx)"
  if [[ -z "$why_not" ]]; then
    if _stage_from_bundle "$staging" buildx && mv -f "$staging/cli-plugins/docker-buildx" "$plugins/docker-buildx"; then
      rm -rf "$staging"
      _note_helpers_installed bundled missing "" buildx
      return 0
    fi
    why_not="bundle-check-failed"
  fi
  if ! _stage_downloads "$staging" buildx || ! mv -f "$staging/cli-plugins/docker-buildx" "$plugins/docker-buildx"; then
    rm -rf "$staging"
    exit 1
  fi
  rm -rf "$staging"
  _note_helpers_installed downloaded missing "$why_not" buildx
}

# Creates the website builder's virtual machine on a first start. With the
# app's copy of its starting disk it starts from that file (about half a
# minute, nothing downloaded); without one, or when that start fails for ANY
# reason, it starts the way it always has, which downloads the disk. Colima
# checks the file's SHA-512 itself, so a damaged copy is refused in a second
# and the plain start heals it (measured, GitHub #312).
_create_the_builder() {
  local started="$SECONDS" seed="" how="" log status_file
  if [[ -z "$(_bundle_problem)" && -f "${PLANTOIR_BUNDLED_HELPERS:-}/vm/${VM_IMAGE_NAME}" ]]; then
    seed="${PLANTOIR_BUNDLED_HELPERS}/vm/${VM_IMAGE_NAME}"
  fi
  if [[ -n "$seed" ]]; then
    echo "   This takes about a minute."
    log="$(mktemp "${TMPDIR:-/tmp}/plantoir-first-start.XXXXXX")"
    status_file="${log}.status"
    # Shown as it happens, and kept, so a refusal can be told from a failure.
    {
      if colima start --cpu "$(_colima_cpus)" --memory "$(_colima_memory_gb)" --vm-type vz --disk-image "$seed" 2>&1; then
        echo "0" > "$status_file"
      else
        echo "1" > "$status_file"
      fi
    } | tee "$log"
    if [[ "$(cat "$status_file" 2>/dev/null || true)" == "0" ]]; then
      how="seeded"
    elif grep -qi "checksum mismatch" "$log"; then
      how="seed-refused-then-downloaded"
    else
      how="seed-failed-then-downloaded"
    fi
    rm -f "$log" "$status_file"
  fi
  if [[ "$how" != "seeded" ]]; then
    echo "   About 350 MB is downloaded once; this can take several minutes."
    # vz is macOS's own virtualization — no extra software needed, unlike
    # the qemu default.
    if colima start --cpu "$(_colima_cpus)" --memory "$(_colima_memory_gb)" --vm-type vz; then
      how="${how:-downloaded}"
    else
      # The wait and the restart below say what happens next.
      how=""
    fi
  fi
  if [[ -n "$how" ]]; then
    echo "PLANTOIR_BUILDER_CREATED: ${how} $((SECONDS - started))"
  fi
  return 0
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
    _create_the_builder
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
  if [[ -d "$HOME/.colima/default" ]]; then
    colima start >/dev/null 2>&1 || true
  else
    # Nothing survived a failed first start, so this start creates it: at
    # Plantoir's size, never Colima's default (#312 review L2).
    colima start --cpu "$(_colima_cpus)" --memory "$(_colima_memory_gb)" --vm-type vz >/dev/null 2>&1 || true
  fi
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
# Which website builder this run uses, by the part of its name that changes
# with the recipe — worth having in a problem report. Until #382 this also
# printed the engine's context and the platform it reported, naming the
# machinery to a teacher (rule 1) at the cost of two more engine calls.
echo "🧰 Website builder version: ${IMAGE##*:}"
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
    echo "❌ Image '$IMAGE' is not on this machine."  # never shown to a teacher: reached only with --image, which the app never passes
    echo "   Build it first, e.g.: docker buildx build --load -t $IMAGE ."  # never shown to a teacher: reached only with --image, which the app never passes
    exit 1
  fi
  # The size is said only when there is no earlier website builder on this
  # Mac: a rebuild after an update reuses most of what the first one fetched
  # (GitHub #312, measured at about 390 MB and 1.5 to 2.5 minutes here).
  if [[ -z "$(docker images -q --filter 'reference=teaching-quartz:*' 2>/dev/null || true)" ]]; then
    echo "🧱 Building your website builder — the first time downloads about 400 MB and takes a few minutes…"
  else
    echo "🧱 Building your website builder — the first time takes a few minutes…"
  fi
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
# The builder is ready: the next launcher may go (GETTING-READY TURN BLOCK).
give_back_the_ready_turn



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
#   - listening on this Mac, in ANY account — the kernel's own list
#     (`netstat -an -p tcp`, every owner: 0.01 s) joined to this account's
#     (`lsof`, 0.06-0.12 s), each read once for all 320 ports rather than
#     per port (0.123 s PER PORT for the old probe: 9.8 s for forty blocks).
#     Until #310 it was `lsof` alone, which run as the teacher lists only the
#     teacher's own programs: a second account on the same Mac was handed
#     8081 while the first account's preview held it, its forward quietly
#     failed to bind, and its Preview opened the other person's site
#     (measured in the #204 rehearsal). Root's listeners (`kdc` on 88,
#     screen sharing on 5900) are invisible to `lsof` for the same reason.
#     Docker cannot see a program on the Mac holding a port and publishes
#     over it anyway (measured: exit 0, and under Colima `docker port` still
#     claims the port), so this is the only guard against another app. Only
#     LISTEN rows count: a port in TIME_WAIT, a preview closed a minute ago,
#     is free. Each listing fails open on its own, so a `netstat` whose
#     columns change in some future macOS falls back to exactly the old
#     `lsof` answer rather than to "nothing listening".
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

# Every TCP port something in ANY account on this Mac is listening on, one
# line per listening socket, from the kernel's own list. netstat writes the
# local address as `*.8081`, `127.0.0.1.8443`, `::1.8443` (a long IPv6
# address is cut short, but its port is kept: measured), so the port is what
# follows the LAST dot. Only LISTEN rows: TIME_WAIT and ESTABLISHED are not
# a listener. Prints nothing, and still succeeds, when netstat is missing or
# fails.
ports_listening_in_every_account() {
  { netstat -an -p tcp 2>/dev/null || true; } \
    | awk '$NF == "LISTEN" { n = split($4, part, "."); if (part[n] ~ /^[0-9]+$/) print part[n] }'
}

# Every TCP port a program of THIS account is listening on, one line per
# listening socket (per program holding it). lsof writes `n*:8081`,
# `n127.0.0.1:8443` and `n[::1]:8443`; the port is what follows the LAST
# colon, whichever of the three it is. Prints nothing, and still succeeds,
# when lsof is missing or fails.
ports_listening_in_this_account() {
  { lsof -nP -iTCP -sTCP:LISTEN -Fn 2>/dev/null || true; } \
    | sed -n 's/^n.*:\([0-9][0-9]*\)$/\1/p'
}

# Every TCP port something on this Mac is listening on: both lists, so that
# either one failing leaves the other's answer (GitHub #310).
listening_ports_on_this_mac() {
  ports_listening_in_every_account
  ports_listening_in_this_account
}

# ---- Whose address is it? (GitHub #310) ---------------------------------
# Under Colima, a workspace's published port is forwarded by THIS account's
# own `ssh` (measured: `ssh … russellgordon *:<port>`, and limactl's own
# listeners beside it). When another account already holds the port, the
# forward fails to bind and NOTHING a launcher reads says so: `docker run`
# and `docker start` exit 0 and `docker port` names the port anyway
# (measured, with root's screen sharing on 5900 standing in for another
# account: XNU refuses a port shared across uids). So two checks look for
# it themselves — before a stopped workspace is started, and before
# preview.sh announces an address — and both are switched on only for the
# engine whose forwarder was measured. Under Docker Desktop a start onto a
# held port is already REFUSED ("Ports are not available", which
# start_the_existing_workspace handles), and an engine nobody measured
# must not pay a two-minute rebuild on a guess.
#
# DOCKER_HOST switches the checks off unless it points into ~/.colima/ (or
# into $COLIMA_HOME, where a developer keeps Colima somewhere else):
# with it set, `docker context show` says "default" whatever the engine is,
# so the only honest reading of an unfamiliar DOCKER_HOST is "not the engine
# that was measured". The app never sets it; a developer who does gets a
# line saying the check was not made (see preview.sh), rather than a check
# that silently stopped happening.
the_docker_host_is_colimas() {
  case "${DOCKER_HOST:-}" in
    */.colima/*) return 0 ;;
  esac
  # A Colima kept somewhere else (COLIMA_HOME) keeps its sockets there.
  if [ -n "${COLIMA_HOME:-}" ]; then
    case "$DOCKER_HOST" in
      *"${COLIMA_HOME%/}/"*) return 0 ;;
    esac
  fi
  return 1
}

the_engine_forwards_from_this_account() {
  local context
  if [ -n "${DOCKER_HOST:-}" ]; then
    the_docker_host_is_colimas
    return
  fi
  context="$(docker context show 2>/dev/null)" || return 1
  case "$context" in
    colima|colima-*) return 0 ;;
  esac
  return 1
}

# Whether DOCKER_HOST names an engine other than Colima, so the checks
# above are off for that reason and not because the engine is Docker
# Desktop.
a_different_engine_was_named_by_hand() {
  if [ -z "${DOCKER_HOST:-}" ] || the_docker_host_is_colimas; then
    return 1
  fi
  return 0
}

# The line the app reads onto the activity trail: contracts/shared-rules.json
# -> activityTrail.mustRecord."preview address held by another account" ->
# marker. Machinery, so the console a teacher reads leaves it out; the app
# writes the trail line from it, as it does for PLANTOIR_WORKSPACE_IN_USE.
# "<before-start|remade|refused|unchecked> <port> <where this run was for>".
tell_the_app_the_address_was_held() {
  echo "PLANTOIR_PREVIEW_ADDRESS_HELD: $1 $2 ${WORKSPACE_TRAIL_PLACE:-setup}"
}

# What the console says when this folder's workspace is made again on free
# addresses because something else has its own: a Docker refusal at start,
# a listener on a stopped workspace's port, or (preview.sh) a forward that
# did not bind. Pinned in contracts/app-rules.json -> previewPorts
# .hostBlockClash.saysWhenAStoppedWorkspaceIsRemade.
say_this_folder_is_set_up_again_on_free_addresses() {
  echo "♻️  Something else is now using this folder's preview addresses, so Plantoir is setting this folder up again on free ones."
  echo "   The next preview will be slower than usual — about two minutes — while it gets ready."
}

# The first of this folder's own published ports that something on this Mac
# is listening on, printed; fails when there is none. Asked only of a STOPPED
# workspace, which listens on nothing itself: under Colima its forward is
# gone 0.011 s after the stop returns and back 0.011 s after a start (5 of 5
# each way, measured), so a listener on one of its ports is somebody else's.
a_port_of_this_stopped_workspace_that_is_taken() {
  local own busy port
  own="$(docker inspect -f '{{range $p, $b := .HostConfig.PortBindings}}{{range $b}}{{.HostPort}} {{end}}{{end}}' "$CONTAINER_NAME" 2>/dev/null)" || return 1
  busy=" $(listening_ports_on_this_mac | tr '\n' ' ') "
  for port in $own; do
    case "$port" in
      ""|*[!0-9]*) continue ;;
    esac
    case "$busy" in
      *" $port "*)
        echo "$port"
        return 0 ;;
    esac
  done
  return 1
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

# Whether Docker refused because a workspace by this name already exists —
# made a moment ago by another launcher remaking the same folder's
# workspace. Docker's words: 'Conflict. The container name "/…" is already
# in use by container "…"'.
it_was_a_name_conflict() {
  case "$1" in
    *"is already in use by container"*) return 0 ;;
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
  local next output running named_already=false
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
    # Another launcher made this folder's workspace a moment ago, under the
    # same name (two runs remaking it together). Given two seconds, it is
    # used as it is if it is running; otherwise the making is tried once
    # more, and a second refusal stops the run with the sentence.
    if it_was_a_name_conflict "$output"; then
      if [ "$named_already" = true ]; then
        printf '%s\n' "$output"
        echo "❌ Plantoir could not start the website builder for this folder. Try again, or restart this Mac if it happens again."
        exit 1
      fi
      named_already=true
      sleep 2
      running="$(docker ps --format '{{.Names}}' 2>/dev/null)" || running=""
      case $'\n'"$running"$'\n' in
        *$'\n'"$CONTAINER_NAME"$'\n'*) return 0 ;;
      esac
      base="$next"
      continue
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
#
# Before the start, a run that will SERVE a preview (WORKSPACE_WILL_SERVE,
# set by preview.sh alone) under Colima looks at the workspace's own ports
# first (GitHub #310): Colima does NOT refuse a start onto a port another
# account holds — it exits 0 and the forward silently fails — so a listener
# on one of them means the same remake, done before the start rather than
# after a refusal that never comes. setup.sh and deploy.sh never serve, so
# a squatted forward costs them nothing and they do not pay a two-minute
# remake for it (a publish at six in the morning keeps its warm builder).
# The workspace is asked once more whether it is RUNNING before anything is
# removed: another launcher for this folder may have started it a moment
# ago, and the listener is then its own forward.
start_the_existing_workspace() {
  local output taken
  if [ "${WORKSPACE_WILL_SERVE:-}" = "yes" ] \
    && the_engine_forwards_from_this_account \
    && taken="$(a_port_of_this_stopped_workspace_that_is_taken)"; then
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -Fxq -- "$CONTAINER_NAME"; then
      return 0
    fi
    say_this_folder_is_set_up_again_on_free_addresses
    if docker rm "$CONTAINER_NAME" >/dev/null 2>&1; then
      run_container_with_mount
      # Only now: the trail line says the workspace WAS set up again, so it
      # is never printed for a rebuild that did not happen (a refused
      # remove, or another launcher's workspace used as it is).
      tell_the_app_the_address_was_held before-start "$taken"
      return 0
    fi
    # Refused: another launcher got here first and it is running again. Use it.
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -Fxq -- "$CONTAINER_NAME"; then
      return 0
    fi
    # There was no start, so there are no engine's words to show.
    echo "❌ Plantoir could not start the website builder for this folder. Try again, or restart this Mac if it happens again."
    exit 1
  fi
  if output="$(docker start "$CONTAINER_NAME" 2>&1)"; then
    return 0
  fi
  if ! it_was_a_port_clash "$output"; then
    printf '%s\n' "$output"
    echo "❌ Plantoir could not start the website builder for this folder. Try again, or restart this Mac if it happens again."
    exit 1
  fi
  say_this_folder_is_set_up_again_on_free_addresses
  if docker rm "$CONTAINER_NAME" >/dev/null 2>&1; then
    run_container_with_mount
    return 0
  fi
  # Refused: another launcher got here first and it is running again. Use it.
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -Fxq -- "$CONTAINER_NAME"; then
    return 0
  fi
  printf '%s\n' "$output"
  echo "❌ Plantoir could not start the website builder for this folder. Try again, or restart this Mac if it happens again."
  exit 1
}

# ---- The second copy another spelling of this folder left (GitHub #189) --
# Until #189 a launcher named this folder by the spelling it was HANDED
# (bash's own `pwd -P`), so a folder reached in the wrong case, by the
# firmlink, or with an accented letter in the other Unicode form had a
# second workspace — teaching-quartz-<FOLDER_ID_AS_HANDED> — and a second
# builds folder, builds/<FOLDER_ID_AS_HANDED>, beside the ones the app used.
# Every launcher now names it by the disk's own spelling, so nothing makes
# that copy any more; this clears away what is left of it, the next time
# the folder is used under the spelling that made it.
#
# Only ever the copy for THIS folder under the spelling this run was handed,
# and only what nothing is using:
#   - a workspace that is RUNNING is left exactly as it is, and named on the
#     console: it may be an older launcher's publish in the middle of its
#     work. It stops when this Mac restarts (or Plantoir stops its
#     workspaces), and is cleared away on a later run. Until then it keeps
#     `docker ps` from being empty, so quitting Plantoir leaves the virtual
#     machine running (documentation/09-mac-app.md).
#   - a STOPPED one is removed with a plain `docker rm` — never -f, which is
#     what would kill one another launcher started a moment ago.
#   - the builds folder is removed only when its note of which folder it
#     serves names THIS folder, and no workspace, running or stopped, still
#     mounts it. A builds folder is derived — every file in it is made again
#     by the next build — and the teacher's courses are never touched.
# When Docker cannot be asked, nothing is removed. The console says what
# was cleared away and the trail gets one line (contracts/shared-rules.json
# -> buildOutputLocation.aSecondSpellingIsClearedAway, and activityTrail).
clear_away_this_folders_other_spelling() {
  local old_id="${FOLDER_ID_AS_HANDED:-}"
  local old_name old_builds everything running names mounted recorded workspace_gone builds_gone what
  case "$old_id" in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
    *) return 0 ;;
  esac
  if [ "$old_id" = "$WORKDIR_ID" ]; then
    return 0
  fi
  old_name="teaching-quartz-${old_id}"
  old_builds="${BUILD_ROOT%/*}/${old_id}"
  if ! everything="$(docker ps -a --format '{{.Names}}' 2>/dev/null)" \
    || ! running="$(docker ps --format '{{.Names}}' 2>/dev/null)"; then
    return 0
  fi
  # Matched as whole lines by `case` rather than by `grep -q`, which can end
  # the pipe early and read as "not there" under pipefail.
  workspace_gone=false
  builds_gone=false
  case $'\n'"$everything"$'\n' in
    *$'\n'"$old_name"$'\n'*)
      case $'\n'"$running"$'\n' in
        *$'\n'"$old_name"$'\n'*)
          echo "ℹ️  A second copy of this folder's website builder, made under another spelling of the folder's name, is still running (${old_name})."
          echo "   Plantoir is leaving it as it is, and will clear it away once it has stopped."
          return 0 ;;
      esac
      if ! docker rm "$old_name" >/dev/null 2>&1; then
        return 0
      fi
      workspace_gone=true ;;
  esac
  if [ -f "$old_builds/working-folder.txt" ]; then
    recorded="$(head -n 1 "$old_builds/working-folder.txt" 2>/dev/null || true)"
    # An EMPTY note names no folder: `cd ""` stays where it is, and would
    # read as this one.
    if [ -n "$recorded" ]; then
      recorded="$( (cd "$recorded" 2>/dev/null && /bin/pwd -P) || true)"
    fi
    if [ -n "$recorded" ] && [ "$recorded" = "$(/bin/pwd -P)" ]; then
      # Names are teaching-quartz-<8 hex digits>, so splitting on spaces is
      # safe. A question Docker does not answer counts as "still mounted",
      # so it removes nothing.
      mounted="$old_builds"
      if names="$(docker ps -a --filter 'name=^teaching-quartz-' --format '{{.Names}}' 2>/dev/null)"; then
        names="$(printf '%s' "$names" | tr '\n' ' ')"
        if [ -z "${names// /}" ]; then
          mounted=""
        else
          # shellcheck disable=SC2086
          mounted="$(docker inspect -f '{{range .Mounts}}{{.Source}}{{"\n"}}{{end}}' $names 2>/dev/null)" || mounted="$old_builds"
        fi
      fi
      case $'\n'"$mounted"$'\n' in
        *$'\n'"$old_builds"$'\n'*) ;;
        *)
          rm -rf -- "$old_builds"
          builds_gone=true ;;
      esac
    fi
  fi
  # The sentence names only what was removed.
  if [ "$workspace_gone" = true ] && [ "$builds_gone" = true ]; then
    what="a second copy of this working folder's website builder and built websites"
  elif [ "$workspace_gone" = true ]; then
    what="a second copy of this working folder's website builder"
  elif [ "$builds_gone" = true ]; then
    what="a second copy of this working folder's built websites"
  else
    return 0
  fi
  echo "🧹 Cleared away ${what}, left behind under another spelling of the folder's name. Nothing in your courses was touched."
  note_on_the_trail "${WORKSPACE_TRAIL_PLACE:-setup} · cleared away ${what}, left under another spelling of its name"
}
# ---- Before a workspace is remade: what is running in it (GitHub #94) ---
# A launcher remakes this folder's workspace when it was made for another
# folder, without the builds mount, from an older recipe, without the
# live-reload addresses, or when its courses folder or its connection has
# gone bad. Removing a workspace ends EVERYTHING running inside it — an open
# preview, another section's build, a publish half-way through its upload —
# and until #94 every one of those twenty places (and the three that retired
# the old shared workspace) stopped it without looking. Now each of them
# comes here, and this LOOKS FIRST:
#   - nothing running          -> remade at once, as before;
#   - a build, a publish or a  -> waited for, up to ten minutes (the same
#     course being set up,        horizon a publish set for later waits for a
#     whose OWNER is running      busy course, #156), then refused, naming it;
#   - a preview that is OPEN   -> refused after twenty seconds (a preview
#                                 closed a moment ago may still be ending; one
#                                 that is open does not end on its own), and
#                                 the sentence names which one;
#   - work whose owner has     -> STOPPED with the workspace, at once, and
#     GONE (GitHub #378)          said: on the console, and on the trail
#                                 through PLANTOIR_LEFTOVER_STOPPED.
# The numbers are contracts/app-rules.json -> previewPorts
# .whenTheWorkspaceIsInUse.waiting; the time is COUNTED in looks rather than
# read from a clock, as the app's quit path counts its own.
#
# Why work is stopped when its owner has gone (#378): a program that ran a
# launcher on a terminal — the app, a Terminal window, an assistant session —
# and was closed while something inside the workspace was waiting for an
# answer leaves that something waiting for ever (measured: killing the host
# side of `docker exec -it` leaves an in-container `read` parented to the
# engine's shim, still there minutes later). Waiting for it only ever ended in
# the ten-minute refusal, and every later preview met the same wait, until the
# Mac was restarted. Work that is still DOING something finishes on its own;
# work that waits for an answer never does.
WORKSPACE_LOOK_EVERY_SECONDS=2
WORKSPACE_PREVIEW_SECONDS=20
WORKSPACE_WORK_SECONDS=600

# What the last look found: "nothing", "a preview" or "other work", and for
# a preview which one ("<course> section <n>" and "<course>/<n>").
# WORKSPACE_WAITING_FOR is what a wait is for, as the marker names it —
# "<build|publish|preview|setup|work> <COURSE/S or -> <origin>" — and
# WORKSPACE_LEFTOVERS is every piece of work whose owner has gone, as
# "<kind>:<COURSE>/<S>", "setup" or "other", separated by spaces.
WORKSPACE_IS_RUNNING="nothing"
WORKSPACE_OPEN_PREVIEW=""
WORKSPACE_OPEN_PREVIEW_PLACE=""
WORKSPACE_WAITING_FOR=""
WORKSPACE_LEFTOVERS=""

# Whether each piece of work found inside the workspace has an OWNER still
# running on this Mac, and who that owner was started by.
#
# $1 is the work, one piece per line: "<kind> <course> <section>" (kind
# preview, build, publish, setup or other; "-" where there is no course or
# section). Prints one line per piece: "<owned|gone> <origin> <kind>
# <course> <section>", origin one of claude, codex, assistant, window,
# scheduled, terminal or "-".
#
# The proof is the LIVE process table, read once by the_launchers_running
# (the PROCESS TABLE BLOCK, shared with preview.sh's #381 guard since #388),
# and nothing else: an owner counts only when a running process's OWN
# command line names it. There is no
# remembered process number anywhere in it — no lease file, no pid file, no
# `kill -0` — so a number the system has since handed to another program
# (Mail, or a launcher for another section) can never keep a dead owner
# alive (GitHub #378). The owners:
#   - a preview: preview.sh for that course and section, not --stop and not
#     --build-only (a publish's build never serves). Unchanged from #94.
#   - a build for publishing: preview.sh for that course and section with
#     --build-only, or deploy.sh for it (it runs that build itself).
#   - a publish: deploy.sh for that course and section, whatever its flags.
# A launcher counts here when its line merely NAMES it, not only when it is
# the program (the guard's stricter rule): `bash -x ./deploy.sh C S` is a
# real, running publish whose program word is a flag away, and missing it
# would end that publish. Counting too many costs a wait; counting too few
# ends a publish (#388).
#   - a course being set up: setup.sh.
#   - anything else (a launcher's short check, a stop, something typed by
#     hand): any launcher at all, preview.sh, deploy.sh or setup.sh.
# And two belts behind those, for everything but a preview:
#   - a publish set for later: while launchd runs it, the app's scheduled
#     runner and the script it runs both carry the script's path,
#     ca.russellgordon.Plantoir.deploy.<CODE>.section<N>[.<folder id>].sh,
#     read by the one label rule the_launchers_running holds (the name must
#     end ".sh", so a `tail -f` of its .log owns nothing — #388). That path is on the table from
#     launchd's first instant to its last, including between the build and
#     the upload, so a publish launchd is still running is never ended.
#   - a `docker exec` still aimed at THIS workspace, by its name or its id:
#     whatever started it (an assistant's own command, an older launcher) is
#     still waiting for it. Closing a program ends its `docker exec` too
#     (measured, #378), so this never keeps real leftovers alive.
# Course names match in either case (the launcher upper-cases), sections
# exactly. This run, its ancestors and its descendants never count (a login
# shell wrapping this run carries the same words). A session that is merely
# OPEN — claude, codex, `Plantoir --mcp-stdio` — owns nothing: it owns work
# only through a launcher it is running.
#
# Who started the owner is read from its ancestors in the same table: a
# publish set for later first (the app's scheduled runner has no
# --mcp-stdio, so it must not be read as a window), then an assistant
# serving another app (claude or codex above it, if either is), then the
# Plantoir app itself, then claude or codex running the launcher directly,
# and otherwise "a command in Terminal".
#
# A table that cannot be read counts as every owner RUNNING, with no origin:
# the cost of that is one wait and a refusal, the cost of the other is
# somebody's publish ended. A table that does not list THIS run counts as
# unread too (#378 review N6): `ps` answering 0 with nothing in it would
# otherwise make every piece of work look abandoned. So does ANY other
# failure of the reader — a missing function answers 127, and a caller that
# waited only on 2 would read that as "every owner gone" (#388).
#
# A course code may carry one space ("AP CALC", CourseCodeRule), so the
# course in "$1" is written with "+" for the space (CourseCodeRule refuses
# a "+"; the command-line setup does not — knownLimits), and the_launchers_running compares a launcher's arguments as the text
# that follows the launcher's name — "AP CALC 1 …" begins with "AP CALC 1 " — never word by
# word (#378 review S1: word by word, a live preview of AP CALC read as
# course AP, section CALC, and was stopped as left over).
the_owners_of_the_work() {
  local places records status
  # A course holding ";" (the PLACES separator) or "\" (which awk -v reads
  # as the start of an escape, "\073" being ";") would shift every later
  # place's number onto the wrong piece, and a live preview of ANOTHER
  # course would read as gone. No app can make such a code, but the
  # command-line setup can (knownLimits), so the answer is the safe one:
  # every piece owned, a wait rather than a guess (#388 impl review S1).
  case "$1" in
    *";"*|*"\\"*)
      printf '%s\n' "$1" | awk 'NF == 3 { print "owned - " $0 }'
      return 0 ;;
  esac
  # One place per piece of work, in the same order as the pieces, so a
  # record's place numbers are the pieces' numbers.
  places="$(printf '%s\n' "$1" | awk 'NF == 3 { printf "%s%s %s", (n++ ? ";" : ""), $2, $3 }')"
  status=0
  records="$(the_launchers_running "$places" "${CONTAINER_NAME:-}" "${2:-}")" || status=$?
  # ANY failure — the table unreadable (2), or the reader itself missing or
  # broken — counts as every owner still running: waiting is the safe way
  # to be wrong here, and the other way ends somebody's publish.
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$1" | awk 'NF == 3 { print "owned - " $0 }'
    return 0
  fi
  printf '%s\n' "$1" | awk -v records="$(printf '%s' "$records" | tr '\n' ';')" '
    function has(list, item) { return index("," list ",", "," item ",") > 0 }
    BEGIN {
      owners = 0
      lines = split(records, record, ";")
      for (r = 1; r <= lines; r++) {
        if (split(record[r], field, " ") != 7) continue
        owners++
        O_origin[owners] = field[2]
        O_kind[owners] = field[3]
        O_flags[owners] = field[5]
        O_places[owners] = field[7]
      }
    }
    NF == 3 {
      j++
      kind = $1; section = $3
      found = 0
      for (o = 1; o <= owners && !found; o++) {
        k = O_kind[o]
        here = has(O_places[o], j)
        if (kind == "preview") {
          found = (k == "preview.sh" && here && !has(O_flags[o], "stop") && !has(O_flags[o], "build-only"))
          continue
        }
        if (k == "exec") { found = 1; continue }
        if (k == "scheduled") {
          found = (kind == "other" || here)
          continue
        }
        if (kind == "build") {
          found = (here && ((k == "preview.sh" && has(O_flags[o], "build-only")) || k == "deploy.sh"))
        } else if (kind == "publish") {
          found = (k == "deploy.sh" && here)
        } else if (kind == "setup") {
          found = (k == "setup.sh" && !has(O_flags[o], "builder-tag"))
        } else {
          found = (k == "preview.sh" || k == "deploy.sh" || (k == "setup.sh" && !has(O_flags[o], "builder-tag")))
        }
      }
      if (found) {
        print "owned " O_origin[o - 1] " " kind " " $2 " " section
      } else {
        print "gone - " kind " " $2 " " section
      }
    }'
}

# Looks once at what is running in the workspace $1 (an id or a name) and
# sets WORKSPACE_IS_RUNNING, WORKSPACE_WAITING_FOR and WORKSPACE_LEFTOVERS.
# The rule is contracts/app-rules.json ->
# previewPorts.whenTheWorkspaceIsInUse.whatCountsAsRunning:
#   - not running, or gone: "nothing", and the workspace is not asked what
#     runs in it (a stopped one cannot answer: `docker top` exits 1);
#   - only its own first process (`tail -f /dev/null`): "nothing" — the same
#     count the app's quit path uses before it stops a workspace;
#   - a preview — `build_site.py` without `--build-only`, with everything it
#     started — whose launcher is still running on this Mac: "a preview";
#   - any other work whose owner is running (the_owners_of_the_work): "other
#     work", and WORKSPACE_WAITING_FOR names it;
#   - work whose owner has gone: nothing to wait for — listed in
#     WORKSPACE_LEFTOVERS, and ended with the workspace;
#   - running, but `docker top` did not answer: "other work". An idle
#     workspace costs a wait; a busy one stopped costs a publish.
# An open preview wins over other work: waiting cannot end it.
#
# Each process belongs to the OUTERMOST piece of work above it (#378): a
# deploy rebuilds a site by running build_site.py --build-only as its own
# child, and that build is the deploy's, owned by deploy.sh — read the other
# way round it would be a build whose preview.sh is not running, and a live
# upload would be stopped as left over. A deploy shows as two lines, the
# `sh -lc` wrapper deploy.sh runs and the Python under it; `docker top`
# prints the wrapper's many lines as one (measured), with the course and
# section written into it, so both lines name the same publish.
look_inside_the_workspace() {
  local state first inside found kind course section owner origin work owners first_named first_other
  WORKSPACE_IS_RUNNING="nothing"
  WORKSPACE_OPEN_PREVIEW=""
  WORKSPACE_OPEN_PREVIEW_PLACE=""
  WORKSPACE_WAITING_FOR=""
  WORKSPACE_LEFTOVERS=""
  state="$(docker inspect -f '{{.State.Running}} {{.State.Pid}}' "$1" 2>/dev/null)" || return 0
  case "$state" in
    "true "*) first="${state#true }" ;;
    *) return 0 ;;
  esac
  if ! inside="$(docker top "$1" 2>/dev/null)"; then
    WORKSPACE_IS_RUNNING="other work"
    WORKSPACE_WAITING_FOR="work - -"
    return 0
  fi
  # One line per process after the heading: UID PID PPID C STIME TTY TIME
  # CMD, the command whole (measured: arguments are not cut short). Each
  # process prints the piece of work it belongs to: "<kind> <course>
  # <section>", "orphan <course> <section>" for a website builder serving
  # with no build_site.py above it, or "other - -". The workspace's own first
  # process prints nothing.
  found="$(printf '%s\n' "$inside" | awk -v first="$first" '
    function named(cmd, flag,    at) {
      if (match(cmd, flag "[= ][^ \t]+")) {
        at = substr(cmd, RSTART + length(flag) + 1, RLENGTH - length(flag) - 1)
        return at
      }
      return "-"
    }
    # The course runs to the next " --", not to the first blank: a code may
    # carry one space (#378 review S1). Quotes a shell kept are dropped,
    # and the space is written "+" so the pieces below stay one word each.
    function course_of(cmd,    rest, cut) {
      if (!match(cmd, /--course[= ]/)) return "-"
      rest = substr(cmd, RSTART + RLENGTH)
      cut = index(rest, " --")
      if (cut > 0) rest = substr(rest, 1, cut - 1)
      gsub(/["\047]/, "", rest)
      sub(/[ \t]+$/, "", rest)
      if (rest == "") return "-"
      gsub(/ /, "+", rest)
      return toupper(rest)
    }
    NR == 1 { next }
    NF >= 8 {
      pid = $2; parent[pid] = $3
      cmd = $8
      for (f = 9; f <= NF; f++) cmd = cmd " " $f
      command[pid] = cmd
      order[++count] = pid
    }
    END {
      for (i = 1; i <= count; i++) {
        pid = order[i]
        cmd = command[pid]
        if (cmd ~ /\/opt\/scripts\/deploy\.py/) {
          root[pid] = "publish " course_of(cmd) " " named(cmd, "--section")
        } else if (cmd ~ /\/opt\/scripts\/build_site\.py/) {
          root[pid] = (cmd ~ /--build-only/ ? "build " : "preview ") course_of(cmd) " " named(cmd, "--section")
        } else if (cmd ~ /\/opt\/scripts\/setup_course\.py/) {
          root[pid] = "setup - -"
        } else if (cmd ~ /[ \t]--serve([ \t]|$)/) {
          serving[pid] = 1
          if (match(cmd, /quartz-builds\/[^\/]+\/section[0-9]+/)) {
            where = substr(cmd, RSTART + 14, RLENGTH - 14)
            k = index(where, "/section")
            place = toupper(substr(where, 1, k - 1))
            gsub(/ /, "+", place)
            served_as[pid] = place " " substr(where, k + 8)
          }
        }
      }
      for (i = 1; i <= count; i++) {
        pid = order[i]
        if (pid == first) continue
        q = pid; belongs = ""; served = ""; steps = 0
        while ((q in command) && q != first && steps < 64) {
          if (q in root) belongs = root[q]
          if ((q in serving) && served == "") served = (q in served_as) ? served_as[q] : "- -"
          q = parent[q]; steps++
        }
        if (belongs != "") {
          print belongs
        } else if (served != "") {
          print "orphan " served
        } else {
          print "other - -"
        }
      }
    }' | sort -u)"
  # The work that can have an owner goes to the_owners_of_the_work in one
  # question; a website builder serving with nothing above it has lost its
  # launcher's side entirely (build_site.py waits on it for as long as a
  # preview is open), so it is left over whatever is running.
  work=""
  while IFS=' ' read -r kind course section; do
    case "$kind" in
      "") ;;
      orphan)
        if [ "$course" = "-" ]; then
          workspace_left_over "other"
        else
          workspace_left_over "preview:$course/$section"
        fi ;;
      *) work="${work}${kind} ${course} ${section}"$'\n' ;;
    esac
  done <<LOOKED
$found
LOOKED
  if [ -z "$work" ]; then
    return 0
  fi
  owners="$(the_owners_of_the_work "$work" "$1")"
  first_named=""
  first_other=""
  while IFS=' ' read -r owner origin kind course section; do
    case "$owner" in
      owned)
        case "$kind" in
          preview)
            if [ "$WORKSPACE_IS_RUNNING" != "a preview" ]; then
              WORKSPACE_IS_RUNNING="a preview"
              WORKSPACE_OPEN_PREVIEW="${course//+/ } section $section"
              WORKSPACE_OPEN_PREVIEW_PLACE="$course/$section"
            fi ;;
          other)
            [ -n "$first_other" ] || first_other="work - $origin" ;;
          setup)
            [ -n "$first_named" ] || first_named="setup - $origin" ;;
          *)
            [ -n "$first_named" ] || first_named="$kind $course/$section $origin" ;;
        esac ;;
      gone)
        case "$kind" in
          setup|other) workspace_left_over "$kind" ;;
          *) workspace_left_over "$kind:$course/$section" ;;
        esac ;;
    esac
  done <<OWNERS
$owners
OWNERS
  if [ "$WORKSPACE_IS_RUNNING" = "a preview" ]; then
    WORKSPACE_WAITING_FOR="preview $WORKSPACE_OPEN_PREVIEW_PLACE -"
  elif [ -n "$first_named" ]; then
    WORKSPACE_IS_RUNNING="other work"
    WORKSPACE_WAITING_FOR="$first_named"
  elif [ -n "$first_other" ]; then
    WORKSPACE_IS_RUNNING="other work"
    WORKSPACE_WAITING_FOR="$first_other"
  fi
}

# Adds one piece of work to WORKSPACE_LEFTOVERS, once.
workspace_left_over() {
  case " $WORKSPACE_LEFTOVERS " in
    *" $1 "*) ;;
    *) WORKSPACE_LEFTOVERS="${WORKSPACE_LEFTOVERS:+$WORKSPACE_LEFTOVERS }$1" ;;
  esac
}

# Who started a piece of work, in a teacher's words. Pinned in
# contracts/app-rules.json -> previewPorts.whenTheWorkspaceIsInUse.sentences
# .origins; the app's status line uses the same words.
workspace_origin_in_words() {
  case "$1" in
    claude) echo "Revise with Claude" ;;
    codex) echo "Revise with Codex" ;;
    assistant) echo "an assistant" ;;
    window) echo "another Plantoir window" ;;
    scheduled) echo "a scheduled deploy" ;;
    terminal) echo "a command in Terminal" ;;
    *) echo "Plantoir" ;;
  esac
}

# What a piece of work is doing, in a teacher's words: "$1" is the kind
# (build, publish or setup) and "$2" is "<COURSE>/<S>". Pinned in
# contracts/app-rules.json -> ….sentences.doing.
workspace_doing_in_words() {
  local course="${2%/*}" section="${2#*/}"
  course="${course//+/ }"
  case "$1" in
    build) echo "building $course section $section" ;;
    publish) echo "deploying $course section $section" ;;
    *) echo "setting up a course" ;;
  esac
}

# What a stopped piece of work was, in a teacher's words: "$1" is one item
# of WORKSPACE_LEFTOVERS. Pinned in contracts/app-rules.json -> ….sentences
# .leftovers.
workspace_leftover_in_words() {
  local place="${1#*:}"
  local course="${place%/*}" section="${place#*/}"
  course="${course//+/ }"
  case "$1" in
    build:*) echo "a build of $course section $section" ;;
    publish:*) echo "a deploy of $course section $section" ;;
    preview:*) echo "a preview of $course section $section" ;;
    setup) echo "the setting up of a course" ;;
    *) echo "something else" ;;
  esac
}

# The machine lines the app reads. PLANTOIR_WAITING_FOR: turns the status
# line under the progress bar into the sentence naming what is waited for
# (GitHub #378, decision 3), and "over" gives it back; PLANTOIR_LEFTOVER_
# STOPPED: is the trail line for what was ended (contracts/shared-rules.json
# -> activityTrail.mustRecord."left-over work stopped"). Machinery, so the
# console a teacher reads leaves both out.
tell_the_app_what_is_waited_for() {
  echo "PLANTOIR_WAITING_FOR: $1"
}

tell_the_app_what_was_stopped() {
  local place="${WORKSPACE_TRAIL_PLACE:-setup}"
  echo "PLANTOIR_LEFTOVER_STOPPED: ${place// /+} $1"
}

# The console sentence for what is waited for, said once each time it
# changes. "$1" is WORKSPACE_WAITING_FOR. Pinned in contracts/app-rules.json
# -> previewPorts.whenTheWorkspaceIsInUse.sentences.whileWaitingFor….
say_what_is_waited_for() {
  # Split without `read`: every `read` in a launcher is taken for a question
  # (scripts/test_*_questions.py), and this is not one.
  local kind="${1%% *}" rest="${1#* }"
  local place="${rest%% *}" origin="${rest#* }"
  case "$kind" in
    preview)
      course="${place%/*}"
      echo "⏳ Waiting for the preview of ${course//+/ } section ${place#*/} to close before Plantoir sets this folder up again…" ;;
    work)
      echo "⏳ Waiting for something else Plantoir is doing in this folder to finish before it sets the folder up again…" ;;
    *)
      echo "⏳ Waiting for $(workspace_origin_in_words "$origin") to finish $(workspace_doing_in_words "$kind" "$place") before Plantoir sets this folder up again…" ;;
  esac
  tell_the_app_what_is_waited_for "$1"
}

# The refusal after ten minutes, naming what was still going when it can.
say_the_work_did_not_finish() {
  # Split without `read`: every `read` in a launcher is taken for a question
  # (scripts/test_*_questions.py), and this is not one.
  local kind="${1%% *}" rest="${1#* }"
  local place="${rest%% *}" origin="${rest#* }"
  case "$kind" in
    build|publish|setup)
      echo "❌ After ten minutes, $(workspace_origin_in_words "$origin") was still $(workspace_doing_in_words "$kind" "$place"), so Plantoir stopped rather than interrupt it." ;;
    *)
      echo "❌ Something Plantoir was doing in this folder was still going after ten minutes, so it stopped rather than interrupt it." ;;
  esac
  echo "   Try again once it has finished. Nothing was changed."
}

# What the marker's fourth and fifth words say was waited for: the item
# ("<kind>:<COURSE>/<S>", "setup" or "work") and who started it.
workspace_waited_for_words() {
  # Split without `read`: every `read` in a launcher is taken for a question
  # (scripts/test_*_questions.py), and this is not one.
  local kind="${1%% *}" rest="${1#* }"
  local place="${rest%% *}" origin="${rest#* }"
  case "$kind" in
    "") ;;
    setup|work) echo "$kind $origin" ;;
    *) echo "$kind:$place $origin" ;;
  esac
}

# The console sentence and the trail's marker for work ended because its
# owner had gone. "$1" is WORKSPACE_LEFTOVERS.
say_what_was_left_over_and_is_stopped() {
  local item what="" count=0 total=0
  for item in $1; do
    total=$((total + 1))
  done
  for item in $1; do
    count=$((count + 1))
    if [ "$count" -eq 1 ]; then
      what="$(workspace_leftover_in_words "$item")"
    elif [ "$count" -eq "$total" ]; then
      what="$what and $(workspace_leftover_in_words "$item")"
    else
      what="$what, $(workspace_leftover_in_words "$item")"
    fi
  done
  echo "🧹 Stopped ${what}, left running after the program that started it had closed. Your pages were not touched."
  tell_the_app_what_was_stopped "$1"
}

# The line the app reads onto the activity trail: contracts/shared-rules.json
# -> activityTrail.mustRecord."workspace was in use" -> marker. It is
# machinery, so the console a teacher reads leaves it out; the app writes the
# trail line from it (the same way a build's PLANTOIR_DATED line reaches the
# trail), whether the run was the app's own or a publish launchd ran.
# "<outcome> <seconds> <where this run was for> [<what> [<origin>]]": what
# is the open preview ("<course>/<section>") for a preview, and for a wait or
# a refusal on other work the item waited for and who started it.
tell_the_app_the_workspace_was_in_use() {
  local place="${WORKSPACE_TRAIL_PLACE:-setup}"
  echo "PLANTOIR_WORKSPACE_IN_USE: $1 $2 ${place// /+}${3:+ $3}"
}

# Removes this folder's workspace and makes it again, once nothing whose
# owner is running is at work in it. Every remake goes through here: the
# launchers' own checks say WHY in one line, then call this.
#
# The workspace is stopped and removed by its ID, never by name and never
# with -f. Two launchers started together after an update can both find the
# old workspace idle; by id, the second one's stop and remove land on the old
# workspace (already gone: harmless) rather than on the NEW one the first
# has just made — which is what stopping by name did, and is #94's shape one
# step down. A remove that fails while the old one is still there is tried
# once more, two seconds later, and then the run stops with the sentence.
#
# Work left over by a program that has closed (#378) is ended by this same
# `docker stop "$id"` and nothing else: there is no second way to end work
# in here, so there is nothing that could aim at another folder's workspace.
# The id is read from THIS folder's name, which is a hash of the disk's own
# spelling of the folder (/bin/pwd -P). Only the leftovers counted in the
# look just before the stop are named: anything that started after it — the
# look-then-stop window of tens of milliseconds — is ended unnamed, which is
# #94's own known limit (contracts: whatCountsAsRunning.knownLimits).
remake_the_workspace() {
  local id waited=0 said="" waited_for=""
  id="$(docker inspect -f '{{.Id}}' "$CONTAINER_NAME" 2>/dev/null)" || id=""
  if [ -z "$id" ]; then
    run_container_with_mount
    return 0
  fi
  while true; do
    look_inside_the_workspace "$id"
    case "$WORKSPACE_IS_RUNNING" in
      nothing)
        break ;;
      "a preview")
        if [ "$waited" -ge "$WORKSPACE_PREVIEW_SECONDS" ]; then
          tell_the_app_what_is_waited_for over
          echo "❌ The preview of $WORKSPACE_OPEN_PREVIEW from this folder is still open, and Plantoir needs to set this folder up again before it can go on."
          echo "   Close that preview — in Plantoir, or wherever it was started — then try again. Nothing was changed."
          tell_the_app_the_workspace_was_in_use preview "$waited" "$WORKSPACE_OPEN_PREVIEW_PLACE"
          exit 1
        fi ;;
      *)
        if [ "$waited" -ge "$WORKSPACE_WORK_SECONDS" ]; then
          tell_the_app_what_is_waited_for over
          say_the_work_did_not_finish "$WORKSPACE_WAITING_FOR"
          tell_the_app_the_workspace_was_in_use work "$waited" "$(workspace_waited_for_words "$WORKSPACE_WAITING_FOR")"
          exit 1
        fi ;;
    esac
    if [ "$WORKSPACE_WAITING_FOR" != "$said" ]; then
      say_what_is_waited_for "$WORKSPACE_WAITING_FOR"
      said="$WORKSPACE_WAITING_FOR"
      waited_for="$(workspace_waited_for_words "$WORKSPACE_WAITING_FOR")"
    fi
    sleep "$WORKSPACE_LOOK_EVERY_SECONDS"
    waited=$((waited + WORKSPACE_LOOK_EVERY_SECONDS))
  done
  if [ -n "$said" ]; then
    tell_the_app_what_is_waited_for over
  fi
  if [ "$waited" -gt 0 ]; then
    tell_the_app_the_workspace_was_in_use waited "$waited" "$waited_for"
  fi
  if [ -n "$WORKSPACE_LEFTOVERS" ]; then
    say_what_was_left_over_and_is_stopped "$WORKSPACE_LEFTOVERS"
  fi
  docker stop "$id" >/dev/null 2>&1 || true
  if ! docker rm "$id" >/dev/null 2>&1; then
    if docker inspect -f '{{.Id}}' "$id" >/dev/null 2>&1; then
      sleep 2
      if ! docker rm "$id" >/dev/null 2>&1 \
        && docker inspect -f '{{.Id}}' "$id" >/dev/null 2>&1; then
        echo "❌ Plantoir could not start the website builder for this folder. Try again, or restart this Mac if it happens again."
        exit 1
      fi
    fi
  fi
  run_container_with_mount
}

# The one shared workspace from before working folders each had their own.
# Superseded: it holds no content (everything lives on the host), and left
# running it would shadow the per-folder workspaces' ports. Retired only when
# nothing at all is running in it — the same look as above, without the wait
# and WITHOUT ending leftovers (#378): it is not this folder's workspace, so
# nothing this folder's launcher proves about an owner entitles it to end
# work in there. Otherwise it is left for another day, silently: it holds
# nothing of the teacher's, and the walk above already steps round its
# addresses.
retire_legacy_container() {
  local id
  id="$(docker inspect -f '{{.Id}}' teaching-quartz 2>/dev/null)" || return 0
  [ -n "$id" ] || return 0
  look_inside_the_workspace "$id"
  if [ "$WORKSPACE_IS_RUNNING" != "nothing" ] || [ -n "$WORKSPACE_LEFTOVERS" ]; then
    return 0
  fi
  echo "♻️  Clearing away the website builder that older versions of Plantoir shared between folders…"
  docker stop "$id" >/dev/null 2>&1 || true
  docker rm "$id" >/dev/null 2>&1 || true
}
# <<< PREVIEW PORT BLOCK <<<
# Where the refusal above is filed on the trail: this run's course and section.
WORKSPACE_TRAIL_PLACE="${COURSE}/${SECTION}"
# A preview SERVES, so a stopped workspace whose addresses somebody else has
# taken is remade before it starts (start_the_existing_workspace, #310). A
# build for publishing serves nothing and keeps its warm builder.
WORKSPACE_WILL_SERVE=""
if [[ -z "$BUILD_ONLY" ]]; then
  WORKSPACE_WILL_SERVE="yes"
fi


run_container_with_mount() {
  retire_legacy_container
  echo "🔗 Letting the website builder read and save your courses: $HOST_COURSES"
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

# A container keeps running the version it was created from, so an update
# only takes effect once the container itself is recreated.
DESIRED_IMAGE_ID=$(docker image inspect --format '{{.Id}}' "$IMAGE" 2>/dev/null || echo "")
RUNNING_IMAGE_ID=$(docker inspect -f '{{.Image}}' "$CONTAINER_NAME" 2>/dev/null || echo "")

echo "🚀 Getting this folder's website builder ready…"
clear_away_this_folders_other_spelling
if docker ps -a --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}$"; then
  # Container exists — check its current /teaching/courses mount
  CURRENT_MOUNT_SRC=$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/teaching/courses"}}{{.Source}}{{end}}{{end}}' "$CONTAINER_NAME" 2>/dev/null || echo "")
  if [[ -z "$CURRENT_MOUNT_SRC" ]]; then
    echo "♻️  Plantoir cannot find your courses from this folder's website builder, so it is setting the folder up again…"
    remake_the_workspace
  elif [[ "$CURRENT_MOUNT_SRC" != "$HOST_COURSES" ]]; then
    echo "🔀 This folder's website builder was set up for a folder somewhere else:"
    echo "   • Set up for:  $CURRENT_MOUNT_SRC"
    echo "   • This folder: $HOST_COURSES"
    echo "♻️  Setting it up again for this folder…"
    remake_the_workspace
  elif ! container_has_builds_mount; then
    # Built websites moved out of the working folder, which needs a second
    # mount this container was made without. A mount cannot be added to a
    # container that already exists.
    echo "♻️  Setting this folder up again so built websites can be kept outside your course folder…"
    remake_the_workspace
  elif [[ -n "$DESIRED_IMAGE_ID" && -n "$RUNNING_IMAGE_ID" && "$RUNNING_IMAGE_ID" != "$DESIRED_IMAGE_ID" ]]; then
    echo "♻️  Plantoir has been updated, so it is setting this folder up again to use the update…"
    remake_the_workspace
  elif ! docker inspect -f '{{json .HostConfig.PortBindings}}' "$CONTAINER_NAME" 2>/dev/null | grep -q '9084/tcp'; then
    # An older container publishes only 8081, and published ports cannot
    # be changed after creation — recreating is the only way to add them.
    echo "♻️  Setting this folder up again so several previews can run at once…"
    remake_the_workspace
  else
    # Mounts match; only start if not already running
    if docker ps --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}$"; then
      echo "✅ This folder's website builder is already running."
    else
      echo "▶️  Starting this folder's website builder…"
      start_the_existing_workspace
    fi
  fi
else
  echo "🆕 Setting up a website builder for this folder…"
  run_container_with_mount
fi

# Preflight: nudge if quartz.layout.ts in the container wasn't initialized by setup.sh
echo "🔎 Checking where the sidebar leaves hidden pages out…"
if ! docker exec -i "$CONTAINER_NAME" bash -lc 'test -f /opt/quartz/quartz.layout.ts && grep -q "const omit = new Set" /opt/quartz/quartz.layout.ts'; then
  echo "⚠️  The website builder could not find where it leaves hidden pages out of the sidebar."
  echo "   (Continuing anyway; the build will attempt a safe fallback.)"
fi

# The requested section is checked against the course's section_numbers by
# build_site.py (validate_requested_section), inside the build, which says so
# and builds nothing. This launcher used to carry its own copy of that check,
# but it fed a heredoc to `docker exec` without -i, so the program never
# arrived, the check never ran (2025-08-11 to 2026-09-23) and every preview
# printed a line that was never true. Removed rather than repaired, GitHub #224.

echo "🔧 Building site for $COURSE, section $SECTION..."
echo "📂 Output will be written to: $OUTPUT_PATH"

# With the new build_site.py:
# - default (no flag) = serve once (no double build)
# - --build-only = build static site only
MODE_FLAG="$BUILD_ONLY"

# The container port maps to a host port block chosen for this folder, so
# the address to open is resolved from the container rather than assumed —
# and when it cannot be resolved, this says so and stops (GitHub #235).
#
# It used to fall back to the CONTAINER port and announce that as fact. That
# port is right only for the first working folder on a Mac (8081 -> 8081); the
# development Mac's own folder publishes 8091 -> 8081, so the guess sent the
# app to the wrong address, or to ANOTHER section's preview. The app believes
# this line — it is the only address it will open — so a guess here is a
# wrong answer delivered as the truth.
#
# The question is put a second time before giving up: one empty answer is
# not proof, and on the commonest Mac the old guess happened to be right, so
# refusing on a single miss would stop previews that used to work. That is a
# second asking of the question, not a wait for anything to settle.
#
# A build for publishing (--build-only) opens no preview, so it asks nothing
# and can never be stopped here: a publish runs this first, and must not be
# refused over a question publishing never asks.
say_the_preview_address_is_unknown() {
  echo "❌ Plantoir could not find out where this preview will be, so it stopped"
  echo "   before building it. Nothing has been lost — try the preview again."
}

# Before building, make sure this Mac can reach the address it is about to
# announce (GitHub #234). The fault this catches was met on 2026-09-19
# (#225): a Mac whose builder had stopped handing NEW addresses through to
# the Mac — fixed only by restarting it — built a preview for about two
# minutes, and the app then waited 45 seconds more before saying the Mac could
# not reach it. Here it is found in about ten seconds, before anything is
# built. documentation/03-launcher-scripts.md -> "Before building, preview.sh
# makes sure this Mac can reach the builder" has the measurements and the
# designs rejected.
#
# The question is a CONNECTION to the announced port, not a listing of
# listening ports: `lsof` run as the teacher sees only the teacher's own
# programs, so a forwarder owned by anybody else would read as missing
# (measured: a root-owned listener on :88 is invisible to lsof and answers
# curl). Nothing is served inside yet, so a healthy Mac answers with an empty
# reply (curl exit 52) in about 0.02 s; a Mac with no forward refuses the
# connection (exit 7). ONLY a refusal counts as absent — every other answer,
# including no curl at all, goes ahead exactly as before, and #225's check
# after the build stays the backstop. A listener that is NOT the forwarder
# answers too, so it is not this check's to find: the ownership look below
# (#310) asks whose it is. Do not tighten this to require a real page, since
# nothing is being served yet.
#
# The retry is a bounded, deliberately paced re-asking of the real question,
# not a wait for something to settle: a healthy Mac answers on the first try,
# and the bound exists for the first address after the builder's virtual
# machine starts, which nobody has timed. That start is the first preview of
# most days (quitting Plantoir stops it when nothing else uses it), so a run
# that started it allows three times as long — and a run that needed more than
# one try says so, so the number that bound rests on arrives with the next
# report. The numbers are pinned in contracts/app-rules.json ->
# previewPorts.whenThisMacCannotReachTheBuilder.
PREVIEW_REACH_ATTEMPTS=20
PREVIEW_REACH_ATTEMPTS_WHEN_THIS_RUN_STARTED_THE_BUILDER=60
PREVIEW_REACH_PAUSE_SECONDS=0.5
this_mac_can_reach_the_builder() {
  local port="$1"
  local attempts="$PREVIEW_REACH_ATTEMPTS"
  if [[ -n "${THIS_RUN_STARTED_THE_BUILDER:-}" ]]; then
    attempts="$PREVIEW_REACH_ATTEMPTS_WHEN_THIS_RUN_STARTED_THE_BUILDER"
  fi
  local attempt=1
  local answer
  while [ "$attempt" -le "$attempts" ]; do
    answer=0
    curl -q -s -o /dev/null --noproxy '*' --max-time 1 "http://127.0.0.1:${port}/" || answer=$?
    if [ "$answer" -ne 7 ]; then
      if [ "$attempt" -gt 1 ]; then
        echo "   Reaching your website builder took ${attempt} tries."
      fi
      return 0
    fi
    attempt=$((attempt + 1))
    if [ "$attempt" -le "$attempts" ]; then
      sleep "$PREVIEW_REACH_PAUSE_SECONDS"
    fi
  done
  return 1
}

say_this_mac_cannot_reach_the_builder() {
  echo "❌ This Mac cannot reach your website builder, so Plantoir stopped before building the preview."
  echo "   Nothing is wrong with your pages. Restarting your Mac puts it right."
}

# Whether the address about to be announced is held by ANOTHER account on
# this Mac, or by macOS itself, rather than by this account's own forward
# (GitHub #310). Succeeds only when that is PROVEN; every doubt goes ahead.
#
# Found in the #204 rehearsal: a second account's workspace was handed 8081
# while the first account's preview held it. Its forward failed to bind with
# nothing said anywhere a launcher reads (`docker run` exit 0, `docker port`
# naming the port anyway), the reach check above was answered by the OTHER
# account's forwarder, and the teacher's Preview opened somebody else's site.
#
# The question, from one listing each: does the kernel show MORE listening
# sockets on this port than this account owns? Under Colima the forward is
# this account's own `ssh` (measured), so on a healthy Mac the two counts
# are equal. Counts rather than presence, because a listener in another
# account on `::1` alone sits BESIDE our IPv4 forward (the bind does not
# collide, measured with a same-account stand-in), and `localhost` — the
# address the app opens — tries `::1` first and reaches the other one.
#   - not Colima (the_engine_forwards_from_this_account): not asked;
#   - the kernel's list shows no listener on the port: not proven;
#   - this account's list is EMPTY: `lsof` failed or is missing, since under
#     Colima this account always owns limactl's listeners (measured) — not
#     proven, goes ahead.
held_by_someone_else() {
  local port="$1" everyone own ours
  the_engine_forwards_from_this_account || return 1
  everyone="$(ports_listening_in_every_account | grep -cx -- "$port" || true)"
  if [ "${everyone:-0}" -eq 0 ]; then
    return 1
  fi
  own="$(ports_listening_in_this_account)"
  if [ -z "$own" ]; then
    return 1
  fi
  ours="$(printf '%s\n' "$own" | grep -cx -- "$port" || true)"
  [ "$everyone" -gt "${ours:-0}" ]
}

# The sentence when the address is still somebody else's after this folder's
# workspace was set up again on free ones. Pinned in contracts/app-rules.json
# -> previewPorts.whenAnotherAccountHasTheAddress.sentence.
say_another_account_has_this_preview_s_address() {
  echo "❌ Another account on this Mac — or macOS itself — is using the address this preview needs, so Plantoir stopped before building it."
  echo "   Nothing is wrong with your pages. Press Preview to try again; if it happens again, restarting this Mac puts it right."
}

# The published host port of this preview, asked twice before giving up
# (GitHub #235: one empty answer is not proof).
the_preview_s_host_port() {
  local host_port=""
  host_port=$(docker port "$CONTAINER_NAME" "${PREVIEW_PORT}/tcp" 2>/dev/null | head -1 | sed 's/.*://')
  if [[ -z "$host_port" ]]; then
    host_port=$(docker port "$CONTAINER_NAME" "${PREVIEW_PORT}/tcp" 2>/dev/null | head -1 | sed 's/.*://')
  fi
  printf '%s' "$host_port"
}

# Finds the address, makes sure this Mac reaches it (#234) and that it is
# this account's own (#310), and only then announces it.
#
# The ownership look comes AFTER the reach check, so a refused connection
# (curl exit 7) is still #234's case, and is said as #234 says it. When the
# address is somebody else's the workspace is remade ONCE, through
# remake_the_workspace (so #94's look at what runs in it applies, and an open
# preview of another section refuses with #94's sentence); the walk that
# remakes it reads the kernel's list too, so the new block is free when it
# is picked. If the address is STILL not ours the run stops before building,
# with the sentence above: exit 1 with no address announced, the shape the
# app already treats as a preview that never appeared (#235). A second
# remake is never tried — rebuilding in a loop against a listener that
# moves with us would cost two minutes a turn and fix nothing.
#
# The remade workspace skips the "Checking where the sidebar leaves
# hidden pages out" look above: it only warns, and it was made from the same image
# the look was just run against. Do not "fix" that by looking again.
announce_the_preview_address() {
  if [[ -n "$BUILD_ONLY" ]]; then
    return 0
  fi
  local host_port="" held_port=""
  local looked=0
  while true; do
    host_port="$(the_preview_s_host_port)"
    if [[ -z "$host_port" ]]; then
      say_the_preview_address_is_unknown
      # Rule 5: without this the trail says only that preview.sh failed, and
      # the reason is in a transcript nobody opens. The words are pinned —
      # contracts/shared-rules.json -> activityTrail.mustRecord."preview did not appear".launcherLine
      note_on_the_trail "${COURSE}/${SECTION} · the preview stopped before building — Plantoir could not find out where it would be"
      return 1
    fi
    if ! this_mac_can_reach_the_builder "$host_port"; then
      say_this_mac_cannot_reach_the_builder
      # Rule 5, words pinned in contracts/shared-rules.json ->
      # activityTrail.mustRecord."preview did not appear".launcherLineWhenThisMacCannotReachTheBuilder
      note_on_the_trail "${COURSE}/${SECTION} · the preview stopped before building — this Mac could not reach the website builder"
      return 1
    fi
    looked=$((looked + 1))
    if [ "$looked" -eq 1 ] && a_different_engine_was_named_by_hand; then
      # Rule 5: a check that was not made says so, rather than silently
      # stopping (contracts/shared-rules.json -> activityTrail.mustRecord.
      # "preview address held by another account", outcome unchecked).
      tell_the_app_the_address_was_held unchecked "$host_port"
      break
    fi
    if ! held_by_someone_else "$host_port"; then
      break
    fi
    if [ "$looked" -ge 2 ]; then
      say_another_account_has_this_preview_s_address
      tell_the_app_the_address_was_held refused "$host_port"
      return 1
    fi
    say_this_folder_is_set_up_again_on_free_addresses
    held_port="$host_port"
    remake_the_workspace
    # After the remake RETURNS, so a remake #94 refused (it exits inside,
    # with its own line for the trail) never leaves a claim of a rebuild.
    tell_the_app_the_address_was_held remade "$held_port"
  done
  echo "🌐 Preview will be available at: http://localhost:${host_port}/"
}

announce_the_preview_address || exit 1

# A terminal is what makes the container's prompts and live progress work, so
# ask for one when there IS one. But `docker exec -t` refuses to start at all
# when stdin is not a terminal — from a script or from CI — and it fails here,
# minutes into the build, saying only "the input device is not a TTY".
# (Everything Plantoir itself starts — a window's buttons, its assistant, and
# the MCP server an assistant in another app talks to — runs on a
# pseudo-terminal, ScriptRunner, so it takes the -it branch. That is why a
# question asked inside the container waits for an answer, and why Plantoir's
# windowless callers pass --non-interactive: a question with nobody to answer
# it, left behind when its program closed, is GitHub #378.) Without a terminal, run python unbuffered so
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
