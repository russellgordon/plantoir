#!/usr/bin/env bash
set -euo pipefail

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

# ---- The image is built HERE, from this folder's own recipe ----------
# Same rules as setup.sh and preview.sh: the tag is a hash of the recipe's
# contents, built locally when missing. No registry involved.
OVERRIDE_IMAGE="${OVERRIDE_IMAGE:-}"

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

# Defaults so help can expand under `set -u` before OS detection
SELF_CMD="./deploy.sh"
PREVIEW_CMD="./preview.sh"

usage() {
  cat <<USAGE
🧰 Usage:
  ${SELF_CMD} <COURSE_CODE> <SECTION_NUMBER> [--target netlify|cloudflare] [--account <ACCOUNT_ID>] [--diagnose] [--team <TEAM_SLUG>] [--reset-token|--logout] [--image REF] [--non-interactive]

Examples:
  ${SELF_CMD} ICS3U 1
  ${SELF_CMD} ICS3U 1 --diagnose
  ${SELF_CMD} ICS3U 1 --team my-org-slug
  ${SELF_CMD} ICS3U 1 --target cloudflare

Notes:
- Deploys from /teaching/courses/<COURSE>/.merged_output/section<SECTION> inside the container.
- You must build first (the static site goes to 'public/' in that section folder).
- --target chooses where the built site goes: netlify (the default) or cloudflare.
- With --to-folder <path>, the site is published to <path>/section<N> on THIS
  computer instead of Netlify — an incremental copy (only changed files move),
  for teachers who upload to their own web host (e.g. over SFTP). A relative
  <path> is taken from this working folder.
- The Netlify Personal Access Token (PAT) is stored in the macOS Keychain and injected securely at runtime.
  Netlify and Cloudflare tokens live under separate Keychain entries, so keeping both is fine.
- A Cloudflare token needs one permission: Account - Cloudflare Pages - Edit.
  The account is discovered from the token when it can be; --account supplies it
  when it cannot (a token scoped only to Pages cannot list its own account).
- Use --reset-token (or --logout) to remove the saved PAT and re-link on next run;
  combine it with --target cloudflare to clear the Cloudflare one instead.
- --image REF publishes using a particular already-built image; normally the
  image is built locally from this folder's recipe when missing.
- If your course code ends with '0' (zero), you'll be prompted to correct it to 'O' for Open-level courses.
USAGE
}

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
_DEPLOY_HOST_OS="$(_detect_host_os)"
if [[ "$_DEPLOY_HOST_OS" == "windows" ]]; then
  SELF_CMD=".\\deploy.bat"
  PREVIEW_CMD=".\\preview.bat"
else
  SELF_CMD="./deploy.sh"
  PREVIEW_CMD="./preview.sh"
fi
# ----------------------------------------------------------------------

