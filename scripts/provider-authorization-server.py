"""Fixed synthetic OAuth/route audit. Never logs request bodies or headers."""
import argparse
import hashlib
import json
from pathlib import Path
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import threading
from urllib.parse import parse_qs

parser = argparse.ArgumentParser()
parser.add_argument('--report', type=Path, required=True)
args = parser.parse_args()
lock = threading.Lock()
gate = threading.Event()
facts = {'tokenRequests': 0, 'tokenResponses': 0, 'holdTimeouts': 0, 'packets': []}
fail_token = False


def save():
    args.report.write_text(json.dumps(facts, indent=2) + '\n')


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, *_):
        pass

    def respond(self, data, code=200):
        payload = json.dumps(data).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)
        self.wfile.flush()

    def do_GET(self):
        global fail_token
        if self.path in ['/arm-token', '/arm-token-failure']:
            with lock:
                fail_token = self.path.endswith('failure')
                gate.clear()
            self.respond({})
        elif self.path == '/release-token':
            gate.set()
            self.respond({})
        elif self.path == '/audit':
            with lock:
                self.respond(facts)
        else:
            self.send_error(404)

    def do_POST(self):
        size = int(self.headers.get('Content-Length', '0'))
        if not 0 < size <= 64000:
            self.send_error(413)
            return
        body = self.rfile.read(size)
        if self.path == '/token':
            form = parse_qs(body.decode())
            if form != {'client_id': ['synthetic-client-42'], 'refresh_token': ['synthetic-refresh-42'], 'grant_type': ['refresh_token']}:
                self.send_error(400)
                return
            with lock:
                facts['tokenRequests'] += 1
                failure = fail_token
                save()
            if not gate.wait(20):
                with lock:
                    facts['holdTimeouts'] += 1
                    save()
            self.respond({'error': 'synthetic_refresh_failure'} if failure else {'access_token': 'synthetic-access-refreshed-42', 'expires_in': 3600}, 503 if failure else 200)
            with lock:
                facts['tokenResponses'] += 1
                save()
            return
        if self.path not in ['/chat-a', '/chat-b']:
            self.send_error(404)
            return
        try:
            packet = json.loads(body)
            messages = packet['messages']
            assert packet['model'] in ['synthetic-provider-42-a', 'synthetic-provider-42-b']
            assert [m['role'] for m in messages] == ['system', 'user']
            assert messages[0]['content'] == 'SYNTHETIC-PROVIDER-CONTEXT-42'
            assert messages[1]['content'] == 'SYNTHETIC-PROVIDER-QUESTION-42'
            credential = self.headers.get('Authorization')
            assert credential in ['Bearer synthetic-access-refreshed-42', 'Bearer synthetic-access-old-42']
        except (ValueError, KeyError, AssertionError, TypeError):
            self.send_error(400)
            return
        with lock:
            assert len(facts['packets']) < 64
            facts['packets'].append({'route': self.path, 'model': packet['model'], 'credential': 'refreshed-fixture' if credential.endswith('refreshed-42') else 'expired-fixture', 'systemCanary': True, 'bodySHA256': hashlib.sha256(body).hexdigest()})
            save()
        self.respond({'choices': [{'index': 0, 'finish_reason': 'stop', 'message': {'role': 'assistant', 'content': 'SYNTHETIC-PROVIDER-REPLY-42'}}]})


server = ThreadingHTTPServer(('127.0.0.1', 48733), Handler)
server.daemon_threads = True
print('Synthetic provider authorization server on loopback:48733', flush=True)
try:
    server.serve_forever()
except KeyboardInterrupt:
    pass
finally:
    server.server_close()
