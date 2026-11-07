"""Read-only exact live-file and synthetic persistent-value backend audit."""
import base64
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import stat
import sys
import time

base = Path(__file__).resolve().parent
report = base / sys.argv[1]
output = base / sys.argv[2]
raw = report.read_bytes()
data = json.loads(raw)
assert len(data['checks']) == 117 and all(x['passed'] for x in data['checks'])
assert len(data['cases']) == 13
outer = Path(data['retainedRoot'])
assert re.fullmatch(r'Lumen-legacy-transaction-[A-F0-9-]{36}', outer.name)
assert stat.S_ISDIR(outer.lstat().st_mode)
sha = lambda b: hashlib.sha256(b).hexdigest()
cases, total_files, total_values, total_envelopes, embedded_rows = [], 0, 0, 0, 0
for case in data['cases']:
    root = Path(case['root'])
    assert root.parent == outer and root.name == case['label']
    assert stat.S_ISDIR(root.lstat().st_mode) and not root.is_symlink()
    for group in ['before', 'after']:
        for encoded in case[group].values():
            base64.b64decode(encoded, validate=True)
            embedded_rows += 1
    expected = case['after']
    actual, envelopes = {}, []
    for parent, directories, files in os.walk(root, followlinks=False):
        for name in directories:
            assert stat.S_ISDIR((Path(parent) / name).lstat().st_mode)
        for name in files:
            file = Path(parent) / name
            facts = file.lstat()
            assert stat.S_ISREG(facts.st_mode) and facts.st_size <= 128 * 1024
            path = str(file.relative_to(root))
            value = file.read_bytes()
            assert value == base64.b64decode(expected[path], validate=True), path
            actual[path] = {'bytes': len(value), 'sha256': sha(value), 'inode': facts.st_ino,
                            'device': facts.st_dev, 'mtimeNS': facts.st_mtime_ns}
            if name.startswith('legacy-origin-'):
                envelope = json.loads(value)
                assert set(envelope) == {'domain', 'key', 'schemaVersion', 'type', 'payload', 'sha256'}
                assert envelope['schemaVersion'] == 1
                origin = base64.b64decode(envelope['payload'], validate=True)
                assert sha(origin) == envelope['sha256']
                typed = case['currentDefaults'][envelope['key']]
                assert origin == base64.b64decode(typed['base64'], validate=True)
                assert (envelope['type'], typed['type']) in [('data', 'Data'), ('stringUTF16LE', 'StringUTF16LE')]
                manifest = json.loads((file.parent / 'manifest.json').read_bytes())
                assert manifest['version'] == 2
                assert manifest['legacyOrigins'][envelope['domain']] == {'file': name, 'sha256': sha(value)}
                assert not (file.parent / (envelope['domain'] + '.json')).exists()
                envelopes.append(path)
    assert set(actual) == set(expected)
    suite = case['suite']
    assert re.fullmatch(r'com\.dbakp\.lumen\.synthetic\.legacy-transaction\.[A-F0-9-]{36}', suite)
    file = Path.home() / 'Library/Preferences' / (suite + '.plist')
    facts = file.lstat()
    assert stat.S_ISREG(facts.st_mode) and facts.st_size < 64_000
    values = plistlib.loads(file.read_bytes())
    assert set(values) == set(case['currentDefaults'])
    for key, expected_value in case['currentDefaults'].items():
        assert key in ['lumen.health.meals.v1', 'lumen.health.workouts.v1', 'lumen.health.goals.v1']
        if expected_value['type'] == 'Data':
            assert isinstance(values[key], bytes)
            value = values[key]
        else:
            assert expected_value['type'] == 'StringUTF16LE' and isinstance(values[key], str)
            value = values[key].encode('utf-16le')
        assert value == base64.b64decode(expected_value['base64'], validate=True)
        total_values += 1
    if case['label'].startswith('reject-'):
        assert case['before'] == case['after']
        assert not any(p.startswith('.health-recovery-history/') for p in actual)
    total_files += len(actual)
    total_envelopes += len(envelopes)
    cases.append({'label': case['label'], 'root': str(root), 'files': actual, 'suite': suite,
                  'persistentTypes': {k: v['type'] for k, v in case['currentDefaults'].items()},
                  'provenanceFiles': envelopes})
assert total_envelopes == 8 and total_values == 14
output.write_text(json.dumps({'status': 'PASS 13 live backend cases/exact files/14typed defaults/8v2 provenance values',
                             'report': report.name, 'reportSHA256': sha(raw), 'embeddedRowsDecoded': embedded_rows,
                             'liveFilesExact': total_files, 'actualPersistentKeys': total_values,
                             'exactLegacyEnvelopes': total_envelopes, 'cases': cases, 'checkedAt': time.time(),
                             'scope': 'Host lstat/file-byte/current persistent plist values only. No independent historical String/defaults or prior-before maps, no metadata continuity, Foundation suite reread, LocalStore.standard/write lock, UI/native acceptance or cleanup.'}, indent=2) + '\n')
print(json.dumps({'status': 'PASS', 'cases': 13, 'embeddedRowsDecoded': embedded_rows,
                  'liveFilesExact': total_files, 'typedPersistentKeys': total_values, 'legacyEnvelopes': total_envelopes}))