if [[ $# -lt 2 ]]; then usage; exit 1; fi

COURSE_CODE="$1"; shift
SECTION_NUM="$1"; shift

# A course code may not begin with a dot, and the refusal is here rather than
# in a comment claiming it cannot happen. Plantoir builds a reference course
# under a HIDDEN folder inside courses/ and renames it into place as the last
# act; handed that hidden name, this script used to treat it as an ordinary
# course — the uppercased name still resolves on a case-insensitive volume —
# and during the copy there is no marker yet to refuse it. The app can never
# pass such a name, but a person or another program can type one.
if [[ "$COURSE_CODE" == .* ]]; then
  echo ""
  echo "❌ A course code cannot begin with a dot."
  echo "   Choose one of your courses — the codes in Plantoir's sidebar."
  echo ""
  exit 1
fi

# Normalize course code to uppercase
COURSE_CODE="$(printf '%s' "$COURSE_CODE" | tr '[:lower:]' '[:upper:]')"

# --non-interactive is looked for HERE, before the flag loop below, because the
# first question this script asks — the 'Open' course-code guard — comes before
# that loop. deploy.ps1 needs no such pre-scan: it parses its flags first and
# asks afterwards. The loop below also accepts the flag, so it is not reported
# as an unknown option; this pre-scan only makes it visible early.
NON_INTERACTIVE="false"
for _early_arg in "$@"; do
  if [[ "$_early_arg" == "--non-interactive" ]]; then NON_INTERACTIVE="true"; fi
done

# Called immediately before every question this script asks. Under
# --non-interactive there is nobody to answer it — the publish was set to
# happen on its own, at half six, with the app closed — so it REFUSES and says
# which question it could not ask, rather than waiting for an answer that will
# never come or quietly taking a default.
#
# Exit code 3 means that and nothing else, matching deploy.py's
# NEEDS_AN_ANSWER. Every other exit in this script is 0 or 1.
assert_can_ask() {
  [[ "$NON_INTERACTIVE" == "true" ]] || return 0
  echo ""
  echo "This publish was set to happen on its own, so nobody is here to answer:"
  echo "   $1"
  echo " $2"
  echo " Nothing was published."
  exit 3
}

# Friendly guard: 'Open' course code ended with zero
if [[ "$COURSE_CODE" =~ ^[A-Z]{3}[0-9]0$ ]]; then
  SUGGESTED="${COURSE_CODE%0}O"
  echo ""
  echo " It looks like you entered '${COURSE_CODE}' (ends with zero)."
  echo " Ontario 'Open' level course codes end with the LETTER 'O' (oh)."
  if [[ -f "courses/$SUGGESTED/course_config.json" && ! -f "courses/$COURSE_CODE/course_config.json" ]]; then
    echo " I see setup data for '$SUGGESTED' on disk."
  fi
  assert_can_ask "Fix course code to '$SUGGESTED'? [Y/n]" "Publish this section once from Plantoir, where you can answer it."
  read -rp " Fix course code to '$SUGGESTED'? [Y/n]: " _ans
  _ans="${_ans:-Y}"
  if [[ "$_ans" =~ ^[Yy]$ ]]; then
    COURSE_CODE="$SUGGESTED"
    echo "✅ Using corrected course code: $COURSE_CODE"
  else
    echo "ℹ️ Continuing with: $COURSE_CODE"
  fi
  echo ""
fi

# ---------- A course kept for reference is never deployed ----------
#
# HERE, before the flag loop, and that placement is the whole point: the
# --to-folder branch further down does its work with rsync on the HOST and
# exits 0 before the container is ever started, so `deploy.py`'s own refusal
# never runs on that path. A guard written only in the shared Python would
# leave the folder destination wide open — the same shape as the live-reload
# defect of 2026-09-05, which is why verify.sh greps this file AND deploy.ps1
# for it.
#
# PLAIN SHELL, with no host python3. Everything above this point, and the whole
# folder publish, needs no interpreter on the host, and this product's first-run
# promise is "no Homebrew, no admin rights" — adding one here would make a
# folder publish fail on a Mac with no Command Line Tools.
#
# FAILS CLOSED. A settings file that is there and cannot be read refuses and
# says so. A settings file that is ABSENT is not this check's business: the
# course-folder check further down says that in its own words.
#
# The sentence is a constant so a test can compare it with
# contracts/shared-rules.json -> referenceCourses.refusal.sentence; the
# launcher cannot read the contract here, because this runs before
# BUILD_CONTEXT is resolved and, under --image, it is never resolved at all.
REFERENCE_COURSE_REFUSAL="is kept for reference, so it is never deployed. Deploy the course you are teaching instead."
_course_config="courses/${COURSE_CODE}/course_config.json"
if [[ -f "$_course_config" ]]; then
  if ! _config_text="$(cat "$_course_config" 2>/dev/null)"; then
    echo "❌ Plantoir cannot tell whether $COURSE_CODE is kept for reference —"
    echo "   its settings file could not be read. Nothing was published."
    exit 1
  fi
  # ONE LINE, because `grep` works a line at a time and `[[:space:]]` cannot
  # span a newline. Without the `tr` a config whose key and colon sit on
  # different lines walked straight past this check — while the shared Python
  # called it a reference course — and the folder publish, which never enters
  # the container, went through at exit 0 saying "Published: 1 file(s)
  # updated." Found by review, 2026-09-20. PowerShell's own `-match` uses .NET
  # regex, where `\s` already matches a newline, so flattening here is also
  # what makes the two launchers agree.
  _flat_config="$(printf '%s' "$_config_text" | tr '\n' ' ')"
  # `"kept_for_reference": true`, in any case, unquoted. A real JSON false and
  # a missing key read as an ordinary course; EVERY OTHER spelling — the
  # string "true", the number 1, a key written with \u escapes — is refused
  # just above as "cannot tell", because the app reads a real JSON boolean and
  # nothing else, so it would treat those as ordinary and this is the only
  # place that stops them. The table of inputs all FOUR readers (this
  # launcher, deploy.ps1, the shared Python and the app) must agree on is
  # contracts/shared-rules.json -> referenceCourses.markerAgreement.
  #
  # "Nothing was published." is deliberate, in the launchers only. A site is
  # DEPLOYED and a page is PUBLISHED (Russell, 2026-09-20), and every sentence
  # the APP says follows that — but this is the launchers own long-standing
  # house sentence, said five times in each of them and asserted by two shared
  # Python tests, and one run saying both words for the same act would be
  # worse than one word that is old. A launcher vocabulary sweep is its own
  # piece of work.
  _reference_code="$COURSE_CODE"
  # A marker that is THERE with a value that is neither true nor false — `1`,
  # `"true"`, a key written with \u escapes. Somebody plainly meant it, and
  # the app reads a real JSON boolean and nothing else, so it would treat this
  # course as ordinary and deploy it. Refused as "cannot tell": it publishes
  # nothing and freezes nothing, which is the only direction that is safe
  # both ways. `"[^"]*ept_for_reference"` catches the escaped spellings and
  # cannot match an ordinary key.
  # An object KEY written with a \u escape, whatever the key is. A key escaped
  # ALL the way through is decoded by the app — which freezes and locks the
  # course — while a text reader like this one sees nothing at all, and the
  # folder publish below never enters the container. Measured: it deployed.
  # Every key Plantoir and the shared Python write is plain ASCII, so an
  # escaped key is never ours.
  #
  # KEYS ONLY. `json.dump` escapes non-ASCII in VALUES by default, so a course
  # name with an accent and every emoji setting carry \uXXXX legitimately. The
  # `[{,]` anchor is what tells a key from a value.
  _escaped_key='[{,][[:space:]]*"[^"]*\\u[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][^"]*"[[:space:]]*:'
  if printf '%s' "$_flat_config" | grep -Eq "$_escaped_key" \
     || { printf '%s' "$_flat_config" | grep -Eq '"[^"]*ept_for_reference"' \
       && ! printf '%s' "$_flat_config" | grep -Eq '"[^"]*ept_for_reference"[[:space:]]*:[[:space:]]*[Tt][Rr][Uu][Ee]' \
       && ! printf '%s' "$_flat_config" | grep -Eq '"[^"]*ept_for_reference"[[:space:]]*:[[:space:]]*[Ff][Aa][Ll][Ss][Ee]'; }; then
    echo ""
    echo "❌ Plantoir cannot tell whether ${COURSE_CODE} is kept for reference —"
    echo "   its settings say something other than true or false. Nothing was published."
    echo ""
    exit 1
  fi
  if printf '%s' "$_flat_config" | grep -Eq '"[^"]*ept_for_reference"[[:space:]]*:[[:space:]]*[Tt][Rr][Uu][Ee]'; then
    # The code a TEACHER reads, which for a reference course is deliberately
    # not the folder name. Falls back to the folder when there is none.
    #
    # `|| true` is load-bearing under `set -euo pipefail`: `grep -Eo` exits 1
    # when a config carries the marker and no course_code, `pipefail`
    # propagates it, and the script then died on this very assignment BEFORE
    # saying anything at all — exit 1 with no output. The whole design of "no
    # fourth exit code, matched on OUTPUT" rests on the sentence being
    # printed, so a silent exit here sends a scheduled deploy back to the
    # generic "did not finish" this was written to replace.
    _recorded_code="$(printf '%s' "$_flat_config" \
      | grep -Eo '"course_code"[[:space:]]*:[[:space:]]*"[^"]*"' \
      | head -n 1 | sed -E 's/.*"([^"]*)"[[:space:]]*$/\1/' || true)"
    if [[ -n "$_recorded_code" ]]; then _reference_code="$_recorded_code"; fi
    echo ""
    echo "❌ ${_reference_code} ${REFERENCE_COURSE_REFUSAL}"
    echo ""
    exit 1
  fi
fi

# Parse flags
DIAGNOSE=""
TEAM_SLUG=""
RESET_TOKEN="false"
TO_FOLDER=""
TARGET="netlify"
ACCOUNT_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      if [[ $# -lt 2 ]]; then echo "❌ Missing value for $1"; echo; usage; exit 1; fi
      TARGET="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"; shift ;;
    --target=*)
      TARGET="$(printf '%s' "${1#*=}" | tr '[:upper:]' '[:lower:]')" ;;
    --account)
      if [[ $# -lt 2 ]]; then echo "❌ Missing value for $1"; echo; usage; exit 1; fi
      ACCOUNT_ARG="$2"; shift ;;
    --account=*)
      ACCOUNT_ARG="${1#*=}" ;;
    --to-folder)
      if [[ $# -lt 2 ]]; then echo "❌ Missing value for $1"; echo; usage; exit 1; fi
      TO_FOLDER="$2"; shift ;;
    --to-folder=*)
      TO_FOLDER="${1#*=}" ;;
    --diagnose) DIAGNOSE="--diagnose" ;;
    --non-interactive) NON_INTERACTIVE="true" ;;
    --team|--team-slug)
      if [[ $# -lt 2 ]]; then echo "❌ Missing value for $1"; echo; usage; exit 1; fi
      TEAM_SLUG="$2"; shift ;;
    --team=*|--team-slug=*)
      TEAM_SLUG="${1#*=}" ;;
    --reset-token|--logout)
      RESET_TOKEN="true" ;;
    --image)
      if [[ $# -lt 2 ]]; then echo "❌ Missing value for $1"; echo; usage; exit 1; fi
      OVERRIDE_IMAGE="$2"; shift ;;
    --image=*)
      OVERRIDE_IMAGE="${1#*=}" ;;
    --help|-h)
      usage; exit 0 ;;
    *)
      echo "❌ Unknown option: $1"; echo; usage; exit 1 ;;
  esac
  shift
done

if [[ "$TARGET" != "netlify" && "$TARGET" != "cloudflare" ]]; then
  echo "❌ Unknown deploy target '${TARGET}'. Use netlify or cloudflare."
  echo
  usage
  exit 1
fi

# Resolve IMAGE (same rules as setup.sh and preview.sh)
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

# Settled before the paths below are read: MERGED_DIR_HOST and everything
# under it resolve THROUGH the link, and a course still holding a real
# .merged_output folder has to be moved out before the preflight looks.
link_course_build_output "$COURSE_CODE"

# Host-side paths (bind-mounted into the container at /teaching/courses)
COURSE_DIR_HOST="$(pwd)/courses/${COURSE_CODE}"
MERGED_DIR_HOST="${COURSE_DIR_HOST}/.merged_output"
SECTION_DIR_HOST="${MERGED_DIR_HOST}/section${SECTION_NUM}"
PUBLIC_DIR_HOST="${SECTION_DIR_HOST}/public"

# Detect host timezone offset in ±HHMM format
HOST_TZ_OFFSET="$(date +%z)"
echo "🕒 Host timezone offset: $HOST_TZ_OFFSET"

