#!/usr/bin/env python3
import argparse
import base64
import datetime as dt
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request
import urllib.error
import urllib.parse
import hashlib
import unicodedata
from zoneinfo import ZoneInfo
from pathlib import Path
from collections import Counter

# ---- Host OS signaling & example command helper -----------------------------
_HOST_OS = "unknown"

def _is_windows(host_os: str) -> bool:
    return (host_os or "").lower() == "windows"

def _cmd_example(script_base: str, course, section, host_os: str) -> str:
    return (f".\\{script_base}.bat {course} {section}") if _is_windows(host_os) else (f"./{script_base}.sh {course} {section}")
# ----------------------------------------------------------------------------

# ---------- Rate-limit helpers (NEW) ----------
def _parse_http_date(s: str) -> dt.datetime | None:
    """Parse an RFC1123 HTTP-date string to a timezone-aware UTC datetime."""
    try:
        # Example: 'Wed, 21 Oct 2015 07:28:00 GMT'
        return dt.datetime.strptime(s, "%a, %d %b %Y %H:%M:%S GMT").replace(tzinfo=dt.timezone.utc)
    except Exception:
        return None

def _format_rate_limit_guidance(headers) -> str:
    """
    Build minimal guidance from rate-limit headers for user-facing output.
    Shows only:
      - the current local time, and
      - "Window resets at ..." (derived from X-RateLimit-Reset)
    Omits Retry-After and limit/remaining to avoid confusing or vendor-specific values.
    """
    try:
        greset = headers.get("X-RateLimit-Reset")

        # Determine local timezone from script context; fallback to UTC.
        try:
            local_tz = TZ  # set by parse_host_tz()
        except NameError:
            try:
                local_tz = parse_host_tz()
            except Exception:
                import datetime as _dt
                local_tz = _dt.timezone.utc

        import datetime as _dt
        now_local = _dt.datetime.now(_dt.timezone.utc).astimezone(local_tz)
        lines = [f"Now: {now_local.strftime('%Y-%m-%d %H:%M:%S %Z')}"]

        # Parse X-RateLimit-Reset: epoch seconds or HTTP-date
        reset_dt = None
        if greset:
            try:
                reset_dt = _dt.datetime.fromtimestamp(int(greset), tz=_dt.timezone.utc)
            except Exception:
                reset_dt = _parse_http_date(greset)

        if reset_dt is not None:
            reset_dt_local = reset_dt.astimezone(local_tz)
            secs = max(0, int((reset_dt - _dt.datetime.now(_dt.timezone.utc)).total_seconds()))
            lines.append(f"Window resets at: {reset_dt_local.strftime('%Y-%m-%d %H:%M:%S %Z')} (in ~{secs}s).")

        return "\n".join(lines)
    except Exception:
        return ""

def sanitize_netlify_name(name: str) -> str:
    """
    Produce a Netlify-safe subdomain from a repo or site name.
    Lowercase, convert spaces/underscores to hyphens, and strip invalid chars.
    """
    name = name.lower().replace(" ", "-").replace("_", "-")
    name = re.sub(r"[^a-z0-9-]", "-", name)
    # collapse repeated dashes and strip from ends
    name = re.sub(r"-{2,}", "-", name).strip("-")
    return name or "site"

def clean_base_url(val: str | None) -> str:
    """Normalize a domain/baseUrl: strip http(s):// scheme, whitespace, and trailing slashes."""
    if not val:
        return ""
    val = val.strip()
    val = re.sub(r"^https?://", "", val, flags=re.IGNORECASE)
    val = val.rstrip("/")
    return val

def safe_clean_public_dir(public_dir: Path):
    """
    Safely clean the public output directory before running Quartz build,
    avoiding ENOTEMPTY / rimraf collisions on Docker bind-mounted filesystems.
    """
    if not public_dir.exists():
        return
    import time
    for attempt in range(5):
        try:
            for item in public_dir.iterdir():
                if item.is_dir() and not item.is_symlink():
                    shutil.rmtree(item, ignore_errors=False)
                else:
                    item.unlink(missing_ok=True)
            return
        except Exception:
            time.sleep(0.05 * (attempt + 1))
    try:
        shutil.rmtree(public_dir, ignore_errors=True)
        public_dir.mkdir(parents=True, exist_ok=True)
    except Exception:
        pass

def rebuild_for_production(course_code: str, section: str, host_os: str):
    """
    Rebuild the section site for production using build_site.py --build-only.
    Stages the build workspace on container-internal ext4 storage (/tmp/quartz-builds),
    syncs public/ to host courses/<COURSE>/.merged_output/section<N>/public,
    and ensures all live site domains and OpenGraph metadata are up to date.
    """
    print(" Rebuilding site for production…")
    build_script = Path("/opt/scripts/build_site.py")
    if not build_script.exists():
        build_script = Path(__file__).parent / "build_site.py"

    cmd = [
        sys.executable,
        str(build_script),
        f"--course={course_code}",
        f"--section={section}",
        "--build-only",
        f"--host-os={host_os}",
    ]
    try:
        subprocess.run(cmd, check=True)
        print("✅ Production build complete.")
    except (subprocess.CalledProcessError, OSError) as e:
        print(f"❌ Production rebuild failed: {e}")
        sys.exit(1)

