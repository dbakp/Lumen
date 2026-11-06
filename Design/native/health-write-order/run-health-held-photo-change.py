"""Independent actual held JPEG source-change audit on the dedicated simulator."""
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
p.add_argument('--mode', choices=['in-place', 'replacement'], required=True)
p.add_argument('--payload', action='store_true')
a = p.parse_args()
assert re.fullmatch(r'[A-Za-z0-9-]+', a.trial)
base = Path(__file__).resolve().parent
repo = base.parents[2]
raw = Path('/tmp/LumenBatch43Checks')
device = 'AF849DEA-DF34-4B0E-9FC1-3E45DCBE8481'
case = 'Mutation' if a.mode == 'in-place' else 'Replacement'
stem = 'HealthHeldPhoto' + ('Payload' if a.payload else '') + case + a.trial
prefix = 'health-held-photo-' + ('payload-' if a.payload else '') + a.mode + '-' + a.trial.lower()
bundle = raw / (stem + '.xcresult')
assert not bundle.exists()
sha = lambda data: hashlib.sha256(data).hexdigest()
source = json.loads((base / a.source).read_text())
build = json.loads((base / a.build).read_text())
changed = (base / 'health-backup-photo-changed-r1.jpg').read_bytes()
assert changed.startswith(b'\xff\xd8') and 0 < len(changed) < 64 * 1024


def container(kind):
    return Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', device,
                                        'com.dbakp.lumen', kind], text=True).strip())


def identity():
    assert build['source'] == a.source
    for name, row in {**source['files'], **source.get('fixtureInputs', {})}.items():
        assert sha((repo / name).read_bytes()) == row['sha256'], name
    assert sha((container('app') / 'Lumen').read_bytes()) == build['sha256']


def snapshot(root):
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
    assert (root / 'water.json').read_bytes() == b'{"syntheticUnavailableWater":'
    return rows


started = time.time()
before = None
expected = None
observations = []
protocol = None
restoration = None
retry_observations = []
command = ['xcodebuild', '-project', 'Lumen.xcodeproj', '-scheme', 'Lumen', '-configuration', 'Debug',
           '-destination', 'platform=iOS Simulator,id=' + device,
           '-derivedDataPath', '/tmp/LumenBatch37Simulator',
           '-clonedSourcePackagesDirPath', '/tmp/LumenBatch37Packages', '-disableAutomaticPackageResolution',
           '-parallel-testing-enabled', 'NO', '-collect-test-diagnostics', 'never',
           '-only-testing:LumenUITests/LumenSmokeTests/testHealthRecoveryReadRetainedPhoto' + ('Payload' if a.payload else '') + case,
           '-resultBundlePath', str(bundle), 'test-without-building']
