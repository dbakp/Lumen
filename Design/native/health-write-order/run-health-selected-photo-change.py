"""Actual selected JPEG same-size metadata mutation/replacement rejects; restored retry and final owner cleanup."""
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
import traceback

p = argparse.ArgumentParser()
p.add_argument('--source', required=True)
p.add_argument('--build', required=True)
p.add_argument('--trial', required=True)
p.add_argument('--mode', choices=['in-place', 'replacement'], required=True)
p.add_argument('--case', choices=['legacy', 'encrypted'], required=True)
a = p.parse_args()
assert re.fullmatch(r'[A-Za-z0-9-]+', a.trial)
base = Path(__file__).resolve().parent
repo = base.parents[2]
raw = Path('/tmp/LumenBatch43Checks')
device = 'AF849DEA-DF34-4B0E-9FC1-3E45DCBE8481'
scope = 'selected-photo'
photo = False
test_mode = 'InPlace' if a.mode == 'in-place' else 'Replacement'
stem = 'HealthSelectedPhotoChange' + a.case.title() + test_mode + a.trial
prefix = 'health-selected-photo-change-' + a.case + '-' + a.mode + '-' + a.trial.lower()
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


def marked_root(file, pid):
    temporary = (container('data') / 'tmp').resolve()
    directory = file.parent
    for _ in range(7):
        if directory.parent.resolve() == temporary:
            break
        directory = directory.parent
    assert directory.parent.resolve() == temporary
    assert directory.is_dir() and not directory.is_symlink()
    marker = directory / '.lumen-workspace-owner.json'
    assert marker.is_file() and not marker.is_symlink() and marker.stat().st_size < 1024
    owner = json.loads(marker.read_bytes())
    assert owner['version'] == 1 and owner['pid'] == pid
    assert directory.name == 'LumenBackupWork-v1-' + str(pid) + '-' + owner['id']
    return directory, owner


def workspace_source(record):
    original = Path(record['reviewSourceFile'])
    assert original.name == 'selected-backup' and original.is_file() and not original.is_symlink()
    workspace, owner = marked_root(original, record['pid'])
    expected_name = 'Lumen-backup-health-photo-' + a.case + ('.lumenbackup' if a.case == 'encrypted' else '.json')
    seed = json.loads((base / 'health-backup-photo-main-seed.json').read_text())
    expected = next(row for row in seed['files'] if Path(row['input']).name == expected_name)
    data = original.read_bytes()
    assert len(data) == expected['bytes'] and sha(data) == expected['sha256']
    provider = Path(expected['seeded'])
    assert provider.is_file() and not provider.is_symlink() and provider.read_bytes() == data
    photo = Path(record['file'])
    assert photo.suffix == '.jpg' and not photo.is_symlink()
    photo_root, photo_owner = marked_root(photo, record['pid'])
    jpeg = (base / 'health-file-photo-oriented-r1-original.jpg').read_bytes()
    assert photo.read_bytes() == jpeg and len(jpeg) == 1023
    return {'directory':str(workspace),'owner':owner,'originalFileName':expected_name,
            'bytes':len(data),'sha256':sha(data),'providerSHA256':sha(provider.read_bytes()),
            'files':snapshot(workspace,current=False), 'photoRoot':str(photo_root),'photoOwner':photo_owner,
            'photoFiles':snapshot(photo_root,current=False),'photoFile':str(photo),'photoBytes':len(jpeg),'photoSHA256':sha(jpeg)}


def owned_workspaces(pid):
    rows = {}
    for folder in (container('data') / 'tmp').glob('LumenBackupWork-v1-' + str(pid) + '-*'):
        assert folder.is_dir() and not folder.is_symlink()
        marker = folder / '.lumen-workspace-owner.json'
        assert marker.is_file() and not marker.is_symlink() and marker.stat().st_size < 1024
        owner = json.loads(marker.read_bytes())
        assert owner['pid'] == pid and owner['version'] == 1
        assert folder.name == 'LumenBackupWork-v1-' + str(pid) + '-' + owner['id']
        dirs = []
        for parent, children, files in os.walk(folder, followlinks=False):
            for name in children: assert not (Path(parent) / name).is_symlink()
            dirs.append(str(Path(parent).relative_to(folder)))
        rows[str(folder)] = {'owner': owner, 'files': snapshot(folder, current=False), 'directories': sorted(dirs)}
    return rows


