"""--serve: serves a built --web folder on 127.0.0.1 at a free port and prints
the address. It never opens a browser: whoever runs it opens the address."""

from __future__ import annotations

import functools
import http.server
import sys
from pathlib import Path

from .problems import HelpError


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, format: str, *arguments: object) -> None:  # noqa: A002 - the base class's name
        return


def serve(folder: Path, port: int = 0) -> None:
    if not (folder / "index.html").exists():
        raise HelpError(str(folder) + " holds no built web copy (run --web first)")
    handler = functools.partial(QuietHandler, directory=str(folder))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", port), handler)
    address: str = "http://127.0.0.1:" + str(server.server_address[1]) + "/"
    print("Serving Plantoir Help at " + address + " (Control-C stops it)")
    sys.stdout.flush()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
