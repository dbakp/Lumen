"""Actual encrypted read/unlock cancellation, preview ownership and final last-owner cleanup."""
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
p.add_argument('--case', choices=['encrypted'], default='encrypted')
p.add_argument('--cancel', action='store_true')
p.add_argument('--boundary', choices=['record', 'unlock'], required=True)
p.add_argument('--wrong-password', action='store_true')
a = p.parse_args()

assert re.fullmatch(r'[A-Za-z0-9-]+', a.trial)
base = Path(__file__).resolve().parent
repo = base.parents[2]
raw = Path('/tmp/LumenBatch43Checks')
device = 'AF849DEA-DF34-4B0E-9FC1-3E45DCBE8481'
scope = 'selected-import'
photo = False
action = 'cancel' if a.cancel else 'back'
assert not a.wrong_password or (a.boundary == 'unlock' and a.cancel)
tag_prefix = ('original-unlock-' if a.boundary == 'unlock' else 'original-decrypt-') + ('wrong-' if a.wrong_password else '') + action
stem = 'HealthEncryptedLifetime' + a.boundary.title() + ('Wrong' if a.wrong_password else '') + action.title() + a.trial
prefix = 'health-encrypted-lifetime-' + a.boundary + '-' + ('wrong-' if a.wrong_password else '') + action + '-' + a.trial.lower()
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
    expected_name = 'Lumen-encrypted-read-baseline.lumenbackup'
    expected = json.loads((base / 'health-encrypted-native-read-r1-seed.json').read_text())
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
root = None
checkpoint = None
acknowledged = set()
released = set()
host_failure = None
cleanup_wait_observations = []
stop_observation = None
stop_seen = None
success_observation = None
final_observation = None
final_seen = None
final_wait_observations = []
command = ['xcodebuild', '-project', 'Lumen.xcodeproj', '-scheme', 'Lumen', '-configuration', 'Debug',
           '-destination', 'platform=iOS Simulator,id=' + device,
           '-derivedDataPath', '/tmp/LumenBatch37Simulator',
           '-clonedSourcePackagesDirPath', '/tmp/LumenBatch37Packages', '-disableAutomaticPackageResolution',
           '-parallel-testing-enabled', 'NO', '-collect-test-diagnostics', 'never',
           '-only-testing:LumenUITests/LumenSmokeTests/testHealthOriginalImport' + ('Unlock' if a.boundary == 'unlock' else 'Decrypt') + ('Wrong' if a.wrong_password else '') + action.title() + 'Encrypted',
           '-resultBundlePath', str(bundle), 'test-without-building']
