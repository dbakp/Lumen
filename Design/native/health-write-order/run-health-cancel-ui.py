"""Run the real synthetic Cancel/retry UI with independent file/barrier reads.

Release files only advance a DEBUG test barrier, not user consent or recovery.
"""
import argparse
import base64
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
p.add_argument('--device', choices=['main', 'compact'], required=True)
p.add_argument('--trial', required=True)
p.add_argument('--appearance', choices=['normal', 'dark', 'largest'], default='normal')
p.add_argument('--expect-failure', action='store_true')
p.add_argument('--action', choices=['cancel', 'back'], default='cancel')
a = p.parse_args()
assert re.fullmatch(r'[A-Za-z0-9-]+', a.trial)
base = Path(__file__).resolve().parent
repo = base.parents[2]
raw = Path('/tmp/LumenBatch43Checks')
device = {'main': 'AF849DEA-DF34-4B0E-9FC1-3E45DCBE8481',
          'compact': '922E011C-3895-4DB1-9C9A-1D3A977226CF'}[a.device]
stem = 'HealthCancel' + a.device.title() + a.trial
prefix = 'health-cancel-' + a.device + '-' + a.trial.lower()
result = raw / (stem + '.xcresult')
assert not result.exists()
source = json.loads((base / a.source).read_text())
build = json.loads((base / a.build).read_text())
sha = lambda data: hashlib.sha256(data).hexdigest()

def container(kind):
    return Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', device,
                                        'com.dbakp.lumen', kind], text=True).strip())

def identity():
    for name, facts in source['files'].items():
        assert sha((repo / name).read_bytes()) == facts['sha256'], name
    assert build['source'] == a.source
    assert sha((container('app') / 'Lumen').read_bytes()) == build['sha256']

def files(root):
    rows = {}
    for path in root.rglob('*'):
        kind = path.lstat().st_mode
        if stat.S_ISDIR(kind):
            continue
        assert stat.S_ISREG(kind), path
        data = path.read_bytes()
        assert len(data) < 1_000_000
        rows[str(path.relative_to(root))] = {'bytes': len(data), 'sha256': sha(data),
                                            'base64': base64.b64encode(data).decode()}
    return rows

def check_originals(root, record):
    for name, encoded in record['originals'].items():
        assert (root / name).read_bytes() == base64.b64decode(encoded), name
    assert (root / 'water.json').read_bytes() == b'{"syntheticUnavailableWater":'
    assert not list((root / '.health-recovery-history').glob('*.json'))

def release(group, record):
    path = group / 'Lumen-health-cancel-release.json'
    temporary = group / (path.name + '.' + record['nonce'] + '.tmp')
    with temporary.open('xb') as stream:
        stream.write(json.dumps({'nonce': record['nonce']}).encode())
    temporary.replace(path)

suffix = {'normal': '', 'dark': 'Dark', 'largest': 'Largest'}[a.appearance]
command = ['xcodebuild', '-project', 'Lumen.xcodeproj', '-scheme', 'Lumen', '-configuration', 'Debug',
           '-destination', 'platform=iOS Simulator,id=' + device,
           '-derivedDataPath', '/tmp/LumenBatch37Simulator',
           '-clonedSourcePackagesDirPath', '/tmp/LumenBatch37Packages', '-disableAutomaticPackageResolution',
           '-parallel-testing-enabled', 'NO',
           '-collect-test-diagnostics', 'never',
           '-only-testing:LumenUITests/LumenSmokeTests/testHealthRecoveryScreenCancel' + ('Back' if a.action == 'back' else '') + suffix,
           '-resultBundlePath', str(result), 'test-without-building']
