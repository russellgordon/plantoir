#!/usr/bin/env python3
"""
Share a course's unit plans to Cloudflare Pages, or stop sharing them (#709).

Run by `deploy.sh <CODE> --plans`, inside the website builder (and natively by
Windows' runtime), never by hand in the ordinary course of things:

    python3 /opt/scripts/share_plan.py --host-os mac --course <CODE>
        [--protect | --remove-password] [--include-answer-keys] [--year YYYY]
        [--stop] [--new-password-waiting] [--non-interactive]

The rules are contracts/shared-rules.json -> unitPlanning.share, and the
order below is the one that keeps the worst fault away: a plan a teacher
believes is protected that can be read without the password. So nothing is
called shared until the address has been fetched and answered as promised
(`proof`), and every older deployment is deleted afterwards, because each
keeps an address of its own that served an open copy after a protected
share (measured 2026-11-12, `oldDeployments`).

The username and password reach this program in one file the launcher makes
for each share (a fresh 0600 file in its own 0700 folder) and names with
--credential-file; it is read first, deleted at once, and deleted again on
every way out, a SIGTERM or SIGHUP included. Neither is ever printed, written
to the marker, or passed on. Only a
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
import secrets
import re
import shutil
import signal
import socket
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
# The file the launcher left the username and password in, named by
# --credential-file: a fresh one per share, 0600 inside its own 0700 folder
# (the director's ruling on the #709 review, M4: two courses shared at once
# from one website builder must never read each other's). None when no file
# was named. A module value so the tests can point it elsewhere.
CRED_FILE: Path | None = None

SHARED_MARKER = "PLANTOIR_PLAN_SHARED:"
REFUSED_MARKER = "PLANTOIR_PLAN_REFUSED:"
STOPPED_MARKER = "PLANTOIR_PLAN_STOPPED:"
PASSWORD_SAVED_MARKER = "PLANTOIR_PLAN_PASSWORD_SAVED:"

# What fetch_address puts in its headers when the name did not resolve.
GONE_KEY = "x-plantoir-gone"

# The statuses Cloudflare answers for a Pages project that no longer exists
# (measured 2026-11-12: 522 and 530, "error code: 1016").
GONE_STATUSES = (522, 530)

# A credential folder left by a share that was killed outright: the
# launcher's own name for one (mktemp -d /tmp/plan_cred.XXXXXX) and the age
# past which no share can still be reading it.
STALE_CREDENTIAL_FOLDER = re.compile(r"^plan_cred\.[A-Za-z0-9]{6}$")
STALE_SECONDS = 600
CREDENTIAL_ROOT = Path("/tmp")

PROOF_SECONDS = 60
STOP_SECONDS = 30
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
    except urllib.error.URLError as error:
        # The one failure that is evidence: the name no longer resolves,
        # which is how a deleted Pages project ends (measured, after about
        # 100 s). Every other failure says nothing either way.
        if isinstance(error.reason, socket.gaierror):
            return None, {GONE_KEY: "nameNotFound"}
        return None, {}
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
    None when it is missing or not one username:password line. The password
    is used exactly as typed: spaces at either end are part of it."""
    if CRED_FILE is None:
        return None
    try:
        raw = CRED_FILE.read_text(encoding="utf-8")
    except OSError:
        return None
    finally:
        forget_credential()
    line = raw
    if line.endswith("\n"):
        line = line[:-1]
    if "\n" in line or "\r" in line or ":" not in line:
        return None
    username, _, password = line.partition(":")
    if not username or not password:
        return None
    return unit_plan_site.credential_b64(username, password)


PRE_READ_CREDENTIAL: str | None = None


def _leave_on_signal(number, frame):
    raise SystemExit(128 + number)


def clear_away_stale_credential_folders() -> None:
    """A share killed outright (SIGKILL) leaves its credential folder behind.
    Removed by the NEXT share: only folders named the way the launcher names
    them (plan_cred. and six letters or digits), only ones older than
    STALE_SECONDS, which no share can still be reading, and never this
    share's own."""
    try:
        entries = list(os.scandir(CREDENTIAL_ROOT))
    except OSError:
        return
    for entry in entries:
        if not STALE_CREDENTIAL_FOLDER.match(entry.name):
            continue
        if CRED_FILE is not None and Path(entry.path) == CRED_FILE.parent:
            continue
        try:
            if not entry.is_dir(follow_symlinks=False):
                continue
            if time.time() - entry.stat(follow_symlinks=False).st_mtime < STALE_SECONDS:
                continue
            shutil.rmtree(entry.path, ignore_errors=True)
        except OSError:
            continue


