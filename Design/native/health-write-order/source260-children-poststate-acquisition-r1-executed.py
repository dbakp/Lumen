"""Read-only bounded post-case synthetic LumenData capture before the next reset.

This is parent supplemental evidence, not a pre-action protection checkpoint.
"""
from pathlib import Path
import base64, gzip, hashlib, json, os, stat, time
B = Path(__file__).resolve().parent
d = json.loads((B / 'retained-owner-source260-children-r1-driver.json').read_bytes())
assert d['case'] == 'children' and d['nativeExit'] == 0 and d['errors'] == []
group = Path(base64.b64decode(d['containerQuery']['stdout'], validate=True).decode().strip())
assert '/Devices/5C4C4A6C-4D9E-4181-8794-E3925C1A7EA7/' in str(group)
root = group / 'LumenData'; assert root.is_dir() and not root.is_symlink()
fields = ['st_dev', 'st_ino', 'st_mode', 'st_nlink', 'st_size', 'st_mtime_ns']
rows = {}; total = 0
for parent, directories, files in os.walk(root, followlinks=False):
    for name in directories:
        path = Path(parent) / name; assert not path.is_symlink() and stat.S_ISDIR(path.lstat().st_mode)
    for name in files:
        path = Path(parent) / name; before = path.lstat()
        assert stat.S_ISREG(before.st_mode) and not path.is_symlink() and before.st_size <= 8 * 1024**2
        raw = path.read_bytes(); after = path.lstat()
        assert all(getattr(before, key) == getattr(after, key) for key in fields)
        total += len(raw); assert total <= 16 * 1024**2
        relative = str(path.relative_to(root))
        rows[relative] = {'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest(),
                          'base64': base64.b64encode(raw).decode(), 'identity': {key: getattr(after, key) for key in fields}}
data = lambda name: base64.b64decode(rows[name]['base64'], validate=True)
receipts = [name for name in rows if name.startswith('.health-recovery-history/') and name.endswith('.json')]
assert len(receipts) == 1; receipt = json.loads(data(receipts[0]))
assert receipt['domains'] == ['meals'] and receipt['source'].startswith('retained:')
copy_id = receipt['source'][len('retained:'):]; assert Path(copy_id).name == copy_id and copy_id not in ['', '.', '..']
source_meals = json.loads(data('.health-recovery/' + copy_id + '/meals.json')); current_meals = json.loads(data('meals.json'))
assert len(source_meals) == len(current_meals) == 2
assert hashlib.sha256(data('meals.json')).hexdigest() == receipt['recordDigests']['meals.json']
original_ids = {meal['photoID'] for meal in source_meals}; current_ids = {meal['photoID'] for meal in current_meals}
assert len(original_ids) == len(current_ids) == 1
old_id, new_id = next(iter(original_ids)), next(iter(current_ids))
for before, after in zip(source_meals, current_meals):
    expected = dict(before, photoID=new_id)
    assert json.dumps(expected, sort_keys=True, separators=(',', ':')) == json.dumps(after, sort_keys=True, separators=(',', ':'))
source_photo = '.health-recovery/' + copy_id + '/photos/' + old_id + '.jpg'
new_photo = 'photos/' + new_id + '.jpg'
assert data(source_photo) == data(new_photo) and hashlib.sha256(data(new_photo)).hexdigest() == receipt['photoDigests'][new_photo]
expected_failed = {'water.json': b'{"syntheticUnavailableWater":', 'workouts.json': b'{', 'goals.json': b'{', 'today.json': b'{'}
assert all(data(name) == expected for name, expected in expected_failed.items())
private_failed_meals = [name for name in rows if name.startswith('.health-recovery/') and name.endswith('/meals.json') and data(name) == b'{']
assert len(private_failed_meals) == 1
record = {'source': 'durable-source-r260.json', 'device': '5C4C4A6C-4D9E-4181-8794-E3925C1A7EA7',
          'root': str(root), 'files': rows, 'receiptPath': receipts[0], 'receipt': receipt,
          'checks': ['poststate receipt meals-only and current meal digest exact', 'two source/current meal records differ only by shared photo remap',
                     'actual new photo bytes equal retained source and receipt digest', 'four unselected health files equal frozen fixture failed bytes',
                     'one permanent private copy contains exact one-byte failed original meals'],
          'scope': 'One actual post-case synthetic tree, captured after UI/native/checker completion. No pre-action host raw snapshot, inode continuity, every protected-file-before/after comparison, fixed-defaults/active flags or journal semantic/backend-wide acceptance. Read-only; no source/simulator writes or reset.', 'checkedAt': time.time()}
raw = json.dumps(record, sort_keys=True).encode(); name = 'source260-children-poststate-raw-r1.json.gz'
assert not (B / name).exists(); (B / name).write_bytes(gzip.compress(raw, mtime=0))
report = {'status': 'SUPPORTED limited actual poststate integrity, broader backend remains open', 'source': record['source'],
          'capture': name, 'decodedBytes': len(raw), 'decodedSHA256': hashlib.sha256(raw).hexdigest(),
          'fileCount': len(rows), 'totalFileBytes': total, 'checks': record['checks'], 'scope': record['scope'], 'checkedAt': time.time()}
(B / 'source260-children-poststate-acquisition-r1.json').write_text(json.dumps(report, indent=2) + '\n'); print(report['status'], len(rows), total)
