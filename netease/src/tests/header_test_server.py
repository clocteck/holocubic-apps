"""Local synthetic HTTP fixture; serves no files and handles no real credentials."""
from http.server import BaseHTTPRequestHandler, HTTPServer

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Set-Cookie","MUSIC_U=synthetic-test; Path=/; HttpOnly")
        self.send_header("Set-Cookie","__csrf=synthetic-csrf; Expires=Wed, 09 Jun 2030 10:18:14 GMT; Path=/")
        self.send_header("Set-Cookie","NMTID=synthetic-device; Path=/")
        self.send_header("Content-Type","text/plain")
        self.send_header("Content-Length","2")
        self.end_headers()
        self.wfile.write(b"OK")
    def log_message(self,*args):
        print("synthetic header request",flush=True)

HTTPServer(("192.168.0.80",18765),Handler).serve_forever()
