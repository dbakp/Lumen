"""Independent file and real-SDK audit of a manual frozen-app flow."""
import base64
import datetime
import hashlib
import json
import re
import stat
import subprocess
import sys
import time
from pathlib import Path

D = Path(__file__).resolve().parent
REPO = D.parents[2]
OUT = D / 'health-measured-lumen-r1-audit.json'
SIM = 'AF849DEA-DF34-4B0E-9FC1-3E45DCBE8481'
C = json.loads((D / 'health-measured-source-r1-contract.json').read_text())
sha = lambda b: hashlib.sha256(b).hexdigest()


def container(bundle, kind):
    return Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', SIM, bundle, kind], text=True).strip())


def facts(root):
    assert root.is_dir() and not root.is_symlink()
    rows = {}
    for p in root.rglob('*'):
        s = p.lstat()
        if stat.S_ISDIR(s.st_mode):
            continue
        assert stat.S_ISREG(s.st_mode) and s.st_size < 256 * 1024
        b = p.read_bytes()
        rows[str(p.relative_to(root))] = dict(bytes=len(b), sha256=sha(b), base64=base64.b64encode(b).decode(),
                                            inode=s.st_ino, mode=stat.S_IMODE(s.st_mode))
    return rows


def frozen():
    source = json.loads((D / 'durable-source-r162.json').read_text())
    for name, fact in {**source['files'], **source['fixtureInputs']}.items():
        b = (REPO / name).read_bytes()
        assert len(b) == fact['bytes'] and sha(b) == fact['sha256'], name
    build = json.loads((D / 'health-daily-controls-r1-build.json').read_text())
    b = (container('com.dbakp.lumen', 'app') / 'Lumen').read_bytes()
    assert len(b) == build['binaryBytes'] and sha(b) == build['sha256']


def save(a):
    OUT.write_text(json.dumps(a, indent=2) + '\n')


def query():
    b = (g / 'Lumen-daily-cache-health-query.json').read_bytes()
    return b, json.loads(b)


frozen()
g = container('com.dbakp.lumen', 'group.com.dbakp.lumen')
root, prior = g / 'LumenData', g / 'LumenData.previous'
phase = sys.argv[1]
if phase == 'baseline':
    assert not OUT.exists()
    old = json.loads((D / 'health-daily-identity-change-r1-audit.json').read_text())
    assert old['status'].startswith('PASS') and facts(root) == old['afterVerification']
    assert facts(prior) == old['previousAfterVerification']
    seed = json.loads((D / 'health-measured-source-r1-inspected.json').read_text())
    assert seed['run'] == C['run'] and seed['status'] == 'inspected-complete'
    assert len(seed['observed']) == len(seed['rows']) == 22
    a = dict(status='Baseline captured; actual app query/save pending', source='durable-source-r162.json',
             started=time.time(), before=facts(root), previousBefore=facts(prior), helper=seed,
             driverSHA256=sha(Path(__file__).read_bytes()),
             scope='Manual main/light/standard actual query/review/commit/removal control; not XCTest or full18metric detail capture or design acceptance.')
    save(a)
