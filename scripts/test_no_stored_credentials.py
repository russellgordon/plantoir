#!/usr/bin/env python3
"""
No file in the repository stores a credential-shaped literal (GitHub #844).

On 2026-11-13 GitGuardian reported a "Basic Auth String exposed on GitHub" in
this repository. It was two redaction fixtures added by #709: an
`Authorization: Basic` header whose base64 decoded to an invented username and
password, and an address with that pair written into it. Nothing real leaked,
but a scanner cannot tell an invented pair from a live one, and neither can a
person reading the alert. The fixtures are now ASSEMBLED by the tests from
pieces that say what they are (`contracts/shared-rules.json` ->
`problemReportRedaction.assembledInput`), and this test keeps every such shape
out of every tracked file, so a new one fails here before a scanner sees it:

  * an address with a username and password written into it, before an `@`
    and the host, unless the host is a reserved example name (`.example`, `.invalid`,
    `.test`, `.localhost`, `localhost`, or example.com/.net/.org), which no
    scanner reads as live and which can never be a real site;
  * an `Authorization`-style `Basic <base64>` whose base64 decodes to
    `something:something` (a word such as "Basic French" decodes to nothing
    and is left alone);
  * the prefixed tokens of services whose detectors key on the prefix:
    Netlify `nfp_`, GitHub `ghp_`/`gho_`/`ghu_`/`ghs_`/`ghr_` and
    `github_pat_`, AWS `AKIA`, Slack `xox?-`, and a PEM private key block.

ALLOWED names each permitted value by its SHA-256, never by the value itself,
since this file would otherwise hold the literal it exists to keep out. Every
entry says where the value is and why it may stay, and an entry that no longer
matches anything fails the test, so the list cannot outlive its reasons.

The self-tests build their samples at run time for the same reason.

Files are listed with `git ls-files` when git can answer, which is what ships;
otherwise the tree is walked, skipping build output and vendored downloads.
Pure stdlib; no Docker, no network. Windows' PythonToolchainTests discovers
and runs it. Run with:

    python3 scripts/test_no_stored_credentials.py
"""
import base64
import binascii
import hashlib
import os
import re
import subprocess
import unittest
from pathlib import Path

REPOSITORY = Path(__file__).resolve().parents[1]

# Folders that are never part of what ships: build output and caches. Used
# only when git cannot list files. A `Vendor` folder's own files (the fetch
# scripts) are tracked and scanned; its subfolders are the downloads those
# scripts fetch, and are not.
SKIPPED_FOLDERS = {".git", "node_modules", "bin", "obj", "__pycache__", "DerivedData"}
DOWNLOADS_FOLDER = "Vendor"

# Reserved by RFC 2606 and RFC 6761. Each with its leading dot, so that
# notexample.com is not taken for example.com; the bare names are below.
RESERVED_HOST_SUFFIXES = (".example", ".invalid", ".test", ".localhost",
                          ".example.com", ".example.net", ".example.org")
RESERVED_HOSTS = {"localhost", "example.com", "example.net", "example.org"}

# Case-insensitive, as LogRedactor's own rules are: HTTPS:// and
# `authorization: basic` are the same thing to a scanner and to a reader.
URL_USERINFO = re.compile(r"\b[a-z][a-z0-9+.\-]*://([^\s/:@\"'<>`\\]+):([^\s/@\"'<>`\\]+)@([A-Za-z0-9.\-]+)",
                          re.IGNORECASE)
