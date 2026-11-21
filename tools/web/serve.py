#!/usr/bin/env python3
"""Server locale per provare l'edizione web: MIME corretto per wasm, gzip come GitHub Pages.
Uso: python3 tools/web/serve.py [cartella] [porta]   (predefiniti: build/web, 8060)"""
import gzip, http.server, mimetypes, os, sys

mimetypes.add_type("application/wasm", ".wasm")
mimetypes.add_type("application/octet-stream", ".pck")
COMPRESSIBLE = (".wasm", ".js", ".html", ".json", ".css", ".svg")

class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def do_GET(self):
        path = self.translate_path(self.path.split("?")[0])
        if os.path.isdir(path):
            path = os.path.join(path, "index.html")
        if (path.endswith(COMPRESSIBLE) and "gzip" in self.headers.get("Accept-Encoding", "")
                and os.path.isfile(path)):
            with open(path, "rb") as f:
                body = gzip.compress(f.read(), 6)
            self.send_response(200)
            self.send_header("Content-Type", self.guess_type(path))
            self.send_header("Content-Encoding", "gzip")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            super().do_GET()

if __name__ == "__main__":
    root = sys.argv[1] if len(sys.argv) > 1 else "build/web"
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 8060
    os.chdir(root)
    http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
