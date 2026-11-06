"""Bind a manual native confirmation to a byte-identical replacement inode.

This only replaces the known synthetic cache on the named test simulator.
No app source changes, SDK substitution, UI actions or physical-device access.
"""
import base64
import hashlib
import json
import os
import stat
import subprocess
import sys
import time
import uuid
from pathlib import Path

D = Path(__file__).resolve().parent
REPO = D.parents[2]
OUT = D / 'health-daily-identity-change-r1-audit.json'
SIM = 'AF849DEA-DF34-4B0E-9FC1-3E45DCBE8481'
sha = lambda b: hashlib.sha256(b).hexdigest()


def container(kind):
    return Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', SIM,
                                        'com.dbakp.lumen', kind], text=True).strip())


def facts(root):
    assert root.is_dir() and not root.is_symlink()
    rows = {}
    for p in root.rglob('*'):
        s = p.lstat()
        if stat.S_ISDIR(s.st_mode):
            continue
        assert stat.S_ISREG(s.st_mode) and s.st_size < 256 * 1024
        b = p.read_bytes()
        rows[str(p.relative_to(root))] = dict(bytes=len(b), sha256=sha(b),
            base64=base64.b64encode(b).decode(), inode=s.st_ino, mode=stat.S_IMODE(s.st_mode))
    return rows


packet = json.loads((D / 'health-daily-cache-review-r1-packet.json').read_text())
for name, digest in packet['frozenFiles'].items():
    assert sha((REPO / name).read_bytes()) == digest
build = json.loads((D / 'health-daily-controls-r1-build.json').read_text())
binary = (container('app') / 'Lumen').read_bytes()
assert len(binary) == build['binaryBytes'] and sha(binary) == build['sha256']
g = container('group.com.dbakp.lumen')
root, prior = g / 'LumenData', g / 'LumenData.previous'
checkpoint = g / 'Lumen-health-cancel-checkpoint.json'
phase = sys.argv[1]
if phase == 'baseline':
    assert not OUT.exists()
    previous = json.loads((D / 'health-daily-preparation-change-r1-audit.json').read_text())
    assert previous['status'].startswith('PASS')
    assert facts(root) == previous['afterNavigation']
    assert facts(prior) == previous['previousAfterNavigation']
    a = dict(status='Predeclared; fresh native query and replacement unexecuted',
             source='durable-source-r162.json', started=time.time(),
             before=facts(root), previousBefore=facts(prior),
             checkpointBefore=base64.b64encode(checkpoint.read_bytes()).decode(),
             checkpointMtimeBefore=checkpoint.stat().st_mtime_ns,
             mutation='After actual SDK review, atomically replace only known synthetic today.json with exact same bytes/mode/mtime and a different inode',
             required=['Native confirmation rejects despite byte-identical cache.',
                       'Preserve replacement inode, all other20current/9prior facts, intent and retained copies.',
                       'No new save worker/stage/receipt/copy; useful native error; reopen/retry/Not now/Back/idle.'],
             scope='Main simulator/light/standard manual native UI; replacement inode before preparation, not mid-read or install race.',
             driverSHA256=sha(Path(__file__).read_bytes()))
else:
    a = json.loads(OUT.read_text())
    if phase == 'replace':
        assert facts(root) == a['before'] and facts(prior) == a['previousBefore']
        q = g / 'Lumen-daily-cache-health-query.json'
        assert q.stat().st_mtime >= a['started']
        query = json.loads(q.read_bytes())
        assert query['requestCompleted'] and len(query['callbacks']) == 18
        assert len(query['metrics']['readings']) == 18
        assert all(r['healthQuery']['outcome'] == 'noData' and r['components'] == []
                   for r in query['metrics']['readings'].values())
        a['query'] = query
        (D / 'health-daily-identity-change-r1-query.json').write_bytes(q.read_bytes())
        p = root / 'today.json'
        info = p.lstat(); raw = p.read_bytes()
        assert json.loads(raw)['readings']['water']['components'][0]['value'] == 402
        temp = root / ('.identity-fixture-' + str(uuid.uuid4()))
        # Create without following or overwriting any existing path.
        fd = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, stat.S_IMODE(info.st_mode))
        with os.fdopen(fd, 'wb') as f:
            f.write(raw); f.flush(); os.fsync(f.fileno())
        os.chmod(temp, stat.S_IMODE(info.st_mode))
        os.utime(temp, ns=(info.st_atime_ns, info.st_mtime_ns), follow_symlinks=False)
        assert temp.lstat().st_ino != info.st_ino and p.lstat().st_ino == info.st_ino
        assert p.read_bytes() == raw and temp.read_bytes() == raw
        os.replace(temp, p)
        now = p.lstat()
        assert now.st_ino != info.st_ino and now.st_mtime_ns == info.st_mtime_ns
        after = facts(root)
        expected = dict(a['before']); expected['today.json'] = dict(expected['today.json'], inode=now.st_ino)
        assert after == expected and facts(prior) == a['previousBefore']
        a.update(afterReplacement=after, replacementAt=time.time(),
                 sameBytesModeMtime=True, oldInode=info.st_ino, newInode=now.st_ino,
                 mtimeNanoseconds=now.st_mtime_ns,
                 status='Actual fresh18noData review observed; exact byte/mode/mtime replacement with new inode verified; native confirmation pending')
    elif phase == 'verify':
        assert facts(root) == a['afterReplacement'] and facts(prior) == a['previousBefore']
        assert checkpoint.read_bytes() == base64.b64decode(a['checkpointBefore'])
        assert checkpoint.stat().st_mtime_ns == a['checkpointMtimeBefore']
        assert not list(g.glob('LumenData.restore-*'))
        a.update(afterVerification=facts(root), previousAfterVerification=facts(prior), verifiedAt=time.time(),
                 noNewWorker=True, noStage=True)
    else:
        raise AssertionError('Unknown phase')
OUT.write_text(json.dumps(a, indent=2) + '\n')
print(a['status'], flush=True)