with (raw / (stem + '.log')).open('wb') as out:
    process = subprocess.Popen(command, cwd=repo, stdout=out, stderr=subprocess.STDOUT)
    awake = subprocess.Popen(['caffeinate', '-d', '-i', '-w', str(process.pid)])
    deadline = time.monotonic() + 400
    try:
        while process.poll() is None:
            assert time.monotonic() < deadline, 'Inspect same producer; observation expiry is not terminal'
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
            if a.payload and observations:
                log = (raw / (stem + '.log')).read_text()
                first = protocol['attempts'][0]
                rejected_tag = 'retained-photo-payload-' + a.mode + '-rejected'
                if restoration is None and ("Added attachment named '" + rejected_tag + "'") in log:
                    assert first['phase'] == 'released' and first['descriptorCloseSucceeded']
                    assert snapshot(root) == expected
                    if a.mode == 'in-place':
                        with file.open('r+b') as writer:
                            writer.write(original); writer.truncate(); writer.flush(); os.fsync(writer.fileno())
                    else:
                        temporary = file.with_name(file.name + '.synthetic-restoration')
                        assert not temporary.exists()
                        temporary.write_bytes(original); temporary.replace(file)
                    assert snapshot(root) == before
                    restoration = {'afterNativeRejectedAttachment': rejected_tag, 'firstDescriptorCloseSucceeded': True,
                                   'restoredSourceSHA256': sha(file.read_bytes()), 'restoredPathInode': file.stat().st_ino,
                                   'allProtectedBytesRestored': True}
                retry_tag = 'retained-photo-payload-' + a.mode + '-restored-retry-held'
                if restoration is not None and len(protocol['attempts']) == 2 and not retry_observations and ("Added attachment named '" + retry_tag + "'") in log:
                    second = protocol['attempts'][1]
                    identity()
                    assert second['ordinal'] == 2 and second['phase'] == 'held'
                    assert second['readBoundary'] == 'photo-payload' and second['workerControlMatchesUI']
                    assert second['nonce'] != first['nonce'] and second['file'] == first['file']
                    facts = file.stat()
                    assert facts.st_ino == second['inode'] and facts.st_size == second['size']
                    assert file.read_bytes() == original and snapshot(root) == before
                    actual = subprocess.check_output(['lsof', '-nP', '-a', '-p', str(second['pid']), '-d', str(second['descriptor']), '-Fnift'], text=True)
                    assert 'tREG' in actual and ('i' + str(second['inode'])) in actual
                    assert any(line.startswith('n') and Path(line[1:]).resolve() == file.resolve() for line in actual.splitlines())
                    retry_observations.append({'record': second, 'openDescriptorReadback': actual,
                                               'sourceSHA256': sha(file.read_bytes()), 'allProtectedBytesExactBefore': True,
                                               'observedAfterNativeAttachment': retry_tag})
                    release = group / 'Lumen-health-read-release.json'
                    temporary = group / (release.name + '.' + second['nonce'] + '.tmp')
                    temporary.write_text(json.dumps({'nonce': second['nonce']})); temporary.replace(release)
                time.sleep(0.2)
                continue
            if not protocol['attempts'] or observations:
                time.sleep(0.2)
                continue
            record = protocol['attempts'][0]
            tag = 'retained-photo-' + ('payload-' if a.payload else '') + a.mode + '-held'
            if ("Added attachment named '" + tag + "'") not in (raw / (stem + '.log')).read_text():
                time.sleep(0.2)
                continue
            identity()
            assert record['ordinal'] == 1 and record['phase'] == 'held'
            assert record['scope'] == 'retained-photo' and record['workerControlMatchesUI']
            assert record['readBoundary'] == ('photo-payload' if a.payload else 'verification')
            file = Path(record['file'])
            assert not file.is_symlink() and file.resolve().is_relative_to((root / '.health-recovery').resolve())
            facts = file.lstat()
            assert stat.S_ISREG(facts.st_mode) and facts.st_ino == record['inode'] and facts.st_size == record['size']
            assert file.name == 'synthetic-review-photo.jpg'
            assert 0 < record['bytesRead'] <= min(64 * 1024, facts.st_size)
            assert Path(subprocess.check_output(['ps', '-p', str(record['pid']), '-o', 'comm='], text=True).strip()) == container('app') / 'Lumen'
            lsof = subprocess.check_output(['lsof', '-nP', '-a', '-p', str(record['pid']), '-d', str(record['descriptor']), '-Fnift'], text=True)
            assert 'tREG' in lsof and ('i' + str(record['inode'])) in lsof
            assert any(line.startswith('n') and Path(line[1:]).resolve() == file.resolve() for line in lsof.splitlines())
            before = snapshot(root)
            original = file.read_bytes()
            assert original != changed and original.startswith(b'\xff\xd8')
            current_photo = root / 'photos' / file.name
            assert current_photo.read_bytes() == original
            relative = str(file.relative_to(root))
            # In-place writes intentionally reach every existing hard-link alias.
            # Record that set independently before mutating; never call it app damage.
            aliases = [name for name in before if (root / name).stat().st_ino == facts.st_ino
                       and (root / name).stat().st_dev == facts.st_dev]
            assert relative in aliases
            affected = aliases if a.mode == 'in-place' else [relative]
            expected = dict(before)
            row = {'bytes': len(changed), 'sha256': sha(changed), 'base64': base64.b64encode(changed).decode()}
            for name in affected:
                expected[name] = row
            if a.mode == 'in-place':
                with file.open('r+b') as writer:
                    writer.write(changed)
                    writer.truncate()
                    writer.flush()
                    os.fsync(writer.fileno())
                assert file.stat().st_ino == facts.st_ino
            else:
                temporary = file.with_name(file.name + '.synthetic-replacement')
                assert not temporary.exists()
                temporary.write_bytes(changed)
                temporary.replace(file)
                assert file.stat().st_ino != facts.st_ino
            assert snapshot(root) == expected
            still_open = subprocess.check_output(['lsof', '-nP', '-a', '-p', str(record['pid']), '-d', str(record['descriptor']), '-Fnift'], text=True)
            assert 'tREG' in still_open and ('i' + str(record['inode'])) in still_open
            observations.append({'record': record.copy(), 'originalBytes': base64.b64encode(original).decode(),
                                 'originalSHA256': sha(original), 'changedSHA256': sha(changed),
                                 'openDescriptorBefore': lsof, 'openDescriptorAfterHostMutation': still_open, 'aliasesBefore': aliases, 'hostChangedPaths': affected,
                                 'afterHostMutation': snapshot(root), 'newPathInode': file.stat().st_ino,
                                 'observedAfterNativeAttachment': tag})
            release = group / 'Lumen-health-read-release.json'
            temporary = group / (release.name + '.' + record['nonce'] + '.tmp')
            temporary.write_text(json.dumps({'nonce': record['nonce']}))
            temporary.replace(release)
            time.sleep(0.2)
        code = process.wait()
    finally:
        (base / (prefix + '-observations.json')).write_text(json.dumps({
            'source': a.source, 'build': a.build, 'producerPID': process.pid, 'producerExitCode': process.poll(),
            'before': before, 'expectedAfterExplicitHostChange': expected, 'heldObservations': observations,
            'protocol': protocol, 'restoration': restoration, 'retryObservations': retry_observations, 'scope': 'Dedicated synthetic simulator only; no personal phone data.'
        }, indent=2) + '\n')