# A known false positive, kept rather than worked round: a dictionary word after
# "Basic" can happen to be base64 for something with a colon in it ("Basic
# Oily" decodes to one). None is in the tree. If one arrives, it goes on
# ALLOWED by its SHA-256 with where it is and why, like any other.
BASIC_HEADER = re.compile(r"\bBasic\s+([A-Za-z0-9+/]{4,}={0,2})(?![A-Za-z0-9+/=])", re.IGNORECASE)
PREFIXED_TOKENS = [
    ("netlifyToken", re.compile(r"\bnfp_[A-Za-z0-9]{16,}")),
    ("githubToken", re.compile(r"\bgh[pousr]_[A-Za-z0-9]{30,}")),
    ("githubFineGrainedToken", re.compile(r"\bgithub_pat_[A-Za-z0-9_]{20,}")),
    ("awsAccessKey", re.compile(r"\bAKIA[0-9A-Z]{16}\b")),
    ("slackToken", re.compile(r"\bxox[abprs]-[A-Za-z0-9\-]{10,}")),
    ("privateKey", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
]

# (kind, SHA-256 of the matched value): where it is, and why it may stay.
ALLOWED = {
    ("netlifyToken", "81e33c1a467596d01b67858fe92313c2f16349c4ff81927c25c290d53642c582"):
        "contracts/shared-rules.json, problemReportRedaction's netlifyToken case: an alphabet walk "
        "after the nfp_ prefix, which is what that rule keys on, so its fixture must carry one.",
    ("netlifyToken", "bd2e521c2ae37c66d78407abd9b9bdbb1f316a0dd62a5573aa62cad8e6be342b"):
        "windows-app/Plantoir.Tests/ProblemReportTests.cs: nfp_ and then the alphabet, a run "
        "transcript proved redacted on disk.",
    ("netlifyToken", "b82579ec409aa31a39a21a1d9ccec245d4a8b67cc97feaa633f07a05d52b5cca"):
        "website/test_netlify_token.py: a value that says it is a test token and never real.",
}


def fingerprint(value):
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def is_reserved_host(host):
    host = host.lower().rstrip(".")
    if host in RESERVED_HOSTS:
        return True
    return host.endswith(RESERVED_HOST_SUFFIXES)


def decoded_pair(encoded):
    """The `user:password` a Basic header's base64 carries, or None when it carries none."""
    padded = encoded + "=" * (-len(encoded) % 4)
    try:
        raw = base64.b64decode(padded, validate=True)
        text = raw.decode("utf-8")
    except (binascii.Error, ValueError, UnicodeDecodeError):
        return None
    if ":" not in text or not text.isprintable():
        return None
    return text


def findings_in_text(text):
    """(line number, kind, matched value) for each credential shape in `text`."""
    found = []
    for number, line in enumerate(text.splitlines(), 1):
        for match in URL_USERINFO.finditer(line):
            if not is_reserved_host(match.group(3)):
                found.append((number, "urlUserinfo", match.group(0)))
        for match in BASIC_HEADER.finditer(line):
            if decoded_pair(match.group(1)) is not None:
                found.append((number, "basicAuthHeader", match.group(1)))
        for kind, pattern in PREFIXED_TOKENS:
            for match in pattern.finditer(line):
                found.append((number, kind, match.group(0)))
    return found


def listed_files(root):
    """Every file under `root` that ships: git's list when git can answer, else a walk."""
    try:
        listing = subprocess.run(["git", "-C", str(root), "ls-files", "-z"],
                                 capture_output=True, check=True, timeout=120).stdout
        names = [name for name in listing.decode("utf-8", "replace").split("\0") if name]
        if names:
            return [root / name for name in names]
    except (OSError, subprocess.SubprocessError):
        pass
    files = []
    for folder, subfolders, names in os.walk(root):
        kept = []
        if Path(folder).name == DOWNLOADS_FOLDER:
            subfolders[:] = []
        for subfolder in subfolders:
            if subfolder in SKIPPED_FOLDERS or subfolder.startswith(".build") or subfolder.endswith(".xcodeproj"):
                continue
            kept.append(subfolder)
        subfolders[:] = kept
        for name in names:
            files.append(Path(folder) / name)
    return files


def findings(root):
    """(relative path, line number, kind, matched value) for every shape not on ALLOWED, and the
    ALLOWED keys that were seen."""
    found = []
    seen_allowed = set()
    for path in listed_files(root):
        try:
            data = path.read_bytes()
        except OSError:
            continue
        if b"\0" in data[:8192]:
            continue
        text = data.decode("utf-8", "replace")
        for number, kind, value in findings_in_text(text):
            key = (kind, fingerprint(value))
            if key in ALLOWED:
                seen_allowed.add(key)
                continue
            found.append((path.relative_to(root).as_posix(), number, kind, value))
    return found, seen_allowed


_REPOSITORY_FINDINGS = None


def repository_findings():
    """findings(REPOSITORY), worked out once for both tests that read it."""
    global _REPOSITORY_FINDINGS
    if _REPOSITORY_FINDINGS is None:
        _REPOSITORY_FINDINGS = findings(REPOSITORY)
    return _REPOSITORY_FINDINGS


def masked(value):
    return f"<{len(value)} characters, starting {value[:4]!r}>"


class TheShapesAreRecognised(unittest.TestCase):
    """The detector itself, on samples built at run time so that this file stores none."""

    def test_a_basic_header_carrying_a_pair_is_found(self):
        encoded = base64.b64encode(("someone" + ":" + "invented-words").encode()).decode()
        line = "curl -H 'Authorization: Basic " + encoded + "' https://plans.example"
        self.assertEqual([kind for _, kind, _ in findings_in_text(line)], ["basicAuthHeader"])

    def test_an_address_with_a_pair_and_a_real_looking_host_is_found(self):
        line = "Opening https" + "://someone:" + "invented-words" + "@plans-2026.pages.dev/"
        self.assertEqual([kind for _, kind, _ in findings_in_text(line)], ["urlUserinfo"])

    def test_a_reserved_example_host_is_left_alone(self):
        for host in ("plans.example", "site.invalid", "a.test", "localhost", "www.example.com", "example.org"):
            line = "https" + "://someone:" + "invented-words" + "@" + host + "/"
            self.assertEqual(findings_in_text(line), [], host)

    def test_a_host_that_only_ends_in_an_example_name_is_found(self):
        line = "https" + "://someone:" + "invented-words" + "@notexample.com/"
        self.assertEqual([kind for _, kind, _ in findings_in_text(line)], ["urlUserinfo"])

    def test_case_does_not_hide_either_shape(self):
        line = "HTTPS" + "://someone:" + "invented-words" + "@plans-2026.pages.dev/"
        self.assertEqual([kind for _, kind, _ in findings_in_text(line)], ["urlUserinfo"])
        encoded = base64.b64encode(("someone" + ":" + "invented-words").encode()).decode()
        line = "authorization: basic " + encoded
        self.assertEqual([kind for _, kind, _ in findings_in_text(line)], ["basicAuthHeader"])

    def test_the_contract_templates_are_left_alone(self):
        self.assertEqual(findings_in_text("Opening https://{user}:{password}@plans.example/"), [])
        self.assertEqual(findings_in_text("curl -H 'Authorization: Basic {basic}' https://plans.example"), [])

    def test_the_word_basic_before_an_ordinary_word_is_left_alone(self):
        for line in ("Shared Basic French unit plans and Basic Skills.",
                     "B3. Understanding Basic Concepts", "the Basic Multilingual Plane"):
            self.assertEqual(findings_in_text(line), [], line)

    def test_a_prefixed_token_is_found(self):
        line = "token " + "gh" + "p_" + "Q" * 36
        self.assertEqual([kind for _, kind, _ in findings_in_text(line)], ["githubToken"])
        line = "NETLIFY=" + "nf" + "p_" + "Z" * 20
        self.assertEqual([kind for _, kind, _ in findings_in_text(line)], ["netlifyToken"])


class NoFileStoresACredential(unittest.TestCase):

    def test_no_tracked_file_holds_a_credential_shaped_literal(self):
        found, _ = repository_findings()
        lines = [f"{path}:{number}  {kind} {masked(value)}" for path, number, kind, value in found]
        self.assertEqual(
            lines, [],
            "A credential-shaped literal is stored in the repository. Assemble it in the test from "
            "pieces that say what they are (problemReportRedaction.assembledInput), use a reserved "
            "example host, or, for a fixture that must keep its shape, add its SHA-256 to ALLOWED "
            "with where it is and why:\n  " + "\n  ".join(lines))

    def test_every_allowed_value_is_still_there(self):
        _, seen = repository_findings()
        stale = []
        for key, why in ALLOWED.items():
            if key not in seen:
                stale.append(f"{key[0]} {key[1][:12]}: {why}")
        self.assertEqual(stale, [], "ALLOWED names a value no file holds any more; remove the entry")


if __name__ == "__main__":
    unittest.main(verbosity=2)
