"""Actual normal Settings/Files selected-file replacement and independent audit."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import time
import traceback

p = argparse.ArgumentParser()
p.add_argument('--source', required=True)
p.add_argument('--build', required=True)
p.add_argument('--case', choices=['legacy', 'encrypted', 'readable'], required=True)
p.add_argument('--trial', required=True)
p.add_argument('--observe-source', action='store_true')
a = p.parse_args()
a.observe_source = True
assert re.fullmatch(r'[A-Za-z0-9-]+', a.trial)
base = Path(__file__).resolve().parent
repo = base.parents[2]
raw = Path('/tmp/LumenBatch43Checks')
device = 'AF849DEA-DF34-4B0E-9FC1-3E45DCBE8481'
stem = 'HealthFileCommit' + a.case.title() + a.trial
prefix = 'health-file-commit-' + a.case + '-' + a.trial.lower()
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

def originals(group, checkpoint):
    root = group / 'LumenData'
    rows = {}
    for name, encoded in checkpoint['originals'].items():
        path = root / name
        assert stat.S_ISREG(path.lstat().st_mode)
        data = path.read_bytes()
        assert data == base64.b64decode(encoded, validate=True), name
        rows[name] = {'bytes': len(data), 'sha256': digest(data), 'base64': encoded}
    assert (root / 'water.json').read_bytes() == b'{"syntheticUnavailableWater":'
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
        assert (root / 'water.json').read_bytes() == b'{"syntheticUnavailableWater":'
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
final_cleanup = None
host_failure = None
def observe_source():
    if not a.observe_source or source_observations:
        return
    tag = 'health-file-' + a.case + '-source'
    if ("Added attachment named '" + tag + "'") not in (raw / (stem + '.log')).read_text():
        return
    expected_name = {'legacy': 'Lumen-backup-health-legacy-small.json',
                     'encrypted': 'Lumen-backup-health-encrypted-small.lumenbackup',
                     'readable': 'Lumen-readable-health-small.json'}[a.case]
    seed = json.loads((base / 'health-backup-small-main-seed.json').read_text())
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

def verify_preparation_tree(root):
    current=snapshot(root,current=False)
    assert previous_before is not None
    assert all(current.get(key)==value for key,value in protected_before.items())
    extra=set(current)-set(protected_before)
    assert len(extra)==3, extra
    parent={str(Path(key).parent) for key in extra};assert len(parent)==1
    directory=Path(next(iter(parent)))
    assert directory.parts[0]=='.health-recovery' and len(directory.parts)==2
    assert {Path(key).name for key in extra}=={'water.json','device-intent.json','manifest.json'}
    water=current[str(directory/'water.json')];intent=current[str(directory/'device-intent.json')]
    assert water==previous_before['water.json']
    assert intent==previous_before['health-write-intent.json']
    manifest=json.loads(base64.b64decode(current[str(directory/'manifest.json')]['base64']))
    assert manifest['version']==1 and manifest['domains']==['water'] and manifest['intent'] is True and manifest['photos'] is False
    assert not list((root/'.health-recovery-history').glob('*.json'))
    return {'files':{key:current[key] for key in sorted(extra)},'manifest':manifest,'priorWaterAndIntentExact':True}


command = ['xcodebuild','-project','Lumen.xcodeproj','-scheme','Lumen','-configuration','Debug',
    '-destination','platform=iOS Simulator,id='+device,'-derivedDataPath','/tmp/LumenBatch37Simulator',
    '-clonedSourcePackagesDirPath','/tmp/LumenBatch37Packages','-disableAutomaticPackageResolution',
    '-parallel-testing-enabled','NO','-collect-test-diagnostics','never',
    '-only-testing:LumenUITests/LumenSmokeTests/testHealthBackupFileRecoveryCommit'+a.case.title(),
    '-resultBundlePath',str(result),'test-without-building']
with (raw/(stem+'.log')).open('wb') as stream:
    process = subprocess.Popen(command,cwd=repo,stdout=stream,stderr=subprocess.STDOUT)
    awake = subprocess.Popen(['caffeinate','-d','-i','-w',str(process.pid)])
    deadline = time.monotonic()+800
    try:
        while process.poll() is None:
            assert time.monotonic()<deadline,'Inspect same finite producer; observation timeout is not terminal'
            group=container('group.com.dbakp.lumen');root=group/'LumenData';baseline=group/'Lumen-health-backup-baseline.json'
            log=(raw/(stem+'.log')).read_text()
            if checkpoint is None:
                try:
                    if baseline.stat().st_mtime<started:time.sleep(0.2);continue
                    value=json.loads(baseline.read_bytes())
                except (FileNotFoundError,json.JSONDecodeError):time.sleep(0.2);continue
                marker='chooseReadableExport' if a.case=='readable' else 'chooseBackup'
                if value['case']!=a.case or ('Tap "'+marker+'" Button') not in log:time.sleep(0.2);continue
                profile=(root/'profile.json').read_bytes();fixture=value['originals']['profile.json']
                assert json.loads(profile)==json.loads(base64.b64decode(fixture))
                value['fixtureProfileBeforeStoreStartup']=fixture;value['originals']['profile.json']=base64.b64encode(profile).decode()
                value['observedBoundary']='Actual normal Settings opens Files before selection'
                before=originals(group,value);protected_before=snapshot(root,current=False);assert len(protected_before)==12
                previous_before=snapshot(root.with_suffix('.previous'),current=False)
                assert {'water.json','meals.json','workouts.json','goals.json','today.json','health-write-intent.json','profile.json'}.issubset(previous_before)
                checkpoint=value
            observe_source()
            cancel=group/'Lumen-health-cancel-checkpoint.json'
            try:
                if cancel.stat().st_mtime<started:time.sleep(0.2);continue
                protocol=json.loads(cancel.read_bytes())
            except (FileNotFoundError,json.JSONDecodeError):time.sleep(0.2);continue
            if not protocol['attempts']:time.sleep(0.2);continue
            record=protocol['attempts'][0]
            if held is None and ("Added attachment named 'health-commit-"+a.case+"-held'") in log:
                identity();assert source_observations
                frame=source_observations[0];pid=frame['owner']['pid']
                assert Path(subprocess.check_output(['ps','-p',str(pid),'-o','comm='],text=True).strip())==container('app')/'Lumen'
                assert record['ordinal']==1 and record['phase']=='held' and record['workerControlMatchesUI'] and not record['uiCancelled']
                assert re.fullmatch(r'LumenData\.restore-[A-Fa-f0-9-]+',record['stage'])
                stage=group/record['stage'];assert stage.is_dir() and not stage.is_symlink() and stat.S_IMODE(stage.stat().st_mode)==0o700
                assert list(stage.iterdir())==[], 'Barrier is immediately after empty stage creation, not after copy'
                preservation_before=verify_preparation_tree(root)
                for key,encoded in record['originals'].items():assert base64.b64decode(encoded)==base64.b64decode(protected_before[key]['base64'])
                owned=owned_workspaces(pid);assert len(owned)==(2 if a.case=='legacy' else 1)
                assert str(Path(frame['directory'])) in owned
                assert (Path(frame['directory'])/'selected-backup').read_bytes()==base64.b64decode(owned[frame['directory']]['files']['selected-backup']['base64'])
                held={'record':record.copy(),'originalSource':frame,'ownedWorkspaces':owned,'stage':str(stage),'stageInitiallyEmpty':True,
                    'protectedBefore':protected_before,'priorSnapshot':previous_before,'preservation':preservation_before,'observedAfterNativeAttachment':'health-commit-'+a.case+'-held'}
                target=group/'Lumen-health-cancel-release.json';temp=target.with_name(target.name+'.'+record['nonce']+'.ack.tmp')
                assert not temp.exists();temp.write_text(json.dumps({'nonce':record['nonce'],'acknowledgementOnly':True}));temp.replace(target)
            if held and released is None and ("Added attachment named 'health-commit-"+a.case+"-observed'") in log:
                pid=held['originalSource']['owner']['pid'];assert record['phase']=='held' and not record['uiCancelled']
                assert verify_preparation_tree(root)==preservation_before and owned_workspaces(pid)==held['ownedWorkspaces']
                assert list(Path(held['stage']).iterdir())==[]
                released={'afterNativeObservedAttachment':True,'sameActualControl':True,'allProtectedBytesExact':True,'allOriginalWorkspacesExact':True}
                target=group/'Lumen-health-cancel-release.json';temp=target.with_name(target.name+'.'+record['nonce']+'.tmp')
                assert not temp.exists();temp.write_text(json.dumps({'nonce':record['nonce']}));temp.replace(target)
            if released and success is None and ("Added attachment named 'health-file-"+a.case+"-success'") in log:
                assert record['phase']=='released' and record['workerControlMatchesUI'] and not record['uiCancelled']
                water=json.loads((root/'water.json').read_bytes());assert len(water)==1 and water[0]['id']=='synthetic-backup-recovery-water' and water[0]['ml']==246
                receipts=list((root/'.health-recovery-history').glob('*.json'));assert len(receipts)==1
                success={'treeAfterCommit':snapshot(root,current=False),'receipt':json.loads(receipts[0].read_bytes()),'observedAfterNativeAttachment':'health-file-'+a.case+'-success'}
            if success and final_cleanup is None and ("Added attachment named 'health-commit-"+a.case+"-final-parent'") in log:
                roots=held['ownedWorkspaces'];pid=held['originalSource']['owner']['pid'];until=time.monotonic()+3
                while any(Path(folder).exists() for folder in roots) and time.monotonic()<until:time.sleep(0.1)
                assert all(not Path(folder).exists() for folder in roots), roots
                assert not Path(held['stage']).exists()
                scan=no_open_roots(pid,roots);assert not owned_workspaces(pid)
                final_cleanup={'ownedRootsAbsent':True,'stageAbsent':True,'liveNoOpenPaths':scan,'hostDeletedWorkspace':False,
                    'treeAtParentBeforeRelaunch':snapshot(root,current=False),'observedAfterNativeAttachment':'health-commit-'+a.case+'-final-parent',
                    'timingScope':'3s host observation guard after parent screenshot, not tap-to-delete latency'}
            time.sleep(0.2)
        code=process.wait()
    except Exception:
        host_failure=traceback.format_exc();code=process.wait(timeout=max(1,deadline-time.monotonic()+30))
    finally:
        (base/(prefix+'-driver-observations.json')).write_text(json.dumps({'source':a.source,'build':a.build,'checkpoint':checkpoint,
            'before':before,'protectedBefore':protected_before,'previousBefore':previous_before,'preservationBeforeCommit':preservation_before,'sourceObservations':source_observations,'protocol':protocol,
            'heldPreparation':held,'releasedPreparation':released,'success':success,'finalCleanup':final_cleanup,'hostFailure':host_failure,
            'producerPID':process.pid,'producerExitCode':process.poll()},indent=2)+'\n')
summary=json.loads(subprocess.check_output(['xcrun','xcresulttool','get','test-results','summary','--path',str(result)],text=True))
for dest in [raw/(stem+'-summary.json'),base/(prefix+'-summary.json')]:dest.write_text(json.dumps(summary,indent=2)+'\n')
assert host_failure is None,host_failure
assert code==0 and summary['passedTests']==1 and summary['failedTests']==0
assert held and released and success and final_cleanup
identity()
root = container('group.com.dbakp.lumen') / 'LumenData'
after = {}
for name, row in protected_before.items():
    data = (root / name).read_bytes()
    after[name] = {'bytes': len(data), 'sha256': digest(data), 'base64': base64.b64encode(data).decode()}
    # SleepStore.init recomputes/persists profile and habits on normal relaunch.
    # Their complete decoded values must remain exact; before relaunch even
    # their encoded bytes must match, so transaction changes cannot hide here.
    if name not in ['water.json', 'health-write-intent.json', 'profile.json', 'habits.json']:
        assert after[name] == row, name
    if name in ['profile.json', 'habits.json']:
        assert final_cleanup['treeAtParentBeforeRelaunch'][name] == row, name
        assert json.loads(data) == json.loads(base64.b64decode(row['base64']))
for key,row in preservation_before['files'].items():
    assert snapshot(root,current=False).get(key)==row, key
water = (root / 'water.json').read_bytes()
decoded_water = json.loads(water)
assert len(decoded_water) == 1 and decoded_water[0]['id'] == 'synthetic-backup-recovery-water' and decoded_water[0]['ml'] == 246
legacy_input=next(row for row in json.loads((base/'health-backup-small-main-seed.json').read_text())['files'] if row['input'].endswith('legacy-small.json'))
legacy_data=Path(legacy_input['seeded']).read_bytes();assert digest(legacy_data)==legacy_input['sha256']
envelope=json.loads(legacy_data);payload=base64.b64decode(envelope['payload']);assert digest(payload)==envelope['sha256']
assert decoded_water==json.loads(payload)['water'], 'Complete selected water record fields must match paired checked fixture'
old_intent = json.loads(base64.b64decode(before['health-write-intent.json']['base64']))
new_intent = json.loads((root / 'health-write-intent.json').read_bytes())
assert new_intent['owner'] == old_intent['owner'] and new_intent['lifecycle'] != old_intent['lifecycle'] and new_intent['events'] == []
copies = list((root / '.health-recovery').glob('*/water.json'))
assert any(p.read_bytes() == base64.b64decode(before['water.json']['base64']) for p in copies)
receipts = list((root / '.health-recovery-history').glob('*.json'))
assert len(receipts) == 1
receipt = json.loads(receipts[0].read_bytes())
seed = json.loads((base / 'health-backup-small-main-seed.json').read_text())
expected_name = {'legacy': 'Lumen-backup-health-legacy-small.json', 'encrypted': 'Lumen-backup-health-encrypted-small.lumenbackup', 'readable': 'Lumen-readable-health-small.json'}[a.case]
expected = next(r for r in seed['files'] if Path(r['input']).name == expected_name)
assert receipt['fileSource'] == {'fileName': expected_name, 'format': {'legacy': 'legacyJSONBackup', 'encrypted': 'encryptedBackup', 'readable': 'readableExport'}[a.case], 'byteCount': expected['bytes'], 'sha256': expected['sha256']}
assert receipt['source'] == 'selected-file:' + expected['sha256'] and receipt['domains'] == ['water'] and receipt['omittedPhotoCount'] == 0
assert receipt['recordDigests']['water.json'] == digest(water)
if a.observe_source:
    assert source_observations, 'No live-owner exact selected-file observation at the actual reviewed/error state'
(base / (prefix + '-host-audit.json')).write_text(json.dumps({
    'status': 'passed: selected-file water replacement survives relaunch',
    'source': a.source, 'build': a.build, 'case': a.case, 'before': before, 'after': after,
    'sourceObservations': source_observations, 'protectedBefore':protected_before,'previousBefore':previous_before,'preservationBeforeCommit':preservation_before,'heldPreparation':held,'releasedPreparation':released,'successBeforeRelaunch':success,'finalCleanupBeforeRelaunch':final_cleanup,'protocol':protocol,'producerExitCode':code,
    'receipt': receipt, 'retainedDamagedWaterPaths': [str(p) for p in copies if p.read_bytes() == base64.b64decode(before['water.json']['base64'])],
    'verifierSHA256': digest(Path(__file__).read_bytes()),
    'scope': 'Actual normal Settings/Files input, off/on choice, typed 246mL review, Not now, confirmation, success and relaunch. Host reads exact healthy domain bytes; profile and habits bytes exact through commit/final parent and complete decoded values unchanged after normal startup persistence. Selected water, private damaged water, same owner/new lifecycle/empty intent, exact original file identity and record digest in receipt checked. Actual empty-stage preparation/control/owned-source hold and final-parent live cleanup observed; actual atomic/in-flight interruption, photos/all domains/ordinary healthy merge/fault/capacity/appearance/design/device/full gates remain separate.'
}, indent=2) + '\n')
print('PASS:', a.case, 'actual selected file recovered; independent original/source/receipt audit passed')
