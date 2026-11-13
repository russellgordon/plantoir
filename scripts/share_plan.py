#!/usr/bin/env python3
"""
Share a course's unit plans to Cloudflare Pages, or stop sharing them (#709).

Run by `deploy.sh <CODE> --plans`, inside the website builder (and natively by
Windows' runtime), never by hand in the ordinary course of things:

    python3 /opt/scripts/share_plan.py --host-os mac --course <CODE>
        [--protect | --remove-password] [--include-answer-keys] [--year YYYY]
        [--stop] [--non-interactive]

The rules are contracts/shared-rules.json -> unitPlanning.share, and the
order below is the one that keeps the worst fault away: a plan a teacher
believes is protected that can be read without the password. So nothing is
called shared until the address has been fetched and answered as promised
(`proof`), and every older deployment is deleted afterwards, because each
keeps an address of its own that served an open copy after a protected
share (measured 2026-11-12, `oldDeployments`).

The username and password reach this program in one file, /tmp/plan_cred,
written by the launcher through a pipe; it is read once and deleted at once,
and neither is ever printed, written to the marker, or passed on. Only a
salted hash goes into the worker. The Cloudflare token arrives in the
environment, as deploy.py's does.

Kept apart from deploy.py so that deploy.py's main() (whose source a test
reads) and its required --section stay as they are; it reuses deploy.py's
Cloudflare calls and its surname question.
"""
from __future__ import annotations

import argparse
import base64
import datetime as dt
import json
import os
import shutil
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path

import sys as _sys
_sys.path.insert(0, str(Path(__file__).resolve().parent))
import deploy  # noqa: E402
import reference_course  # noqa: E402
import toolchain_paths  # noqa: E402
import unit_plan_site  # noqa: E402

# Where the launcher leaves the username and password. A module value so the
# tests can point it elsewhere.
CRED_FILE = Path("/tmp/plan_cred")

SHARED_MARKER = "PLANTOIR_PLAN_SHARED:"
REFUSED_MARKER = "PLANTOIR_PLAN_REFUSED:"
STOPPED_MARKER = "PLANTOIR_PLAN_STOPPED:"

PROOF_SECONDS = 60
PROOF_EVERY = 2
NEW_PROJECT_SECONDS = 60
NAME_TRIES = 3

# The calls that reach the network, named here so the tests can replace them.
cloudflare_api = deploy.cloudflare_api
deploy_to_cloudflare = deploy.deploy_to_cloudflare
discover_cloudflare_account = deploy.discover_cloudflare_account
now = time.monotonic
sleep = time.sleep


def today() -> dt.date:
    return dt.date.today()


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def fetch_address(url: str, credential: str | None = None):
    """GET url, never following a redirect. Returns (status, headers with
    lower-case names); status is None when nothing answered."""
    request = urllib.request.Request(url, method="GET")
    request.add_header("User-Agent", "Plantoir")
    request.add_header("Cache-Control", "no-cache")
    if credential is not None:
        request.add_header("Authorization", "Basic " + credential)
    opener = urllib.request.build_opener(_NoRedirect)
    try:
        with opener.open(request, timeout=15) as answer:
            answer.read()
            return answer.status, _lower(answer.headers)
    except urllib.error.HTTPError as error:
        return error.code, _lower(error.headers)
    except Exception:
        return None, {}


def _lower(headers) -> dict:
    out = {}
    if headers is None:
        return out
    for name, value in headers.items():
        out[name.lower()] = value
    return out


# ------------------------------------------------------------------ helpers

def code_word(course: str) -> str:
    return str(course).replace(" ", "+")


def share_words() -> dict:
    return unit_plan_site.share_rules()


def say_refused(course: str, key: str, count: int | None = None, **values) -> None:
    sentence = share_words()["refusals"][key]
    if values:
        sentence = sentence.format(**values)
    print(f"❌ {sentence}")
    tail = f" {count}" if count is not None else ""
    print(f"{REFUSED_MARKER} {code_word(course)} {key}{tail}", flush=True)


def marker_path(course_dir: Path, year: int) -> Path:
    return course_dir / ".cloudflare_sites" / unit_plan_site.marker_name(year)


