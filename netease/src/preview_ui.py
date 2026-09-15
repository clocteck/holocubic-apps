"""Loopback-only live preview for the fixed-size device design, not the device UI."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import json

DESIGN = Path(__file__).with_name("device-ui.html")

class PreviewHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        route = self.path.split("?", 1)[0]
        if route in ("/", "/device-ui.html"):
            body = DESIGN.read_bytes()
            mime = "text/html; charset=utf-8"
        elif route == "/__revision":
            body = json.dumps({"revision": str(DESIGN.stat().st_mtime_ns)}).encode()
            mime = "application/json"
        else:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass

if __name__ == "__main__":
    print("Device UI preview: http://127.0.0.1:18766/device-ui.html", flush=True)
    ThreadingHTTPServer(("127.0.0.1", 18766), PreviewHandler).serve_forever()
