#!/usr/bin/env python3
"""Serve _site/ locally WITH HTTP Range support.

`quarto preview` answers video requests with 200 and the whole file, never
206 Partial Content. Safari then can't seek, so the skip/scrub buttons in the
player (especially fullscreen) do nothing. GitHub Pages supports ranges, so
the published site is fine; use this to test video locally:

    quarto render && python3 scripts/serve_site.py   # http://localhost:8000
"""
import os, re, sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer


class H(SimpleHTTPRequestHandler):
    # Python's table has no .vtt; browsers want text/vtt for caption tracks.
    extensions_map = {**SimpleHTTPRequestHandler.extensions_map, ".vtt": "text/vtt"}

    def send_head(self):
        rng = self.headers.get("Range")
        path = self.translate_path(self.path)
        m = re.match(r"bytes=(\d*)-(\d*)$", rng or "")
        if not (m and os.path.isfile(path)):
            return super().send_head()
        size = os.path.getsize(path)
        a, b = m.groups()
        start = int(a) if a else size - int(b)
        end = int(b) if a and b else size - 1
        end = min(end, size - 1)
        self.send_response(206)
        self.send_header("Content-Type", self.guess_type(path))
        self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.send_header("Content-Length", str(end - start + 1))
        self.end_headers()
        f = open(path, "rb")
        f.seek(start)
        self._left = end - start + 1
        return f

    def copyfile(self, src, dst):
        left = getattr(self, "_left", None)
        self._left = None
        try:
            while True:
                n = 65536 if left is None else min(65536, left)
                buf = src.read(n) if n else b""
                if not buf:
                    break
                dst.write(buf)
                if left is not None:
                    left -= len(buf)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def end_headers(self):
        self.send_header("Accept-Ranges", "bytes")
        super().end_headers()


os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "_site"))
port = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
ThreadingHTTPServer(("", port), H).serve_forever()
