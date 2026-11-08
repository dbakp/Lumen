"""Seed one canonical synthetic backup, retaining any partial attempt."""
import base64
import hashlib
import json
import os
from pathlib import Path
import plistlib
import stat
import subprocess
import time
import traceback

BASE = Path(__file__).resolve().parent
DEVICE = '5C4C4A6C-4D9E-4181-8794-E3925C1A7EA7'
NAME = 'Lumen-backup-health-matrix-two-legacy.json'
OUT = BASE / 'source224-reset-provider-context.json'
ATTEMPT = BASE / 'source224-reset-provider-seed-r2-attempt.json'
assert not OUT.exists() and not ATTEMPT.exists(), 'Never overwrite or silently retry an attempt'
state = {'status': 'PREPARING single synthetic input', 'device': DEVICE, 'started': time.time(),
         'targetCreated': False, 'steps': [], 'physicalDeviceActions': False}
target = None


def persist():
    ATTEMPT.write_text(json.dumps(state, indent=2) + '\n')


def identity(path):
    facts = path.lstat()
    assert stat.S_ISREG(facts.st_mode) and not path.is_symlink()
    return {key: getattr(facts, key) for key in ['st_ino', 'st_dev', 'st_mode', 'st_nlink', 'st_size', 'st_mtime_ns']}


persist()  # No simulator or provider mutation precedes the durable attempt.
try:
    diagnostic = json.loads((BASE / 'source224-fresh-diagnostic-r2-outcome.json').read_text())
    assert diagnostic['device'] == DEVICE and diagnostic['status'].startswith('PASS actual fresh-context')
    assert diagnostic['diagnostic']['classification'] == 'approved-initial'
    assert diagnostic['diagnostic']['credentialQueryOSStatus'] == -25300
    source = BASE / ('health-photo-matrix-r1-' + NAME)
    assert stat.S_ISREG(source.lstat().st_mode) and not source.is_symlink()
    data = source.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    assert len(data) == 4992 and digest == '80d236abd21b33a3d012d3287a0606e699d53ddc18a9e4263a635cb899629078'
    state['input'] = {'file': str(source), 'bytes': len(data), 'sha256': digest}; persist()
    root = Path.home() / 'Library/Developer/CoreSimulator/Devices' / DEVICE / 'data/Containers/Shared/AppGroup'
    assert root.is_dir() and not root.is_symlink()
    state['steps'].append('before Files launch'); persist()
    subprocess.run(['xcrun', 'simctl', 'launch', DEVICE, 'com.apple.DocumentsApp'], capture_output=True, check=True, timeout=90)
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
    state['providerCandidates'] = [str(path) for path in candidates]; persist()
    assert len(candidates) == 1
    folder = candidates[0]
    assert not folder.is_symlink()
    state['steps'].append('before provider folder creation'); persist()
    folder.mkdir(exist_ok=True)
    assert stat.S_ISDIR(folder.lstat().st_mode)
    target = folder / NAME
    state['target'] = str(target); persist()
    assert not os.path.lexists(target), 'Never replace existing Files content'
    descriptor = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    state['targetCreated'] = True
    try:
        state['createdIdentity'] = identity(target); persist()
        offset = 0
        while offset < len(data):
            written = os.write(descriptor, data[offset:])
            assert written > 0
            offset += written
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
    assert target.read_bytes() == data
    facts = identity(target)
    context = {'status': 'PASS seeded one exact synthetic backup; no existing content replaced',
               'device': DEVICE, 'input': str(source), 'seeded': str(target), 'bytes': len(data),
               'sha256': digest, 'identity': facts, 'freshDiagnostic': 'source224-fresh-diagnostic-r2-outcome.json',
               'seederSHA256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), 'checkedAt': time.time(),
               'physicalDeviceActions': False}
    state['contextIntended'] = context; persist()
    OUT.write_text(json.dumps(context, indent=2) + '\n')
    state['status'] = 'PASS seeded exact 4992-byte synthetic input'
except BaseException:
    state['status'] = 'FAILED single-input seed; preserve partial target, no retry or deletion'
    state['error'] = traceback.format_exc()
    raise
finally:
    try:
        if state['targetCreated'] and target is not None:
            facts = identity(target)
            assert facts['st_size'] <= 4992
            partial = target.read_bytes()
            state['actualTarget'] = {'identity': facts, 'bytes': len(partial),
                                     'sha256': hashlib.sha256(partial).hexdigest(),
                                     'base64': base64.b64encode(partial).decode()}
    except BaseException:
        state['targetInspectionError'] = traceback.format_exc()
    state['finished'] = time.time()
    try:
        persist()
    except BaseException:
        state['persistenceError'] = traceback.format_exc()
        emergency = BASE / 'source224-reset-provider-seed-r2-emergency.json'
        with emergency.open('x') as stream:
            json.dump(state, stream, indent=2)
            stream.write('\n')
        raise
print(state['status'], flush=True)
