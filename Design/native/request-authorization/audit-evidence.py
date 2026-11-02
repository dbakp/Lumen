"""Verify final scoped batch evidence; publication/cleanup remain separate."""
import gzip
import hashlib
import json
from pathlib import Path
import re
import runpy
import struct

base = Path(__file__).resolve().parent
repo = base.parents[2]
runpy.run_path(str(base / 'audit-progress.py'))

def read(name):
    return json.loads((base / name).read_text())

scope = read('acceptance-scope.json')
# Carry transport regression only when its actual implementation is unchanged.
old_transport_source = read('source-r7.json')['files']
for path in ['Lumen/Algorithms/ProviderReplyTransport.swift']:
    assert old_transport_source[path]['sha256'] == hashlib.sha256((repo / path).read_bytes()).hexdigest(), path
for path, digest in read(scope['applicationSource']).items():
    source = repo / path
    assert source.is_file() and not source.is_symlink()
    assert hashlib.sha256(source.read_bytes()).hexdigest() == digest, path
for path, facts in read(scope['runtimeSource'])['files'].items():
    assert hashlib.sha256((repo / path).read_bytes()).hexdigest() == facts['sha256'], path
logic = gzip.open(base / 'LogicR3.log.gz', 'rt').read().splitlines()
assert sum(line.startswith('PASS:') for line in logic) == 1619
assert not any(line.startswith('FAIL:') for line in logic)
assert read('logic-r3-boundary.json')['inputCount'] == 106
for path, facts in read('logic-r3-boundary.json')['files'].items():
    assert hashlib.sha256((repo / path).read_bytes()).hexdigest() == facts['sha256'], path
native = read('native-r9-report.json')
assert native['status'] == 'Request authorization checks passed' and len(native['observations']) == 19
assert native['packets'] == read('native-r9-host-readback.json') and len(native['packets']) == 9
for result in native['observations']:
    expected = result['mode'] in {'plan', 'local', 'overlap-plan'}
    assert result['savedConversation'] and result['eligible'] == expected
    assert result['automaticPlanCount'] == int(expected)
    assert result['automaticStepCount'] == (3 if expected else 0)
    if result['mode'] in {'withdraw', 'edit', 'remove', 'revert', 'history', 'lease', 'urgent', 'search-error', 'submission-withdraw', 'submission-personal'}:
        assert result['requestCount'] == 0
regression = read('personal-regression-r9-report.json')
assert regression['status'] == 'Personal context checks passed'
assert len(regression['checks']) == 43 and all(item['passed'] for item in regression['checks'])
assert regression['requests'] == read('personal-regression-r9-host-readback.json') and len(regression['requests']) == 8
for run in scope['finalUIRuns']:
    summary = read(run + '-summary.json')
    assert summary['passedTests'] == 1 and summary['failedTests'] == summary['skippedTests'] == 0
    files = read(run + '-file-readback.json')
    assert files['markedTitleChecked'] and files['noticeSavedAsNoteOnly'] and files['allDocumentsSharingOff']
    assert files['automaticPlans'] == 1 and files['genuinePlanSteps'] == 3
    receipts = read(run + '-host-readback.json')
    assert not any(counts.get('holdTimeouts', 0) for counts in receipts['routes'].values())
    assert len(receipts['personalAudit']) in {1, 2}
    for row in read(run + '/manifest.json'):
        assert hashlib.sha256((repo / row['repositoryPath']).read_bytes()).hexdigest() == row['sha256']
        assert row['source'] == files['source']
release = read(scope['release'])
assert release['status'] == 'passed' and release['applicationSources'] == scope['applicationSource']
assert release['minimumOSVersion'] == '18.0' and set(release['architectures'].split()) == {'arm64', 'x86_64'}
assert len(release['checkedDevelopmentMarkers']) == 71 and not release['foundDevelopmentMarkers']
assert len(release['debugPositiveControls']) == 22 and not release['bundledModelPackages']
assert release['auditorSHA256'] == hashlib.sha256((base / 'audit-release.py').read_bytes()).hexdigest()
reviewed = 0
for round_number in [1, 2, 3]:
    packet = read(f'review-packet-r{round_number}.json')
    audit = read(f'review-images-r{round_number}.json')
    inspection = audit['inspection']
    assert inspection['selected'] == inspection['opened'] == inspection['hashMatches'] == len(packet['images'])
    assert inspection['hashErrors'] == inspection['imageFailures'] == inspection['skips'] == 0
    expected = {row['repositoryPath']: row['sha256'] for row in packet['images']}
    original_paths = {row['path']: row['repositoryPath'] for row in packet['images']}
    for row in audit['images']:
        repository_path = row.get('repositoryPath') or original_paths[row['path']]
        assert expected[repository_path] == row['sha256']
        assert hashlib.sha256((repo / repository_path).read_bytes()).hexdigest() == row['sha256']
        assert row['hashResult'] == 'match' and row['imageResult'] == 'opened-original'
    reviewed += len(audit['images'])
assert re.search(r'(?im)^Done by the stop rule', (base / 'critique-r3.md').read_text())
for archive in base.glob('*.gz'):
    with gzip.open(archive, 'rb') as stream:
        while stream.read(1024 * 1024):
            pass
pngs = list(base.rglob('*.png'))
for path in pngs:
    assert not path.is_symlink()
    data = path.read_bytes()
    assert data[:8] == b'\x89PNG\r\n\x1a\n' and data[12:16] == b'IHDR'
    assert struct.unpack('>II', data[16:24]) in {(750, 1334), (1206, 2622)}
print(json.dumps(dict(status='passed', applicationInputs=208, runtimeSource=scope['runtimeSource'], logic=1619,
                      nativeScenarios=19, personalRegression=43, transportCasesCarriedAtUnchangedImplementation=15,
                      finalUIRuns=scope['finalUIRuns'], releaseMarkersAbsent=71, debugPositiveControls=22,
                      reviewedImageRecords=reviewed, retainedPNGs=len(pngs), scope='Local scoped batch acceptance; publication, cleanup and full product/device/provider/clinical/accessibility/distribution gates remain separate.')))
