"""Verify local scoped progress without asserting whole-batch acceptance."""
from pathlib import Path
import argparse
import gzip
import hashlib
import json
import subprocess
import re
from collections import Counter

base = Path(__file__).resolve().parent
repo = base.parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--current-source', help='Additionally require the working tree to match this source manifest')
args = parser.parse_args()


def read(name):
    return json.loads((base / name).read_text())


for revision, count in [(1, 13), (2, 26)]:
    report = read(f'storage-r{revision}-report.json')
    summary = read(f'storage-r{revision}-summary.json')
    assert report['status'] == 'Credential storage checks passed'
    assert len(report['checks']) == count and all(row['passed'] for row in report['checks'])
    assert summary['passedTests'] == 1 and summary['failedTests'] == summary['skippedTests'] == 0
auth = read('auth-r2-report.json')
host = read('auth-r2-host-readback.json')
summary = read('auth-r2-summary.json')
assert summary['passedTests'] == 1 and summary['failedTests'] == summary['skippedTests'] == 0
assert auth['status'] == 'Provider authorization checks passed' and auth['host'] == host
assert host['tokenRequests'] == host['tokenResponses'] == 12 and len(host['packets']) == 5 and host['holdTimeouts'] == 0
observations = {row['mode']: row for row in auth['observations']}
assert len(observations) == 22
allowed = {'unchanged': 1, 'coalesced': 2, 'submission-unchanged': 1, 'key-unchanged': 1}
for name, row in observations.items():
    assert row['accountIdentityPreserved'] and row['legacySourcesAbsent']
    assert row['outgoingRequests'] == allowed.get(name, 0) == len(row['packets'])
    assert row['replyAccepted'] == (name in allowed)
    for packet in row['packets']:
        assert packet['route'] == '/chat-a' and packet['model'] == 'synthetic-provider-42-a' and packet['systemCanary']
        assert packet['credential'] == ('api-key-fixture' if name.startswith('key-') else 'refreshed-fixture')
assert observations['disconnect']['accessState'] == observations['reset']['accessState'] == 'missing'
assert observations['refresh-failure']['accessState'] == observations['credential-write-failure']['accessState'] == 'expired-fixture'
assert observations['credential-write-failure']['credentialProblem'] and observations['key-write-failure']['credentialProblem']
for name in ['mode', 'endpoint', 'model', 'client', 'scope', 'revert', 'submission-model', 'submission-revert', 'key-replace', 'key-revert', 'key-mode']:
    assert observations[name]['authorizationChanged']
for revision in [6, 10]:
    fresh_auth, fresh_host, fresh_summary = [read(f'auth-r{revision}-' + name + '.json') for name in ['report', 'host-readback', 'summary']]
    assert fresh_auth['status'] == 'Provider authorization checks passed' and fresh_auth['cleanupVerified'] and fresh_auth['host'] == fresh_host
    assert fresh_summary['passedTests'] == 1 and fresh_summary['failedTests'] == fresh_summary['skippedTests'] == 0
    assert fresh_host['tokenRequests'] == fresh_host['tokenResponses'] == 12 and len(fresh_host['packets']) == 5 and fresh_host['holdTimeouts'] == 0
    assert {row['mode'] for row in fresh_auth['observations']} == set(observations)
    for row in fresh_auth['observations']:
        for key in ['accessState', 'accountPresent', 'accountIdentityPreserved', 'legacySourcesAbsent', 'authorizationChanged', 'credentialProblem', 'outgoingRequests', 'replyAccepted']:
            assert row[key] == observations[row['mode']][key], (row['mode'], key)
        for packet in row['packets']:
            assert packet['route'] == '/chat-a' and packet['model'] == 'synthetic-provider-42-a' and packet['systemCanary']
            assert packet['credential'] == ('api-key-fixture' if row['mode'].startswith('key-') else 'refreshed-fixture')
for revision, kinds, total in [(6, ['coach', 'plan', 'health'], 17), (7, ['coach', 'plan', 'health', 'photo', 'description'], 27), (10, ['coach', 'plan', 'health', 'photo', 'description'], 27)]:
    caller, caller_host, caller_summary = [read(f'caller-r{revision}-' + name + '.json') for name in ['report', 'host-readback', 'summary']]
    assert caller['status'] == 'Provider caller checks passed' and caller['cleanupVerified'] and caller['host'] == caller_host
    assert caller_summary['passedTests'] == 1 and caller_summary['failedTests'] == caller_summary['skippedTests'] == 0
    assert len(caller['observations']) == total and len(caller_host['packets']) == 3 * len(kinds)
    assert caller_host['tokenRequests'] == caller_host['loginRequests'] == caller_host['holdTimeouts'] == 0
    for kind in kinds:
        rows = [row for row in caller['observations'] if row['caller'] == kind]
        expected_modes = {'unchanged', 'stale-before-task', 'submission-change', 'response-change', 'response-revert'} | ({'search-change', 'search-revert'} if kind == 'coach' else set())
        assert {row['mode'] for row in rows} == expected_modes
        for row in rows:
            assert row['accepted'] == (row['mode'] == 'unchanged')
            assert row['outgoingRequests'] == int(row['mode'] == 'unchanged' or row['mode'].startswith('response-'))
            assert row['savedConversation'] == (kind == 'coach')
            assert row['savedPlans'] == int(row['accepted'] and kind in {'coach', 'plan'})
            assert row['source'] == ('API key · http://127.0.0.1:48733' if row['accepted'] and kind in {'coach', 'plan', 'health'} else 'Lumen notice' if kind == 'coach' else '')
        assert sum(packet['kind'] == kind for packet in caller_host['packets']) == 3
    for packet in caller_host['packets']:
        assert packet['route'] == '/caller-chat' and packet['model'] == 'synthetic-provider-42-a' and packet['credential'] == 'api-key-fixture' and packet['systemCanary']
        if packet['kind'] == 'photo':
            assert packet['imageSHA256'] == caller['expectedSyntheticImageSHA256']
signin = read('signin-r4-report.json')
signin_host = read('signin-r4-host-readback.json')
signin_summary = read('signin-r4-summary.json')
assert signin_summary['passedTests'] == 1 and signin_summary['failedTests'] == signin_summary['skippedTests'] == 0
assert signin['status'] == 'Provider sign-in checks passed' and signin['host'] == signin_host
assert signin['cleanupVerified'] and signin['invalidClientsRejected']
assert signin_host['loginRequests'] == signin_host['loginResponses'] == 10
assert signin_host['tokenRequests'] == signin_host['tokenResponses'] == signin_host['holdTimeouts'] == 0 and not signin_host['packets']
assert len(signin_host['loginAudit']) == 10 and all(row['pkceMatches'] and row['redirectMatches'] and row['reservedCodeDecoded'] for row in signin_host['loginAudit'])
signins = {row['mode']: row for row in signin['observations']}
assert set(signins) == {'success', 'no-refresh', 'cancel', 'wrong-state', 'duplicate-state', 'wrong-scheme', 'wrong-path', 'stale-attempt', 'disconnect-before-callback', 'configuration-before-callback', 'disconnect-held', 'configuration-held', 'revert-held', 'replacement-held', 'write-failure', 'error-response'}
for mode, row in signins.items():
    assert row['oldAccountPreserved'] and row['originalPKCE'] and row['sdkCallbackMatches'] and not row['pendingAttempt']
    assert row['accountState'] == ('new-account' if mode in {'success', 'no-refresh', 'stale-attempt', 'replacement-held'} else 'old-preserved' if mode == 'write-failure' else 'missing')
