"""Read-only bounded capture-state evidence helpers; no producer on import."""
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import re
import stat
import subprocess
import time

BASE = Path(__file__).resolve().parent


def module(name, file):
    spec = importlib.util.spec_from_file_location(name, BASE / file)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


h = module('capture_common', 'health-mixed-ineligible-evidence-r1.py')
ns = module('capture_namespace', 'capture-state-namespace-fault-r1.py')
CASES = {
    'pending-back': ['pending-progress', 'pending-choices', 'parent-old-worker-held',
                     'parent-old-worker-terminal', 'fresh-review', 'fresh-parent'],
    'retry-failure': ['before-read-progress', 'genuine-failure', 'failure-disabled-choices',
                     'retry-ready', 'retry-off-choices', 'retry-parent'],
}


def fixed(expected, sink):
    assert expected['bundle'] == 'com.dbakp.lumen' and expected['kind'] == 'data'
    assert set(expected['values']) == {'meals', 'workouts'}
    values = plistlib.loads(h.read(h.container('data') / 'Library/Preferences/com.dbakp.lumen.plist'))
    for domain in ['meals', 'workouts']:
        key = 'lumen.health.' + domain + '.v1'
        value = values.get(key)
        row = {'key': key, 'actualType': type(value).__name__}
        sink[domain] = row
        if isinstance(value, bytes):
            row.update({'type': 'data', **h.row(value)})
        assert type(value) is bytes and value == h.DATA
        assert expected['values'][domain] == {'key': key, 'type': 'data', 'payload': row['base64']}
    return sink


def capture(group, started, case):
    path = group / 'Lumen-legacy-capture-checkpoint.json'
    assert path.stat().st_mtime >= started
    value = h.load(path)
    assert value['version'] == 1 and value['pid'] > 0
    assert value['mode'] == case
    assert re.fullmatch(r'[A-Fa-f0-9-]{36}', value['runID'])
    rows = value['events']
    assert isinstance(rows, list) and len(rows) <= 64
    for row in rows:
        assert row['pid'] == value['pid'] and row['runID'] == value['runID']
        assert row['ordinal'] in [1, 2]
        for key in ['sessionID', 'controlID', 'nonce']:
            assert re.fullmatch(r'[A-Fa-f0-9-]{36}', row[key])
        assert row['leaseState'] in ['initial', 'capturing', 'ready', 'closed']
        assert type(row['metadataAvailable']) is type(row['taskCancelled']) is type(row['controlAlive']) is bool
        if row['controlAlive']:
            assert type(row['controlCancelled']) is bool
        assert not row['event'].startswith('barrier-timeout'), row
    return value


def selected(started):
    value = h.selected(started)
    value['workspaceMetadata'] = {path: h.metadata(Path(path)) for path in value['workspaces']}
    return value


def source_exact(value):
    h.source_exact(value)
    assert {path: h.metadata(Path(path)) for path in value['workspaces']} == value['workspaceMetadata']


def same_protocol(value, original):
    for key in ['runID', 'pid']:
        assert value[key] == original[key]
    assert value['events'][:len(original['events'])] == original['events']


def records(value, ordinal, event=None):
    return [row for row in value['events'] if row['ordinal'] == ordinal and
            (event is None or row['event'] == event)]


def unique(value, ordinal, event):
    result = records(value, ordinal, event)
    assert len(result) == 1, (ordinal, event, result)
    return result[0]


def clean_no_open(selection, *, guard=3):
    until = time.monotonic() + guard
    while any(os.path.lexists(path) for path in selection['workspaces']) and time.monotonic() < until:
        time.sleep(0.1)
    assert not any(os.path.lexists(path) for path in selection['workspaces'])
    pid = selection['source']['owner']['pid']
    assert not h.owned(pid)
    scan = subprocess.run(['lsof', '-nP', '-a', '-p', str(pid), '-Fn'], capture_output=True, text=True)
    assert scan.returncode == 0
    for line in scan.stdout.splitlines():
        if line.startswith('n'):
            assert not any(line[1:] == path or line[1:].startswith(path + '/') for path in selection['workspaces'])
    return {'rootsAbsent': True, 'noOpenPaths': scan.stdout, 'hostDeletedWorkspace': False,
            'guardSeconds': guard, 'scope': 'Bounded observation after native attachment, not tap-to-delete latency'}


def native_helper(value, case, run_id):
    assert value['scope'] == 'real-legacy-capture-state' and value['case'] == case and value['phase'] == 'completed'
    args = value['launchArguments']
    assert args[args.index('-health-legacy-capture-run') + 1] == run_id
    assert args[args.index('-health-legacy-capture-ui') + 1] == case
    rows = value['observations']
    phases = {row['phase']: row for row in rows}
    assert len(phases) == len(rows)
    for phase in CASES[case]:
        # Parent originals are separately named screenshots, without fabricated AX rows.
        if phase in ['parent-old-worker-held', 'parent-old-worker-terminal', 'fresh-parent', 'retry-parent']:
            continue
        assert phase in phases
        row = phases[phase]
        assert row['elements']
        for element in row['elements']:
            box = element['frame']
            assert box['width'] > 0 and box['height'] > 0
            assert box['x'] >= row['usableLeft'] and box['x'] + box['width'] <= row['usableRight']
            assert box['y'] >= row['usableTop'] and box['y'] + box['height'] <= row['usableBottom']
    for phase, enabled in ([('pending-choices', False), ('fresh-review', True)] if case == 'pending-back'
                           else [('failure-disabled-choices', False), ('retry-off-choices', True)]):
        controls = phases[phase]['elements']
        assert len(controls) == 3
        assert [row['identifier'] for row in [controls[0], controls[2]]] == ['recoverFile-meals', 'recoverFile-workouts']
        assert controls[1]['label'] == 'Recover without meal photos'
        assert all(row['value'] == '0' and row['enabled'] is enabled for row in controls)
        assert phases[phase + '-action']['recoverDisabled'] is True
    if case == 'retry-failure':
        assert phases['genuine-failure']['elements'][0]['label'] == "Saved data couldn't be checked. Check again to retry."
        assert phases['genuine-failure']['elements'][1]['identifier'] == 'retryFileRecoveryCapture'
    return value