def ensure_base_url_and_rebuild(section_dir: Path, target_domain: str, course_code: str, section: str, host_os: str):
    """
    If quartz.config.ts in internal build dir has a baseUrl that does not match target_domain,
    rebuild for production using build_site.py so OpenGraph and Twitter meta tags reflect
    the deployed site domain.
    """
    clean_target = clean_base_url(target_domain)
    if not clean_target:
        return

    internal_dir = Path(f"/tmp/quartz-builds/{course_code}/section{section}")
    config_paths = [p / "quartz.config.ts" for p in [section_dir, internal_dir] if (p / "quartz.config.ts").is_file()]

    needs_rebuild = False
    if not config_paths:
        needs_rebuild = True
    else:
        for config_path in config_paths:
            try:
                src = config_path.read_text(encoding="utf-8")
                m = re.search(r'baseUrl\s*:\s*(["\'])([^"\']*)(\1)', src)
                current_val = m.group(2) if m else None
                if current_val != clean_target:
                    needs_rebuild = True
                    break
            except Exception:
                needs_rebuild = True
                break

    if needs_rebuild:
        print(f" Updating Quartz baseUrl to '{clean_target}' and rebuilding for production…")
        rebuild_for_production(course_code, section, host_os)

# ---------- Teacher profile (unchanged) ----------
COURSES_ROOT = Path("/teaching/courses")
# Hidden global store for non-secret preferences (e.g., teacher profile)
GLOBAL_SECRETS_ROOT = COURSES_ROOT / ".internal"
# Legacy path (kept only to migrate profile.json, not tokens)
OLD_GLOBAL_SECRETS_ROOT = COURSES_ROOT / "_secrets"

def _profile_path() -> Path:
    return GLOBAL_SECRETS_ROOT / "profile.json"

def _ensure_courses_gitignore():
    """
    Ensure /teaching/courses/.gitignore exists and ignores:
      - /.internal/ (hidden store for small prefs)
      - /_backups/  (backups should never be committed)
    Idempotent: only adds missing lines.
    """
    try:
        COURSES_ROOT.mkdir(parents=True, exist_ok=True)
        gi_path = COURSES_ROOT / ".gitignore"
        to_add = [
            "# Dockerized Quartz for Teachers (auto-ignore)",
            "/.internal/",
            "/_backups/",
            "",  # trailing newline
        ]
        existing = []
        if gi_path.exists():
            try:
                existing = gi_path.read_text(encoding="utf-8").splitlines()
            except Exception:
                existing = []
        new_lines = existing[:]
        def ensure(line: str):
            if line not in new_lines:
                new_lines.append(line)
        for line in to_add:
            ensure(line)
        gi_path.write_text("\n".join(new_lines) + ("\n" if not new_lines or new_lines[-1] != "" else ""), encoding="utf-8")
    except Exception:
        # Non-fatal: continue silently if we cannot write .gitignore
        pass

def _ensure_global_secrets_dir():
    _ensure_courses_gitignore()
    GLOBAL_SECRETS_ROOT.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(GLOBAL_SECRETS_ROOT, 0o700)
    except Exception:
        pass

def sanitize_last_name(name: str) -> str:
    """
    Lowercase and keep letters only; e.g., 'Mc-Donald ' -> 'mcdonald'.

    Accented letters are folded to their plain form rather than dropped, so
    'Côté' becomes 'cote' instead of 'ct'. Ontario staff lists are full of
    names that the dropping version turned into two or three letters, which
    a teacher would not recognise as their own site.
    """
    folded = unicodedata.normalize("NFKD", name.strip().lower())
    folded = "".join(ch for ch in folded if not unicodedata.combining(ch))
    return re.sub(r"[^a-z]", "", folded)

def load_teacher_last_name() -> str | None:
    path = _profile_path()
    if not path.exists():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        ln = (data or {}).get("teacher_last_name")
        if ln:
            return sanitize_last_name(ln)
    except Exception:
        return None
    return None

def save_teacher_last_name(last_name: str):
    _ensure_global_secrets_dir()
    data = {"teacher_last_name": sanitize_last_name(last_name)}
    path = _profile_path()
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")
    try:
        os.chmod(path, 0o600)
    except Exception:
        pass

def get_or_prompt_teacher_last_name() -> str | None:
    ln = load_teacher_last_name()
    if ln:
        return ln
    if not sys.stdin.isatty():
        return None
    try:
        # First run under this /teaching/courses folder
        print("\nTeacher Surname.")
        print("Your surname is used to create a clear, recognizable web address for your")
        print("students and families (such as mcv4u-s1-2026-gordon), and to prevent naming")
        print("conflicts with other classes. It is saved on this computer and only asked once.\n")
        raw = input("First time setup... what is your last name? (letters only): ").strip()
        ln = sanitize_last_name(raw)
        while not ln:
            raw = input("Please enter letters only for your last name (e.g., 'Gordon'): ").strip()
            ln = sanitize_last_name(raw)
        save_teacher_last_name(ln)
        print(f" Saved teacher last name for future deploys: {ln}")
        return ln
    except (EOFError, OSError):
        return None

# ---------- Timezone helpers ----------
def parse_host_tz() -> dt.tzinfo:
    """
    Parse HOST_TZ_OFFSET from env in ±HHMM form (e.g., -0400, +0530).
    Fallback: system local timezone (as a last resort UTC if unknown).
    """
    raw = os.getenv("HOST_TZ_OFFSET", "").strip()
    if re.fullmatch(r"[+-]\d{4}", raw):
        sign = 1 if raw[0] == "+" else -1
        hours = int(raw[1:3])
        minutes = int(raw[3:5])
        offset = dt.timedelta(hours=sign * hours, minutes=sign * minutes)
        return dt.timezone(offset)
    try:
        return dt.datetime.now().astimezone().tzinfo or dt.timezone.utc
    except Exception:
        return dt.timezone.utc

