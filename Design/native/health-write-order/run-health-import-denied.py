"""Real denied-open after provider copy, failed-owner cleanup and healthy retry."""
import argparse
import base64
import errno
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import time
import traceback

p = argparse.ArgumentParser()
p.add_argument('--source', required=True)
p.add_argument('--build', required=True)
p.add_argument('--case', choices=['legacy', 'encrypted', 'readable'], required=True)
p.add_argument('--trial', required=True)
a = p.parse_args()
assert re.fullmatch(r'[A-Za-z0-9-]+', a.trial)
base = Path(__file__).resolve().parent
repo = base.parents[2]
raw = Path('/tmp/LumenBatch43Checks')
device = 'AF849DEA-DF34-4B0E-9FC1-3E45DCBE8481'
stem = 'HealthImportDenied' + a.case.title() + a.trial
prefix = 'health-import-denied-' + a.case + '-' + a.trial.lower()
tag = 'original-denied-' + a.case
result = raw / (stem + '.xcresult')
assert not result.exists()
load = lambda name: json.loads((base / name).read_text())
source = load(a.source)
build = load(a.build)
digest = lambda data: hashlib.sha256(data).hexdigest()

def container(kind):
    return Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container',
        device, 'com.dbakp.lumen', kind], text=True).strip())

def identity():
    assert build['source'] == a.source
    for name, row in {**source['files'], **source['fixtureInputs']}.items():
        assert digest((repo / name).read_bytes()) == row['sha256'], name
    assert digest((container('app') / 'Lumen').read_bytes()) == build['sha256']

def snapshot(root):
    assert root.is_dir() and not root.is_symlink()
    rows = {}
    total = 0
    for parent, dirs, files in os.walk(root, followlinks=False):
        assert all(not (Path(parent) / name).is_symlink() for name in dirs)
        for name in files:
            f = Path(parent) / name
            assert stat.S_ISREG(f.lstat().st_mode) and f.stat().st_size <= 256 * 1024
            data = f.read_bytes()
            total += len(data)
            assert total < 2 * 1024 * 1024
            rows[str(f.relative_to(root))] = {'bytes': len(data),
                'sha256': digest(data), 'base64': base64.b64encode(data).decode()}
    return rows

def owned(pid):
    rows = {}
    for folder in (container('data') / 'tmp').glob('LumenBackupWork-v1-' + str(pid) + '-*'):
        assert folder.is_dir() and not folder.is_symlink()
        marker = folder / '.lumen-workspace-owner.json'
        assert stat.S_ISREG(marker.lstat().st_mode) and marker.stat().st_size < 1024
        owner = json.loads(marker.read_bytes())
        assert owner['pid'] == pid and owner['version'] == 1
        assert folder.name == 'LumenBackupWork-v1-' + str(pid) + '-' + owner['id']
        rows[str(folder)] = {'owner': owner, 'files': snapshot(folder)}
    return rows

def no_open(pid, roots):
    scan = subprocess.run(['lsof', '-nP', '-a', '-p', str(pid), '-Fn'], capture_output=True, text=True)
    assert scan.returncode == 0, scan.stderr
    for line in scan.stdout.splitlines():
        if line.startswith('n'):
            assert not any(line[1:] == root or line[1:].startswith(root + '/') for root in roots), line
    return scan.stdout

healthy_name = {'legacy': 'Lumen-backup-health-legacy-small.json',
    'encrypted': 'Lumen-backup-health-encrypted-small.lumenbackup',
    'readable': 'Lumen-readable-health-small.json'}[a.case]
healthy = next(r for r in load('health-backup-small-main-seed.json')['files']
               if Path(r['input']).name == healthy_name)
providers = [healthy, healthy]
def verify_provider(row):
    f = Path(row['seeded'])
    assert stat.S_ISREG(f.lstat().st_mode)
    data = f.read_bytes()
    assert len(data) == row['bytes'] and digest(data) == row['sha256']
    return data

def descriptor(pid, number, file, inode):
    scan = subprocess.check_output(['lsof', '-nP', '-a', '-p', str(pid), '-d', str(number), '-Fnift'], text=True)
    assert 'tREG' in scan and ('i' + str(inode)) in scan
    assert any(line.startswith('n') and Path(line[1:]).resolve() == file.resolve() for line in scan.splitlines())
    return scan