removal_summary = read('removal-r5-summary.json')
assert removal_summary['passedTests'] == 1 and removal_summary['failedTests'] == removal_summary['skippedTests'] == 0
for mode in ['oauth', 'all']:
    prepare, resume = [read(f'removal-r5-{mode}-{phase}.json') for phase in ['prepare', 'resume']]
    assert prepare['status'] == f'Credential removal relaunch checks passed: {mode} prepare'
    assert resume['status'] == f'Credential removal relaunch checks passed: {mode} resume'
    assert len(prepare['checks']) == 8 and len(resume['checks']) == 10
    assert prepare['pid'] == prepare['originalPID'] == resume['originalPID'] and prepare['pid'] != resume['pid']
connection = read('connection-r8-report.json')
connection_summary = read('connection-r8-summary.json')
assert connection['status'] == 'Connection storage checks passed' and connection['cleanupVerified']
assert len(connection['checks']) == 22 and all(row['passed'] for row in connection['checks'])
assert connection_summary['passedTests'] == 2 and connection_summary['failedTests'] == connection_summary['skippedTests'] == 0
for mode in ['oauth', 'all', 'key']:
    prepare, resume = [read(f'removal-r8-{mode}-{phase}.json') for phase in ['prepare', 'resume']]
    assert prepare['status'] == f'Credential removal relaunch checks passed: {mode} prepare'
    assert resume['status'] == f'Credential removal relaunch checks passed: {mode} resume'
    assert len(prepare['checks']) == 9 and len(resume['checks']) == 11
    assert prepare['pid'] == prepare['originalPID'] == resume['originalPID'] and prepare['pid'] != resume['pid']
current_connection = read('connection-r10-report.json')
assert current_connection['status'] == 'Connection storage checks passed' and current_connection['cleanupVerified'] and len(current_connection['checks']) == 22 and all(row['passed'] for row in current_connection['checks'])
assert read('connection-r10-summary.json')['passedTests'] == 2 and read('connection-r10-summary.json')['failedTests'] == read('connection-r10-summary.json')['skippedTests'] == 0
for mode in ['oauth', 'all', 'key']:
    prepare, resume = [read(f'removal-r10-{mode}-{phase}.json') for phase in ['prepare', 'resume']]
    assert prepare['status'] == f'Credential removal relaunch checks passed: {mode} prepare' and len(prepare['checks']) == 9
    assert resume['status'] == f'Credential removal relaunch checks passed: {mode} resume' and len(resume['checks']) == 11
    assert prepare['pid'] == resume['originalPID'] and prepare['pid'] != resume['pid']
current_signin = read('signin-r10-report.json')
current_signin_host = read('signin-r10-host-readback.json')
assert current_signin['status'] == 'Provider sign-in checks passed' and current_signin['cleanupVerified'] and current_signin['invalidClientsRejected'] and current_signin['host'] == current_signin_host
assert len(current_signin['observations']) == 16 and {row['mode'] for row in current_signin['observations']} == set(signins)
assert current_signin_host['loginRequests'] == current_signin_host['loginResponses'] == 10 and not current_signin_host['packets'] and current_signin_host['holdTimeouts'] == current_signin_host['tokenRequests'] == 0
assert all(row['pkceMatches'] and row['redirectMatches'] and row['reservedCodeDecoded'] for row in current_signin_host['loginAudit'])
assert read('signin-r10-summary.json')['passedTests'] == 1 and read('signin-r10-summary.json')['failedTests'] == read('signin-r10-summary.json')['skippedTests'] == 0
assert read('connection-ui-r9-summary.json')['failedTests'] == 1
ui_host = read('connection-ui-r10-host-readback.json')
assert not ui_host['packets'] and ui_host['tokenRequests'] == ui_host['loginRequests'] == ui_host['holdTimeouts'] == 0
assert [row['checkpoint'] for row in ui_host['uiReadbacks']] == ['opened', 'typed', 'kept-draft', 'failed-save', 'saved', 'reopened', 'relaunched', 'removed']
ui = {row['checkpoint']: row['state'] for row in ui_host['uiReadbacks']}
assert len({row['state']['nonce'] for row in ui_host['uiReadbacks']}) == 1
for name in ['opened', 'typed', 'kept-draft', 'failed-save']:
    assert ui[name]['apiKeyClass'] == 'fixture-a' and ui[name]['preset'] == 'custom' and ui[name]['recordSHA256'] == ui['opened']['recordSHA256']
    assert ui[name]['dirty'] == (name != 'opened')
assert not ui['failed-save']['configured']
for name in ['saved', 'reopened', 'relaunched']:
    assert ui[name]['apiKeyClass'] == 'fixture-b' and ui[name]['recordSHA256'] == ui['saved']['recordSHA256'] and not ui[name]['dirty'] and ui[name]['configured']
assert ui['saved']['recordSHA256'] != ui['opened']['recordSHA256'] and ui['relaunched']['pid'] != ui['opened']['pid']
assert ui['removed']['apiKeyClass'] == 'missing' and not ui['removed']['oauthAccountPresent'] and not ui['removed']['legacyAPIKeyPresent'] and not ui['removed']['configured'] and ui['removed']['mode'] == 'onDevice'
assert Counter(json.dumps(row['state'], sort_keys=True) for row in ui_host['uiReadbacks']) == Counter(json.dumps(row['data'], sort_keys=True) for row in read('connection-ui-r10-xctest-readbacks.json'))
assert read('connection-ui-r10-summary.json')['passedTests'] == 1 and read('connection-ui-r10-summary.json')['failedTests'] == read('connection-ui-r10-summary.json')['skippedTests'] == 0
assert [path for path in read('connection-source-r9.json')['files'] if read('connection-source-r9.json')['files'][path] != read('connection-source-r10.json')['files'][path]] == ['scripts/provider-authorization-server.py']
if args.current_source:
    for path, facts in read(args.current_source)['files'].items():
        data = (repo / path).read_bytes()
        assert len(data) == facts['bytes'] and hashlib.sha256(data).hexdigest() == facts['sha256'], path
original_bytes = {}
for prefix in ['storage-source-r1', 'storage-source-r2', 'auth-source-r1', 'auth-source-r2', 'auth-source-r3', 'auth-source-r4', 'removal-source-r5', 'caller-source-r6', 'caller-source-r7', 'connection-source-r8', 'connection-source-r9', 'connection-source-r10', 'connection-source-r11', 'connection-source-r12', 'connection-source-r13', 'connection-source-r14', 'connection-source-r15', 'connection-source-r16']:
    source = read(prefix + '.json')
    changes = json.loads(gzip.decompress((base / (prefix + '-changes.json.gz')).read_bytes()))
    for path, facts in source['files'].items():
        if path in changes:
            data = changes[path].encode()
        else:
            key = (source['baseCommit'], path)
            if key not in original_bytes:
                original_bytes[key] = subprocess.check_output(['git', 'show', f'{key[0]}:{key[1]}'], cwd=repo)
            data = original_bytes[key]
        assert len(data) == facts['bytes'] and hashlib.sha256(data).hexdigest() == facts['sha256'], (prefix, path)
