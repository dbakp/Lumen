"""Independent filesystem/SDK audit for a manually operated frozen Lumen UI.

This does not tap or confirm UI and does not edit product data. The save
observer releases the existing DEBUG preparation barrier only after checking
the actual worker and unchanged baseline; it does not extend its deadline.
"""
import argparse
import base64
import hashlib
import json
import re
import stat
import subprocess
import time
from pathlib import Path

base = Path(__file__).resolve().parent
repo = base.parents[2]
device = 'AF849DEA-DF34-4B0E-9FC1-3E45DCBE8481'
parser = argparse.ArgumentParser()
parser.add_argument('phase', choices=['before-query', 'query', 'watch-save'])
parser.add_argument('--run', required=True)
args = parser.parse_args()
assert re.fullmatch(r'[A-F0-9-]{36}', args.run)
prefix = 'health-foreign-lumen-r1'
path = base / (prefix + '-audit.json')
sha = lambda data: hashlib.sha256(data).hexdigest()


def container(bundle, kind):
    return Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', device, bundle, kind], text=True).strip())


def files(root):
    assert root.is_dir() and not root.is_symlink()
    rows, total = {}, 0
    for p in root.rglob('*'):
        info = p.lstat()
        if stat.S_ISDIR(info.st_mode):
            continue
        assert stat.S_ISREG(info.st_mode) and info.st_size < 256 * 1024, p
        data = p.read_bytes(); total += len(data)
        assert total < 8 * 1024 * 1024
        rows[str(p.relative_to(root))] = dict(bytes=len(data), sha256=sha(data), base64=base64.b64encode(data).decode(),
                                               inode=info.st_ino, mode=stat.S_IMODE(info.st_mode))
    return rows


def verify():
    source = json.loads((base / 'durable-source-r162.json').read_text())
    for name, fact in {**source['files'], **source['fixtureInputs']}.items():
        data = (repo / name).read_bytes()
        assert len(data) == fact['bytes'] and sha(data) == fact['sha256'], name
    build = json.loads((base / 'health-daily-controls-r1-build.json').read_text())
    binary = (container('com.dbakp.lumen', 'app') / 'Lumen').read_bytes()
    assert len(binary) == build['binaryBytes'] and sha(binary) == build['sha256']


verify()
group = container('com.dbakp.lumen', 'group.com.dbakp.lumen')
root, prior = group / 'LumenData', group / 'LumenData.previous'
if args.phase == 'before-query':
    assert not path.exists(), 'Never overwrite a previous trial'
    helper = container('com.dbakp.lumen.fixture.health-source', 'data') / 'Documents' / ('health-source-' + args.run + '.json')
    seed = json.loads(helper.read_bytes())
    assert seed['status'] == 'seeded' and seed['run'] == args.run
    assert len(seed['rows']) == len(seed['observed']) == len(set(seed['observed'])) == 10
    assert set(seed['observed']) == {r['uuid'] for r in seed['rows']}
    assert seed['source'] == 'com.dbakp.lumen.fixture.health-source'
    before = files(root)
    assert base64.b64decode(before['today.json']['base64']) == b'{"syntheticUnavailableToday":'
    assert len(before) == 16 and len(files(prior)) == 9
    audit = dict(status='baseline captured before actual UI query', source='durable-source-r162.json',
                 uiMode='manual native controls; no XCTest result claimed', run=args.run, seeded=seed,
                 started=time.time(), before=before, previousBefore=files(prior), driverSHA256=sha(Path(__file__).read_bytes()))
