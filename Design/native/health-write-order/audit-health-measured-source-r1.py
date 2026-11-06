"""Reinspect exact synthetic SDK samples and audit the incomplete Lumen query.

This does not relax the original eleven-reading/save/removal contract.
"""
import datetime as dt
import hashlib
import json
import subprocess
import time
from pathlib import Path

D = Path(__file__).resolve().parent
SIM = 'AF849DEA-DF34-4B0E-9FC1-3E45DCBE8481'
BUNDLE = 'com.dbakp.lumen.fixture.health-source'
C = json.loads((D / 'health-measured-source-r1-contract.json').read_text())


def container(bundle, kind):
    return Path(subprocess.check_output(
        ['xcrun', 'simctl', 'get_app_container', SIM, bundle, kind], text=True).strip())


def fact(path):
    b = path.read_bytes()
    return dict(bytes=len(b), sha256=hashlib.sha256(b).hexdigest())


assert fact(container(BUNDLE, 'app') / 'LumenHealthSourceFixture') == C['helperBinary']
for name, expected in C['helperFiles'].items():
    assert fact(D.parents[2] / name) == expected, name
ledger = container(BUNDLE, 'data') / 'Documents' / f"health-source-{C['run']}.json"
started = time.time()
launch = subprocess.check_output(['xcrun', 'simctl', 'launch', '--terminate-running-process',
                                  SIM, BUNDLE, 'inspect', C['run']], text=True).strip()
deadline = time.monotonic() + 20
while time.monotonic() < deadline:
    b = ledger.read_bytes()
    actual = json.loads(b)
    if ledger.stat().st_mtime >= started and actual['status'] == 'inspected-complete':
        break
    time.sleep(.1)
else:
    raise AssertionError('No fresh complete SDK inspection within20seconds')
previous = json.loads((D / 'health-measured-source-r1-inspected.json').read_text())
assert actual['version'] == 2 and actual['dataset'] == 'measured'
assert actual['source'] == BUNDLE and actual['run'] == C['run']
assert actual['rows'] == previous['rows']
assert len(actual['rows']) == len(actual['observed']) == 22
assert set(actual['observed']) == {r['uuid'] for r in actual['rows']}
assert len(set(actual['observed'])) == 22
(D / 'health-measured-source-r1-reinspected.json').write_bytes(b)

q = json.loads((D / 'health-measured-lumen-r1-active-access-query.json').read_text())
mapping = dict(hrv='HeartRateVariabilitySDNN', spo2='OxygenSaturation', weight='BodyMass',
               respiratoryRate='RespiratoryRate', vo2max='VO2Max', bodyFat='BodyFatPercentage')
date = lambda x: dt.datetime.fromtimestamp(x + 978307200, dt.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
parse = lambda x: dt.datetime.fromisoformat(x.replace('Z', '+00:00'))
assert q['requestCompleted'] and len(q['callbacks']) == len(q['metrics']['readings']) == 18
recorded, latest = [], []
for key, reading in q['metrics']['readings'].items():
    check = reading['healthQuery']
    assert check['start'] == q['start'] and check['end'] == q['end']
    if check['outcome'] != 'recorded':
        assert check['outcome'] == 'noData' and reading['components'] == []
        continue
    component, = reading['components']
    assert abs(component['value'] - C['expected'][key]) < 1e-8
    assert component['origin'] == 'healthKit' and not component['isEstimate']
    aggregation = 'latest' if key in C['latestKeys'] else 'average' if key == 'heartRate' else 'total'
    assert component['aggregation'] == aggregation
    if aggregation == 'latest':
        rows = [r for r in actual['rows'] if r['identifier'] == 'HKQuantityTypeIdentifier' + mapping[key]]
        assert len(rows) == 2
        newest = max(rows, key=lambda r: r['end'])
        assert component['start'] == component['end'] == component['lastSampleAt'] == date(newest['end'])
        assert component['source'] == 'Apple Health · Lumen Health Source Fixture'
        assert component['lastSampleAt'] != q['end']
        latest.append(key)
    else:
        assert component['start'] == q['start'] and component['end'] == q['end']
        assert component['source'] == 'Apple Health'
    recorded.append(key)
assert set(recorded) == set(C['expected']) - {'restingHR'} and len(latest) == 6
for row in actual['rows']:
    assert parse(q['start']) <= parse(date(row['start'])) <= parse(q['end'])
out = dict(status='PASS exact22sample SDK reinspection and ten returned metric facts; full case INCOMPLETE',
           run=C['run'], source='durable-source-r162.json', launch=launch, started=started,
           ledgerUpdated=ledger.stat().st_mtime, helperSamplesPresent=22,
           recordedKeys=sorted(recorded), latestSampleDatesMatched=sorted(latest),
           missingRequired=['restingHR'], unknownCount=8, failedCount=0,
           queryRequestID=q['requestID'], originalContractPassed=False,
           saveAndRemovalControlVerified=False, samplesRemainForImmediateContinuation=True,
           sources={n: fact(D / n) for n in ['health-measured-source-r1-contract.json',
                    'health-measured-source-r1-reinspected.json',
                    'health-measured-lumen-r1-active-access-query.json']})
(D / 'health-measured-source-r1-partial-audit.json').write_text(json.dumps(out, indent=2) + '\n')
print(out['status'], flush=True)
