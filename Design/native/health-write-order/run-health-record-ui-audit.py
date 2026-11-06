"""Independent read-only host audit of the dedicated synthetic record fixture.

Host files describe the final case only. Optional UI attachments contain actual
AX readbacks from individual cases; identical fixture content is not a claim of
host file inspection at every intermediate transition.
"""
import argparse
import base64
import hashlib
from io import BytesIO
import json
from pathlib import Path
import re
import stat
import subprocess
from PIL import Image

parser = argparse.ArgumentParser()
parser.add_argument('--source', required=True)
parser.add_argument('--build', required=True)
parser.add_argument('--device', choices=['main', 'compact'], required=True)
parser.add_argument('--mode', choices=['records', 'oriented', 'invalid', 'empty'], required=True)
parser.add_argument('--trial', required=True)
parser.add_argument('--ui-readback', action='append', default=[])
parser.add_argument('--confidence-readback', action='append', default=[])
args = parser.parse_args()
assert re.fullmatch(r'[a-zA-Z0-9-]+', args.trial)
base = Path(__file__).resolve().parent
repo = base.parents[2]
device = {'main': 'AF849DEA-DF34-4B0E-9FC1-3E45DCBE8481',
          'compact': '922E011C-3895-4DB1-9C9A-1D3A977226CF'}[args.device]
source = json.loads((base / args.source).read_text())
build = json.loads((base / args.build).read_text())
sha = lambda data: hashlib.sha256(data).hexdigest()
for name, facts in source['files'].items():
    assert sha((repo / name).read_bytes()) == facts['sha256'], name
def container(kind):
    return Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', device,
                                         'com.dbakp.lumen', kind], text=True).strip())
assert sha((container('app') / 'Lumen').read_bytes()) == build['sha256']
assert build['source'] == args.source
root = container('group.com.dbakp.lumen') / 'LumenData'
previous = root.with_suffix('.previous')
water = json.loads((previous / 'water.json').read_bytes())
assert (len(water) == 0 if args.mode == 'empty' else len(water) == 2 and water[0]['id'] == 'synthetic-detailed-water')
meals = json.loads((previous / 'meals.json').read_bytes())
workouts = json.loads((previous / 'workouts.json').read_bytes())
goals = json.loads((previous / 'goals.json').read_bytes())
day = json.loads((previous / 'today.json').read_bytes())
assert [m['id'] for m in meals] == ['synthetic-first-meal', 'synthetic-second-meal']
assert [w['id'] for w in workouts] == ['synthetic-unknown-energy', 'synthetic-known-zero']
assert workouts[0]['energyKnown'] is False and workouts[0]['activeCalories'] == 0
assert workouts[1]['energyKnown'] is True and workouts[1]['activeCalories'] == 0
assert all(goals.get(key) is None for key in ['weightKg', 'heightCm', 'age'])
assert day['readings']['steps']['components'][0]['value'] == 0
assert day['readings']['water']['components'] == []
assert day['readings']['water']['healthQuery']['outcome'] == 'noData'
assert day['readings']['activeEnergy']['components'][0]['isEstimate'] is True
copies = list((root / '.health-recovery').iterdir())
assert len(copies) == 1 and copies[0].is_dir() and not copies[0].is_symlink()
copy = copies[0]
for domain in ['water', 'meals', 'workouts', 'goals', 'today']:
    assert (root / (domain + '.json')).read_bytes() == (b'{"syntheticUnavailableWater":' if domain == 'water' else b'{')
    assert (copy / (domain + '.json')).read_bytes() == (previous / (domain + '.json')).read_bytes()
photo = (previous / 'photos/synthetic-review-photo.jpg').read_bytes()
assert (copy / 'photos/synthetic-review-photo.jpg').read_bytes() == photo
photo_metadata = {'bytes': len(photo), 'sha256': sha(photo)}
if args.mode == 'invalid':
    assert photo == b'synthetic-not-a-jpeg'
    photo_metadata['type'] = 'deliberately invalid synthetic bytes'
else:
    with Image.open(BytesIO(photo)) as image:
        assert image.format == 'JPEG'
        photo_metadata.update(type='JPEG', width=image.width, height=image.height,
                              orientation=image.getexif().get(274, 1))
        assert photo_metadata['orientation'] == (6 if args.mode == 'oriented' else 1)
        image.verify()