started = time.time()
events, released = [], set()
cancel_seen = None
latest = None
log = raw / (stem + '.log')
with log.open('wb') as stream:
    process = subprocess.Popen(command, cwd=repo, stdout=stream, stderr=subprocess.STDOUT)
    # Keep this finite native test awake without changing system preferences.
    # The assertion ends automatically when its actual xcodebuild exits.
    awake = subprocess.Popen(['caffeinate', '-d', '-i', '-w', str(process.pid)])
    try:
        while process.poll() is None:
            assert time.time() - started < 210, 'Native UI test deadline'
            try:
                group = container('group.com.dbakp.lumen')
                checkpoint = group / 'Lumen-health-cancel-checkpoint.json'
                if not checkpoint.exists() or checkpoint.stat().st_mtime < started:
                    time.sleep(0.2)
                    continue
                latest = json.loads(checkpoint.read_bytes())
            except (subprocess.CalledProcessError, FileNotFoundError, json.JSONDecodeError):
                # Installation/atomic checkpoint replacement is transient;
                # keep observing the same live XCTest producer.
                time.sleep(0.2)
                continue
            identity()
            root = group / 'LumenData'
            for record in latest['attempts']:
                assert re.fullmatch(r'LumenData\.restore-[A-Fa-f0-9-]+', record['stage'])
                if record['nonce'] in released:
                    continue
                if a.expect_failure and record['ordinal'] == 1 and record['uiCancelled']:
                    assert not record['workerControlMatchesUI']
                    check_originals(root, record)
                    cancel_seen = cancel_seen or time.monotonic()
                    if time.monotonic() - cancel_seen >= 5:
                        events.append({'record': record, 'beforeReleaseFiles': files(root),
                                       'heldAfterObservedUICancelSeconds': time.monotonic() - cancel_seen,
                                       'stageExists': (group / record['stage']).is_dir()})
                        release(group, record); released.add(record['nonce'])
                elif not a.expect_failure and record['ordinal'] == 2 and record['phase'] == 'held':
                    # XCTest must first observe the real busy accessibility
                    # state and capture it. Releasing at checkpoint creation
                    # races that observation and can skip the held screen.
                    if "Added attachment named 'health-recovery-cancel-retry-held'" not in log.read_text():
                        continue
                    first = latest['attempts'][0]
                    assert first['phase'] == 'cancelled' and first['uiCancelled'] and first['workerControlMatchesUI']
                    assert not (group / first['stage']).exists()
                    assert record['workerControlMatchesUI']
                    check_originals(root, first); check_originals(root, record)
                    events.append({'cancelledAttempt': first, 'retryRecord': record,
                                   'beforeRetryReleaseFiles': files(root), 'cancelledStageAbsent': True})
                    release(group, record); released.add(record['nonce'])
            time.sleep(0.2)
        code = process.wait()
    finally:
        (base / (prefix + '-driver-observations.json')).write_text(json.dumps({
            'source': a.source, 'build': a.build, 'events': events, 'latest': latest,
            'producerPID': process.pid, 'producerExitCode': process.poll(),
            'scope': 'Actual dedicated synthetic stage/control and file observations; no HealthKit/device claim.'
        }, indent=2) + '\n')

# First reads/exports from this bundle are deliberately sequential.
summary = json.loads(subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary',
                                              '--path', str(result)], text=True))
(raw / (stem + '-summary.json')).write_text(json.dumps(summary, indent=2) + '\n')
(base / (prefix + '-summary.json')).write_text(json.dumps(summary, indent=2) + '\n')
assert events and latest, 'No valid held/cancelled transaction was independently observed'
identity()
group = container('group.com.dbakp.lumen'); root = group / 'LumenData'
for record in latest['attempts']:
    deadline = time.monotonic() + 5
    while (group / record['stage']).exists() and time.monotonic() < deadline:
        time.sleep(0.05)
    assert not (group / record['stage']).exists(), 'Abandoned stage did not finish cleanup'
if a.expect_failure:
    assert code == 65 and summary['failedTests'] == 1
    assert 'Cancel must reach held transaction preparation' in json.dumps(summary['testFailures'])
    check_originals(root, latest['attempts'][0])
else:
    assert code == 0 and summary['passedTests'] == 1 and summary['failedTests'] == 0
    assert len(latest['attempts']) == 2
    water = (root / 'water.json').read_bytes()
    assert json.loads(water)[0]['id'] == 'synthetic-review-water' and json.loads(water)[0]['ml'] == 137
    original = latest['attempts'][0]['originals']
    for name in ['meals.json', 'workouts.json', 'goals.json', 'today.json']:
        assert (root / name).read_bytes() == base64.b64decode(original[name])
    journal = json.loads((root / 'health-write-intent.json').read_bytes())
    old = json.loads(base64.b64decode(original['health-write-intent.json']))
    assert journal['owner'] == old['owner'] and journal['lifecycle'] != old['lifecycle'] and journal['events'] == []
    receipts = list((root / '.health-recovery-history').glob('*.json'))
    assert len(receipts) == 1
    receipt = json.loads(receipts[0].read_bytes())
    assert receipt['domains'] == ['water'] and receipt['recordDigests']['water.json'] == sha(water)
    private = list((root / '.health-recovery').glob('*/water.json'))
    assert any(f.read_bytes() == water for f in private)
    assert any(f.read_bytes() == b'{"syntheticUnavailableWater":' for f in private)
(base / (prefix + '-host-audit.json')).write_text(json.dumps({
    'status': 'expected baseline failure verified' if a.expect_failure else 'Cancel/retry/relaunch and exact final files verified',
    'source': a.source, 'build': a.build, 'events': events, 'finalProtocol': latest,
    'files': files(root), 'verifierSHA256': sha(Path(__file__).read_bytes()),
    'scope': 'Held real water transaction on dedicated synthetic simulator. Source files/empty intent unchanged through Cancel; '
             'successful retry/relaunch checked when applicable. Not all-domain capacity, in-flight daemon, process-loss or device proof.'
}, indent=2) + '\n')
print('VERIFIED:', a.device, a.trial, 'exit', code, 'host events', len(events), flush=True)