# Preflight checks
if [[ ! -d "${COURSE_DIR_HOST}" ]]; then
  echo "❌ Course folder not found on host:"
  echo " ${COURSE_DIR_HOST}"
  echo
  echo " Make sure you've run the course setup and/or preview steps."
  echo " Try: ${PREVIEW_CMD} ${COURSE_CODE} ${SECTION_NUM}"
  if [[ -d "$(pwd)/courses" ]]; then
    echo
    echo " Available course folders:"
    ls -1 "$(pwd)/courses" | sed 's/^/ - /'
  fi
  exit 1
fi

if [[ ! -d "${SECTION_DIR_HOST}" ]]; then
  echo "❌ Section directory not found on host:"
  echo " ${SECTION_DIR_HOST}"
  echo
  echo " You likely need to build the merged output first:"
  echo " ${PREVIEW_CMD} ${COURSE_CODE} ${SECTION_NUM}"
  if [[ -d "${MERGED_DIR_HOST}" ]]; then
    EXISTING_SECTIONS=$(ls -1d "${MERGED_DIR_HOST}"/section* 2>/dev/null | xargs -n1 basename || true)
    if [[ -n "${EXISTING_SECTIONS:-}" ]]; then
      echo
      echo " Existing merged sections for ${COURSE_CODE}:"
      echo "${EXISTING_SECTIONS}" | sed 's/^/ - /'
    fi
  fi
  exit 1
fi

_BUILT_FOUND="false"
for ((_i=0; _i<10; _i++)); do
  if [[ -d "${PUBLIC_DIR_HOST}" && -n "$(ls -A "${PUBLIC_DIR_HOST}" 2>/dev/null || true)" ]]; then
    _BUILT_FOUND="true"
    break
  fi
  sleep 0.2
done

if [[ "$_BUILT_FOUND" != "true" ]]; then
  echo "❌ Built site not found at:"
  echo " ${PUBLIC_DIR_HOST}"
  echo
  echo " If you have just built, check this section still has its front page."
  echo " A section without one produces no website, so there is nothing to publish."
  echo
  echo " Build first:"
  echo " ${PREVIEW_CMD} ${COURSE_CODE} ${SECTION_NUM} --build-only"
  exit 1
fi

