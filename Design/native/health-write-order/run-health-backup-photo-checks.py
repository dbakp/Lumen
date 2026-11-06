"""Run checked native photo adapters/restore with independent bounded host reads."""
import argparse
import base64
import gzip
import hashlib
import json
from pathlib import Path
import re
import stat
import subprocess
import time

p = argparse.ArgumentParser()
p.add_argument('--source', required=True)
p.add_argument('--build', required=True)
p.add_argument('--trial', required=True)
a = p.parse_args()
assert re.fullmatch('[A-Za-z0-9-]+', a.trial)
base = Path(__file__).resolve().parent
repo = base.parents[2]
raw = Path('/tmp/LumenBatch43Checks')
stem = 'HealthBackupPhotoNative' + a.trial
prefix = 'health-backup-photo-native-' + a.trial.lower()
result = raw / (stem + '.xcresult')
assert not result.exists()
source = json.loads((base / a.source).read_text())
build = json.loads((base / a.build).read_text())
sha = lambda data: hashlib.sha256(data).hexdigest()
device = 'AF849DEA-DF34-4B0E-9FC1-3E45DCBE8481'

def container(kind):
    return Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', device, 'com.dbakp.lumen', kind], text=True).strip())

def verify():
    assert build['source'] == a.source
    for name, row in {**source['files'], **source.get('fixtureInputs', {})}.items():
        assert sha((repo / name).read_bytes()) == row['sha256'], name

def files(root):
    rows = {}
    total = 0
    for path in root.rglob('*'):
        kind = path.lstat().st_mode
        if stat.S_ISDIR(kind):
            continue
        assert stat.S_ISREG(kind) and path.stat().st_size < 256 * 1024, path
        data = path.read_bytes()
        total += len(data)
        assert total < 2 * 1024 * 1024
        rows[str(path.relative_to(root))] = {'bytes': len(data), 'sha256': sha(data), 'base64': base64.b64encode(data).decode()}
    return rows

verify()
command = ['xcodebuild', '-project', 'Lumen.xcodeproj', '-scheme', 'Lumen', '-configuration', 'Debug',
           '-destination', 'platform=iOS Simulator,id=' + device, '-derivedDataPath', '/tmp/LumenBatch37Simulator',
           '-clonedSourcePackagesDirPath', '/tmp/LumenBatch37Packages', '-disableAutomaticPackageResolution',
           '-parallel-testing-enabled', 'NO', '-collect-test-diagnostics', 'never',
           '-only-testing:LumenUITests/LumenSmokeTests/testBackupPhotoBindingChecks', '-resultBundlePath', str(result), 'test-without-building']
started = time.time()
with (raw / (stem + '.log')).open('xb') as stream:
    process = subprocess.Popen(command, cwd=repo, stdout=stream, stderr=subprocess.STDOUT)
    awake = subprocess.Popen(['caffeinate', '-d', '-i', '-w', str(process.pid)])
    code = process.wait()
summary = json.loads(subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(result)], text=True))
(raw / (stem + '-summary.json')).write_text(json.dumps(summary, indent=2) + '\n')
(base / (prefix + '-summary.json')).write_text(json.dumps(summary, indent=2) + '\n')
path = container('group.com.dbakp.lumen') / 'Lumen-photo-binding-checked.json'
assert path.stat().st_mtime >= started
report = json.loads(path.read_bytes())
root = Path(report['root'])
healthy = Path(report['healthyRoot'])
assert root.parent == container('data') / 'tmp' and re.fullmatch('Lumen-photo-binding-checked-[A-F0-9-]+', root.name) and not root.is_symlink()
assert healthy == container('group.com.dbakp.lumen') / 'LumenData' and not healthy.is_symlink()
actual = {'source': a.source, 'build': a.build, 'producerExitCode': code, 'nativeReport': report,
          'inputTargetFiles': files(root), 'healthyFiles': files(healthy),
          'verifierSHA256': sha(Path(__file__).read_bytes()),
          'scope': 'Actual native BackupService adapters and restore, original/changed JPEGs, isolated recovery/omission targets and live healthy merge. Independent bounded host bytes. Not actual Files/meal/photo UI or full interruption/device acceptance.'}
