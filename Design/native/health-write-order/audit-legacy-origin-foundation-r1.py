"""Read-only independent audit of retained synthetic origin-value fixtures."""
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
data = report.read_bytes()
result = json.loads(data)
assert len(result['checks']) == 57 and all(row['passed'] for row in result['checks'])
root = Path(result['retainedRoot'])
assert re.fullmatch(r'Lumen-legacy-origin-[A-F0-9-]{36}', root.name)
assert stat.S_ISDIR(root.lstat().st_mode) and not root.is_symlink()
rows, suites = {}, []
sha = lambda value: hashlib.sha256(value).hexdigest()
for parent, directories, files in os.walk(root, followlinks=False):
    for name in directories + files:
        path = Path(parent) / name
        facts = path.lstat()
        row = {'mode': facts.st_mode, 'inode': facts.st_ino, 'device': facts.st_dev,
               'size': facts.st_size, 'mtimeNS': facts.st_mtime_ns}
        if stat.S_ISLNK(facts.st_mode):
            row['linkDestination'] = os.readlink(path)
        elif stat.S_ISREG(facts.st_mode):
            assert facts.st_size <= 64_000
            value = path.read_bytes()
            row.update(bytes=len(value), sha256=sha(value), base64=base64.b64encode(value).decode())
        else:
            assert stat.S_ISDIR(facts.st_mode)
        rows[str(path.relative_to(root))] = row
assert len(result['retainedFixtures']) == 3
for fixture in result['retainedFixtures']:
    domain = fixture['domain']
    assert domain in ['meals', 'workouts', 'goals']
    directory = root / domain
    assert str(directory) == fixture['root']
    facts = directory.lstat()
    assert stat.S_ISDIR(facts.st_mode)
    assert facts.st_ino == fixture['rootInode'] and facts.st_dev == fixture['rootDevice']
    for kind in ['data', 'string']:
        value = (directory / ('retained-' + kind + '-origin.json')).read_bytes()
        assert value == base64.b64decode(fixture[kind + 'Envelope'], validate=True)
        envelope = json.loads(value)
        assert set(envelope) == {'schemaVersion', 'domain', 'key', 'type', 'payload', 'sha256'}
        assert envelope['schemaVersion'] == 1 and envelope['domain'] == domain
        assert envelope['key'] == fixture['key'] == 'lumen.health.' + domain + '.v1'
        raw = base64.b64decode(envelope['payload'], validate=True)
        assert sha(raw) == envelope['sha256']
        if kind == 'data':
            assert envelope['type'] == 'data'
            assert raw == base64.b64decode(fixture['finalValueBase64'], validate=True)
        else:
            assert envelope['type'] == 'stringUTF16LE'
            assert raw.decode('utf-16le') == 'synthetic old value e\u0301 🫖'
    suite = fixture['suite']
    assert re.fullmatch(r'com\.dbakp\.lumen\.synthetic\.legacy-origin\.[A-F0-9-]{36}', suite)
    plist = Path.home() / 'Library/Preferences' / (suite + '.plist')
    facts = plist.lstat()
    assert stat.S_ISREG(facts.st_mode) and facts.st_size <= 64_000
    stored = plistlib.loads(plist.read_bytes())
    assert set(stored) == {fixture['key']}
    assert isinstance(stored[fixture['key']], bytes)
    assert stored[fixture['key']] == base64.b64decode(fixture['finalValueBase64'], validate=True)
    suites.append({'suite': suite, 'key': fixture['key'], 'path': str(plist),
                   'storedType': 'plist Data', 'valueSHA256': sha(stored[fixture['key']]),
                   'plistSHA256': sha(plist.read_bytes())})
regular = [name for name, row in rows.items() if 'sha256' in row]
assert len(regular) == 6
output.write_text(json.dumps({'status': 'PASS six live envelopes/three exact synthetic persistent Data keys',
                             'report': report.name, 'reportSHA256': sha(data), 'root': str(root),
                             'entries': rows, 'suites': suites, 'checkedAt': time.time(),
                             'scope': 'Read-only host plist/type/value and lstat/root/file audit. No Foundation suite reread, native recovery/transaction/LocalStore.standard integration or deletion.'}, indent=2) + '\n')
print('PASS live6exactprovenancefiles/3rootidentities/3persistentData keys; fixtures retained')
