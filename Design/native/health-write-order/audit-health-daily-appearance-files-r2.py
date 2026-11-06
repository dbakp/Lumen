"""Read-only verification of the live simulator tree before the next fixture reset."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import struct
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--prefix', required=True)
args = parser.parse_args()
base = Path(__file__).resolve().parent
prefix = args.prefix
match = re.fullmatch(r'health-daily-appearance-(compact|main)-(normal|dark|largest)-r[1-9][0-9]*', prefix)
assert match
phone, mode = match.groups()
device, pixels = {
    'compact': ('922E011C-3895-4DB1-9C9A-1D3A977226CF', (750, 1334)),
    'main': ('AF849DEA-DF34-4B0E-9FC1-3E45DCBE8481', (1206, 2622)),
}[phone]
sha = lambda data: hashlib.sha256(data).hexdigest()
audit_path = base / (prefix + '-host-audit.json')
audit = json.loads(audit_path.read_text())
assert audit['fullFlowHostTerminalChecksPassed'] and audit['producerExitCode'] == 0
assert audit['fullDetailsRequiredPrefixes'] == 133 and audit['privateCopies'] == 2
assert audit['phone'] == phone and audit['mode'] == mode
group = Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', device,
                                     'com.dbakp.lumen', 'group.com.dbakp.lumen'], text=True).strip())
for root, expected in [(group / 'LumenData', audit['after']),
                       (group / 'LumenData.previous', audit['previousAfter'])]:
    assert root.is_dir() and not root.is_symlink()
    actual = {}
    for folder, directories, names in os.walk(root, followlinks=False):
        assert not any((Path(folder) / name).is_symlink() for name in directories)
        for name in names:
            path = Path(folder) / name
            facts = path.lstat()
            assert stat.S_ISREG(facts.st_mode) and not path.is_symlink()
            data = path.read_bytes()
            key = str(path.relative_to(root))
            actual[key] = dict(bytes=len(data), sha256=sha(data),
                               base64=base64.b64encode(data).decode(),
                               mode=stat.S_IMODE(facts.st_mode), inode=facts.st_ino)
            assert actual[key] == expected[key], key
    assert actual == expected
sdk_path = base / (prefix + '-sdk-query.json')
sdk = json.loads(sdk_path.read_text())
current = json.loads((group / 'LumenData/today.json').read_text())
assert current == sdk['metrics']
assert len(current['readings']) == 18 and current['excludesLumenNutrition'] is True
assert audit['previousAfter'] == audit['previousBefore']
assert len(audit['before']) == 16 and len(audit['previousBefore']) == 9
assert all(audit['after'][name] == facts for name, facts in audit['before'].items() if name != 'today.json')
assert not (group / audit['held']['stage']).exists()
cleanup = json.loads((group / 'Lumen-daily-cache-recorded-fixture.json').read_text())
assert cleanup == audit['exactFourSampleCleanup']
assert cleanup['remaining'] == 0 and cleanup['status'] == 'cleaned'
images = json.loads((base / (prefix + '-images.json')).read_text())
for row in images:
    data = (base / row['file']).read_bytes()
    assert row['source'] == audit['source']
    assert len(data) == row['bytes'] and sha(data) == row['sha256']
    assert Path(row['raw']).read_bytes() == data
    assert data[:8] == b'\x89PNG\r\n\x1a\n' and struct.unpack('>II', data[16:24]) == pixels
readbacks = json.loads((base / (prefix + '-readbacks.json')).read_text())
assert len(readbacks) == 1
for row in readbacks:
    data = (base / row['file']).read_bytes()
    assert row['source'] == audit['source']
    assert len(data) == row['bytes'] and sha(data) == row['sha256'] and Path(row['raw']).read_bytes() == data
result = dict(status='passed', source=audit['source'], phone=phone, mode=mode,
              auditorSHA256=sha(Path(__file__).read_bytes()), hostAuditSHA256=sha(audit_path.read_bytes()),
              actualSDKQuerySHA256=sha(sdk_path.read_bytes()),
              currentTreeFiles=len(audit['after']), previousTreeFiles=len(audit['previousAfter']),
              baselineCurrentPreservedExceptSnapshot=15, previousPreserved=9,
              actualCommitted18MetricsEqualSDK=True, actualStageAbsent=True, actualFixtureCleaned=True,
              originalPNGExactSourceExportHashes=len(images), nativePixelDimensions=list(pixels),
              nativeJSONExactSourceExportHashes=len(readbacks),
              scope='Independent live whole-tree/cleanup/export hash audit after terminal producers, before next simulator reset. Original-image review and broader acceptance remain separate.')
(base / (prefix + '-independent-files.json')).write_text(json.dumps(result, indent=2) + '\n')
print('PASS independent live tree,18SDK results,15other current/9prior files,cleanup and original exports:', phone, mode)