def forget_credential() -> None:
    """Deletes the credential file and the private folder the launcher made
    for it, on every way out."""
    if CRED_FILE is None:
        return
    try:
        CRED_FILE.unlink()
    except OSError:
        pass
    if CRED_FILE.parent.name.startswith("plan_cred."):
        try:
            CRED_FILE.parent.rmdir()
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


def prove(address: str, protected: bool, credential: str | None, token: str, account: str, name: str,
          share_id: str) -> bool:
    """unitPlanning.share.proof: the address answers as this share promises,
    a path the share does not hold answers 404 from the worker, and the
    project says its current deployment runs the worker. Every check is
    retried together until all hold or PROOF_SECONDS pass, because the main
    address can go on answering the PREVIOUS deployment for a moment
    (measured up to 2.2 s): after Change Password the old deployment also
    answers 401 without a password, and only the new password's 200 tells
    the two apart."""
    start = now()
    while True:
        if _proven_once(address, protected, credential, token, account, name, share_id):
            return True
        if now() - start >= PROOF_SECONDS:
            return False
        sleep(PROOF_EVERY)


def _proven_once(address: str, protected: bool, credential: str | None, token: str, account: str, name: str,
                 share_id: str) -> bool:
    # Only an answer from THIS share's deployment counts (review M1): the
    # main address answers the previous one for a moment, and when the two
    # answer alike only the share's own header tells them apart.
    status, headers = fetch_address(address)
    if headers.get("x-plantoir-share", "") != share_id:
        return False
    if protected:
        challenge = headers.get("www-authenticate", "")
        if status != 401 or not challenge.lower().startswith("basic"):
            return False
        status, headers = fetch_address(address, credential)
        if status != 200 or headers.get("x-plantoir-share", "") != share_id:
            return False
    elif status != 200:
        return False
    status, headers = fetch_address(address + "plantoir-not-shared-" + secrets.token_hex(4), credential)
    if status != 404 or headers.get("cache-control", "") != "no-store":
        return False
    if headers.get("x-plantoir-share", "") != share_id:
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

def utc_now_text() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def older_deployment_count(token: str, account: str, name: str) -> int:
    """How many deployments are not the canonical one, before any is
    deleted; 1 when that cannot be told, so the bar says an older copy may
    still answer rather than nothing."""
    try:
        project = cloudflare_api("GET", project_path(account, name), token)
        deployments = cloudflare_api("GET", project_path(account, name) + "/deployments", token)
    except Exception:
        return 1
    canonical_id = ((project or {}).get("canonical_deployment") or {}).get("id")
    count = 0
    for deployment in deployments or []:
        if deployment.get("id") and deployment.get("id") != canonical_id:
            count += 1
    return count


def one_line(text: str) -> str:
    return text.replace("\r", " ").replace("\n", " ")


def _note_for(document, place: str, protected: bool) -> str:
    """The words beside a name in the terminal's lists, as the tables' Note
    column says them (startingPlace.mark, startingPlace.warns)."""
    words = share_words()["wordsForTheTables"]
    mark = unit_plan_site.mark_of(document)
    if mark == "cannotShare":
        return words["noteCannotShare"]
    if unit_plan_site.warns(document, place, protected):
        return words["noteOpenKey"]
    if mark == "answerKey":
        return words["noteAnswerKey"]
    if mark == "mayBeAnswerKey":
        return words["noteMayBe"]
    return ""