# -------------------- Publish to a local folder ------------------------
# The built site already sits on the host (the working folder is
# bind-mounted), so publishing to a folder is a host-side incremental
# sync — only changed files move, and files deleted from the site are
# deleted from the folder. Each section lands in its own subfolder so
# sections can never overwrite one another. Netlify is not involved.
if [[ -n "$TO_FOLDER" ]]; then
  # A relative folder is taken from THIS working folder (line 5 already
  # cd'd here), and made a full path before anything reads it. Three
  # things go wrong with a relative one, all measured (GitHub issue #227):
  #   * rsync reads anything with a colon before its first slash as a
  #     REMOTE host: "out 26:27" became host "out 26", and "localhost:site"
  #     opened an ssh connection to this Mac — with a real host name it
  #     would copy the site to another machine. Both printed "Published".
  #   * mkdir reads a name starting with "-" as an option.
  #   * PUBLISHED_FOLDER= must be a path the app can open, and the app's
  #     own current folder is "/", not this one.
  # A full path starts with "/", so none of the three can happen to it.
  case "$TO_FOLDER" in
    /*) ;;
    *) TO_FOLDER="$(pwd)/${TO_FOLDER}" ;;
  esac
  TARGET_DIR="${TO_FOLDER%/}/section${SECTION_NUM}"
  mkdir -p "$TARGET_DIR" || {
    echo "❌ Cannot create the publish folder:"
    echo "   $TARGET_DIR"
    exit 1
  }
  # A PREVIEW build must never reach a published site. Serve mode bakes a
  # live-reload client — new WebSocket('ws://localhost:<port>') — into every
  # page, and on a published site that script makes a student's browser ask
  # permission to "access other apps and services on this device".
  #
  # `deploy.py` already refuses this, but ONLY for Netlify and Cloudflare:
  # this branch publishes host-to-host and never enters the container, so
  # deploy.py never runs and the check was simply absent. The app's own
  # publish path is protected by BuildFreshness ("the built site was made by
  # a PREVIEW" forces a rebuild), which is why publishing to a folder from
  # the APP has always been safe and why this went unnoticed — but from the
  # command line, `./preview.sh CODE N` followed by `./deploy.sh CODE N
  # --to-folder …` shipped the live-reload client. Found 2026-09-05 by
  # publishing straight after a preview and looking at what came out: 230 of
  # 244 files carried it.
  # Detected across the whole HTML tree, not just the front page. Checking
  # only `index.html` was the asymmetry that made the guard incomplete: the
  # WAIT below already scans everything, precisely because a clean front page
  # can sit in front of stale preview pages — and detection reading only the
  # front page meant that exact state never triggered a rebuild at all, and was
  # published. Found by review on 2026-09-05, after the mixture had been
  # written up as real in the documentation without anyone noticing the
  # trigger could not see it.
  if grep -rq --include='*.html' "ws://localhost:" "${PUBLIC_DIR_HOST}" 2>/dev/null; then
    echo "🔁 This site was built by a preview, which bakes in a live-reload script"
    echo "   that students' browsers would ask about. Rebuilding it for publishing…"
    # Forward the flag. Without it this rebuild is a SECOND way a scheduled
    # publish can meet a question nobody is there to answer: preview.sh has its
    # own course-code guard, and preview.sh has no `set -e`, so unattended it
    # would take the [Y/n] default and rebuild a DIFFERENT course — which this
    # script would then publish, successfully, against the wrong one.
    _PREVIEW_EXTRA=()
    if [[ "$NON_INTERACTIVE" == "true" ]]; then _PREVIEW_EXTRA+=(--non-interactive); fi
    # `|| _rc=$?`, and BOTH halves of that are load-bearing under this script's
    # `set -euo pipefail` (line 2). Two wrong shapes were shipped here in turn,
    # so both are written down:
    #
    #   if ! CMD; then _rc=$?          `!` in front of a pipeline makes the
    #                                  status the logical NOT, so `$?` is 0 and
    #                                  the -eq 3 test below could NEVER fire.
    #                                  Measured, bash 5.3.15:
    #                                    if ! f; then echo "$?"; fi   ->  0
    #
    #   CMD                            `set -e` aborts the whole script the
    #   _rc=$?                         instant CMD is non-zero, so `_rc=$?` is
    #                                  never reached and NOTHING is printed.
    #                                  Measured the same day: the guard line
    #                                  never ran and the script exited 3 in
    #                                  silence.
    #
    # An `||` list is exempt from `set -e`, and the right-hand side runs with
    # `$?` still holding the real code. Verified both ways in
    # scripts/test_deploy_non_interactive.py, which RUNS the comparison rather
    # than asserting a shape.
    _rc=0
    "${PREVIEW_CMD}" "$COURSE_CODE" "$SECTION_NUM" --build-only "${_PREVIEW_EXTRA[@]+"${_PREVIEW_EXTRA[@]}"}" || _rc=$?
    if [[ $_rc -ne 0 ]]; then
      if [[ $_rc -eq 3 ]]; then
        echo "❌ Could not rebuild this site for publishing: it needed an answer."
        exit 3
      fi
      echo "❌ Could not rebuild this site for publishing."
      exit 1
    fi
    # Without waiting here the publish ran against a directory that did not
    # yet hold the rebuilt site and copied NOTHING, reporting "Published: 0
    # file(s) updated" over an empty folder.
    #
    # That was FIRST blamed on the container's bind mount lagging, and that was
    # wrong: a rebuild takes about 3 seconds and the tree is clean the moment
    # it returns. The real cause was a preview still serving this section and
    # overwriting the rebuild — now stopped by `--build-only` itself. The wait
    # is kept because it is the honest post-condition either way.
    #
    # Waits on the real CONDITION rather than a guessed interval, and the
    # condition is the WHOLE TREE, not the front page.
    #
    # Checking only index.html was the first attempt and it was wrong in a way
    # that looked right: serve mode bakes the live-reload client into EVERY
    # page, the host mirror is replaced file by file, and the front page can be
    # clean while two hundred other pages are still the preview's. That
    # published a MIXTURE — a correct front page and stale pages behind it —
    # which is worse than publishing the preview wholesale, because the front
    # page looks fine. Caught by verify-deploy.sh on 2026-09-05, which fetches
    # what was published and reads it.
    #
    # HTML only. The live-reload client is only ever in a page, and the
    # SUCCESS condition is "no match anywhere" — which means every file is read
    # to the end. Without the filter that is a full pass over `public/`,
    # including every image the course embeds, over a bind mount, twice per
    # publish. Bounded, so a rebuild that produced nothing falls through to the
    # guard below rather than hanging.
    for ((_w=0; _w<150; _w++)); do
      if [[ -f "${PUBLIC_DIR_HOST}/index.html" ]] \
         && ! grep -rq --include='*.html' "ws://localhost:" "${PUBLIC_DIR_HOST}" 2>/dev/null; then
        break
      fi
      sleep 0.2
    done
    if grep -rq --include='*.html' "ws://localhost:" "${PUBLIC_DIR_HOST}" 2>/dev/null; then
      echo "❌ The rebuilt site still carries the preview's live-reload script."
      echo "   Nothing was published, rather than publishing pages students'"
      echo "   browsers would ask about."
      exit 1
    fi
    if [[ ! -f "${PUBLIC_DIR_HOST}/index.html" ]]; then
      echo "❌ The rebuilt site has not appeared. Nothing was published."
      exit 1
    fi
  fi

  echo "📦 Publishing ${COURSE_CODE} section ${SECTION_NUM} to a folder…"
  # -a preserves what matters, --delete mirrors removals, and the
  # itemized output is counted so the teacher sees how little moved.
  #
  # rsync's OWN exit status decides, not the count. It used to be piped
  # straight into `grep -c … || true`, which threw the status away: a copy
  # that failed outright, or finished only in part (exit 23, 24 — a page
  # that could not be written, or a stale page --delete could not remove),
  # printed "Published" and PUBLISHED_FOLDER= all the same. A partial copy
  # is a FAILURE here on purpose: the page left behind may be one the
  # teacher took down. No PUBLISHED_FOLDER= line follows a failure, so the
  # app offers no folder to open. The sentence below is matched by the
  # app (app-rules.json -> failureExplanations), so keep its first line.
  _rsync_rc=0
  _rsync_said="$(rsync -a --delete --itemize-changes "${PUBLIC_DIR_HOST}/" "${TARGET_DIR}/")" || _rsync_rc=$?
  if [[ $_rsync_rc -ne 0 ]]; then
    echo "❌ Not every page could be copied into the publishing folder, so it is not up to date."
    echo "   Folder: ${TARGET_DIR}"
    echo "   (copy error ${_rsync_rc})"
    exit 1
  fi
  CHANGED_COUNT="$(printf '%s\n' "$_rsync_said" | grep -c '^[<>ch.]f' || true)"
  echo "✅ Published: ${CHANGED_COUNT} file(s) updated."
  echo "   Folder: ${TARGET_DIR}"
  echo "   Upload that folder to your web host however you prefer (e.g. SFTP)."
  # The app reads this line to offer the folder in Finder.
  echo "PUBLISHED_FOLDER=${TARGET_DIR}"
  exit 0
fi

# -------------------- macOS Keychain token handling --------------------
if [[ "$_DEPLOY_HOST_OS" != "mac" ]]; then
  echo "❌ This script targets macOS. On Windows, use: .\\deploy.ps1"
  exit 1
fi

KEYCHAIN_SERVICE="containerized-quartz-netlify"
TOKENS_FILE="courses/.internal/tokens.json"
KEY_FILE="courses/.internal/.key"

get_token_keychain() {
  /usr/bin/security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$USER" -w 2>/dev/null || true
}
set_token_keychain() {
  /usr/bin/security add-generic-password -U -s "$KEYCHAIN_SERVICE" -a "$USER" -w "$1" >/dev/null
}
delete_token_keychain() {
  /usr/bin/security delete-generic-password -s "$KEYCHAIN_SERVICE" -a "$USER" >/dev/null 2>&1 || true
}
validate_token() {
  curl -fsS -H "Authorization: Bearer $1" https://api.netlify.com/api/v1/user >/dev/null
}

# ---- Cloudflare credentials ------------------------------------------
# Cloudflare's token lives under its own Keychain name, so a teacher who
# deploys some courses to Netlify and others to Cloudflare keeps both
# without one clobbering the other. The remembered account ID gets its own
# entry too — a teacher should never be asked for it twice.
CF_KEYCHAIN_SERVICE="containerized-quartz-cloudflare"
CF_ACCOUNT_KEYCHAIN_SERVICE="containerized-quartz-cloudflare-account"

get_cf_token_keychain() {
  /usr/bin/security find-generic-password -s "$CF_KEYCHAIN_SERVICE" -a "$USER" -w 2>/dev/null || true
}
set_cf_token_keychain() {
  /usr/bin/security add-generic-password -U -s "$CF_KEYCHAIN_SERVICE" -a "$USER" -w "$1" >/dev/null
}
delete_cf_token_keychain() {
  /usr/bin/security delete-generic-password -s "$CF_KEYCHAIN_SERVICE" -a "$USER" >/dev/null 2>&1 || true
}
get_cf_account_keychain() {
  /usr/bin/security find-generic-password -s "$CF_ACCOUNT_KEYCHAIN_SERVICE" -a "$USER" -w 2>/dev/null || true
}
set_cf_account_keychain() {
  /usr/bin/security add-generic-password -U -s "$CF_ACCOUNT_KEYCHAIN_SERVICE" -a "$USER" -w "$1" >/dev/null
}
delete_cf_account_keychain() {
  /usr/bin/security delete-generic-password -s "$CF_ACCOUNT_KEYCHAIN_SERVICE" -a "$USER" >/dev/null 2>&1 || true
}

# Does Cloudflare still recognise this token at all? Kept separate from the
# account lookup below, because the two can disagree: a token can be
# perfectly valid and still list no accounts.
validate_cf_token() {
  [[ -n "${1:-}" ]] || return 1
  curl -fsS --max-time 20 -H "Authorization: Bearer $1" \
    https://api.cloudflare.com/client/v4/user/tokens/verify 2>/dev/null \
    | grep -q '"success":[[:space:]]*true'
}

# Best-effort account lookup, so that in the common case a teacher pastes a
# token and nothing else — the account ID is a 32-character hex string buried
# in the dashboard, and asking for it loses people.
#
# This is deliberately NOT treated as proof of validity. Tested against a real
# token: /accounts can answer success with an EMPTY list, because listing
# accounts is its own permission and a token scoped only to Pages need not
# carry it. Prints nothing to mean "ask", never "bad token".
discover_cf_account() {
  [[ -n "${1:-}" ]] || return 0
  curl -fsS --max-time 20 -H "Authorization: Bearer $1" \
    https://api.cloudflare.com/client/v4/accounts 2>/dev/null \
    | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if data.get("success"):
    accounts = data.get("result") or []
    if accounts:
        print(accounts[0].get("id", ""), end="")
' || true
}

# Only reached when the token cannot name its own account and nothing was
# remembered. The app collects this in its own window instead, and passes
# it as --account, because a GUI deploy has no console to answer on.
#
# EVERYTHING THIS FUNCTION SAYS TO THE TEACHER GOES TO STDERR, and that is
# not tidiness. It is called as `CF_ACCOUNT="$(prompt_for_cf_account)"`, and
# a command substitution is a subshell that captures stdout — so its stdout
# is its RETURN VALUE and nothing else may go there. Measured 2026-09-09 by
# driving the real script through a pseudo-terminal (issue #129): with these
# on stdout the six-step "where to find your Account ID" block never
# appeared, and a teacher who mistyped the ID saw NOTHING AT ALL before the
# script exited 1 — they were asked to paste a code with no hint where it
# lives, and told nothing when it was wrong. Worse, on the SUCCESS path the
# caller got the instructions AND the id — 519 characters (521 bytes) where
# 32 were meant —
# which was then saved to the Keychain and handed to wrangler. Same trap as
# the refusal that issue #92 moved out to the call site; these two were left
# behind because nobody had run the script this far. `read -rp` already
# writes its prompt to stderr, so this puts the instructions where their own
# question is.
#
# deploy.ps1 never had this, and reaches the same place a different way:
# Read-CloudflareAccountId says both of these INSIDE the function too, but
# pipes them to `Out-Host` / `Write-Host`, which bypass the success stream
# that `$CF_ACCOUNT = Read-CloudflareAccountId` captures. PowerShell's host
# stream is doing exactly the job stderr does here, so after this fix the two
# launchers solve it the same way rather than differently.
prompt_for_cf_account() {
  cat >&2 <<'MSG'

One more thing from Cloudflare.

The token you just made is allowed to publish, but not to look up which
Cloudflare account it belongs to — so the account's ID is needed as well.
This is the only time you will be asked for it.

  1. Open this page:  https://dash.cloudflare.com
  2. Choose "Workers & Pages" from the list on the left.
  3. Find "Account ID" on the right-hand side, and copy it.
     (It is also the long code in the address bar, just after
     dash.cloudflare.com/.)

MSG
  read -rp "Paste Cloudflare Account ID: " entered
  entered="$(printf '%s' "$entered" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
  if [[ ! "$entered" =~ ^[0-9a-f]{32}$ ]]; then
    echo "❌ That doesn’t look like an Account ID (it should be 32 letters and digits)." >&2
    return 1
  fi
  printf '%s' "$entered"
}

# ---- Legacy token readers/migration helpers --------------------------

# Try to decode the XOR+base64 obfuscated token using the per-user key file
read_legacy_token_xor() {
  [[ -f "$TOKENS_FILE" && -f "$KEY_FILE" ]] || return 1
  python3 - "$TOKENS_FILE" "$KEY_FILE" <<'PY'
import sys, json, base64, pathlib
tokens_path = pathlib.Path(sys.argv[1])
key_path    = pathlib.Path(sys.argv[2])
try:
    data = json.loads(tokens_path.read_text(encoding="utf-8"))
    entry = (data.get("tokens") or {}).get("netlify") or {}
    obf = entry.get("obf")
    if not obf:
        sys.exit(2)
    key = key_path.read_bytes()
    raw = base64.b64decode(obf)
    plain = bytes(b ^ key[i % len(key)] for i, b in enumerate(raw)).decode("utf-8")
    print(plain, end="")
except Exception:
    sys.exit(1)
PY
}

# Simple/older formats: pick any value under a key that mentions netlify/token
read_legacy_token_plain() {
  [[ -f "$TOKENS_FILE" ]] || return 1
  local line
  line="$(grep -Eoi '"[^"]*netlify[^"]*"[[:space:]]*:[[:space:]]*"[^"]+"' "$TOKENS_FILE" | head -n1 || true)"
  if [[ -z "$line" ]]; then
    line="$(grep -Eo '"(NETLIFY_AUTH_TOKEN|netlify_token|token)"[[:space:]]*:[[:space:]]*"[^"]+"' "$TOKENS_FILE" | head -n1 || true)"
  fi
  [[ -n "$line" ]] || return 1
  echo "$line" | sed -E 's/.*:[[:space:]]*"([^"]*)".*/\1/'
}

