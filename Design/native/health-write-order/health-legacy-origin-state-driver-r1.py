"""Origin-aware genuine-error/Back/reselect host producer. Requires independent source review before execution; ordinary driver retained unchanged."""
import gzip
import plistlib
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import signal
import subprocess
import time
import traceback

p = argparse.ArgumentParser()
p.add_argument('--source', required=True)
p.add_argument('--build', required=True)
p.add_argument('--case', choices=['legacy', 'encrypted'], required=True)
p.add_argument('--trial', required=True)
p.add_argument('--origin', required=True, choices=['data','string'])
p.add_argument('--fault', choices=['missing','damaged'], required=True)
p.add_argument('--observe-source', action='store_true')
p.add_argument('--phone', choices=['main','compact'], default='main')
p.add_argument('--appearance', choices=['normal','dark','largest'], default='normal')
p.add_argument('--input-manifest', default='health-file-photo-matrix-r1-input-manifest.json')
p.add_argument('--inputs', default='health-file-photo-matrix-r1-inputs.json')
a = p.parse_args()
a.mode = "two"
a.observe_source = True
assert re.fullmatch(r'[A-Za-z0-9-]+', a.trial)
base = Path(__file__).resolve().parent
repo = base.parents[2]
raw = Path('/tmp/LumenBatch44Checks')
raw.mkdir(exist_ok=True)
device = {'main':'AF849DEA-DF34-4B0E-9FC1-3E45DCBE8481','compact':'922E011C-3895-4DB1-9C9A-1D3A977226CF'}[a.phone]
assert a.appearance=='normal' or (a.case=='encrypted' and a.fault=='missing'), 'Declared appearance supplements use missing encrypted only'
assert a.phone=='main' and a.appearance=='normal' and a.fault=='missing'
assert (a.case,a.origin) in [('legacy','data'),('encrypted','string')]
stem = 'HealthErrorState' + a.case.title() + a.trial
prefix = 'health-error-state-' + a.case + '-' + a.trial.lower()
ui_prefix = 'health-error-state-' + a.case
expected_name = ('Lumen-readable-health-matrix-' + a.mode + '.json') if a.case == 'readable' else ('Lumen-backup-health-matrix-' + a.mode + '-' + a.case + ('.lumenbackup' if a.case == 'encrypted' else '.json'))
matrix = json.loads((base / a.input_manifest).read_text())['cases'][a.mode]
result = raw / (stem + '.xcresult')
assert not result.exists()
source = json.loads((base / a.source).read_text())
build = json.loads((base / a.build).read_text())
digest = lambda data: hashlib.sha256(data).hexdigest()

def container(kind):
    return Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', device,
                                        'com.dbakp.lumen', kind], text=True).strip())

def identity():
    for name, row in {**source['files'],**source.get('fixtureInputs',{})}.items():
        assert digest((repo / name).read_bytes()) == row['sha256'], name
    assert build['source'] == a.source
    assert digest((container('app') / 'Lumen').read_bytes()) == build['sha256']
    test_binary = Path(build['testBinary'])
    assert test_binary.is_file() and digest(test_binary.read_bytes()) == build['testBinarySHA256']

def legacy_defaults(expected):
    assert expected['bundle']=='com.dbakp.lumen' and expected['kind']==a.origin
    path=container('data')/'Library/Preferences/com.dbakp.lumen.plist'
    facts=path.lstat();assert stat.S_ISREG(facts.st_mode) and not path.is_symlink() and facts.st_size<256*1024
    # Only known fixed synthetic keys are retained in reports, never all preferences.
    values=plistlib.loads(path.read_bytes());checked={}
    assert set(expected['values'])=={'meals','workouts'}
    for domain,row in expected['values'].items():
        assert row['key']=='lumen.health.'+domain+'.v1'
        value=values[row['key']]
        wanted=b'{synthetic persisted legacy origin damaged' if a.origin=='data' else 'Synthetic persisted old value e\u0301 🫖'.encode('utf-16-le')
        raw=value if isinstance(value,bytes) else value.encode('utf-16-le')
        assert (isinstance(value,bytes) if a.origin=='data' else isinstance(value,str))
        assert row['type']==('data' if a.origin=='data' else 'stringUTF16LE')
        assert raw==wanted==base64.b64decode(row['payload'],validate=True)
        checked[domain]={'key':row['key'],'type':row['type'],'bytes':len(raw),'sha256':digest(raw),'base64':row['payload']}
    return checked


def origin_events():
    path=container('group.com.dbakp.lumen')/'Lumen-legacy-origin-review-events.json'
    assert not path.is_symlink() and stat.S_ISREG(path.lstat().st_mode) and path.stat().st_size<64*1024
    rows=json.loads(path.read_bytes())['events']
    assert rows and all(re.fullmatch(r'[A-Fa-f0-9-]{36}',r['sessionID']) and r['event'] in ['open','ready','acquire','closed'] for r in rows)
    return rows


def legacy_copies(root):
    expected=checkpoint['legacyOrigins'];legacy_defaults(expected)
    copies=[]
    for path in (root/'.health-recovery').glob('*/manifest.json'):
        assert not path.is_symlink() and stat.S_ISREG(path.lstat().st_mode)
        manifest=json.loads(path.read_bytes())
        if manifest['version']!=2:continue
        assert manifest['domains']==['meals','workouts']
        assert set(manifest['legacyOrigins'])=={'meals','workouts'}
        directory=path.parent;envelopes={}
        for domain,row in expected['values'].items():
            descriptor=manifest['legacyOrigins'][domain]
            assert descriptor['file']=='legacy-origin-'+domain+'.json'
            envelope_file=directory/descriptor['file'];assert not envelope_file.is_symlink() and stat.S_ISREG(envelope_file.lstat().st_mode)
            data=envelope_file.read_bytes();assert digest(data)==descriptor['sha256']
            value=json.loads(data)
            assert set(value)=={'schemaVersion','domain','key','type','payload','sha256'}
            assert value['schemaVersion']==1 and value['domain']==domain and value['key']==row['key'] and value['type']==row['type'] and value['payload']==row['payload']
            assert value['sha256']==digest(base64.b64decode(value['payload'],validate=True))
            assert not (directory/(domain+'.json')).exists()
            envelopes[domain]={'file':str(envelope_file),'bytes':len(data),'sha256':digest(data),'envelope':value}
        copies.append({'manifest':manifest,'envelopes':envelopes})
    assert len(copies)==1
    return copies


