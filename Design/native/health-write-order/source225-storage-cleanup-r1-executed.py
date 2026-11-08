"""Remove only exact-backed completed exports and unused task Release cache."""
from pathlib import Path
import hashlib
import json
import os
import shutil
import stat
import subprocess
import time

BASE = Path(__file__).resolve().parent
OUT = BASE / 'source225-storage-cleanup-r1.json'
assert not OUT.exists(), 'Never count recovery twice'
proof = json.loads((BASE / 'source224-failed-completion-exact-github.json').read_text())
assert proof['commit'] == '5eb433501e779de4c62dd507342aecbafc7bbb20'
assert proof['status'].startswith('PASS') and proof['unionPaths'] == 463
required = ['health-legacy-settings-erasure-source224-round2-part105-failed-native.json',
            'health-legacy-settings-erase-data-source224r1-all-originals.json',
            'health-legacy-settings-erase-data-source224r1-all-nonvideo-payloads.json.gz',
            'health-legacy-settings-erase-data-source224r1-failure-recording.mp4',
            'health-current-release-source223-round2-part99.json',
            'source223-unsigned-release-r1-build.log.gz',
            'source223-unsigned-release-r1-settings-audit.json']
release_proof = json.loads((BASE / 'source223-completion-exact-github.json').read_text())
assert release_proof['commit'] == 'c16cd98ad2b44fca573e151c912d8b177700b9b8'
rows = {row['file']: (row, release_proof['commit']) for row in release_proof['proofs']}
rows.update({row['file']: (row, proof['commit']) for row in proof['proofs']})
for name in required:
    path = BASE / name
    relative = str(path.relative_to(BASE.parents[2]))
    data = path.read_bytes()
    row, backed_commit = rows[relative]
    assert len(data) == row['bytes'] and hashlib.sha256(data).hexdigest() == row['sha256']
    assert subprocess.check_output(['git', 'show', backed_commit + ':' + relative], cwd=BASE.parents[2]) == data
for line in subprocess.check_output(['ps', '-axo', 'command='], text=True).splitlines():
    command = line.strip().split(' ', 1)[0]
    if command.endswith('/xcodebuild') or command == 'xcodebuild':
        assert '/tmp/LumenBatch37Release' not in line, 'Release cache still in use'
release = Path('/tmp/LumenBatch37Release')
binary = release / 'Build/Products/Release-iphoneos/Lumen.app/Lumen'
assert hashlib.sha256(binary.read_bytes()).hexdigest() == '5f4004fd2033863ed2a0511a51406ebaa151c0a46531e97f2f22fbdb104db0d5'
targets = [release]
raw = Path('/tmp/LumenBatch44Checks')
for stem in ['HealthResetPreflightDiagnosticSource223R1', 'HealthLegacySettingsEraseDataSource224R1']:
    targets.extend(raw / (stem + suffix) for suffix in ['.xcresult', 'PNG', 'JSON', '.log', '-summary.json'])
targets.append(raw / 'HealthLegacySettingsEraseDataSource224R1All')
assert len(targets) == 12
before = shutil.disk_usage(BASE).free
state = {'status': 'RUNNING scoped cleanup', 'proofCommit': proof['commit'], 'targets': [str(p) for p in targets],
         'availableBeforeBytes': before, 'started': time.time(), 'removedRegularFiles': 0, 'unlinkedSymlinks': 0,
         'physicalDeviceActions': False}
OUT.write_text(json.dumps(state, indent=2) + '\n')
inodes = {}


def remove(path):
    facts = path.lstat()
    if stat.S_ISLNK(facts.st_mode):
        path.unlink()
        state['unlinkedSymlinks'] += 1
    elif stat.S_ISREG(facts.st_mode):
        key = (facts.st_dev, facts.st_ino)
        record = inodes.setdefault(key, {'links': facts.st_nlink, 'removed': 0, 'allocated': facts.st_blocks * 512})
        path.unlink()
        record['removed'] += 1
        state['removedRegularFiles'] += 1
    else:
        assert stat.S_ISDIR(facts.st_mode)
        for child in path.iterdir():
            remove(child)
        path.rmdir()


try:
    for target in targets:
        assert target.is_absolute() and str(target).startswith('/tmp/Lumen') and not target.is_symlink()
        if os.path.lexists(target):
            remove(target)
        OUT.write_text(json.dumps(state, indent=2) + '\n')
    state['status'] = 'PASS scoped exact-backed disposable cleanup; native build/packages/inputs preserved'
finally:
    after = shutil.disk_usage(BASE).free
    allocated = sum(row['allocated'] for row in inodes.values() if row['removed'] >= row['links'])
    state.update(availableAfterBytes=after, observedFreeIncreaseBytes=after-before,
                 knownReleasedAllocatedBytes=allocated, creditedRecoveredBytes=max(0, min(allocated, after-before)),
                 finished=time.time(), rawPathsNowHistorical=True)
    OUT.write_text(json.dumps(state, indent=2) + '\n')
print(json.dumps({key: state[key] for key in ['status', 'removedRegularFiles', 'unlinkedSymlinks',
                                            'knownReleasedAllocatedBytes', 'observedFreeIncreaseBytes', 'creditedRecoveredBytes']}))
