#!/usr/bin/env python3
"""pages.py: the local test site for tests/ctlhq-browser/run.sh, on 127.0.0.1 only.

Usage: pages.py PORT_FILE
Binds a free port on 127.0.0.1, writes the port number to PORT_FILE, and serves:
  /          a page with a planted console error, one slow script (/slow.js, 800 ms),
             a missing image (404), a performance mark, and a growing array of
             CtlhqGrowing objects for the heap test
  /clean     a plain page with none of those
  /slow.js   answers after 800 ms
"""
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MAIN = b"""<!doctype html><html><head><meta charset="utf-8"><title>planted</title>
<script src="/slow.js"></script></head>
<body style="background:#123456;color:#fff"><h1>planted page</h1>
<img src="/missing.png" alt="">
<script>
class CtlhqGrowing { constructor(i) { this.i = i; this.pad = 'x' + i; } }
window.ctlhqGrow = [];
for (let i = 0; i < 5000; i++) window.ctlhqGrow.push(new CtlhqGrowing(i));
setInterval(() => { for (let i = 0; i < 100; i++) window.ctlhqGrow.push(new CtlhqGrowing(i)); }, 50);
performance.mark('ctlhq-mark');
console.warn('planted-console-warning');
console.error('planted-console-error', 42);
</script></body></html>"""

CLEAN = b"""<!doctype html><html><head><meta charset="utf-8"><title>clean</title><link rel="icon" href="data:,"></head>
<body style="background:#fff"><h1>clean page</h1><script>console.log('only a log line');</script></body></html>"""


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def send(self, code, ctype, body):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        p = self.path.split("?")[0]
        if p == "/":
            self.send(200, "text/html; charset=utf-8", MAIN)
        elif p == "/clean":
            self.send(200, "text/html; charset=utf-8", CLEAN)
        elif p == "/slow.js":
            time.sleep(0.8)
            self.send(200, "text/javascript", b"window.slowLoaded = true;\n")
        else:
            self.send(404, "text/plain", b"not found\n")


def main():
    srv = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    with open(sys.argv[1], "w") as f:
        f.write(str(srv.server_address[1]))
    srv.serve_forever()


if __name__ == "__main__":
    main()