def originals(group, checkpoint):
    root = group / 'LumenData'
    rows = {}
    for name, encoded in checkpoint['originals'].items():
        path = root / name
        assert stat.S_ISREG(path.lstat().st_mode)
        data = path.read_bytes()
        assert data == base64.b64decode(encoded, validate=True), name
        rows[name] = {'bytes': len(data), 'sha256': digest(data), 'base64': encoded}
    assert json.loads((root / 'water.json').read_bytes())[0]['ml'] == 137
    assert checkpoint['missing']==['meals.json','workouts.json']
    for name in checkpoint['missing']:
        try:(root/name).lstat();raise AssertionError('Missing target unexpectedly exists: '+name)
        except FileNotFoundError:pass
    legacy_defaults(checkpoint['legacyOrigins'])
    assert not list((root / '.health-recovery-history').glob('*.json'))
    return rows


sha = digest
def snapshot(root, current=True):
    assert root.is_dir() and not root.is_symlink()
    rows = {}
    total = 0
    for parent, directories, files in os.walk(root, followlinks=False):
        for name in directories:
            assert not (Path(parent) / name).is_symlink()
        for name in files:
            f = Path(parent) / name
            facts = f.lstat()
            assert stat.S_ISREG(facts.st_mode) and facts.st_size <= 256 * 1024, f
            data = f.read_bytes()
            total += len(data)
            assert total <= 2 * 1024 * 1024
            rows[str(f.relative_to(root))] = {'bytes': len(data), 'sha256': sha(data),
                                             'base64': base64.b64encode(data).decode()}
    if current:
        assert json.loads((root / 'water.json').read_bytes())[0]['ml'] == 137
        baseline = json.loads((root.parent / 'Lumen-health-backup-baseline.json').read_bytes())
        assert baseline['case'] == a.case
        for name, encoded in baseline['originals'].items():
            assert (root / name).read_bytes() == base64.b64decode(encoded)
    return rows


def owned_workspaces(pid):
    rows = {}
    for folder in (container('data') / 'tmp').glob('LumenBackupWork-v1-' + str(pid) + '-*'):
        assert folder.is_dir() and not folder.is_symlink()
        marker = folder / '.lumen-workspace-owner.json'
        assert marker.is_file() and not marker.is_symlink() and marker.stat().st_size < 1024
        owner = json.loads(marker.read_bytes())
        assert owner['pid'] == pid and owner['version'] == 1
        assert folder.name == 'LumenBackupWork-v1-' + str(pid) + '-' + owner['id']
        dirs = []
        for parent, children, files in os.walk(folder, followlinks=False):
            for name in children: assert not (Path(parent) / name).is_symlink()
            dirs.append(str(Path(parent).relative_to(folder)))
        rows[str(folder)] = {'owner': owner, 'files': snapshot(folder, current=False), 'directories': sorted(dirs)}
    return rows


def no_open_roots(pid, roots):
    result = subprocess.run(['lsof', '-nP', '-a', '-p', str(pid), '-Fn'], text=True, capture_output=True)
    assert result.returncode == 0, result.stderr
    for line in result.stdout.splitlines():
        if line.startswith('n'):
            path = line[1:]
            assert not any(path == root or path.startswith(root + '/') for root in roots), line
    return result.stdout



def verify_installed(root):
    actual = json.loads((root/'meals.json').read_bytes())
    expected = matrix['expectedMeals']
    assert len(actual)==len(expected)==2
    photo_digests = {}
    fresh = set()
    for row,wanted in zip(actual,expected):
        clean = row.copy(); original = wanted.copy()
        old_id = original.pop('photoID',None); new_id = clean.pop('photoID',None)
        assert clean==original,(clean,original)
        if old_id:
            assert new_id and new_id not in matrix['photos'] and new_id not in fresh
            fresh.add(new_id)
            assert re.fullmatch(r'[A-Fa-f0-9-]{36}',new_id)
            path=root/'photos'/(new_id+'.jpg');assert not path.is_symlink() and stat.S_ISREG(path.lstat().st_mode)
            data=path.read_bytes();wanted_photo=matrix['photos'][old_id]
            assert len(data)==wanted_photo['bytes'] and digest(data)==wanted_photo['sha256']
            photo_digests['photos/'+new_id+'.jpg']=digest(data)
        else:assert new_id is None
    photos=root/'photos'
    assert not photos.is_symlink()
    if photos.exists():
        assert sorted(p.name for p in photos.iterdir())==sorted(key.split('/')[-1] for key in photo_digests)
    else:assert not photo_digests
    assert json.loads((root/'workouts.json').read_bytes())==[]
    return photo_digests


started = time.time()
checkpoint = None
before = None
protected_before = None
previous_before = None
preservation_before = None
source_observations = []
protocol = None
held = None
released = None
success = None
not_now_observed = False
final_cleanup = None
host_failure = None
fault_observation = None
failed_boundary = None
repeated_failed_boundary = None
omission_not_now_boundary = None
def observe_source():
    if not a.observe_source or source_observations:
        return
    tag = ui_prefix + '-source'
    if ("Added attachment named '" + tag + "'") not in (raw / (stem + '.log')).read_text():
        return
    seed = json.loads((base / a.inputs).read_text())
    expected = next(row for row in seed['files'] if Path(row['input']).name == expected_name)
    for directory in (container('data') / 'tmp').glob('LumenBackupWork-v1-*'):
        marker = directory / '.lumen-workspace-owner.json'
        file = directory / 'selected-backup'
        try:
            if directory.is_symlink() or not stat.S_ISDIR(directory.lstat().st_mode):
                continue
            if not stat.S_ISREG(marker.lstat().st_mode) or marker.stat().st_size > 1024 or marker.stat().st_mtime < started:
                continue
            owner = json.loads(marker.read_bytes())
            if owner['version'] != 1 or owner['pid'] <= 0 or directory.name != 'LumenBackupWork-v1-' + str(owner['pid']) + '-' + owner['id']:
                continue
            try:
                os.kill(owner['pid'], 0)
            except ProcessLookupError:
                continue
            except PermissionError:
                pass  # EPERM still establishes that this PID exists.
            command = subprocess.check_output(['ps', '-p', str(owner['pid']), '-o', 'comm='], text=True).strip()
            if Path(command) != container('app') / 'Lumen':
                continue
            if not stat.S_ISREG(file.lstat().st_mode) or file.stat().st_size != expected['bytes']:
                continue
            data = file.read_bytes()
            provider = Path(expected['seeded'])
            assert provider.is_file() and not provider.is_symlink() and provider.read_bytes() == data
            if digest(data) != expected['sha256']:
                continue
            if not any(row['directory'] == str(directory) for row in source_observations):
                source_observations.append({'directory': str(directory), 'owner': owner,
                    'originalFileName': expected_name, 'bytes': len(data), 'sha256': digest(data),
                    'observedAfterNativeAttachment': tag, 'observedAtUnixTime': time.time()})
        except (FileNotFoundError, json.JSONDecodeError, subprocess.CalledProcessError):
            continue