else:
    a = json.loads(OUT.read_text())
    assert facts(prior) == a['previousBefore']
    if phase == 'access-control':
        assert facts(root) == a['before']
        b, q = query()
        first = json.loads((D / 'health-measured-lumen-r1-first-query.json').read_text())
        assert q['requestID'] != first['requestID']
        assert q['requestCompleted'] and len(q['callbacks']) == 18
        readings = q['metrics']['readings']
        assert len(readings) == 18
        recorded = {k for k, r in readings.items() if r['healthQuery']['outcome'] == 'recorded'}
        assert recorded == set(C['expected']) - {'restingHR'}
        for key, reading in readings.items():
            check = reading['healthQuery']
            assert check['start'] == q['start'] and check['end'] == q['end']
            if key in recorded:
                component, = reading['components']
                assert abs(component['value'] - C['expected'][key]) < 1e-8
                assert component['origin'] == 'healthKit' and not component['isEstimate']
            else:
                assert check['outcome'] == 'noData' and reading['components'] == []
        assert first['metrics']['readings']['activeEnergy']['healthQuery']['outcome'] == 'noData'
        assert readings['activeEnergy']['components'][0]['value'] == 50
        (D / 'health-measured-lumen-r1-active-access-query.json').write_bytes(b)
        a.update(accessControl=dict(requestID=q['requestID'], firstRequestID=first['requestID'],
                 recorded=10, noData=8, failed=0, activeEnergy=50,
                 allCurrentFileFactsExact=True, allPriorFileFactsExact=True,
                 permissionEvidence='health-measured-lumen-r1-active-access-limited.png',
                 noReadPermissionInferredFromEmptyResult=True,
                 stillMissing=['restingHR'], committed=False),
                 status='Partial diagnostic: active-energy access change yields expected50kcal; restingHR unresolved; original11recorded contract NOT passed')
        save(a)
    elif phase == 'query':
        assert facts(root) == a['before']
        b, q = query()
        assert (g / 'Lumen-daily-cache-health-query.json').stat().st_mtime >= a['started']
        assert q['requestCompleted'] and len(q['callbacks']) == 18
        assert len(q['metrics']['readings']) == 18
        mapping = dict(restingHR='RestingHeartRate', hrv='HeartRateVariabilitySDNN', spo2='OxygenSaturation',
                       weight='BodyMass', respiratoryRate='RespiratoryRate', vo2max='VO2Max', bodyFat='BodyFatPercentage')
        for key, reading in q['metrics']['readings'].items():
            check = reading['healthQuery']
            assert check['start'] == q['start'] and check['end'] == q['end']
            assert check['outcome'] == ('recorded' if key in C['expected'] else 'noData')
            if key not in C['expected']:
                assert reading['components'] == []
                continue
            assert len(reading['components']) == 1
            c = reading['components'][0]
            assert abs(c['value'] - C['expected'][key]) < 1e-8 and c['origin'] == 'healthKit' and not c['isEstimate']
            assert c['aggregation'] == ('latest' if key in C['latestKeys'] else 'average' if key == 'heartRate' else 'total')
            if key in C['latestKeys']:
                rows = [r for r in a['helper']['rows'] if r['identifier'] == 'HKQuantityTypeIdentifier' + mapping[key]]
                assert len(rows) == 2
                latest = max(rows, key=lambda r: r['end'])
                date = datetime.datetime.fromtimestamp(latest['end'] + 978307200, datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
                assert c['start'] == c['end'] == c['lastSampleAt'] == date, (key, c, date)
                assert c['source'] == 'Apple Health · Lumen Health Source Fixture'
            else:
                assert c['start'] == q['start'] and c['end'] == q['end']
        for row in a['helper']['rows']:
            instant = datetime.datetime.fromtimestamp(row['start'] + 978307200, datetime.timezone.utc)
            assert datetime.datetime.fromisoformat(q['start'].replace('Z', '+00:00')) <= instant <= datetime.datetime.fromisoformat(q['end'].replace('Z', '+00:00'))
        access = json.loads((g / 'Lumen-daily-cache-health-access.json').read_bytes())
        assert access['requestCompleted'] and access['available'] and access['connected'] and not access['readPermissionInferred']
        (D / 'health-measured-lumen-r1-query.json').write_bytes(b)
        a.update(query=q, access=access, status='Actual11recorded/7noData values, units/aggregation/latest dates pass; native save pending')
        save(a)
    elif phase == 'watch-save':
        assert 'query' in a and facts(root) == a['before']
        deadline = time.monotonic() + 180
        while time.monotonic() < deadline:
            p = g / 'Lumen-health-cancel-checkpoint.json'
            state = json.loads(p.read_bytes())
            if p.stat().st_mtime >= a['started'] and state.get('attempts') and state['attempts'][-1]['phase'] == 'held':
                break
            time.sleep(.05)
        else:
            raise AssertionError('No actual held worker within180seconds')
        record = state['attempts'][-1]
        assert record['workerControlMatchesUI'] and not record['uiCancelled']
        assert re.fullmatch(r'LumenData\.restore-[A-Fa-f0-9-]+', record['stage']) and (g / record['stage']).is_dir()
        assert facts(root) == a['before'] and facts(prior) == a['previousBefore']
        release = g / ('Lumen-measured-release-' + record['nonce'] + '.tmp')
        release.write_text(json.dumps({'nonce': record['nonce']}))
        release.replace(g / 'Lumen-health-cancel-release.json')
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            after = facts(root)
            if after['today.json']['sha256'] != a['before']['today.json']['sha256'] and not (g / record['stage']).exists():
                break
            time.sleep(.05)
        else:
            raise AssertionError('No actual commit/stage cleanup within30seconds')
        for name, value in a['before'].items():
            if name != 'today.json':
                assert after[name] == value, name
        assert facts(prior) == a['previousBefore']
        assert json.loads(base64.b64decode(after['today.json']['base64'])) == a['query']['metrics']
        added = set(after) - set(a['before'])
        assert len(added) == 4 and all(n.startswith(('.health-recovery/', '.health-cache-history/')) for n in added)
        assert sum(n.startswith('.health-recovery/') and n.endswith('/today.json') and f['sha256'] == a['before']['today.json']['sha256'] for n, f in after.items()) == 1
        receipts = [n for n in added if n.startswith('.health-cache-history/')]
        assert len(receipts) == 1
        receipt = json.loads(base64.b64decode(after[receipts[0]]['base64']))
        owner = json.loads(base64.b64decode(a['before']['health-write-intent.json']['base64']))['owner']
        assert receipt['action'] == 'rebuild' and receipt['owner'] == owner and receipt['rawDigest'] == after['today.json']['sha256']
        assert receipt['prior']['state'] == 'healthy' and receipt['prior']['entries']['']['digest'] == a['before']['today.json']['sha256']
        a.update(held=record, heldUICaptureClaimed=False, after=after, previousAfter=facts(prior), receipt=receipt,
                 stageAbsent=True, status='Actual measured snapshot committed; all19other-current/9prior facts exact; helper removal control pending')
        save(a)
    elif phase == 'removal-control':
        assert facts(root) == a['after'] and facts(prior) == a['previousBefore']
        cleaned = json.loads((D / 'health-measured-source-r1-cleaned.json').read_text())
        inspected = json.loads((D / 'health-measured-source-r1-after-cleanup.json').read_text())
        for ledger in (cleaned, inspected):
            assert ledger['run'] == C['run'] and ledger['rows'] == a['helper']['rows']
            assert ledger['observed'] == [] and len(ledger['rows']) == 22
        assert cleaned['status'] == 'cleaned' and inspected['status'] == 'inspected-partial'
        b, q = query()
        assert q['requestID'] != a['query']['requestID'] and q['requestCompleted']
        assert len(q['callbacks']) == len(q['metrics']['readings']) == 18
        assert q['end'] > a['query']['end']
        for reading in q['metrics']['readings'].values():
            assert reading['healthQuery']['outcome'] == 'noData' and reading['components'] == []
        assert not list(g.glob('LumenData.restore-*'))
        (D / 'health-measured-lumen-r1-removal-query.json').write_bytes(b)
        a.update(removalControl=dict(requestID=q['requestID'], recorded=0, noData=18, failed=0,
                 exactHelperSamplesRemoved=22, independentlyRelaunchedRemaining=0,
                 committed24FilesExact=True, prior9FilesExact=True),
                 status='Actual11metric commit and exact22sample removal/fresh18noData pass; final Back/idle pending')
        save(a)
    elif phase == 'verify':
        assert facts(root) == a['after'] and facts(prior) == a['previousBefore']
        assert not list(g.glob('LumenData.restore-*'))
        a.update(afterNavigation=facts(root), previousAfterNavigation=facts(prior), verifiedAt=time.time())
        save(a)
    else:
        raise AssertionError('Unknown phase')
print(json.loads(OUT.read_text())['status'], flush=True)