for revision in [17, 18, 19, 20, 21, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43]:
    prefix = f'connection-source-r{revision}'
    source = read(prefix + '.json')
    changes = json.loads(gzip.decompress((base / (prefix + '-changes.json.gz')).read_bytes()))
    assert len(source['files']) == 216
    for path, facts in source['files'].items():
        if path in changes:
            data = changes[path].encode()
        else:
            key = (source['baseCommit'], path)
            if key not in original_bytes:
                original_bytes[key] = subprocess.check_output(['git', 'show', key[0] + ':' + path], cwd=repo)
            data = original_bytes[key]
        assert len(data) == facts['bytes'] and hashlib.sha256(data).hexdigest() == facts['sha256'], (prefix, path)
    if revision > 17:
        previous = read(f'connection-source-r{21 if revision == 23 else revision-1}.json')
        changed = [p for p in source['files'] if source['files'][p] != previous['files'][p]]
        expected = ['Lumen/Views/SettingsView.swift'] if revision in [30, 31] else (['Lumen/Services/LLMConnectionService.swift', 'Lumen/Views/SettingsView.swift'] if revision == 29 else (['scripts/provider-authorization-server.py'] if revision == 28 else (['Lumen/Views/SettingsView.swift', 'LumenUITests/LumenSmokeTests.swift'] if revision in [23, 24, 32] else ['LumenUITests/LumenSmokeTests.swift'])))
        if revision in [34, 41]:
            expected = ['Lumen/Views/SettingsView.swift']
        if revision == 37:
            expected = ['Lumen/Views/SettingsView.swift', 'LumenUITests/LumenSmokeTests.swift']
        assert changed == expected
for prefix, passed, failed, count, image_count in [
    ('connection-ui-compact-r16', 3, 1, 41, 28),
    ('connection-ui-r17', 2, 1, 31, 27),
    ('connection-modes-ui-r18', 0, 1, 6, 8),
    ('connection-modes-ui-r19', 0, 1, 3, 2),
    ('connection-modes-ui-r20', 0, 1, 3, 2),
    ('connection-modes-ui-r21', 0, 1, 7, 9),
    ('connection-keyboard-modes-ui-r22', 1, 1, 17, 19),
    ('connection-ui-r23', 2, 1, 23, 21),
    ('connection-ui-r24', 1, 1, 13, 11),
    ('connection-ui-r25', 2, 1, 19, 14),
    ('connection-ui-r26', 1, 0, 4, 1),
    ('connection-ui-r27', 1, 0, 15, 14),
    ('connection-ui-compact-r28', 5, 1, 41, 34),
    ('connection-ui-r29', 1, 0, 15, 26),
    ('connection-ui-main-r30', 9, 6, 64, 50),
    ('connection-ui-main-r31', 6, 0, 99, 88),
    ('connection-ui-r33', 0, 2, 3, 0),
    ('connection-ui-r34', 2, 0, 10, 3),
    ('connection-ui-r35', 1, 1, 13, 19),
    ('connection-ui-r36', 1, 1, 7, 3),
    ('connection-ui-r37', 0, 1, 1, 1),
    ('connection-ui-r38', 1, 0, 4, 3),
    ('connection-ui-r39', 5, 1, 51, 39),
    ('connection-ui-r40', 0, 1, 3, 5),
    ('connection-ui-r41', 0, 1, 3, 6),
    ('connection-ui-r42', 6, 0, 63, 66),
    ('connection-ui-main-r43', 12, 3, 131, 114),
    ('connection-ui-main-r44', 0, 1, 5, 8),
    ('connection-ui-main-r45', 0, 1, 7, 14),
    ('connection-ui-main-r46', 2, 1, 42, 68),
    ('connection-ui-main-r48', 2, 0, 19, 44),
    ('connection-ui-compact-r49', 2, 0, 19, 56),
    ('connection-ui-compact-r50', 4, 0, 22, 8),
    ('connection-ui-compact-r51', 14, 0, 144, 141),
    ('connection-ui-compact-r52', 3, 0, 18, 6),
]:
    summary = read(prefix + '-summary.json')
    host = read(prefix + '-host-readback.json')
    reads = read(prefix + '-xctest-readbacks.json')
    images = read(prefix + '-images.json')
    assert (summary['passedTests'], summary['failedTests'], summary['skippedTests']) == (passed, failed, 0)
    assert len(host['uiReadbacks']) == len(reads) == count and len(images) == image_count
    assert Counter(json.dumps(r['data'], sort_keys=True) for r in reads) == Counter(json.dumps(r['state'], sort_keys=True) for r in host['uiReadbacks'])
    for row in images:
        data = (repo / row['repositoryPath']).read_bytes()
        assert len(data) == row['bytes'] and hashlib.sha256(data).hexdigest() == row['sha256']
    if prefix == 'connection-ui-r37':
        assert not summary.get('runtimeWarnings'), 'This failed selection trial recorded no frame warning'
    else:
        assert summary.get('runtimeWarnings'), 'Retain observed frame warnings; do not claim clean UI acceptance'
native_keyboard = read('connection-ui-compact-r52-native-images.json')
keyboard_reads = read('connection-ui-compact-r52-xctest-readbacks.json')
assert len(native_keyboard) == 6
for row in native_keyboard:
    data = (repo / row['repositoryPath']).read_bytes()
    assert len(data) == row['bytes'] and hashlib.sha256(data).hexdigest() == row['sha256']
    assert sum(item['data'] == row['state'] and ('provider-ui-' + row['checkpoint']) in item['attachment'] for item in keyboard_reads) == 1
nonces = {row['state']['nonce'] for row in native_keyboard}
assert len(nonces) == 3
for nonce in nonces:
    states = {}
    for phase in ['opened', 'focused', 'touched-key', 'done', 'discard-reopened', 'cleaned']:
        matches = [row['data'] for row in keyboard_reads if row['data']['nonce'] == nonce and ('provider-ui-keyboard-' + phase + '_') in row['attachment']]
        assert len(matches) == 1, (nonce, phase)
        states[phase] = matches[0]
    assert len({states[phase]['recordSHA256'] for phase in states if phase != 'cleaned'}) == 1
    assert [states[phase]['dirty'] for phase in ['opened', 'focused', 'touched-key', 'done', 'discard-reopened']] == [False, False, True, True, False]
    assert states['cleaned']['apiKeyClass'] == 'missing' and not states['cleaned']['oauthAccountPresent']
    assert {row['checkpoint'] for row in native_keyboard if row['state']['nonce'] == nonce} == {'keyboard-touched-key', 'keyboard-done'}
for revision, count in [(1, 8), (2, 2)]:
    reference = read(f'literal-field-reference-r{revision}.json')
    assert hashlib.sha256((base / reference['source']).read_bytes()).hexdigest() == reference['sourceSHA256']
    assert len(reference['captures']) == count
    for row in reference['captures']:
        assert hashlib.sha256((base / row['screenshot']).read_bytes()).hexdigest() == row['sha256']
helper = read('connection-ui-r31-identity.json')
assert hashlib.sha256(gzip.decompress((base / helper['helperSource']).read_bytes())).hexdigest() == helper['helperSHA256']
assert helper['helperSHA256'] == read('connection-source-r28.json')['files']['scripts/provider-authorization-server.py']['sha256']
assert read('connection-ui-r29-self-inspection.json')['images'] == read('connection-ui-r29-images.json')
manual = read('manual-keyboard-r32.json')
assert manual['binarySHA256'] == 'f1ba3e4312b8b9f236882e1a4687e175cda33fd128c66cda63d597707b3eacd6'
for path, facts in manual['files'].items():
    data = (base / path).read_bytes()
    assert len(data) == facts['bytes'] and hashlib.sha256(data).hexdigest() == facts['sha256']
