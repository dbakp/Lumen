"""Actual selected reader survives UI owner close until cancelled worker unwinds; independent FD/bytes/lifetime audits."""
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
p.add_argument('--case', choices=['legacy', 'encrypted', 'readable'], required=True)
a = p.parse_args()
assert re.fullmatch(r'[A-Za-z0-9-]+', a.trial)
base = Path(__file__).resolve().parent
repo = base.parents[2]
raw = Path('/tmp/LumenBatch43Checks')
device = 'AF849DEA-DF34-4B0E-9FC1-3E45DCBE8481'
scope = 'selected-record'
photo = False
stem = 'HealthSelectedOwnerUnwind' + a.case.title() + a.trial
prefix = 'health-selected-owner-unwind-' + a.case + '-' + a.trial.lower()
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
observations = []
protocol = None
acknowledged = set()
released = set()
host_failure = None
worker_unwind = None
first_owned = None
retry_owned = None
final_cleanup = None
cancelled_cleanup = None
group = None
root = None
command = ['xcodebuild', '-project', 'Lumen.xcodeproj', '-scheme', 'Lumen', '-configuration', 'Debug',
           '-destination', 'platform=iOS Simulator,id=' + device,
           '-derivedDataPath', '/tmp/LumenBatch37Simulator',
           '-clonedSourcePackagesDirPath', '/tmp/LumenBatch37Packages', '-disableAutomaticPackageResolution',
           '-parallel-testing-enabled', 'NO', '-collect-test-diagnostics', 'never',
           '-only-testing:LumenUITests/LumenSmokeTests/testHealthBackupFileReadOwnerUnwind' + a.case.title(),
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
            log = (raw / (stem + '.log')).read_text()
            first = protocol['attempts'][0] if protocol['attempts'] else None
            owner_tag = 'selected-record-' + a.case + '-owner-closed-worker-held'
            if first and first['phase'] == 'cancelled-worker-held' and worker_unwind is None and ("Added attachment named '" + owner_tag + "'") in log:
                identity()
                assert first['uiCancelled'] and first['reviewOwnerClosed'] is True
                assert first.get('descriptorCloseSucceeded') is None
                assert workspace_source(first) == observations[0]['workspace']
                owned = owned_workspaces(first['pid']); assert owned == first_owned
                descriptor = subprocess.check_output(['lsof', '-nP', '-a', '-p', str(first['pid']), '-d', str(first['descriptor']), '-Fnift'], text=True)
                assert 'tREG' in descriptor and ('i' + str(first['inode'])) in descriptor
                assert any(line.startswith('n') and Path(line[1:]).resolve() == Path(first['file']).resolve() for line in descriptor.splitlines())
                assert snapshot(root) == before
                worker_unwind = {'record':first.copy(), 'ownedWorkspaces':owned, 'actualOpenDescriptor':descriptor, 'treeMatchesBefore':True, 'observedAfterNativeAttachment':owner_tag, 'hostDeletedFiles':False}
                release = group / 'Lumen-health-read-release.json'
                temporary = group / (release.name + '.' + first['nonce'] + '.tmp')
                temporary.write_text(json.dumps({'nonce':first['nonce']})); temporary.replace(release)
            finished_tag = 'selected-record-' + a.case + '-worker-finished-parent'
            if worker_unwind and cancelled_cleanup is None and ("Added attachment named '" + finished_tag + "'") in log:
                until = time.monotonic() + 3
                while time.monotonic() < until:
                    protocol = json.loads(checkpoint.read_bytes())
                    first = protocol['attempts'][0]
                    if first.get('descriptorCloseSucceeded') is True and all(not Path(folder).exists() for folder in first_owned):
                        break
                    time.sleep(0.1)
                assert first.get('descriptorCloseSucceeded') is True
                assert all(not Path(folder).exists() for folder in first_owned)
                scan = no_open_roots(first['pid'], first_owned)
                assert snapshot(root) == before
                cancelled_cleanup = {'actualReaderClosed':True, 'rootsAbsent':True, 'noOpenPathsReadback':scan, 'treeMatchesBefore':True, 'hostDeletedFiles':False, 'observedAfterNativeAttachment':finished_tag, 'timingScope':'3s host observation guard after parent capture; not tap-to-delete latency'}
            for record in protocol['attempts']:
                # Returning from detail can restart the record list's .task.
                # Do not release that late read: final Back must cancel it.
                if record['ordinal'] > 2:
                    continue
                nonce = record['nonce']
                if record['phase'] != 'held' or nonce in acknowledged or nonce in released:
                    continue
                tag = 'selected-record-' + a.case + ('-held' if record['ordinal'] == 1 else '-retry-held')
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
                    first_owned = owned_workspaces(record['pid'])
                else:
                    first = protocol['attempts'][0]
                    assert worker_unwind is not None
                    assert cancelled_cleanup is not None
                    assert first['phase'] == 'cancelled-worker-released' and first['uiCancelled'] and first['descriptorCloseSucceeded']
                    assert first['file'] != record['file']
                    assert all(not Path(folder).exists() for folder in first_owned)
                    no_open_roots(first['pid'], first_owned)
                    assert first['nonce'] != nonce and record['ordinal'] == 2
                    assert observations[0]['workspace']['owner'] != workspace['owner']
                    assert observations[0]['sourceSHA256'] == sha(file.read_bytes())
                    released.add(nonce)
                release = group / 'Lumen-health-read-release.json'
                temporary = group / (release.name + '.' + nonce + '.tmp')
                temporary.write_text(json.dumps(message))
                temporary.replace(release)
            if len(observations) == 2:
                detail_tag = 'selected-record-' + a.case + '-retry-detail'
                if retry_owned is None and ("Added attachment named '" + detail_tag + "'") in log:
                    retry_owned = owned_workspaces(first['pid'])
                    assert len(retry_owned) == (2 if a.case == 'legacy' else 1), retry_owned
                    assert workspace_source(protocol['attempts'][1]) == observations[1]['workspace']
                    assert protocol['attempts'][1]['descriptorCloseSucceeded'] is True
                    assert snapshot(root) == before
                final_tag = 'selected-record-' + a.case + '-final-parent'
                if retry_owned and final_cleanup is None and ("Added attachment named '" + final_tag + "'") in log:
                    until = time.monotonic() + 3
                    while any(Path(folder).exists() for folder in retry_owned) and time.monotonic() < until:
                        time.sleep(0.1)
                    assert all(not Path(folder).exists() for folder in retry_owned), retry_owned
                    protocol = json.loads(checkpoint.read_bytes())
                    assert protocol['attempts'][1]['reviewOwnerClosed'] is True
                    for late in protocol['attempts'][2:]:
                        assert late['scope'] == scope and late['workerControlMatchesUI']
                        assert late['file'] == protocol['attempts'][1]['file'] and late['inode'] == protocol['attempts'][1]['inode']
                        assert late['phase'] == 'cancelled' and late['uiCancelled'] and late['descriptorCloseSucceeded'] is True
                    scan = no_open_roots(first['pid'], list(first_owned) + list(retry_owned))
                    assert not owned_workspaces(first['pid'])
                    final_cleanup = {'rootsAbsent':True,'noOpenPathsReadback':scan,'reviewOwnerClosed':True,'hostDeletedFiles':False,'observedAfterNativeAttachment':final_tag}
            time.sleep(0.2)
        code = process.wait()
    except Exception as error:
        host_failure = traceback.format_exc()
        # Do not abandon the native producer on a failed host precondition.
        # Its finite XCTest wait must finish and retain a readable result bundle.
        code = process.wait(timeout=max(1, deadline - time.monotonic() + 30))
    finally:
        (base / (prefix + '-observations.json')).write_text(json.dumps({
            'source': a.source, 'build': a.build, 'producerPID': process.pid, 'producerExitCode': process.poll(),
            'before': before, 'heldObservations': observations, 'protocol': protocol, 'hostFailure': host_failure, 'workerUnwind':worker_unwind, 'firstOwnedWorkspaces':first_owned, 'retryOwnedWorkspaces':retry_owned, 'cancelledCleanup':cancelled_cleanup, 'finalCleanup':final_cleanup,
            'scope': 'Dedicated synthetic simulator only; no personal phone data. No full original-contract acceptance.'
        }, indent=2) + '\n')
summary = json.loads(subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(bundle)], text=True))
for destination in [raw / (stem + '-summary.json'), base / (prefix + '-summary.json')]:
    destination.write_text(json.dumps(summary, indent=2) + '\n')
