"""Fixed synthetic OAuth/route audit. Never logs request bodies or headers."""
import argparse
import hashlib
import json
from pathlib import Path
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import threading
import base64
import re
import subprocess
from urllib.parse import parse_qs, urlsplit

parser = argparse.ArgumentParser()
parser.add_argument('--report', type=Path, required=True)
parser.add_argument('--ui-state', type=Path)
parser.add_argument('--ui-device', choices=['922E011C-3895-4DB1-9C9A-1D3A977226CF', 'AF849DEA-DF34-4B0E-9FC1-3E45DCBE8481'])
args = parser.parse_args()
lock = threading.Lock()
gate = threading.Event()
chat_gate = threading.Event()
chat_gate.set()
first_chat_gate = threading.Event()
first_chat_gate.set()
hold_next_chat = False
facts = {'tokenRequests': 0, 'tokenResponses': 0, 'holdTimeouts': 0, 'packets': [], 'loginRequests': 0, 'loginResponses': 0, 'loginAudit': []}
fail_token = False
login_challenge = None
login_refresh = True
login_failure = False
image_digest = None
response_case = 'valid'
response_gate = threading.Event()
response_gate.set()
response_cases = {'valid', 'mixed-case-bearer', 'malformed', 'duplicate', 'escaped-duplicate', 'nested-duplicate', 'error', 'null-error', 'http-error', 'oversized-header', 'oversized-chunked', 'redirect', 'wrong-type', 'wrong-token-type', 'zero-expiry', 'invalid-token', 'invalid-utf8', 'non-object', 'cancelled'}


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
        global fail_token, login_challenge, login_refresh, login_failure, image_digest, hold_next_chat, response_case
        parts = urlsplit(self.path)
        if parts.path == '/arm-response':
            case = parse_qs(parts.query).get('case', [''])[0]
            if case not in response_cases:
                self.send_error(400)
                return
            with lock:
                response_case = case
                facts.setdefault('tokenTransportAudit', [])
                facts.setdefault('tokenTransportResponses', 0)
                facts.setdefault('tokenRedirectHits', 0)
                response_gate.clear() if case == 'cancelled' else response_gate.set()
            self.respond({})
            return
        if parts.path == '/release-response':
            response_gate.set()
            self.respond({})
            return
        if parts.path == '/token-redirect-sink':
            with lock:
                facts['tokenRedirectHits'] = facts.get('tokenRedirectHits', 0) + 1
                save()
            self.respond({})
            return
        if parts.path == '/ui-state' and (args.ui_state or args.ui_device):
            try:
                path = args.ui_state
                if args.ui_device:
                    root = Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', args.ui_device, 'com.dbakp.lumen', 'data'], text=True, timeout=5).strip())
                    assert root.is_absolute() and args.ui_device in root.parts
                    path = root / 'tmp' / 'Lumen-provider-ui-live.json'
                content = path.read_bytes()
                assert len(content) <= 16000
                state = json.loads(content)
                assert state['apiKeyClass'] in ['fixture-a', 'fixture-b', 'missing']
                checkpoint = parse_qs(parts.query).get('checkpoint', ['read'])[0]
                assert re.fullmatch(r'[a-z0-9-]{1,64}', checkpoint)
            except (OSError, ValueError, KeyError, AssertionError, subprocess.SubprocessError):
                self.send_error(409)
                return
            with lock:
                # A full device/style matrix exceeds 64 verified checkpoints.
                # Keep the capture bounded and return an explicit HTTP failure.
                if len(facts.setdefault('uiReadbacks', [])) >= 256:
                    self.send_error(429, 'UI checkpoint limit reached')
                    return
                facts['uiReadbacks'].append({'checkpoint': checkpoint, 'state': state})
                save()
            self.respond(state)
            return
        if parts.path == '/arm-photo':
            value = parse_qs(parts.query).get('sha256', [''])[0]
            if not re.fullmatch(r'[a-f0-9]{64}', value):
                self.send_error(400)
                return
            image_digest = value
            self.respond({})
            return
        if parts.path == '/arm-login':
            query = parse_qs(parts.query)
            if not re.fullmatch(r'[A-Za-z0-9_-]{43}', query.get('challenge', [''])[0]):
                self.send_error(400)
                return
            with lock:
                login_challenge = query['challenge'][0]
                login_refresh = query.get('refresh', ['1']) == ['1']
                login_failure = query.get('failure', ['0']) == ['1']
                gate.clear()
            self.respond({})
            return
        if self.path in ['/arm-token', '/arm-token-failure']:
            with lock:
                fail_token = self.path.endswith('failure')
                gate.clear()
            self.respond({})
        elif self.path == '/release-token':
            gate.set()
            self.respond({})
        elif self.path == '/arm-chat':
            chat_gate.clear()
            self.respond({})
        elif self.path == '/release-chat':
            chat_gate.set()
            self.respond({})
        elif self.path == '/arm-first-chat':
            with lock:
                hold_next_chat = True
                first_chat_gate.clear()
            self.respond({})
        elif self.path == '/release-first-chat':
            first_chat_gate.set()
            self.respond({})
        elif self.path == '/audit':
            with lock:
                self.respond(facts)
        else:
            self.send_error(404)

    def do_POST(self):
        global hold_next_chat
        size = int(self.headers.get('Content-Length', '0'))
        if not 0 < size <= 64000:
            self.send_error(413)
            return
        body = self.rfile.read(size)
        if self.path == '/token-redirect-sink':
            with lock:
                facts['tokenRedirectHits'] = facts.get('tokenRedirectHits', 0) + 1
                save()
            self.respond({})
            return
        if self.path in ['/adversarial-refresh', '/adversarial-login']:
            self.adversarial_token(body)
            return
        if self.path == '/token-login':
            form = parse_qs(body.decode())
            verifier = form.get('code_verifier', [''])[0]
            if (set(form) != {'client_id', 'code', 'code_verifier', 'grant_type', 'redirect_uri'}
                    or any(len(v) != 1 for v in form.values())
                    or form['client_id'] != ['123456789-synthetic42.apps.googleusercontent.com']
                    or form['code'] != ['SYNTHETIC+AUTH&CODE=42'] or form['grant_type'] != ['authorization_code']
                    or form['redirect_uri'] != ['com.googleusercontent.apps.123456789-synthetic42:/oauth2redirect/google']
                    or not re.fullmatch(r'[A-Za-z0-9._~-]{64}', verifier)):
                self.send_error(400)
                return
            challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).decode().rstrip('=')
            with lock:
                include_refresh, failure = login_refresh, login_failure
                facts['loginRequests'] = facts.get('loginRequests', 0) + 1
                facts.setdefault('loginAudit', []).append({'pkceMatches': challenge == login_challenge, 'redirectMatches': True, 'reservedCodeDecoded': True, 'bodySHA256': hashlib.sha256(body).hexdigest()})
                save()
            if not gate.wait(20):
                with lock:
                    facts['holdTimeouts'] += 1
                    save()
            payload = {'access_token': 'synthetic-signin-access-42', 'expires_in': 3600, 'token_type': 'Bearer'}
            if include_refresh:
                payload['refresh_token'] = 'synthetic-signin-refresh-42'
            self.respond({'error': 'synthetic_login_failure'} if failure else payload, 400 if failure else 200)
            with lock:
                facts['loginResponses'] = facts.get('loginResponses', 0) + 1
                save()
            return
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
            self.respond({'error': 'synthetic_refresh_failure'} if failure else {'access_token': 'synthetic-access-refreshed-42', 'expires_in': 3600, 'token_type': 'Bearer'}, 503 if failure else 200)
            with lock:
                facts['tokenResponses'] += 1
                save()
            return
        if self.path not in ['/chat-a', '/chat-b', '/caller-chat']:
            self.send_error(404)
            return
        try:
            packet = json.loads(body)
            messages = packet['messages']
            assert packet['model'] in ['synthetic-provider-42-a', 'synthetic-provider-42-b']
            kind = None
            photo_digest = None
            if self.path == '/caller-chat':
                roles = [m['role'] for m in messages]
                if roles == ['user']:
                    user = messages[0]['content']
                    if isinstance(user, list):
                        assert len(user) == 2 and user[0]['type'] == 'text' and user[0]['text'].startswith('You are a nutrition vision model.')
                        assert user[1]['type'] == 'image_url' and user[1]['image_url']['url'].startswith('data:image/jpeg;base64,')
                        image = base64.b64decode(user[1]['image_url']['url'].split(',', 1)[1], validate=True)
                        assert len(image) <= 4096 and image.startswith(b'\xff\xd8')
                        photo_digest = hashlib.sha256(image).hexdigest()
                        assert image_digest is not None and photo_digest == image_digest
                        kind = 'photo'
                    else:
                        if user == 'Reply with exactly: Lumen AI link OK':
                            kind = 'connectivity'
                        else:
                            assert user.startswith('You are a precise nutrition assistant.') and '\nMeal: SYNTHETIC-PROVIDER-MEAL-42\n' in user
                            kind = 'description'
                else:
                    assert roles == ['system', 'user']
                    system, user = messages[0]['content'], messages[1]['content']
                if kind:
                    pass
                elif user == 'SYNTHETIC-PROVIDER-COACH-42 make a plan':
                    assert 'SYNTHETIC-PROVIDER-NOTE-42' in system
                    kind = 'coach'
                elif user == 'SYNTHETIC-PROVIDER-LOG-42 I drank 250 ml water':
                    assert system.startswith("Extract proposed health logs from the user's selected statement.")
                    kind = 'health'
                else:
                    assert user.startswith('Planning request (untrusted JSON data):\n')
                    assert json.loads(user.split('\n', 1)[1])['goal'] == 'SYNTHETIC-PROVIDER-PLAN-42'
                    assert system.endswith('SYNTHETIC-PROVIDER-CONTEXT-42')
                    kind = 'plan'
            else:
                assert [m['role'] for m in messages] == ['system', 'user']
                assert messages[0]['content'] == 'SYNTHETIC-PROVIDER-CONTEXT-42'
                assert messages[1]['content'] == 'SYNTHETIC-PROVIDER-QUESTION-42'
            credential = self.headers.get('Authorization')
            assert credential in ['Bearer synthetic-access-refreshed-42', 'Bearer synthetic-access-old-42', 'Bearer synthetic-key-42-a', 'Bearer synthetic-key-42-b']
        except (ValueError, KeyError, AssertionError, TypeError):
            self.send_error(400)
            return
        with lock:
            assert len(facts['packets']) < 64
            classification = {'Bearer synthetic-access-refreshed-42': 'refreshed-fixture', 'Bearer synthetic-access-old-42': 'expired-fixture', 'Bearer synthetic-key-42-a': 'api-key-fixture', 'Bearer synthetic-key-42-b': 'replacement-key-fixture'}[credential]
            record = {'route': self.path, 'model': packet['model'], 'credential': classification, 'systemCanary': True, 'bodySHA256': hashlib.sha256(body).hexdigest()}
            hold_first = hold_next_chat
            hold_next_chat = False
            if hold_first:
                record['staleConnectivityReply'] = kind == 'connectivity'
            if kind:
                record['kind'] = kind
            if photo_digest:
                record['imageSHA256'] = photo_digest
            facts['packets'].append(record)
            save()
        content = 'SYNTHETIC-PROVIDER-REPLY-42'
        if kind:
            if hold_first and not first_chat_gate.wait(20):
                with lock:
                    facts['holdTimeouts'] += 1
                    save()
            if not chat_gate.wait(20):
                with lock:
                    facts['holdTimeouts'] += 1
                    save()
            if kind == 'coach':
                content = 'Synthetic routine\nA fixed test plan.\n1. Take a short walk\n2. Drink water with lunch\n3. Review the routine tomorrow'
            elif kind == 'plan':
                content = json.dumps({'version': 1, 'title': 'Synthetic routine', 'reason': 'Fixed provider caller check.', 'steps': [{'day': 1, 'title': 'Take a short walk'}]})
            elif kind == 'health':
                content = json.dumps({'entries': [{'kind': 'water', 'evidence': 'I drank 250 ml water', 'waterML': 250}]})
            elif kind == 'connectivity':
                content = 'SYNTHETIC-STALE-CONNECTION-RESULT-42' if hold_first else 'Lumen AI link OK'
            else:
                content = json.dumps({'headline': 'Synthetic meal', 'coachingNote': 'Fixed estimate for caller checks.', 'items': [{'name': 'Synthetic food', 'grams': 100, 'calories': 250, 'proteinG': 20, 'carbsG': 30, 'fatG': 5, 'fiberG': 2}]})
        self.respond({'choices': [{'index': 0, 'finish_reason': 'stop', 'message': {'role': 'assistant', 'content': content}}]})

    def adversarial_token(self, body):
        form = parse_qs(body.decode())
        login = self.path.endswith('login')
        pkce = None
        if login:
            verifier = form.get('code_verifier', [''])[0]
            pkce = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).decode().rstrip('=') == login_challenge
            valid = (set(form) == {'client_id', 'code', 'code_verifier', 'grant_type', 'redirect_uri'}
                     and all(len(v) == 1 for v in form.values())
                     and form['client_id'] == ['123456789-synthetic42.apps.googleusercontent.com']
                     and form['code'] == ['SYNTHETIC+AUTH&CODE=42'] and form['grant_type'] == ['authorization_code']
                     and form['redirect_uri'] == ['com.googleusercontent.apps.123456789-synthetic42:/oauth2redirect/google']
                     and re.fullmatch(r'[A-Za-z0-9._~-]{64}', verifier) and pkce)
        else:
            valid = form == {'client_id': ['synthetic-client-42'], 'refresh_token': ['synthetic-refresh-42'], 'grant_type': ['refresh_token']}
        if not valid:
            self.send_error(400)
            return
        with lock:
            case = response_case
        value = {'access_token': 'synthetic-access-refreshed-42', 'refresh_token': 'synthetic-refresh-42', 'expires_in': 3600, 'token_type': 'Bearer', 'extension': {'ignored': True}}
        code = 200
        if case == 'mixed-case-bearer': value['token_type'] = 'bEaReR'
        if case == 'error': value['error'] = 'synthetic_error_42'
        if case == 'null-error': value['error'] = None
        if case == 'http-error': code = 503
        if case == 'wrong-type': value['expires_in'] = '3600'
        if case == 'wrong-token-type': value['token_type'] = 'Basic'
        if case == 'zero-expiry': value['expires_in'] = 0
        if case == 'invalid-token': value['access_token'] = 'synthetic invalid token 42'
        payload = json.dumps(value).encode()
        if case == 'malformed': payload = b'{"access_token":'
        if case == 'invalid-utf8': payload = b'\xff' + payload
        if case == 'non-object': payload = b'[' + payload + b']'
        if case == 'duplicate': payload = b'{"access_token":"synthetic-access-refreshed-42",' + payload[1:]
        if case == 'escaped-duplicate': payload = b'{"\\u0061ccess_token":"synthetic-access-refreshed-42",' + payload[1:]
        if case == 'nested-duplicate': payload = payload[:-1] + b',"meta":{"x":1,"x":2}}'
        if case in ['oversized-header', 'oversized-chunked']: payload += b' ' * (128001 - len(payload))
        if case == 'redirect': code = 307
        chunked = case in ['oversized-chunked', 'cancelled']
        record = {'caseName': case, 'requestKind': 'login' if login else 'refresh', 'bodySHA256': hashlib.sha256(body).hexdigest(),
                  'formMatches': True, 'cookieAbsent': self.headers.get('Cookie') is None, 'statusCode': code,
                  'payloadBytes': len(payload), 'advertisedBytes': -1 if chunked else len(payload), 'streamStarted': False}
        if pkce is not None: record['pkceMatches'] = pkce
        with lock:
            facts['tokenTransportAudit'].append(record)
            save()
        try:
            self.send_response(code)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Set-Cookie', 'synthetic_token_cookie_42=1; Path=/')
            if case == 'redirect': self.send_header('Location', 'http://127.0.0.1:48733/token-redirect-sink')
            self.send_header('Transfer-Encoding' if chunked else 'Content-Length', 'chunked' if chunked else str(len(payload)))
            self.end_headers()
            if case == 'cancelled':
                prefix = payload[:16]
                self.wfile.write(f'{len(prefix):x}\r\n'.encode() + prefix + b'\r\n'); self.wfile.flush()
                with lock:
                    record['streamStarted'] = True
                    save()
                if not response_gate.wait(20):
                    with lock:
                        facts['holdTimeouts'] += 1
                        save()
                payload = payload[16:]
            if chunked: self.wfile.write(f'{len(payload):x}\r\n'.encode() + payload + b'\r\n0\r\n\r\n')
            else: self.wfile.write(payload)
            self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass  # Expected when the bounded/cancelled client closes the stream.
        finally:
            with lock:
                facts['tokenTransportResponses'] += 1
                save()


server = ThreadingHTTPServer(('127.0.0.1', 48733), Handler)
server.daemon_threads = True
print('Synthetic provider authorization server on loopback:48733', flush=True)
try:
    server.serve_forever()
except KeyboardInterrupt:
    pass
finally:
    server.server_close()