TZ = parse_host_tz()
NOW = dt.datetime.now(TZ)

def prompt(text: str, default: str | None = None) -> str:
    if not sys.stdin.isatty():
        return default or ""
    if default is not None and default != "":
        try:
            resp = input(f"{text} [{default}]: ").strip()
            return resp or default
        except (EOFError, OSError):
            return default
    try:
        return input(f"{text}: ").strip()
    except (EOFError, OSError):
        return ""

# ---------- Netlify API helpers ----------
def netlify_api(method: str, path: str, token: str, payload: dict | None = None, headers: dict | None = None, data: bytes | None = None) -> dict:
    base = "https://api.netlify.com/api/v1"
    url = f"{base}{path}"
    req = urllib.request.Request(url, method=method)
    req.add_header("Accept", "application/json")
    req.add_header("Authorization", f"Bearer {token}")
    if headers:
        for k, v in headers.items():
            req.add_header(k, v)
    body = None
    if data is not None:
        body = data
    elif payload is not None:
        body = json.dumps(payload).encode("utf-8")
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, data=body, timeout=60) as resp:
            raw = resp.read()
            if not raw:
                return {}
            return json.loads(raw.decode("utf-8"))
    except urllib.error.HTTPError as e:
        msg = e.read().decode("utf-8", errors="ignore")
        # NEW: enrich 429 errors (and others) with rate-limit guidance
        guidance = _format_rate_limit_guidance(getattr(e, "headers", {}))
        suffix = f"\n{guidance}" if guidance else ""
        raise RuntimeError(f"Netlify API error {e.code}: {msg}{suffix}") from e

def _extract_json_from_error(err: Exception) -> dict | None:
    s = str(err).strip()
    idx = s.rfind("{")
    if idx == -1:
        return None
    candidate = s[idx:]
    try:
        return json.loads(candidate)
    except Exception:
        return None

def _is_netlify_name_conflict(err: Exception) -> bool:
    s = str(err).lower()
    if "422" in s and ("unique" in s or "already" in s or "taken" in s or "exists"):
        return True
    data = _extract_json_from_error(err)
    if isinstance(data, dict):
        errs = data.get("errors")
        if isinstance(errs, dict):
            for _, messages in errs.items():
                if isinstance(messages, list):
                    for m in messages:
                        lm = (m or "").lower()
                        if any(x in lm for x in ["unique", "already", "taken", "exists"]):
                            return True
    return False

def suggest_site_base(course_code: str, section: str, teacher_last_name: str) -> str:
    """Example: ICD2O + 1 + gordon -> icd2o-s1-2025-gordon"""
    course = (course_code or "").lower()
    sec = f"s{section}"
    base = f"{course}-{sec}-{NOW.year}-{teacher_last_name}"
    return sanitize_netlify_name(base)

def maybe_create_netlify_site_simple(token: str, team_slug: str | None, course_code: str | None, section: str | None, teacher_last_name: str | None) -> dict:
    """
    Create a Netlify site WITHOUT linking to a Git provider.
    POST /api/v1/sites (or /api/v1/accounts/{team_slug}/sites)
    If the chosen name is taken, prompt for a different one.
    """
    if teacher_last_name and course_code and section:
        base = suggest_site_base(course_code, section, teacher_last_name)
    else:
        base = sanitize_netlify_name(f"{course_code or 'course'}-s{section or '1'}-{NOW.year}")
    print("\nChoose a Website Address.")
    print("Every website published to Netlify (*.netlify.app) needs a unique web address.")
    print("This name is shared globally with all users across the world.\n")
    site_name = prompt("Enter Netlify site name", default=base).strip() or base
    path = f"/accounts/{team_slug}/sites" if team_slug else "/sites"
    attempt = 0
    while True:
        payload = {
            "name": site_name,
            "created_via": "Dockerized Quartz for Teachers",
        }
        try:
            site = netlify_api("POST", path, token, payload)
            return site
        except RuntimeError as e:
            if _is_netlify_name_conflict(e):
                attempt += 1
                suggestion = f"{base}-{attempt:02d}"
                if not sys.stdin.isatty():
                    print(f"⚠️ Website Address '{site_name}' is already in use on Netlify. Trying '{suggestion}'…")
                    site_name = suggestion
                    continue
                print(f"\n⚠️ Website Address Already Taken.")
                print(f"The address '{site_name}' is already in use by another site on Netlify.")
                print("Tip: Add your school's initials (e.g. lcs-mcv4u-s1-2026-gordon) or a number suffix.\n")
                new_name = prompt("Choose a different Netlify site name (or 'q' to cancel)", default=suggestion).strip()
                if new_name.lower() in {"q", "quit", "exit"}:
                    raise RuntimeError("User cancelled Netlify site creation after name conflict.") from e
                site_name = sanitize_netlify_name(new_name) or suggestion
                continue
            raise

# ---------- Stable site marker (new) + migration from legacy ----------
def _stable_marker_dir(course_dir: Path) -> Path:
    return course_dir / ".netlify_sites"

def _stable_marker_path(course_dir: Path, section: str | int) -> Path:
    return _stable_marker_dir(course_dir) / f"section{section}.json"

def _legacy_marker_path(section_dir: Path) -> Path:
    return section_dir / ".netlify_site.json"

