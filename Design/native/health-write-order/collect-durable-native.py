"""Read back the simulator's actual data and compare every reported byte."""
import base64
import hashlib
import json
from pathlib import Path
import subprocess
import argparse

parser = argparse.ArgumentParser()
parser.add_argument('device'); parser.add_argument('label')
parser.add_argument('--source', default='durable-source-r2.json')
parser.add_argument('--build', default='durable-native-build-r2.json')
args = parser.parse_args()
device, label = args.device, args.label
base = Path(__file__).resolve().parent
repo = base.parents[2]
def run(*args):
    return subprocess.check_output(args).decode().strip()
def digest(data):
    return hashlib.sha256(data).hexdigest()
app_data = Path(run('xcrun', 'simctl', 'get_app_container', device, 'com.dbakp.lumen', 'data'))
group = Path(run('xcrun', 'simctl', 'get_app_container', device, 'com.dbakp.lumen', 'group.com.dbakp.lumen'))
report = json.loads((app_data / 'tmp/Lumen-durable-health-report.json').read_bytes())
assert report['status'] == 'Health recovery checks passed'
assert report['checks'] and all(row['passed'] for row in report['checks'])
assert report['persistedFiles'].keys() == {'water.json', 'meals.json', 'goals.json', 'today.json', 'health-write-intent.json'}
raw = {}
for name, data in report['persistedFiles'].items():
    actual = (group / 'LumenData' / name).read_bytes()
    assert actual == base64.b64decode(data), name
    raw[name] = actual
journal = json.loads(raw['health-write-intent.json'])
assert len(journal['events']) == 4
external = {}
for event in journal['events']:
    assert set(event['acknowledged']) == {c['metric'] for c in event['components']}
    assert event.get('issue') is None
    if event['action'] == 'save':
        for component in event['components']:
            key = f"com.dbakp.lumen.health.v1.{journal['owner']}.{event['id']}.{component['metric']}"
            external[key] = component['value']
assert external == report['external'] and len(external) == report['externalComponents'] == 7
assert report['pendingCount'] == 0 and report.get('writeStatus') is None
assert report['liveWaterIDs'] == [row['id'] for row in json.loads(raw['water.json'])]
assert report['liveMealIDs'] == [row['id'] for row in json.loads(raw['meals.json'])]
assert json.loads(raw['goals.json'])['weightKg'] == report['liveWeight'] == 75
assert report['trace'] == ['save:water', 'delete:water']
assert 'No matching Lumen entry remains' in report['undoStatus']
source = json.loads((base / args.source).read_text())
for name, facts in source['files'].items():
    assert digest((repo / name).read_bytes()) == facts['sha256'], name
app = Path(run('xcrun', 'simctl', 'get_app_container', device, 'com.dbakp.lumen', 'app'))
binary = (app / 'Lumen').read_bytes()
expected = json.loads((base / args.build).read_text())
compiled = json.loads((base / expected['source']).read_text())
changed = [name for name, facts in compiled['files'].items() if digest((repo / name).read_bytes()) != facts['sha256']]
assert all(name.startswith('Tests/') for name in changed), changed
assert digest(binary) == expected['sha256'], 'Installed native binary differs'
(base / (label + '-report.json')).write_text(json.dumps(report, indent=2) + '\n')
result = {'status': 'passed', 'device': device, 'source': args.source, 'nativeBuildSource': expected['source'], 'testOnlySourceCarry': changed,
          'nativeChecks': len(report['checks']), 'hostMatchedSavedFiles': len(raw),
          'externalComponents': len(external), 'installedBinarySHA256': digest(binary),
          'files': {name: {'bytes': len(data), 'sha256': digest(data)} for name, data in raw.items()},
          'scope': 'Independent host reads match all native-reported saved bytes, live IDs/weight and controlled adapter components. Actual native test outcome, screenshots, real HealthKit and device gates remain separate.'}
(base / (label + '-host-audit.json')).write_text(json.dumps(result, indent=2) + '\n')
print('PASS:', len(report['checks']), 'native checks, five exact host/native files, seven source-owned controlled components, installed binary/source match.')