with (raw / (stem + '.log')).open('wb') as out:
    process = subprocess.Popen(command, cwd=repo, stdout=out, stderr=subprocess.STDOUT)
    awake = subprocess.Popen(['caffeinate', '-d', '-i', '-w', str(process.pid)])
    deadline = time.monotonic() + 700
    try:
        while process.poll() is None:
            assert time.monotonic() < deadline, 'Inspect same producer; do not restart on observation timeout'
            group = container('group.com.dbakp.lumen')
            root = group / 'LumenData'
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
            stop_tag = tag_prefix + '-stopped'
            log = (raw / (stem + '.log')).read_text()
            if observations and stop_observation is None and ("Added attachment named '" + stop_tag + "'") in log:
                if stop_seen is None:
                    stop_seen = time.monotonic()
                first = protocol['attempts'][0]
                assert first['phase'] == 'cancelled' and first['uiCancelled'] and first['descriptorCloseSucceeded']
                if a.boundary == 'record':
                    assert first['decryptedCloseAttempts'] == 1 and isinstance(first['decryptedCloseSucceeded'], bool)
                else:
                    assert first['passwordSetStarted'] is False and first['decryptedStreamCreated'] is False
                    assert first.get('decryptedCloseAttempts') is None and first.get('extractedDirectory') is None
                old = Path(observations[0]['workspace']['directory'])
                extraction = Path(first['extractedDirectory']) if first.get('extractedDirectory') else None
                assert extraction is None or not extraction.exists(), 'Failed encrypted preview directory must be removed before ready/Back'
                assert snapshot(root) == before
                scan = subprocess.run(['lsof', '-nP', '-a', '-p', str(first['pid']), '-Fn'], text=True, capture_output=True)
                assert scan.returncode == 0
                opened = [line[1:] for line in scan.stdout.splitlines() if line.startswith('n')]
                leftovers = [name for name in opened if name == str(old) or name.startswith(str(old) + '/') or (extraction is not None and (name == str(extraction) or name.startswith(str(extraction) + '/')))]
                assert not leftovers, 'No open source or extraction paths may remain after cancellation'
                if a.cancel:
                    assert workspace_source(first) == observations[0]['workspace'], 'Same-file password retry must retain exact owned original'
                elif old.exists():
                    cleanup_wait_observations.append({'observedAtUnix': time.time(), 'secondsAfterStopAttachmentSeen': time.monotonic() - stop_seen, 'workspace': str(old)})
                    assert time.monotonic() - stop_seen < 3, 'Back must release old original after last reader'
                    time.sleep(0.2)
                    continue
                stop_observation = {'observedAfterNativeAttachment': stop_tag, 'observedAtUnix': time.time(),
                    'cancelledReaderClosed': True, 'decryptedCloseAttempts': first.get('decryptedCloseAttempts'),
                    'decryptedCloseSucceeded': first.get('decryptedCloseSucceeded'), 'decryptedCloseError': first.get('decryptedCloseError'),
                    'extractedDirectoryAbsent': str(extraction) if extraction is not None else None, 'passwordSetStarted': first.get('passwordSetStarted'), 'decryptedStreamCreated': first.get('decryptedStreamCreated'), 'originalRetainedForPasswordRetry': a.cancel,
                    'originalWorkspaceAbsent': None if a.cancel else str(old), 'allProtectedBytesExact': True,
                    'openPathsUnderOriginalOrExtraction': leftovers, 'actualProcessDescriptorScanSucceeded': True}
            for record in protocol['attempts']:
                nonce = record['nonce']
                if record['phase'] != 'held' or nonce in acknowledged or nonce in released:
                    continue
                tag = tag_prefix + ('-held' if record['ordinal'] == 2 else '-retry-held')
                if ("Added attachment named '" + tag + "'") not in (raw / (stem + '.log')).read_text():
                    continue
                identity()
                assert record['scope'] == scope and record['workerControlMatchesUI'] and record['readBoundary'] == ('encrypted-record' if a.boundary == 'record' else 'encrypted-unlock')
                file = Path(record['file'])
                assert not file.is_symlink()
                workspace = workspace_source(record)
                facts = file.lstat()
                assert stat.S_ISREG(facts.st_mode) and facts.st_ino == record['inode'] and facts.st_size == record['size']
                assert facts.st_size == 20480
                if a.boundary == 'record':
                    assert record['bytesRead'] == record['recordOffset'] == 65536
                    assert record['encryptedRecordKind'] == 'personalContext' and record['recordLength'] > 200 * 1024
                    extracted = Path(record['extractedDirectory'])
                    assert extracted.parent.resolve() == file.parent.resolve()
                    assert extracted.name.startswith('LumenBackupPreview-') and extracted.is_dir() and not extracted.is_symlink()
                    extracted_files = snapshot(extracted, current=False)
                    extracted_directories = sorted(str(Path(parent).relative_to(extracted)) for parent, _, _ in os.walk(extracted, followlinks=False))
                    assert extracted_directories == ['.'] and extracted_files == {}
                else:
                    assert record['bytesRead'] == 0 and record['passwordSetStarted'] is False and record['decryptedStreamCreated'] is False
                    assert record.get('extractedDirectory') is None
                    assert sorted(f.name for f in file.parent.iterdir()) == ['.lumen-workspace-owner.json', 'selected-backup']
                    extracted_directories, extracted_files = [], {}
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
                                     'treeMatchesBefore': True, 'workspace': workspace, 'extractedDirectories': extracted_directories, 'extractedFiles': extracted_files, 'observedAfterNativeAttachment': tag})
                message = {'nonce': nonce}
                if record['ordinal'] == 2:
                    message['acknowledgementOnly'] = True
                    acknowledged.add(nonce)
                else:
                    first = protocol['attempts'][0]
                    assert first['phase'] == 'cancelled' and first['uiCancelled'] and first['descriptorCloseSucceeded']
                    assert stop_observation is not None
                    assert first['nonce'] != nonce and record['ordinal'] == (3 if a.cancel else 4)
                    assert first['pid'] == record['pid']
                    if a.boundary == 'record':
                        assert first['extractedDirectory'] != record['extractedDirectory']
                        assert not Path(first['extractedDirectory']).exists()
                    if a.cancel:
                        assert first['file'] == record['file'] and first['inode'] == record['inode']
                        assert workspace == observations[0]['workspace']
                    else:
                        assert first['file'] != record['file']
                        assert not Path(observations[0]['workspace']['directory']).exists()
                        assert observations[0]['workspace']['owner']['id'] != workspace['owner']['id']
                    assert observations[0]['workspace']['sha256'] == workspace['sha256']
                    released.add(nonce)
                release = group / 'Lumen-health-read-release.json'
                temporary = group / (release.name + '.' + nonce + '.tmp')
                temporary.write_text(json.dumps(message))
                temporary.replace(release)
            log = (raw / (stem + '.log')).read_text()
            detail_tag, final_tag = tag_prefix + '-retry-detail', tag_prefix + '-final-parent'
            if success_observation is None and ("Added attachment named '" + detail_tag + "'") in log:
                healthy = protocol['attempts'][-1]
                assert healthy['phase'] == 'released' and healthy['decryptedCloseAttempts'] == 1 and healthy['decryptedCloseSucceeded'] is True and healthy['descriptorCloseSucceeded'] is True
                assert healthy['passwordSetStarted'] is True and healthy['decryptedStreamCreated'] is True
                extracted = Path(healthy['extractedDirectory'])
                assert extracted.is_dir() and not extracted.is_symlink() and extracted.parent == Path(healthy['file']).parent
                assert snapshot(extracted, current=False) == {}
                owned = workspace_source(healthy)
                assert owned == observations[-1]['workspace'] and snapshot(root) == before
                success_observation = {'observedAtUnix': time.time(), 'observedAfterNativeAttachment': detail_tag,
                    'actualRecord': healthy.copy(), 'workspace': owned, 'extractedDirectoryPresent': str(extracted),
                    'extractedFiles': {}, 'extractedDirectories': sorted(str(Path(parent).relative_to(extracted)) for parent, _, _ in os.walk(extracted, followlinks=False)),
                    'savedFilesExact': True}
            if final_observation is None and ("Added attachment named '" + final_tag + "'") in log:
                assert success_observation is not None
                if final_seen is None: final_seen = time.monotonic()
                healthy = protocol['attempts'][-1]
                old, extracted = Path(healthy['file']).parent, Path(healthy['extractedDirectory'])
                assert snapshot(root) == before
                if old.exists() or extracted.exists():
                    final_wait_observations.append({'observedAtUnix': time.time(), 'secondsAfterFinalParentAttachmentSeen': time.monotonic() - final_seen,
                        'originalWorkspacePresent': old.exists(), 'extractedDirectoryPresent': extracted.exists(), 'reviewOwnerClosed': healthy.get('reviewOwnerClosed')})
                    assert time.monotonic() - final_seen < 3, 'Last successful preview owner must release original/extraction within3s at final parent'
                else:
                    scan = subprocess.run(['lsof', '-nP', '-a', '-p', str(healthy['pid']), '-Fn'], text=True, capture_output=True)
                    assert scan.returncode == 0
                    opened = [line[1:] for line in scan.stdout.splitlines() if line.startswith('n')]
                    leftovers = [name for name in opened if name == str(old) or name.startswith(str(old) + '/')]
                    assert not leftovers
                    final_observation = {'observedAtUnix': time.time(), 'observedAfterNativeAttachment': final_tag,
                        'originalWorkspaceAbsent': str(old), 'extractedDirectoryAbsent': str(extracted),
                        'openPathsUnderOriginalOrExtraction': leftovers, 'actualProcessDescriptorScanSucceeded': True,
                        'savedFilesExact': True, 'hostDeletedFiles': False, 'reviewOwnerClosed': healthy.get('reviewOwnerClosed')}
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
            'cleanupWaitObservations': cleanup_wait_observations, 'successObservation': success_observation, 'finalObservation': final_observation, 'finalWaitObservations': final_wait_observations,
            'protocolAtProducerTerminal': json.loads(checkpoint.read_bytes()) if checkpoint is not None and checkpoint.exists() else None,
            'afterAtProducerTerminal': snapshot(root) if root is not None and root.exists() else None,
            'scope': 'Dedicated synthetic simulator only; actual ' + a.boundary + ' cancellation and final successful preview/original lifetime. Cancel retains same owned source for retry; final parent must release it. No atomic password/key derivation preemption/full acceptance.'
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
assert stop_observation is not None and success_observation is not None and final_observation is not None
assert protocol['attempts'][1]['decryptedCloseAttempts'] == 1 and protocol['attempts'][1]['decryptedCloseSucceeded'] is True
assert all(not Path(row['file']).parent.exists() for row in protocol['attempts'])
assert not Path(protocol['attempts'][1]['extractedDirectory']).exists()
assert protocol['attempts'][1].get('reviewOwnerClosed') is True
(base / (prefix + '-host-audit.json')).write_text(json.dumps({
    'status': 'passed: native ' + a.boundary + ' ' + action + '/password retry and final successful preview last-owner cleanup; live source/rawfd/control/stream/extraction audit, native137mL and saved bytes exact',
    'source': a.source, 'build': a.build, 'before': before, 'after': after,
    'heldObservations': observations, 'protocol': protocol, 'stopObservation': stop_observation, 'producerExitCode': code,
    'verifierSHA256': sha(Path(__file__).read_bytes()), 'cleanupWaitObservations': cleanup_wait_observations, 'successObservation': success_observation, 'finalObservation': final_observation, 'finalWaitObservations': final_wait_observations,
    'scope': 'One main-normal encrypted ' + a.boundary + ' ' + action + '/password retry/final parent. Unlock hold precedes synchronous password setter and is not preemption inside key derivation/attributes. Source rawfd/control observed; successful original/extraction owned through actual detail then released at final parent. Atomic/in-flight/capacity/source/selection/photo/appearance and all full original contracts remain required.'
}, indent=2) + '\n')
print('PASS: actual ' + scope + ' ' + action + '/retry; independent exact bytes and open-descriptor audits')
