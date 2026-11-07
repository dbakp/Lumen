"""Read-only no-follow byte/identity audit of retained synthetic baseline cases."""
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import sys
import tempfile

report_path, output = map(Path, sys.argv[1:])
assert not output.exists()
report = json.loads(report_path.read_text())
root = Path(report['temporaryRoot'])
assert re.fullmatch(r'Lumen-unavailable-origins-[A-F0-9-]{36}', root.name)
assert root.parent.resolve() == Path(tempfile.gettempdir()).resolve()
assert root.is_dir() and not root.is_symlink()

def snapshot(area):
    result = {}
    def visit(path, name):
        facts = path.lstat()
        kind = stat.S_IFMT(facts.st_mode)
        row = {'kind': str(kind), 'inode': str(facts.st_ino), 'device': str(facts.st_dev),
               'mode': str(facts.st_mode), 'size': str(facts.st_size),
               'modifiedSeconds': str(facts.st_mtime_ns // 10**9),
               'modifiedNanoseconds': str(facts.st_mtime_ns % 10**9)}
        if stat.S_ISLNK(facts.st_mode):
            row['linkDestination'] = os.readlink(path)
        elif stat.S_ISREG(facts.st_mode):
            descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
            try:
                opened = os.fstat(descriptor)
                assert stat.S_ISREG(opened.st_mode) and opened.st_size <= 128 * 1024
                assert (opened.st_dev, opened.st_ino) == (facts.st_dev, facts.st_ino)
                chunks = []
                while chunk := os.read(descriptor, 65536):
                    chunks.append(chunk)
                    assert sum(map(len, chunks)) <= 128 * 1024
                data = b''.join(chunks)
                final = os.fstat(descriptor)
                assert (final.st_size, final.st_mtime_ns) == (facts.st_size, facts.st_mtime_ns)
            finally:
                os.close(descriptor)
            assert len(data) == facts.st_size
            row.update(base64=base64.b64encode(data).decode(), sha256=hashlib.sha256(data).hexdigest())
        else:
            assert stat.S_ISDIR(facts.st_mode), 'Unexpected special fixture path'
        result[name] = row
        if stat.S_ISDIR(facts.st_mode):
            for child in sorted(path.iterdir()):
                visit(child, name + '/' + child.name)
    visit(area, '.')
    return result

rows = []
for item in report['observations']:
    area = Path(item['areaPath'])
    assert area == root / item['case'] and not area.is_symlink()
    observed = snapshot(area)
    assert observed == item['afterPreparation'], item['case']
    rows.append({'case': item['case'], 'areaPath': str(area), 'liveEntriesVerified': len(observed),
                 'liveRegularFilesVerified': sum('base64' in row for row in observed.values()),
                 'exactBytesAndMetadata': True,
                 'treeSHA256': hashlib.sha256(json.dumps(observed, sort_keys=True).encode()).hexdigest()})
assert len(rows) == 5
assert set(path.name for path in root.iterdir()) == {item['case'] for item in report['observations']} | {'controls'}
assert snapshot(root / 'controls')['./meals.json']['base64'] == base64.b64encode(b'[]').decode()
result = {'status': 'PASS independent live retained fixture byte/identity audit',
          'reportSHA256': hashlib.sha256(report_path.read_bytes()).hexdigest(),
          'auditorSHA256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
          'temporaryRoot': str(root), 'observations': rows, 'controlsCurrentEmptyBytesExact': True,
          'cleanupPerformed': False,
          'scope': 'All five live final trees exact, including lstat/readlink and no-follow regular payloads. Only known owned root; no personal files, defaults or native UI accessed.'}
output.write_text(json.dumps(result, indent=2) + '\n')
print('Five live retained case trees independently byte/identity exact; fixture root kept')
