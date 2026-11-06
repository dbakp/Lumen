"""Independent host readback between and after actual native app processes."""
import argparse
import base64
import copy
import hashlib
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('phase', choices=['prepare', 'resume'])
parser.add_argument('scenario', choices=['before-worker', 'before-receipt', 'undo-before-receipt'])
parser.add_argument('--source', required=True)
parser.add_argument('--build', required=True)
parser.add_argument('--trial', default='r1')
args = parser.parse_args()
base = Path(__file__).resolve().parent
repo = base.parents[2]
device = '922E011C-3895-4DB1-9C9A-1D3A977226CF'
def digest(data):
    return hashlib.sha256(data).hexdigest()
def container(kind):
    return Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', device, 'com.dbakp.lumen', kind]).decode().strip())
def normalize(value):
    value = copy.deepcopy(value)
    for event in value['events']:
        event['acknowledged'].sort()
    return value
source = json.loads((base / args.source).read_text())
for name, facts in source['files'].items():
    assert digest((repo / name).read_bytes()) == facts['sha256'], name
build = json.loads((base / args.build).read_text())
assert build['source'] == args.source
assert digest((container('app') / 'Lumen').read_bytes()) == build['sha256']
group = container('group.com.dbakp.lumen') / 'LumenData'
checkpoint_bytes = (group / 'health-write-restart-checkpoint.json').read_bytes()
checkpoint = json.loads(checkpoint_bytes)
assert checkpoint['scenario'] == args.scenario
assert checkpoint['checks'] and all(row['passed'] for row in checkpoint['checks'])
assert len(checkpoint['journal']['events']) == 3
assert len({event['domain'] for event in checkpoint['journal']['events']}) == 3
expected_values = {'water': 137, 'calories': 213, 'protein': 11, 'carbs': 23, 'fat': 9, 'fiber': 4, 'weight': 76.25}
identities = {}
for event in checkpoint['journal']['events']:
    assert not event['acknowledged']
    assert event['action'] == ('delete' if args.scenario == 'undo-before-receipt' and event['domain'] == 'water' else 'save')
    for component in event['components']:
        assert component['value'] == expected_values[component['metric']]
        identity = f"com.dbakp.lumen.health.v1.{checkpoint['journal']['owner']}.{event['id']}.{component['metric']}"
        identities[component['metric']] = (identity, component)
assert set(identities) == set(expected_values)
def validate_samples(rows, existing):
    assert len(rows) == 7 and {row['metric'] for row in rows} == set(expected_values)
    for row in rows:
        identity, payload = identities[row['metric']]
        count = 1 if row['metric'] in existing else 0
        assert row['syncIdentifier'] == identity and row['count'] == count
        assert len(row['values']) == len(row['dates']) == len(row['sourceBundles']) == len(row['sampleUUIDs']) == count
        if count:
            assert abs(row['values'][0] - payload['value']) <= 1e-7
            assert abs(row['dates'][0] - payload['date']) <= 0.001
            assert row['sourceBundles'] == ['com.dbakp.lumen']
old_existing = set() if args.scenario == 'before-worker' else {'water', 'calories', 'weight'}
validate_samples(checkpoint['samples'], old_existing)
assert len(checkpoint['verifiedOperations']) == (0 if args.scenario == 'before-worker' else 3)
if args.phase == 'prepare':
    data = checkpoint
    report_bytes = checkpoint_bytes
    assert all(not event['acknowledged'] for event in data['journal']['events'])
else:
    report_bytes = (container('data') / 'tmp/Lumen-health-restart-report.json').read_bytes()
    data = json.loads(report_bytes)
    assert data['status'] == 'Health restart checks passed'
    assert data['prepared'] == checkpoint and data['pid'] != checkpoint['pid']
    assert all(row['passed'] for row in data['checks']) and data['exactFixtureCleanupVerified']
    validate_samples(data['samplesBeforeRecovery'], old_existing)
    new_existing = set(expected_values) - ({'water'} if args.scenario == 'undo-before-receipt' else set())
    validate_samples(data['samplesAfterRecovery'], new_existing)
    assert len(data['verifiedOperations']) == 7
    for event in data['journal']['events']:
        assert set(event['acknowledged']) == {row['metric'] for row in event['components']}
    before_events = {event['id']: event for event in checkpoint['journal']['events']}
    for event in data['journal']['events']:
        old = before_events[event['id']]
        for key in ['id', 'domain', 'localID', 'identity', 'lifecycle', 'generation', 'action', 'components']:
            assert event[key] == old[key], key
assert data['files'].keys() == {'water.json', 'meals.json', 'goals.json', 'today.json', 'health-write-intent.json'}
raw = {}
for name, encoded in data['files'].items():
    actual = (group / name).read_bytes()
    assert actual == base64.b64decode(encoded), name
    raw[name] = actual
assert normalize(json.loads(raw['health-write-intent.json'])) == normalize(data['journal'])
assert data['waterIDs'] == [row['id'] for row in json.loads(raw['water.json'])]
assert len(data['waterIDs']) == (0 if args.scenario == 'undo-before-receipt' else 1)
assert data['mealIDs'] == [row['id'] for row in json.loads(raw['meals.json'])]
assert data['mealIDs'] == ['synthetic-restart-43-' + checkpoint['nonce']]
assert data['weight'] == json.loads(raw['goals.json'])['weightKg'] == 76.25
if args.phase == 'resume':
    for name in ['water.json', 'meals.json', 'goals.json', 'today.json']:
        assert data['files'][name] == checkpoint['files'][name], name
prefix = f"native-health-restart-{args.scenario}-{args.phase}-{args.trial}"
(base / (prefix + '-report.json')).write_bytes(report_bytes)
audit = {'status': 'passed', 'phase': args.phase, 'scenario': args.scenario,
         'source': args.source, 'sourceInputs': len(source['files']), 'nativeBuild': args.build,
         'nativeChecks': len(data['checks']), 'pid': data['pid'], 'preparedPID': checkpoint['pid'],
         'nonce': checkpoint['nonce'], 'hostMatchedFiles': len(raw),
         'sourceOwnedComponentIdentities': 7, 'installedBinarySHA256': build['sha256'],
         'reportSHA256': digest(report_bytes),
         'files': {name: {'bytes': len(value), 'sha256': digest(value)} for name, value in raw.items()},
         'scope': 'Actual source/binary plus host reads of all five native files between or after app processes; native real-HealthKit observations and checked receipts. No direct host Health database query, OS power loss, in-flight daemon completion, physical-device or background/locked proof.'}
(base / (prefix + '-host-audit.json')).write_text(json.dumps(audit, indent=2) + '\n')
print('PASS:', args.scenario, args.phase, len(data['checks']), 'native checks; five exact host files, seven original identities and current binary/source match.')