def confirm_the_share(course: str, year: int, listing, settled: dict, protected: bool,
                      include_answer_keys: bool) -> bool:
    """unitPlanning.share.openShareLists: before EVERY share goes out (#833),
    the plan's documents in two lists, where each starts, and the share goes
    only on a yes (under --non-interactive, the remembered choices and the
    rule decide and the lists are printed)."""
    words = share_words()["openShareLists"]
    marks = words["markers"]
    tables = share_words()["wordsForTheTables"]
    shared_documents = []
    held_documents = []
    for document in sorted(listing.documents, key=lambda item: item.place):
        if settled.get(document.place) == unit_plan_site.SHARED:
            shared_documents.append(document)
        else:
            held_documents.append(document)
    # Each document twice: the lines a person reads at a terminal, and one
    # marker line the app reads (and keeps out of the console) to fill the
    # two tables, so the app never guesses at the console's own lines.
    print(f"{marks['begin']} {year} protected:{'yes' if protected else 'no'} "
          f"tick:{'yes' if include_answer_keys else 'no'} ownFiles:{listing.own_files}")
    print(words["sharedHeadingProtected"] if protected else words["sharedHeading"])
    if not shared_documents:
        print("   " + words["none"])
    for document in shared_documents:
        note = _note_for(document, unit_plan_site.SHARED, protected)
        print(f"   • {document.place}" + (f" ({note})" if note else ""))
        print(f"{marks['document']} {json.dumps(document.line(unit_plan_site.SHARED), ensure_ascii=True)}")
    print(words["leftOutHeading"])
    if not held_documents:
        print("   " + words["none"])
    for document in held_documents:
        note = _note_for(document, unit_plan_site.NOT_SHARED, protected)
        print(f"   • {document.place}" + (f" ({note})" if note else ""))
        print(f"{marks['document']} {json.dumps(document.line(unit_plan_site.NOT_SHARED), ensure_ascii=True)}")
    print(tables["ownFilesLine"].replace("{n}", str(listing.own_files)))
    print(words["byName"])
    print(marks["end"], flush=True)
    if deploy.NON_INTERACTIVE:
        print(words["nonInteractive"], flush=True)
        return True
    try:
        answer = input(words["questionProtected"] if protected else words["question"])
    except (EOFError, OSError):
        answer = ""
    return answer.strip().lower() in ("y", "yes")


def carried(before: dict | None, choices: dict, proven: bool = False) -> dict:
    """The keys every marker this share writes carries over (#833): the
    remembered choices, and a new password still waiting for a share until
    one proves the address."""
    out = {"documents": choices}
    if not proven and (before or {}).get("newPasswordWaiting") is True:
        out["newPasswordWaiting"] = True
    return out


def note_new_password(course: str, course_dir: Path, year: int) -> int:
    """unitPlanning.share.changePasswordCases: Change Password saved a new
    password and shared nothing. The year's marker says the new password is
    waiting when the plans have an address, so the bar says so until a share
    proves it; with no address there is nothing to wait for."""
    path = marker_path(course_dir, year)
    marker = unit_plan_site.read_json_file(path) if path.exists() else None
    if not marker or not marker.get("address"):
        print(f"{PASSWORD_SAVED_MARKER} {code_word(course)} {year} notShared", flush=True)
        return 0
    updated = dict(marker)
    updated["newPasswordWaiting"] = True
    write_marker(path, updated)
    print("✅ " + share_words()["words"]["newPasswordNotInUse"])
    print(f"{PASSWORD_SAVED_MARKER} {code_word(course)} {year} waiting", flush=True)
    return 0