manual_states = [read('ManualKeyboardR32-' + phase + '.json') for phase in ['before', 'typed', 'done', 'reopened']]
assert all(row['nonce'] == manual['nonce'] and row['apiKeyClass'] == 'fixture-a' for row in manual_states)
assert len({row['recordSHA256'] for row in manual_states}) == 1
assert [row['dirty'] for row in manual_states] == [False, True, True, False]
for revision in [1, 2]:
    reference = read(f'keyboard-reference-r{revision}.json')
    for path, facts in reference['files'].items():
        data = (base / path).read_bytes()
        assert len(data) == facts['bytes'] and hashlib.sha256(data).hexdigest() == facts['sha256']
    warnings = json.loads(gzip.decompress((base / f'KeyboardReferenceWarningsR{revision}.json.gz').read_bytes()))
    pids = [reference['processID']] if revision == 1 else [reference['normalPID'], reference['securePID']]
    for pid in pids:
        rows = [row for row in warnings if row.get('processID') == pid]
        assert len(rows) == 1
        assert [(frame['imageUUID'], frame['imageOffset']) for frame in rows[0]['backtrace']['frames'][:3]] == [
            ('F15F494F-B1FF-392B-B682-B2F2DD366E23', 9053084),
            ('F15F494F-B1FF-392B-B682-B2F2DD366E23', 9043420),
            ('480EC830-2694-3017-BEA4-230C8818DDED', 12065900),
        ]
assert read('keyboard-r23-visual-rejection.json')['visualAcceptance'] is False
assert read('keyboard-r24-visual-rejection.json')['visualAcceptance'] is False
assert read('keyboard-r25-model-pixel-review.json')['visualAcceptance'] is True
keyboard_reads = read('connection-ui-r25-host-readback.json')['uiReadbacks']
for nonce in {r['state']['nonce'] for r in keyboard_reads if r['checkpoint'] == 'keyboard-opened'}:
    states = {r['checkpoint']: r['state'] for r in keyboard_reads if r['state']['nonce'] == nonce}
    opened = states['keyboard-opened']
    for checkpoint, dirty in [('keyboard-focused', False), ('keyboard-touched-key', True), ('keyboard-done', True), ('keyboard-discard-reopened', False)]:
        assert states[checkpoint]['recordSHA256'] == opened['recordSHA256'] and states[checkpoint]['dirty'] is dirty
        assert states[checkpoint]['oauthAccountSHA256'] == opened['oauthAccountSHA256'] and states[checkpoint]['apiKeyClass'] == 'fixture-a'
    assert states['keyboard-cleaned']['apiKeyClass'] == 'missing' and not states['keyboard-cleaned']['oauthAccountPresent'] and not states['keyboard-cleaned']['configured']
modes_host = read('connection-ui-r27-host-readback.json')
modes = {r['checkpoint']: r['state'] for r in modes_host['uiReadbacks']}
assert len(modes) == 15 and len({r['nonce'] for r in modes.values()}) == 1
assert modes_host['tokenRequests'] == modes_host['loginRequests'] == modes_host['holdTimeouts'] == len(modes_host['packets']) == 0
opened = modes['modes-opened']
for checkpoint in ['preset-openai-draft', 'preset-google-draft', 'api-settings-draft']:
    assert modes[checkpoint]['recordSHA256'] == opened['recordSHA256'] and modes[checkpoint]['authorizationRevision'] == opened['authorizationRevision']
api = modes['api-settings-saved']
assert api['apiEndpointClass'] == api['modelClass'] == 'fixture-b' and not api['preferExternal']
assert modes['api-settings-reopened']['recordSHA256'] == modes['oauth-mode-draft']['recordSHA256'] == modes['oauth-settings-draft']['recordSHA256'] == api['recordSHA256']
assert modes['oauth-mode-draft']['mode'] == 'key' and modes['oauth-settings-draft']['dirty']
oauth = modes['oauth-settings-saved']
for key in ['oauthClientClass', 'oauthScopeClass', 'oauthEndpointClass', 'oauthModelClass']:
    assert modes['oauth-settings-draft'][key] == 'fixture-a' and oauth[key] == 'fixture-b'
assert oauth['mode'] == 'oauth' and not oauth['configured']
assert modes['oauth-settings-reopened']['recordSHA256'] == modes['builtin-mode-draft']['recordSHA256'] == oauth['recordSHA256']
built_in = modes['builtin-mode-saved']
assert built_in['mode'] == 'onDevice' and not built_in['configured']
assert modes['builtin-reopened']['recordSHA256'] == built_in['recordSHA256']
restored = modes['api-mode-restored']
assert restored['mode'] == 'key' and restored['apiEndpointClass'] == restored['modelClass'] == 'fixture-b' and not restored['preferExternal']
for checkpoint, row in modes.items():
    if checkpoint != 'modes-cleaned':
        assert row['apiKeyClass'] == 'fixture-a' and row['oauthAccountSHA256'] == opened['oauthAccountSHA256']
assert modes['modes-cleaned']['apiKeyClass'] == 'missing' and not modes['modes-cleaned']['oauthAccountPresent'] and not modes['modes-cleaned']['configured']
large_host = read('connection-ui-r29-host-readback.json')
large_modes = {r['checkpoint']: r['state'] for r in large_host['uiReadbacks']}
assert set(large_modes) == set(modes) and len({r['nonce'] for r in large_modes.values()}) == 1
assert large_host['tokenRequests'] == large_host['loginRequests'] == large_host['holdTimeouts'] == len(large_host['packets']) == 0
for checkpoint, row in large_modes.items():
    for key in ['apiEndpointClass', 'apiKeyClass', 'mode', 'modelClass', 'preferExternal', 'oauthClientClass', 'oauthScopeClass', 'oauthEndpointClass', 'oauthModelClass', 'configured', 'dirty', 'globalRemovalPending', 'keyRemovalPending', 'legacyCleanupPending', 'oauthAccountPresent']:
        assert row[key] == modes[checkpoint][key], (checkpoint, key)
    if checkpoint != 'modes-cleaned':
        assert row['oauthAccountSHA256'] == large_modes['modes-opened']['oauthAccountSHA256']
for checkpoints in [
    ['modes-opened', 'preset-openai-draft', 'preset-google-draft', 'api-settings-draft'],
    ['api-settings-saved', 'api-settings-reopened', 'oauth-mode-draft', 'oauth-settings-draft'],
    ['oauth-settings-saved', 'oauth-settings-reopened', 'builtin-mode-draft'],
    ['builtin-mode-saved', 'builtin-reopened'],
]:
    assert len({large_modes[c]['recordSHA256'] for c in checkpoints}) == 1
main_host = read('connection-ui-main-r31-host-readback.json')
assert main_host['tokenRequests'] == main_host['loginRequests'] == main_host['holdTimeouts'] == 0
assert len(main_host['packets']) == 1, 'Retain the manual compact connectivity request; do not claim zero traffic'
packet = main_host['packets'][0]
assert packet['kind'] == 'connectivity' and packet['route'] == '/caller-chat' and packet['credential'] == 'api-key-fixture'
assert packet['bodySHA256'] == '2528215503ec30f81477291fd45569a5d0179b030ec31a74e15cbf3af7af1065'
groups = {}
for row in main_host['uiReadbacks']:
    groups.setdefault(row['state']['nonce'], {})[row['checkpoint']] = row['state']
main_modes = [group for group in groups.values() if 'modes-opened' in group]
assert len(main_modes) == 3 and len(groups) == 15
for group in main_modes:
    assert set(group) == set(modes)
    for checkpoint, state in group.items():
        for key in ['apiEndpointClass', 'apiKeyClass', 'mode', 'modelClass', 'preferExternal', 'oauthClientClass', 'oauthScopeClass', 'oauthEndpointClass', 'oauthModelClass', 'configured', 'dirty', 'globalRemovalPending', 'keyRemovalPending', 'legacyCleanupPending', 'oauthAccountPresent']:
            assert state[key] == modes[checkpoint][key], (checkpoint, key)
        if checkpoint != 'modes-cleaned': assert state['oauthAccountSHA256'] == group['modes-opened']['oauthAccountSHA256']
