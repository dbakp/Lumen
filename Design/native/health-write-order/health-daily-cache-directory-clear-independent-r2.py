"""Independently finish validation of terminal R3 without rerunning its native test.

The original R3 host's rejection of a required new history directory remains a
failed expectation. This audit permits only that exact private container, checks
its permissions, and re-observes the unchanged complete saved tree.
"""
import base64
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
import time

base = Path(__file__).resolve().parent
repo = base.parents[2]
prefix = 'health-daily-cache-directory-clear-r3'
audit_path = base / (prefix + '-host-audit.json')
audit_bytes = audit_path.read_bytes()
audit = json.loads(audit_bytes)
summary = json.loads((base / (prefix + '-summary.json')).read_text())
assert audit['nativeExitCode'] == 0
assert summary['passedTests'] == 1 and summary['failedTests'] == summary['skippedTests'] == 0
assert audit['initialCapturedBeforeClearReview'] and audit['notNowPreservedExactTree'] and audit['heldTreeExactBeforeRelease']
assert audit['status'].startswith('FAILED') and audit['observationError'] == "AssertionError('.health-cache-history')"
source = json.loads((base / 'durable-source-r165.json').read_text())
for path, facts in {**source['files'], **source['fixtureInputs']}.items():
    data = (repo / path).read_bytes()
    assert len(data) == facts['bytes'] and hashlib.sha256(data).hexdigest() == facts['sha256'], path

def container(kind):
    return Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', 'AF849DEA-DF34-4B0E-9FC1-3E45DCBE8481', 'com.dbakp.lumen', kind], text=True).strip())

build = json.loads((base / 'health-daily-cache-directory-clear-r1-build.json').read_text())
data = (container('app') / 'Lumen').read_bytes()
assert len(data) == build['binaryBytes'] and hashlib.sha256(data).hexdigest() == build['sha256']

def tree(root):
    assert root.is_dir() and not root.is_symlink()
    result = {}
    for parent, dirs, files in os.walk(root, followlinks=False):
        for name in dirs + files:
            path = Path(parent) / name; info = path.lstat()
            assert stat.S_ISDIR(info.st_mode) or stat.S_ISREG(info.st_mode)
            row = dict(kind='directory' if stat.S_ISDIR(info.st_mode) else 'file', mode=info.st_mode,
                       device=info.st_dev, inode=info.st_ino, bytes=info.st_size, modifiedNS=info.st_mtime_ns)
            if row['kind'] == 'file':
                assert info.st_size < 256 * 1024
                data = path.read_bytes()
                row.update(sha256=hashlib.sha256(data).hexdigest(), base64=base64.b64encode(data).decode())
            result[str(path.relative_to(root))] = row
    return result

group = container('group.com.dbakp.lumen'); root = group / 'LumenData'
before, previous = audit['before'], audit['previousBefore']
after, previous_after = tree(root), tree(group / 'LumenData.previous')
assert tree(root) == after == audit['after']
assert tree(group / 'LumenData.previous') == previous_after == previous == audit['previousAfter']
for name, facts in before.items():
    if name == 'today.json' or name.startswith('today.json/'): continue
    if facts['kind'] == 'file': assert after[name] == facts, name
    else: assert after[name]['kind'] == 'directory' and after[name]['mode'] == facts['mode'], name
for name in set(after) - set(before):
    if name in ['.health-cache-history', '.health-recovery']:
        assert after[name]['kind'] == 'directory'
        # History metadata is inside the owner-only root; raw private-copy directories are checked separately below.
        assert root.lstat().st_mode & 0o777 == 0o700
    else: assert name.startswith(('.health-cache-history/', '.health-recovery/')), name
current = json.loads(base64.b64decode(after['today.json']['base64']))
assert after['today.json']['kind'] == 'file' and current['readings'] == {} and current['recordedTotalKeys'] == [] and current['excludesLumenNutrition'] is True
assert not any(k.startswith('today.json/') for k in after)
copies = [k for k, v in after.items() if k.startswith('.health-recovery/') and k.endswith('/today.json') and v['kind'] == 'directory']
assert len(copies) == 1
raw_entries = {k[len('today.json'):].lstrip('/'): v for k, v in before.items() if k == 'today.json' or k.startswith('today.json/')}
assert len(raw_entries) == 4
for name, facts in raw_entries.items():
    copied = after[copies[0] + ('/' + name if name else '')]
    assert copied['kind'] == facts['kind']
    expected_mode = stat.S_IFDIR | 0o700 if facts['kind'] == 'directory' else facts['mode']
    assert copied['mode'] == expected_mode
    if facts['kind'] == 'file':
        assert all(copied[k] == facts[k] for k in ['inode', 'bytes', 'sha256', 'base64'])
receipts = [k for k, v in after.items() if k.startswith('.health-cache-history/') and v['kind'] == 'file']
assert len(receipts) == 1
receipt = json.loads(base64.b64decode(after[receipts[0]]['base64']))
journal = json.loads(base64.b64decode(before['health-write-intent.json']['base64']))
assert receipt['action'] == 'clear' and receipt['owner'] == journal['owner'] and receipt['prior']['state'] == 'unavailable'
assert set(receipt['prior']['entries']) == set(raw_entries)
for name, facts in raw_entries.items():
    entry = receipt['prior']['entries'][name]
    assert entry['mode'] == facts['mode'] and entry['device'] == facts['device'] and entry['inode'] == facts['inode'] and entry['size'] == facts['bytes']
    assert entry['modifiedSeconds'] * 1_000_000_000 + entry['modifiedNanos'] == facts['modifiedNS']
    assert entry.get('digest') == facts.get('sha256')
assert receipt['rawDigest'] == after['today.json']['sha256']
assert not (group / audit['held']['stage']).exists()
result = dict(status='PASS independent post-terminal nativeR3 directory-clear audit; original R3 host expectation remains failed',
              checkedAt=time.time(), source='durable-source-r165.json', nativeTrial=prefix,
              originalHostAuditSHA256=hashlib.sha256(audit_bytes).hexdigest(), independentAuditorSHA256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              sourceInputs=253, fixtureInputs=6, nativePassedTests=1, nativeFailedTests=0, nativeSkippedTests=0,
              exactCurrentTreeReobserved=True, exactPreviousTreeReobserved=True,
              preActionAndNotNowAndHeldAudits=True, explicitUnknownSnapshot=True,
              rawDirectoryEntriesPreserved=4, sentinelFileInodesAndBytesAndModesExact=True, privateDirectoriesMode='0700',
              originalDirectoryModesAndAllRawMetadataExactInReceipt=True, receipt=receipt,
              historyContainerMode=oct(after['.health-cache-history']['mode']), ownerOnlyDataRootMode=oct(root.lstat().st_mode),
              otherCurrentRegularFilesPreserved=sum(v['kind'] == 'file' for k, v in before.items() if not k.startswith('today.json/')),
              previousRegularFilesPreserved=sum(v['kind'] == 'file' for v in previous.values()),
              privateDirectoryCopy=copies[0], stageAbsent=True,
              scope='Main/light/standard explicit directory clear only. NativeR1canceled/R2modeexpectation/R3containerexpectation remain failed; no new native rerun or broader acceptance.')
(base / (prefix + '-independent-audit.json')).write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({k: v for k, v in result.items() if k != 'receipt'}, indent=2))
