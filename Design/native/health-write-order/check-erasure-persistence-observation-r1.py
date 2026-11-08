"""Exercise the actual read-only helper with isolated plist files/fake time."""
import base64
import copy
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import time

BASE = Path(__file__).resolve().parent


def module(name, file):
    spec = importlib.util.spec_from_file_location(name, BASE / file)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


p = module('actual_persistence_observer', 'legacy-erasure-persistence-observation-r1.py')
h = module('isolated_file_utilities', 'health-mixed-ineligible-evidence-r1.py')
root = Path(tempfile.mkdtemp(prefix='LumenErasurePersistenceR1-'))
rows = []
for case in ['data-converges', 'string-converges', 'never-clears', 'changed-value',
             'unsupported-type', 'health-connected', 'native-present', 'persistence-error',
             'fleeting-absence', 'malformed-plist']:
    folder = root / case
    folder.mkdir()
    path = folder / 'preferences.plist'
    is_string = case == 'string-converges'
    value = 'synthetic invalid legacy å🙂' if is_string else b'{synthetic invalid legacy'
    raw_value = value.encode('utf-16-le') if is_string else value
    original = {'kind': 'string' if is_string else 'data', 'values': {
        domain: {'key': key, 'payload': base64.b64encode(raw_value).decode()} for domain, key in p.KEYS.items()}}
    native = {'healthConnected': False, 'healthAuthorized': False, 'fixed': {
        domain: {'key': key, 'persistedPresent': False, 'effectivePresent': False} for domain, key in p.KEYS.items()}}
    initial = {key: value for key in p.KEYS.values()}
    initial['lumen.health.connected'] = False
    if case == 'changed-value':
        initial[p.KEYS['meals']] = b'changed'
    elif case == 'unsupported-type':
        initial[p.KEYS['meals']] = {'unexpected': 1}
    elif case == 'health-connected':
        initial['lumen.health.connected'] = True
    elif case == 'native-present':
        native['fixed']['meals']['persistedPresent'] = True
    elif case == 'fleeting-absence':
        initial = {'lumen.health.connected': False}
    path.write_bytes(b'synthetic invalid plist' if case == 'malformed-plist' else plistlib.dumps(initial))
    (folder / 'initial.plist').write_bytes(path.read_bytes())
    state = {'clock': 0.0, 'persistCalls': 0, 'transition': None}
    sink = {}

    def persist():
        state['persistCalls'] += 1
        if case == 'persistence-error' and state['persistCalls'] == 2:
            raise OSError('isolated intentional evidence persistence failure')
        (folder / 'actual-helper-state.json').write_text(json.dumps(sink, indent=2) + '\n')

    def sleep(seconds):
        state['clock'] += seconds
        stage = None
        if case in ['data-converges', 'string-converges'] and state['clock'] >= 0.3:
            stage = 'absent'
        if case == 'fleeting-absence':
            stage = 'old' if state['clock'] < 0.3 else 'absent'
        if stage != state['transition'] and stage is not None:
            state['transition'] = stage
            values = {'lumen.health.connected': False}
            if stage == 'old':
                values.update({key: value for key in p.KEYS.values()})
            path.write_bytes(plistlib.dumps(values))

    error = None
    try:
        p.wait(path, original, native, sink, persist, h, clock=lambda: state['clock'],
               wall=lambda: 1794130000 + state['clock'], sleep=sleep)
    except BaseException as failure:
        error = type(failure).__name__ + ': ' + str(failure)
    should_pass = case in ['data-converges', 'string-converges', 'fleeting-absence']
    assert (error is None) is should_pass, (case, error)
    if should_pass:
        p.validate_retained(sink, original, native)
        assert sink['elapsedSeconds'] >= 0.5
    else:
        assert sink['status'].startswith('FAILED') and sink.get('error')
        if case == 'never-clears':
            assert state['clock'] == 10.0 and len(sink['samples']) > 90
        if case in ['changed-value', 'unsupported-type', 'health-connected']:
            assert set(sink['samples'][0]['fixed']) == set(p.KEYS)
    record = {'case': case, 'expectedAccepted': should_pass, 'actualAccepted': error is None,
              'error': error, 'samples': len(sink['samples']), 'fakeElapsedSeconds': state['clock'],
              'persistCalls': state['persistCalls'], 'actualHelperState': sink, 'scope': 'isolated plist/fake clock, no app/native erasure'}
    (folder / 'control-outcome.json').write_text(json.dumps(record, indent=2) + '\n')
    rows.append({key: record[key] for key in ['case', 'expectedAccepted', 'actualAccepted', 'error', 'samples', 'fakeElapsedSeconds']})
payloads = {}
for path in sorted(root.rglob('*')):
    if path.is_file():
        assert not path.is_symlink()
        data = path.read_bytes()
        payloads[str(path.relative_to(root))] = {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(),
                                               'base64': base64.b64encode(data).decode()}
archive = 'erasure-persistence-observation-r1-fixtures.json.gz'
(BASE / archive).write_bytes(gzip.compress(json.dumps(payloads, sort_keys=True).encode(), mtime=0))
outcome = {'status': 'PASS ten actual helper controls with isolated plist files and fake time',
           'cases': rows, 'payloads': len(payloads), 'archive': archive, 'rawRoot': str(root),
           'helperSHA256': hashlib.sha256((BASE / 'legacy-erasure-persistence-observation-r1.py').read_bytes()).hexdigest(),
           'runnerSHA256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
           'scope': 'Actual helper control branches only; no native Settings erase, real latency, preferences synchronization, app compilation or full logic-suite credit.',
           'checkedAt': time.time()}
(BASE / 'erasure-persistence-observation-r1-outcome.json').write_text(json.dumps(outcome, indent=2) + '\n')
print(outcome['status'], ';', len(payloads), 'retained payloads', flush=True)