def write_marker(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name("." + path.name + ".tmp")
    temporary.write_text(json.dumps(data, indent=2), encoding="utf-8")
    try:
        os.chmod(temporary, 0o600)
    except OSError:
        pass
    os.replace(temporary, path)


def decide_protected(marker: dict | None, protect: bool, remove_password: bool) -> bool:
    """unitPlanning.share.modeCases: --protect protects, --remove-password
    opens, and neither keeps what the year's marker last asked for."""
    if protect:
        return True
    if remove_password:
        return False
    if marker is None:
        return False
    return marker.get("asked") == "protected" or marker.get("protected") is True


def read_credential() -> str | None:
    """The base64 of username:password from CRED_FILE, deleted at once.
    None when it is missing or not one username:password line."""
    try:
        raw = CRED_FILE.read_text(encoding="utf-8")
    except OSError:
        return None
    finally:
        forget_credential()
    line = raw.strip("\r\n")
    if "\n" in line or ":" not in line:
        return None
    username, _, password = line.partition(":")
    if not username or not password:
        return None
    return unit_plan_site.credential_b64(username, password)


def forget_credential() -> None:
    try:
        CRED_FILE.unlink()
    except OSError:
        pass


def project_path(account: str, name: str) -> str:
    return f"/accounts/{account}/pages/projects/{name}"


def fail_closed_configs() -> dict:
    return {"production": {"fail_open": False}, "preview": {"fail_open": False}}


def set_fail_closed(token: str, account: str, name: str) -> bool:
    """unitPlanning.share.failClosed: PATCH both environments, then read it
    back; True only when the read-back shows false on both."""
    try:
        cloudflare_api("PATCH", project_path(account, name), token,
                       {"deployment_configs": fail_closed_configs()})
        project = cloudflare_api("GET", project_path(account, name), token)
    except Exception:
        return False
    configs = (project or {}).get("deployment_configs") or {}
    for environment in ("production", "preview"):
        if (configs.get(environment) or {}).get("fail_open") is not False:
            return False
    return True


def wait_for_project(token: str, account: str, name: str) -> dict | None:
    """A project just made can answer 404 for a moment (measured once), and
    wrangler then fails with 'Project not found'. Wait for it."""
    start = now()
    while True:
        try:
            project = cloudflare_api("GET", project_path(account, name), token)
            if project:
                return project
        except RuntimeError:
            pass
        if now() - start >= NEW_PROJECT_SECONDS:
            return None
        sleep(PROOF_EVERY)


def make_project(token: str, account: str, course: str, year: int) -> dict:
    """A new project for this year, named with a fresh suffix; a name taken in
    this account (409) gets another suffix, at most NAME_TRIES times."""
    surname = deploy.get_or_prompt_teacher_last_name()
    last_error = None
    for _ in range(NAME_TRIES):
        name = unit_plan_site.project_name(course, year, surname, unit_plan_site.new_suffix())
        try:
            return cloudflare_api("POST", f"/accounts/{account}/pages/projects", token, {
                "name": name,
                "production_branch": "main",
                "deployment_configs": fail_closed_configs(),
            })
        except RuntimeError as error:
            if "error 409" in str(error):
                last_error = error
                continue
            raise
    raise RuntimeError(f"Cloudflare kept saying the name was taken: {last_error}")


def prove(address: str, protected: bool, credential: str | None, token: str, account: str, name: str) -> bool:
    """unitPlanning.share.proof."""
    start = now()
    while True:
        status, headers = fetch_address(address)
        if protected:
            challenge = headers.get("www-authenticate", "")
            if status == 401 and challenge.lower().startswith("basic"):
                break
        elif status == 200:
            return True
        if now() - start >= PROOF_SECONDS:
            return False
        sleep(PROOF_EVERY)
    status, _ = fetch_address(address, credential)
    if status != 200:
        return False
    try:
        project = cloudflare_api("GET", project_path(account, name), token)
    except Exception:
        return False
    canonical = (project or {}).get("canonical_deployment") or {}
    return canonical.get("uses_functions") is True


def delete_older_deployments(token: str, account: str, name: str) -> int:
    """Deletes every deployment but the canonical one; returns how many are
    still there afterwards (0 when all went)."""
    remaining = 0
    for _ in range(5):
        try:
            project = cloudflare_api("GET", project_path(account, name), token)
            deployments = cloudflare_api("GET", project_path(account, name) + "/deployments", token)
        except Exception:
            return max(remaining, 1)
        canonical_id = ((project or {}).get("canonical_deployment") or {}).get("id")
        if not canonical_id:
            return max(len(deployments or []) - 1, 1)
        older = []
        for deployment in deployments or []:
            if deployment.get("id") and deployment.get("id") != canonical_id:
                older.append(deployment["id"])
        if not older:
            return 0
        remaining = 0
        deleted_any = False
        for deployment_id in older:
            try:
                cloudflare_api("DELETE", project_path(account, name) + f"/deployments/{deployment_id}?force=true", token)
                deleted_any = True
            except Exception:
                remaining += 1
        if not deleted_any:
            return remaining
    return remaining


# -------------------------------------------------------------------- share

def share(course: str, course_dir: Path, year: int, protect: bool, remove_password: bool,
          include_answer_keys: bool, token: str, account: str) -> int:
    path = marker_path(course_dir, year)
    marker = unit_plan_site.read_json_file(path) if path.exists() else None
    protected = decide_protected(marker, protect, remove_password)
    credential = None
    if protected:
        credential = read_credential()
        if credential is None:
            say_refused(course, "noPassword")
            return 1
    else:
        forget_credential()

    planning_dir = course_dir / ".internal" / "planning"
    problems = unit_plan_site.check(planning_dir, unit_plan_site.bundled_assets_dir())
    if problems:
        print(f"Plantoir found {len(problems)} thing(s) to fix in {course}'s unit plans before they can be shared:")
        for problem in problems:
            print(f"   • {problem.line()}")
        only_size = True
        for problem in problems:
            if problem.kind != "tooLarge":
                only_size = False
        if only_size:
            say_refused(course, "tooLarge")
        else:
            say_refused(course, "checkFound", len(problems), n=len(problems))
        return 1

    if marker and marker.get("name"):
        name = marker["name"]
        remade = deploy.remake_pages_project_if_gone(token, account, name)
        project = remade or wait_for_project(token, account, name)
    else:
        project = make_project(token, account, course, year)
        name = project.get("name")
        write_marker(path, {"name": name, "subdomain": project.get("subdomain"), "year": year})
        project = wait_for_project(token, account, name) or project
    if not project:
        print(f"❌ Cloudflare did not show the project {name}, so nothing was shared.")
        return 1
    subdomain = project.get("subdomain") or (marker or {}).get("subdomain")
    if not subdomain:
        print("❌ Cloudflare gave no address for these plans, so nothing was shared.")
        return 1
    address = f"https://{subdomain}/"

    fail_closed = set_fail_closed(token, account, name)
    keys_in = protected or include_answer_keys
    staging_root = Path(tempfile.mkdtemp(prefix="plantoir-plans-"))
    old_cwd = os.getcwd()
    try:
        public = staging_root / "public"
        staged = unit_plan_site.stage(planning_dir, public, unit_plan_site.bundled_assets_dir(), keys_in)
        if protected:
            (public / "_worker.js").write_text(
                unit_plan_site.worker_js(credential, unit_plan_site.realm_for(course)), encoding="utf-8")
        else:
            (public / "_headers").write_text(unit_plan_site.open_headers(), encoding="utf-8")
        # wrangler uploads a functions/ folder from the folder it runs in,
        # not from the one it is handed, so it runs beside the staged folder.
        os.chdir(staging_root)
        print(f" Sending {staged.units} unit plan(s) to Cloudflare Pages…", flush=True)
        deploy_to_cloudflare(public, name, token, account)
    finally:
        os.chdir(old_cwd)
        shutil.rmtree(staging_root, ignore_errors=True)
        credential_kept = credential
        credential = None
        forget_credential()

    proven = prove(address, protected, credential_kept, token, account, name)
    credential_kept = None
    old_copies = delete_older_deployments(token, account, name)
    shown_protected = protected and proven
    record = {
        "name": name,
        "subdomain": subdomain,
        "address": address,
        "year": year,
        "asked": "protected" if protected else "open",
        "protected": shown_protected,
        "failClosed": fail_closed,
        "answerKeys": "in" if keys_in else "out",
        "answerKeysLeftOut": staged.answer_keys_left_out,
        "lastShared": dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "units": staged.units,
        "oldCopies": old_copies,
    }
    write_marker(path, record)
    if not proven:
        if protected:
            say_refused(course, "notProtectedYet")
        else:
            say_refused(course, "notAnsweringYet")
        return 1
    if old_copies:
        print("⚠️ " + share_words()["refusals"]["oldCopyStillThere"])
    print(f"✅ Shared {course}'s unit plans for {unit_plan_site.year_label(year)}: {address}")
    print(f"{SHARED_MARKER} {code_word(course)} {year} {address} "
          f"protected:{'yes' if shown_protected else 'no'} failClosed:{'yes' if fail_closed else 'no'} "
          f"answerKeys:{record['answerKeys']} units:{staged.units} oldCopies:{old_copies}", flush=True)
    return 0


# --------------------------------------------------------------------- stop

def stop(course: str, course_dir: Path, year: int, token: str, account: str) -> int:
    path = marker_path(course_dir, year)
    marker = unit_plan_site.read_json_file(path) if path.exists() else None
    if not marker or not marker.get("name"):
        print(f"{STOPPED_MARKER} {code_word(course)} {year} none alreadyGone", flush=True)
        return 0
    name = marker["name"]
    address = marker.get("address") or f"https://{marker.get('subdomain') or name + '.pages.dev'}/"
    outcome = _delete_project(token, account, name)
    if outcome == "failed":
        try:
            deployments = cloudflare_api("GET", project_path(account, name) + "/deployments", token)
            for deployment in deployments or []:
                try:
                    cloudflare_api("DELETE", project_path(account, name) + f"/deployments/{deployment.get('id')}?force=true", token)
                except Exception:
                    pass
        except Exception:
            pass
        outcome = _delete_project(token, account, name)
    if outcome == "failed":
        print("❌ " + share_words()["words"]["stopFailed"])
        print(f"{STOPPED_MARKER} {code_word(course)} {year} {address} failed", flush=True)
        return 1
    try:
        path.unlink()
    except OSError:
        pass
    print(f"✅ Stopped sharing {course}'s unit plans for {unit_plan_site.year_label(year)}.")
    print(f"{STOPPED_MARKER} {code_word(course)} {year} {address} {outcome}", flush=True)
    return 0


def _delete_project(token: str, account: str, name: str) -> str:
    try:
        cloudflare_api("DELETE", project_path(account, name), token)
        return "deleted"
    except RuntimeError as error:
        if "error 404" in str(error):
            return "alreadyGone"
        return "failed"
    except Exception:
        return "failed"


# --------------------------------------------------------------------- main

def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Share a course's unit plans to Cloudflare Pages, or stop sharing them.")
    parser.add_argument("--host-os", choices=["windows", "mac", "linux", "unknown"], default="unknown")
    parser.add_argument("--course", required=True)
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--protect", action="store_true")
    group.add_argument("--remove-password", action="store_true")
    parser.add_argument("--include-answer-keys", action="store_true")
    parser.add_argument("--year", type=int, default=None)
    parser.add_argument("--stop", action="store_true")
    parser.add_argument("--non-interactive", action="store_true")
    args = parser.parse_args(argv)
    deploy.NON_INTERACTIVE = bool(args.non_interactive)

    course = args.course
    course_dir = toolchain_paths.COURSES_DIR / course
    try:
        if reference_course.cannot_tell(course_dir):
            print(f"❌ Plantoir cannot tell whether {course} is kept for reference —")
            print(f"   {reference_course.why_cannot_tell(course_dir)}. Nothing was shared.")
            print(f"{REFUSED_MARKER} {code_word(course)} referenceCourse", flush=True)
            return 1
        if reference_course.is_reference(course_dir):
            print("❌ " + reference_course.refusal_sentence(reference_course.display_code(course_dir)))
            print(f"{REFUSED_MARKER} {code_word(course)} referenceCourse", flush=True)
            return 1

        year = args.year if args.year is not None else unit_plan_site.school_year(today())
        token = os.getenv("CLOUDFLARE_API_TOKEN") or ""
        if not token:
            print("❌ No Cloudflare token was handed over, so nothing was shared.")
            return 1
        account = os.getenv("CLOUDFLARE_ACCOUNT_ID") or ""
        if not account:
            account = discover_cloudflare_account(token)
        if args.stop:
            return stop(course, course_dir, year, token, account)
        return share(course, course_dir, year, args.protect, args.remove_password,
                     args.include_answer_keys, token, account)
    except RuntimeError as error:
        # Cloudflare's own words, which never carry the username or password:
        # neither is ever sent to its API.
        print(f" Cloudflare said: {error}")
        say_refused(course, "cloudflareSaidNo")
        return 1
    finally:
        forget_credential()


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        forget_credential()
        sys.exit(130)