else:
    audit = json.loads(path.read_text()); assert audit['run'] == args.run
    assert files(prior) == audit['previousBefore']
    if args.phase == 'query':
        assert files(root) == audit['before']
        p = group / 'Lumen-daily-cache-health-query.json'
        assert p.stat().st_mtime >= audit['started']
        observed = json.loads(p.read_bytes())
        access = json.loads((group / 'Lumen-daily-cache-health-access.json').read_bytes())
        assert access['requestCompleted'] and access['available'] and access['connected'] and not access['readPermissionInferred']
        expected = {'water': 400, 'calories': 350, 'protein': 20, 'carbs': 40, 'fat': 12}
        readings = observed['metrics']['readings']
        assert len(readings) == 18 and observed['requestCompleted'] and len(observed['callbacks']) == 18
        for key, reading in readings.items():
            query = reading['healthQuery']
            assert query['start'] == observed['start'] and query['end'] == observed['end']
            assert query['outcome'] == ('recorded' if key in expected else 'noData'), (key, reading)
            if key in expected:
                assert len(reading['components']) == 1
                component = reading['components'][0]
                assert abs(component['value'] - expected[key]) < 1e-8 and component['origin'] == 'healthKit'
                # Statistics supplies no named source for these aggregates.
                # Causal source attribution needs a separate removal/requery
                # control; do not substitute the helper's name in product data.
                assert component['source'] == 'Apple Health'
            else:
                assert reading['components'] == []
        audit.update(status='actual five expected SDK quantities pass; save and removal control unexecuted', query=observed, access=access,
                     aggregateSourceLabel='Apple Health', causalRemovalControlRequired=True,
                     queryAuditDriverSHA256=sha(Path(__file__).read_bytes()))
        (base / (prefix + '-sdk-query.json')).write_bytes(p.read_bytes())
    else:
        assert 'query' in audit
        deadline = time.monotonic() + 180
        while time.monotonic() < deadline:
            checkpoint = group / 'Lumen-health-cancel-checkpoint.json'
            try:
                state = json.loads(checkpoint.read_bytes())
                if checkpoint.stat().st_mtime >= audit['started'] and state.get('attempts'):
                    break
            except (FileNotFoundError, json.JSONDecodeError):
                pass
            time.sleep(.1)
        else:
            raise AssertionError('No new actual preparation worker within180s')
        record = state['attempts'][0]
        assert len(state['attempts']) == 1 and record['ordinal'] == 1 and record['phase'] == 'held'
        assert record['workerControlMatchesUI'] and not record['uiCancelled']
        assert re.fullmatch(r'LumenData\.restore-[A-Fa-f0-9-]+', record['stage'])
        assert files(root) == audit['before'] and files(prior) == audit['previousBefore']
        assert (group / record['stage']).is_dir()
        verify()
        release = group / ('Lumen-cache-release-' + record['nonce'] + '.tmp')
        release.write_text(json.dumps({'nonce': record['nonce']}))
        release.replace(group / 'Lumen-health-cancel-release.json')
        audit['held'] = record
        audit['heldUICaptureClaimed'] = False
        path.write_text(json.dumps(audit, indent=2) + '\n')
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            after = files(root)
            if after['today.json']['sha256'] != audit['before']['today.json']['sha256'] and not (group / record['stage']).exists():
                break
            time.sleep(.1)
        else:
            raise AssertionError('No committed snapshot/stage cleanup within30s')
        assert files(prior) == audit['previousBefore']
        for name, fact in audit['before'].items():
            if name != 'today.json':
                assert after[name] == fact, name
        assert all(n.startswith(('.health-cache-history/', '.health-recovery/')) for n in set(after) - set(audit['before']))
        current = json.loads(base64.b64decode(after['today.json']['base64']))
        assert current == audit['query']['metrics'] and current['excludesLumenNutrition']
        assert any(n.startswith('.health-recovery/') and n.endswith('/today.json') and f['sha256'] == audit['before']['today.json']['sha256'] for n, f in after.items())
        receipts = [n for n in after if n.startswith('.health-cache-history/')]
        assert len(receipts) == 1
        receipt = json.loads(base64.b64decode(after[receipts[0]]['base64']))
        journal = json.loads(base64.b64decode(audit['before']['health-write-intent.json']['base64']))
        assert receipt['action'] == 'rebuild' and receipt['owner'] == journal['owner']
        assert receipt['rawDigest'] == after['today.json']['sha256']
        assert receipt['prior']['state'] == 'unavailable' and receipt['prior']['entries']['']['digest'] == audit['before']['today.json']['sha256']
        audit.update(status='actual foreign-source SDK snapshot committed;15other-current/9prior/raw/intent preserved', after=after,
                     previousAfter=files(prior), receipt=receipt, stageAbsent=True)
path.write_text(json.dumps(audit, indent=2) + '\n')
print(audit['status'], flush=True)