def verify_provider():
    inputs = json.loads((base / a.inputs).read_text())
    original = next(row for row in inputs['files'] if Path(row['input']).name == expected_name)
    provider = Path(original['seeded'])
    facts = provider.lstat()
    assert stat.S_ISREG(facts.st_mode) and not provider.is_symlink()
    assert facts.st_ino == original['inode'] and facts.st_dev == original['device']
    assert facts.st_mode == original['mode'] and facts.st_mtime_ns == original['modifiedNS']
    assert digest(provider.read_bytes()) == original['sha256'] and facts.st_size == original['bytes']
    return {'originalProviderBytesAndIdentityExact': True, 'fileName': expected_name}


def metadata_tree(root):
    result = {}
    for parent, directories, files in os.walk(root, followlinks=False):
        for name in directories + files:
            path = Path(parent) / name
            facts = path.lstat()
            assert not path.is_symlink()
            result[str(path.relative_to(root))] = {key: getattr(facts, key) for key in ['st_ino', 'st_dev', 'st_mode', 'st_nlink', 'st_size', 'st_mtime_ns']}
    return result


def inject_photo_fault(root):
    global fault_observation
    if fault_observation is not None or not source_observations:
        return
    frame = source_observations[0]
    pid = frame['owner']['pid']
    workspaces = owned_workspaces(pid)
    assert len(workspaces) == (2 if a.case == 'legacy' else 1)
    expected_photo = matrix['photos']['synthetic-matrix-photo-a']
    targets = [(Path(folder) / name, folder) for folder, workspace in workspaces.items()
               for name, row in workspace['files'].items()
               if row['sha256'] == expected_photo['sha256'] and row['bytes'] == expected_photo['bytes']]
    assert len(targets) == 1, targets
    target, folder = targets[0]
    facts = target.lstat()
    assert stat.S_ISREG(facts.st_mode) and facts.st_nlink == 1 and not target.is_symlink()
    assert target.resolve().is_relative_to(Path(folder).resolve())
    parent = target.parent
    while parent != Path(folder):
        assert not parent.is_symlink() and stat.S_ISDIR(parent.lstat().st_mode)
        parent = parent.parent
    assert stat.S_IMODE(Path(folder).stat().st_mode) == 0o700
    assert snapshot(root, current=False) == protected_before
    assert snapshot(root.with_suffix('.previous'), current=False) == previous_before
    verify_provider()
    original_file=Path(frame['directory'])/'selected-backup'
    original_facts=original_file.lstat()
    assert stat.S_ISREG(original_facts.st_mode) and original_facts.st_nlink==1
    original_identity={key:getattr(original_facts,key) for key in ['st_ino','st_dev','st_mode','st_nlink','st_size','st_mtime_ns']}
    assert (original_facts.st_ino,original_facts.st_dev)!=(facts.st_ino,facts.st_dev)
    before_metadata = metadata_tree(root)
    prior_metadata = metadata_tree(root.with_suffix('.previous'))
    if a.fault == 'missing':
        target.unlink()
    else:
        # Refuse following links and preserve identity when damaging this extracted synthetic file.
        descriptor = os.open(target, os.O_WRONLY | os.O_NOFOLLOW)
        try:
            now = os.fstat(descriptor)
            assert now.st_ino == facts.st_ino and now.st_dev == facts.st_dev and now.st_nlink == 1
            os.ftruncate(descriptor, 0)
            assert os.write(descriptor, b'Synthetic invalid JPEG for extracted-resource verification\n') == len(b'Synthetic invalid JPEG for extracted-resource verification\n')
        finally:
            os.close(descriptor)
    after = owned_workspaces(pid)
    expected_workspaces = json.loads(json.dumps(workspaces))
    relative = str(target.relative_to(folder))
    if a.fault == 'missing':
        del expected_workspaces[folder]['files'][relative]
    else:
        expected_workspaces[folder]['files'][relative] = snapshot(Path(folder), current=False)[relative]
    assert after == expected_workspaces
    verify_provider()
    fault_observation = {'originalSelectedBackupPath':str(original_file),'originalSelectedBackupIdentity':original_identity,'kind': a.fault, 'target': str(target), 'targetRelativePath': relative,
        'beforeTarget': {key: getattr(facts, key) for key in ['st_ino','st_dev','st_mode','st_nlink','st_size','st_mtime_ns']},
        'originalPhoto': expected_photo, 'ownedBefore': workspaces, 'ownedAfter': after,
        'currentMetadataBefore': before_metadata, 'priorMetadataBefore': prior_metadata,
        'observedAfterNativeAttachment': ui_prefix + '-source', 'checkedAt': time.time()}


def verify_original_identity():
    assert fault_observation is not None
    file=Path(fault_observation['originalSelectedBackupPath'])
    facts=file.lstat()
    assert not file.is_symlink() and stat.S_ISREG(facts.st_mode)
    assert {key:getattr(facts,key) for key in fault_observation['originalSelectedBackupIdentity']} == fault_observation['originalSelectedBackupIdentity']
    assert digest(file.read_bytes())==source_observations[0]['sha256']
    return {'originalSelectedBackupBytesAndIdentityExact':True}


