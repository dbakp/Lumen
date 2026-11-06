"""Actual original-import Back/reselection; real source-reader/cleanup/new-workspace audit."""
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
p.add_argument('--case', choices=['legacy', 'encrypted', 'readable'], required=True)
p.add_argument('--cancel', action='store_true')
a = p.parse_args()
assert re.fullmatch(r'[A-Za-z0-9-]+', a.trial)
base = Path(__file__).resolve().parent
repo = base.parents[2]
raw = Path('/tmp/LumenBatch43Checks')
device = 'AF849DEA-DF34-4B0E-9FC1-3E45DCBE8481'
scope = 'selected-import'
photo = False
action = 'cancel' if a.cancel else 'back'
tag_prefix = 'original-import-' + ('cancel-' if a.cancel else '') + a.case
stem = 'HealthOriginalImportRead' + action.title() + a.case.title() + a.trial
prefix = 'health-original-import-read-' + action + '-' + a.case + '-' + a.trial.lower()
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


def snapshot(root, current=True):
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
    if current:
        assert (root / 'water.json').read_bytes() == b'{"syntheticUnavailableWater":'
        baseline = json.loads((root.parent / 'Lumen-health-backup-baseline.json').read_bytes())
        assert baseline['case'] == a.case
        for name, encoded in baseline['originals'].items():
            assert (root / name).read_bytes() == base64.b64decode(encoded)
    return rows


def workspace_source(record):
    file = Path(record['file'])
    workspace = file.parent
    assert file.name == 'selected-backup'
    assert workspace.parent.resolve() == (container('data') / 'tmp').resolve()
    marker = workspace / '.lumen-workspace-owner.json'
    assert marker.is_file() and not marker.is_symlink() and marker.stat().st_size < 1024
    owner = json.loads(marker.read_bytes())
    assert owner['version'] == 1 and owner['pid'] == record['pid']
    assert workspace.name == 'LumenBackupWork-v1-' + str(owner['pid']) + '-' + owner['id']
    expected_name = {'legacy': 'Lumen-backup-health-legacy-small.json',
                     'encrypted': 'Lumen-backup-health-encrypted-small.lumenbackup',
                     'readable': 'Lumen-readable-health-small.json'}[a.case]
    seed = json.loads((base / 'health-backup-small-main-seed.json').read_text())
    expected = next(row for row in seed['files'] if Path(row['input']).name == expected_name)
    data = file.read_bytes()
    assert len(data) == expected['bytes'] and sha(data) == expected['sha256']
    provider = Path(expected['seeded'])
    assert provider.is_file() and not provider.is_symlink() and provider.read_bytes() == data
    return {'directory': str(workspace), 'owner': owner, 'originalFileName': expected_name,
            'bytes': len(data), 'sha256': sha(data), 'providerSHA256': sha(provider.read_bytes()),
            'files': snapshot(workspace, current=False)}


started = time.time()
before = None
observations = []
protocol = None
acknowledged = set()
released = set()
host_failure = None
stop_observation = None
stop_seen = None
command = ['xcodebuild', '-project', 'Lumen.xcodeproj', '-scheme', 'Lumen', '-configuration', 'Debug',
           '-destination', 'platform=iOS Simulator,id=' + device,
           '-derivedDataPath', '/tmp/LumenBatch37Simulator',
           '-clonedSourcePackagesDirPath', '/tmp/LumenBatch37Packages', '-disableAutomaticPackageResolution',
           '-parallel-testing-enabled', 'NO', '-collect-test-diagnostics', 'never',
           '-only-testing:LumenUITests/LumenSmokeTests/testHealthOriginalImport' + action.title() + a.case.title(),
           '-resultBundlePath', str(bundle), 'test-without-building']