def no_open_roots(pid, roots):
    result = subprocess.run(['lsof', '-nP', '-a', '-p', str(pid), '-Fn'], text=True, capture_output=True)
    assert result.returncode == 0, result.stderr
    for line in result.stdout.splitlines():
        if line.startswith('n'):
            path = line[1:]
            assert not any(path == root or path.startswith(root + '/') for root in roots), line
    return result.stdout


started = time.time()
before = None
owned_before = None
expected_owned = None
source_before = None
protocol = None
first_observation = None
restoration = None
retry_observation = None
image_observation = None
final_cleanup = None
host_failure = None
root = None
checkpoint = None
original = (base / 'health-file-photo-oriented-r1-original.jpg').read_bytes()
changed = (base / 'health-selected-photo-change-r1-mutated.jpg').read_bytes()
assert len(original) == len(changed) == 1023 and sha(original) != sha(changed)
tag = 'selected-photo-change-' + a.case + '-' + a.mode

def release(group, nonce):
    target = group / 'Lumen-health-read-release.json'
    temporary = group / (target.name + '.' + nonce + '.tmp')
    assert not temporary.exists()
    temporary.write_text(json.dumps({'nonce':nonce})); temporary.replace(target)

command = ['xcodebuild', '-project', 'Lumen.xcodeproj', '-scheme', 'Lumen', '-configuration', 'Debug',
    '-destination', 'platform=iOS Simulator,id=' + device, '-derivedDataPath', '/tmp/LumenBatch37Simulator',
    '-clonedSourcePackagesDirPath', '/tmp/LumenBatch37Packages', '-disableAutomaticPackageResolution',
    '-parallel-testing-enabled', 'NO', '-collect-test-diagnostics', 'never',
    '-only-testing:LumenUITests/LumenSmokeTests/testHealthBackupPhotoChange' + a.case.title() + test_mode,
    '-resultBundlePath', str(bundle), 'test-without-building']