def verify_failed_boundary(root, tag):
    legacy_defaults(checkpoint['legacyOrigins'])
    assert fault_observation is not None
    assert snapshot(root, current=False) == protected_before
    assert snapshot(root.with_suffix('.previous'), current=False) == previous_before
    assert metadata_tree(root) == fault_observation['currentMetadataBefore']
    assert metadata_tree(root.with_suffix('.previous')) == fault_observation['priorMetadataBefore']
    assert not list(root.parent.glob('LumenData.restore-*'))
    assert not (root.parent / 'Lumen-health-cancel-checkpoint.json').exists()
    assert owned_workspaces(source_observations[0]['owner']['pid']) == fault_observation['ownedAfter']
    identity()
    verify_original_identity()
    verify_provider()
    return {'observedAfterNativeAttachment': tag, 'currentAndPriorBytesAndMetadataExact': True,
        'noReceiptStageOrCheckpoint': True, 'sourceWorkspacesExactExceptDeclaredPhotoFault': True,
        'checkedAt': time.time()}


def verify_preparation_tree(root):
    current=snapshot(root,current=False)
    assert previous_before is not None
    assert all(current.get(key)==value for key,value in protected_before.items())
    extra=set(current)-set(protected_before)
    assert extra and all(key.startswith('.health-recovery/') for key in extra), extra
    manifests=[k for k in extra if k.endswith('/manifest.json')]
    assert len(manifests)==1
    directory=Path(manifests[0]).parent
    manifest=json.loads(base64.b64decode(current[manifests[0]]['base64']))
    assert manifest['version']==1 and manifest['domains']==['meals','workouts'] and manifest['intent'] is True and manifest['photos'] is False
    expected={domain+'.json' for domain in manifest['domains']} | {'device-intent.json','manifest.json'}
    assert {Path(key).name for key in extra}==expected and all(Path(k).parent==directory for k in extra)
    for domain in manifest['domains']:assert current[str(directory/(domain+'.json'))]==previous_before[domain+'.json']
    assert current[str(directory/'device-intent.json')]==previous_before['health-write-intent.json']
    assert not list((root/'.health-recovery-history').glob('*.json'))
    return {'files':{key:current[key] for key in sorted(extra)},'manifest':manifest,'priorSelectedDomainsAndIntentExact':True}




"""Pending follow-on host helpers, not integrated or executed.
Uses the existing r3 verifier's globals/helpers. Future183+ setup/read-control
and a complete finite producer are required before this can verify any case.
"""

def assert_protected_state(root):
    legacy_defaults(checkpoint['legacyOrigins'])
    assert snapshot(root, current=False) == protected_before
    assert snapshot(root.with_suffix('.previous'), current=False) == previous_before
    assert metadata_tree(root) == fault_observation['currentMetadataBefore']
    assert metadata_tree(root.with_suffix('.previous')) == fault_observation['priorMetadataBefore']
    assert not list(root.parent.glob('LumenData.restore-*'))
    assert not list((root / '.health-recovery-history').glob('*.json'))
    verify_provider()
    identity()


def read_protocol(group):
    path = group / 'Lumen-health-read-checkpoint.json'
    assert not path.is_symlink() and stat.S_ISREG(path.lstat().st_mode)
    assert path.stat().st_mtime >= started and path.stat().st_size < 64 * 1024
    value = json.loads(path.read_bytes())
    assert value['root'] == str(group / 'LumenData')
    assert len(value['attempts']) == 1
    return value, value['attempts'][0]


def audit_actual_reader(group):
    value, record = read_protocol(group)
    old = source_observations[0]
    assert record['ordinal'] == 1 and record['scope'] == 'selected-record'
    assert record['readBoundary'] == 'selected-source'
    assert record['phase'] == 'held' and not record['uiCancelled']
    assert record['workerControlMatchesUI'] and record.get('descriptorCloseSucceeded') is None
    assert record.get('reviewOwnerClosed') is not True
    assert record['pid'] == old['owner']['pid']
    path = Path(fault_observation['originalSelectedBackupPath'])
    assert Path(record['file']) == path
    facts = path.lstat()
    assert stat.S_ISREG(facts.st_mode) and not path.is_symlink()
    assert facts.st_ino == record['inode'] and facts.st_size == record['size']
    assert 1 <= record['bytesRead'] <= min(65536, facts.st_size)
    assert Path(subprocess.check_output(['ps','-p',str(record['pid']),'-o','comm='],text=True).strip()) == container('app') / 'Lumen'
    scan = subprocess.check_output(['lsof','-nP','-a','-p',str(record['pid']),'-d',str(record['descriptor']),'-Ffni'],text=True)
    fields = scan.splitlines()
    assert any(x.startswith('f') and x[1:].rstrip('ruw') == str(record['descriptor']) for x in fields)
    assert any(x == 'i' + str(facts.st_ino) for x in fields)
    assert any(x.startswith('n') and Path(x[1:]).resolve() == path.resolve() for x in fields)
    verify_original_identity()
    assert_protected_state(group / 'LumenData')
    assert owned_workspaces(record['pid']) == fault_observation['ownedAfter']
    return {'protocol': value, 'record': record.copy(), 'lsof': scan,
            'actualDescriptorAndSourceBound': True, 'checkedAt': time.time()}


def send_read_message(group, record, acknowledge):
    assert re.fullmatch(r'[A-Fa-f0-9-]{36}', record['nonce'])
    target = group / 'Lumen-health-read-release.json'
    temp = target.with_name(target.name + '.' + record['nonce'] + '.state.tmp')
    assert not temp.exists()
    if target.exists():
        assert not target.is_symlink() and stat.S_ISREG(target.lstat().st_mode)
    message = {'nonce': record['nonce']}
    if acknowledge: message['acknowledgementOnly'] = True
    temp.write_text(json.dumps(message)); temp.replace(target)


