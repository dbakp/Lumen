"""Verify original dimensions; retain, rather than rewrite, the R3 report defect."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct

parser = argparse.ArgumentParser()
parser.add_argument('--prefix', required=True)
args = parser.parse_args()
base = Path(__file__).resolve().parent
match = re.fullmatch(r'health-daily-appearance-(main|compact)-(normal|dark|largest)-r[1-9][0-9]*', args.prefix)
assert match
phone, mode = match.groups()
logical, pixels = ((402, 874), (1206, 2622)) if phone == 'main' else ((375, 667), (750, 1334))
sha = lambda data: hashlib.sha256(data).hexdigest()
host_path = base / (args.prefix + '-host-audit.json')
host = json.loads(host_path.read_bytes())
assert host['fullFlowHostTerminalChecksPassed'] and host['producerExitCode'] == 0
assert (host['phone'], host['mode']) == (phone, mode)
images = json.loads((base / (args.prefix + '-images.json')).read_bytes())
readbacks = json.loads((base / (args.prefix + '-readbacks.json')).read_bytes())
assert len(readbacks) == 1 and images
for row in images + readbacks:
    data = (base / row['file']).read_bytes()
    assert len(data) == row['bytes'] and sha(data) == row['sha256']
    assert row['source'] == host['source']
native = json.loads((base / readbacks[0]['file']).read_bytes())
assert (native['logicalWidth'], native['logicalHeight']) == logical
assert native['mainPhoneRequested'] is (phone == 'main')
assert native['requestedAppearance'] == ('light' if mode == 'normal' else 'dark')
assert native['largestDetailsRequested'] is (mode == 'largest')
for row in images:
    data = (base / row['file']).read_bytes()
    assert data[:8] == b'\x89PNG\r\n\x1a\n'
    assert struct.unpack('>II', data[16:24]) == pixels
assert host['nativePixelDimensions'] == list(pixels)
original_dimensions_match = host['nativeLogicalDimensions'] == list(logical)
if not original_dimensions_match:
    # Only the diagnosed R3 reporting defect is accepted as a known discrepancy.
    # Any different producer, dimensions or capture height must fail this audit.
    driver = base / 'health-daily-appearance-driver-r3.py'
    assert host['driverSHA256'] == sha(driver.read_bytes())
    assert host['nativeLogicalDimensions'] == [logical[0], '52.0']
    assert all(abs(value - 52) < 1e-8 for value in native['valueHeights'].values())
result = dict(
    status='PASS independently verified nativeJSON and every original PNG dimension; original host discrepancy retained' if not original_dimensions_match else 'PASS nativeJSON, every original PNG and host dimensions agree',
    source=host['source'], phone=phone, mode=mode,
    auditorSHA256=sha(Path(__file__).read_bytes()),
    hostAudit=host_path.name, hostAuditSHA256=sha(host_path.read_bytes()),
    nativeJSON=readbacks[0]['file'], nativeJSONSHA256=readbacks[0]['sha256'],
    originalPNGVerified=len(images), originalNativeJSONVerified=1,
    actualNativeLogicalDimensions=list(logical), actualPNGDimensions=list(pixels),
    originalHostDimensionField=host['nativeLogicalDimensions'],
    originalHostDimensionFieldMatchesNative=original_dimensions_match,
    originalEvidenceRewritten=False,
    scope='Independent archived dimension check and explicit reporting correction only. Does not replace live-file, SDK, metadata, visual, six-case or broader product gates.')
(base / (args.prefix + '-dimensions-audit.json')).write_text(json.dumps(result, indent=2) + '\n')
print(result['status'], len(images), 'original PNG')
