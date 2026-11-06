"""Actual selected-file Cancel/retry with held-stage and original-source audits."""
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
p.add_argument('--case', choices=['legacy', 'encrypted', 'readable'], required=True)
p.add_argument('--trial', required=True)
p.add_argument('--observe-source', action='store_true')
p.add_argument('--back', action='store_true')
a = p.parse_args()
assert re.fullmatch(r'[A-Za-z0-9-]+', a.trial)
base = Path(__file__).resolve().parent
repo = base.parents[2]
raw = Path('/tmp/LumenBatch43Checks')
device = 'AF849DEA-DF34-4B0E-9FC1-3E45DCBE8481'
stem = 'HealthBackup' + ('Back' if a.back else 'Cancel') + a.case.title() + a.trial
prefix = 'health-backup-' + ('back-' if a.back else 'cancel-') + a.case + '-' + a.trial.lower()
result = raw / (stem + '.xcresult')
assert not result.exists()
source = json.loads((base / a.source).read_text())
build = json.loads((base / a.build).read_text())
digest = lambda data: hashlib.sha256(data).hexdigest()

def container(kind):
    return Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', device,
                                        'com.dbakp.lumen', kind], text=True).strip())

def identity():
    for name, row in {**source['files'], **source.get('fixtureInputs', {})}.items():
        assert digest((repo / name).read_bytes()) == row['sha256'], name
    assert build['source'] == a.source
    assert digest((container('app') / 'Lumen').read_bytes()) == build['sha256']

def originals(group, checkpoint):
    root = group / 'LumenData'
    rows = {}
    for name, encoded in checkpoint['originals'].items():
        path = root / name
        assert stat.S_ISREG(path.lstat().st_mode)
        data = path.read_bytes()
        assert data == base64.b64decode(encoded, validate=True), name
        rows[name] = {'bytes': len(data), 'sha256': digest(data), 'base64': encoded}
    assert (root / 'water.json').read_bytes() == b'{"syntheticUnavailableWater":'
    assert not list((root / '.health-recovery-history').glob('*.json'))
    return rows

command = ['xcodebuild', '-project', 'Lumen.xcodeproj', '-scheme', 'Lumen', '-configuration', 'Debug',
           '-destination', 'platform=iOS Simulator,id=' + device,
           '-derivedDataPath', '/tmp/LumenBatch37Simulator',
           '-clonedSourcePackagesDirPath', '/tmp/LumenBatch37Packages', '-disableAutomaticPackageResolution',
           '-parallel-testing-enabled', 'NO', '-collect-test-diagnostics', 'never',
           '-only-testing:LumenUITests/LumenSmokeTests/testHealthBackupFileRecovery' + a.case.title() + ('Back' if a.back else 'Cancel'),
           '-resultBundlePath', str(result), 'test-without-building']
started = time.time()
checkpoint = None
before = None
source_observations = []
held_observations = []
cancel_protocol = None
back_observation = None
released = set()
acknowledged = set()