def audit_back_after_failure(group, held_reader):
    protocol, record = read_protocol(group)
    assert record['nonce'] == held_reader['record']['nonce']
    assert record['file'] == held_reader['record']['file']
    assert record['phase'] == 'released' and not record['uiCancelled']
    assert record['descriptorCloseSucceeded'] is True
    assert record['reviewOwnerClosed'] is True
    root = group / 'LumenData'
    assert_protected_state(root)
    assert not (group / 'Lumen-health-cancel-checkpoint.json').exists()
    old = fault_observation['ownedAfter']
    existing = owned_workspaces(record['pid'])
    assert set(existing) <= set(old)
    for folder, workspace in existing.items(): assert workspace == old[folder]
    # Parent preview may still own files. Observe this honestly; do not equate
    # review-owner closure with all parent-owned roots already being deleted.
    return {'protocol': protocol, 'actualReviewOwnerClosed': True,
            'completedReaderDescriptorClosed': True, 'existingOldWorkspaces': existing,
            'absentOldWorkspaces': sorted(set(old) - set(existing)),
            'currentPriorBytesAndMetadataExact': True, 'noReceiptStageOrRecoveryWorker': True,
            'hostDeletedWorkspace': False, 'checkedAt': time.time()}


def audit_completed_reader(group, held_reader):
    protocol, record=read_protocol(group)
    assert record['nonce']==held_reader['record']['nonce'] and record['ordinal']==1
    assert record['file']==held_reader['record']['file'] and record['workerControlMatchesUI']
    assert record['phase']=='released' and not record['uiCancelled']
    assert record['descriptorCloseSucceeded'] is True and record.get('reviewOwnerClosed') is not True
    return {'protocol':protocol,'record':record.copy(),'sameActualReaderCompletedAndClosed':True,
        'reviewOwnerStillOpen':True,'checkedAt':time.time()}


def audit_fresh_reselected_source(group, back_observation):
    assert back_observation['actualReviewOwnerClosed']
    assert_protected_state(group / 'LumenData')
    old = source_observations[0]
    pid = old['owner']['pid']
    assert Path(subprocess.check_output(['ps','-p',str(pid),'-o','comm='],text=True).strip()) == container('app') / 'Lumen'
    owned = owned_workspaces(pid)
    assert len(owned) == (2 if a.case == 'legacy' else 1)
    assert not set(owned) & set(fault_observation['ownedAfter'])
    assert all(not Path(folder).exists() for folder in fault_observation['ownedAfter'])
    candidates = []
    for folder, workspace in owned.items():
        path = Path(folder) / 'selected-backup'
        if not path.exists(): continue
        facts = path.lstat()
        assert stat.S_ISREG(facts.st_mode) and not path.is_symlink() and facts.st_nlink == 1
        data = path.read_bytes()
        assert len(data) == old['bytes'] and digest(data) == old['sha256']
        assert workspace['owner']['id'] != old['owner']['id']
        assert str(path) != fault_observation['originalSelectedBackupPath']
        seed=json.loads((base/a.inputs).read_text())
        provider=Path(next(row['seeded'] for row in seed['files'] if Path(row['input']).name==expected_name))
        provider_facts=provider.lstat()
        assert (facts.st_ino,facts.st_dev)!=(provider_facts.st_ino,provider_facts.st_dev)
        candidates.append({'directory': folder, 'owner': workspace['owner'], 'file': str(path),
                           'bytes': len(data), 'sha256': digest(data),
                           'identity': {key: getattr(facts, key) for key in ['st_ino','st_dev','st_mode','st_nlink','st_size','st_mtime_ns']}})
    assert len(candidates) == 1
    photos = {}
    for photo_id, expected in matrix['photos'].items():
        matches = [(folder, name) for folder, workspace in owned.items()
                   for name, row in workspace['files'].items()
                   if row['sha256'] == expected['sha256'] and row['bytes'] == expected['bytes']]
        assert len(matches) == 1
        folder, name = matches[0]
        photos[photo_id] = {'file': str(Path(folder) / name), **expected}
    verify_provider()
    return {'source': candidates[0], 'ownedWorkspaces': owned, 'photos': photos,
            'allOldWorkspacesAbsent': True, 'independentFreshOwnership': True,
            'healthyOriginalPhotosRestoredByNewSelection': True, 'checkedAt': time.time()}


def verify_fresh_original_identity(fresh):
    source = fresh['source']; path = Path(source['file']); facts = path.lstat()
    assert not path.is_symlink() and stat.S_ISREG(facts.st_mode)
    assert {key: getattr(facts, key) for key in source['identity']} == source['identity']
    assert len(path.read_bytes()) == source['bytes'] and digest(path.read_bytes()) == source['sha256']
    assert owned_workspaces(source['owner']['pid']) == fresh['ownedWorkspaces']
    verify_provider()
    return {'freshSelectedBackupBytesAndIdentityExact': True, 'providerIdentityExact': True}


def assert_same_recovery_control(record, phase):
    assert record == {**held['record'], 'phase': phase, 'uiCancelled': False}
    assert record['ordinal']==2 and record['workerControlMatchesUI']
    assert re.fullmatch(r'[A-Fa-f0-9-]{36}',record['nonce'])


def audit_success_receipt_before_ack(root, receipt):
    seed=json.loads((base/a.inputs).read_text())
    original=next(row for row in seed['files'] if Path(row['input']).name==expected_name)
    assert receipt['fileSource']=={'fileName':expected_name,'format':{'legacy':'legacyJSONBackup','encrypted':'encryptedBackup'}[a.case],
        'byteCount':original['bytes'],'sha256':original['sha256']}
    assert receipt['source']=='selected-file:'+original['sha256']
    assert receipt['domains']==['meals','workouts'] and receipt['omittedPhotoCount']==0
    assert set(receipt['recordDigests'])=={'meals.json','workouts.json'}
    for name in ['meals.json','workouts.json']:assert receipt['recordDigests'][name]==digest((root/name).read_bytes())
    photo_digests=verify_installed(root)
    assert receipt['photoDigests']==photo_digests
    assert receipt['reviewedPhotos']=={key:{'byteCount':v['bytes'],'sha256':v['sha256']} for key,v in matrix['photos'].items()}
    current=snapshot(root,current=False)
    legacy_copies(root)
    for name,row in protected_before.items():
        if name not in {'meals.json','workouts.json','health-write-intent.json'}:assert current[name]==row,name
    for name,row in preservation_before['files'].items():assert current[name]==row,name
    old=json.loads(base64.b64decode(before['health-write-intent.json']['base64']))
    new=json.loads((root/'health-write-intent.json').read_bytes())
    assert new['owner']==old['owner'] and new['lifecycle']!=old['lifecycle'] and new['events']==[]
    return {'fullReceiptAuditedBeforeAck':True,'healthyCurrentAndPrivatePriorExact':True,'installedPhotoDigests':photo_digests}

