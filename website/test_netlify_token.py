#!/usr/bin/env python3
"""
Where `website/build.py --deploy` finds the Netlify token (#452).

The environment variable first; then the stored credential named
`containerized-quartz-netlify` — the login Keychain item on a Mac, the
generic Credential Manager credential on Windows, read with CredReadW and
decoded as UTF-8 (deploy.ps1's WriteSecret stores Encoding.UTF8 bytes; read
as UTF-16 on 2026-10-03, the same secret made a header Python refused).
Nothing here ever prints a token.

Stdlib only, no network. Every case runs on any machine with the readers
stubbed; one more, on Windows only, writes a THROWAWAY generic credential,
reads it back through the real API and deletes it, which is what proves the
struct layout. It never touches the real credential. No suite discovers
website/ tests (like its neighbours), so run it by hand:

    python -I website/test_netlify_token.py
"""
from __future__ import annotations

import contextlib
import io
import os
import sys
import unittest
import uuid
from pathlib import Path
from unittest import mock

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))

import netlify_deploy  # noqa: E402

SECRET = "nfp_TestTokenNeverReal-é"


def _never(*_arguments, **_keywords):
    raise AssertionError("this reader must not be consulted")


class ReadTokenTests(unittest.TestCase):

    def setUp(self) -> None:
        self.environment = mock.patch.dict(os.environ, {}, clear=False)
        self.environment.start()
        os.environ.pop("NETLIFY_AUTH_TOKEN", None)

    def tearDown(self) -> None:
        self.environment.stop()

    def read_quietly(self) -> tuple[str | None, str | None, str]:
        """(token, exit message, everything printed)."""
        printed = io.StringIO()
        token = message = None
        with contextlib.redirect_stdout(printed), contextlib.redirect_stderr(printed):
            try:
                token = netlify_deploy.read_token()
            except SystemExit as stop:
                message = str(stop.code)
        return token, message, printed.getvalue()

    def test_the_environment_variable_wins_and_no_store_is_asked(self):
        os.environ["NETLIFY_AUTH_TOKEN"] = "  from-the-environment \n"
        with mock.patch.object(netlify_deploy, "_windows_credential_blob", _never), \
                mock.patch.object(netlify_deploy.subprocess, "run", _never):
            for platform in ("win32", "darwin", "linux"):
                with mock.patch.object(netlify_deploy.sys, "platform", platform):
                    self.assertEqual(netlify_deploy.read_token(), "from-the-environment")

    def test_windows_reads_the_launchers_credential_as_utf8_and_prints_nothing(self):
        asked: list[str] = []

        def blob(target: str) -> bytes:
            asked.append(target)
            return (SECRET + "\r\n").encode("utf-8")

        with mock.patch.object(netlify_deploy.sys, "platform", "win32"), \
                mock.patch.object(netlify_deploy, "_windows_credential_blob", blob):
            token, message, printed = self.read_quietly()
        self.assertEqual(token, SECRET)
        self.assertIsNone(message)
        self.assertEqual(printed, "")
        self.assertEqual(asked, ["containerized-quartz-netlify"])

    def test_a_credential_written_as_utf16_is_not_taken_for_the_token(self):
        # UTF-16 bytes are VALID UTF-8 (a NUL after every letter), so a plain
        # decode would send that garbage to Netlify as the token (http.client
        # lets a NUL through; only a line break makes it quote the header in
        # a traceback). It is refused here, and nothing is printed.
        self.assertIsNone(netlify_deploy._token_from_blob("tok".encode("utf-16-le")))
        with mock.patch.object(netlify_deploy.sys, "platform", "win32"), \
                mock.patch.object(netlify_deploy, "_windows_credential_blob",
                                  lambda _target: SECRET.encode("utf-16-le")):
            token, message, printed = self.read_quietly()
        self.assertIsNone(token)
        self.assertIn("UTF-8", message)
        self.assertIn("containerized-quartz-netlify", message)
        self.assertNotIn("TestToken", message)
        self.assertEqual(printed, "")

    def test_bytes_that_are_not_utf8_or_hold_a_line_break_are_no_token(self):
        self.assertIsNone(netlify_deploy._token_from_blob(b"\xff\xfe\xfd"))
        self.assertIsNone(netlify_deploy._token_from_blob(b"tok\nen"))
        self.assertIsNone(netlify_deploy._token_from_blob(b""))
        self.assertIsNone(netlify_deploy._token_from_blob(None))
        self.assertEqual(netlify_deploy._token_from_blob(b"  tok  "), "tok")

    def test_an_absent_credential_names_credential_manager_not_the_keychain(self):
        with mock.patch.object(netlify_deploy.sys, "platform", "win32"), \
                mock.patch.object(netlify_deploy, "_windows_credential_blob", lambda _target: None):
            token, message, printed = self.read_quietly()
        self.assertIsNone(token)
        self.assertIn("Credential Manager", message)
        self.assertIn("containerized-quartz-netlify", message)
        self.assertNotIn("Keychain", message)
        self.assertEqual(printed, "")

    def test_a_mac_asks_the_keychain_and_never_the_windows_reader(self):
        class Empty:
            stdout = ""

        with mock.patch.object(netlify_deploy.sys, "platform", "darwin"), \
                mock.patch.object(netlify_deploy, "_windows_credential_blob", _never), \
                mock.patch.object(netlify_deploy.subprocess, "run", lambda *_a, **_k: Empty()):
            token, message, _printed = self.read_quietly()
        self.assertIsNone(token)
        self.assertIn("Keychain", message)
        self.assertNotIn("Credential Manager", message)

    def test_an_environment_variable_with_a_control_character_is_refused_without_quoting_it(self):
        # A plain dict, since a real environment refuses a NUL outright.
        with mock.patch.object(netlify_deploy.os, "environ", {"NETLIFY_AUTH_TOKEN": "nfp_\x00Secret"}):
            token, message, printed = self.read_quietly()
        self.assertIsNone(token)
        self.assertNotIn("Secret", message)
        self.assertEqual(printed, "")