summary = json.loads(subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(bundle)], text=True))
for destination in [raw / (stem + '-summary.json'), base / (prefix + '-summary.json')]:
    destination.write_text(json.dumps(summary, indent=2) + '\n')
assert code == 0 and summary['passedTests'] == 1 and summary['failedTests'] == 0
identity()
protocol = json.loads((container('group.com.dbakp.lumen') / 'Lumen-health-read-checkpoint.json').read_bytes())
assert len(observations) == 1
assert len(protocol['attempts']) == (2 if a.payload else 1)
assert all(r['phase'] == 'released' and r['workerControlMatchesUI'] and r['descriptorCloseSucceeded'] for r in protocol['attempts'])
if a.payload:
    assert restoration is not None and len(retry_observations) == 1
after = snapshot(container('group.com.dbakp.lumen') / 'LumenData')
assert after == (before if a.payload else expected)
(base / (prefix + '-host-audit.json')).write_text(json.dumps({
    'status': 'passed: actual held JPEG ' + ('payload ' if a.payload else 'verification ') + a.mode + ' source change rejected; native error/no image, reader closed' + ('; original restored and fresh retry displays image; all protected bytes exact' if a.payload else '; only explicit host changes remain'),
    'source': a.source, 'build': a.build, 'before': before, 'after': after,
    'expectedAfterExplicitHostChange': expected, 'heldObservations': observations, 'protocol': protocol,
    'restoration': restoration, 'retryObservations': retry_observations, 'producerExitCode': code, 'verifierSHA256': sha(Path(__file__).read_bytes()),
    'scope': ('One main-normal actual final retained-photo payload read/source-change/restoration/retry case; selected-file and full parent contracts remain required.' if a.payload else 'One main-normal verification read case; final payload/restoration and full other scopes remain required.')
}, indent=2) + '\n')
print('PASS: actual held JPEG ' + ('payload ' if a.payload else 'verification ') + a.mode + ' source change rejected' + ('; restored source/fresh retry/all protected bytes pass' if a.payload else '; only explicit host changes remain'))