def share(course: str, course_dir: Path, year: int, protect: bool, remove_password: bool,
          include_answer_keys: bool, token: str, account: str) -> int:
    path = marker_path(course_dir, year)
    marker = unit_plan_site.read_json_file(path) if path.exists() else None
    protected = decide_protected(marker, protect, remove_password)
    credential = None
    if protected:
        credential = PRE_READ_CREDENTIAL
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

    # Advice never stops a share (unitPlanning.share.advice, #833).
    for note in unit_plan_site.advice(planning_dir):
        print(f"💡 {note.detail}")

    # The documents the teacher sees, where each starts, and the choices
    # remembered from the last share of this year's plans (#833).
    listing = unit_plan_site.list_documents(planning_dir, unit_plan_site.bundled_assets_dir())
    remembered = unit_plan_site.remembered_choices(marker)
    if unit_plan_site.refused_choices(remembered, listing):
        say_refused(course, "listNotShareable")
        return 1
    settled = unit_plan_site.settle(listing, protected, include_answer_keys, remembered)

    share_id = secrets.token_hex(8)
    staging_root = Path(tempfile.mkdtemp(prefix="plantoir-plans-"))
    old_cwd = os.getcwd()
    try:
        public = staging_root / "public"
        if not confirm_the_share(course, year, listing, settled, protected, include_answer_keys):
            print(share_words()["openShareLists"]["declined"])
            print(f"{REFUSED_MARKER} {code_word(course)} notConfirmed", flush=True)
            return 0
        # The app writes the places the teacher settled into the marker
        # before it answers (rememberedChoices): read them again now, and
        # share exactly the documents that were listed and settle in Shared.
        marker = unit_plan_site.read_json_file(path) if path.exists() else None
        chosen = unit_plan_site.remembered_choices(marker)
        if unit_plan_site.refused_choices(chosen, listing):
            say_refused(course, "listNotShareable")
            return 1
        settled = unit_plan_site.settle(listing, protected, include_answer_keys, chosen)
        choices = unit_plan_site.kept_choices(chosen, listing)
        staged = unit_plan_site.stage(planning_dir, public, unit_plan_site.bundled_assets_dir(),
                                      include_answer_keys, settled=settled)
        keys_in = staged.answer_keys_shared > 0

        if marker and marker.get("name"):
            name = marker["name"]
            remade = deploy.remake_pages_project_if_gone(token, account, name)
            project = remade or wait_for_project(token, account, name)
        else:
            project = make_project(token, account, course, year)
            name = project.get("name")
            first = {"name": name, "subdomain": project.get("subdomain"), "year": year}
            first.update(carried(marker, choices))
            write_marker(path, first)
            project = wait_for_project(token, account, name) or project
        if not project:
            print(f"❌ Cloudflare did not show the project {name}, so nothing was shared.")
            return 1
        subdomain = project.get("subdomain") or (marker or {}).get("subdomain")
        if not subdomain:
            print("❌ Cloudflare gave no address for these plans, so nothing was shared.")
            return 1
        address = f"https://{subdomain}/"

        # Before anything is sent (review H1): the marker says the least this
        # share can promise, so a Cancel or a crash at any later point leaves
        # the bar saying no more than the site does: the address is on it, so
        # Stop Sharing is offered; it is never protected until proven; and the
        # answer keys are "in" when this share or the one before carried them.
        # unitPlanning.share.interruptionCases.
        before = marker or {}
        sending = {
            "name": name, "subdomain": subdomain, "address": address, "year": year,
            "state": "sending",
            "asked": "protected" if protected else "open",
            "protected": False,
            "failClosed": bool(before.get("failClosed", False)),
            "answerKeys": "in" if (keys_in or before.get("answerKeys") == "in") else "out",
            # 0 while the address may still serve a key the last share carried
            # (fix review M1): the bar never says keys are left out then.
            "answerKeysLeftOut": 0 if (keys_in or before.get("answerKeys") == "in") else staged.answer_keys_left_out,
            "lastShared": before.get("lastShared") or utc_now_text(),
            "units": staged.units,
            "oldCopies": max(int(before.get("oldCopies") or 0), 1 if before.get("address") else 0),
            "documentsShared": staged.documents_shared,
            "documentsHeldBack": staged.documents_held_back,
        }
        sending.update(carried(before, choices))
        write_marker(path, sending)

        fail_closed = set_fail_closed(token, account, name)
        # Both kinds of share carry the worker: it answers only the files this
        # share holds, because Cloudflare's edge cache went on serving a file
        # a later share left out (measured 2026-11-12, unitPlanning.share
        # .edgeCache). An open share keeps _headers as well, which is what the
        # static files would carry if the worker were ever passed by.
        (public / "_worker.js").write_text(
            unit_plan_site.worker_js(credential if protected else None,
                                     unit_plan_site.realm_for(course), staged.files, share_id=share_id),
            encoding="utf-8")
        if not protected:
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

    proven = prove(address, protected, credential_kept, token, account, name, share_id)
    credential_kept = None
    shown_protected = protected and proven
    record = {
        "name": name,
        "subdomain": subdomain,
        "address": address,
        "year": year,
        "state": "shared" if proven else "sending",
        "asked": "protected" if protected else "open",
        "protected": shown_protected,
        "failClosed": fail_closed,
        "answerKeys": "in" if (keys_in or not proven and (marker or {}).get("answerKeys") == "in") else "out",
        "answerKeysLeftOut": (0 if (keys_in or not proven and (marker or {}).get("answerKeys") == "in")
                              else staged.answer_keys_left_out),
        "lastShared": utc_now_text(),
        "units": staged.units,
        # Counted before the deletes, so a Cancel during them leaves the bar
        # saying an older copy may still answer (review M2).
        "oldCopies": older_deployment_count(token, account, name),
        "documentsShared": staged.documents_shared,
        "documentsHeldBack": staged.documents_held_back,
    }
    # A new password waiting for a share stops waiting only once the
    # address is proved (changePasswordCases).
    record.update(carried(marker, choices, proven=proven))
    write_marker(path, record)
    old_copies = delete_older_deployments(token, account, name)
    record["oldCopies"] = old_copies
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
          f"answerKeys:{record['answerKeys']} units:{staged.units} oldCopies:{old_copies} "
          f"documents:{staged.documents_shared} heldBack:{staged.documents_held_back}", flush=True)
    return 0


