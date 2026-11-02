"""Audit preserved intermediate evidence; deliberately not final batch acceptance."""
from pathlib import Path
import gzip
import hashlib
import json
import re
import subprocess

base = Path(__file__).resolve().parent
repo = base.parents[2]

def read(name):
    return json.loads((base / name).read_text())

def stream(name):
    return gzip.open(base / name, 'rt').read()

def summary(name, failed=0):
    value = read(name)
    assert value['totalTestCount'] == 1 and value['failedTests'] == failed
    assert value['passedTests'] == 1 - failed and value['skippedTests'] == 0

summary('baseline-r1-summary.json')
summary('native-r2-failed-summary.json', failed=1)
summary('native-r4-summary.json')
summary('native-r5-summary.json')
summary('personal-regression-r4-summary.json')
summary('submission-baseline-r6-summary.json')
summary('native-r7-summary.json')
summary('ui-r1-summary.json')
summary('ui-r2-failed-summary.json', failed=1)
baseline = read('baseline-native-report.json')
assert baseline['packets'] == read('baseline-host-readback.json')
assert len(baseline['observations']) == 2
withdrawn = baseline['observations'][1]
assert withdrawn['mode'] == 'withdraw' and withdrawn['requestCount'] == 1
assert withdrawn['systemCanaryCount'] > 0 and withdrawn['eligible']
assert withdrawn['savedConversation'] and withdrawn['automaticPlanCount'] == 1 and withdrawn['automaticStepCount'] == 2
for revision, count, packets in [('r4', 14, 6), ('r5', 16, 8), ('r7', 19, 9)]:
    native = read(f'native-{revision}-report.json')
    assert native['status'] == 'Request authorization checks passed'
    assert native['packets'] == read(f'native-{revision}-host-readback.json')
    assert len(native['observations']) == count and len(native['packets']) == packets
    assert sum(v['requestCount'] for v in native['observations']) == packets
    for observation in native['observations']:
        assert observation['savedConversation']
        expected_plan = observation['mode'] in {'plan', 'local', 'overlap-plan'}
        assert observation['eligible'] == expected_plan
        assert observation['automaticPlanCount'] == int(expected_plan)
        assert observation['automaticStepCount'] == (3 if expected_plan else 0)
        if observation['mode'] in {'withdraw', 'edit', 'remove', 'revert', 'history', 'lease', 'urgent', 'search-error', 'submission-withdraw', 'submission-personal'}:
            assert observation['requestCount'] == 0
submission = read('submission-baseline-r6-report.json')
assert submission['status'] == 'Submission baseline reproduced' and len(submission['observations']) == 2
assert submission['packets'] == read('submission-baseline-r6-host-readback.json')
assert all(v['packetCount'] == 1 and v['libraryCount'] > 0 for v in submission['observations'])
transport = read('transport-r7-report.json')
assert transport['status'] == 'passed' and len(transport['cases']) == 15 and all(v['status'] == 'passed' for v in transport['cases'])
assert sum(v.get('requests', 0) for v in read('transport-r7-host-readback.json').values()) == 14
assert len(read('ui-r1-host-readback.json')) == 2 and read('ui-r1-file-readback.json')['noticeSavedAsNoteOnly']
assert read('ui-r2-host-readback.json')['personalAudit'] == []
regression = read('personal-regression-r4-report.json')
assert regression['status'] == 'Personal context checks passed'
assert len(regression['checks']) == 43 and all(v['passed'] for v in regression['checks'])
assert len(regression['requests']) == 8 and regression['requests'] == read('personal-regression-r4-host-readback.json')
logic = stream('LogicR1.log.gz').splitlines()
assert sum(v.startswith('PASS:') for v in logic) == 1614 and not any(v.startswith('FAIL:') for v in logic)
assert 'TEST EXECUTE FAILED' in stream('NativeR2.log.gz')
assert 'search-error outgoing count' in stream('NativeR2.log.gz')
for name in ['BaselineR1.log.gz', 'NativeR4.log.gz', 'NativeR5.log.gz', 'RegressionR4.log.gz']:
    assert 'TEST EXECUTE SUCCEEDED' in stream(name)
# Reconstruct exact historical source identities from the immutable starting
# commit plus each saved instrumentation/change snapshot, not today's checkout.
source = read('baseline-source.json')
commit = source['baseCommit']
base_bytes = {}
for revision, manifest, archive in [
    ('baseline', 'baseline-source.json', 'baseline-instrumentation.json.gz'),
    ('r2', 'source-r2.json', 'source-r2-changes.json.gz'),
    ('r4', 'source-r4.json', 'source-r4-changes.json.gz'),
    ('r5', 'source-r5.json', 'source-r5-changes.json.gz'),
    ('r6', 'source-r6.json', 'source-r6-changes.json.gz'),
    ('r7', 'source-r7.json', 'source-r7-changes.json.gz'),
    ('r8', 'source-r8.json', 'source-r8-changes.json.gz'),
    ('r9', 'source-r9.json', 'source-r9-changes.json.gz'),
    ('r10', 'source-r10.json', 'source-r10-changes.json.gz'),
    ('r11', 'source-r11.json', 'source-r11-changes.json.gz')]:
    changes = json.loads(stream(archive))
    for path, expected in read(manifest)['files'].items():
        if path in changes:
            data = changes[path].encode()
        else:
            if path not in base_bytes:
                base_bytes[path] = subprocess.check_output(['git', 'show', f'{commit}:{path}'], cwd=repo)
            data = base_bytes[path]
        assert len(data) == expected['bytes'] and hashlib.sha256(data).hexdigest() == expected['sha256'], (revision, path)
print('Intermediate evidence verified: baseline defects, retained failed trial, native14/16/19, regression43, transport15, logic1614, scoped main UI and retained compact failure and exact historical sources. Final acceptance is checked separately.')
