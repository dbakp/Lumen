#!/usr/bin/env python3
"""Explicit loopback test server. Never stores prompts, headers or credentials."""
import argparse
import json
import re
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--port", type=int, default=48731)
parser.add_argument("--report", type=Path, required=True)
args = parser.parse_args()
counts = {}
lock = threading.Lock()


def record(route, event):
    with lock:
        bucket = counts.setdefault(route, {})
        bucket[event] = bucket.get(event, 0) + 1
        args.report.write_text(json.dumps({"scope": "Synthetic loopback requests only; no request bodies or headers retained", "routes": counts}, indent=2) + "\n")


def envelope(text="  Exact synthetic text.  ", finish="stop", refusal=None):
    return json.dumps({"choices": [{"index": 0, "finish_reason": finish, "message": {"role": "assistant", "content": text, "refusal": refusal}}]}, ensure_ascii=False, separators=(",", ":")).encode()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_):
        pass

    def do_POST(self):
        route = self.path.strip("/")
        size = int(self.headers.get("Content-Length", "0"))
        if not 0 < size <= 12_000_000:
            self.send_error(413)
            return
        body = self.rfile.read(size)
        record(route, "requests")
        try:
            if route == "redirect":
                self.send_response(307)
                self.send_header("Location", "/redirect-target")
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            text = "  Exact synthetic text.  "
            if route.startswith("native-"):
                # The app adapter sends only a synthetic route and request ID,
                # never the normal health summary, history or source excerpts.
                source = re.search(rb"record_[a-f0-9]{16}_[1-4]", body)
                token = source.group().decode() if source else "record_missing_9"
                text = "Synthetic complete HTTP control. Local server only. [" + token + "]" if route == "native-stop" else "SYNTHETIC-INCOMPLETE-ASSERTION [" + token + "]"
            payload = envelope(text=text, finish="length" if route in ("length", "native-length") else "content_filter" if route == "filter" else "tool_calls" if route == "tool" else "stop", refusal="Synthetic refusal" if route in ("refusal", "native-refusal") else None)
            if route == "utf8-chunks":
                payload = envelope(text="Café 🧑🏽‍⚕️ · 12,5 µg/L")
            if route == "nonjson":
                payload = b"data: incomplete server event"
            if route == "exact-limit":
                payload += b" " * (1_000_000 - len(payload))
            if route == "oversize-chunked":
                payload = b" " * 1_000_001
            self.send_response(503 if route == "http-error" else 200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Cache-Control", "no-store")
            chunked = route in ("oversize-chunked", "utf8-chunks")
            if chunked:
                self.send_header("Transfer-Encoding", "chunked")
            else:
                self.send_header("Content-Length", "1000001" if route == "oversize-header" else str(len(payload)))
            self.end_headers()
            if route in ("slow", "native-slow"):
                time.sleep(5)
            if route == "oversize-header":
                # The header alone must stop the receiver before a body exists.
                time.sleep(0.5)
                self.close_connection = True
                return
            if chunked:
                step = 1 if route == "utf8-chunks" else 4096
                for offset in range(0, len(payload), step):
                    chunk = payload[offset:offset + step]
                    self.wfile.write(f"{len(chunk):X}\r\n".encode() + chunk + b"\r\n")
                self.wfile.write(b"0\r\n\r\n")
            else:
                self.wfile.write(payload)
            self.wfile.flush()
            record(route, "responsesWritten")
        except (BrokenPipeError, ConnectionResetError):
            record(route, "clientDisconnected")


server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
server.daemon_threads = True
print(f"http://127.0.0.1:{server.server_port}", flush=True)
try:
    server.serve_forever()
except KeyboardInterrupt:
    pass
finally:
    server.server_close()