# After migrating, remove just the 'netlify' entry from tokens.json (delete file if empty)
prune_legacy_netlify_entry() {
  [[ -f "$TOKENS_FILE" ]] || return 0
  python3 - "$TOKENS_FILE" <<'PY'
import sys, json, pathlib
p = pathlib.Path(sys.argv[1])
try:
    data = json.loads(p.read_text(encoding="utf-8"))
    tokens = data.get("tokens") or {}
    if "netlify" in tokens:
        tokens.pop("netlify", None)
        if tokens:
            data["tokens"] = tokens
            p.write_text(json.dumps(data, indent=2), encoding="utf-8")
        else:
            p.unlink()
except Exception:
    pass
PY
}

if [[ "${RESET_TOKEN}" == "true" && "$TARGET" == "cloudflare" ]]; then
  echo "🔒 Clearing saved Cloudflare token from Keychain…"
  delete_cf_token_keychain
  delete_cf_account_keychain
  echo "Done. Next deploy will ask for a new token."
  exit 0
fi

if [[ "${RESET_TOKEN}" == "true" ]]; then
  echo "🔒 Clearing saved Netlify token from Keychain…"
  delete_token_keychain
  if [[ -f "$TOKENS_FILE" ]]; then
    echo "🧹 Removing legacy Netlify entry from: $TOKENS_FILE"
    prune_legacy_netlify_entry
  fi
  echo "Done. Next run will prompt to create/paste a new token."
  exit 0
fi

# -------------------- Cloudflare token and account ---------------------
CF_TOKEN=""
CF_ACCOUNT=""
if [[ "$TARGET" == "cloudflare" ]]; then
  CF_TOKEN="$(get_cf_token_keychain)"
  if [[ -n "$CF_TOKEN" ]] && ! validate_cf_token "$CF_TOKEN"; then
    echo "⚠️ The saved Cloudflare token no longer works, so it has been cleared."
    delete_cf_token_keychain
    delete_cf_account_keychain
    CF_TOKEN=""
  fi
  if [[ -z "$CF_TOKEN" ]]; then
    cat <<'MSG'

Connect to Cloudflare.

Cloudflare hosts this section's website for free, and it needs to know that
the publishing is coming from you. It does that with an API token — a long
code that acts like a password made just for this app. Creating one takes
about two minutes, and you will not be asked again: it is saved securely on
this computer.

  1. Open this page:  https://dash.cloudflare.com/profile/api-tokens
     (Sign in if you are asked to.)
  2. Choose "Create Token", then "Create Custom Token".
  3. Name it something you will recognise later, such as "Class websites".
  4. Give it ONE permission, chosen from the three dropdowns:
     Account  ->  Cloudflare Pages  ->  Edit
  5. Under "Account Resources", choose "Include" and then your own account
     by name. A token that names no account cannot publish anything, and
     what you get back if you skip this does not mention accounts at all.
  6. Under "TTL", set the end date to after the end of your school year —
     next July is a safe choice — or leave it with no end date. An expired
     token stops your publishing working, with nothing to say why.
  7. Choose "Continue to summary", then "Create Token".
  8. Copy the long code Cloudflare shows you — it is only shown once — and
     paste it below. Nothing appears as you paste; that is normal.