def load_netlify_marker(course_dir: Path, section_dir: Path, section: str | int) -> dict | None:
    """
    Prefer stable marker at /.netlify_sites/section.json.
    If not found, migrate legacy marker from /.netlify_site.json.
    """
    stable = _stable_marker_path(course_dir, section)
    if stable.exists():
        try:
            return json.loads(stable.read_text(encoding="utf-8"))
        except Exception:
            pass
    legacy = _legacy_marker_path(section_dir)
    if legacy.exists():
        try:
            data = json.loads(legacy.read_text(encoding="utf-8"))
            # migrate
            _stable_marker_dir(course_dir).mkdir(parents=True, exist_ok=True)
            stable.write_text(json.dumps(data, indent=2), encoding="utf-8")
            try:
                os.chmod(stable, 0o600)
            except Exception:
                pass
            try:
                legacy.unlink()
            except Exception:
                pass
            print(" Migrated Netlify site marker to stable location.")
            return data
        except Exception:
            return None
    return None

def save_netlify_marker(course_dir: Path, section: str | int, site: dict):
    _stable_marker_dir(course_dir).mkdir(parents=True, exist_ok=True)
    p = _stable_marker_path(course_dir, section)
    p.write_text(json.dumps(site, indent=2), encoding="utf-8")
    try:
        os.chmod(p, 0o600)
    except Exception:
        pass

# ---------- Cloudflare Pages ----------
# Cloudflare refuses any single file larger than this, and the failure comes
# back from deep inside the upload as an unhelpful error — so the size is
# checked here, before anything is sent, and reported by filename.
CF_MAX_FILE_BYTES = 25 * 1024 * 1024
CF_API = "https://api.cloudflare.com/client/v4"

def cloudflare_api(method: str, path: str, token: str, payload: dict | None = None):
    """
    Cloudflare wraps every response in {success, errors, result} and can
    report failure inside a 200, so both the HTTP status and that envelope
    are checked. Returns the unwrapped `result` (a dict or a list).
    """
    req = urllib.request.Request(f"{CF_API}{path}", method=method)
    req.add_header("Accept", "application/json")
    req.add_header("Authorization", f"Bearer {token}")
    body = None
    if payload is not None:
        body = json.dumps(payload).encode("utf-8")
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, data=body) as resp:
            raw = resp.read()
    except urllib.error.HTTPError as e:
        raw = e.read()
        raise RuntimeError(f"Cloudflare API error {e.code}: {_cf_errors(raw)}") from e
    if not raw:
        return {}
    data = json.loads(raw.decode("utf-8"))
    if not data.get("success", True):
        raise RuntimeError(f"Cloudflare API error: {_cf_errors(raw)}")
    result = data.get("result")
    return {} if result is None else result

def _cf_errors(raw: bytes) -> str:
    try:
        data = json.loads(raw.decode("utf-8", errors="ignore"))
        messages = [str(x.get("message", "")).strip() for x in (data.get("errors") or [])]
        joined = "; ".join(m for m in messages if m)
        if joined:
            return joined
    except Exception:
        pass
    return raw.decode("utf-8", errors="ignore").strip() or "no details given"

def discover_cloudflare_account(token: str) -> str:
    """
    Cloudflare needs an account ID as well as a token, but asking a teacher to
    find a 32-character hex string in a dashboard is exactly the kind of step
    that loses people. The token already knows which account it can reach, so
    look it up instead of asking.
    """
    accounts = cloudflare_api("GET", "/accounts", token)
    if not isinstance(accounts, list) or not accounts:
        raise RuntimeError("This token cannot reach any Cloudflare account.")
    if len(accounts) > 1:
        names = ", ".join(str(a.get("name", "?")) for a in accounts)
        print(f" This token can reach several Cloudflare accounts: {names}")
        print(f" Using the first one ({accounts[0].get('name')}).")
    return accounts[0]["id"]

def sanitize_pages_name(name: str) -> str:
    """
    Cloudflare Pages project names allow lowercase letters, digits and
    hyphens, must begin and end alphanumeric, and stop at 58 characters.
    """
    name = name.lower().replace(" ", "-").replace("_", "-")
    name = re.sub(r"[^a-z0-9-]", "-", name)
    name = re.sub(r"-{2,}", "-", name).strip("-")
    return name[:58].strip("-") or "class-site"

def suggest_pages_name(course_code: str, section: str, teacher_last_name: str | None) -> str:
    base = f"{course_code or 'course'}-s{section or '1'}-{NOW.year}"
    if teacher_last_name:
        base = f"{base}-{teacher_last_name}"
    return sanitize_pages_name(base)

def _cf_marker_dir(course_dir: Path) -> Path:
    return course_dir / ".cloudflare_sites"

def _cf_marker_path(course_dir: Path, section: str | int) -> Path:
    return _cf_marker_dir(course_dir) / f"section{section}.json"

def load_cloudflare_marker(course_dir: Path, section: str | int) -> dict | None:
    p = _cf_marker_path(course_dir, section)
    if p.exists():
        try:
            return json.loads(p.read_text(encoding="utf-8"))
        except Exception:
            pass
    return None

def save_cloudflare_marker(course_dir: Path, section: str | int, project: dict):
    _cf_marker_dir(course_dir).mkdir(parents=True, exist_ok=True)
    p = _cf_marker_path(course_dir, section)
    p.write_text(json.dumps(project, indent=2), encoding="utf-8")
    try:
        os.chmod(p, 0o600)
    except Exception:
        pass