journal = (root / 'health-write-intent.json').read_bytes()
assert journal == (previous / 'health-write-intent.json').read_bytes()
assert journal == (copy / 'device-intent.json').read_bytes()
assert json.loads(journal)['events'] == []
assert not list((root / '.health-recovery-history').glob('*.json'))
readbacks = []
for name in args.ui_readback:
    path = Path(name)
    observed = json.loads(path.read_bytes())
    assert observed['longNote'] == water[0]['note']
    labels = {'water-amount': 'Amount', 'water-statement': 'Statement', 'water-source-id': 'Conversation ID',
              'workout-unknown': 'Active energy', 'workout-known-zero': 'Active energy',
              'workout-heart-rate': 'Average heart rate', 'workout-import': 'Filename', 'workout-warning': 'Text',
              'food-protein': 'Protein', 'food-score': 'Saved confidence score',
              'target-missing-4': 'Weight', 'target-missing-5': 'Height', 'target-missing-6': 'Age',
              'day-water-unknown': 'Saved value', 'day-water-query': 'Outcome',
              'day-recorded-zero': 'Saved value', 'day-estimate': 'Saved value',
              'day-aggregation': 'Aggregation', 'day-estimate-flag': 'Estimate',
              'day-query': 'Outcome', 'day-cache-weight': 'Stored weight'}
    values = {}
    for key, label in labels.items():
        assert observed[key].startswith(label + ', '), key
        values[key] = observed[key][len(label) + 2:]
    assertions = {
        'water-amount': '137 mL', 'water-statement': water[0]['logOrigin']['statement'],
        'water-source-id': water[0]['logOrigin']['conversationID'],
        'workout-unknown': 'Energy not provided', 'workout-known-zero': '0 kcal',
        'workout-import': workouts[1]['importOrigin']['filename'],
        'workout-warning': workouts[1]['importOrigin']['warnings'][0],
        'target-missing-4': 'Not provided', 'target-missing-5': 'Not provided', 'target-missing-6': 'Not provided',
        'day-water-unknown': 'No reading', 'day-water-query': 'No samples returned',
        'day-recorded-zero': '0 steps', 'day-aggregation': 'Reported day',
        'day-estimate-flag': 'Yes', 'day-query': 'Samples found'
    }
    for key, expected in assertions.items():
        assert values[key] == expected, key
    numeric = {'workout-heart-rate': f"{workouts[1]['avgHR']} bpm",
               'food-protein': f"{meals[0]['items'][0]['proteinG']} g",
               'food-score': str(meals[0]['items'][0]['confidence']),
               'day-estimate': f"About {day['readings']['activeEnergy']['components'][0]['value']} kcal",
               'day-cache-weight': f"{day['weightKg']} kg"}
    for key, expected in numeric.items():
        assert expected == values[key].replace(',', '.'), key
    if 'day-query-checked' in observed:
        # Independent Foundation formatting of the actual saved timestamp.
        # Context is the test process's observed locale/time zone, not a fixed
        # English date literal or the application's rendered label.
        formatter = '''import Foundation
let f = DateFormatter()
f.locale = Locale(identifier: CommandLine.arguments[1])
f.timeZone = TimeZone(identifier: CommandLine.arguments[2])!
f.dateStyle = .medium; f.timeStyle = .long
let date = ISO8601DateFormatter().date(from: CommandLine.arguments[3])!
print(f.string(from: date))
'''
        expected_date = subprocess.check_output([
            'swift', '-e', formatter, observed['context-locale'], observed['context-timeZone'],
            str(day['readings']['activeEnergy']['healthQuery']['checkedAt'])
        ], text=True).strip()
        assert observed['day-query-checked'] == 'Checked at, ' + expected_date
    readbacks.append({'raw': str(path), 'sha256': sha(path.read_bytes()), 'values': observed})
confidence_readbacks = []
for name in args.confidence_readback:
    path = Path(name)
    observed = json.loads(path.read_bytes())
    prefix = 'Saved confidence score, '
    assert observed['score'].startswith(prefix)
    assert observed['score'][len(prefix):].replace(',', '.') == str(meals[0]['items'][0]['confidence'])
    assert observed['footer'] == 'This is a saved estimate score, not a measure of accuracy.'
    confidence_readbacks.append({'raw': str(path), 'sha256': sha(path.read_bytes()), 'values': observed})
files = {}
for prefix, directory in [('current', root), ('previous', previous)]:
    for path in directory.rglob('*'):
        kind = path.lstat().st_mode
        if stat.S_ISDIR(kind):
            continue
        assert stat.S_ISREG(kind), path
        data = path.read_bytes()
        assert len(data) < 1_000_000  # Only the fixed, small synthetic fixture.
        files[prefix + '/' + str(path.relative_to(directory))] = {
            'bytes': len(data), 'sha256': sha(data), 'base64': base64.b64encode(data).decode()}
result = {'status': 'actual final-case synthetic files and supplied UI readbacks matched',
          'source': args.source, 'build': args.build, 'device': device, 'mode': args.mode,
          'photo': photo_metadata, 'files': files, 'uiReadbacks': readbacks,
          'confidenceReadbacks': confidence_readbacks,
          'verifierSHA256': sha(Path(__file__).read_bytes()),
          'scope': 'Final-case current originals remain damaged, previous/private records and photo bytes match, '
                   'same unchanged empty device intent, no recovery receipt. Individual UI text attachments '
                   'are compared with the deterministic final fixture content; not per-transition host audits, '
                   'HealthKit, physical-device or complete recovery acceptance.'}
(base / f'health-record-{args.device}-{args.trial}-host-audit.json').write_text(json.dumps(result, indent=2) + '\n')
print('PASS:', args.device, args.mode, 'actual record/photo/original/intent files,',
      len(readbacks), 'full UI readbacks and', len(confidence_readbacks), 'confidence/footer readbacks')