# Pending producer body; assembled into a standalone driver only after source freeze.
reader_held = None
reader_release_requested = None
reader_completed = None
scroll_boundary = None
back_boundary = None
fresh_selection = None
command = ['xcodebuild','-project','Lumen.xcodeproj','-scheme','Lumen','-configuration','Debug',
    '-destination','platform=iOS Simulator,id='+device,'-derivedDataPath','/tmp/LumenBatch37Simulator',
    '-clonedSourcePackagesDirPath','/tmp/LumenBatch37Packages','-disableAutomaticPackageResolution',
    '-parallel-testing-enabled','NO','-collect-test-diagnostics','never',
    '-only-testing:LumenUITests/LumenSmokeTests/testHealthBackupFileRecoveryPhotoFaultErrorBack'+a.case.title()+('OriginData' if a.origin=='data' else 'OriginString'),
    '-resultBundlePath',str(result),'test-without-building']
with (raw/(stem+'.log')).open('xb') as stream:
    process = subprocess.Popen(command,cwd=repo,stdout=stream,stderr=subprocess.STDOUT)
    print('Running',stem,'PID',process.pid,flush=True)
    awake = subprocess.Popen(['caffeinate','-d','-i','-w',str(process.pid)])
    deadline = time.monotonic()+800
    try:
        while process.poll() is None:
            assert time.monotonic()<deadline,'Finite state producer timed out; retain actual outcome'
            group=container('group.com.dbakp.lumen');root=group/'LumenData';baseline=group/'Lumen-health-backup-baseline.json'
            log=(raw/(stem+'.log')).read_text()
            def captured(suffix):return ("Added attachment named '"+ui_prefix+'-'+suffix+"'") in log
            if checkpoint is None:
                try:
                    if baseline.stat().st_mtime<started:time.sleep(0.2);continue
                    value=json.loads(baseline.read_bytes())
                except (FileNotFoundError,json.JSONDecodeError):time.sleep(0.2);continue
                if value['case']!=a.case or 'Tap "chooseBackup" Button' not in log:time.sleep(0.2);continue
                profile=(root/'profile.json').read_bytes();fixture=value['originals']['profile.json']
                assert json.loads(profile)==json.loads(base64.b64decode(fixture))
                value['fixtureProfileBeforeStoreStartup']=fixture;value['originals']['profile.json']=base64.b64encode(profile).decode()
                value['observedBoundary']='Actual Settings opens Files before initial selection'
                checkpoint=value
                before=originals(group,value);protected_before=snapshot(root,current=False)
                goals=json.loads((root/'goals.json').read_bytes());assert [goals[k] for k in ['stepGoal','weightKg','heightCm','age']]==[6543,88.5,181,42]
                previous_before=snapshot(root.with_suffix('.previous'),current=False)
                assert {'water.json','meals.json','workouts.json','goals.json','today.json','health-write-intent.json','profile.json'}.issubset(previous_before)
                checkpoint=value
            observe_source();inject_photo_fault(root)
            if reader_held is None and captured('record-held-1'):
                assert fault_observation is not None
                reader_held=audit_actual_reader(group)
                send_read_message(group,reader_held['record'],True)
            if reader_held and reader_release_requested is None and captured('record-observed-1'):
                actual=audit_actual_reader(group)
                assert actual['record']['nonce']==reader_held['record']['nonce']
                reader_release_requested={'record':actual['record'],'sameActualReader':True,'releaseRequestedAfterObservedNativeCapture':True,'checkedAt':time.time()}
                send_read_message(group,actual['record'],False)
            if failed_boundary is None and captured('failed'):
                assert reader_release_requested
                reader_completed=audit_completed_reader(group,reader_held)
                failed_boundary=verify_failed_boundary(root,ui_prefix+'-failed')
            if scroll_boundary is None and captured('scroll-stays'):
                assert failed_boundary
                scroll_boundary=verify_failed_boundary(root,ui_prefix+'-scroll-stays')
            if omission_not_now_boundary is None and captured('omission-not-now'):
                assert scroll_boundary
                omission_not_now_boundary=verify_failed_boundary(root,ui_prefix+'-omission-not-now')
            if back_boundary is None and captured('back-parent'):
                assert omission_not_now_boundary and reader_held
                # The close observer may publish just after the parent attachment.
                _,read=read_protocol(group)
                if read.get('reviewOwnerClosed') is not True:time.sleep(0.1);continue
                back_boundary=audit_back_after_failure(group,reader_held)
            if fresh_selection is None and captured('reselected-source'):
                assert back_boundary
                fresh_selection=audit_fresh_reselected_source(group,back_boundary)
            cancel=group/'Lumen-health-cancel-checkpoint.json'
            try:
                if cancel.stat().st_mtime<started:time.sleep(0.2);continue
                assert not cancel.is_symlink() and stat.S_ISREG(cancel.lstat().st_mode) and cancel.stat().st_size<64*1024
                protocol=json.loads(cancel.read_bytes())
            except (FileNotFoundError,json.JSONDecodeError):time.sleep(0.2);continue
            if not protocol['attempts']:time.sleep(0.2);continue
            record=protocol['attempts'][0]
            assert len(protocol['attempts'])==1
            if held is None and captured('held-2'):
                assert fresh_selection and failed_boundary and scroll_boundary and omission_not_now_boundary
                identity();verify_fresh_original_identity(fresh_selection)
                frame=fresh_selection['source'];pid=frame['owner']['pid']
                assert Path(subprocess.check_output(['ps','-p',str(pid),'-o','comm='],text=True).strip())==container('app')/'Lumen'
                assert record['ordinal']==2 and len(protocol['attempts'])==1 and record['phase']=='held' and record['workerControlMatchesUI'] and not record['uiCancelled']
                assert re.fullmatch(r'LumenData\.restore-[A-Fa-f0-9-]+',record['stage'])
                stage=group/record['stage'];assert stage.is_dir() and not stage.is_symlink() and stat.S_IMODE(stage.stat().st_mode)==0o700
                assert list(stage.iterdir())==[]
                preservation_before=verify_preparation_tree(root)
                for key,encoded in record['originals'].items():assert base64.b64decode(encoded)==base64.b64decode(protected_before[key]['base64'])
                owned=owned_workspaces(pid);assert owned==fresh_selection['ownedWorkspaces']
                held={'record':record.copy(),'originalSource':frame,'ownedWorkspaces':owned,'stage':str(stage),'stageInitiallyEmpty':True,
                    'protectedBefore':protected_before,'priorSnapshot':previous_before,'preservation':preservation_before,'observedAfterNativeAttachment':ui_prefix+'-held-2'}
                target=group/'Lumen-health-cancel-release.json';temp=target.with_name(target.name+'.'+record['nonce']+'.ack.tmp')
                assert not temp.exists();temp.write_text(json.dumps({'nonce':record['nonce'],'acknowledgementOnly':True}));temp.replace(target)
            if held and released is None and captured('observed-2'):
                verify_fresh_original_identity(fresh_selection)
                assert_same_recovery_control(record,'held')
                assert verify_preparation_tree(root)==preservation_before and list(Path(held['stage']).iterdir())==[]
                released={'observedRecord':record.copy(),'afterNativeObservedAttachment':True,'sameActualControl':True,'allProtectedBytesExact':True,'allFreshOriginalWorkspacesExact':True}
                target=group/'Lumen-health-cancel-release.json';temp=target.with_name(target.name+'.'+record['nonce']+'.tmp')
                assert not temp.exists();temp.write_text(json.dumps({'nonce':record['nonce']}));temp.replace(target)
            if released and success is None and captured('success'):
                observation_file=group/'Lumen-health-success-checkpoint.json'
                if not observation_file.exists() or observation_file.stat().st_mtime<started:time.sleep(0.2);continue
                assert not observation_file.is_symlink() and stat.S_ISREG(observation_file.lstat().st_mode) and observation_file.stat().st_size<1024
                observation=json.loads(observation_file.read_bytes());assert re.fullmatch(r'[A-Fa-f0-9-]{36}',observation['nonce'])
                verify_fresh_original_identity(fresh_selection);verify_provider()
                assert_same_recovery_control(record,'released')
                receipts=list((root/'.health-recovery-history').glob('*.json'));assert len(receipts)==1
                receipt=json.loads(receipts[0].read_bytes())
                receipt_audit=audit_success_receipt_before_ack(root,receipt)
                success={'treeAfterCommit':snapshot(root,current=False),'receipt':receipt,'observedAfterNativeAttachment':ui_prefix+'-success','observationNonce':observation['nonce'],
                    'sourceIdentityAuditedWhileReviewOpen':True,'providerIdentityAuditedWhileReviewOpen':True,'receiptAuditBeforeAck':receipt_audit,'releasedControl':record.copy()}
                target=group/'Lumen-health-success-ack.json';temp=target.with_name(target.name+'.'+observation['nonce']+'.tmp')
                assert not temp.exists();temp.write_text(json.dumps({'nonce':observation['nonce'],'acknowledgementOnly':True}));temp.replace(target)
            if success and final_cleanup is None and captured('parent'):
                roots=held['ownedWorkspaces'];pid=held['originalSource']['owner']['pid'];until=time.monotonic()+3
                while any(Path(folder).exists() for folder in roots) and time.monotonic()<until:time.sleep(0.1)
                assert all(not Path(folder).exists() for folder in roots) and all(not Path(folder).exists() for folder in fault_observation['ownedAfter'])
                assert not Path(held['stage']).exists()
                scan=no_open_roots(pid,{**roots,**fault_observation['ownedAfter']});assert not owned_workspaces(pid)
                final_cleanup={'ownedRootsAbsent':True,'stageAbsent':True,'liveNoOpenPaths':scan,'hostDeletedWorkspace':False,
                    'treeAtParentBeforeRelaunch':snapshot(root,current=False),'observedAfterNativeAttachment':ui_prefix+'-parent',
                    'timingScope':'3s host observation guard after parent screenshot, not tap-to-delete latency'}
            time.sleep(0.2)
        code=process.wait()
    except Exception:
        host_failure=traceback.format_exc();process.send_signal(signal.SIGINT)
        try:code=process.wait(timeout=30)
        except subprocess.TimeoutExpired:
            process.terminate()
            try:code=process.wait(timeout=15)
            except subprocess.TimeoutExpired:process.kill();code=process.wait()
    finally:
        observations={'source':a.source,'build':a.build,'checkpoint':checkpoint,'before':before,'protectedBefore':protected_before,'previousBefore':previous_before,
            'preservationBeforeCommit':preservation_before,'sourceObservations':source_observations,'readerHeld':reader_held,'readerReleaseRequested':reader_release_requested,'readerCompleted':reader_completed,'protocol':protocol,
            'heldPreparation':held,'releasedPreparation':released,'success':success,'finalCleanup':final_cleanup,'hostFailure':host_failure,
            'faultObservation':fault_observation,'failedBoundary':failed_boundary,'scrollBoundary':scroll_boundary,'omissionNotNowBoundary':omission_not_now_boundary,
            'backBoundary':back_boundary,'freshSelection':fresh_selection,'producerPID':process.pid,'producerExitCode':process.poll()}
        (base/(prefix+'-driver-observations.json')).write_text(json.dumps(observations,indent=2)+'\n')