def observe_source(tag=None):
    if not a.observe_source:
        return
    tag = tag or 'health-file-' + a.case + '-source'
    existing = next((row for row in source_observations if row['observedAfterNativeAttachment'] == tag), None)
    if existing:
        return existing
    if ("Added attachment named '" + tag + "'") not in (raw / (stem + '.log')).read_text():
        return
    expected_name = {'legacy': 'Lumen-backup-health-legacy-small.json',
                     'encrypted': 'Lumen-backup-health-encrypted-small.lumenbackup',
                     'readable': 'Lumen-readable-health-small.json'}[a.case]
    seed = json.loads((base / 'health-backup-small-main-seed.json').read_text())
    expected = next(row for row in seed['files'] if Path(row['input']).name == expected_name)
    for directory in (container('data') / 'tmp').glob('LumenBackupWork-v1-*'):
        marker = directory / '.lumen-workspace-owner.json'
        file = directory / 'selected-backup'
        try:
            if directory.is_symlink() or not stat.S_ISDIR(directory.lstat().st_mode):
                continue
            if not stat.S_ISREG(marker.lstat().st_mode) or marker.stat().st_size > 1024 or marker.stat().st_mtime < started:
                continue
            owner = json.loads(marker.read_bytes())
            if owner['version'] != 1 or owner['pid'] <= 0 or directory.name != 'LumenBackupWork-v1-' + str(owner['pid']) + '-' + owner['id']:
                continue
            try:
                os.kill(owner['pid'], 0)
            except ProcessLookupError:
                continue
            except PermissionError:
                pass  # EPERM still establishes that this PID exists.
            command = subprocess.check_output(['ps', '-p', str(owner['pid']), '-o', 'comm='], text=True).strip()
            if Path(command) != container('app') / 'Lumen':
                continue
            if not stat.S_ISREG(file.lstat().st_mode) or file.stat().st_size != expected['bytes']:
                continue
            data = file.read_bytes()
            if digest(data) != expected['sha256']:
                continue
            row = {'directory': str(directory), 'owner': owner,
                    'originalFileName': expected_name, 'bytes': len(data), 'sha256': digest(data),
                    'observedAfterNativeAttachment': tag, 'observedAtUnixTime': time.time()}
            source_observations.append(row)
            return row
        except (FileNotFoundError, json.JSONDecodeError, subprocess.CalledProcessError):
            continue

def observe_preparation():
    global cancel_protocol, back_observation
    group = container('group.com.dbakp.lumen')
    checkpoint_file = group / 'Lumen-health-cancel-checkpoint.json'
    try:
        if checkpoint_file.stat().st_mtime < started:
            return
        cancel_protocol = json.loads(checkpoint_file.read_bytes())
    except (FileNotFoundError, json.JSONDecodeError):
        return
    if a.back and back_observation is None and held_observations:
        tag = 'health-file-' + a.case + '-back-import-screen'
        if ("Added attachment named '" + tag + "'") in (raw / (stem + '.log')).read_text():
            first = cancel_protocol['attempts'][0]
            assert first['phase'] == 'cancelled' and first['uiCancelled'] and first['workerControlMatchesUI']
            assert not (group / first['stage']).exists()
            assert originals(group, checkpoint) == before
            old = Path(held_observations[0]['originalSource']['directory'])
            old_source = observe_source(tag) if old.exists() else None
            if old.exists():
                assert old_source and old_source['directory'] == str(old), 'Any retained old source must still have exact bytes and its live app owner'
            back_observation = {'observedAfterNativeAttachment': tag, 'cancelledStageAbsent': True,
                                'originalsUnchanged': True, 'oldSourceDirectory': str(old),
                                'oldSourceExistsAfterBack': old.exists(), 'retainedOldSource': old_source}
    for record in cancel_protocol['attempts']:
        assert re.fullmatch(r'LumenData\.restore-[A-Fa-f0-9-]+', record['stage'])
        if record['phase'] != 'held' or record['nonce'] in released:
            continue
        tag = 'health-file-' + a.case + ('-cancel-held' if record['ordinal'] == 1 else '-retry-held')
        source = observe_source(tag)
        if source is None:
            continue
        assert record['workerControlMatchesUI'] and not record['uiCancelled']
        assert originals(group, checkpoint) == before
        assert (group / record['stage']).is_dir()
        if not any(row['record']['nonce'] == record['nonce'] for row in held_observations):
            held_observations.append({'record': record.copy(), 'originalSource': source,
                                      'originals': before, 'stageExists': True})
        if record['ordinal'] == 1 and record['nonce'] not in acknowledged:
            # Acknowledge only that host reads are complete. This cannot
            # release the worker or replace XCTest's actual Cancel action.
            target = group / 'Lumen-health-cancel-release.json'
            temporary = group / (target.name + '.' + record['nonce'] + '.ack.tmp')
            temporary.write_text(json.dumps({'nonce': record['nonce'], 'acknowledgementOnly': True}))
            temporary.replace(target)
            acknowledged.add(record['nonce'])
        if record['ordinal'] == 2:
            first = cancel_protocol['attempts'][0]
            assert first['phase'] == 'cancelled' and first['uiCancelled'] and first['workerControlMatchesUI']
            assert not (group / first['stage']).exists()
            old = Path(held_observations[0]['originalSource']['directory'])
            if a.back:
                assert back_observation is not None
                assert old != Path(source['directory']), 'Explicit reselect must own a new input workspace'
                assert not old.exists(), 'Replaced old preview workspace must finish cleanup'
                back_observation['newSourceDirectory'] = source['directory']
                back_observation['oldSourceAbsentAfterReselection'] = True
            else:
                assert str(old) == source['directory'], 'Retry must still own the same selected file'
            target = group / 'Lumen-health-cancel-release.json'
            temporary = group / (target.name + '.' + record['nonce'] + '.tmp')
            temporary.write_text(json.dumps({'nonce': record['nonce']}))
            temporary.replace(target)
            released.add(record['nonce'])