with (raw / (stem + '.log')).open('wb') as out:
    process = subprocess.Popen(command, cwd=repo, stdout=out, stderr=subprocess.STDOUT)
    awake = subprocess.Popen(['caffeinate', '-d', '-i', '-w', str(process.pid)])
    deadline = time.monotonic() + 700
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
            stop_tag = tag_prefix + ('-cancelled-ready' if a.cancel else '-back-closed')
            log = (raw / (stem + '.log')).read_text()
            if observations and stop_observation is None and ("Added attachment named '" + stop_tag + "'") in log:
                if stop_seen is None:
                    stop_seen = time.monotonic()
                first = protocol['attempts'][0]
                assert first['phase'] == 'cancelled' and first['uiCancelled'] and first['descriptorCloseSucceeded']
                old = Path(observations[0]['workspace']['directory'])
                if old.exists():
                    assert time.monotonic() - stop_seen < 3, 'Abandoned original selection must clean up promptly'
                else:
                    assert snapshot(root) == before
                    closed_readback = subprocess.run(['lsof', '-nP', '-a', '-p', str(first['pid']), '-Fn'], text=True, capture_output=True)
                    assert closed_readback.returncode == 0
                    abandoned_open_paths = [line[1:] for line in closed_readback.stdout.splitlines()
                                            if line.startswith('n') and line[1:].startswith(str(old) + '/')]
                    assert not abandoned_open_paths, 'No original-import descriptor may retain abandoned workspace paths'
                    stop_observation = {'observedAfterNativeAttachment': stop_tag, 'observedAtUnix': time.time(),
                                        'cancelledReaderClosed': True, 'originalWorkspaceAbsent': str(old),
                                        'allProtectedBytesExact': True, 'oldWorkspaceOpenPaths': abandoned_open_paths, 'actualProcessDescriptorScanSucceeded': True}
            for record in protocol['attempts']:
                nonce = record['nonce']
                if record['phase'] != 'held' or nonce in acknowledged or nonce in released:
                    continue
                tag = tag_prefix + ('-held' if record['ordinal'] == 1 else '-retry-held')
                if ("Added attachment named '" + tag + "'") not in (raw / (stem + '.log')).read_text():
                    continue
                identity()
                assert record['scope'] == scope and record['workerControlMatchesUI'] and record['readBoundary'] == 'selected-source'
                file = Path(record['file'])
                assert not file.is_symlink()
                workspace = workspace_source(record)
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
                observations.append({'record': record.copy(), 'sourceBytes': base64.b64encode(file.read_bytes()).decode(),
                                     'sourceSHA256': sha(file.read_bytes()), 'openDescriptorReadback': lsof,
                                     'treeMatchesBefore': True, 'workspace': workspace, 'observedAfterNativeAttachment': tag})
                message = {'nonce': nonce}
                if record['ordinal'] == 1:
                    message['acknowledgementOnly'] = True
                    acknowledged.add(nonce)
                else:
                    first = protocol['attempts'][0]
                    assert first['phase'] == 'cancelled' and first['uiCancelled'] and first['descriptorCloseSucceeded']
                    assert stop_observation is not None
                    assert first['file'] != record['file']
                    assert not Path(observations[0]['workspace']['directory']).exists()
                    assert first['nonce'] != nonce and record['ordinal'] == 2
                    assert first['pid'] == record['pid']
                    assert observations[0]['workspace']['directory'] != workspace['directory']
                    assert observations[0]['workspace']['owner']['id'] != workspace['owner']['id']
                    assert observations[0]['workspace']['sha256'] == workspace['sha256']
                    released.add(nonce)
                release = group / 'Lumen-health-read-release.json'
                temporary = group / (release.name + '.' + nonce + '.tmp')
                temporary.write_text(json.dumps(message))
                temporary.replace(release)
            time.sleep(0.2)
        code = process.wait()
    except Exception as error:
        host_failure = repr(error)
        # Do not abandon the native producer on a failed host precondition.
        # Its finite XCTest wait must finish and retain a readable result bundle.
        code = process.wait(timeout=max(1, deadline - time.monotonic() + 30))
    finally:
        (base / (prefix + '-observations.json')).write_text(json.dumps({
            'source': a.source, 'build': a.build, 'producerPID': process.pid, 'producerExitCode': process.poll(),
            'before': before, 'heldObservations': observations, 'protocol': protocol, 'hostFailure': host_failure, 'stopObservation': stop_observation,
            'scope': 'Dedicated synthetic simulator only; no personal phone data. No full original-contract acceptance.'
        }, indent=2) + '\n')
summary = json.loads(subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(bundle)], text=True))
for destination in [raw / (stem + '-summary.json'), base / (prefix + '-summary.json')]:
    destination.write_text(json.dumps(summary, indent=2) + '\n')
assert host_failure is None, host_failure
assert code == 0 and summary['passedTests'] == 1 and summary['failedTests'] == 0
identity()
protocol = json.loads((container('group.com.dbakp.lumen') / 'Lumen-health-read-checkpoint.json').read_bytes())
assert len(protocol['attempts']) == len(observations) == 2
assert protocol['attempts'][0]['phase'] == 'cancelled' and protocol['attempts'][1]['phase'] == 'released'
assert all(row['workerControlMatchesUI'] and row['descriptorCloseSucceeded'] for row in protocol['attempts'])
after = snapshot(container('group.com.dbakp.lumen') / 'LumenData')
assert after == before
assert workspace_source(protocol['attempts'][1]) == observations[1]['workspace']
assert stop_observation is not None and not Path(observations[0]['workspace']['directory']).exists()
(base / (prefix + '-host-audit.json')).write_text(json.dumps({
    'status': 'passed: native ' + action + ' cancels original-import source read and closes descriptor; abandoned original workspace removed; real Files reselection creates distinct original workspace and native246mL detail; saved bytes unchanged',
    'source': a.source, 'build': a.build, 'before': before, 'after': after,
    'heldObservations': observations, 'protocol': protocol, 'stopObservation': stop_observation, 'producerExitCode': code,
    'verifierSHA256': sha(Path(__file__).read_bytes()),
    'scope': 'One main-normal ' + a.case + ' original-import source-identity read ' + action + '/reselection. Other copy/decode/unlock windows, changed bytes, selected-photo/full workspace lifetime/appearance and all original contracts remain required.'
}, indent=2) + '\n')
print('PASS: actual ' + scope + ' ' + action + '/retry; independent exact bytes and open-descriptor audits')