for group in groups.values():
    if 'modes-opened' in group: continue
    kind = next(iter(group)).split('-')[0]
    assert kind in ['cleanup', 'remove', 'stale', 'discard']
    opened = group[kind + '-opened']
    cleaned = group[kind + '-cleaned']
    assert cleaned['apiKeyClass'] == 'missing' and not cleaned['oauthAccountPresent'] and not cleaned['configured']
    if kind in ['cleanup', 'remove']:
        pending, resumed, retried = [group[kind + '-' + phase] for phase in ['pending', 'resumed', 'retried']]
        assert pending['recordSHA256'] == resumed['recordSHA256'] and pending['pid'] != resumed['pid']
        flag = 'legacyCleanupPending' if kind == 'cleanup' else 'keyRemovalPending'
        assert pending[flag] and not pending['configured'] and not resumed['configured']
        assert not retried['legacyCleanupPending'] and not retried['keyRemovalPending'] and not retried['legacyAPIKeyPresent']
        assert retried['apiKeyClass'] == ('fixture-b' if kind == 'cleanup' else 'missing') and retried['configured'] == (kind == 'cleanup')
    elif kind == 'stale':
        rejected, kept, reloaded = [group['stale-' + phase] for phase in ['rejected', 'kept', 'reloaded']]
        assert rejected['modelClass'] == 'fixture-b' and rejected['apiKeyClass'] == 'fixture-a' and rejected['dirty'] and kept['dirty']
        assert reloaded['recordSHA256'] == rejected['recordSHA256'] and not reloaded['dirty']
    else:
        assert group['discard-reopened']['recordSHA256'] == opened['recordSHA256'] and not group['discard-reopened']['dirty']
candidate_host = read('connection-ui-r34-host-readback.json')
assert candidate_host['tokenRequests'] == candidate_host['loginRequests'] == candidate_host['holdTimeouts'] == len(candidate_host['packets']) == 0
candidate = {r['checkpoint']: r['state'] for r in candidate_host['uiReadbacks']}
assert candidate['scope-diagnostic-edited']['dirty'] and candidate['scope-diagnostic-edited']['recordSHA256'] == candidate['scope-diagnostic-opened']['recordSHA256'] == candidate['scope-diagnostic-discarded']['recordSHA256']
assert candidate['keyboard-touched-key']['dirty'] and candidate['keyboard-done']['dirty']
assert len({candidate[c]['recordSHA256'] for c in ['keyboard-opened', 'keyboard-focused', 'keyboard-touched-key', 'keyboard-done', 'keyboard-discard-reopened']}) == 1
assert not candidate['keyboard-discard-reopened']['dirty']
for c in ['scope-diagnostic-cleaned', 'keyboard-cleaned']:
    assert candidate[c]['apiKeyClass'] == 'missing' and not candidate[c]['oauthAccountPresent']
assert read('connection-ui-r34-self-inspection.json')['originals'] == read('connection-ui-r34-images.json')
print('Additional UI progress through trial R27 at source R26: full compact-normal modes15, isolated scopes4, model-keyboard6 with drawn keys, exact host/source/image identities. Main R30/R31 together pass15 distinct main-device cases on frozen sourceR27, retain6 earlier host-cap failures and1manual connectivity packet. Native warnings remain. Current candidate sourceR30 is separate; pixels/critic/final regressions/Release/publication remain open.')
print('Largest compact modes R29 passes the same15 semantic checkpoints at source R27; R28 retains5 passes/1 failed scroll-direction trial. All26 R29 originals reviewed with copy/label/literal-wrap issues open. Main R30 retains9 passes/6 host-cap failures,64 matched states/50 originals. Source R28 changes only the bounded synthetic helper; R31 runs on unchanged build R27. Remaining style/main pixels, UI polish and continuing critique remain open.')
for name in ['storager1-images.json', 'storager2-images.json', 'authr2-images.json', 'signinr4-images.json', 'removalr5-images.json', 'callerr6-images.json', 'authr6-images.json', 'callerr7-images.json']:
    rows = read(name)
    assert len(rows) == 1
    for row in rows:
        assert hashlib.sha256((repo / row['repositoryPath']).read_bytes()).hexdigest() == row['sha256']
rows = read('connectionr8-images.json')
assert len(rows) == 2
for row in rows:
    data = (repo / row['repositoryPath']).read_bytes()
    assert len(data) == row['bytes'] and hashlib.sha256(data).hexdigest() == row['sha256']
for name, count in [('connectionr10', 2), ('authr10', 1), ('callerr10', 1), ('signinr10', 1), ('connection-ui-r10', 8), ('authr11', 1), ('callerr12', 1), ('connection-ui-r12', 17), ('account-reset-r13', 1), ('account-reset-r14', 6), ('token-transport-r16', 1), ('authr16', 1), ('signinr16', 1)]:
    rows = read(name + '-images.json'); assert len(rows) == count
    for row in rows:
        data = (repo / row['repositoryPath']).read_bytes()
        assert len(data) == row['bytes'] and hashlib.sha256(data).hexdigest() == row['sha256']
for path in base.glob('*.gz'):
    with gzip.open(path, 'rb') as stream:
        while stream.read(1024 * 1024):
            pass
auth11, host11, summary11 = [read('auth-r11-' + name + '.json') for name in ['report', 'host-readback', 'summary']]
assert auth11['status'] == 'Provider authorization checks passed' and auth11['cleanupVerified'] and auth11['host'] == host11
assert summary11['passedTests'] == 1 and summary11['failedTests'] == summary11['skippedTests'] == 0
assert len(auth11['observations']) == 27 and host11['tokenRequests'] == host11['tokenResponses'] == 17
assert len(host11['packets']) == 5 and host11['holdTimeouts'] == 0
extra_modes = {'connection-preference', 'connection-preset', 'connection-api-endpoint', 'connection-api-model', 'connection-api-key'}
assert {row['mode'] for row in auth11['observations']} == set(observations) | extra_modes
for row in auth11['observations']:
    if row['mode'] in extra_modes:
        assert row['authorizationChanged'] and row['outgoingRequests'] == 0 and not row['replyAccepted']
        assert row['accountIdentityPreserved'] and row['legacySourcesAbsent']
caller12, host12, summary12 = [read('caller-r12-' + name + '.json') for name in ['report', 'host-readback', 'summary']]
assert caller12['status'] == 'Provider caller checks passed' and caller12['cleanupVerified'] and caller12['host'] == host12
assert summary12['passedTests'] == 1 and summary12['failedTests'] == summary12['skippedTests'] == 0
assert len(caller12['observations']) == 33 and len(host12['packets']) == 20
assert caller12['observations'][:27] == read('caller-r10-report.json')['observations']
assert host12['tokenRequests'] == host12['loginRequests'] == host12['holdTimeouts'] == 0
connectivity = {row['mode']: row for row in caller12['observations'] if row['caller'] == 'connectivity'}
assert set(connectivity) == {'unchanged', 'stale-before-task', 'submission-change', 'response-change', 'response-revert', 'overlap'}
for mode, row in connectivity.items():
    assert row['accepted'] == (mode in {'unchanged', 'overlap'})
    assert row['outgoingRequests'] == (2 if mode == 'overlap' else 1 if mode == 'unchanged' or mode.startswith('response-') else 0)