with (raw / (stem + '.log')).open('wb') as stream:
    process = subprocess.Popen(command, cwd=repo, stdout=stream, stderr=subprocess.STDOUT)
    awake = subprocess.Popen(['caffeinate', '-d', '-i', '-w', str(process.pid)])
    try:
        while process.poll() is None and time.time() - started < 120:
            try:
                group = container('group.com.dbakp.lumen')
                path = group / 'Lumen-health-backup-baseline.json'
                if path.stat().st_mtime >= started:
                    value = json.loads(path.read_bytes())
                    if value['case'] == a.case:
                        identity()
                        marker = 'chooseReadableExport' if a.case == 'readable' else 'chooseBackup'
                        if ('Tap "' + marker + '" Button') not in (raw / (stem + '.log')).read_text():
                            time.sleep(0.2)
                            continue
                        # SleepStore legitimately persists the same profile
                        # during normal startup, using a different JSON key
                        # order. Observe the actual operation boundary after
                        # Settings opens Files, before a file is selected.
                        profile = (group / 'LumenData/profile.json').read_bytes()
                        fixture_profile = value['originals']['profile.json']
                        assert json.loads(profile) == json.loads(base64.b64decode(fixture_profile, validate=True))
                        value['fixtureProfileBeforeStoreStartup'] = fixture_profile
                        value['originals']['profile.json'] = base64.b64encode(profile).decode()
                        value['observedBoundary'] = 'Actual native Files-picker opening, before file selection'
                        before = originals(group, value)
                        checkpoint = value
                        break
            except (subprocess.CalledProcessError, FileNotFoundError, json.JSONDecodeError):
                pass
            time.sleep(0.2)
        assert checkpoint is not None, 'Fresh native normal-Settings fixture checkpoint missing; inspect same producer'
        deadline = time.monotonic() + (600 if a.back else 300)
        while process.poll() is None:
            assert time.monotonic() < deadline, 'Inspect same native producer before considering another run'
            observe_source()
            observe_preparation()
            time.sleep(0.2)
        code = process.wait()
        observe_source()
    finally:
        (base / (prefix + '-driver-observations.json')).write_text(json.dumps({
            'source': a.source, 'build': a.build, 'checkpoint': checkpoint, 'before': before,
            'producerPID': process.pid, 'producerExitCode': process.poll(),
            'sourceObservations': source_observations,
            'heldObservations': held_observations, 'cancelProtocol': cancel_protocol,
            'backObservation': back_observation,
            'scope': 'DEBUG normal-Root fixture with background Health/Watch sync withheld; real Settings and Files importer path. No physical-device/background-delivery proof.'
        }, indent=2) + '\n')
summary = json.loads(subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary',
                                             '--path', str(result)], text=True))
(raw / (stem + '-summary.json')).write_text(json.dumps(summary, indent=2) + '\n')
(base / (prefix + '-summary.json')).write_text(json.dumps(summary, indent=2) + '\n')
assert code == 0 and summary['passedTests'] == 1 and summary['failedTests'] == 0
assert len(held_observations) == 2 and cancel_protocol and len(cancel_protocol['attempts']) == 2
assert cancel_protocol['attempts'][0]['phase'] == 'cancelled'
assert cancel_protocol['attempts'][1]['phase'] == 'released'
if a.back:
    assert back_observation and back_observation['oldSourceAbsentAfterReselection']
