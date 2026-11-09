"""Remove only completed Core258 build cache after exact GitHub evidence backup."""
from pathlib import Path
import hashlib, json, os, shutil, stat, subprocess, time
B = Path(__file__).resolve().parent; R = B.parents[2]
proof = json.loads((B / 'source258-notready-exact-github.json').read_bytes())
assert proof['commit'] == '7f5eb5f1f52e179c670882ab6ce7bd3938d7938d' and proof['unionPaths'] == 2478
for ref in ['HEAD', 'origin/main']:
    assert subprocess.check_output(['git', 'rev-parse', ref], cwd=R, text=True).strip() == proof['commit']
facts = {item['file']: item for item in proof['proofs']}
required = ['source258-retained-owner-core-r5.json', 'source258-retained-owner-core-r5.log.gz',
            'source258-full-core-r3.json', 'source258-full-core-r3.log.gz', 'source258-root-part179-review.json',
            'health-retained-review-owner-source258-round2-part179-source.json']
for name in required:
    path = B / name; raw = path.read_bytes(); expected = facts[str(path.relative_to(R))]
    assert len(raw) == expected['bytes'] and hashlib.sha256(raw).hexdigest() == expected['sha256']
target = Path('/tmp/LumenLogicBuild'); assert target.is_dir() and not target.is_symlink()
processes = subprocess.check_output(['ps', '-axo', 'pid=,comm=,args='], text=True)
for row in processes.splitlines():
    fields = row.split(None, 2)
    if len(fields) == 3 and Path(fields[1]).name in ['swift', 'swift-build', 'swiftc', 'swift-frontend', 'LumenLogicChecks']:
        assert '/tmp/LumenLogicBuild' not in fields[2], 'Task-owned Core cache still active'
allocated = 0; entries = 0; symlinks = 0
for parent, directories, files in os.walk(target, followlinks=False):
    for name in directories + files:
        info = (Path(parent) / name).lstat(); allocated += info.st_blocks * 512; entries += 1
        if stat.S_ISLNK(info.st_mode): symlinks += 1
before = shutil.disk_usage(R).free
shutil.rmtree(target)  # Does not follow symlinks into package/global caches.
after = shutil.disk_usage(R).free
assert not target.exists()
credited = min(allocated, max(0, after - before))
report = {'status': 'PASS scoped completed Core258 cache cleanup', 'deleted': str(target),
          'proof': 'source258-notready-exact-github.json', 'proofCommit': proof['commit'],
          'entries': entries, 'symlinksNotFollowed': symlinks, 'allocatedBytes': allocated,
          'availableBeforeBytes': before, 'availableAfterBytes': after, 'creditedRecoveryBytes': credited,
          'aggregateCreditedRecoveryBytes': 16746454615 + credited,
          'preserved': 'Repository/currentinputs/Debug/packages/provider/designskill/canonical evidence/unbacked191219/unrelated data and global caches',
          'checkedAt': time.time()}
path = B / 'source259-completed-core258-cleanup-r1.json'; assert not path.exists(); path.write_text(json.dumps(report, indent=2) + '\n'); print(json.dumps(report))