with (raw / (stem + '.log')).open('wb') as out:
    process = subprocess.Popen(command, cwd=repo, stdout=out, stderr=subprocess.STDOUT)
    awake = subprocess.Popen(['caffeinate','-d','-i','-w',str(process.pid)])
    deadline = time.monotonic() + 700
    try:
        while process.poll() is None:
            assert time.monotonic() < deadline, 'Inspect same finite producer, do not restart on observation timeout'
            group = container('group.com.dbakp.lumen'); root = group / 'LumenData'
            checkpoint = group / 'Lumen-health-read-checkpoint.json'
            try:
                if checkpoint.stat().st_mtime < started:
                    time.sleep(0.2); continue
                protocol = json.loads(checkpoint.read_bytes())
            except (FileNotFoundError,json.JSONDecodeError):
                time.sleep(0.2); continue
            assert Path(protocol['root']).resolve() == root.resolve()
            log = (raw / (stem + '.log')).read_text()
            if not protocol['attempts']:
                time.sleep(0.2); continue
            first = protocol['attempts'][0]
            file = Path(first['file'])
            if first_observation is None and ("Added attachment named '" + tag + "-held'") in log:
                identity()
                assert first['ordinal'] == 1 and first['phase'] == 'held' and first['scope'] == scope
                assert first['workerControlMatchesUI'] and first['readBoundary'] == 'photo-payload'
                facts = file.lstat(); assert stat.S_ISREG(facts.st_mode) and not file.is_symlink()
                assert facts.st_ino == first['inode'] and facts.st_size == first['size'] == first['bytesRead'] == 1023
                assert Path(subprocess.check_output(['ps','-p',str(first['pid']),'-o','comm='],text=True).strip()) == container('app') / 'Lumen'
                descriptor = subprocess.check_output(['lsof','-nP','-a','-p',str(first['pid']),'-d',str(first['descriptor']),'-Fnift'],text=True)
                assert 'tREG' in descriptor and ('i'+str(first['inode'])) in descriptor
                assert any(line.startswith('n') and Path(line[1:]).resolve() == file.resolve() for line in descriptor.splitlines())
                before = snapshot(root); assert len(before) == 12
                source_before = workspace_source(first)
                owned_before = owned_workspaces(first['pid']); assert len(owned_before) == (2 if a.case == 'legacy' else 1)
                assert file.read_bytes() == original
                # Only this actual owned JPEG is deliberately changed; every
                # other workspace and saved-data byte remains protected.
                expected_owned = json.loads(json.dumps(owned_before))
                relative = str(file.relative_to(Path(source_before['photoRoot'])))
                assert expected_owned[source_before['photoRoot']]['files'][relative]['sha256'] == sha(original)
                expected_owned[source_before['photoRoot']]['files'][relative] = {'bytes':len(changed),'sha256':sha(changed),'base64':base64.b64encode(changed).decode()}
                if a.mode == 'in-place':
                    with file.open('r+b') as writer:
                        writer.write(changed); writer.truncate(); writer.flush(); os.fsync(writer.fileno())
                    assert file.stat().st_ino == facts.st_ino
                else:
                    temporary = file.with_name(file.name + '.lumen-synthetic-replacement')
                    assert not temporary.exists(); temporary.write_bytes(changed); temporary.replace(file)
                    assert file.stat().st_ino != facts.st_ino
                assert file.stat().st_size == 1023 and file.read_bytes() == changed
                assert owned_workspaces(first['pid']) == expected_owned and snapshot(root) == before
                after_fd = subprocess.check_output(['lsof','-nP','-a','-p',str(first['pid']),'-d',str(first['descriptor']),'-Fnift'],text=True)
                assert 'tREG' in after_fd and ('i'+str(first['inode'])) in after_fd
                first_observation = {'record':first.copy(),'source':source_before,'ownedWorkspaces':owned_before,'actualOpenDescriptor':descriptor,
                    'afterHostMutationDescriptor':after_fd,'changedPathInode':file.stat().st_ino,'originalReaderInode':facts.st_ino,
                    'originalSHA256':sha(original),'changedSHA256':sha(changed),'sameByteCount':True,'hostChangedOnlyJPEG':str(file),
                    'afterExplicitHostMutation':expected_owned,'savedFilesExact':True,'observedAfterNativeAttachment':tag+'-held'}
                release(group,first['nonce'])
            if first_observation and restoration is None and ("Added attachment named '" + tag + "-rejected'") in log:
                assert first['phase'] == 'released' and first['descriptorCloseSucceeded'] is True
                assert owned_workspaces(first['pid']) == expected_owned and snapshot(root) == before
                assert Path(first['reviewSourceFile']).read_bytes() == base64.b64decode(source_before['files']['selected-backup']['base64'])
                if a.mode == 'in-place':
                    with file.open('r+b') as writer:
                        writer.write(original); writer.truncate(); writer.flush(); os.fsync(writer.fileno())
                else:
                    temporary = file.with_name(file.name + '.lumen-synthetic-restoration')
                    assert not temporary.exists(); temporary.write_bytes(original); temporary.replace(file)
                assert owned_workspaces(first['pid']) == owned_before and snapshot(root) == before
                restoration = {'observedAfterNativeAttachment':tag+'-rejected','firstReaderClosed':True,'restoredOriginalSHA256':sha(file.read_bytes()),
                    'restoredPathInode':file.stat().st_ino,'allWorkspaceBytesRestored':True,'savedFilesExact':True}
            if restoration and retry_observation is None and len(protocol['attempts']) == 2 and ("Added attachment named '" + tag + "-retry-held'") in log:
                second = protocol['attempts'][1]; identity()
                assert second['ordinal'] == 2 and second['phase'] == 'held' and second['scope'] == scope and second['workerControlMatchesUI']
                assert second['readBoundary'] == 'photo-payload' and second['nonce'] != first['nonce']
                assert second['file'] == first['file'] and second['reviewSourceFile'] == first['reviewSourceFile']
                facts = file.lstat(); assert facts.st_ino == second['inode'] and facts.st_size == second['size'] == second['bytesRead'] == 1023
                assert workspace_source(second) == source_before and owned_workspaces(first['pid']) == owned_before and snapshot(root) == before
                descriptor = subprocess.check_output(['lsof','-nP','-a','-p',str(second['pid']),'-d',str(second['descriptor']),'-Fnift'],text=True)
                assert 'tREG' in descriptor and ('i'+str(second['inode'])) in descriptor
                assert any(line.startswith('n') and Path(line[1:]).resolve() == file.resolve() for line in descriptor.splitlines())
                retry_observation = {'record':second.copy(),'actualOpenDescriptor':descriptor,'restoredJPEGBytesExact':True,'sameSelectedOriginal':True,
                    'observedAfterNativeAttachment':tag+'-retry-held'}
                release(group,second['nonce'])
            if retry_observation and image_observation is None and ("Added attachment named '" + tag + "-retry-image'") in log:
                assert protocol['attempts'][1]['descriptorCloseSucceeded'] is True
                assert owned_workspaces(first['pid']) == owned_before and snapshot(root) == before
                image_observation = {'ownedWorkspaces':owned_before,'restoredJPEGExact':True,'savedFilesExact':True,'observedAfterNativeAttachment':tag+'-retry-image'}
            if image_observation and final_cleanup is None and ("Added attachment named '" + tag + "-final-parent'") in log:
                until = time.monotonic() + 3
                while any(Path(folder).exists() for folder in owned_before) and time.monotonic() < until: time.sleep(0.1)
                assert all(not Path(folder).exists() for folder in owned_before), owned_before
                protocol = json.loads(checkpoint.read_bytes())
                assert all(r.get('reviewOwnerClosed') is True and r['descriptorCloseSucceeded'] is True for r in protocol['attempts'])
                scan = no_open_roots(first['pid'],owned_before); assert not owned_workspaces(first['pid']) and snapshot(root) == before
                final_cleanup = {'allRootsAbsent':True,'liveNoOpenPaths':scan,'savedFilesExact':True,'hostDeletedWorkspace':False,
                    'observedAfterNativeAttachment':tag+'-final-parent','timingScope':'3s host observation guard after parent capture, not tap-delete latency'}
            time.sleep(0.2)
        code = process.wait()
    except Exception:
        host_failure = traceback.format_exc()
        code = process.wait(timeout=max(1,deadline-time.monotonic()+30))
    finally:
        (base/(prefix+'-observations.json')).write_text(json.dumps({'source':a.source,'build':a.build,'mode':a.mode,
            'producerPID':process.pid,'producerExitCode':process.poll(),'before':before,'ownedBefore':owned_before,
            'first':first_observation,'restoration':restoration,'retry':retry_observation,'image':image_observation,'finalCleanup':final_cleanup,
            'protocol':protocol,'hostFailure':host_failure},indent=2)+'\n')
