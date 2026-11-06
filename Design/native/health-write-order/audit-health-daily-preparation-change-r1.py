"""Manual native UI observer: mutate only the dedicated synthetic cache.

No UI automation, app edits, reset, SDK substitution or physical device use.
The real DEBUG worker barrier retains its original thirty-second deadline.
"""
import base64
import hashlib
import json
import os
import re
import stat
import subprocess
import sys
import time
from pathlib import Path

D = Path(__file__).resolve().parent
REPO = D.parents[2]
PREFIX = 'health-daily-preparation-change-r1'
OUT = D / (PREFIX + '-audit.json')
SIM = 'AF849DEA-DF34-4B0E-9FC1-3E45DCBE8481'
sha = lambda b: hashlib.sha256(b).hexdigest()


def container(kind):
    return Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', SIM,
                                        'com.dbakp.lumen', kind], text=True).strip())


def facts(root):
    assert root.is_dir() and not root.is_symlink()
    result = {}
    for p in root.rglob('*'):
        s = p.lstat()
        if stat.S_ISDIR(s.st_mode):
            continue
        assert stat.S_ISREG(s.st_mode) and s.st_size < 256 * 1024, p
        b = p.read_bytes()
        result[str(p.relative_to(root))] = dict(bytes=len(b), sha256=sha(b),
            base64=base64.b64encode(b).decode(), inode=s.st_ino, mode=stat.S_IMODE(s.st_mode))
    return result


def frozen():
    packet = json.loads((D / 'health-daily-cache-review-r1-packet.json').read_text())
    for name, digest in packet['frozenFiles'].items():
        assert sha((REPO / name).read_bytes()) == digest, name
    build = json.loads((D / 'health-daily-controls-r1-build.json').read_text())
    b = (container('app') / 'Lumen').read_bytes()
    assert len(b) == build['binaryBytes'] and sha(b) == build['sha256']


def save(a):
    OUT.write_text(json.dumps(a, indent=2) + '\n')


frozen()
g = container('group.com.dbakp.lumen')
root, prior = g / 'LumenData', g / 'LumenData.previous'
phase = sys.argv[1]
if phase == 'baseline':
    assert not OUT.exists()
    old = json.loads((D / 'health-daily-changed-cache-r1-audit.json').read_text())
    assert facts(root) == old['afterNavigation'] and facts(prior) == old['previousAfterNavigation']
    a = dict(status='Predeclared; native query/save not executed', started=time.time(),
             source='durable-source-r162.json', before=facts(root), previousBefore=facts(prior),
             mutation='Only known synthetic today.json water401to402, in place during actual preparation hold',
             scope='Main simulator/light/standard manual native UI; mutation after transaction source snapshot and stage creation, before clone/install. Not a completed clone/precommit/install race.',
             driverSHA256=sha(Path(__file__).read_bytes()))
    save(a)
elif phase == 'watch':
    a = json.loads(OUT.read_text())
    assert facts(root) == a['before'] and facts(prior) == a['previousBefore']
    q = g / 'Lumen-daily-cache-health-query.json'
    assert q.stat().st_mtime >= a['started']
    query = json.loads(q.read_bytes())
    assert query['requestCompleted'] and len(query['callbacks']) == 18
    assert len(query['metrics']['readings']) == 18
    assert all(r['healthQuery']['outcome'] == 'noData' and r['components'] == []
               for r in query['metrics']['readings'].values())
    a['query'] = query
    (D / (PREFIX + '-query.json')).write_bytes(q.read_bytes())
    save(a)
    checkpoint = g / 'Lumen-health-cancel-checkpoint.json'
    deadline = time.monotonic() + 180
    while time.monotonic() < deadline:
        state = json.loads(checkpoint.read_bytes())
        if checkpoint.stat().st_mtime >= a['started'] and state.get('attempts'):
            record = state['attempts'][-1]
            if record['phase'] == 'held':
                break
        time.sleep(.05)
    else:
        raise AssertionError('No fresh held worker within180seconds')
    assert record['workerControlMatchesUI'] and not record['uiCancelled']
    assert re.fullmatch(r'LumenData\.restore-[A-Fa-f0-9-]+', record['stage'])
    assert (g / record['stage']).is_dir()
    assert facts(root) == a['before'] and facts(prior) == a['previousBefore']
    p = root / 'today.json'
    raw = p.read_bytes()
    old = json.loads(raw)
    assert old['readings']['water']['components'][0]['value'] == 401
    # Preserve every byte except the exact component value, and keep inode/mode.
    new, count = re.subn(rb'("value"\s*:\s*)401(?=\s*[,}])', rb'\g<1>402', raw)
    assert count == 1 and len(raw) == len(new)
    expected = json.loads(raw)
    expected['readings']['water']['components'][0]['value'] = 402
    assert json.loads(new) == expected
    with p.open('r+b') as f:
        f.write(new)
        f.flush()
        os.fsync(f.fileno())
    changed = facts(root)
    assert changed['today.json']['inode'] == a['before']['today.json']['inode']
    assert changed['today.json']['mode'] == a['before']['today.json']['mode']
    expected_facts = dict(a['before']); expected_facts['today.json'] = changed['today.json']
    assert changed == expected_facts
    a.update(held=record, mutationAppliedAt=time.time(), mutatedToday=changed['today.json'],
             afterMutation=changed, heldUICaptureClaimed=False,
             status='Actual worker held; synthetic401to402mutation verified; release pending')
    save(a)
    release = g / ('Lumen-cache-change-release-' + record['nonce'] + '.tmp')
    release.write_text(json.dumps({'nonce': record['nonce']}))
    release.replace(g / 'Lumen-health-cancel-release.json')
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline and (g / record['stage']).exists():
        time.sleep(.05)
    assert not (g / record['stage']).exists(), 'Stage not cleaned within30s'
    assert facts(root) == changed and facts(prior) == a['previousBefore']
    final = json.loads(checkpoint.read_bytes())
    assert final['attempts'][-1]['nonce'] == record['nonce']
    assert final['attempts'][-1]['phase'] == 'released'
    a.update(afterRejection=facts(root), previousAfterRejection=facts(prior), checkpointAfter=final,
             stageAbsent=True, rejectedAt=time.time(),
             status='Worker released; changed snapshot preserved; stage cleaned; native error/retry verification pending')
    save(a)
elif phase == 'verify':
    a = json.loads(OUT.read_text())
    assert facts(root) == a['afterRejection'] and facts(prior) == a['previousBefore']
    assert not list(g.glob('LumenData.restore-*'))
    a.update(afterNavigation=facts(root), previousAfterNavigation=facts(prior), verifiedAt=time.time())
    save(a)
else:
    raise AssertionError('Unknown phase')
print(json.loads(OUT.read_text())['status'], flush=True)