@unittest.skipUnless(sys.platform == "win32", "CredWriteW / CredReadW are Windows'")
class RealCredentialManagerRoundTrip(unittest.TestCase):
    """A throwaway generic credential, written the way deploy.ps1 writes one
    (UTF-8 bytes, CRED_PERSIST_LOCAL_MACHINE), read back by the reader under
    test, and deleted whatever happened."""

    def test_the_reader_gets_back_what_deploy_ps1_would_have_stored(self):
        import ctypes
        from ctypes import wintypes

        class CREDENTIALW(ctypes.Structure):
            _fields_ = [
                ("Flags", wintypes.DWORD), ("Type", wintypes.DWORD),
                ("TargetName", wintypes.LPWSTR), ("Comment", wintypes.LPWSTR),
                ("LastWritten", wintypes.FILETIME), ("CredentialBlobSize", wintypes.DWORD),
                ("CredentialBlob", ctypes.c_void_p), ("Persist", wintypes.DWORD),
                ("AttributeCount", wintypes.DWORD), ("Attributes", ctypes.c_void_p),
                ("TargetAlias", wintypes.LPWSTR), ("UserName", wintypes.LPWSTR),
            ]

        advapi32 = ctypes.WinDLL("advapi32", use_last_error=True)
        advapi32.CredWriteW.argtypes = [ctypes.POINTER(CREDENTIALW), wintypes.DWORD]
        advapi32.CredWriteW.restype = wintypes.BOOL
        advapi32.CredDeleteW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD]
        advapi32.CredDeleteW.restype = wintypes.BOOL

        target = f"plantoir-test-netlify-{uuid.uuid4()}"
        self.assertNotEqual(target, netlify_deploy.CREDENTIAL_NAME)
        secret = SECRET.encode("utf-8")
        buffer = ctypes.create_string_buffer(secret, len(secret))
        credential = CREDENTIALW()
        credential.Type = 1                       # CRED_TYPE_GENERIC
        credential.TargetName = target
        credential.UserName = "plantoir-test"
        credential.CredentialBlobSize = len(secret)
        credential.CredentialBlob = ctypes.cast(buffer, ctypes.c_void_p)
        credential.Persist = 2                    # CRED_PERSIST_LOCAL_MACHINE
        self.assertTrue(advapi32.CredWriteW(ctypes.byref(credential), 0),
                        f"CredWriteW failed: {ctypes.get_last_error()}")
        try:
            blob = netlify_deploy._windows_credential_blob(target)
            self.assertEqual(blob, secret)
            self.assertEqual(netlify_deploy._token_from_blob(blob), SECRET)
        finally:
            advapi32.CredDeleteW(target, 1, 0)
        self.assertIsNone(netlify_deploy._windows_credential_blob(target))


if __name__ == "__main__":
    unittest.main()
