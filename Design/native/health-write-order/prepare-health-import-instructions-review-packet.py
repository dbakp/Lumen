"""Collect current, fully root-inspected cases without declaring design acceptance."""
import hashlib
import json
from pathlib import Path

base = Path(__file__).resolve().parent
load = lambda name: json.loads((base / name).read_text())
sha = lambda data: hashlib.sha256(data).hexdigest()
ledger = load('health-import-instructions-matrix-r2-producer.json')
contract = load('health-import-instructions-matrix-r2-contract.json')
cases, images, readbacks = [], [], []
for result in ledger['results']:
    if result['driverExit'] != 0 or not result.get('attachmentsRetained'):
        continue
    prefix = result['prefix']
    png = load(prefix + '-images.json')
    native = load(prefix + '-readbacks.json')
    if not all(row.get('individuallyOpened') for row in png + native):
        continue
    summary = load(prefix + '-summary.json')
    host = load(prefix + '-host-audit.json')
    assert summary['passedTests'] == 1 and summary['failedTests'] == summary['skippedTests'] == 0
    assert host['source'] == ledger['source'] and host['build'] == ledger['build']
    assert host['producerExitCode'] == 0 and host['status'].startswith('passed:')
    for rows, target in [(png, images), (native, readbacks)]:
        for row in rows:
            assert row['source'] == ledger['source']
            p = base / row['file']
            data = p.read_bytes()
            assert len(data) == row['bytes'] and sha(data) == row['sha256']
            assert data == Path(row['raw']).read_bytes()
            target.append({**row, 'path': str(p), 'case': prefix})
    cases.append({**result, 'summaryPath': str(base / (prefix + '-summary.json')),
                  'hostAuditPath': str(base / (prefix + '-host-audit.json')),
                  'observationPath': str(base / (prefix + '-observations.json'))})
identity = lambda row: tuple(row[key] for key in ('device', 'format', 'mode'))
required = {identity(row) for row in contract['requiredCases']}
provided = [identity(row) for row in cases]
assert len(required) == contract['caseCount'] == 18
assert len(set(provided)) == len(provided) and set(provided) <= required
complete = set(provided) == required
packet = {'scope': 'Continuing denied-import Round2. All18actual131cases required before final scoring. '
                  'Current packet appends only fully root-inspected successful cases. Root flags '
                  'are not independent reviewer inspection flags. No aggregate design acceptance.',
          'source': ledger['source'], 'build': ledger['build'],
          'contract': 'health-import-instructions-matrix-r2-contract.json',
          'requiredCases': contract['requiredCases'], 'requiredCaseCount': 18,
          'providedCaseCount': len(cases), 'packetComplete': complete,
          'providedOriginalPNG': len(images), 'providedNativeJSON': len(readbacks),
          'earlierRound': 'critique-b43-denied-review-r1.md',
          'cases': cases, 'images': images, 'readbacks': readbacks,
          'repair': 'Keep native unstyled alert. Full instructions persist as semantic-primary Form '
                    'Text beside explicit chooser afterOK, cleared on fresh selection/readable close. '
                    '131targets actual readable notice, after130failed trial. Full type retained.',
          'limits': 'DEBUG Import read check/Read check overlays are simulator evidence, not product UI. '
                    'Some neighbor/chooser glyphs are obscured; no fullpage claim. Native alerts remain '
                    'system styled; judge complete persistent instructions across actual overlap scrolls. '
                    'VoiceOver/physical device/all-domain/fullproduct gates remain separate.'}
(base / 'health-import-instructions-review-r2-packet.json').write_text(json.dumps(packet, indent=2) + '\n')
outcome_path = base / 'health-import-instructions-matrix-r2-outcome.json'
outcome = json.loads(outcome_path.read_text())
outcome.update(status=('Current131all18native/host/root inspections complete; design review pending'
                       if complete else 'Current131partial native/host/root inspection; full18matrix and design review pending'),
               currentVerifiedCaseCount=len(cases), currentOriginalPNGOpened=len(images),
               currentNativeJSONRead=len(readbacks), verifiedCasePrefixes=[row['prefix'] for row in cases],
               reviewPacket='health-import-instructions-review-r2-packet.json',
               sameCriticRound2='Incremental same-critic Round2 underway; final scores/acceptance require all18cases and independent inspection.',
               scope=f'{len(cases)}/18 actual131cases passed native/host and root original inspection. '
                     'The original passedCases entry retains its extra first-case post-terminal22file audit; '
                     'verifiedCasePrefixes and currentCaseResults cover the current inspected set. '
                     'Fullcontracts/sixareas/remainingScope/eightgroups/product/VoiceOver/device/publication remain required.',
               currentCaseResults=[{'device':row['device'], 'format':row['format'], 'mode':row['mode'],
                                    'prefix':row['prefix'], 'driverExit':row['driverExit'],
                                    'summaryPath':row['summaryPath'], 'hostAuditPath':row['hostAuditPath'],
                                    'nativePassed':1, 'nativeFailed':0, 'nativeSkipped':0,
                                    'rootOriginalPNGOpened':sum(image['case']==row['prefix'] for image in images),
                                    'rootNativeJSONRead':sum(item['case']==row['prefix'] for item in readbacks)}
                                   for row in cases])
outcome_path.write_text(json.dumps(outcome, indent=2) + '\n')
print(len(cases), '/18cases;', len(images), 'original PNG;', len(readbacks), 'native JSON;complete=', packet['packetComplete'])
