"""Cross-check retained host bytes against the actual native selected-copy taps."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import re

p = argparse.ArgumentParser()
p.add_argument('--prefix', required=True)
p.add_argument('--stem', required=True)
a = p.parse_args()
assert re.fullmatch(r'[A-Za-z0-9-]+', a.prefix)
assert re.fullmatch(r'[A-Za-z0-9-]+', a.stem)
base = Path(__file__).resolve().parent
raw = Path('/tmp/LumenBatch43Checks')
audit = json.loads((base / (a.prefix + '-host-audit.json')).read_text())
summary = json.loads((base / (a.prefix + '-summary.json')).read_text())
assert summary['passedTests'] == 1 and summary['failedTests'] == 0
log = (raw / (a.stem + '.log')).read_bytes()
taps = re.findall(r'Tap "healthRecoveryCopy-([A-Za-z0-9-]+)" Button', log.decode())
assert len(taps) >= 2 and len(set(taps)) == 1, taps
files = {}
for name, row in audit['files'].items():
    data = base64.b64decode(row['base64'], validate=True)
    assert len(data) == row['bytes']
    assert hashlib.sha256(data).hexdigest() == row['sha256']
    files[name] = data
receipts = [json.loads(data) for name, data in files.items()
            if name.startswith('.health-recovery-history/') and name.endswith('.json')]
assert len(receipts) == 1
receipt = receipts[0]
assert receipt['source'] == 'retained:' + taps[0]
assert files['water.json'] == files['.health-recovery/' + taps[0] + '/water.json']
assert receipt['recordDigests']['water.json'] == hashlib.sha256(files['water.json']).hexdigest()
assert receipt['domains'] == ['water']
assert json.loads(files['health-write-intent.json'])['events'] == []
outcome = {
    'status': 'passed', 'source': audit['source'], 'build': audit['build'],
    'selectedCopy': taps[0], 'nativeCopyTaps': len(taps), 'receipt': receipt,
    'nativeLogSHA256': hashlib.sha256(log).hexdigest(),
    'hostAuditSHA256': hashlib.sha256((base / (a.prefix + '-host-audit.json')).read_bytes()).hexdigest(),
    'verifierSHA256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    'scope': 'Exact retained host bytes and native tapped identity at this terminal synthetic water trial. No new live-container, all-domain, capacity, daemon or device claim.'
}
(base / (a.prefix + '-receipt-audit.json')).write_text(json.dumps(outcome, indent=2) + '\n')
print('PASS:', a.prefix, 'receipt matches native selected/reopened copy and exact installed water')