summary = json.loads(subprocess.check_output(['xcrun','xcresulttool','get','test-results','summary','--path',str(bundle)],text=True))
for destination in [raw/(stem+'-summary.json'),base/(prefix+'-summary.json')]: destination.write_text(json.dumps(summary,indent=2)+'\n')
assert host_failure is None,host_failure
assert code == 0 and summary['passedTests'] == 1 and summary['failedTests'] == 0
identity(); protocol = json.loads(checkpoint.read_bytes()); after = snapshot(root)
assert after == before and len(protocol['attempts']) == 2 and all(r['phase']=='released' and r['descriptorCloseSucceeded'] and r['workerControlMatchesUI'] for r in protocol['attempts'])
assert first_observation and restoration and retry_observation and image_observation and final_cleanup
(base/(prefix+'-host-audit.json')).write_text(json.dumps({'status':'passed: actual selected JPEG same-size '+a.mode+' change rejects/no image/reader closes; original restored only after captured rejection, fresh photo control displays original; final roots absent/no open paths and saved files exact',
    'source':a.source,'build':a.build,'mode':a.mode,'producerExitCode':code,'before':before,'after':after,'first':first_observation,
    'restoration':restoration,'retry':retry_observation,'image':image_observation,'finalCleanup':final_cleanup,'protocol':protocol,
    'verifierSHA256':sha(Path(__file__).read_bytes()),'scope':'Main-normal one known JPEG, same-length EXIF6->8metadata mutation. No compressed-pixel substitution/other photo matrix/commit/fault/appearance/capacity/full contract acceptance. Pixels separately verified on original screenshot.'},indent=2)+'\n')
print('PASS: selected JPEG '+a.case+'/'+a.mode+' rejection, restored retry, final cleanup and saved bytes')