summary=json.loads(subprocess.check_output(['xcrun','xcresulttool','get','test-results','summary','--path',str(result)],text=True))
for dest in [raw/(stem+'-summary.json'),base/(prefix+'-summary.json')]:dest.write_text(json.dumps(summary,indent=2)+'\n')
# Preserve actual native results before any terminal host assertion.
log_bytes=(raw/(stem+'.log')).read_bytes()
(base/(stem+'.log.gz')).write_bytes(gzip.compress(log_bytes,mtime=0))
for ext,pattern in [('PNG','*.png'),('JSON','*.json')]:
    subprocess.run(['xcrun','xcresulttool','export','attachments','--path',str(result),'--output-path',str(raw/(stem+ext)),'--filter',pattern],check=True,stdout=subprocess.DEVNULL)
retain=['python3',str(base/'retain-health-record-attachments.py'),'--stem',stem,'--prefix',prefix,'--source',a.source,'--png-dir',str(raw/(stem+'PNG')),'--json-dir',str(raw/(stem+'JSON')),'--raw-root',str(raw)]
if host_failure or code:retain.append('--include-failed-trial')
subprocess.run(retain,cwd=repo,check=True)
assert host_failure is None,host_failure
assert code==0 and summary['passedTests']==1 and summary['failedTests']==summary['skippedTests']==0
assert held and released and success and final_cleanup and fault_observation and failed_boundary and scroll_boundary and omission_not_now_boundary and back_boundary and fresh_selection and reader_held and reader_release_requested and reader_completed
identity()
root = container('group.com.dbakp.lumen') / 'LumenData'
after=snapshot(root,current=False)
selected={'meals.json','workouts.json'}
for name in set(after)-set(protected_before):assert name in selected or name.startswith(('.health-recovery/','.health-recovery-history/','photos/')),name
for name,row in protected_before.items():
    if name in selected or name=='health-write-intent.json':continue
    assert final_cleanup['treeAtParentBeforeRelaunch'][name]==row,name
    if name in ['profile.json','habits.json']:assert json.loads(base64.b64decode(after[name]['base64']))==json.loads(base64.b64decode(row['base64']))
    else:assert after[name]==row,name
