"""Read-only predicates for dedicated synthetic Settings erasure observations."""
import base64
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import time

BASE = Path(__file__).resolve().parent

def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, BASE / filename)
    value = importlib.util.module_from_spec(spec); spec.loader.exec_module(value); return value

h = module('reset_common', 'health-mixed-ineligible-evidence-r1.py')
ns = module('reset_namespace', 'capture-state-namespace-fault-r1.py')
PROTOCOL = 'Lumen-legacy-settings-erasure-verification-v1'
PHASES = [('initial-fixture', 1, 'before-selection'), ('initial-fixture', 2, 'ready'),
          ('initial-fixture', 3, 'owners-closed'), ('initial-fixture', 4, 'erased'),
          ('readonly-clean-relaunch', 1, 'relaunch'), ('readonly-clean-relaunch', 2, 'followup')]
IMAGES = ['before-selection', 'ready-original', 'ready-choices', 'ready-action', 'erase-control',
          'erase-confirmation', 'erased-welcome', 'clean-relaunch', 'bounded-followup']
KEYS = ['lumen.health.meals.v1', 'lumen.health.workouts.v1']


def fixed(expected=None):
    path = h.container('data') / 'Library/Preferences/com.dbakp.lumen.plist'
    values = plistlib.loads(h.read(path)) if path.exists() else {}
    observed = {}
    for key in KEYS:
        value = values.get(key)
        if expected is None:
            assert key not in values, key
            observed[key] = {'present': False}
        else:
            domain = key.split('.')[-2]; wanted = expected['values'][domain]
            assert wanted['key'] == key
            if expected['kind'] == 'data':
                assert type(value) is bytes
                encoded = value; assert value == h.DATA
            else:
                assert expected['kind'] == 'string' and type(value) is str
                encoded = value.encode('utf-16-le')
            assert encoded == base64.b64decode(wanted['payload'], validate=True)
            observed[key] = {'present': True, 'type': wanted['type'], **h.row(encoded)}
    assert not values.get('lumen.health.connected', False)
    return observed


def checkpoint(group, path, started, run_id=None):
    assert path.stat().st_mtime >= started
    value = h.load(path)
    assert value['verificationProtocol'] == PROTOCOL and value['pid'] > 0
    assert value['sequence'] > 0 and value['mode'] in {x[0] for x in PHASES}
    if run_id is not None: assert value['runID'] == run_id
    assert not value['healthConnected'] and not value['healthAuthorized']
    assert set(value['fixed']) == {'meals', 'workouts'}
    if value['mode'] == 'readonly-clean-relaunch':
        args = value['launchArguments']
        assert '-health-legacy-reset-observer' in args
        assert not any(flag in args for flag in ['-resetForUITests', '-health-backup-ui-fixture',
             '-health-legacy-origin-ui', '-health-legacy-reset-ui', '-health-legacy-capture-ui'])
    return value


def journal_reset(before, after):
    assert before['owner'] == after['owner'] and before['version'] == after['version'] == 1
    assert before['lifecycle'] != after['lifecycle']
    old = [x for x in before['events'] if x['action'] == 'delete' and set(x['acknowledged']) != {c['metric'] for c in x['components']}]
    assert len(old) == len(after['events']) == 1
    original, current = old[0], after['events'][0]
    for key in ['id', 'lifecycle', 'domain', 'localID', 'identity', 'requestedAt', 'acknowledged']:
        assert current[key] == original[key], key
    assert current['generation'] != original['generation'] and current['action'] == 'delete'
    assert current['localID'] == 'synthetic-reset-pending-removal'
    assert current['components'] == [{**c, 'value': 0, 'date': -978307200} for c in original['components']]
    assert current.get('issue') in [None, 'unavailable']
    assert not any(x['localID'] == 'synthetic-reset-unstarted-save' for x in after['events'])
    return {'owner': after['owner'], 'lifecycle': after['lifecycle'], 'event': current['id'],
            'generation': current['generation'], 'issue': current.get('issue'), 'pendingDeletionRetained': True,
            'unstartedSaveRemoved': True}


def erased(group, observation, before_journal):
    root = group / 'LumenData'; files = h.snapshot(root)
    assert not (root / '.health-recovery').exists() and not (root / '.health-recovery-history').exists()
    assert not root.with_suffix('.previous').exists()
    for pattern in ['LumenData.restore-*', 'LumenData.retired-*', 'Lumen-reset-fixture-*']:
        assert not list(group.glob(pattern)), pattern
    for row in observation['fixed'].values():
        assert row['persistedPresent'] is False and row['effectivePresent'] is False
    fixed_values = fixed()
    assert observation['onboardingDone'] is False and observation['profileName'] != 'Synthetic backup baseline'
    assert observation['stepGoal'] != 6543 and observation['meals'] == observation['workouts'] == observation['water'] == 0
    for name in ['water.json', 'meals.json', 'workouts.json', 'sleep.json']:
        if name in files: assert json.loads(base64.b64decode(files[name]['base64'])) == []
    profile = json.loads(base64.b64decode(files['profile.json']['base64']))
    assert profile['onboardingDone'] is False and profile['name'] != 'Synthetic backup baseline'
    journal = h.load(root / 'health-write-intent.json')
    return {'files': files, 'metadata': ns.tree(root), 'fixed': fixed_values,
            'journal': journal, 'intent': journal_reset(before_journal, journal),
            'observerIntent': journal_reset(before_journal, observation['journal'])}


def no_owned(selection, pid):
    roots = list(selection['workspaces'])
    assert not h.owned(pid) and all(not os.path.lexists(p) for p in roots)
    result = h.subprocess.run(['lsof', '-nP', '-p', str(pid), '-F', 'n'], capture_output=True, text=True)
    assert result.returncode == 0
    assert all(path not in result.stdout for path in roots)
    return {'rootsAbsent': True, 'roots': roots, 'noOpenPaths': result.stdout, 'hostDeletedWorkspace': False}