def held_source(record):
    f = Path(record['file']); target = Path(record['copyTarget'])
    facts = f.lstat(); output = target.lstat()
    assert f.name == healthy_name and target.name == 'selected-backup'
    assert stat.S_ISREG(facts.st_mode) and stat.S_ISREG(output.st_mode)
    assert output.st_nlink == 1 and (output.st_dev, output.st_ino) != (facts.st_dev, facts.st_ino)
    assert facts.st_ino == record['inode'] and facts.st_size == record['size']
    data = verify_provider(healthy); assert f.read_bytes() == target.read_bytes() == data
    assert record['readBoundary'] == 'original-copy' and record['scope'] == 'selected-import'
    assert record['workerControlMatchesUI'] and not record['uiCancelled']
    assert record['bytesRead'] == facts.st_size and 0 < facts.st_size < 64 * 1024
    assert stat.S_IMODE(output.st_mode) == 0o600
    assert target.parent.parent.resolve() == (container('data') / 'tmp').resolve()
    assert Path(subprocess.check_output(['ps', '-p', str(record['pid']), '-o', 'comm='], text=True).strip()) == container('app') / 'Lumen'
    uid = int(subprocess.check_output(['ps', '-p', str(record['pid']), '-o', 'uid='], text=True))
    assert uid == os.getuid() != 0
    roots = owned(record['pid']); assert len(roots) == 1 and str(target.parent) in roots
    return {'record': record.copy(), 'provider': healthy, 'ownedRoots': roots,
        'sourceBytes': base64.b64encode(data).decode(), 'targetInode': output.st_ino,
        'targetBytes': output.st_size, 'targetMode': stat.S_IMODE(output.st_mode), 'uid': uid,
        'inputDescriptorReadback': descriptor(record['pid'], record['descriptor'], f, facts.st_ino),
        'outputDescriptorReadback': descriptor(record['pid'], record['outputDescriptor'], target, output.st_ino)}

