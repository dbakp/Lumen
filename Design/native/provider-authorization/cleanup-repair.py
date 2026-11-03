"""One-shot Batch42 cleanup, requiring a fresh exact published checkpoint proof."""
import gzip
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
from datetime import datetime, timezone

base = Path(__file__).resolve().parent
repo = base.parents[2]
proof = json.loads(Path(sys.argv[1]).read_text())
plan = json.loads((base / 'cleanup-plan-r1.json').read_text())
def run(*args):
    return subprocess.check_output(args, cwd=repo).decode().strip()
def sha(data):
    return hashlib.sha256(data).hexdigest()
def safe_components(path):
    # /tmp is the system's /private/tmp alias, resolved once; never follow any
    # symlink within an owned output root or simulator app container.
    actual = Path('/private/tmp') / path.relative_to('/tmp') if str(path).startswith('/tmp/') else path
    for part in [actual, *actual.parents]:
        assert not part.is_symlink(), str(part)
    return actual

head = run('git', 'rev-parse', 'HEAD')
assert proof['status'] == 'passed' and proof['commit'] == head
assert run('gh', 'api', 'repos/dbakp/Lumen/git/ref/heads/main', '--jq', '.object.sha') == head
assert (datetime.now(timezone.utc) - datetime.fromisoformat(proof['checkedAtUTC'])).total_seconds() < 1800
for row in proof['requiredBlobs']:
    assert sha((repo / row['path']).read_bytes()) == row['sha256'], row['path']
processes = run('ps', '-axo', 'pid=,comm=,args=').splitlines()
for line in processes:
    if str(os.getpid()) == line.split()[0]:
        continue
    assert not any(x in line for x in ['xcodebuild', 'XCBBuildService', 'xctest ', 'testmanagerd.runner']), line
    assert not ('python' in line and '/tmp/LumenBatch42Checks/' in line), line

# Verify every complete primary log and current helper before removing raw copies.
for filename, key in [('raw-primary-log-retention-r1.json', 'logs'), ('raw-helper-source-retention-r1.json', 'inputs')]:
    retention = json.loads((base / filename).read_text())
    for row in retention[key]:
        raw = safe_components(Path(row['raw'])).read_bytes()
        retained = (repo / row['retained']).read_bytes()
        assert sha(raw) == row['sha256'] and gzip.decompress(retained) == raw
        assert sha(retained) == row['compressedSHA256']

expected = {
    '/tmp/LumenBatch42Checks',
    '/tmp/LumenBatch37Simulator/Build/Products/Release-iphonesimulator',
    '/tmp/LumenBatch37Simulator/Build/Intermediates.noindex/Lumen.build/Release-iphonesimulator',
    '/tmp/LumenBatch37Simulator/Build/Intermediates.noindex/ZIPFoundation.build/Release-iphonesimulator',
}
assert {row['path'] for row in plan['roots']} == expected
roots = []
inventory = []
seen = set()
logical = allocated = 0
for row in plan['roots']:
    path = safe_components(Path(row['path']))
    info = path.lstat()
    assert stat.S_ISDIR(info.st_mode) and info.st_uid == row['ownerUID'] == os.getuid()
    assert (info.st_dev, info.st_ino) == (row['device'], row['inode'])
    roots.append(path)
    for directory, dirs, files in os.walk(path, followlinks=False):
        for name in dirs + files:
            item = Path(directory) / name
            details = item.lstat()
            assert stat.S_ISREG(details.st_mode) or stat.S_ISDIR(details.st_mode) or stat.S_ISLNK(details.st_mode), str(item)
            inventory.append({'path': str(item), 'bytes': details.st_size, 'allocatedBytes': details.st_blocks * 512, 'symlink': stat.S_ISLNK(details.st_mode)})
            if (details.st_dev, details.st_ino) not in seen:
                seen.add((details.st_dev, details.st_ino))
                allocated += details.st_blocks * 512
                if stat.S_ISREG(details.st_mode):
                    logical += details.st_size

# Keep simulator reports conservatively: these tiny files may be reused by
# subsequent diagnostics. This execution removes only the four stopped roots.
before = shutil.disk_usage(repo).free
for path in roots:
    shutil.rmtree(path)  # Python's fd-based implementation does not follow links.
    assert not path.exists()
after = shutil.disk_usage(repo).free
(base / 'repair-cleanup-inventory-r1.json.gz').write_bytes(gzip.compress(json.dumps(inventory).encode(), mtime=0))
receipt = {
    'status': 'completed', 'checkedAtUTC': datetime.now(timezone.utc).isoformat(),
    'publishedCheckpoint': head, 'verifiedRequiredBlobs': proof['verifiedRequiredBlobs'],
    'removedRoots': sorted(expected), 'retainedPrimaryLogs': 310, 'retainedHelperSources': 3,
    'beforeAvailableBytes': before, 'afterAvailableBytes': after,
    'immediateAvailableIncreaseBytes': after - before,
    'logicalFileBytes': logical, 'uniqueInodeAllocatedBytes': allocated,
    'inventoryEntries': len(inventory),
    'scope': 'Only four stopped task-owned raw/Release roots. Symlinks unlinked without following targets. Simulator reports, both task simulators, current Debug/package/logic caches, working repo, supplied skill, current inputs, unrelated data and global caches preserved. No cleanup-only build.',
    'measurementLimit': 'Available-volume delta includes APFS and concurrent activity; logical and allocated file bytes are separate measurements.',
}
(base / 'repair-storage-cleanup-r1.json').write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps(receipt, indent=2))