def completed_state(state):
    case, value = state['case'], state['finalCapture']
    assert case in CASES and state['nativeExit'] == 0
    assert state['after'] == state['before'] and state['afterMetadata'] == state['beforeMetadata']
    assert len(state['before']) == len(state['prior']) == 10
    assert len(state['boundaries']) == 7 and all(row['status'] == 'PASS' for row in state['boundaries'])
    expected = (['initial-before-selection', 'held-before-action', 'pending-choices-before-back',
        'back-old-worker-still-held', 'oldWorkerTerminalCleanup', 'fresh-ready', 'finalCleanup'] if case == 'pending-back'
        else ['initial-before-selection', 'held-before-action', 'sentinel-before-real-read-release',
        'real-operational-failure-before-restore', 'root-restored-before-retry', 'actual-check-again-ready', 'finalCleanup'])
    assert [row['phase'] for row in state['boundaries']] == expected
    for row in state['boundaries']:
        assert row['current'] == state['before'] and row['currentMetadata'] == state['beforeMetadata']
        assert row['prior'] == state['prior'] and row['priorMetadata'] == state['priorMetadata']
        assert row['fixed'] == state['fixed'] and row['provider'] == state['provider']
    first, second = unique(value, 1, 'registered'), unique(value, 2, 'registered')
    assert first['controlID'] != second['controlID'] and first['nonce'] != second['nonce']
    assert first['sessionID'] != second['sessionID'] if case == 'pending-back' else first['sessionID'] == second['sessionID']
    for ordinal, registered in [(1, first), (2, second)]:
        for row in records(value, ordinal):
            assert all(row[key] == registered[key] for key in ['runID', 'pid', 'sessionID', 'controlID', 'nonce'])
        assert registered['leaseState'] == 'capturing' and not registered['metadataAvailable']
        assert not registered['controlCancelled'] and not registered['taskCancelled']
    ready = unique(value, 2, 'finish-accepted')
    assert ready['leaseState'] == 'ready' and ready['metadataAvailable'] and not ready['controlCancelled']
    assert unique(value, 2, 'capture-returned')['leaseState'] == 'ready'
    assert unique(value, 2, 'ui-wrapper-cleanup')['metadataAvailable']
    assert not records(value, 1, 'finish-accepted')
    error = unique(value, 1, 'capture-threw-finish' if case == 'pending-back' else 'capture-threw-capture')
    returned = unique(value, 1, 'capture-returned-error')
    assert not error['metadataAvailable'] and error['errorType'] == returned['errorType']
    assert error['errorDomain'] == returned['errorDomain'] and error['errorCode'] == returned['errorCode']
    assert records(value, 1, 'ui-wrapper-cleanup')
    if case == 'pending-back':
        assert error['controlCancelled'] and error['leaseState'] == 'closed'
        assert state['oldWorkerTerminalCleanup']['rootsAbsent'] and state['oldTerminal']
        assert set(state['freshSelection']['workspaces']).isdisjoint(state['selection']['workspaces'])
    else:
        assert not error['controlCancelled'] and not error['taskCancelled'] and error['leaseState'] == 'capturing'
        assert 'HealthLocalFiles.Failure' in error['errorType'] and state['faultRestored'] is True
        assert state['retryReady']['sessionID'] == first['sessionID']
    trace = state['finalOriginEvents']
    owners = {first['sessionID'], second['sessionID']}
    assert {row['sessionID'] for row in trace} == owners
    assert not any(row['event'] == 'acquire' for row in trace)
    assert len([row for row in trace if row['event'] == 'ready']) == 1
    for owner in owners:
        events = [row for row in trace if row['sessionID'] == owner]
        assert events[0]['event'] == 'open' and events[-1]['event'] == 'closed'
        assert sum(row['event'] == 'open' for row in events) == 1
        for row in events:
            assert row['event'] in ['open', 'ready', 'closed']
            assert row['domains'] == (['meals', 'workouts'] if row['event'] == 'ready' else [])
        assert any(row['event'] == 'ready' for row in events) is (owner == second['sessionID'])
    assert state['finalCleanup']['rootsAbsent'] and state['finalCleanup']['hostDeletedWorkspace'] is False
    return {'status': 'PASS retained actual capture-state model', 'case': case,
            'boundaries': 7, 'currentFiles': 10, 'priorFiles': 10, 'controls': 2,
            'scope': 'Declared bounded cases only; no universal timing, process-crash or global acceptance'}
