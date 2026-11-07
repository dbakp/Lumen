"""Read-only audit of retained old-defect or fixed synthetic boundary cases."""
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
source = base / sys.argv[1]
output = base / sys.argv[2]
raw = source.read_bytes()
report = json.loads(raw)
assert len(report['cases']) == (5 if report['expectingDefects'] else 6)
assert len(report['checks']) == (19 if report['expectingDefects'] else 22)
assert all(row['passed'] for row in report['checks'])
outer = Path(report['retainedRoot'])
assert re.fullmatch(r'Lumen-legacy-boundaries-[A-F0-9-]{36}', outer.name)
sha = lambda b: hashlib.sha256(b).hexdigest()
file_count, stage_count, records = 0, 0, []

def scan(root, expected):
    global file_count
    assert stat.S_ISDIR(root.lstat().st_mode)
    actual = {}
    for parent, directories, files in os.walk(root, followlinks=False):
        for name in directories:
            assert stat.S_ISDIR((Path(parent) / name).lstat().st_mode)
        for name in files:
            file = Path(parent) / name
            facts = file.lstat()
            assert stat.S_ISREG(facts.st_mode) and facts.st_size < 128 * 1024
            relative = str(file.relative_to(root))
            value = file.read_bytes()
            assert value == base64.b64decode(expected[relative], validate=True)
            actual[relative] = {'bytes': len(value), 'sha256': sha(value), 'inode': facts.st_ino,
                                'device': facts.st_dev, 'mtimeNS': facts.st_mtime_ns}
    assert set(actual) == set(expected)
    file_count += len(actual)
    return actual

for case in report['cases']:
    root = Path(case['root'])
    assert root.parent == outer and root.name == case['fault']
    current = scan(root, case['after'])
    stages = {}
    for path, expected in case['stageFilesAfter'].items():
        stage = Path(path)
        assert stage.resolve().parent == outer.resolve()
        assert stage.name.startswith(root.name + '.restore-')
        stages[path] = scan(stage, expected)
        stage_count += 1
    actual_stages = list(outer.glob(root.name + '.restore-*'))
    assert {x.resolve() for x in actual_stages} == {Path(x).resolve() for x in stages}
    suite = case['suite']
    assert re.fullmatch(r'com\.dbakp\.lumen\.synthetic\.legacy-boundary\.[A-F0-9-]{36}', suite)
    plist = Path.home() / 'Library/Preferences' / (suite + '.plist')
    assert stat.S_ISREG(plist.lstat().st_mode)
    values = plistlib.loads(plist.read_bytes())
    assert set(values) == {case['key']} == {'lumen.health.meals.v1'}
    assert isinstance(values[case['key']], bytes)
    assert values[case['key']] == base64.b64decode(case['currentDefaultsData'], validate=True)
    if case['fault'].startswith('post-stage'):
        assert case['populatedStageFaultActivated'] and not case['prepared'] and not case['committed']
        assert case['before'] == case['after']
        assert len(stages) == (1 if report['expectingDefects'] else 0)
        if case['fault'] == 'post-stage-cancel':
            assert case['errorKind'] == 'CancellationError'
    else:
        assert case['prepared'] and case['committed'] == report['expectingDefects']
        assert not stages
        if report['expectingDefects']:
            assert case['catalogHasIncompleteCopy'] and case['before'] != case['after']
            assert 'meals.json' in current
            name = 'legacy-origin-unexpected.json' if case['fault'] == 'extra-origin' else 'meals.json'
            assert any(k.startswith('.health-recovery/') and k.endswith('/' + name) for k in current)
        else:
            assert not case['catalogHasIncompleteCopy'] and case['before'] == case['after']
    records.append({'fault': case['fault'], 'current': current, 'stages': stages,
                    'suite': suite, 'persistedDataSHA256': sha(values[case['key']])})
assert stage_count == (3 if report['expectingDefects'] else 0)
output.write_text(json.dumps({'status': 'PASS read-only actual boundary fixture audit', 'report': source.name,
                             'reportSHA256': sha(raw), 'expectingDefects': report['expectingDefects'],
                             'actualFilesExact': file_count, 'actualUnownedStages': stage_count,
                             'actualPersistentDataKeys': len(report['cases']), 'cases': records, 'checkedAt': time.time(),
                             'scope': 'Actual retained root/stage bytes and the known synthetic plist Data values only. Baseline defects are unaccepted synthetic results, no product/native recovery or continuous metadata/allrace guarantee.'}, indent=2) + '\n')
print(json.dumps({'status': 'PASS', 'actualFilesExact': file_count, 'actualUnownedStages': stage_count,
                  'persistentKeys': len(report['cases']), 'expectingDefects': report['expectingDefects']}))
