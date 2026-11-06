"""Read-only post-driver audit of the entire synthetic recovery tree."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess

p = argparse.ArgumentParser()
p.add_argument('--prefix', required=True)
a = p.parse_args()
b = Path(__file__).resolve().parent
audit = json.loads((b / (a.prefix + '-host-audit.json')).read_text())
root = Path(subprocess.check_output([
    'xcrun', 'simctl', 'get_app_container',
    'AF849DEA-DF34-4B0E-9FC1-3E45DCBE8481', 'com.dbakp.lumen',
    'group.com.dbakp.lumen'], text=True).strip()) / 'LumenData'
assert root.is_dir() and not root.is_symlink()
tree = {}
for parent, dirs, files in os.walk(root, followlinks=False):
    assert all(not (Path(parent) / name).is_symlink() for name in dirs)
    for name in files:
        f = Path(parent) / name
        assert stat.S_ISREG(f.lstat().st_mode) and f.stat().st_size < 256 * 1024
        data = f.read_bytes()
        tree[str(f.relative_to(root))] = {
            'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(),
            'base64': base64.b64encode(data).decode()}
decode = lambda row: json.loads(base64.b64decode(row['base64']))
before = audit['protectedBefore']
parent = audit['finalCleanupBeforeRelaunch']['treeAtParentBeforeRelaunch']
assert len(before) == 12 and len(tree) == 19
assert set(tree) == set(parent)
for name, row in before.items():
    assert tree[name] == audit['after'][name]
    if name not in ['water.json', 'health-write-intent.json']:
        assert parent[name] == row, name
        if name in ['profile.json', 'habits.json']:
            assert decode(tree[name]) == decode(row), name
        else:
            assert tree[name] == row, name
    else:
        assert tree[name] == parent[name], name
extra = set(tree) - set(before)
prior = audit['preservationBeforeCommit']['files']
assert len(prior) == 3 and all(tree[k] == row for k, row in prior.items())
damaged = [k for k in extra if k.endswith('/water.json') and tree[k] == before['water.json']]
assert len(damaged) == 1
folder = Path(damaged[0]).parent
damaged_keys = {str(folder / name) for name in ['water.json', 'device-intent.json', 'manifest.json']}
assert tree[str(folder / 'device-intent.json')] == before['health-write-intent.json']
manifest = decode(tree[str(folder / 'manifest.json')])
assert manifest['version'] == 1 and manifest['domains'] == ['water']
assert manifest['intent'] is True and manifest['photos'] is False
receipts = [k for k in extra if k.startswith('.health-recovery-history/')]
assert len(receipts) == 1 and decode(tree[receipts[0]]) == audit['receipt']
assert extra == set(prior) | damaged_keys | set(receipts)
assert all(tree[k] == parent[k] for k in extra)
out = {'status': 'passed: complete nineteen-file tree after normal relaunch',
       'source': audit['source'], 'hostAudit': a.prefix + '-host-audit.json',
       'case': audit['case'], 'tree': tree,
       'unchangedCurrentBeforeRelaunch': 10,
       'startupSemanticOnlyExceptions': ['profile.json', 'habits.json'],
       'privatePreviousWaterAndIntentExact': True,
       'privateDamagedWaterAndIntentExact': True,
       'bothPrivateManifestsWaterOnlyNoPhotos': True,
       'onlySevenExpectedPrivateAndReceiptFilesAdded': True,
       'allSevenPrivateAndReceiptBytesSurviveRelaunch': True,
       'verifierSHA256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
       'hostMutatedAppData': False}
(b / (a.prefix + '-tree-audit.json')).write_text(json.dumps(out, indent=2) + '\n')
print('PASS:', audit['case'], 'entire nineteen-file tree; both histories and intents preserved')