# Normal recovery retires .previous. Its two selected domains and intent
# remain exact in preservation_before['files'], checked below.

for key,row in preservation_before['files'].items():assert after.get(key)==row,key
verify_installed(root)
assert json.loads(base64.b64decode(after['workouts.json']['base64']))==[]
photo=None
old_intent=json.loads(base64.b64decode(before['health-write-intent.json']['base64']))
new_intent=json.loads((root/'health-write-intent.json').read_bytes())
assert new_intent['owner']==old_intent['owner'] and new_intent['lifecycle']!=old_intent['lifecycle'] and new_intent['events']==[]
copies=legacy_copies(root)
receipts=list((root/'.health-recovery-history').glob('*.json'));assert len(receipts)==1
receipt=json.loads(receipts[0].read_bytes());seed=json.loads((base/a.inputs).read_text())
expected=next(r for r in seed['files'] if Path(r['input']).name==expected_name)
provider=Path(expected['seeded']);info=provider.lstat();assert provider.read_bytes()==(base/Path(expected['canonical']).name).read_bytes()
assert info.st_ino==expected['inode'] and info.st_dev==expected['device'] and info.st_mode==expected['mode'] and info.st_mtime_ns==expected['modifiedNS']
assert receipt['fileSource']=={'fileName':expected_name,'format':{'legacy':'legacyJSONBackup','encrypted':'encryptedBackup','readable':'readableExport'}[a.case],'byteCount':expected['bytes'],'sha256':expected['sha256']}
assert receipt['source']=='selected-file:'+expected['sha256'] and receipt['domains']==['meals','workouts'] and receipt['omittedPhotoCount']==0
assert set(receipt['recordDigests'])==selected
for name in selected:assert receipt['recordDigests'][name]==after[name]['sha256']
expected_photo_digests=verify_installed(root)
assert receipt['photoDigests']==expected_photo_digests
assert receipt['reviewedPhotos']=={key:{'byteCount':v['bytes'],'sha256':v['sha256']} for key,v in matrix['photos'].items()}
assert final_cleanup['treeAtParentBeforeRelaunch']==success['treeAfterCommit']
for name,row in success['treeAfterCommit'].items():
    if name in ['profile.json','habits.json']:
        assert json.loads(base64.b64decode(after[name]['base64']))==json.loads(base64.b64decode(row['base64']))
    else:assert after[name]==row,name
events=origin_events();opened=[r['sessionID'] for r in events if r['event']=='open']
assert len(opened)==2 and len(set(opened))==2
for owner in opened:
    own=[r for r in events if r['sessionID']==owner]
    assert [r['event'] for r in own[:3]]==['open','ready','acquire']
    assert own[3:] and all(r['event']=='closed' for r in own[3:])
    assert own[1]['domains']==own[2]['domains']==['meals','workouts']
legacy_values=legacy_defaults(checkpoint['legacyOrigins'])
assert source_observations
(base/(prefix+'-host-audit.json')).write_text(json.dumps({'status':'PASS actual genuine error/scroll/Back/fresh original reselect/two-photo recovery/relaunch','source':a.source,'build':a.build,'case':a.case,'origin':a.origin,'fixedLegacyValues':legacy_values,'originReviewEvents':events,'phone':a.phone,'appearance':a.appearance,'device':device,'inputManifest':a.input_manifest,'inputProvenance':a.inputs,'before':before,'after':after,'protectedBefore':protected_before,'previousBefore':previous_before,'preservationBeforeCommit':preservation_before,'sourceObservations':source_observations,'heldPreparation':held,'releasedPreparation':released,'successBeforeRelaunch':success,'finalCleanupBeforeRelaunch':final_cleanup,'protocol':protocol,'producerExitCode':code,'receipt':receipt,'retainedDamagedPaths':copies,'faultObservation':fault_observation,'failedBoundary':failed_boundary,'readerHeld':reader_held,'readerReleaseRequested':reader_release_requested,'readerCompleted':reader_completed,'scrollBoundary':scroll_boundary,'backBoundary':back_boundary,'freshSelection':fresh_selection,'omissionNotNowBoundary':omission_not_now_boundary,'photoMode':a.mode,'installedPhotoDigests':expected_photo_digests,'providerIdentityExact':True,'conflictingHealthyGoalsChecked':True,'verifierSHA256':digest(Path(__file__).read_bytes()),'scope':'main/normal actual genuine failure, bounded3s deliberate scroll, omission Not-now, completed reader closure on Back, fresh original selection/choices off, real two-photo recovery without omission and relaunch. Full state/VoiceOver/Reduce Motion/broader gates remain.'},indent=2)+'\n')
print('PASS:',a.case,'actual genuine error/scroll/Back/reselect/photo recovery audit')
