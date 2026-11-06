"""Retain exact terminal XCTest attachment exports with source provenance."""
import argparse
import hashlib
import json
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('--stem', required=True)
p.add_argument('--prefix', required=True)
p.add_argument('--source', required=True)
p.add_argument('--png-dir', required=True)
p.add_argument('--json-dir', required=True)
p.add_argument('--include-failed-trial', action='store_true')
a = p.parse_args()
base = Path(__file__).resolve().parent
raw = Path('/tmp/LumenBatch43Checks')
summary = json.loads((raw / (a.stem + '-summary.json')).read_text())
assert (summary['result'] == 'Passed' and summary['failedTests'] == 0) or a.include_failed_trial
(base / (a.prefix + '-summary.json')).write_bytes((raw / (a.stem + '-summary.json')).read_bytes())
for suffix, directory in [('images', a.png_dir), ('readbacks', a.json_dir)]:
    directory = Path(directory)
    entries = []
    for case in json.loads((directory / 'manifest.json').read_text()):
        for metadata in case['attachments']:
            origin = directory / metadata['exportedFileName']
            data = origin.read_bytes()
            target = base / (a.prefix + '-' + origin.name)
            assert not target.exists() or target.read_bytes() == data
            target.write_bytes(data)
            entries.append({'file': target.name, 'raw': str(origin), 'metadata': metadata,
                            'test': case['testIdentifier'], 'source': a.source,
                            'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(),
                            'individuallyOpened': False})
    (base / (a.prefix + '-' + suffix + '.json')).write_text(json.dumps(entries, indent=2) + '\n')
    print(suffix, len(entries))
