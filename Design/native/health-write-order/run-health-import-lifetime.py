"""Legacy/readable payload Cancel, final owner cleanup and same-parent fresh selection."""
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
p.add_argument('--case', choices=['legacy', 'readable'], required=True)
p.add_argument('--cancel', action='store_true')
a = p.parse_args()
assert a.cancel, 'Lifetime trial starts with visible Cancel'
assert re.fullmatch(r'[A-Za-z0-9-]+', a.trial)
base = Path(__file__).resolve().parent
repo = base.parents[2]
raw = Path('/tmp/LumenBatch43Checks')
device = 'AF849DEA-DF34-4B0E-9FC1-3E45DCBE8481'
scope = 'selected-import'
photo = False
action = 'cancel' if a.cancel else 'back'
tag_prefix = 'original-lifetime-' + a.case
stem = 'HealthImportLifetime' + a.case.title() + a.trial
prefix = 'health-import-lifetime-' + a.case + '-' + a.trial.lower()
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


started = time.time()
before = None
observations = []
protocol = None
root = None
checkpoint = None
success_observations = {}
final_observations = {}
final_seen = {}
final_wait_observations = []
acknowledged = set()
released = set()
host_failure = None
cleanup_wait_observations = []
stop_observation = None
stop_seen = None
command = ['xcodebuild', '-project', 'Lumen.xcodeproj', '-scheme', 'Lumen', '-configuration', 'Debug',
           '-destination', 'platform=iOS Simulator,id=' + device,
           '-derivedDataPath', '/tmp/LumenBatch37Simulator',
           '-clonedSourcePackagesDirPath', '/tmp/LumenBatch37Packages', '-disableAutomaticPackageResolution',
           '-parallel-testing-enabled', 'NO', '-collect-test-diagnostics', 'never',
           '-only-testing:LumenUITests/LumenSmokeTests/testHealthOriginalImportPayloadLifetime' + a.case.title(),
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
            stop_tag = tag_prefix + ('-cancelled-ready' if a.cancel else '-back-closed')
            log = (raw / (stem + '.log')).read_text()
            if observations and stop_observation is None and ("Added attachment named '" + stop_tag + "'") in log:
                if stop_seen is None:
                    stop_seen = time.monotonic()
                first = protocol['attempts'][0]
                assert first['phase'] == 'cancelled' and first['uiCancelled'] and first['descriptorCloseSucceeded']
                old = Path(observations[0]['workspace']['directory'])
                if old.exists():
                    current = workspace_source(first)
                    closed_scan = subprocess.run(['lsof', '-nP', '-a', '-p', str(first['pid']), '-Fn'], text=True, capture_output=True)
                    assert closed_scan.returncode == 0
                    old_open = [line[1:] for line in closed_scan.stdout.splitlines() if line.startswith('n') and line[1:].startswith(str(old) + '/')]
                    cleanup_wait_observations.append({'observedAtUnix': time.time(), 'secondsAfterReadyAttachmentSeen': time.monotonic() - stop_seen,
                        'nativeReadyCaptureSeen': True, 'readerReportedClosed': first['descriptorCloseSucceeded'], 'uiCancelled': first['uiCancelled'],
                        'originalWorkspaceStillPresent': str(old), 'originalWorkspaceExact': current == observations[0]['workspace'],
                        'savedFilesExact': snapshot(root) == before, 'actualAppDescriptorScanSucceeded': True, 'oldWorkspaceOpenPaths': old_open})
                    assert time.monotonic() - stop_seen < 3, 'Unused original selection must clean up within3s while Cancelled-ready parent stays idle'
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
                tag = tag_prefix + ({1:'-held',2:'-retry-held',3:'-reselected-held'}[record['ordinal']])
                if ("Added attachment named '" + tag + "'") not in (raw / (stem + '.log')).read_text():
                    continue
                identity()
                assert record['scope'] == scope and record['workerControlMatchesUI'] and record['readBoundary'] == 'original-payload'
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
                    assert first['nonce'] != nonce and record['ordinal'] in [2,3]
                    assert first['pid'] == record['pid']
                    assert observations[0]['workspace']['directory'] != workspace['directory']
                    assert observations[0]['workspace']['owner']['id'] != workspace['owner']['id']
                    assert observations[0]['workspace']['sha256'] == workspace['sha256']
                    if record['ordinal'] == 3:
                        assert 2 in final_observations
                        previous = protocol['attempts'][1]
                        assert previous.get('reviewOwnerClosed') is True and previous['descriptorCloseSucceeded']
                        assert previous['file'] != record['file']
                        assert observations[1]['workspace']['owner']['id'] != workspace['owner']['id']
                        assert all(not Path(f).exists() for f in success_observations[2]['workspaces'])
                    released.add(nonce)
                release = group / 'Lumen-health-read-release.json'
                temporary = group / (release.name + '.' + nonce + '.tmp')
                temporary.write_text(json.dumps(message))
                temporary.replace(release)
            log = (raw / (stem + '.log')).read_text()
            for ordinal, detail_tag, parent_tag in [(2,tag_prefix+'-retry-detail',tag_prefix+'-first-parent'), (3,tag_prefix+'-reselected-detail',tag_prefix+'-final-parent')]:
                matches = [r for r in protocol['attempts'] if r['ordinal'] == ordinal]
                if not matches: continue
                healthy = matches[0]
                if ordinal not in success_observations and ("Added attachment named '"+detail_tag+"'") in log:
                    assert healthy['phase'] == 'released' and healthy['descriptorCloseSucceeded']
                    source_workspace = workspace_source(healthy)
                    assert source_workspace == observations[ordinal-1]['workspace']
                    owned = owned_workspaces(healthy['pid'])
                    assert len(owned) == (2 if a.case == 'legacy' else 1), owned
                    assert source_workspace['directory'] in owned
                    for directory, inventory in owned.items():
                        assert inventory['directories'] == ['.']
                        if directory != source_workspace['directory']: assert set(inventory['files']) == {'.lumen-workspace-owner.json'}
                    assert snapshot(root) == before
                    success_observations[ordinal] = {'nativeAttachment':detail_tag,'observedAtUnix':time.time(),'record':healthy.copy(),'workspaces':owned,'savedFilesExact':True}
                if ordinal not in final_observations and ("Added attachment named '"+parent_tag+"'") in log:
                    assert ordinal in success_observations
                    if ordinal not in final_seen: final_seen[ordinal] = time.monotonic()
                    paths = list(success_observations[ordinal]['workspaces'])
                    present_paths = [f for f in paths if Path(f).exists()]
                    assert snapshot(root) == before
                    if present_paths:
                        final_wait_observations.append({'ordinal':ordinal,'observedAtUnix':time.time(),'secondsAfterParentAttachmentSeen':time.monotonic()-final_seen[ordinal],'present':present_paths,'reviewOwnerClosed':healthy.get('reviewOwnerClosed')})
                        assert time.monotonic()-final_seen[ordinal] < 3, 'Successful original/photo workspace must clean within3s at actual parent'
                    else:
                        scan = subprocess.run(['lsof','-nP','-a','-p',str(healthy['pid']),'-Fn'],text=True,capture_output=True)
                        assert scan.returncode == 0
                        leftovers = [line[1:] for line in scan.stdout.splitlines() if line.startswith('n') and any(line[1:]==f or line[1:].startswith(f+'/') for f in paths)]
                        assert not leftovers and healthy.get('reviewOwnerClosed') is True
                        final_observations[ordinal] = {'nativeAttachment':parent_tag,'observedAtUnix':time.time(),'workspacesAbsent':paths,'actualProcessDescriptorScanSucceeded':True,'openPaths':leftovers,'reviewOwnerClosed':True,'savedFilesExact':True,'hostDeletedFiles':False}
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
            'cleanupWaitObservations': cleanup_wait_observations, 'successObservations':success_observations, 'finalObservations':final_observations, 'finalWaitObservations':final_wait_observations,
            'protocolAtProducerTerminal': json.loads(checkpoint.read_bytes()) if checkpoint is not None and checkpoint.exists() else None,
            'afterAtProducerTerminal': snapshot(root) if root is not None and root.exists() else None,
            'scope': 'Dedicated synthetic simulator only; actual Cancelled-ready idle4s checks late progress/preview and host original cleanup. No personal phone data/full original acceptance.'
        }, indent=2) + '\n')
