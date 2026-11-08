"""Seed exactly one small canonical synthetic backup in the fresh reset device."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import stat
import subprocess
import time

BASE = Path(__file__).resolve().parent
DEVICE = '5C4C4A6C-4D9E-4181-8794-E3925C1A7EA7'
NAME = 'Lumen-backup-health-matrix-two-legacy.json'
OUT = BASE / 'source224-reset-provider-context.json'
assert not OUT.exists(), 'Do not overwrite a context'
diagnostic = json.loads((BASE / 'source224-fresh-diagnostic-r2-outcome.json').read_text())
assert diagnostic['device'] == DEVICE and diagnostic['status'].startswith('PASS actual fresh-context')
assert diagnostic['diagnostic']['classification'] == 'approved-initial'
assert diagnostic['diagnostic']['credentialQueryOSStatus'] == -25300
source = BASE / ('health-photo-matrix-r1-' + NAME)
assert stat.S_ISREG(source.lstat().st_mode) and not source.is_symlink()
data = source.read_bytes()
digest = hashlib.sha256(data).hexdigest()
assert len(data) == 4992 and digest == '80d236abd21b33a3d012d3287a0606e699d53ddc18a9e4263a635cb899629078'
root = Path.home() / 'Library/Developer/CoreSimulator/Devices' / DEVICE / 'data/Containers/Shared/AppGroup'
assert root.is_dir() and not root.is_symlink()
subprocess.run(['xcrun', 'simctl', 'launch', DEVICE, 'com.apple.DocumentsApp'], capture_output=True, check=True)
deadline = time.monotonic() + 30
while True:
    candidates = []
    for metadata in root.glob('*/.com.apple.mobile_container_manager.metadata.plist'):
        assert not metadata.is_symlink() and not metadata.parent.is_symlink()
        if plistlib.loads(metadata.read_bytes()).get('MCMMetadataIdentifier') == 'group.com.apple.FileProvider.LocalStorage':
            candidates.append(metadata.parent / 'File Provider Storage')
    if candidates or time.monotonic() >= deadline:
        break
    time.sleep(0.1)
assert len(candidates) == 1, 'Require exactly one local Files provider in this new device'
folder = candidates[0]
assert not folder.is_symlink()
folder.mkdir(exist_ok=True)
assert stat.S_ISDIR(folder.lstat().st_mode)
target = folder / NAME
assert not os.path.lexists(target), 'Never replace existing Files content'
descriptor = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
try:
    assert os.write(descriptor, data) == len(data)
    os.fsync(descriptor)
finally:
    os.close(descriptor)
assert target.read_bytes() == data
facts = target.lstat()
identity = {key: getattr(facts, key) for key in ['st_ino', 'st_dev', 'st_mode', 'st_nlink', 'st_size', 'st_mtime_ns']}
OUT.write_text(json.dumps({'status': 'PASS seeded one exact synthetic backup; no existing content replaced',
    'device': DEVICE, 'input': str(source), 'seeded': str(target), 'bytes': len(data), 'sha256': digest,
    'identity': identity, 'freshDiagnostic': 'source224-fresh-diagnostic-r2-outcome.json',
    'seederSHA256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), 'checkedAt': time.time(),
    'physicalDeviceActions': False}, indent=2) + '\n')
print('Seeded exactly 4992 synthetic bytes in the fresh dedicated simulator', flush=True)