# --------------------------------------------------------------------- stop

def what_the_address_says(address: str) -> str:
    """unitPlanning.share.stopCases: "plans" while it answers as a plan site
    (200, 401, or anything carrying the worker's share header), "gone" only
    on an answer that proves the site is gone (522 or 530, or the name no
    longer resolving), and "unknown" for anything else: no answer at all, a
    school filter's 403, a 5xx, a 404."""
    status, headers = fetch_address(address)
    if headers.get("x-plantoir-share") or status in (200, 401):
        return "plans"
    if status in GONE_STATUSES or headers.get(GONE_KEY):
        return "gone"
    return "unknown"


def stop(course: str, course_dir: Path, year: int, token: str, account: str) -> int:
    """unitPlanning.share.stopSharing: stopped is said only once the address
    was fetched and no longer answers with the plans (review M5). A delete
    Cloudflare answers with 404 proves nothing on its own: the token may now
    reach another account, and the site in the first one is still up."""
    path = marker_path(course_dir, year)
    marker = unit_plan_site.read_json_file(path) if path.exists() else None
    if not marker or not marker.get("name"):
        print(f"{STOPPED_MARKER} {code_word(course)} {year} none alreadyGone", flush=True)
        return 0
    name = marker["name"]
    address = marker.get("address") or f"https://{marker.get('subdomain') or name + '.pages.dev'}/"
    stopping = dict(marker)
    stopping["state"] = "stopping"
    stopping["address"] = address
    write_marker(path, stopping)
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
        # Cloudflare refused the delete: the site is up as it was.
        write_marker(path, marker)
        print("❌ " + share_words()["words"]["stopFailed"])
        print(f"{STOPPED_MARKER} {code_word(course)} {year} {address} failed", flush=True)
        return 1
    # Stopped only on an answer that proves it (fix review M2): a share
    # that cannot tell keeps the marker, the row and the saved password.
    start = now()
    while what_the_address_says(address) != "gone":
        if now() - start >= STOP_SECONDS:
            print("❌ " + share_words()["words"]["stopUnconfirmed"])
            print(f"{STOPPED_MARKER} {code_word(course)} {year} {address} unconfirmed", flush=True)
            return 1
        sleep(PROOF_EVERY)
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
    parser.add_argument("--new-password-waiting", action="store_true",
                        help="Change Password saved a new password and shared nothing (#833): say so in the year's marker.")
    parser.add_argument("--credential-file", default=None,
                        help="The file the launcher left the username and password in (a path, never the secret).")
    args = parser.parse_args(argv)
    deploy.NON_INTERACTIVE = bool(args.non_interactive)
    global CRED_FILE
    CRED_FILE = Path(args.credential_file) if args.credential_file else None
    # The app's Cancel ends a share with SIGTERM; a closed terminal sends
    # SIGHUP. Both leave through the same finally as ^C does, so the
    # credential file and its folder go (fix review LOW).
    for number in (signal.SIGTERM, signal.SIGHUP):
        try:
            signal.signal(number, _leave_on_signal)
        except (ValueError, OSError, AttributeError):
            pass
    clear_away_stale_credential_folders()
    # Read FIRST, before anything that could wait on the network.
    global PRE_READ_CREDENTIAL
    PRE_READ_CREDENTIAL = read_credential() if CRED_FILE is not None else None

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
        if args.new_password_waiting:
            forget_credential()
            return note_new_password(course, course_dir, year)
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
        PRE_READ_CREDENTIAL = None


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        forget_credential()
        sys.exit(130)