identity()
root = container('group.com.dbakp.lumen') / 'LumenData'
for record in cancel_protocol['attempts']:
    assert not (root.parent / record['stage']).exists(), 'Cancelled/committed stage must finish cleanup'
after = {}
for name, row in before.items():
    data = (root / name).read_bytes()
    after[name] = {'bytes': len(data), 'sha256': digest(data), 'base64': base64.b64encode(data).decode()}
    if name not in ['water.json', 'health-write-intent.json', 'profile.json']:
        assert after[name] == row, name
    if name == 'profile.json':
        assert json.loads(data) == json.loads(base64.b64decode(row['base64']))
water = (root / 'water.json').read_bytes()
decoded_water = json.loads(water)
assert len(decoded_water) == 1 and decoded_water[0]['id'] == 'synthetic-backup-recovery-water' and decoded_water[0]['ml'] == 246
old_intent = json.loads(base64.b64decode(before['health-write-intent.json']['base64']))
new_intent = json.loads((root / 'health-write-intent.json').read_bytes())
assert new_intent['owner'] == old_intent['owner'] and new_intent['lifecycle'] != old_intent['lifecycle'] and new_intent['events'] == []
copies = list((root / '.health-recovery').glob('*/water.json'))
assert any(p.read_bytes() == base64.b64decode(before['water.json']['base64']) for p in copies)
receipts = list((root / '.health-recovery-history').glob('*.json'))
assert len(receipts) == 1
receipt = json.loads(receipts[0].read_bytes())
seed = json.loads((base / 'health-backup-small-main-seed.json').read_text())
expected_name = {'legacy': 'Lumen-backup-health-legacy-small.json', 'encrypted': 'Lumen-backup-health-encrypted-small.lumenbackup', 'readable': 'Lumen-readable-health-small.json'}[a.case]
expected = next(r for r in seed['files'] if Path(r['input']).name == expected_name)
assert receipt['fileSource'] == {'fileName': expected_name, 'format': {'legacy': 'legacyJSONBackup', 'encrypted': 'encryptedBackup', 'readable': 'readableExport'}[a.case], 'byteCount': expected['bytes'], 'sha256': expected['sha256']}
assert receipt['source'] == 'selected-file:' + expected['sha256'] and receipt['domains'] == ['water'] and receipt['omittedPhotoCount'] == 0
assert receipt['recordDigests']['water.json'] == digest(water)
if a.observe_source:
    assert source_observations, 'No live-owner exact selected-file observation at the actual reviewed/error state'
(base / (prefix + '-host-audit.json')).write_text(json.dumps({
    'status': 'passed: held selected-file recovery exits via Back, reopens off, explicitly reselects a new owned file and recovers after host release' if a.back else 'passed: held selected-file recovery cancels promptly, retains choice and exact original source, retries and survives relaunch',
    'source': a.source, 'build': a.build, 'case': a.case, 'before': before, 'after': after,
    'sourceObservations': source_observations,
    'heldObservations': held_observations, 'cancelProtocol': cancel_protocol,
    'backObservation': back_observation,
    'receipt': receipt, 'retainedDamagedWaterPaths': [str(p) for p in copies if p.read_bytes() == base64.b64decode(before['water.json']['base64'])],
    'verifierSHA256': digest(Path(__file__).read_bytes()),
    'scope': ('Actual Back during held preparation, import preview destination, reopened/reselected off choices, distinct new source workspace, old workspace cleanup, second actual hold before host release; ' if a.back else 'Actual visible Cancel within3s, retained choice and same source, second hold before host release; ') + 'Actual normal Settings/Files input, typed246mL review, Not now, success/relaunch and independent original/source/stage/receipt audits. Held import/typed-read runtime cancellation/source replacement, photo/appearance/design/device and full contracts remain required.'
}, indent=2) + '\n')
print('PASS:', a.case, 'actual selected file recovered; independent original/source/receipt audit passed')
