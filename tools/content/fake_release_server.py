#!/usr/bin/env python3
"""Server locale che imita /releases/latest di GitHub e i download degli asset, per provare l'aggiornatore
senza pubblicare nulla (solo build di sviluppo: SESTRIA_UPDATE_API / SESTRIA_UPDATE_RELEASES).
Uso: fake_release_server.py <cartella-asset> <tag> [porta]   (porta 0 = libera, stampata all'avvio)"""
import hashlib, http.server, json, os, sys

folder, tag = os.path.abspath(sys.argv[1]), sys.argv[2]
port = int(sys.argv[3]) if len(sys.argv) > 3 else 0

class Handler(http.server.BaseHTTPRequestHandler):
    def release(self):
        base = f"http://{self.headers.get('Host', '127.0.0.1:%d' % self.server.server_port)}/releases/download/{tag}/"
        assets = []
        for name in sorted(os.listdir(folder)):
            path = os.path.join(folder, name)
            if name.startswith("Sestria-v") and os.path.isfile(path):
                data = open(path, "rb").read()
                assets.append({"name": name, "state": "uploaded", "size": len(data), "digest": "sha256:" + hashlib.sha256(data).hexdigest(), "browser_download_url": base + name})
        return {"tag_name": tag, "draft": False, "prerelease": False, "body": "Release di prova", "assets": assets}

    def do_GET(self):
        if self.path == "/api/latest":
            body, kind = json.dumps(self.release()).encode(), "application/json"
        elif self.path.startswith(f"/releases/download/{tag}/"):
            path = os.path.join(folder, os.path.basename(self.path))
            if not os.path.isfile(path):
                self.send_error(404)
                return
            body, kind = open(path, "rb").read(), "application/octet-stream"
        else:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass

server = http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler)
print(server.server_port, flush=True)
server.serve_forever()
