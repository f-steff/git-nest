#!/usr/bin/env python3
# Local preview server for the built Jekyll site.
# The site is built with baseurl /git-nest, so every link points at
# /git-nest/... -- this server strips that prefix and serves _site/.
#   python3 tools/serve-site.py [port]
# Then open http://localhost:4000/git-nest/
import http.server
import os
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 4000
SITE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "_site")


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=SITE, **kwargs)

    def translate_path(self, path):
        # Strip the /git-nest baseurl prefix, default to index.html.
        if path.startswith("/git-nest"):
            path = path[len("/git-nest"):]
        if path in ("", "/"):
            path = "/index.html"
        return super().translate_path(path)

    def log_message(self, fmt, *args):
        print("[%s] %s" % (self.address_string(), fmt % args))


if __name__ == "__main__":
    os.chdir(SITE)
    http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
