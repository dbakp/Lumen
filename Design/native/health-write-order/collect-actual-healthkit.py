"""Audit current actual-HealthKit observations against persisted native receipts."""
import hashlib
import gzip
import json
from pathlib import Path
import subprocess

base = Path(__file__).resolve().parent
repo = base.parents[2]
device = '922E011C-3895-4DB1-9C9A-1D3A977226CF'
def container(kind):
    return Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', device, 'com.dbakp.lumen', kind]).decode().strip())
def digest(data):
    return hashlib.sha256(data).hexdigest()
report_bytes = (container('data') / 'tmp/Lumen-durable-healthkit-report.json').read_bytes()
report = json.loads(report_bytes)
assert report['status'] == 'HealthKit replay checks passed'
assert len(report['checks']) == 47 and all(row['passed'] for row in report['checks'])
assert report['exactFixtureCleanupVerified']
native_log = gzip.decompress((base / 'DurableActualHealthKitR2.log.gz').read_bytes()).decode()
assert '** TEST EXECUTE SUCCEEDED **' in native_log
assert "testDurableHealthKitReplayAndRemoval]' passed" in native_log
expected = {'water': 137, 'calories': 213, 'protein': 11, 'carbs': 23, 'fat': 9, 'fiber': 4, 'weight': 76.25}
assert {row['metric'] for row in report['samples']} == set(expected)
saves, deletes = report['journalAfterSaves'], report['journalAfterDeletes']
assert saves['owner'] == deletes['owner'] and saves['lifecycle'] == deletes['lifecycle']
assert len(saves['events']) == len(deletes['events']) == 3
identities = {}
for event in saves['events']:
    assert event['action'] == 'save' and not event.get('issue')
    assert set(event['acknowledged']) == {row['metric'] for row in event['components']}
    for component in event['components']:
        identity = f"com.dbakp.lumen.health.v1.{saves['owner']}.{event['id']}.{component['metric']}"
        identities[component['metric']] = (identity, component)
for row in report['samples']:
    identity, component = identities[row['metric']]
    assert row['syncIdentifier'] == identity
    assert row['beforeCount'] == row['afterReplayCount'] == 1
    assert row['value'] == row['beforeValue'] == component['value'] == expected[row['metric']]
    assert row['date'] == row['beforeDate'] == component['date'] == 1_790_000_043 - 978_307_200
    assert row['sourceBundle'] == 'com.dbakp.lumen'
    assert row['beforeUUID'] and row['afterReplayUUID']
for event in deletes['events']:
    assert event['action'] == ('save' if event['domain'] == 'weight' else 'delete')
    assert set(event['acknowledged']) == {row['metric'] for row in event['components']}
def normalize(journal):
    for event in journal['events']:
        event['acknowledged'].sort()
    return journal
actual_intent = (container('group.com.dbakp.lumen') / 'LumenData/health-write-intent.json').read_bytes()
assert normalize(json.loads(actual_intent)) == normalize(deletes)
source = json.loads((base / 'durable-source-r6.json').read_text())
for name, facts in source['files'].items():
    assert digest((repo / name).read_bytes()) == facts['sha256'], name
binary = (container('app') / 'Lumen').read_bytes()
build = json.loads((base / 'durable-native-build-r5.json').read_text())
assert digest(binary) == build['sha256']
(base / 'actual-healthkit-r2-report.json').write_bytes(report_bytes)
(base / 'actual-healthkit-r2-persisted-intent.json').write_bytes(actual_intent)
result = {'status': 'passed', 'source': 'durable-source-r6.json', 'sourceInputs': len(source['files']),
          'nativeXCTest': 'passed', 'nativeChecks': len(report['checks']), 'sampleTypes': len(expected),
          'firstSaveCountPerType': 1, 'afterReplayCountPerType': 1,
          'sameUUIDCount': sum(row['beforeUUID'] == row['afterReplayUUID'] for row in report['samples']),
          'measuredQuantitiesAndDatesMatch': True, 'sourceBundleMatches': True,
          'persistedReceiptStateMatches': True, 'exactFixtureCleanupVerified': True,
          'installedBinarySHA256': digest(binary), 'reportSHA256': digest(report_bytes),
          'intentSHA256': digest(actual_intent),
          'scope': 'Host verifies actual native HealthKit API observations for seven types, one logical sample per type before/after replay, values/dates/source, exact persisted receipt state and installed binary. Cleanup verified by the native API. No independent host Health database query, foreign-source, process restart, physical-device or background/locked proof.'}
(base / 'actual-healthkit-r2-host-audit.json').write_text(json.dumps(result, indent=2) + '\n')
print('PASS: 47 native checks; seven real HealthKit types retain one logical sample and exact quantities/dates/source; persisted receipts and installed binary match; exact fixture cleanup verified.')