assert sum(packet.get('staleConnectivityReply') is True for packet in host12['packets']) == 1
assert read('caller-r11-collection-failure.json')['onlyDifferenceVerified'] is True
assert [path for path in read('connection-source-r11.json')['files'] if read('connection-source-r11.json')['files'][path] != read('connection-source-r12.json')['files'][path]] == ['Lumen/Services/ProviderAuthorizationNativeProbe.swift']
ui12 = read('connection-ui-r12-host-readback.json')
summary12 = read('connection-ui-r12-summary.json')
assert summary12['passedTests'] == 2 and summary12['failedTests'] == summary12['skippedTests'] == 0
assert len(ui12['uiReadbacks']) == 28 and len({row['state']['nonce'] for row in ui12['uiReadbacks']}) == 5
assert Counter(json.dumps(row['state'], sort_keys=True) for row in ui12['uiReadbacks']) == Counter(json.dumps(row['data'], sort_keys=True) for row in read('connection-ui-r12-xctest-readbacks.json'))
states = {row['checkpoint']: row['state'] for row in ui12['uiReadbacks']}
assert len(states) == 28
assert states['before-open']['authorizationRevision'] == states['opened']['authorizationRevision'] == states['typed']['authorizationRevision']
for name in ['opened', 'typed', 'kept-draft', 'failed-save']:
    assert states[name]['recordSHA256'] == states['before-open']['recordSHA256'] and states[name]['apiKeyClass'] == 'fixture-a'
for name in ['saved', 'tested-saved', 'reopened', 'relaunched']:
    assert states[name]['recordSHA256'] == states['saved']['recordSHA256'] and states[name]['apiKeyClass'] == 'fixture-b' and states[name]['configured'] and not states[name]['dirty']
assert states['tested-saved']['testResultClass'] == 'success' and states['relaunched']['pid'] != states['opened']['pid']
assert ui12['tokenRequests'] == ui12['loginRequests'] == ui12['holdTimeouts'] == 0 and len(ui12['packets']) == 1
assert ui12['packets'][0]['kind'] == 'connectivity' and ui12['packets'][0]['credential'] == 'replacement-key-fixture'
for mode, flag in [('cleanup', 'legacyCleanupPending'), ('remove', 'keyRemovalPending')]:
    pending, resumed, retried = [states[mode + '-' + phase] for phase in ['pending', 'resumed', 'retried']]
    assert pending[flag] and resumed[flag] and not pending['configured'] and not resumed['configured']
    assert pending['recordSHA256'] == resumed['recordSHA256'] and pending['pid'] != resumed['pid']
    assert not retried['legacyCleanupPending'] and not retried['keyRemovalPending'] and not retried['legacyAPIKeyPresent']
    assert retried['configured'] == (mode == 'cleanup') and retried['apiKeyClass'] == ('fixture-b' if mode == 'cleanup' else 'missing')
assert states['stale-rejected']['modelClass'] == 'fixture-b' and states['stale-rejected']['apiKeyClass'] == 'fixture-a'
assert states['stale-rejected']['dirty'] and states['stale-kept']['dirty'] and not states['stale-reloaded']['dirty']
assert states['stale-rejected']['recordSHA256'] == states['stale-reloaded']['recordSHA256']
assert states['discard-opened']['recordSHA256'] == states['discard-reopened']['recordSHA256'] and not states['discard-reopened']['dirty']
for name in ['removed', 'cleanup-cleaned', 'remove-cleaned', 'stale-cleaned', 'discard-cleaned']:
    assert states[name]['apiKeyClass'] == 'missing' and not states[name]['oauthAccountPresent']
assert read('account-reset-r13-summary.json')['failedTests'] == 1
assert read('account-reset-r13-failure-prepare.json')['status'] == 'Account reset checks passed: failure prepare'
assert read('account-reset-r13-failure-resume.json')['status'] == 'Account reset checks failed: exact original profile and local fixture bytes remain'
for mode in ['failure', 'after-secrets']:
    prepare, resume = [read('account-reset-r14-' + mode + '-' + phase + '.json') for phase in ['prepare', 'resume']]
    assert prepare['status'] == 'Account reset checks passed: ' + mode + ' prepare' and len(prepare['checks']) == 7
    assert resume['status'] == 'Account reset checks passed: ' + mode + ' resume' and len(resume['checks']) == 17
    assert prepare['pid'] == prepare['originalPID'] == resume['originalPID'] and resume['pid'] != prepare['pid']
reset_summary = read('account-reset-r14-summary.json')
assert reset_summary['passedTests'] == 2 and reset_summary['failedTests'] == reset_summary['skippedTests'] == 0
reset_host = read('account-reset-ui-r14-host-readback.json')
assert reset_host['tokenRequests'] == reset_host['loginRequests'] == reset_host['holdTimeouts'] == 0 and not reset_host['packets']
assert [row['checkpoint'] for row in reset_host['uiReadbacks']] == ['reset-before', 'reset-failed', 'reset-resumed', 'reset-complete']
assert Counter(json.dumps(row['state'], sort_keys=True) for row in reset_host['uiReadbacks']) == Counter(json.dumps(row['data'], sort_keys=True) for row in read('account-reset-ui-r14-xctest-readbacks.json'))
before, failed, resumed, done = [row['state'] for row in reset_host['uiReadbacks']]
assert len({row['state']['nonce'] for row in reset_host['uiReadbacks']}) == 1
assert before['profileSHA256'] == failed['profileSHA256']
assert before['profileContentSHA256'] == failed['profileContentSHA256'] == resumed['profileContentSHA256']
assert before['recordSHA256'] == failed['recordSHA256'] == resumed['recordSHA256'] and failed['pid'] != resumed['pid']
assert failed['globalRemovalPending'] and resumed['globalRemovalPending'] and not failed['configured'] and not resumed['configured']
assert done['profileSHA256'] != before['profileSHA256'] and done['apiKeyClass'] == 'missing' and not done['oauthAccountPresent'] and not done['globalRemovalPending'] and not done['configured']
assert set(path for path in read('connection-source-r13.json')['files'] if read('connection-source-r13.json')['files'][path] != read('connection-source-r14.json')['files'][path]) == {'Lumen/Services/ProviderConnectionNativeProbe.swift', 'LumenUITests/LumenSmokeTests.swift'}
token, token_host, token_summary = [read('token-transport-r16-' + name + '.json') for name in ['report', 'host-readback', 'summary']]
assert token['status'] == 'Token transport checks passed' and token['cleanupVerified'] and token['host'] == token_host
assert token_summary['passedTests'] == 1 and token_summary['failedTests'] == token_summary['skippedTests'] == 0
assert len(token['observations']) == 45 and len(token_host['tokenTransportAudit']) == token_host['tokenTransportResponses'] == 39
assert token_host['tokenRedirectHits'] == token_host['holdTimeouts'] == token_host['tokenRequests'] == token_host['loginRequests'] == 0
assert len(token_host['packets']) == 5
expected_modes = {'valid', 'mixed-case-bearer', 'malformed', 'duplicate', 'escaped-duplicate', 'nested-duplicate', 'error', 'null-error', 'http-error', 'oversized-header', 'oversized-chunked', 'redirect', 'wrong-type', 'wrong-token-type', 'zero-expiry', 'invalid-token', 'invalid-utf8', 'non-object', 'cancelled', 'cancel-before-task'}
for flow in ['refresh', 'login']:
    rows = [row for row in token['observations'] if row['flow'] == flow and row['mode'] != 'cancelled-shared-waiter']
    assert len(rows) == 20 and {row['mode'] for row in rows} == expected_modes
    for row in rows:
        positive = row['mode'] in {'valid', 'mixed-case-bearer'}
        assert row['accepted'] == positive and row['accountBytesPreserved'] == (not positive)
        assert row['accountBytesPreserved'] == (row['accountBeforeSHA256'] == row['accountAfterSHA256'])
        assert row['accountIdentityPreserved'] == (flow == 'refresh' or not positive)
        assert row['tokenExchanges'] == (0 if row['mode'] == 'cancel-before-task' else 1) and row['chatPackets'] == int(positive)
