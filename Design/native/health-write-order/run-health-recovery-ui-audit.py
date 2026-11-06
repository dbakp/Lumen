"""Independent final-case file readback after the dedicated synthetic UI tests.

This does not claim a host audit of every intermediate UI case or HealthKit.
It refuses to record a non-fixture water history and never mutates a simulator.
"""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import stat
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--source', required=True)
parser.add_argument('--build', required=True)
parser.add_argument('--trial', required=True)
parser.add_argument('--device', choices=['main', 'compact', 'both'], default='both')
args = parser.parse_args()
assert args.trial and all(c.isalnum() or c == '-' for c in args.trial)
base = Path(__file__).resolve().parent
repo = base.parents[2]
source = json.loads((base / args.source).read_text())
build = json.loads((base / args.build).read_text())
digest = lambda data: hashlib.sha256(data).hexdigest()
for name, facts in source['files'].items():
    assert digest((repo / name).read_bytes()) == facts['sha256'], name
for short, device in [('compact', '922E011C-3895-4DB1-9C9A-1D3A977226CF'),
                      ('main', 'AF849DEA-DF34-4B0E-9FC1-3E45DCBE8481')]:
    if args.device != 'both' and args.device != short:
        continue
    def container(kind):
        return Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', device,
                                             'com.dbakp.lumen', kind], text=True).strip())
    root = container('group.com.dbakp.lumen') / 'LumenData'
    assert digest((container('app') / 'Lumen').read_bytes()) == build['sha256']
    water = (root / 'water.json').read_bytes()
    records = json.loads(water)
    assert len(records) == 1 and records[0]['id'] == 'synthetic-review-water'
    assert records[0]['ml'] == 137 and records[0]['date'] == '2026-11-02T12:00:00Z'
    files = {}
    paths = list(root.glob('*.json')) + list((root / '.health-recovery').rglob('*'))
    paths += list((root / '.health-recovery-history').glob('*.json'))
    for path in paths:
        kind = path.lstat().st_mode
        if stat.S_ISDIR(kind):
            continue
        assert stat.S_ISREG(kind), path
        data = path.read_bytes()
        files[str(path.relative_to(root))] = {'bytes': len(data), 'sha256': digest(data),
                                              'base64': base64.b64encode(data).decode()}
    private_water = [(name, base64.b64decode(row['base64'])) for name, row in files.items()
                     if name.startswith('.health-recovery/') and name.endswith('/water.json')]
    assert len(private_water) == 2 and sum(data == water for _, data in private_water) == 1
    assert any(data == b'{"syntheticUnavailableWater":' for _, data in private_water)
    source_id = next(name.split('/')[1] for name, data in private_water if data == water)
    journal = json.loads((root / 'health-write-intent.json').read_bytes())
    assert journal['events'] == []
    provenance = [json.loads(base64.b64decode(row['base64'])) for name, row in files.items()
                  if name.startswith('.health-recovery/') and name.endswith('/device-intent.json')]
    assert provenance and all(row['owner'] == journal['owner'] and row['lifecycle'] != journal['lifecycle']
                              and row['events'] == [] for row in provenance)
    receipts = list((root / '.health-recovery-history').glob('*.json'))
    assert len(receipts) == 1
    receipt = json.loads(receipts[0].read_bytes())
    assert receipt['domains'] == ['water'] and receipt['recordDigests']['water.json'] == digest(water)
    assert receipt['source'] == 'retained:' + source_id
    outcome = {'status': 'independent actual UI post-relaunch files matched', 'source': args.source,
               'build': args.build, 'device': device, 'files': files,
               'scope': 'After final largest-text successful UI case: exact reviewed and damaged water bytes, '
                        'same owner/new lifecycle, empty Health intent and source-bound receipt. '
                        'Not a host audit of every intermediate UI case or actual HealthKit/device proof.'}
    (base / ('health-recovery-' + short + '-' + args.trial + '-host-audit.json')).write_text(json.dumps(outcome, indent=2) + '\n')
    print('PASS:', short, 'reviewed/damaged original bytes, source receipt and same-owner empty intent')