MSG
    assert_can_ask "Paste Cloudflare token" "Publish this section once from Plantoir, where you can paste it. It is saved afterwards."
    read -rsp "Paste Cloudflare token: " cf_pasted; echo
    if ! validate_cf_token "$cf_pasted"; then
      echo "❌ Cloudflare did not accept that token."
      echo "   Check that it has the 'Cloudflare Pages - Edit' permission, then try again."
      exit 1
    fi
    set_cf_token_keychain "$cf_pasted"
    CF_TOKEN="$cf_pasted"
    echo "✅ Saved token to macOS Keychain (service: ${CF_KEYCHAIN_SERVICE})."
  fi

  # The app collected it from the teacher, which beats any guess made here;
  # otherwise let the token name its own account, then fall back to what was
  # remembered last time, and only then ask. An empty discovery is never
  # treated as a bad token — it just means the question has to be asked once.
  if [[ -n "$ACCOUNT_ARG" ]]; then
    CF_ACCOUNT="$(printf '%s' "$ACCOUNT_ARG" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
    set_cf_account_keychain "$CF_ACCOUNT"
  fi
  if [[ -z "$CF_ACCOUNT" ]]; then CF_ACCOUNT="$(discover_cf_account "$CF_TOKEN")"; fi
  # What was remembered is CHECKED before it is trusted, and this is a repair
  # rather than a belt-and-braces. Until 2026-09-09 prompt_for_cf_account
  # printed its instructions to stdout while the call site captured stdout, so
  # a teacher who answered correctly had the whole instruction block AND their
  # id — 519 characters (521 bytes) where 32 were meant — written here by
  # set_cf_account_keychain. Fixing the printing does not help them: this line
  # would hand the same blob back on every later run, the question would never
  # be asked again, and wrangler would keep being given nonsense. Two released
  # versions (v1.0.0, v1.1.0) can have done this, so the entry has to be
  # examined rather than assumed good.
  #
  # Anything that is not 32 hex characters is discarded and the entry removed,
  # which drops through to asking the question again — the state the teacher
  # would have been in had the bug never happened. Deliberately silent about
  # the repair: "your saved Account ID was wrong" invites a support question
  # about something already put right, and the next line asks for it anyway.
  if [[ -z "$CF_ACCOUNT" ]]; then
    _remembered="$(get_cf_account_keychain)"
    if [[ "$_remembered" =~ ^[0-9a-f]{32}$ ]]; then
      CF_ACCOUNT="$_remembered"
    elif [[ -n "$_remembered" ]]; then
      delete_cf_account_keychain
    fi
  fi
  if [[ -z "$CF_ACCOUNT" ]]; then
    # GUARDED HERE, not inside prompt_for_cf_account, and that is the whole
    # point. The function's output is CAPTURED — `$( )` is a subshell — so a
    # refusal printed in there goes into $CF_ACCOUNT instead of onto the
    # screen, and its `exit 3` exits the subshell, leaving `|| exit 1` to
    # report an ordinary failure. Nothing printed, wrong exit code, and the
    # launchd wrapper the mac is being asked to build would read it as an
    # ordinary failure and leave no note. Found by review; the other three
    # guards in this file are at the top level and are unaffected.
    assert_can_ask "Paste Cloudflare Account ID" "Add the Account ID in this course's settings in Plantoir, under Deploying."
    CF_ACCOUNT="$(prompt_for_cf_account)" || exit 1
    set_cf_account_keychain "$CF_ACCOUNT"
  fi
fi

# -------------------- Netlify token ------------------------------------
# Left unindented, as in deploy.ps1, so this long-standing block stays
# readable beside its Windows twin.
TOKEN=""
if [[ "$TARGET" == "netlify" ]]; then
TOKEN="$(get_token_keychain || true)"
if [[ -n "$TOKEN" ]] && ! validate_token "$TOKEN"; then
  echo "⚠️ The saved Netlify token no longer works, so it has been cleared."
  delete_token_keychain
  TOKEN=""
fi

# If legacy file exists, try to migrate it (XOR+base64 scheme first)
if [[ -f "$TOKENS_FILE" ]]; then
  migrated="false"

  if [[ -z "$TOKEN" ]]; then
    if decoded="$(read_legacy_token_xor || true)"; then
      if [[ -n "${decoded:-}" ]] && validate_token "$decoded"; then
        set_token_keychain "$decoded"
        TOKEN="$decoded"
        echo "🔐 Migrated Netlify token (obfuscated) into macOS Keychain."
        prune_legacy_netlify_entry
        migrated="true"
      fi
    fi
  fi

  # Fallback: plain legacy heuristics
  if [[ "$migrated" != "true" && -z "$TOKEN" ]]; then
    legacy_plain="$(read_legacy_token_plain || true)"
    if [[ -n "${legacy_plain:-}" ]] && validate_token "$legacy_plain"; then
      set_token_keychain "$legacy_plain"
      TOKEN="$legacy_plain"
      echo "🔐 Migrated Netlify token into macOS Keychain."
      prune_legacy_netlify_entry
    elif [[ -z "${legacy_plain:-}" ]]; then
      echo "ℹ️ Legacy tokens file found, but no Netlify token key detected."
    else
      echo "⚠️ Legacy token value found, but it is invalid."
    fi
  fi
fi

# If still no token, prompt user to create one (quote-safe via here-doc)
if [[ -z "$TOKEN" ]]; then
  cat <<'MSG'

Connect to Netlify.

Netlify hosts this section's website for free, and it needs to know that the
publishing is coming from you. It does that with an access token — a long
code that acts like a password made just for this app. Creating one takes
about a minute, and you will not be asked again: it is saved securely on
this computer.

  1. Open this page:
     https://app.netlify.com/user/applications#personal-access-tokens
     (Sign in if you are asked to.)
  2. Choose "New access token".
  3. Describe it as something you will recognise later, such as
     "Class websites".
  4. Change the expiry — it starts at 7 days. A token that expires stops
     your publishing working, with nothing on screen to say why, so set a
     date after the end of your school year: next July is a safe choice.
     Choose "No expiration" instead if it is offered.
  5. Choose "Generate token", then copy the long code Netlify shows you —
     it is only shown once.
  6. Paste it below. Nothing appears as you paste; that is normal.

MSG
  echo ""
  assert_can_ask "Paste Netlify token" "Publish this section once from Plantoir, where you can paste it. It is saved afterwards."
  read -rsp "Paste Netlify token: " pasted; echo
  if ! validate_token "$pasted"; then
    echo "❌ Token invalid (Netlify rejected it). Please try again."
    exit 1
  fi
  set_token_keychain "$pasted"
  TOKEN="$pasted"
  echo "✅ Saved token to macOS Keychain (service: ${KEYCHAIN_SERVICE})."
fi
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

# -------------------- Mount-aware container handling --------------------
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