shared = next(row for row in token['observations'] if row['mode'] == 'cancelled-shared-waiter')
assert shared['accepted'] and not shared['accountBytesPreserved'] and shared['accountIdentityPreserved'] and shared['tokenExchanges'] == shared['chatPackets'] == 1
direct = [row for row in token['observations'] if row['flow'] == 'transport']
assert {row['mode'] for row in direct} == {'empty-request', 'oversized-request', 'withdrawn-before-submit', 'cancelled-before-submit'}
assert all(not row['accepted'] and row['accountBytesPreserved'] and row['accountBeforeSHA256'] == row['accountAfterSHA256'] and row['tokenExchanges'] == row['chatPackets'] == 0 for row in direct)
assert Counter(row['requestKind'] for row in token_host['tokenTransportAudit']) == {'refresh': 20, 'login': 19}
for row in token_host['tokenTransportAudit']:
    assert row['formMatches'] and row['cookieAbsent'] and (row['requestKind'] != 'login' or row['pkceMatches'])
    assert row['statusCode'] == (307 if row['caseName'] == 'redirect' else 503 if row['caseName'] == 'http-error' else 200)
    if row['caseName'].startswith('oversized-'):
        assert row['payloadBytes'] == 128001 and row['advertisedBytes'] == (128001 if row['caseName'] == 'oversized-header' else -1)
    if row['caseName'] == 'cancelled': assert row['streamStarted']
for packet in token_host['packets']:
    assert packet['route'] == '/chat-a' and packet['model'] == 'synthetic-provider-42-a' and packet['credential'] == 'refreshed-fixture' and packet['systemCanary']
failed_token = read('token-transport-r15-report.json')
assert failed_token['host'] == read('token-transport-r15-host-readback.json') and read('token-transport-r15-summary.json')['failedTests'] == 1
assert failed_token['status'].endswith('refresh/cancel-before-task') and len(failed_token['observations']) == 20
assert failed_token['observations'][-1]['tokenExchanges'] == 1 and not failed_token['observations'][-1]['accountBytesPreserved'] and failed_token['observations'][-1]['chatPackets'] == 0
assert [path for path in read('connection-source-r15.json')['files'] if read('connection-source-r15.json')['files'][path] != read('connection-source-r16.json')['files'][path]] == ['Lumen/Services/LLMConnectionService.swift']
changes15 = json.loads(gzip.decompress((base / 'connection-source-r15-changes.json.gz').read_bytes()))
changes16 = json.loads(gzip.decompress((base / 'connection-source-r16-changes.json.gz').read_bytes()))
assert changes15['Lumen/Services/LLMConnectionService.swift'].replace('guard expected.mode == .oauth,', 'guard !Task.isCancelled, expected.mode == .oauth,', 1).replace('guard expectedRevision.map', 'guard !Task.isCancelled, expectedRevision.map', 1) == changes16['Lumen/Services/LLMConnectionService.swift']
auth16, host16, summary16 = [read('auth-r16-' + name + '.json') for name in ['report', 'host-readback', 'summary']]
assert auth16['status'] == 'Provider authorization checks passed' and auth16['cleanupVerified'] and auth16['host'] == host16
assert summary16['passedTests'] == 1 and summary16['failedTests'] == summary16['skippedTests'] == 0
assert len(auth16['observations']) == 27 and host16['tokenRequests'] == host16['tokenResponses'] == 17 and len(host16['packets']) == 5 and host16['holdTimeouts'] == 0
old_auth = {row['mode']: row for row in auth11['observations']}
for row in auth16['observations']:
    for key in ['accessState', 'accountPresent', 'accountIdentityPreserved', 'legacySourcesAbsent', 'authorizationChanged', 'credentialProblem', 'outgoingRequests', 'replyAccepted']:
        assert row[key] == old_auth[row['mode']][key]
signin16, signin_host16, signin_summary16 = [read('signin-r16-' + name + '.json') for name in ['report', 'host-readback', 'summary']]
assert signin16['status'] == 'Provider sign-in checks passed' and signin16['cleanupVerified'] and signin16['host'] == signin_host16 and signin16['invalidClientsRejected']
assert signin16['observations'] == read('signin-r10-report.json')['observations']
assert signin_summary16['passedTests'] == 1 and signin_summary16['failedTests'] == signin_summary16['skippedTests'] == 0
assert signin_host16['loginRequests'] == signin_host16['loginResponses'] == 10 and signin_host16['tokenRequests'] == signin_host16['holdTimeouts'] == 0 and not signin_host16['packets']
assert all(row['pkceMatches'] and row['redirectMatches'] and row['reservedCodeDecoded'] for row in signin_host16['loginAudit'])
current_review = read('connection-ui-r39-self-inspection.json')
assert current_review['originalsIndividuallyOpenedAndHashMatched'] == 39
assert current_review['images'] == read('connection-ui-r39-images.json')
current_library = read('regression-r39-Lumen-library-checks-report.json')
current_conversation = read('regression-r39-Lumen-conversation-native-report.json')
mixed_host = read('RegressionServerR39.json')
assert current_library['status'] == 'Request authorization checks passed'
assert len(current_library['observations']) == 19
assert current_library['packets'] == mixed_host['personalAudit'][:len(current_library['packets'])]
assert current_conversation['status'] == 'Conversation checks passed'
assert len(current_conversation['checks']) == 49 and all(row['passed'] for row in current_conversation['checks'])
mixed_failure = read('regression-r39-personal-failed-report.json')
assert mixed_failure['status'] == 'Personal context checks failed: actual production HTTP request arrives once at the synthetic audit route'
personal40 = read('personal-r40-report.json')
assert personal40['status'] == 'Personal context checks passed'
assert len(personal40['checks']) == 43 and all(row['passed'] for row in personal40['checks'])
assert personal40['requests'] == read('personal-r40-host-readback.json')['personalAudit'] and len(personal40['requests']) == 8
assert read('personal-r40-summary.json')['passedTests'] == 1
assert read('personal-r40-summary.json')['failedTests'] == read('personal-r40-summary.json')['skippedTests'] == 0
transport40 = read('transport-r40-report.json')
assert transport40['status'] == 'passed' and len(transport40['cases']) == 15
assert all(row['status'] == 'passed' for row in transport40['cases'])
expected_routes = {row['route']: 1 for row in transport40['cases'] if row['route'] not in ['request-must-not-arrive', 'slow', 'slow-timeout']}
expected_routes['slow'] = 2
transport_routes = read('transport-r40-host-readback.json')['routes']
assert set(transport_routes) == set(expected_routes)
assert all(transport_routes[route]['requests'] == count for route, count in expected_routes.items())
assert read('logic-r39-outcome.json')['exitCode'] == 0 and read('logic-r39-outcome.json')['passed'] == 1619
assert hashlib.sha256(gzip.decompress((base / 'LogicR39.log.gz').read_bytes())).hexdigest() == read('logic-r39-outcome.json')['logSHA256']
print('Current production R34: compact R39 five passes/one model-selection failure retained, 51 matched states, 39 inspected originals; Library19/conversation49/personal43 and transport15 pass at recorded current boundaries. Mixed-server personal failure retained. Source R35/R36 change only native test gestures, not production. Current UI/critic/Release/publication remain open.')
storage42 = read('storage-r42-identity.json')
assert storage42['source'] == 'connection-source-r37.json' and storage42['xctestsPassed'] == 4 and storage42['processPairs'] == 5
assert len(storage42['reports']) == 12
for name, item in storage42['reports'].items():
    data = (base / item['file']).read_bytes()
    assert hashlib.sha256(data).hexdigest() == item['sha256']
    report = json.loads(data)
    assert report['status'] == item['status'] and 'passed' in report['status'] and len(report['checks']) == item['checks']
