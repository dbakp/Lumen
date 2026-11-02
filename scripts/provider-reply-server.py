#!/usr/bin/env python3
"""Explicit loopback test server. Never stores prompts, headers or credentials."""
import argparse
import hashlib
import json
import re
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--port", type=int, default=48731)
parser.add_argument("--report", type=Path, required=True)
parser.add_argument("--personal-audit", action="store_true", help="Record only fixed synthetic canary facts by message role, never arbitrary text")
args = parser.parse_args()
counts = {}
lock = threading.Lock()
held_gate = threading.Event()
prepared_gate = threading.Event()
personal_gate = threading.Event()
personal_audit = []
personal_canaries = {
    "noteA": "SYNTHETIC-PERSONAL-NOTE-40-A",
    "noteB": "SYNTHETIC-PERSONAL-NOTE-40-B",
    "unsaved": "SYNTHETIC-PERSONAL-UNSAVED-40",
    "known": "SYNTHETIC-KNOWN-ASSISTANT-40",
    "matching": "SYNTHETIC-MATCHING-ASSISTANT-40",
    "stale": "SYNTHETIC-STALE-ASSISTANT-40",
    "legacy": "SYNTHETIC-LEGACY-ASSISTANT-40",
    "user": "SYNTHETIC-USER-QUESTION-40",
    "returned": "SYNTHETIC-PERSONAL-REPLY-40",
}


def write_report_locked():
    report = {"scope": "Synthetic loopback only; no prompts, headers or credentials retained", "routes": counts}
    if args.personal_audit:
        report["personalAudit"] = personal_audit
    args.report.write_text(json.dumps(report, indent=2) + "\n")


def inspect_personal(body, route):
    # Inspect the actual decoded request from the production turn/HTTP builders.
    # Retain bounded fixture-token counts, role order and digest, not prompt text.
    packet = json.loads(body)
    messages = packet.get("messages")
    valid = (packet.get("model") == "synthetic-no-provider" and isinstance(messages, list)
             and 1 <= len(messages) <= 14 and all(isinstance(m, dict) and m.get("role") in ("system", "user", "assistant")
             and isinstance(m.get("content"), str) for m in messages))
    if not valid:
        raise ValueError("Invalid synthetic personal request")
    fact = {"route": route, "bodySHA256": hashlib.sha256(body).hexdigest(), "roles": [m["role"] for m in messages],
            "canaries": {name: {role: sum(m["content"].count(token) for m in messages if m["role"] == role)
                                for role in ("system", "user", "assistant")} for name, token in personal_canaries.items()}}
    with lock:
        if len(personal_audit) >= 32:
            raise ValueError("Synthetic personal audit limit")
        personal_audit.append(fact)
        write_report_locked()


def record(route, event):
    with lock:
        bucket = counts.setdefault(route, {})
        bucket[event] = bucket.get(event, 0) + 1
        write_report_locked()


def envelope(text="  Exact synthetic text.  ", finish="stop", refusal=None):
    return json.dumps({"choices": [{"index": 0, "finish_reason": finish, "message": {"role": "assistant", "content": text, "refusal": refusal}}]}, ensure_ascii=False, separators=(",", ":")).encode()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_):
        pass

    def do_GET(self):
        if args.personal_audit and self.path in ("/arm-personal", "/release-personal"):
            if self.path == "/arm-personal":
                personal_gate.clear()
            else:
                personal_gate.set()
                record("personal-held", "releases")
            self.send_response(204)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if args.personal_audit and self.path == "/personal-audit":
            with lock:
                payload = json.dumps(personal_audit).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return
        if self.path in ("/arm-prepared", "/release-prepared"):
            if self.path == "/arm-prepared":
                prepared_gate.clear()
            else:
                prepared_gate.set()
                record("prepared-stage", "releases")
            self.send_response(204)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if self.path == "/prepared-hold":
            record("prepared-stage", "requests")
            if not prepared_gate.wait(timeout=85):
                record("prepared-stage", "holdTimeouts")
            self.send_response(200)
            self.send_header("Content-Length", "0")
            self.end_headers()
            record("prepared-stage", "responsesWritten")
            return
        if self.path in ("/arm-held", "/release-held"):
            if self.path == "/arm-held":
                held_gate.clear()
            else:
                held_gate.set()
                record("native-held", "releases")
            self.send_response(204)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if self.path != "/counts":
            self.send_error(404)
            return
        with lock:
            payload = json.dumps(counts).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_POST(self):
        route = self.path.strip("/")
        size = int(self.headers.get("Content-Length", "0"))
        if not 0 < size <= 12_000_000:
            self.send_error(413)
            return
        body = self.rfile.read(size)
        if route in ("personal-held", "personal-complete"):
            if not args.personal_audit:
                self.send_error(404)
                return
            try:
                inspect_personal(body, route)
            except (ValueError, TypeError, KeyError):
                self.send_error(400)
                return
        record(route, "requests")
        try:
            if route == "redirect":
                self.send_response(307)
                self.send_header("Location", "/redirect-target")
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            text = "  Exact synthetic text.  "
            if route in ("personal-held", "personal-complete"):
                text = personal_canaries["returned"]
            if route.startswith("native-"):
                # The app adapter sends only a synthetic route and request ID,
                # never the normal health summary, history or source excerpts.
                source = re.search(rb"record_[a-f0-9]{16}_[1-4]", body)
                token = source.group().decode() if source else "record_missing_9"
                text = "Synthetic complete HTTP control. Local server only. [" + token + "]" if route in ("native-stop", "native-held") else "SYNTHETIC-INCOMPLETE-ASSERTION [" + token + "]"
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
            if route == "personal-held":
                if not personal_gate.wait(timeout=85):
                    record(route, "holdTimeouts")
            if route == "native-held":
                # A UI test explicitly releases this synthetic response after
                # performing the competing action. Bound abandoned workers.
                if not held_gate.wait(timeout=85):
                    record(route, "holdTimeouts")
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
