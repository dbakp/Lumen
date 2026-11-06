"""Record completed human image/JSON inspections, then audit immutable evidence.

Invoke only for a case whose entire image manifest was actually opened and whose
native JSON readbacks were actually read. Passing this script is not a design
score, a VoiceOver check, or aggregate acceptance of the eighteen-case contract.
"""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import re

parser = argparse.ArgumentParser()
parser.add_argument('--reviewed-prefix', action='append', required=True)
args = parser.parse_args()
base = Path(__file__).resolve().parent
load = lambda name: json.loads((base / name).read_text())
digest = lambda data: hashlib.sha256(data).hexdigest()
source = 'durable-source-r131.json'
driver = (base / 'run-health-import-denied-matrix.py').read_bytes()
assert gzip.decompress((base / 'health-import-denied-matrix-driver-r1.py.gz').read_bytes()) == driver

for prefix in args.reviewed_prefix:
    match = re.fullmatch(r'health-import-denied-matrix-(main|compact)-(legacy|encrypted|readable)-(normal|dark|largest)-r9', prefix)
    assert match, prefix
    device, kind, mode = match.groups()
    summary = load(prefix + '-summary.json')
    host = load(prefix + '-host-audit.json')
    assert summary['passedTests'] == 1 and summary['failedTests'] == summary['skippedTests'] == 0
    assert host['producerExitCode'] == 0 and host['source'] == source
    assert host['verifierSHA256'] == digest(driver)
    assert host['before'] == host['after'] and len(host['before']) == 12
    assert host['previousBefore'] == host['previousAfter'] and len(host['previousBefore']) == 10
    assert host['errorCleanup']['rootsAbsent'] and host['finalCleanup']['rootsAbsent']
    assert host['permissionFault']['actualHostOpenErrno'] == 13
    expected_appearance = 'light' if mode == 'normal' else 'dark'
    expected_type = 'accessibility5' if mode == 'largest' else 'large'
    native = []
    for suffix in ['images', 'readbacks']:
        name = prefix + '-' + suffix + '.json'
        rows = load(name)
        assert rows
        for row in rows:
            assert row['source'] == source and Path(row['file']).name == row['file']
            assert row['file'].startswith(prefix + '-')
            retained = (base / row['file']).read_bytes()
            assert retained == Path(row['raw']).read_bytes()
            assert len(retained) == row['bytes'] and digest(retained) == row['sha256']
            raw_manifest = json.loads((Path(row['raw']).parent / 'manifest.json').read_text())
            matches = [(group['testIdentifier'], item) for group in raw_manifest
                       for item in group['attachments']
                       if item['exportedFileName'] == Path(row['raw']).name]
            assert matches == [(row['test'], row['metadata'])], row['file']
            if suffix == 'readbacks':
                value = json.loads(retained)
                assert value['format'] == kind
                assert value['observedTraits'] == 'Import read check; appearance=' + expected_appearance + '; type=' + expected_type
                assert value['expectedAppearance'] == expected_appearance and value['expectedType'] == expected_type
                assert value['errorFrames']['actionHittable']
                assert 'Lumen couldn’t read this file. Keep the original and choose it again. No records were imported.' in value['errorMessage']
                assert 'LumenBackupWork-v1-' not in value['errorMessage'] and 'selected-backup' not in value['errorMessage']
                native.append(value)
            row['individuallyOpened'] = True
        (base / name).write_text(json.dumps(rows, indent=2) + '\n')
    assert len(native) == 2
    assert {row['scope'] for row in native} == {'selected-original-copy-denied-read', 'selected-original-denied-error-layout'}
    final = next(row for row in native if row['scope'] == 'selected-original-copy-denied-read')
    assert final['retryAmount'] == '246 mL' and final['retryChoiceOff'] and not final['recoveryCommitted']
    assert final['idleAfterFailureSeconds'] == final['idleAfterFinalParentSeconds'] == 4
    assert final['persistentReadInstructionsVerified'] and final['persistentReadInstructionsClearedOnRetry']
    print('REVIEW RECORDED ' + device + ' ' + kind + ' ' + mode)

ledger = load('health-import-instructions-matrix-r2-producer.json')
manifest = load('health-backup-r1-logs.json')
known = {row['raw'] for row in manifest['entries']}
for result in ledger['results']:
    if not (result['producerTerminal'] and result.get('attachmentsRetained')):
        continue
    for suffix in ['', 'Driver', 'PNGExport', 'JSONExport']:
        raw = Path('/tmp/LumenBatch43Checks') / (result['stem'] + suffix + '.log')
        data = raw.read_bytes()
        if str(raw) in known:
            row = next(row for row in manifest['entries'] if row['raw'] == str(raw))
            assert len(data) == row['rawBytes'] and digest(data) == row['rawSHA256']
            continue
        retained = raw.name + '.gz'
        (base / retained).write_bytes(gzip.compress(data, mtime=0))
        manifest['entries'].append({'raw': str(raw), 'retained': retained,
            'rawBytes': len(data), 'rawSHA256': digest(data)})
        known.add(str(raw))
for row in manifest['entries']:
    data = gzip.decompress((base / row['retained']).read_bytes())
    assert len(data) == row['rawBytes'] and digest(data) == row['rawSHA256']
manifest['status'] = '131current sequential18case instruction matrix continues; explicit human-inspected cases recorded separately. Terminal logs decoded/hash verified; no aggregate appearance/VoiceOver/critic/full product acceptance. Full goal active; Batch43unpublished.'
(base / 'health-backup-r1-logs.json').write_text(json.dumps(manifest, indent=2) + '\n')
print('TERMINAL LOGS ' + str(len(manifest['entries'])))