for kind, modes, counts in [('removal', ['oauth', 'all', 'key'], (9, 11)), ('reset', ['failure', 'after-secrets'], (7, 17))]:
    for mode in modes:
        before = storage42['reports'][f'Lumen-provider-{kind}-{mode}-prepare.json']
        after = storage42['reports'][f'Lumen-provider-{kind}-{mode}-resume.json']
        assert before['pid'] != after['pid'] and before['pid'] == after['originalPID']
        assert (before['checks'], after['checks']) == counts
for name, count in [('Lumen-provider-storage-report.json', 26), ('Lumen-provider-connection-report.json', 22)]:
    report = read(storage42['reports'][name]['file'])
    assert len(report['checks']) == count and all(row['passed'] for row in report['checks'])
assert read('storage-r42-summary.json')['passedTests'] == 4
assert read('storage-r42-summary.json')['failedTests'] == read('storage-r42-summary.json')['skippedTests'] == 0
assert read('storage-r42-self-inspection.json')['originalsIndividuallyOpenedAndHashMatched'] == 7
assert read('storage-r42-self-inspection.json')['images'] == read('storage-r42-images.json')
for row in read('storage-r42-images.json'):
    data = (repo / row['repositoryPath']).read_bytes()
    assert len(data) == row['bytes'] and hashlib.sha256(data).hexdigest() == row['sha256']
print('Source R37 native storage26/whole connection22 and five actual restart pairs pass in StorageR42; 12 exact reports/7 inspected originals retained. These are diagnostic fixtures, not Settings visual acceptance.')
final47 = read('final-provider-r47-identity.json')
assert final47['source'] == 'connection-source-r41.json' and len(final47['completedCases']) == 4
assert final47['applicationSHA256'] == read('connection-ui-r46-identity.json')['applicationSHA256']
for kind, prior, count, tokens, packets, logins in [('auth', 16, 27, 17, 5, 0), ('signin', 16, 16, 0, 0, 10), ('token-transport', 16, 45, 0, 5, 0), ('caller', 12, 33, 0, 20, 0)]:
    report, host, summary = [read(f'{kind}-r47-{suffix}.json') for suffix in ['report', 'host-readback', 'summary']]
    assert report['status'].endswith('checks passed') and report['cleanupVerified'] and report['host'] == host
    assert len(report['observations']) == count and summary['passedTests'] == 1 and summary['failedTests'] == summary['skippedTests'] == 0
    assert host['tokenRequests'] == host['tokenResponses'] == tokens and len(host['packets']) == packets
    assert host['loginRequests'] == host['loginResponses'] == logins and host['holdTimeouts'] == 0
    previous = read(f'{kind}-r{prior}-report.json')['observations']
    current = json.loads(json.dumps(report['observations']))
    if kind == 'auth':
        for rows in [current, previous]:
            for row in rows:
                for packet in row['packets']:
                    packet.pop('bodySHA256', None)  # Per-run body identity remains in the full independent host match above.
    if kind == 'token-transport':
        assert len(host['tokenTransportAudit']) == host['tokenTransportResponses'] == 39 and host['tokenRedirectHits'] == 0
        assert sum(row['accepted'] for row in report['observations']) == 5
        for row in report['observations']:
            if not row['accepted']:
                assert row['accountBeforeSHA256'] == row['accountAfterSHA256']
        for rows in [current, previous]:
            for row in rows:
                row.pop('accountBeforeSHA256'); row.pop('accountAfterSHA256')
    assert current == previous, (kind, 'native behavioral classifications changed')
for row in read('final-provider-r47-self-inspection.json')['images']:
    data = (repo / row['repositoryPath']).read_bytes()
    assert len(data) == row['bytes'] and hashlib.sha256(data).hexdigest() == row['sha256']
print('Current sourceR41 native R47: auth27/signin16/token45/caller33 pass; four independently matched fresh hosts and preserved account-byte rejection outcomes. Original four diagnostic completion frames inspected; no live-provider or design acceptance inferred.')
cleanup16 = read('storage-run-r16.json')
assert cleanup16['sourceSHA256'] == read('connection-source-r16.json')['files']['scripts/provider-authorization-server.py']['sha256']
assert cleanup16['availableDeltaBytes'] == cleanup16['availableAfterBytes'] - cleanup16['availableBeforeBytes'] == cleanup16['creditedRecoveryBytes'] == 8192
assert cleanup16['logicalBytes'] == 14378 and cleanup16['allocatedBytes'] == 16384
print('Historical R16 transport/auth/sign-in proof retained with its explicit source boundaries; failed R15 cancellation control remains failed.')
release = read('release-audit-r1.json')
assert release['status'] == 'passed' and release['source'] == 'connection-source-r43.json' and release['applicationSource'] == 'connection-source-r41.json'
assert release['sourceInputs'] == 216 and release['minimumOSVersion'] == '18.0'
assert set(release['architectures']) == {'arm64', 'x86_64'} and not release['bundledModelPackages']
assert len(release['checkedDevelopmentMarkers']) == 110 and not release['foundDevelopmentMarkers']
assert len(release['debugPositiveControls']) == 59 and len(release['verifiedProductionMarkers']) == 6
for field, name in [('sourceManifestSHA256', 'connection-source-r43.json'), ('auditorSHA256', 'audit-release.py'), ('planSHA256', 'release-audit-plan-r1.json')]:
    assert release[field] == hashlib.sha256((base / name).read_bytes()).hexdigest()
review = read('review-images-b42-r2.json')
assert not review['pending'] and review['applicationSource'] == 'connection-source-r41.json' and review['currentTestSource'] == 'connection-source-r43.json'
assert review['inspection']['selected'] == review['inspection']['opened'] == len(review['images']) == 368
for field in ['hashErrors', 'byteCountErrors', 'imageFailures', 'skips', 'notYetOpened']:
    assert review['inspection'][field] == 0
for row in review['images']:
    data = (repo / row['repositoryPath']).read_bytes()
    assert len(data) == row['bytes'] == row['actualBytes']
    assert hashlib.sha256(data).hexdigest() == row['sha256'] == row['actualSHA256']
    assert row['imageResult'] == 'opened-original'
critique = (base / 'critique-b42-r2.md').read_text()
scores = {name.strip(): int(score) for name, score in re.findall(r'^\|([^|]+)\|\s*([1-5])\s*\|', critique, re.MULTILINE)}
assert len(scores) == 11 and sum(scores.values()) == 43
assert min(scores.values()) >= 3 and sum(value >= 4 for value in scores.values()) / len(scores) >= 0.8
assert all(scores[name] >= 4 for name in ['Concept', 'Finish', 'Native', 'Copy'])
assert 'Done by the stop rule in critique.md for the supplied Batch42' in critique
print('Final scoped Batch42 gates pass: production41/test43, native providers121, compactR51 14 tests/144 states, secureR52 3/18 plus6 exact native pixels, Release110/59/6 and continuing critic43/55 after368 original opens. No later UI edit. GitHub publication/backup and full Health/Watch/evidence/device/privacy/product gates remain separate.')
