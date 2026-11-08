"""Read-only actual capture evidence/live state verification; no seed/ack/reset."""
import base64
import gzip
import importlib.util
import json
from pathlib import Path
import struct
import sys
import time

base = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('capture_checker_evidence', base / 'capture-state-evidence-r3.py')
e = importlib.util.module_from_spec(spec)
spec.loader.exec_module(e)
h, ns = e.h, e.ns
prefix, output = sys.argv[1:3]
state = h.load(base / (prefix + '-host-audit.json'))
outcome = h.load(base / (prefix + '-outcome.json'))
assert outcome['nativeExit'] == outcome['driverExit'] == 0 and outcome['hostError'] is None
assert not outcome.get('outcomePersistenceErrors') and not outcome.get('finalizationPersistenceErrors')
assert not outcome.get('observationPersistenceError') and not outcome.get('retainerException')
assert not (base / (prefix + '-outcome.json.emergency.json')).exists()
assert state['status'].startswith('PASS strict host')
preflight = h.verify_inputs(state['source'], state['build'])
h.installed(state['build'])
model = e.completed_state(state)
case = state['case']
summary = h.load(base / (prefix + '-summary.json'))
assert summary == outcome['summary'] == outcome['retention']['summary']
assert [summary[key] for key in ['passedTests', 'failedTests', 'skippedTests']] == [1, 0, 0]
assert not outcome['retention']['errors'] and all(row['exitCode'] == 0 for row in outcome['retention']['queries'])
images = h.load(base / (prefix + '-images.json'))
helpers = h.load(base / (prefix + '-readbacks.json'))
assert len(images) == 8 and len(helpers) == 1
ui = 'health-capture-pending-back' if case == 'pending-back' else 'health-capture-failure-retry'
names = []
for row in images + helpers:
    data = h.read(base / row['file'], 4 * 1024 * 1024)
    assert len(data) == row['bytes'] and h.sha(data) == row['sha256'] and row['source'] == state['source']
    assert h.read(row['raw'], 4 * 1024 * 1024) == data
    if row in images:
        assert struct.unpack('>II', data[16:24]) == (1206, 2622)
        name = row['metadata']['suggestedHumanReadableName']
        matches = [phase for phase in e.CASES[case] if ui + '-' + phase + '_' in name]
        assert len(matches) == 1, name
        names.extend(matches)
assert sorted(names) == sorted(e.CASES[case])
helper = h.load(base / helpers[0]['file'])
e.native_helper(helper, case, state['finalCapture']['runID'])
payload_count = 0


def payloads(value):
    global payload_count
    if isinstance(value, dict):
        if isinstance(value.get('base64'), str) and 'bytes' in value and 'sha256' in value:
            data = base64.b64decode(value['base64'], validate=True)
            assert len(data) == value['bytes'] and h.sha(data) == value['sha256']
            payload_count += 1
        for item in value.values():
            payloads(item)
    elif isinstance(value, list):
        for item in value:
            payloads(item)


payloads(state)
group = h.container('group.com.dbakp.lumen')
root = group / 'LumenData'
assert h.snapshot(root) == state['after'] == state['before']
assert ns.tree(root) == state['afterMetadata'] == state['beforeMetadata']
assert h.snapshot(root.with_suffix('.previous')) == state['prior']
assert ns.tree(root.with_suffix('.previous')) == state['priorMetadata']
observed_fixed = {}
e.fixed(state['checkpoint']['legacyOrigins'], observed_fixed)
assert observed_fixed == state['fixed']
assert h.provider() == state['provider']
assert e.capture(group, state['started'], case) == state['finalCapture']
assert h.events(group) == state['finalOriginEvents']
assert not h.owned(state['finalCapture']['pid'])
assert not list(group.glob('LumenData.restore-*')) and not list(group.glob('LumenData.retired-*'))
for name, value in state['messages'].items():
    assert h.load(group / name) == value
for row in state['messageHistory']:
    assert row['afterBoundary'] in [item['phase'] for item in state['boundaries']]
    assert row['value']['runID'] == state['finalCapture']['runID']
if case == 'retry-failure':
    data = gzip.decompress(h.read(base / (prefix + '-fault-journal.jsonl.gz')))
    assert data == h.read(state['faultJournal']['file'])
    assert len(data) == state['faultJournal']['bytes'] and h.sha(data) == state['faultJournal']['sha256']
    journal = [json.loads(line) for line in data.splitlines()]
    assert [row['phase'] for row in journal] == ['prepared', 'rename-intended', 'root-moved',
        'sentinel-create-intended', 'sentinel-created', 'capture-failed', 'sentinel-remove-intended',
        'sentinel-removed', 'restore-rename-intended', 'restored']
    assert journal[5]['originalError'] == state['genuineFailure']
    assert not list(group.glob('LumenData.capture-fault-*'))
    assert h.load(base / (prefix + '-fault-descriptor.json')) == state['faultDescriptor']
result = {'status': 'PASS read-only actual capture-state source/native/live audit', 'source': state['source'],
    'build': state['build'], 'case': case, 'sourceInputs': preflight['inputs'], 'originals': 8,
    'fullNativeHelperBytes': helpers[0]['bytes'], 'embeddedPayloadInstancesDecoded': payload_count,
    'liveCurrentFiles': 10, 'livePriorFiles': 10, 'fixedTypedBoundaries': len(state['boundaries']),
    'model': model, 'checkedAt': time.time(), 'scope': 'Two separately executed declared synthetic capture cases only; no all43/appearance/speech/motion/process-crash/global acceptance.'}
(base / output).write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result), flush=True)
