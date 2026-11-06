"""Actual retained-record Back/retry; independent source/tree/open-FD audit."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import time

p = argparse.ArgumentParser()
p.add_argument('--source', required=True)
p.add_argument('--build', required=True)
p.add_argument('--trial', required=True)
p.add_argument('--scope', choices=['retained-record', 'retained-photo'], default='retained-record')
a = p.parse_args()
assert re.fullmatch(r'[A-Za-z0-9-]+', a.trial)
base = Path(__file__).resolve().parent
repo = base.parents[2]
raw = Path('/tmp/LumenBatch43Checks')
device = 'AF849DEA-DF34-4B0E-9FC1-3E45DCBE8481'
scope = a.scope
photo = scope == 'retained-photo'
stem = ('HealthHeldReadRetainedPhoto' if photo else 'HealthHeldReadRetainedRecord') + a.trial
prefix = 'health-held-read-' + scope + '-' + a.trial.lower()
bundle = raw / (stem + '.xcresult')
assert not bundle.exists()
source = json.loads((base / a.source).read_text())
build = json.loads((base / a.build).read_text())
sha = lambda data: hashlib.sha256(data).hexdigest()


def container(kind):
    return Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', device,
                                        'com.dbakp.lumen', kind], text=True).strip())


def identity():
    assert build['source'] == a.source
    for name, row in {**source['files'], **source.get('fixtureInputs', {})}.items():
        assert sha((repo / name).read_bytes()) == row['sha256'], name
    assert sha((container('app') / 'Lumen').read_bytes()) == build['sha256']


def snapshot(root):
    assert root.is_dir() and not root.is_symlink()
    rows = {}
    total = 0
    for parent, directories, files in os.walk(root, followlinks=False):
        for name in directories:
            assert not (Path(parent) / name).is_symlink()
        for name in files:
            f = Path(parent) / name
            facts = f.lstat()
            assert stat.S_ISREG(facts.st_mode) and facts.st_size <= 256 * 1024, f
            data = f.read_bytes()
            total += len(data)
            assert total <= 2 * 1024 * 1024
            rows[str(f.relative_to(root))] = {'bytes': len(data), 'sha256': sha(data),
                                             'base64': base64.b64encode(data).decode()}
    assert (root / 'water.json').read_bytes() == b'{"syntheticUnavailableWater":'
    return rows


started = time.time()
before = None
observations = []
protocol = None
acknowledged = set()
released = set()
command = ['xcodebuild', '-project', 'Lumen.xcodeproj', '-scheme', 'Lumen', '-configuration', 'Debug',
           '-destination', 'platform=iOS Simulator,id=' + device,
           '-derivedDataPath', '/tmp/LumenBatch37Simulator',
           '-clonedSourcePackagesDirPath', '/tmp/LumenBatch37Packages', '-disableAutomaticPackageResolution',
           '-parallel-testing-enabled', 'NO', '-collect-test-diagnostics', 'never',
           '-only-testing:LumenUITests/LumenSmokeTests/' + ('testHealthRecoveryReadRetainedPhoto' if photo else 'testHealthRecoveryReadRetainedRecords'),
           '-resultBundlePath', str(bundle), 'test-without-building']
with (raw / (stem + '.log')).open('wb') as out:
    process = subprocess.Popen(command, cwd=repo, stdout=out, stderr=subprocess.STDOUT)
    awake = subprocess.Popen(['caffeinate', '-d', '-i', '-w', str(process.pid)])
    deadline = time.monotonic() + 400
    try:
        while process.poll() is None:
            assert time.monotonic() < deadline, 'Inspect same producer; do not restart on observation timeout'
            group = container('group.com.dbakp.lumen')
            checkpoint = group / 'Lumen-health-read-checkpoint.json'
            try:
                if checkpoint.stat().st_mtime < started:
                    time.sleep(0.2)
                    continue
                protocol = json.loads(checkpoint.read_bytes())
            except (FileNotFoundError, json.JSONDecodeError):
                time.sleep(0.2)
                continue
            root = group / 'LumenData'
            assert Path(protocol['root']).resolve() == root.resolve()
            for record in protocol['attempts']:
                nonce = record['nonce']
                if record['phase'] != 'held' or nonce in acknowledged or nonce in released:
                    continue
                tag = scope + ('-read-held' if record['ordinal'] == 1 else '-read-retry-held')
                if ("Added attachment named '" + tag + "'") not in (raw / (stem + '.log')).read_text():
                    continue
                identity()
                assert record['scope'] == scope and record['workerControlMatchesUI']
                file = Path(record['file'])
                assert not file.is_symlink() and file.resolve().is_relative_to((root / '.health-recovery').resolve())
                facts = file.lstat()
                assert stat.S_ISREG(facts.st_mode) and facts.st_ino == record['inode'] and facts.st_size == record['size']
                assert 0 < record['bytesRead'] <= min(64 * 1024, facts.st_size)
                assert Path(subprocess.check_output(['ps', '-p', str(record['pid']), '-o', 'comm='], text=True).strip()) == container('app') / 'Lumen'
                lsof = subprocess.check_output(['lsof', '-nP', '-a', '-p', str(record['pid']), '-d', str(record['descriptor']), '-Fnift'], text=True)
                assert 'tREG' in lsof and ('i' + str(record['inode'])) in lsof
                assert any(line.startswith('n') and Path(line[1:]).resolve() == file.resolve() for line in lsof.splitlines())
                tree = snapshot(root)
                if before is None:
                    before = tree
                assert tree == before
                if photo:
                    assert file.suffix == '.jpg' and file.name == 'synthetic-review-photo.jpg'
                    assert file.read_bytes().startswith(b'\xff\xd8')
                    meals = json.loads((file.parent.parent / 'meals.json').read_bytes())
                    assert len(meals) == 2 and all(row['photoID'] == 'synthetic-review-photo' for row in meals)
                    current_photo = root / 'photos' / file.name
                    assert current_photo.read_bytes() == file.read_bytes()
                else:
                    water = json.loads((file.parent / 'water.json').read_bytes())
                    assert len(water) == 1 and water[0]['id'] == 'synthetic-review-water' and water[0]['ml'] == 137
                observations.append({'record': record.copy(), 'sourceBytes': base64.b64encode(file.read_bytes()).decode(),
                                     'sourceSHA256': sha(file.read_bytes()), 'openDescriptorReadback': lsof,
                                     'treeMatchesBefore': True, 'observedAfterNativeAttachment': tag})
                message = {'nonce': nonce}
                if record['ordinal'] == 1:
                    message['acknowledgementOnly'] = True
                    acknowledged.add(nonce)
                else:
                    first = protocol['attempts'][0]
                    assert first['phase'] == 'cancelled' and first['uiCancelled'] and first['descriptorCloseSucceeded']
                    assert first['file'] == record['file'] and first['inode'] == record['inode']
                    assert first['nonce'] != nonce and record['ordinal'] == 2
                    released.add(nonce)
                release = group / 'Lumen-health-read-release.json'
                temporary = group / (release.name + '.' + nonce + '.tmp')
                temporary.write_text(json.dumps(message))
                temporary.replace(release)
            time.sleep(0.2)
        code = process.wait()
    finally:
        (base / (prefix + '-observations.json')).write_text(json.dumps({
            'source': a.source, 'build': a.build, 'producerPID': process.pid, 'producerExitCode': process.poll(),
            'before': before, 'heldObservations': observations, 'protocol': protocol,
            'scope': 'Dedicated synthetic simulator only; no personal phone data. No full original-contract acceptance.'
        }, indent=2) + '\n')
summary = json.loads(subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(bundle)], text=True))
for destination in [raw / (stem + '-summary.json'), base / (prefix + '-summary.json')]:
    destination.write_text(json.dumps(summary, indent=2) + '\n')
assert code == 0 and summary['passedTests'] == 1 and summary['failedTests'] == 0
identity()
protocol = json.loads((container('group.com.dbakp.lumen') / 'Lumen-health-read-checkpoint.json').read_bytes())
assert len(protocol['attempts']) == len(observations) == 2
assert protocol['attempts'][0]['phase'] == 'cancelled' and protocol['attempts'][1]['phase'] == 'released'
assert all(row['workerControlMatchesUI'] and row['descriptorCloseSucceeded'] for row in protocol['attempts'])
after = snapshot(container('group.com.dbakp.lumen') / 'LumenData')
assert after == before
(base / (prefix + '-host-audit.json')).write_text(json.dumps({
    'status': 'passed: native Back cancels actual matching ' + scope + ' reader and closes its descriptor; fresh retry after host release; all protected bytes unchanged',
    'source': a.source, 'build': a.build, 'before': before, 'after': after,
    'heldObservations': observations, 'protocol': protocol, 'producerExitCode': code,
    'verifierSHA256': sha(Path(__file__).read_bytes()),
    'scope': 'One main-normal ' + scope + ' Back/retry case. Held imports/selected records/photos, source mutation/replacement and full original contracts remain required.'
}, indent=2) + '\n')
print('PASS: actual ' + scope + ' Back/retry; independent exact bytes and open-descriptor audits')
