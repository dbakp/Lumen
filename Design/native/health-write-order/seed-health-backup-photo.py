"""Seed only the three checked small synthetic inputs in a dedicated simulator."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import stat

p = argparse.ArgumentParser()
p.add_argument('--device', choices=['main', 'compact'], required=True)
p.add_argument('--inputs', type=Path, required=True)
a = p.parse_args()
device = {'main': 'AF849DEA-DF34-4B0E-9FC1-3E45DCBE8481',
          'compact': '922E011C-3895-4DB1-9C9A-1D3A977226CF'}[a.device]
names = ['Lumen-backup-health-photo-encrypted.lumenbackup', 'Lumen-backup-health-photo-legacy.json']
manifest = json.loads((a.inputs / 'health-backup-photo-manifest.json').read_text())
assert set(manifest['files']) == set(names)
root = Path.home() / 'Library/Developer/CoreSimulator/Devices' / device / 'data/Containers/Shared/AppGroup'
providers = []
for metadata in root.glob('*/.com.apple.mobile_container_manager.metadata.plist'):
    assert not metadata.is_symlink() and not metadata.parent.is_symlink()
    if plistlib.loads(metadata.read_bytes()).get('MCMMetadataIdentifier') == 'group.com.apple.FileProvider.LocalStorage':
        providers.append(metadata.parent / 'File Provider Storage')
assert len(providers) == 1, 'Dedicated simulator Files provider must already exist'
folder = providers[0]
assert not folder.is_symlink()
folder.mkdir(exist_ok=True)
assert stat.S_ISDIR(folder.lstat().st_mode)
readable = folder / '00 Lumen readable checks'
assert not readable.is_symlink()
readable.mkdir(exist_ok=True)
assert stat.S_ISDIR(readable.lstat().st_mode)
rows = []
for name in names:
    source = a.inputs / name
    assert stat.S_ISREG(source.lstat().st_mode)
    data = source.read_bytes()
    assert len(data) == int(manifest['files'][name]['bytes']) and len(data) < 256 * 1024
    assert hashlib.sha256(data).hexdigest() == manifest['files'][name]['sha256']
    target = (readable if name.startswith('Lumen-readable-') else folder) / name
    if target.exists() or target.is_symlink():
        assert stat.S_ISREG(target.lstat().st_mode) and target.read_bytes() == data, 'Never overwrite different existing Files content'
    else:
        shutil.copyfile(source, target)
    assert target.read_bytes() == data
    rows.append({'input': str(source), 'seeded': str(target), 'bytes': len(data),
                 'sha256': hashlib.sha256(data).hexdigest()})
base = Path(__file__).resolve().parent
(base / ('health-backup-photo-' + a.device + '-seed.json')).write_text(json.dumps({
    'status': 'two exact synthetic photo archives seeded; no other files generated or removed',
    'device': device, 'files': rows,
    'verifierSHA256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
}, indent=2) + '\n')
print('Seeded', sum(r['bytes'] for r in rows), 'bytes across', len(rows), 'checked inputs on', a.device)