summary = json.loads(subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(bundle)], text=True))
for destination in [raw / (stem + '-summary.json'), base / (prefix + '-summary.json')]:
    destination.write_text(json.dumps(summary, indent=2) + '\n')
assert host_failure is None, host_failure
assert code == 0 and summary['passedTests'] == 1 and summary['failedTests'] == 0
identity()
protocol = json.loads((container('group.com.dbakp.lumen') / 'Lumen-health-read-checkpoint.json').read_bytes())
assert len(protocol['attempts']) == len(observations) == 3
assert protocol['attempts'][0]['phase'] == 'cancelled' and all(r['phase']=='released' for r in protocol['attempts'][1:])
assert all(row['workerControlMatchesUI'] and row['descriptorCloseSucceeded'] for row in protocol['attempts'])
after = snapshot(container('group.com.dbakp.lumen') / 'LumenData')
assert after == before
assert set(success_observations)==set(final_observations)=={2,3}
assert not owned_workspaces(protocol['attempts'][-1]['pid'])
assert stop_observation is not None and not Path(observations[0]['workspace']['directory']).exists()
(base / (prefix + '-host-audit.json')).write_text(json.dumps({
    'status': 'passed: native payload Cancel, retry and two successful original/photo workspace lifetimes; same-parent fresh selection resets previously enabled choice to off,246mL twice and saved bytes exact',
    'source': a.source, 'build': a.build, 'before': before, 'after': after,
    'heldObservations': observations, 'protocol': protocol, 'stopObservation': stop_observation, 'producerExitCode': code,
    'verifierSHA256': sha(Path(__file__).read_bytes()), 'cleanupWaitObservations': cleanup_wait_observations, 'successObservations':success_observations, 'finalObservations':final_observations, 'finalWaitObservations':final_wait_observations,
    'scope': 'One main-normal small '+a.case+' payload Cancel and two successful review lifetimes; all current-process marked original/photo roots inventoried and gone at final parent without host deletion. No photo payload/active-worker/ordinary merge/recovery commit/fault/appearance/full original acceptance.'
}, indent=2) + '\n')
print('PASS: actual ' + scope + ' ' + action + '/retry; independent exact bytes and open-descriptor audits')
