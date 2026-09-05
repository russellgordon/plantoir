#!/usr/bin/env bash
set -euo pipefail

# Ensure we're in the same directory as this script
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
  ${SELF_CMD} <COURSE_CODE> <SECTION_NUMBER> [--target netlify|cloudflare] [--account <ACCOUNT_ID>] [--diagnose] [--team <TEAM_SLUG>] [--reset-token|--logout] [--image REF]

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
  for teachers who upload to their own web host (e.g. over SFTP).
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

# Normalize course code to uppercase
COURSE_CODE="$(printf '%s' "$COURSE_CODE" | tr '[:lower:]' '[:upper:]')"

# Friendly guard: 'Open' course code ended with zero
if [[ "$COURSE_CODE" =~ ^[A-Z]{3}[0-9]0$ ]]; then
  SUGGESTED="${COURSE_CODE%0}O"
  echo ""
  echo " It looks like you entered '${COURSE_CODE}' (ends with zero)."
  echo " Ontario 'Open' level course codes end with the LETTER 'O' (oh)."
  if [[ -f "courses/$SUGGESTED/course_config.json" && ! -f "courses/$COURSE_CODE/course_config.json" ]]; then
    echo " I see setup data for '$SUGGESTED' on disk."
  fi
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
  if grep -q "ws://localhost:" "${PUBLIC_DIR_HOST}/index.html" 2>/dev/null; then
    echo "🔁 This site was built by a preview, which bakes in a live-reload script"
    echo "   that students' browsers would ask about. Rebuilding it for publishing…"
    if ! "${PREVIEW_CMD}" "$COURSE_CODE" "$SECTION_NUM" --build-only; then
      echo "❌ Could not rebuild this site for publishing."
      exit 1
    fi
    # The rebuild writes through the container's bind mount and the host's
    # view of it LAGS — which is why the "built site not found" loop further
    # up exists at all. Without waiting here the publish ran against a
    # directory the host could not see yet and copied NOTHING, reporting
    # "Published: 0 file(s) updated" over an empty folder. Found by running
    # the fix rather than reasoning about it, 2026-09-05.
    #
    # Waits on the real CONDITION rather than a guessed interval: a front page
    # that no longer carries the live-reload client is exactly what "the
    # rebuild is visible here" means. Bounded, so a rebuild that somehow
    # produced nothing still falls through to the guard below instead of
    # hanging.
    for ((_w=0; _w<75; _w++)); do
      if [[ -f "${PUBLIC_DIR_HOST}/index.html" ]] \
         && ! grep -q "ws://localhost:" "${PUBLIC_DIR_HOST}/index.html" 2>/dev/null; then
        break
      fi
      sleep 0.2
    done
    if [[ ! -f "${PUBLIC_DIR_HOST}/index.html" ]]; then
      echo "❌ The rebuilt site has not appeared. Nothing was published."
      exit 1
    fi
  fi

  echo "📦 Publishing ${COURSE_CODE} section ${SECTION_NUM} to a folder…"
  # -a preserves what matters, --delete mirrors removals, and the
  # itemized output is counted so the teacher sees how little moved.
  CHANGED_COUNT="$(rsync -a --delete --itemize-changes "${PUBLIC_DIR_HOST}/" "${TARGET_DIR}/" | grep -c '^[<>ch.]f' || true)"
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
prompt_for_cf_account() {
  cat <<'MSG'

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
    echo "❌ That doesn’t look like an Account ID (it should be 32 letters and digits)."
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
  if [[ -z "$CF_ACCOUNT" ]]; then CF_ACCOUNT="$(get_cf_account_keychain)"; fi
  if [[ -z "$CF_ACCOUNT" ]]; then
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
  ensure_image_present
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
if docker ps -a --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}$"; then
  CURRENT_MOUNT_SRC=$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/teaching/courses"}}{{.Source}}{{end}}{{end}}' "$CONTAINER_NAME" 2>/dev/null || echo "")
  if [[ -z "$CURRENT_MOUNT_SRC" ]]; then
    echo " Existing container has no /teaching/courses mount; recreating with correct mount…"
    if docker ps --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}$"; then docker stop "$CONTAINER_NAME" >/dev/null; fi
    docker rm "$CONTAINER_NAME" >/dev/null || true
    run_container_with_mount
  elif [[ "$CURRENT_MOUNT_SRC" != "$HOST_COURSES" ]]; then
    echo " Detected different working directory:"
    echo " • Existing mount: $CURRENT_MOUNT_SRC"
    echo " • Desired mount: $HOST_COURSES"
    echo "♻️ Recreating container '$CONTAINER_NAME' to point at the new folder…"
    if docker ps --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}$"; then docker stop "$CONTAINER_NAME" >/dev/null; fi
    docker rm "$CONTAINER_NAME" >/dev/null || true
    run_container_with_mount
  else
    if docker ps --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}$"; then
      if ! probe_container_write; then
        echo " 🛑 Mounted 'courses/' is not writable from the container — recreating it…"
        docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
        run_container_with_mount
      elif ! probe_container_network; then
        echo " 🔌 This container's connection has gone stale — recreating it…"
        docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
        run_container_with_mount
      else
        echo "✅ Container $CONTAINER_NAME is already running with correct, writable mount."
      fi
    else
      echo " Starting existing container $CONTAINER_NAME..."
      docker start "$CONTAINER_NAME" >/dev/null
      if ! probe_container_write; then
        echo " 🛑 Mounted 'courses/' is not writable from the container after start — recreating it…"
        docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
        run_container_with_mount
      elif ! probe_container_network; then
        echo " 🔌 This container's connection has gone stale after starting it — recreating it…"
        docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
        run_container_with_mount
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
  -e TEAM_SLUG="${TEAM_SLUG}" \
  -e TARGET="${TARGET}" \
  -e CF_ACCOUNT="${CF_ACCOUNT}" \
  "$CONTAINER_NAME" \
  sh -lc '
    tok=$(cat /tmp/deploy_pat); rm -f /tmp/deploy_pat;
    opts="";
    [ -n "$DIAGNOSE" ]  && opts="$opts $DIAGNOSE";
    [ -n "$TEAM_SLUG" ] && opts="$opts --team $TEAM_SLUG";
    if [ "$TARGET" = "cloudflare" ]; then
      CLOUDFLARE_API_TOKEN="$tok" CLOUDFLARE_ACCOUNT_ID="$CF_ACCOUNT" \
        python3 /opt/scripts/deploy.py --host-os mac --target cloudflare --course '"$COURSE_CODE"' --section '"$SECTION_NUM"' $opts
    else
      NETLIFY_AUTH_TOKEN="$tok" \
        python3 /opt/scripts/deploy.py --host-os mac --course '"$COURSE_CODE"' --section '"$SECTION_NUM"' $opts
    fi
  '