(base / (prefix + '-host-observations.json')).write_text(json.dumps(actual, indent=2) + '\n')
log = raw / (stem + '.log')
(base / (log.name + '.gz')).write_bytes(gzip.compress(log.read_bytes(), mtime=0))
assert code == 0 and summary['passedTests'] == 1 and summary['failedTests'] == 0
verify()
assert sha((container('app') / 'Lumen').read_bytes()) == build['sha256']
assert report['status'] == 'Backup photo checks passed' and len(report['cases']) == 2
live_meals = json.loads((healthy / 'meals.json').read_bytes())
assert len(live_meals) == 2
for case in report['cases']:
    assert Path(case['input']).parent == root and Path(case['target']).parent == root and Path(case['omissionTarget']).parent == root
    original = (root / 'original.jpg').read_bytes()
    changed = (root / 'changed.jpg').read_bytes()
    assert sha(original) == case['originalPhotoSHA256'] != case['changedPhotoSHA256'] == sha(changed)
    assert case['shownPhotoSHA256'] == case['installedPhotoSHA256'] == sha(original)
    assert case['changedReviewRejected'] and case['changedPayloadRejected'] and case['healthyChangedMergeRejected']
    archive = Path(case['input']).read_bytes()
    assert sha(archive) == case['identity']['sha256'] and len(archive) == case['identity']['byteCount']
    target = Path(case['target'])
    meals = json.loads((target / 'meals.json').read_bytes())
    photo = 'photos/' + meals[0]['photoID'] + '.jpg'
    assert sha((target / photo).read_bytes()) == sha(original)
    receipt = json.loads(next((target / '.health-recovery-history').glob('*.json')).read_bytes())
    assert receipt['fileSource'] == case['identity'] and receipt['photoDigests'] == {photo: sha(original)}
    assert receipt['reviewedPhotos'] == {'synthetic-reviewed-photo': {'byteCount': len(original), 'sha256': sha(original)}}
    assert any(p.read_bytes() == b'{"syntheticUnavailableMeals":' for p in (target / '.health-recovery').glob('*/meals.json'))
    omitted = Path(case['omissionTarget'])
    assert all(m.get('photoID') is None for m in json.loads((omitted / 'meals.json').read_bytes()))
    omission_receipt = json.loads(next((omitted / '.health-recovery-history').glob('*.json')).read_bytes())
    assert omission_receipt['fileSource'] == case['identity'] and omission_receipt['omittedPhotoCount'] == 1
    assert omission_receipt['photoDigests'] == {} and omission_receipt['reviewedPhotos'] == {}
    live = next(m for m in live_meals if m['id'] == 'synthetic-photo-binding-' + case['kind'])
    assert live['photoID'] == case['healthyPhotoID'] and sha((healthy / 'photos' / (live['photoID'] + '.jpg')).read_bytes()) == sha(original)
    assert json.loads((target / 'health-write-intent.json').read_bytes())['events'] == []
assert json.loads((healthy / 'health-write-intent.json').read_bytes())['events'] == []
retained = Path(report['retainedSameRootTarget'])
assert retained.parent == root
retained_meals = json.loads((retained / 'meals.json').read_bytes())
assert len(retained_meals) == 1 and retained_meals[0]['id'] == 'native-same-root-retained'
retained_photo = 'photos/' + retained_meals[0]['photoID'] + '.jpg'
assert sha((retained / retained_photo).read_bytes()) == sha((root / 'original.jpg').read_bytes())
retained_receipt = json.loads(next((retained / '.health-recovery-history').glob('*.json')).read_bytes())
assert retained_receipt['source'].startswith('retained:') and retained_receipt['photoDigests'] == {retained_photo: sha((root / 'original.jpg').read_bytes())}
assert any(p.read_bytes() == b'{"syntheticUnavailableMeals":' for p in (retained / '.health-recovery').glob('*/meals.json'))
actual['status'] = 'passed: changed photos rejected; reviewed bytes/receipts/omissions and healthy live merge independently matched'
(base / (prefix + '-host-audit.json')).write_text(json.dumps(actual, indent=2) + '\n')
print('PASS:', len(report['checks']), 'actual native service checks, both formats, independent photo/receipt/healthy-store audit')