assert host_failure is None, host_failure
assert code == 0 and summary['passedTests'] == 1 and summary['failedTests'] == 0
identity()
protocol = json.loads((container('group.com.dbakp.lumen') / 'Lumen-health-read-checkpoint.json').read_bytes())
assert len(observations) == 2 and len(protocol['attempts']) >= 2
assert protocol['attempts'][0]['phase'] == 'cancelled-worker-released' and protocol['attempts'][1]['phase'] == 'released'
assert all(row['workerControlMatchesUI'] and row['descriptorCloseSucceeded'] for row in protocol['attempts'])
assert all(row['phase'] == 'cancelled' and row['uiCancelled'] and row['file'] == protocol['attempts'][1]['file'] for row in protocol['attempts'][2:])
after = snapshot(container('group.com.dbakp.lumen') / 'LumenData')
assert after == before
assert worker_unwind and cancelled_cleanup and retry_owned and final_cleanup
assert not owned_workspaces(protocol['attempts'][0]['pid'])
(base / (prefix + '-host-audit.json')).write_text(json.dumps({
    'status': 'passed: UI closes review while actual cancelled reader retains original/workspaces/open FD; only host-held unwind delay released, then cancellation closes/cleans. Distinct Files source and record control retry246mL/off; final roots gone and saved files exact',
    'source': a.source, 'build': a.build, 'before': before, 'after': after,
    'heldObservations': observations, 'protocol': protocol, 'producerExitCode': code, 'workerUnwind':worker_unwind, 'firstOwnedWorkspaces':first_owned, 'retryOwnedWorkspaces':retry_owned, 'cancelledCleanup':cancelled_cleanup, 'finalCleanup':final_cleanup,
    'verifierSHA256': sha(Path(__file__).read_bytes()),
    'scope': 'One main-normal small ' + a.case + ' actual selected-record verification worker ownership through parent close and cancellation unwind. Artificial unwind delay is not cancellation latency. Photo workers/restore/recovery commits/faults/capacity/appearances/full original contracts remain required.'
}, indent=2) + '\n')
print('PASS: actual ' + scope + ' Back/retry; independent exact bytes and open-descriptor audits')