def ensure_pages_project(token: str, account_id: str, name: str) -> dict:
    """
    Find this section's project or create it. A Pages project name only has to
    be unique inside the teacher's own account — unlike a Netlify site name,
    which is global — so a name that already exists almost always means "this
    section published before" and is reused rather than renamed around.
    """
    try:
        existing = cloudflare_api("GET", f"/accounts/{account_id}/pages/projects/{name}", token)
        if existing:
            return existing
    except RuntimeError:
        pass  # Most often "not found"; a real problem resurfaces on create.
    return cloudflare_api(
        "POST", f"/accounts/{account_id}/pages/projects", token,
        {"name": name, "production_branch": "main"},
    )

def oversized_for_cloudflare(public_dir: Path) -> list[tuple[str, int]]:
    """Files Cloudflare Pages will refuse, newest complaint first."""
    too_big = []
    for f in _iter_public_files(public_dir):
        try:
            size = f.stat().st_size
        except OSError:
            continue
        if size > CF_MAX_FILE_BYTES:
            too_big.append((_remote_path_for(public_dir, f), size))
    too_big.sort(key=lambda pair: pair[1], reverse=True)
    return too_big

def deploy_to_cloudflare(public_dir: Path, project_name: str, token: str, account_id: str):
    """
    Hand the built folder to Cloudflare's own CLI. The upload protocol is a
    multi-stage, undocumented one (BLAKE3 asset hashing, a short-lived upload
    JWT that can expire mid-upload on a large site, batching); wrangler is
    Cloudflare's supported implementation of it and already handles those
    edges, so publishing rides on it rather than on a reimplementation.
    """
    env = os.environ.copy()
    env["CLOUDFLARE_API_TOKEN"] = token
    env["CLOUDFLARE_ACCOUNT_ID"] = account_id
    # The app runs this with no console to answer prompts on.
    env["CI"] = "1"
    env.setdefault("WRANGLER_SEND_METRICS", "false")
    cmd = [
        "wrangler", "pages", "deploy", str(public_dir),
        f"--project-name={project_name}",
        # The production branch is what gives the stable <project>.pages.dev
        # address; a different branch would publish to a preview URL instead.
        "--branch=main",
        # There is no git repository here, and without this wrangler stops to
        # ask about the "dirty" working directory.
        "--commit-dirty=true",
    ]
    try:
        completed = subprocess.run(cmd, env=env)
    except OSError as e:
        raise RuntimeError(f"Could not run Cloudflare's deploy tool: {e}") from e
    if completed.returncode != 0:
        raise RuntimeError(f"Cloudflare's deploy tool exited with code {completed.returncode}")

def publish_to_cloudflare(public_dir: Path, course_dir: Path, course_code: str,
                          section: str, teacher_last_name: str | None):
    token = os.getenv("CLOUDFLARE_API_TOKEN")
    if not token:
        print("❌ Cloudflare token missing.")
        print(" This script expects the token to be passed in by the launcher.")
        print(" If you ran this directly, create an API token with the")
        print(" 'Cloudflare Pages: Edit' permission here:")
        print("   https://dash.cloudflare.com/profile/api-tokens")
        print(" Then set it as CLOUDFLARE_API_TOKEN and re-run via your launcher:")
        print(f"   {_cmd_example('deploy', course_code, section, _HOST_OS)}")
        sys.exit(1)

    oversized = oversized_for_cloudflare(public_dir)
    if oversized:
        print("❌ Some files are too large for Cloudflare Pages.")
        print(" Cloudflare refuses any single file bigger than 25 MB:")
        for rel, size in oversized[:10]:
            print(f"   {rel} — {size / (1024 * 1024):.1f} MB")
        if len(oversized) > 10:
            print(f"   …and {len(oversized) - 10} more.")
        print(" Shorten or compress the file — a shorter or lower-resolution")
        print(" video is usually enough — or publish this section to Netlify,")
        print(" which allows larger files.")
        sys.exit(1)

    account_id = os.getenv("CLOUDFLARE_ACCOUNT_ID")
    if not account_id:
        account_id = discover_cloudflare_account(token)

    marker = load_cloudflare_marker(course_dir, section)
    if marker and marker.get("name"):
        project_name = marker["name"]
        print(f" Using this section's existing Cloudflare project: {project_name}")
    else:
        # Same rule as the Netlify path: the surname is asked for only when
        # a NEW project is being named, never on a repeat deploy.
        if teacher_last_name is None:
            try:
                teacher_last_name = get_or_prompt_teacher_last_name()
            except Exception:
                teacher_last_name = None
        project_name = suggest_pages_name(course_code, section, teacher_last_name)
        project = ensure_pages_project(token, account_id, project_name)
        project_name = project.get("name") or project_name
        save_cloudflare_marker(course_dir, section, {
            "name": project_name,
            "id": project.get("id"),
            "subdomain": project.get("subdomain"),
            "account_id": account_id,
        })
        print(f" Cloudflare project ready: {project_name}")

    marker = load_cloudflare_marker(course_dir, section) or {}
    host = marker.get("subdomain") or f"{project_name}.pages.dev"
    ensure_base_url_and_rebuild(public_dir.parent, host, course_code, str(section), _HOST_OS)

    print(" Uploading the built site to Cloudflare…")
    deploy_to_cloudflare(public_dir, project_name, token, account_id)

    # The marker's subdomain is authoritative when Cloudflare has given one;
    # otherwise the production address is <project>.pages.dev by construction.
    print(f" Live URL: https://{host}")
    print("\n✅ Deploy complete.")

