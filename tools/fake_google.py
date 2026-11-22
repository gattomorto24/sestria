#!/usr/bin/env python3
"""Finto Google per provare il salvataggio su Drive senza account: codice dispositivo, token, profilo e file creato dall'app.
Uso: tools/fake_google.py [porta]   (SESTRIA_DRIVE_TEST=http://127.0.0.1:PORTA nelle build di sviluppo)."""
import http.server, json, sys, urllib.parse

state = {"approved": False, "files": {}, "next": 1, "revoked": False, "access": "acc-1", "polls": 0}

class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def send(self, code, obj, raw=None):
        body = raw if raw is not None else json.dumps(obj).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
    def body(self):
        return self.rfile.read(int(self.headers.get("Content-Length", 0))).decode()
    @staticmethod
    def norm(path):
        for prefix in ("/drive", "/upload"):
            if path.startswith(prefix + "/"):
                return path[len(prefix):]
        return path
    def authed(self):
        return self.headers.get("Authorization") == "Bearer " + state["access"]
    def do_POST(self):
        path = self.norm(urllib.parse.urlparse(self.path).path)
        data = self.body()
        if path == "/device":
            f = urllib.parse.parse_qs(data)
            assert "drive.file" in f["scope"][0] and "appdata" not in f["scope"][0]
            self.send(200, {"device_code": "dev123", "user_code": "ABCD-EFGH", "verification_url": "https://www.google.com/device", "expires_in": 600, "interval": 2})
        elif path == "/token":
            f = urllib.parse.parse_qs(data)
            if f.get("grant_type", [""])[0].endswith("device_code"):
                state["polls"] += 1
                if not state["approved"]:
                    self.send(428, {"error": "authorization_pending"})
                else:
                    self.send(200, {"access_token": state["access"], "refresh_token": "refresh-token-abcdef", "expires_in": 3600})
            elif f.get("grant_type", [""])[0] == "refresh_token":
                if state["revoked"] or f["refresh_token"][0] != "refresh-token-abcdef":
                    self.send(400, {"error": "invalid_grant"})
                else:
                    self.send(200, {"access_token": state["access"], "expires_in": 3600})
        elif path == "/approve":
            state["approved"] = True; self.send(200, {})
        elif path == "/revoke_all":
            state["revoked"] = True; self.send(200, {})
        elif path == "/files":
            if not self.authed(): return self.send(401, {})
            parts = data.split("\r\n")
            meta = json.loads(parts[3]); content = parts[7]
            fid = "file%d" % state["next"]; state["next"] += 1
            assert "parents" not in meta
            state["files"][fid] = {"name": meta["name"], "content": content}
            self.send(200, {"id": fid})
        else:
            self.send(404, {})
    def do_PATCH(self):
        path = self.norm(urllib.parse.urlparse(self.path).path)
        data = self.body()
        if path.startswith("/files/") and self.authed():
            fid = path.split("/")[2]
            parts = data.split("\r\n")
            state["files"][fid]["content"] = parts[7]
            self.send(200, {"id": fid})
        else:
            self.send(401, {})
    def do_GET(self):
        u = urllib.parse.urlparse(self.path); path = self.norm(u.path); q = urllib.parse.parse_qs(u.query)
        if path == "/userinfo":
            self.send(200, {"name": "Prova Tester", "email": "prova@example.com"}) if self.authed() else self.send(401, {})
        elif path == "/files":
            if not self.authed(): return self.send(401, {})
            assert q.get("spaces") == ["drive"] and "trashed = false" in q["q"][0]
            self.send(200, {"files": [{"id": k, "modifiedTime": "x"} for k, v in state["files"].items() if v["name"] in q["q"][0]]})
        elif path.startswith("/files/"):
            if not self.authed(): return self.send(401, {})
            f = state["files"].get(path.split("/")[2])
            self.send(200, None, raw=f["content"].encode()) if f else self.send(404, {})
        elif path == "/state":
            self.send(200, {"files": {k: json.loads(v["content"]) for k, v in state["files"].items()}, "polls": state["polls"]})
        else:
            self.send(404, {})

if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 32660
    http.server.ThreadingHTTPServer(("127.0.0.1", port), H).serve_forever()
