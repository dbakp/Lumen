"""Actual normal Settings/Files baseline while current Water cannot be opened."""
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
a = p.parse_args()
assert re.fullmatch(r'[A-Za-z0-9-]+', a.trial)
base = Path(__file__).resolve().parent
repo = base.parents[2]
raw = Path('/tmp/LumenBatch43Checks')
device = 'AF849DEA-DF34-4B0E-9FC1-3E45DCBE8481'
stem = 'HealthBackupBaseline' + a.case.title() + a.trial
prefix = 'health-backup-baseline-' + a.case + '-' + a.trial.lower()
result = raw / (stem + '.xcresult')
assert not result.exists()
source = json.loads((base / a.source).read_text())
build = json.loads((base / a.build).read_text())
digest = lambda data: hashlib.sha256(data).hexdigest()

def container(kind):
    return Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', device,
                                        'com.dbakp.lumen', kind], text=True).strip())

def identity():
    for name, row in source['files'].items():
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
           '-only-testing:LumenUITests/LumenSmokeTests/testHealthBackupUnavailable' + a.case.title() + 'Baseline',
           '-resultBundlePath', str(result), 'test-without-building']
started = time.time()
checkpoint = None
before = None
source_observations = []

def observe_source():
    if not a.observe_source or source_observations:
        return
    tag = 'health-backup-baseline-readable-valid-review' if a.case == 'readable' else 'health-backup-baseline-' + a.case + '-current-unavailable'
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
            if not any(row['directory'] == str(directory) for row in source_observations):
                source_observations.append({'directory': str(directory), 'owner': owner,
                    'originalFileName': expected_name, 'bytes': len(data), 'sha256': digest(data),
                    'observedAfterNativeAttachment': tag, 'observedAtUnixTime': time.time()})
        except (FileNotFoundError, json.JSONDecodeError, subprocess.CalledProcessError):
            continue
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
        deadline = time.monotonic() + 300
        while process.poll() is None:
            assert time.monotonic() < deadline, 'Inspect same native producer before considering another run'
            observe_source()
            time.sleep(0.2)
        code = process.wait()
        observe_source()
    finally:
        (base / (prefix + '-driver-observations.json')).write_text(json.dumps({
            'source': a.source, 'build': a.build, 'checkpoint': checkpoint, 'before': before,
            'producerPID': process.pid, 'producerExitCode': process.poll(),
            'sourceObservations': source_observations,
            'scope': 'DEBUG normal-Root fixture with background Health/Watch sync withheld; real Settings and Files importer path. No physical-device/background-delivery proof.'
        }, indent=2) + '\n')
summary = json.loads(subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary',
                                             '--path', str(result)], text=True))
(raw / (stem + '-summary.json')).write_text(json.dumps(summary, indent=2) + '\n')
(base / (prefix + '-summary.json')).write_text(json.dumps(summary, indent=2) + '\n')
assert code == 0 and summary['passedTests'] == 1 and summary['failedTests'] == 0
identity()
after = originals(container('group.com.dbakp.lumen'), checkpoint)
assert before == after
if a.observe_source:
    assert source_observations, 'No live-owner exact selected-file observation at the actual reviewed/error state'
(base / (prefix + '-host-audit.json')).write_text(json.dumps({
    'status': 'baseline defect reproduced: valid selected input rejected because current Water is unavailable',
    'source': a.source, 'build': a.build, 'case': a.case, 'before': before, 'after': after,
    'sourceObservations': source_observations,
    'verifierSHA256': digest(Path(__file__).read_bytes()),
    'scope': 'Native test asserts the specific saved-health-data-unavailable error, not a wrong password or invalid archive. Exact original seven canonical files and absent receipt independently checked. Product recovery is NOT accepted; private source ownership during review needs separate held-work tests.'
}, indent=2) + '\n')
print('REPRODUCED:', a.case, 'actual Files input rejected; seven original files unchanged')