ensure_image_present() {
  if docker image inspect "$IMAGE" >/dev/null 2>&1; then
    return 0
  fi
  if [[ -z "$BUILD_CONTEXT" ]]; then
    echo "❌ No local image named '$IMAGE'."
    echo "   Build it first, e.g.: docker buildx build --load -t $IMAGE ."
    exit 1
  fi
  echo "🧱 Building your website builder — the first time takes a few minutes…"
  local build_cmd=(docker buildx build --load)
  if ! docker buildx version >/dev/null 2>&1; then
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
        echo "❌ Plantoir could not start this folder's workspace. Try again, or restart this Mac if it happens again."
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
          echo "ℹ️  A second copy of this folder's workspace, made under another spelling of the folder's name, is still running (${old_name})."
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
    what="a second copy of this working folder's workspace and built websites"
  elif [ "$workspace_gone" = true ]; then
    what="a second copy of this working folder's workspace"
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
#   - a build or a publish     -> waited for, up to ten minutes (the same
#                                 horizon a publish set for later waits for a
#                                 busy course, #156), then refused;
#   - a preview that is OPEN   -> refused after twenty seconds (a preview
#                                 closed a moment ago may still be ending; one
#                                 that is open does not end on its own), and
#                                 the sentence names which one.
# The numbers are contracts/app-rules.json -> previewPorts
# .whenTheWorkspaceIsInUse.waiting; the time is COUNTED in looks rather than
# read from a clock, as the app's quit path counts its own.
WORKSPACE_LOOK_EVERY_SECONDS=2
WORKSPACE_PREVIEW_SECONDS=20
WORKSPACE_WORK_SECONDS=600

# What the last look found: "nothing", "a preview" or "other work", and for
# a preview which one ("<course> section <n>" and "<course>/<n>").
WORKSPACE_IS_RUNNING="nothing"
WORKSPACE_OPEN_PREVIEW=""
WORKSPACE_OPEN_PREVIEW_PLACE=""

# Whether a preview.sh for this course and section is running on this Mac,
# other than this run and the programs it started or was started by.
#
# Why the Mac is asked as well as the workspace: a preview whose launcher
# has gone — the app force-quit, a Terminal window closed, an assistant's
# client exiting — leaves its website builder running inside the workspace
# (measured: killing the `docker exec` client left the process in
# `docker top`, parented to the engine's shim). Nothing a teacher can close
# is left open, so counting it as an open preview would refuse every remake
# of that folder for ever. A preview counts as OPEN only while the launcher
# that started it is still running.
#
# Matched on the word after preview.sh and the one after that, the course
# (in either case: the launcher upper-cases it) and the section, because a
# command-line run names the launcher by a relative path. The whole process
# table is read once, and this run's own
# ancestors and descendants are left out (a login shell wrapping this run
# carries the same words). A `--stop` run is not a preview, and neither is
# a `--build-only` one (a publish's build, which never serves). A table that
# cannot be read counts as "running":
# the cost of that is one refused remake, the cost of the other is a killed
# preview.
a_preview_launcher_is_running_for() {
  local table
  table="$(ps -Ao pid=,ppid=,args= 2>/dev/null)" || return 0
  printf '%s\n' "$table" | awk -v self="$$" -v course="$1" -v section="$2" '
    {
      pid = $1; parent[pid] = $2
      line = $0
      sub(/^[ \t]*[0-9]+[ \t]+[0-9]+[ \t]+/, "", line)
      args[pid] = line
      order[++count] = pid
    }
    END {
      mine[self] = 1
      p = self
      while ((p in parent) && parent[p] != p && !(parent[p] in mine) && parent[p] > 1) {
        p = parent[p]; mine[p] = 1
      }
      for (i = 1; i <= count; i++) {
        pid = order[i]
        if (pid in mine) continue
        q = pid; ours = 0; steps = 0
        while ((q in parent) && steps < 64) {
          if (parent[q] == self) { ours = 1; break }
          q = parent[q]; steps++
        }
        if (ours) continue
        if (args[pid] ~ /[ \t]--(stop|build-only)([ \t]|$)/) continue
        n = split(args[pid], word, /[ \t]+/)
        for (w = 1; w + 2 <= n; w++) {
          if (word[w] ~ /(^|\/)preview\.sh$/ && toupper(word[w + 1]) == toupper(course) && word[w + 2] == section) {
            found = 1
          }
        }
      }
      exit(found ? 0 : 1)
    }'
}

# Looks once at what is running in the workspace $1 (an id or a name) and
# sets WORKSPACE_IS_RUNNING. The rule is contracts/app-rules.json ->
# previewPorts.whenTheWorkspaceIsInUse.whatCountsAsRunning:
#   - not running, or gone: "nothing", and the workspace is not asked what
#     runs in it (a stopped one cannot answer: `docker top` exits 1);
#   - only its own first process (`tail -f /dev/null`): "nothing" — the same
#     count the app's quit path uses before it stops a workspace;
#   - a preview — `build_site.py` without `--build-only`, with everything it
#     started — whose launcher is still running on this Mac: "a preview";
#   - anything else: "other work" — a build for publishing, a publish, a
#     course being set up, another launcher's check of the folder. A preview
#     whose launcher has gone, with what it started, counts as nothing.
#   - running, but `docker top` did not answer: "other work". An idle
#     workspace costs a wait; a busy one stopped costs a publish.
# An open preview wins over other work: waiting cannot end it.
look_inside_the_workspace() {
  local state first inside found place course section
  WORKSPACE_IS_RUNNING="nothing"
  WORKSPACE_OPEN_PREVIEW=""
  WORKSPACE_OPEN_PREVIEW_PLACE=""
  state="$(docker inspect -f '{{.State.Running}} {{.State.Pid}}' "$1" 2>/dev/null)" || return 0
  case "$state" in
    "true "*) first="${state#true }" ;;
    *) return 0 ;;
  esac
  if ! inside="$(docker top "$1" 2>/dev/null)"; then
    WORKSPACE_IS_RUNNING="other work"
    return 0
  fi
  # One line per process after the heading: UID PID PPID C STIME TTY TIME
  # CMD, the command whole (measured: arguments are not cut short). Each
  # process that is part of a preview prints "preview <course> <section>";
  # any other prints "other". The workspace's own first process prints
  # nothing.
  found="$(printf '%s\n' "$inside" | awk -v first="$first" '
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
        if (cmd ~ /\/opt\/scripts\/build_site\.py/ && cmd !~ /--build-only/) {
          c = cmd; sub(/.*--course=/, "", c); sub(/[ \t].*/, "", c)
          s = cmd; sub(/.*--section=/, "", s); sub(/[ \t].*/, "", s)
          root[pid] = c " " s
        } else if (cmd ~ /[ \t]--serve([ \t]|$)/) {
          serving[pid] = 1
        }
      }
      for (i = 1; i <= count; i++) {
        pid = order[i]
        if (pid == first) continue
        q = pid; belongs = ""; served = 0; steps = 0
        while ((q in command) && steps < 64) {
          if (q in root) { belongs = root[q]; break }
          if (q in serving) served = 1
          q = parent[q]; steps++
        }
        if (belongs != "") {
          print "preview " belongs
        } else if (served) {
          print "orphan"
        } else {
          print "other"
        }
      }
    }' | sort -u)"
  # A website builder serving with no build_site.py above it (and whatever
  # it started) has lost its launcher's side entirely — build_site.py waits
  # on it for as long as a preview is open — so it is left out like any
  # other orphaned preview.
  while IFS=' ' read -r what course section; do
    case "$what" in
      preview)
        if [ "$WORKSPACE_IS_RUNNING" != "a preview" ] \
          && a_preview_launcher_is_running_for "$course" "$section"; then
          WORKSPACE_IS_RUNNING="a preview"
          WORKSPACE_OPEN_PREVIEW="$course section $section"
          WORKSPACE_OPEN_PREVIEW_PLACE="$course/$section"
        fi ;;
      other)
        if [ "$WORKSPACE_IS_RUNNING" = "nothing" ]; then
          WORKSPACE_IS_RUNNING="other work"
        fi ;;
    esac
  done <<LOOKED
$found
LOOKED
}

# The line the app reads onto the activity trail: contracts/shared-rules.json
# -> activityTrail.mustRecord."workspace was in use" -> marker. It is
# machinery, so the console a teacher reads leaves it out; the app writes the
# trail line from it (the same way a build's PLANTOIR_DATED line reaches the
# trail), whether the run was the app's own or a publish launchd ran.
# "<outcome> <seconds> <where this run was for> [<the open preview>]".
tell_the_app_the_workspace_was_in_use() {
  echo "PLANTOIR_WORKSPACE_IN_USE: $1 $2 ${WORKSPACE_TRAIL_PLACE:-setup}${3:+ $3}"
}

# Removes this folder's workspace and makes it again, once nothing is running
# in it. Every remake goes through here: the launchers' own checks say WHY in
# one line, then call this.
#
# The workspace is stopped and removed by its ID, never by name and never
# with -f. Two launchers started together after an update can both find the
# old workspace idle; by id, the second one's stop and remove land on the old
# workspace (already gone: harmless) rather than on the NEW one the first
# has just made — which is what stopping by name did, and is #94's shape one
# step down. A remove that fails while the old one is still there is tried
# once more, two seconds later, and then the run stops with the sentence.
remake_the_workspace() {
  local id waited=0 said=false
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
          echo "❌ The preview of $WORKSPACE_OPEN_PREVIEW from this folder is still open, and this folder's workspace needs updating before Plantoir can go on."
          echo "   Close that preview — in Plantoir, or wherever it was started — then try again. Nothing was changed."
          tell_the_app_the_workspace_was_in_use preview "$waited" "$WORKSPACE_OPEN_PREVIEW_PLACE"
          exit 1
        fi ;;
      *)
        if [ "$waited" -ge "$WORKSPACE_WORK_SECONDS" ]; then
          echo "❌ Something in this folder was still being built or published after ten minutes, so Plantoir stopped rather than interrupt it."
          echo "   Try again once it has finished. Nothing was changed."
          tell_the_app_the_workspace_was_in_use work "$waited"
          exit 1
        fi ;;
    esac
    if [ "$said" = false ]; then
      echo "⏳ Something in this folder is still running. Plantoir will update this folder's workspace as soon as it has finished…"
      said=true
    fi
    sleep "$WORKSPACE_LOOK_EVERY_SECONDS"
    waited=$((waited + WORKSPACE_LOOK_EVERY_SECONDS))
  done
  if [ "$waited" -gt 0 ]; then
    tell_the_app_the_workspace_was_in_use waited "$waited"
  fi
  docker stop "$id" >/dev/null 2>&1 || true
  if ! docker rm "$id" >/dev/null 2>&1; then
    if docker inspect -f '{{.Id}}' "$id" >/dev/null 2>&1; then
      sleep 2
      if ! docker rm "$id" >/dev/null 2>&1 \
        && docker inspect -f '{{.Id}}' "$id" >/dev/null 2>&1; then
        echo "❌ Plantoir could not start this folder's workspace. Try again, or restart this Mac if it happens again."
        exit 1
      fi
    fi
  fi
  run_container_with_mount
}