# ---------- Delta deploy helpers ----------
def _sha1_bytes(data: bytes) -> str:
    h = hashlib.sha1()
    h.update(data)
    return h.hexdigest()

def _sha1_file(path: Path, bufsize: int = 1024 * 1024) -> str:
    h = hashlib.sha1()
    with path.open("rb") as f:
        while True:
            b = f.read(bufsize)
            if not b:
                break
            h.update(b)
    return h.hexdigest()

def _iter_public_files(root: Path):
    for p in sorted(root.rglob("*")):
        if p.is_file():
            # skip obvious junk
            name = p.name.lower()
            if name in {".ds_store"}:
                continue
            yield p

def _remote_path_for(root: Path, file_path: Path) -> str:
    rel = file_path.relative_to(root).as_posix()
    return "/" + rel  # Netlify expects leading slash

def _build_files_manifest(root: Path) -> tuple[dict, dict]:
    """
    Return:
      - files_map: { "/path/on/site": "sha1digest" }
      - sha_to_pairs: { "sha1": [(remote_path, relative_local_path), ...] }
    """
    files_map: dict[str, str] = {}
    sha_to_pairs: dict[str, list[tuple[str, str]]] = {}
    for f in _iter_public_files(root):
        remote = _remote_path_for(root, f)
        digest = _sha1_file(f)
        files_map[remote] = digest
        sha_to_pairs.setdefault(digest, []).append((remote, f.relative_to(root).as_posix()))
    return files_map, sha_to_pairs

def create_delta_deploy(site_id: str, token: str, root: Path, draft: bool = False, async_req: bool = False) -> dict:
    """
    Step 1: POST /sites/{site_id}/deploys with {"files": { "/path": "sha1", ... }}
    Returns a list of "required" digests to upload via PUTs.
    """
    files_map, sha_to_pairs = _build_files_manifest(root)
    payload = {"files": files_map}
    if draft:
        payload["draft"] = True
    if async_req:
        payload["async"] = True
    deploy = netlify_api("POST", f"/sites/{site_id}/deploys", token, payload=payload)
    deploy["_sha_to_pairs"] = sha_to_pairs  # carry through for upload/diagnostics
    return deploy

def _upload_required_files(deploy_id: str, token: str, root: Path, required_shas: list[str], sha_to_pairs: dict[str, list[tuple[str, str]]]):
    """
    Step 2: PUT each required file to /deploys/{deploy_id}/files/<path>
    Only one path per required digest is necessary.
    """
    if not required_shas:
        print(" No file uploads needed (all content already present on Netlify).", flush=True)
        return

    items_to_upload = []
    for sha in required_shas:
        pairs = sha_to_pairs.get(sha) or []
        if not pairs:
            print(f"⚠️ Netlify requested unknown digest {sha[:8]}…; skipping.", flush=True)
            continue
        remote_path, local_rel = pairs[0]
        local_file = root / local_rel
        if not local_file.exists():
            print(f"⚠️ Missing local file for {remote_path}; skipping.", flush=True)
            continue
        encoded_path = urllib.parse.quote(remote_path.lstrip("/"), safe="/")
        items_to_upload.append((encoded_path, local_file))

    uploaded = 0
    total = len(items_to_upload)
    import concurrent.futures

    def _upload_one(item):
        # Netlify rate-limits the upload endpoint, and concurrent PUTs reach
        # that limit far sooner than the old serial loop did — measured live:
        # 318 files at 10 workers died on the first 429 and failed the whole
        # deploy. A 429 (or a transient 5xx/timeout) is therefore an expected
        # event here, not an error: back off — honouring Retry-After when
        # Netlify names a wait — and try that file again.
        enc_path, loc_file = item
        with loc_file.open("rb") as f:
            data = f.read()
        headers = {"Content-Type": "application/octet-stream"}
        delay = 1.0
        last_error: Exception | None = None
        for attempt in range(6):
            try:
                netlify_api("PUT", f"/deploys/{deploy_id}/files/{enc_path}", token, headers=headers, data=data)
                return
            except RuntimeError as e:
                msg = str(e)
                retryable = any(f"Netlify API error {code}" in msg for code in (429, 500, 502, 503, 504))
                if not retryable:
                    raise
                last_error = e
                wait = delay
                cause = getattr(e, "__cause__", None)
                retry_after = None
                try:
                    if cause is not None and getattr(cause, "headers", None):
                        retry_after = cause.headers.get("Retry-After")
                except Exception:
                    retry_after = None
                if retry_after:
                    try:
                        wait = max(wait, float(retry_after))
                    except ValueError:
                        pass
                time.sleep(min(wait, 30.0))
                delay *= 2
            except (urllib.error.URLError, TimeoutError) as e:
                # Socket timeout or drop mid-upload; the file is small, retry it.
                last_error = e
                time.sleep(min(delay, 30.0))
                delay *= 2
        raise RuntimeError(f"Upload of {enc_path} kept failing after retries: {last_error}") from last_error

    # 5 workers, not 10: with retries in place 10 still converges, but it
    # spends most of its time backing off — 5 stays under the limit.
    max_workers = min(5, max(1, len(items_to_upload)))
    with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = {executor.submit(_upload_one, item): item for item in items_to_upload}
        for future in concurrent.futures.as_completed(futures):
            future.result()
            uploaded += 1
            if uploaded % 25 == 0 or uploaded == total:
                print(f" …uploaded {uploaded}/{total} required files", flush=True)

    print(f"⬆️ Uploaded {uploaded} file(s) required by Netlify.", flush=True)

