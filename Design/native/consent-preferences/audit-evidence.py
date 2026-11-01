"""Check retained source/evidence identities; never starts a build or changes app data."""
import gzip
import hashlib
import json
from pathlib import Path
import struct

repo = Path(__file__).resolve().parents[3]
evidence = Path(__file__).resolve().parent

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

for name in ['application-source-r14.json', 'source-r23.json', 'logic-source-r3.json']:
    inputs = json.loads((evidence / name).read_text())
    for relative, expected in inputs.items():
        path = repo / relative
        assert path.is_file() and not path.is_symlink(), relative
        assert digest(path) == expected, relative
    print(name, len(inputs), 'current inputs match')

boundary = json.loads((evidence / 'app13-to-app14-boundary.json').read_text())
prior = (evidence / boundary['retainedPriorUI']).read_bytes()
current = (repo / 'Lumen/Views/PersonalContextView.swift').read_bytes()
assert hashlib.sha256(prior).hexdigest() == boundary['priorUISHA256']
assert hashlib.sha256(current).hexdigest() == boundary['currentUISHA256']
old_map = json.loads((evidence / 'application-source-r13.json').read_text())
new_map = json.loads((evidence / 'application-source-r14.json').read_text())
assert old_map['Lumen/Views/PersonalContextView.swift'] == boundary['priorUISHA256']
assert [key for key in old_map if old_map[key] != new_map[key]] == ['Lumen/Views/PersonalContextView.swift']
old_branch = prior.decode().split('case .discard:', 1)[1].split('case .saving', 1)[0]
new_branch = current.decode().split('case .discard:', 1)[1].split('case .saving', 1)[0]
assert old_branch == new_branch
assert hashlib.sha256(new_branch.encode()).hexdigest() == boundary['unchangedDiscardBranchSHA256']

records = 0
paths = {}
for manifest in sorted(evidence.glob('*/captures.json')):
    for row in json.loads(manifest.read_text()):
        path = evidence / row['retainedPath']
        assert path.is_file() and not path.is_symlink(), path
        assert digest(path) == row['sha256'], path
        for key in ['applicationSourceMap', 'selectedSourceMap']:
            if key in row:
                assert (evidence / row[key]).is_file(), row[key]
        data = path.read_bytes()
        assert data[:8] == b'\x89PNG\r\n\x1a\n', path
        width, height = struct.unpack('>II', data[16:24])
        assert (width, height) in [(1206, 2622), (750, 1334)], (path, width, height)
        paths[row['retainedPath']] = dict(path=row['retainedPath'], sha256=row['sha256'], bytes=len(data), width=width, height=height)
        records += 1

# A stopped-helper investigation also retains one manual native viewport.
# Include separately named PNGs in the complete retained-file inventory.
for path in sorted(evidence.rglob('*.png')):
    relative = str(path.relative_to(evidence))
    if relative in paths:
        continue
    assert not path.is_symlink(), path
    data = path.read_bytes()
    assert data[:8] == b'\x89PNG\r\n\x1a\n', path
    width, height = struct.unpack('>II', data[16:24])
    assert (width, height) in [(1206, 2622), (750, 1334)], (path, width, height)
    paths[relative] = dict(path=relative, sha256=hashlib.sha256(data).hexdigest(), bytes=len(data), width=width, height=height, source='manual native viewport; source/stop boundary in README and gutter-helper-stop.json')

for row in json.loads((evidence / 'producer-logs.json').read_text()):
    data = gzip.decompress((evidence / row['retained']).read_bytes())
    assert len(data) == row['uncompressedBytes'], row['name']
    assert hashlib.sha256(data).hexdigest() == row['sha256'], row['name']

for name in ['native-backend-provenance.json', 'native-backend-provenance-r12.json']:
    proof = json.loads((evidence / name).read_text())
    report_name = 'native-backend-report-r12.json' if '-r12' in name else 'native-backend-report.json'
    path = evidence / report_name
    assert digest(path) == proof['sha256'], path
    report = json.loads(path.read_text())
    assert report['status'] == 'Preference checks passed'
    assert len(report['checks']) == 16 and all(row['passed'] for row in report['checks'])
    assert [len(row['pending']) for row in report['snapshots']] == [1, 1, 1, 0]

inventory = sorted(paths.values(), key=lambda row: row['path'])
(evidence / 'png-inventory.json').write_text(json.dumps(dict(attachmentRecords=records, retainedPNGFiles=len(paths), uniqueHashes=len({row['sha256'] for row in inventory}), files=inventory), indent=2) + '\n')
print(records, 'capture records;', len(paths), 'retained PNG files; compact logs and both backend reports match')