# The one shared workspace from before working folders each had their own.
# Superseded: it holds no content (everything lives on the host), and left
# running it would shadow the per-folder workspaces' ports. Retired only when
# nothing is running in it — the same look as above, without the wait — and
# otherwise left for another day, silently: it holds nothing of the
# teacher's, and the walk above already steps round its addresses.
retire_legacy_container() {
  local id
  id="$(docker inspect -f '{{.Id}}' teaching-quartz 2>/dev/null)" || return 0
  [ -n "$id" ] || return 0
  look_inside_the_workspace "$id"
  if [ "$WORKSPACE_IS_RUNNING" != "nothing" ]; then
    return 0
  fi
  echo "♻️  Retiring the old shared workspace container…"
  docker stop "$id" >/dev/null 2>&1 || true
  docker rm "$id" >/dev/null 2>&1 || true
}
# <<< PREVIEW PORT BLOCK <<<
# Where the refusal above is filed on the trail: this run's course and section.
WORKSPACE_TRAIL_PLACE="${COURSE_CODE}/${SECTION_NUM}"


run_container_with_mount() {
  ensure_image_present
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

probe_container_write() {
  docker exec "$CONTAINER_NAME" sh -lc 'mkdir -p /teaching/courses &&
    echo ok >/teaching/courses/.write_probe &&
    rm -f /teaching/courses/.write_probe'
}

# A long-lived container's own network namespace can wedge independently
# of everything else — Colima, the Docker daemon, and every OTHER
# container on the same machine (including a brand-new one built from
# the identical image) can be perfectly healthy while this one specific
# container can no longer resolve DNS at all. Found 2026-08-22: an
# existing working folder's Cloudflare deploy failed with wrangler's own
# "fetch failed" — a genuine connectivity error, not a bug in wrangler or
# in this script — while a brand-new working folder deployed without a
# problem seconds later. A teacher would have seen a bare Python
# traceback and no way to know their internet was never actually the
# problem. Skipped for local_folder, which needs no network at all.
probe_container_network() {
  if [[ "$TARGET" == "local_folder" ]]; then
    return 0
  fi
  local PROBE_HOST="api.cloudflare.com"
  if [[ "$TARGET" == "netlify" ]]; then
    PROBE_HOST="app.netlify.com"
  fi
  docker exec "$CONTAINER_NAME" sh -lc "getent hosts $PROBE_HOST" >/dev/null 2>&1
}

echo " Ensuring container is running with the correct, writable mount..."
clear_away_this_folders_other_spelling
if docker ps -a --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}$"; then
  CURRENT_MOUNT_SRC=$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/teaching/courses"}}{{.Source}}{{end}}{{end}}' "$CONTAINER_NAME" 2>/dev/null || echo "")
  if [[ -z "$CURRENT_MOUNT_SRC" ]]; then
    echo " Existing container has no /teaching/courses mount; recreating with correct mount…"
    remake_the_workspace
  elif [[ "$CURRENT_MOUNT_SRC" != "$HOST_COURSES" ]]; then
    echo " Detected different working directory:"
    echo " • Existing mount: $CURRENT_MOUNT_SRC"
    echo " • Desired mount: $HOST_COURSES"
    echo "♻️ Recreating container '$CONTAINER_NAME' to point at the new folder…"
    remake_the_workspace
  elif ! container_has_builds_mount; then
    # Built websites moved out of the working folder, which needs a second
    # mount this container was made without. A mount cannot be added to a
    # container that already exists.
    echo "♻️  Rebuilding your workspace so built websites can be kept outside your course folder…"
    remake_the_workspace
  else
    if docker ps --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}$"; then
      if ! probe_container_write; then
        echo " 🛑 Mounted 'courses/' is not writable from the container — recreating it…"
        remake_the_workspace
      elif ! probe_container_network; then
        echo " 🔌 This container's connection has gone stale — recreating it…"
        remake_the_workspace
      else
        echo "✅ Container $CONTAINER_NAME is already running with correct, writable mount."
      fi
    else
      echo " Starting existing container $CONTAINER_NAME..."
      start_the_existing_workspace
      if ! probe_container_write; then
        echo " 🛑 Mounted 'courses/' is not writable from the container after start — recreating it…"
        remake_the_workspace
      elif ! probe_container_network; then
        echo " 🔌 This container's connection has gone stale after starting it — recreating it…"
        remake_the_workspace
      fi
    fi
  fi
else
  echo " Creating new container named $CONTAINER_NAME with correct mount…"
  run_container_with_mount
fi

SECTION_DIR_IN_CONTAINER="/teaching/courses/${COURSE_CODE}/.merged_output/section${SECTION_NUM}"
echo "🚀 Deploying ${COURSE_CODE} S${SECTION_NUM} from: ${SECTION_DIR_IN_CONTAINER}"

# --- Securely inject token into container without exposing on host CLI ---
if [[ "$TARGET" == "cloudflare" ]]; then
  printf %s "$CF_TOKEN" | docker exec -i "$CONTAINER_NAME" sh -lc 'umask 077; cat > /tmp/deploy_pat'
else
  printf %s "$TOKEN" | docker exec -i "$CONTAINER_NAME" sh -lc 'umask 077; cat > /tmp/deploy_pat'
fi

# Ask for a terminal only when there is one: `docker exec -t` refuses to start
# without a terminal on stdin, which is how this runs from a script or from
# Plantoir's MCP server. See the same note in preview.sh.
if [[ -t 0 ]]; then _EXEC_TTY="-it"; else _EXEC_TTY="-i"; fi

# Pass options via env to avoid fragile mixed quoting in sh -lc
docker exec $_EXEC_TTY \
  -e HOST_TZ_OFFSET="${HOST_TZ_OFFSET}" \
  -e DIAGNOSE="${DIAGNOSE}" \
  -e NON_INTERACTIVE="${NON_INTERACTIVE}" \
  -e TEAM_SLUG="${TEAM_SLUG}" \
  -e TARGET="${TARGET}" \
  -e CF_ACCOUNT="${CF_ACCOUNT}" \
  "$CONTAINER_NAME" \
  sh -lc '
    tok=$(cat /tmp/deploy_pat); rm -f /tmp/deploy_pat;
    opts="";
    [ -n "$DIAGNOSE" ]  && opts="$opts $DIAGNOSE";
    # PARSING the flag is not enough — it has to reach the Python, which is
    # where the site-name question lives. A launcher that took the flag and
    # never forwarded it would leave a green test suite and an unchanged hang.
    [ "$NON_INTERACTIVE" = "true" ] && opts="$opts --non-interactive";
    [ -n "$TEAM_SLUG" ] && opts="$opts --team $TEAM_SLUG";
    if [ "$TARGET" = "cloudflare" ]; then
      CLOUDFLARE_API_TOKEN="$tok" CLOUDFLARE_ACCOUNT_ID="$CF_ACCOUNT" \
        python3 /opt/scripts/deploy.py --host-os mac --target cloudflare --course '"$COURSE_CODE"' --section '"$SECTION_NUM"' $opts
    else
      NETLIFY_AUTH_TOKEN="$tok" \
        python3 /opt/scripts/deploy.py --host-os mac --course '"$COURSE_CODE"' --section '"$SECTION_NUM"' $opts
    fi
  '