# ---------- Diagnostics (new) ----------
_IMG_EXT  = {"jpg","jpeg","png","gif","webp","svg","bmp","tiff","ico","avif"}
_FONT_EXT = {"woff","woff2","ttf","otf","eot"}
_SCRIPT_EXT = {"js","mjs"}
_STYLE_EXT = {"css"}
_HTML_EXT = {"html","htm"}
_DATA_EXT = {"json","xml","txt","map","csv"}
_MEDIA_EXT = {"mp4","mp3","wav","ogg","webm","m4a"}

def _category_for(rel: str) -> str:
    ext = rel.rsplit(".", 1)[-1].lower() if "." in rel else ""
    if ext in _IMG_EXT: return "images"
    if ext in _FONT_EXT: return "fonts"
    if ext in _SCRIPT_EXT: return "scripts"
    if ext in _STYLE_EXT: return "styles"
    if ext in _HTML_EXT: return "html"
    if ext in _DATA_EXT: return "data"
    if ext in _MEDIA_EXT: return "media"
    return "other"

def print_required_diagnostics(required_shas: list[str], sha_to_pairs: dict[str, list[tuple[str, str]]], public_dir: Path):
    """
    Summarize and persist the 'required' list from Netlify.
    Writes full, ordered list to: public/_required_last_deploy.txt
    """
    items: list[tuple[str,str,str]] = []  # (sha, remote_path, local_rel)
    for sha in required_shas:
        pairs = sha_to_pairs.get(sha) or []
        if not pairs:  # shouldn't happen
            items.append((sha, "", ""))
        else:
            items.append((sha, pairs[0][0], pairs[0][1]))

    # Counts by category
    cat = Counter(_category_for(rel) for _, _, rel in items)
    total = len(items)
    print("\n Diagnostics: Breakdown of 'required' files")
    for k in ("html","styles","scripts","data","images","fonts","media","other"):
        if cat.get(k):
            print(f" • {k:7s}: {cat[k]}")
    print(f" • total : {total}")

    # Show a small sample (up to 30)
    print("\n Sample (first up to 30 paths Netlify requested):")
    for sha, _, rel in items[:30]:
        print(f" - {rel} [{sha[:8]}…]")

    # Persist full list
    out = public_dir / "_required_last_deploy.txt"
    try:
        with out.open("w", encoding="utf-8") as f:
            f.write(f"Required files for last deploy — generated {NOW.isoformat(timespec='seconds')}\n")
            f.write(f"Public root: {public_dir}\n\n")
            f.write("Count by category:\n")
            for k in ("html","styles","scripts","data","images","fonts","media","other"):
                if cat.get(k):
                    f.write(f" - {k:7s}: {cat[k]}\n")
            f.write(f" - total : {total}\n\n")
            f.write("Full list (sha remote_path local_rel):\n")
            for sha, remote, rel in items:
                f.write(f"{sha} {remote} {rel}\n")
        print(f"\n Wrote full list to: {out}")
    except Exception as e:
        print(f"⚠️ Could not write diagnostics file: {e}")