def deny_open(frame, record):
    target = Path(record['copyTarget'])
    # Restrict the mutation to this actual worker's marked, disposable copy.
    # The source/provider, directory and currently open descriptors stay intact.
    assert str(target.parent) in frame['ownedRoots'] and target.name == 'selected-backup'
    before_stat = target.lstat(); assert stat.S_ISREG(before_stat.st_mode)
    assert before_stat.st_ino == frame['targetInode'] and target.read_bytes() == verify_provider(healthy)
    os.chmod(target, 0, follow_symlinks=False)
    after_stat = target.lstat()
    assert stat.S_ISREG(after_stat.st_mode) and stat.S_IMODE(after_stat.st_mode) == 0
    assert after_stat.st_ino == before_stat.st_ino and after_stat.st_size == before_stat.st_size
    try:
        unexpected = os.open(target, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except PermissionError as failure:
        denied_errno = failure.errno; assert denied_errno == errno.EACCES
    else:
        os.close(unexpected); raise AssertionError('Actual OS read-open must fail EACCES')
    assert Path(record['file']).read_bytes() == verify_provider(healthy)
    return {'target': str(target), 'inode': after_stat.st_ino, 'bytes': after_stat.st_size,
        'modeBefore': 0o600, 'modeAfter': 0, 'actualHostOpenErrno': denied_errno,
        'actualAppAndHostUID': frame['uid'], 'appliedAfterNativeObservedCapture': True,
        'providerUnchanged': True, 'hostDeletedWorkspace': False,
        'inputDescriptorStillOpen': descriptor(record['pid'], record['descriptor'], Path(record['file']), record['inode']),
        'outputDescriptorStillOpen': descriptor(record['pid'], record['outputDescriptor'], target, after_stat.st_ino)}

started = time.time()
before = previous = protocol = error_cleanup = success = final_cleanup = denial = host_failure = None
observations = []
acknowledged = set()
released = set()
command = ['xcodebuild', '-project', 'Lumen.xcodeproj', '-scheme', 'Lumen', '-configuration', 'Debug',
    '-destination', 'platform=iOS Simulator,id=' + device, '-derivedDataPath', '/tmp/LumenBatch37Simulator',
    '-clonedSourcePackagesDirPath', '/tmp/LumenBatch37Packages', '-disableAutomaticPackageResolution',
    '-parallel-testing-enabled', 'NO', '-collect-test-diagnostics', 'never',
    '-only-testing:LumenUITests/LumenSmokeTests/testHealthOriginalImportCopyDenied' + a.case.title(),
    '-resultBundlePath', str(result), 'test-without-building']
with (raw / (stem + '.log')).open('wb') as stream:
    process = subprocess.Popen(command, cwd=repo, stdout=stream, stderr=subprocess.STDOUT)
    awake = subprocess.Popen(['caffeinate', '-d', '-i', '-w', str(process.pid)])
    deadline = time.monotonic() + 800
    try:
        while process.poll() is None:
            assert time.monotonic() < deadline, 'Inspect same finite producer; observation timeout is not terminal'
            group = container('group.com.dbakp.lumen')
            checkpoint = group / 'Lumen-health-read-checkpoint.json'
            try:
                if checkpoint.stat().st_mtime < started:
                    time.sleep(0.2); continue
                protocol = json.loads(checkpoint.read_bytes())
            except (FileNotFoundError, json.JSONDecodeError):
                time.sleep(0.2); continue
            root = group / 'LumenData'
            log = (raw / (stem + '.log')).read_text()
            for record in protocol['attempts']:
                ordinal = record['ordinal']; nonce = record['nonce']
                assert ordinal in [1, 2]
                held_tag = tag + ('-held' if ordinal == 1 else '-retry-held')
                if record['phase'] != 'held' or nonce in released or ("Added attachment named '" + held_tag + "'") not in log:
                    continue
                identity()
                frame = held_source(record)
                tree = snapshot(root)
                if before is None:
                    baseline = json.loads((group / 'Lumen-health-backup-baseline.json').read_bytes())
                    assert baseline['case'] == a.case and len(tree) == 12
                    for name, encoded in baseline['originals'].items():
                        actual = base64.b64decode(tree[name]['base64']); expected = base64.b64decode(encoded)
                        assert json.loads(actual) == json.loads(expected) if name == 'profile.json' else actual == expected, name
                    before = tree; previous = snapshot(root.with_suffix('.previous')); assert len(previous) == 10
                assert tree == before and snapshot(root.with_suffix('.previous')) == previous
                if nonce not in acknowledged:
                    observations.append(frame); acknowledged.add(nonce)
                    if ordinal == 2:
                        assert error_cleanup is not None
                        first = protocol['attempts'][0]
                        assert first['phase'] == 'released' and first['descriptorCloseSucceeded'] and not first['uiCancelled']
                        assert first['copyTarget'] != record['copyTarget'] and first['pid'] == record['pid']
                        assert all(not Path(folder).exists() for folder in observations[0]['ownedRoots'])
                    message = {'nonce': nonce, 'acknowledgementOnly': True} if ordinal == 1 else {'nonce': nonce}
                else:
                    if ordinal != 1 or ("Added attachment named '" + tag + "-observed'") not in log:
                        continue
                    assert frame == observations[0]
                    assert denial is None
                    denial = deny_open(frame, record)
                    assert snapshot(root) == before and snapshot(root.with_suffix('.previous')) == previous
                    message = {'nonce': nonce}
                target = group / 'Lumen-health-read-release.json'
                temp = target.with_name(target.name + '.' + nonce + '.tmp')
                assert not temp.exists(); temp.write_text(json.dumps(message)); temp.replace(target)
                if not message.get('acknowledgementOnly'): released.add(nonce)
            if observations and error_cleanup is None and ("Added attachment named '" + tag + "-ready'") in log:
                first = protocol['attempts'][0]; roots = observations[0]['ownedRoots']; until = time.monotonic() + 3
                assert first['phase'] == 'released' and first['descriptorCloseSucceeded'] and first['outputDescriptorCloseSucceeded'] and not first['uiCancelled']
                assert denial and denial['actualHostOpenErrno'] == errno.EACCES
                while any(Path(folder).exists() for folder in roots) and time.monotonic() < until: time.sleep(0.1)
                assert all(not Path(folder).exists() for folder in roots), roots
                assert not owned(first['pid'])
                assert snapshot(root) == before and snapshot(root.with_suffix('.previous')) == previous
                error_cleanup = {'rootsAbsent': True, 'liveNoOpenPaths': no_open(first['pid'], roots),
                    'saved12AndPrevious10Exact': True, 'observedAfterNativeAttachment': tag + '-ready',
                    'hostDeletedWorkspace': False, 'timingScope': '3s host guard after ready capture, not error-to-delete latency'}
            if len(observations) == 2 and success is None and ("Added attachment named '" + tag + "-retry-off'") in log:
                second = protocol['attempts'][1]
                assert second['phase'] == 'released' and second['descriptorCloseSucceeded'] and second['outputDescriptorCloseSucceeded'] and not second['uiCancelled']
                roots = owned(second['pid']); assert len(roots) == (2 if a.case == 'legacy' else 1)
                assert str(Path(second['copyTarget']).parent) in roots
                assert snapshot(root) == before and snapshot(root.with_suffix('.previous')) == previous
                assert Path(second['copyTarget']).read_bytes() == verify_provider(healthy)
                success = {'ownedRoots': roots, 'saved12AndPrevious10Exact': True,
                    'observedAfterNativeAttachment': tag + '-retry-off'}
            if success and final_cleanup is None and ("Added attachment named '" + tag + "-final-parent'") in log:
                roots = success['ownedRoots']; pid = protocol['attempts'][1]['pid']; until = time.monotonic() + 3
                while any(Path(folder).exists() for folder in roots) and time.monotonic() < until: time.sleep(0.1)
                assert all(not Path(folder).exists() for folder in roots), roots
                assert not owned(pid)
                assert snapshot(root) == before and snapshot(root.with_suffix('.previous')) == previous
                final_cleanup = {'rootsAbsent': True, 'liveNoOpenPaths': no_open(pid, roots),
                    'saved12AndPrevious10Exact': True, 'hostDeletedWorkspace': False,
                    'observedAfterNativeAttachment': tag + '-final-parent'}
            time.sleep(0.2)
        code = process.wait()
    except Exception:
        host_failure = traceback.format_exc()
        code = process.wait(timeout=max(1, deadline - time.monotonic() + 30))
    finally:
        (base / (prefix + '-observations.json')).write_text(json.dumps({
            'source': a.source, 'build': a.build, 'producerPID': process.pid, 'producerExitCode': process.poll(),
            'before': before, 'previousBefore': previous, 'heldObservations': observations, 'protocol': protocol,
            'errorCleanup': error_cleanup, 'successfulReview': success, 'finalCleanup': final_cleanup,
            'permissionFault': denial, 'hostFailure': host_failure}, indent=2) + '\n')
summary = json.loads(subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(result)], text=True))
for f in [raw / (stem + '-summary.json'), base / (prefix + '-summary.json')]: f.write_text(json.dumps(summary, indent=2) + '\n')
assert host_failure is None, host_failure
assert code == 0 and summary['passedTests'] == 1 and summary['failedTests'] == 0
assert len(observations) == 2 and len(released) == 2 and denial and error_cleanup and success and final_cleanup
identity()
after = snapshot(root); previous_after = snapshot(root.with_suffix('.previous'))
assert after == before and previous_after == previous
for row in providers: verify_provider(row)
(base / (prefix + '-host-audit.json')).write_text(json.dumps({
    'status': 'passed: actual denied-open permission error and cleanup, fresh healthy off246mL review and final cleanup',
    'source': a.source, 'build': a.build, 'case': a.case, 'producerExitCode': code,
    'before': before, 'after': after, 'previousBefore': previous, 'previousAfter': previous_after,
    'heldObservations': observations, 'protocol': protocol, 'errorCleanup': error_cleanup,
    'successfulReview': success, 'finalCleanup': final_cleanup, 'permissionFault': denial,
    'verifierSHA256': digest(Path(__file__).read_bytes()),
    'scope': 'Actual OS EACCES13 denied-open after tiny completed provider copy. Host changes only verified disposable copied target permissions600to000 after both descriptors/source bytes are observed; actual app/host share nonroot UID. Native permission error, both copy descriptors close without cancellation, failed workspace gone/no open paths. Original provider and saved12/prior10 unchanged, fresh healthy copy/review/final cleanup. Not EIO inside active read/midwrite/multichunk/capacity/all fault/appearance/full original gates.'}, indent=2) + '\n')
print('PASS:', a.case, 'actual OS denied-open/cleanup, fresh off246mL review and final cleanup; saved12/prior10/provider exact')
