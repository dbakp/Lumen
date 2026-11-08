"""Read-only predicates for dedicated synthetic Settings erasure observations."""
import base64
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import stat
import traceback
import datetime
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


def fixed(expected=None, sink=None):
    observed = sink if sink is not None else {}
    path = h.container('data') / 'Library/Preferences/com.dbakp.lumen.plist'
    values = plistlib.loads(h.read(path)) if path.exists() else {}
    for key in KEYS:
        value = values.get(key)
        actual = {'key': key, 'present': key in values, 'actualType': type(value).__name__}
        observed[key] = actual
        # Retain supported bounded actual values BEFORE deciding equality.
        if type(value) is bytes:
            actual['type'] = 'data'; actual['actualBytes'] = len(value)
            assert len(value) <= 4096
            actual.update(h.row(value))
        elif type(value) is str:
            actual['type'] = 'stringUTF16LE'; actual['utf16Length'] = len(value.encode('utf-16-le', errors='surrogatepass')) // 2
            encoded = value.encode('utf-16-le', errors='surrogatepass')
            assert len(encoded) <= 4096
            actual.update(h.row(encoded))
        elif value is not None:
            actual['classification'] = 'unsupported fixed-key type; no unrelated payload retained'
        if expected is None:
            assert key not in values, key
        else:
            domain = key.split('.')[-2]; wanted = expected['values'][domain]
            assert wanted['key'] == key
            assert actual.get('type') == ('data' if expected['kind'] == 'data' else 'stringUTF16LE')
            encoded = base64.b64decode(actual['base64'], validate=True)
            assert encoded == base64.b64decode(wanted['payload'], validate=True)
            if expected['kind'] == 'data': assert encoded == h.DATA
            else: assert expected['kind'] == 'string'
    observed['_healthConnected'] = {'actual': values.get('lumen.health.connected'), 'effectiveBool': bool(values.get('lumen.health.connected', False))}
    assert not observed['_healthConnected']['effectiveBool']
    return observed


def observe_tree(path, sink):
    """Incrementally retain actual bounded entries, including a failing type/path."""
    path = Path(path); sink.update(exists=os.path.lexists(path), files={}, metadata={'files': {}, 'directories': []}, entries=[])
    try:
        facts = path.lstat(); sink['rootIdentity'] = {key: getattr(facts, key) for key in h.FIELDS}
        assert stat.S_ISDIR(facts.st_mode) and not path.is_symlink()
        total = 0
        for parent, dirs, names in os.walk(path, followlinks=False):
            for name in sorted(dirs + names):
                child = Path(parent) / name; facts = child.lstat(); relative = str(child.relative_to(path))
                identity = {key: getattr(facts, key) for key in h.FIELDS}
                entry = {'path': relative, 'identity': identity}; sink['entries'].append(entry)
                assert not stat.S_ISLNK(facts.st_mode), relative
                if name in dirs:
                    entry['kind'] = 'directory'; assert stat.S_ISDIR(facts.st_mode)
                    sink['metadata']['directories'].append(relative)
                else:
                    entry['kind'] = 'regular' if stat.S_ISREG(facts.st_mode) else 'unsupported'
                    assert stat.S_ISREG(facts.st_mode) and facts.st_size <= 256 * 1024, relative
                    data = h.read(child); total += len(data); assert total <= 2 * 1024 * 1024
                    sink['files'][relative] = h.row(data)
                    sink['metadata']['files'][relative] = {'identity': identity, 'bytes': len(data), 'sha256': h.sha(data)}
        sink['metadata']['directories'].sort(); sink['status'] = 'observed'
    except BaseException:
        sink['status'] = 'FAILED observation'; sink['error'] = traceback.format_exc(); raise
    return sink


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
    assert current['localID'] == 'synthetic-reset-pending-removal' and original['identity'] == 'sync'
    assert any(c['value'] > 0 and c['date'] != -978307200 for c in original['components'])
    assert current['components'] == [{**c, 'value': 0, 'date': -978307200} for c in original['components']]
    assert current.get('issue') in [None, 'unavailable']
    assert not any(x['localID'] == 'synthetic-reset-unstarted-save' for x in after['events'])
    return {'owner': after['owner'], 'lifecycle': after['lifecycle'], 'event': current['id'],
            'generation': current['generation'], 'issue': current.get('issue'), 'pendingDeletionRetained': True,
            'unstartedSaveRemoved': True}


FRESH_GOALS = {'stepGoal': 10000, 'activeCalGoal': 600, 'exerciseGoalMin': 30, 'standGoal': 12,
               'weightKg': 75, 'heightCm': 178, 'age': 30, 'sex': 'unspecified', 'activityLevel': 'moderate', 'goal': 'maintain'}
FRESH_ARRAYS = {'sleep.json', 'water.json', 'meals.json', 'workouts.json', 'chat.json', 'conversations.json',
                'symptoms.json', 'check-ins.json', 'documents.json', 'imported-days.json', 'import-receipts.json'}