# ---------- Main ----------
def main():
    p = argparse.ArgumentParser(
        description="Publish a built section site — to Netlify by delta (file-digest) upload, or to Cloudflare Pages."
    )
    p.add_argument("--host-os", choices=["windows","mac","linux","unknown"], default="unknown",
                   help="Host OS passed by deploy launchers")
    p.add_argument("--target", choices=["netlify", "cloudflare"], default="netlify",
                   help="Where to publish. Defaults to netlify.")
    p.add_argument("--course", required=True, help="Course code, e.g., ICS3U")
    p.add_argument("--section", required=True, help="Section number, e.g., 1")
    p.add_argument("--diagnose", action="store_true",
                   help="Print a breakdown of required files and save list to _required_last_deploy.txt")
    # optional team slug flag (advanced users only)
    p.add_argument("--team", "--team-slug", dest="team", default=None,
                   help="Netlify team slug (advanced). If omitted, your personal team is used.")
    args = p.parse_args()

    global _HOST_OS
    _HOST_OS = getattr(args, 'host_os', 'unknown')

    # Keep .gitignore hygiene and migrate *profile only* from legacy if present.
    _ensure_courses_gitignore()
    # (Do NOT migrate or touch any token stores here; host launcher handles that.)

    # Path: /teaching/courses/<COURSE>/.merged_output/section<SECTION>
    section_dir = Path(f"/teaching/courses/{args.course}/.merged_output/section{args.section}").resolve()
    if not section_dir.exists():
        print(f"❌ Section directory not found: {section_dir}")
        print(f" Please run the preview/build first:")
        print(f"{_cmd_example('preview', args.course, args.section, _HOST_OS)}")
        sys.exit(1)

    # Require the built site (public/)
    public_dir = section_dir / "public"
    if not public_dir.exists() or not any(public_dir.iterdir()):
        print(f"❌ Built site not found at: {public_dir}")
        print(f" Please build before deploying.\n For example:")
        print(f"{_cmd_example('preview', args.course, args.section, _HOST_OS)}")
        sys.exit(1)

    # A PREVIEW build must never reach the public site. Serve mode bakes a
    # live-reload client — new WebSocket('ws://localhost:<port>') — into every
    # page; on the published site that script makes browsers ask permission to
    # "access other apps and services on this device". Since previewing is the
    # documented way to produce public/, detect the client and quietly re-emit
    # a production build from the same merged sources before uploading.
    index_html = public_dir / "index.html"
    try:
        is_preview_build = "ws://localhost:" in index_html.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        is_preview_build = False
    if is_preview_build:
        print(" Preview build detected (live-reload client) — rebuilding for production…")
        rebuild_for_production(args.course, str(args.section), _HOST_OS)

    # Determine course dir (for stable marker)
    course_dir = section_dir.parent.parent  # .../<COURSE>/.merged_output/section#

    # The surname exists ONLY to name a NEW site, so it is merely LOADED
    # here — never prompted for. A deploy to a section that already has its
    # site must ask no questions at all: prompting eagerly meant every
    # deploy on a machine with no saved surname stopped for input, and in
    # the GUI a missed or cancelled dialog read as "deploys are broken".
    # The prompt happens at the one place a name is actually being chosen.
    try:
        teacher_last_name = load_teacher_last_name()
    except Exception:
        teacher_last_name = None

    print(f" Deploying from local build: {public_dir}")
    print(f" Timestamp TZ offset: {NOW.strftime('%z')}")

    # Everything above is target-independent: the same built folder is what
    # gets published wherever it goes.
    if args.target == "cloudflare":
        publish_to_cloudflare(
            public_dir=public_dir,
            course_dir=course_dir,
            course_code=args.course,
            section=str(args.section),
            teacher_last_name=teacher_last_name,
        )
        return

    # --- Token handling (new, simplified) ---
    # Only read from environment; host launcher (deploy.sh/.ps1) must inject it.
    netlify_token = os.getenv("NETLIFY_AUTH_TOKEN")
    if not netlify_token:
        print("❌ Netlify token missing.")
        print(" This script now expects the token to be passed via environment by the host launcher.")
        print(" If you ran this directly, create a Personal Access Token here:")
        print("   https://app.netlify.com/user/applications#personal-access-tokens")
        print(" Then set it as NETLIFY_AUTH_TOKEN and re-run via your platform launcher:")
        print(f"   {_cmd_example('deploy', args.course, args.section, _HOST_OS)}")
        sys.exit(1)

    # Discover or create the Netlify site (no repo link)
    site_marker = load_netlify_marker(course_dir, section_dir, args.section)
    site_id = None
    site_url = None
    if site_marker:
        site_id = site_marker.get("id")
        site_url = site_marker.get("url") or site_marker.get("admin_url")
        # Verify that the site actually exists on Netlify with this token
        if site_id:
            try:
                live_site = netlify_api("GET", f"/sites/{site_id}", netlify_token)
                site_url = live_site.get("ssl_url") or live_site.get("url") or site_url
                print(" Using existing Netlify site for this section.")
                if site_url:
                    print(f" Site: {site_url}")
            except RuntimeError as e:
                if "404" in str(e):
                    print(f"⚠️ Saved Netlify site ({site_id}) was not found on Netlify.")
                    print(" Creating a fresh Netlify site for this section…")
                    site_marker = None
                    site_id = None
                    site_url = None
                else:
                    raise

    if not site_marker:
        # A site is about to be NAMED — the one moment the surname is
        # useful. On a terminal this asks (once, then it is saved); anywhere
        # non-interactive it stays None and the name simply omits it.
        if teacher_last_name is None:
            try:
                teacher_last_name = get_or_prompt_teacher_last_name()
            except Exception:
                teacher_last_name = None
        team_slug = args.team  # <-- use CLI flag; no interactive prompt
        if team_slug:
            print(f" Using Netlify team: {team_slug}")
        try:
            site = maybe_create_netlify_site_simple(
                token=netlify_token,
                team_slug=team_slug,
                course_code=args.course,
                section=str(args.section),
                teacher_last_name=teacher_last_name
            )
            save_netlify_marker(course_dir, args.section, site)
            site_id = site.get("id")
            site_url = site.get("ssl_url") or site.get("url")
            admin_url = site.get("admin_url")
            print(" Netlify site created.")
            if site_url:
                print(f" Live URL: {site_url}")
            if admin_url:
                print(f" Admin: {admin_url}")
        except Exception as e:
            print("❌ Failed to create Netlify site.")
            print(f" Details: {e}")
            sys.exit(1)

    if not site_id:
        print("❌ Could not determine Netlify site ID.")
        sys.exit(1)

    target_domain = clean_base_url(site_url)
    if target_domain:
        ensure_base_url_and_rebuild(section_dir, target_domain, args.course, str(args.section), _HOST_OS)

    # Always delta deploy to PRODUCTION (as requested)
    print(" Preparing delta deploy manifest…")
    try:
        manifest_resp = create_delta_deploy(site_id, netlify_token, public_dir, draft=False, async_req=False)
        deploy_id = manifest_resp.get("id")
        required = manifest_resp.get("required") or []
        sha_to_pairs = manifest_resp.get("_sha_to_pairs") or {}
        print(f" Netlify requires {len(required)} file(s) for this deploy.")
        if args.diagnose:
            print_required_diagnostics(required, sha_to_pairs, public_dir)
        _upload_required_files(deploy_id, netlify_token, public_dir, required, sha_to_pairs)
        print("✅ Delta deploy created (production).")
        if deploy_id:
            print(f" Deploy ID: {deploy_id}")
        if site_url:
            print(f" Site URL: {site_url}")
    except Exception as e:
        print("❌ Delta deploy failed.")
        print(f" Details: {e}")
        print(" Tip: Check for unusual filenames (control chars) and ensure your token has access to this team/site.")
        sys.exit(1)

    print("\n✅ Deploy complete.")

if __name__ == "__main__":
    main()
