"""Remove completed225 raw duplicates only after exact full-pair publication."""
from pathlib import Path
import base64
import gzip
import hashlib
import json
import os
import shutil
import stat
import time
import tempfile

BASE = Path(__file__).resolve().parent
OUT = BASE / 'source226-completed-erasure-raw-cleanup-r1.json'
assert not OUT.exists()
proof = json.loads((BASE / 'source225-pair-completion-exact-github.json').read_text())
assert proof['commit'] == '4e659b8d487bb1e3d2d8779f0788632144d11f1b' and proof['unionPaths'] == 516
backed = {row['file']: row for row in proof['proofs']}
targets = []
raw = Path('/tmp/LumenBatch44Checks')
for case, part in [('data', '107-data'), ('string', '108-string')]:
    prefix = 'health-legacy-settings-erase-' + case + '-source225r1'
    outcome = json.loads((BASE / (prefix + '-outcome.json')).read_text())
    assert outcome['nativeExit'] == outcome['driverExit'] == 0 and outcome['hostError'] is None
    for suffix in ['images', 'readbacks']:
        items = json.loads((BASE / (prefix + '-' + suffix + '.json')).read_text())
        assert len(items) == (9 if suffix == 'images' else 1)
        for row in items:
            path = BASE / row['file']
            data = path.read_bytes()
            declared = backed[str(path.relative_to(BASE.parents[2]))]
            assert len(data) == declared['bytes'] and hashlib.sha256(data).hexdigest() == declared['sha256']
            assert data == Path(row['raw']).read_bytes() and row['individuallyOpened']
    stem = 'HealthLegacySettingsErase' + case.title() + 'Source225R1'
    targets.extend(raw / (stem + suffix) for suffix in ['.xcresult', 'PNG', 'JSON', '.log', '-summary.json'])
isolated = json.loads((BASE / 'erasure-persistence-observation-r1-outcome.json').read_text())
root = Path(isolated['rawRoot'])
assert root.parent == Path(tempfile.gettempdir()) and root.name.startswith('LumenErasurePersistenceR1-') and not root.is_symlink()
archive = json.loads(gzip.decompress((BASE / isolated['archive']).read_bytes()))
assert len(archive) == 40
for name, row in archive.items():
    path = root / name
    assert not path.is_symlink()
    data = path.read_bytes()
    assert data == base64.b64decode(row['base64'], validate=True) and hashlib.sha256(data).hexdigest() == row['sha256']
targets.append(root)
assert len(targets) == 11
state = {'status': 'RUNNING exact-backed completed raw cleanup', 'proofCommit': proof['commit'],
         'targets': [str(p) for p in targets], 'beforeAvailableBytes': shutil.disk_usage(BASE).free,
         'started': time.time(), 'regularFiles': 0, 'symlinksUnlinked': 0}
OUT.write_text(json.dumps(state, indent=2) + '\n')
inodes = {}


def remove(path):
    facts = path.lstat()
    if stat.S_ISLNK(facts.st_mode):
        path.unlink()
        state['symlinksUnlinked'] += 1
    elif stat.S_ISREG(facts.st_mode):
        row = inodes.setdefault((facts.st_dev, facts.st_ino), {'links': facts.st_nlink, 'removed': 0, 'allocated': facts.st_blocks*512})
        path.unlink()
        row['removed'] += 1
        state['regularFiles'] += 1
    else:
        assert stat.S_ISDIR(facts.st_mode)
        for child in path.iterdir():
            remove(child)
        path.rmdir()


try:
    for target in targets:
        assert (str(target).startswith('/tmp/LumenBatch44Checks/HealthLegacySettingsErase') or target == root) and not target.is_symlink()
        if os.path.lexists(target):
            remove(target)
    state['status'] = 'PASS completed225 raw duplicates removed; canonical18originals/helpers/source and currentDebug/packages retained'
finally:
    after = shutil.disk_usage(BASE).free
    allocated = sum(v['allocated'] for v in inodes.values() if v['removed'] >= v['links'])
    state.update(afterAvailableBytes=after, knownReleasedAllocatedBytes=allocated,
                 observedFreeIncreaseBytes=after-state['beforeAvailableBytes'],
                 creditedRecoveredBytes=max(0, min(allocated, after-state['beforeAvailableBytes'])),
                 oldRawPathsNowHistorical=True, physicalDeviceActions=False, finished=time.time())
    OUT.write_text(json.dumps(state, indent=2) + '\n')
print(json.dumps({key: state[key] for key in ['status', 'regularFiles', 'symlinksUnlinked',
                                           'knownReleasedAllocatedBytes', 'observedFreeIncreaseBytes', 'creditedRecoveredBytes']}))