FRESH_ALLOWED = FRESH_ARRAYS | {'profile.json', 'habits.json', 'personal-context.json', 'reminder-preferences.json',
                              'goals.json', 'today.json', 'conversation-selection.json', 'health-write-intent.json', '.completed-local-erasure'}
FRESH_REQUIRED = {'profile.json', 'sleep.json', 'habits.json', 'personal-context.json', 'reminder-preferences.json',
                  'symptoms.json', 'check-ins.json', 'documents.json', 'imported-days.json', 'import-receipts.json', 'health-write-intent.json'}


def erased(group, observation, before_journal, initial_files, sink=None):
    actual = sink if sink is not None else {}
    root = group / 'LumenData'
    actual['tree'] = {}; observe_tree(root, actual['tree'])
    files = actual['tree']['files']; actual['files'] = files; actual['metadata'] = actual['tree']['metadata']
    actual['priorExists'] = os.path.lexists(root.with_suffix('.previous'))
    actual['ownedResiduals'] = {pattern: [str(p) for p in group.glob(pattern)] for pattern in
                              ['LumenData.restore-*', 'LumenData.retired-*', 'Lumen-reset-fixture-*']}
    actual['fixed'] = {}; fixed(None, actual['fixed'])
    actual['journal'] = h.load(root / 'health-write-intent.json')
    # Everything acquired above remains in the caller's boundary even on failure.
    assert FRESH_REQUIRED <= set(files) <= FRESH_ALLOWED, sorted(set(files) - FRESH_ALLOWED)
    assert not actual['metadata']['directories'], 'No fresh data subdirectories expected in this declared case'
    assert not actual['priorExists'] and not any(actual['ownedResiduals'].values())
    for row in observation['fixed'].values():
        assert row['persistedPresent'] is False and row['effectivePresent'] is False
    assert observation['onboardingDone'] is False and observation['profileName'] == ''
    assert observation['goals'] == FRESH_GOALS and observation['stepGoal'] == 10000
    assert observation['meals'] == observation['workouts'] == observation['water'] == 0
    def decoded(name): return json.loads(base64.b64decode(files[name]['base64'], validate=True))
    for name in FRESH_ARRAYS & set(files): assert decoded(name) == [], name
    if 'goals.json' in files: assert decoded('goals.json') == FRESH_GOALS
    # Initial synthetic profile/habits were production defaults except these two
    # declared profile fields. No arbitrary user profile is a defaults authority.
    profile = json.loads(base64.b64decode(initial_files['profile.json']['base64'], validate=True))
    assert profile['name'] == 'Synthetic backup baseline' and profile['onboardingDone'] is True
    profile.update(name='', onboardingDone=False)
    assert decoded('profile.json') == profile
    habits = decoded('habits.json')
    assert habits == json.loads(base64.b64decode(initial_files['habits.json']['base64'], validate=True))
    assert len(habits) == 16 and all(x['doneToday'] is False for x in habits)
    assert decoded('personal-context.json') == {**dict.fromkeys(['focus', 'foodPreferences', 'allergies', 'limitations', 'schedule', 'notes'], ''), 'includeInAssistant': False}
    assert decoded('reminder-preferences.json') == {'enabled': False, 'quietStart': 21, 'quietEnd': 8, 'showDetails': False}
    if 'conversation-selection.json' in files: assert decoded('conversation-selection.json') == {}
    if '.completed-local-erasure' in files:
        assert base64.b64decode(files['.completed-local-erasure']['base64'], validate=True) == b'Lumen completed local erasure v1'
    if 'today.json' in files:
        today = decoded('today.json'); date = today.pop('date')
        assert today == {'steps': 0, 'activeCalories': 0, 'restingCalories': 0, 'exerciseMin': 0, 'standHours': 0, 'waterML': 0}
        stamp = datetime.datetime.fromisoformat(date.replace('Z', '+00:00')).timestamp()
        assert -3600 <= observation['at'] - stamp <= 36 * 3600
    for name, row in files.items():
        data = base64.b64decode(row['base64'], validate=True)
        assert not any(marker in data for marker in [b'synthetic-review-water', b'synthetic-current-meal', b'synthetic-multi-zero', b'Synthetic backup baseline', b'synthetic-reset-unstarted-save']), name
    actual['intent'] = journal_reset(before_journal, actual['journal'])
    actual['observerIntent'] = journal_reset(before_journal, observation['journal'])
    return actual


def no_owned(selection, pid):
    roots = list(selection['workspaces'])
    assert not h.owned(pid) and all(not os.path.lexists(p) for p in roots)
    result = h.subprocess.run(['lsof', '-nP', '-p', str(pid), '-F', 'n'], capture_output=True, text=True)
    assert result.returncode == 0
    assert all(path not in result.stdout for path in roots)
    return {'rootsAbsent': True, 'roots': roots, 'noOpenPaths': result.stdout, 'hostDeletedWorkspace': False}
