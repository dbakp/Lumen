"""Remove only this backed case's exact host release/ack metadata before the next case."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess
import time

base = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('capture_metadata_evidence', base / 'capture-state-evidence-r3.py')
e = importlib.util.module_from_spec(spec)
spec.loader.exec_module(e)
h = e.h
p = argparse.ArgumentParser()
p.add_argument('--prefix', required=True)
p.add_argument('--proof', required=True)
p.add_argument('--root-review', required=True)
p.add_argument('--independent', required=True)
a = p.parse_args()
assert re.fullmatch(r'health-capture-state-[A-Za-z0-9-]+', a.prefix)
state = h.load(base / (a.prefix + '-host-audit.json'))
outcome = h.load(base / (a.prefix + '-outcome.json'))
assert state['device'] == h.DEVICE and outcome['nativeExit'] == outcome['driverExit'] == 0
e.completed_state(state)
proof = h.load(Path(a.proof))
assert proof['commit'] == subprocess.check_output(['git', 'rev-parse', 'origin/main'], cwd=h.REPO, text=True).strip()
paths = set()
for row in proof['proofs']:
    name = row['file']
    assert not Path(name).is_absolute() and '..' not in Path(name).parts
    path = h.REPO / name
    data = h.read(path, 8 * 1024 * 1024)
    assert len(data) == row['bytes'] and h.sha(data) == row['sha256']
    assert subprocess.check_output(['git', 'show', 'origin/main:' + name], cwd=h.REPO) == data
    paths.add(name)
for suffix in ['-host-audit.json', '-outcome.json', '-images.json', '-readbacks.json']:
    assert str((base / (a.prefix + suffix)).relative_to(h.REPO)) in paths
for name in [a.root_review, a.independent]:
    assert Path(name).name == name and str((base / name).relative_to(h.REPO)) in paths
root_review = h.load(base / a.root_review)
independent_data = h.read(base / a.independent, 1024 * 1024)
assert root_review['source'] == state['source'] and root_review['status'].startswith('Supported')
independent = root_review['independent']
assert independent['file'] == a.independent and independent['fullReportRead'] is True
assert independent['bytes'] == len(independent_data) and independent['sha256'] == h.sha(independent_data)
for index in ['images', 'readbacks']:
    for row in h.load(base / (a.prefix + '-' + index + '.json')):
        assert row['individuallyOpened'] is True
        assert str((base / row['file']).relative_to(h.REPO)) in paths
group = h.container('group.com.dbakp.lumen')
assert not h.owned(state['finalCapture']['pid'])
removed = []
before = shutil.disk_usage(h.REPO).free
allocated = 0
for name, value in state['messages'].items():
    assert name in ['Lumen-legacy-capture-release.json', 'Lumen-legacy-capture-host-ack.json']
    path = group / name
    data = h.read(path, 4096)
    assert json.loads(data) == value and value['runID'] == state['finalCapture']['runID']
    facts = h.identity(path)
    scan = subprocess.run(['lsof', '-nP', str(path)], capture_output=True, text=True)
    assert scan.returncode == 1 and not scan.stdout
    allocated += path.lstat().st_blocks * 512
    removed.append({'file': str(path), 'bytes': len(data), 'sha256': h.sha(data), 'identity': facts})
for row in removed:
    path = Path(row['file'])
    assert h.identity(path) == row['identity'] and h.sha(h.read(path, 4096)) == row['sha256']
    path.unlink()
after = shutil.disk_usage(h.REPO).free
result = {'status': 'PASS exact backed synthetic host release/ack metadata removed', 'source': state['source'],
    'case': state['case'], 'prefix': a.prefix, 'exactGithubMain': proof['commit'], 'removed': removed,
    'allocatedBytes': allocated, 'observedFreeDeltaBytes': after - before,
    'positiveRecoveryCreditBytes': min(allocated, max(0, after - before)),
    'scope': 'Known nonce/run-bound synthetic metadata only. Capture/origin checkpoints, raw native evidence, current/prior/defaults/provider, caches and personal data untouched. Prior live checker message paths are historical after cleanup.',
    'checkedAt': time.time()}
(base / (a.prefix + '-metadata-cleanup.json')).write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({key: result[key] for key in ['status', 'allocatedBytes', 'observedFreeDeltaBytes', 'positiveRecoveryCreditBytes']}), flush=True)
