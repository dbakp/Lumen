"""Actual normal Settings/Files selected-file replacement and independent audit."""
import gzip
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
stem = 'HealthFileMulti' + a.case.title() + a.trial
prefix = 'health-file-multi-' + a.case + '-' + a.trial.lower()
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
not_now_observed = False
final_cleanup = None
host_failure = None
def observe_source():
    if not a.observe_source or source_observations:
        return
    tag = 'health-multi-' + a.case + '-source'
    if ("Added attachment named '" + tag + "'") not in (raw / (stem + '.log')).read_text():
        return
    expected_name = {'legacy': 'Lumen-backup-health-multi-legacy.json',
                     'encrypted': 'Lumen-backup-health-multi-encrypted.lumenbackup',
                     'readable': 'Lumen-readable-health-multi.json'}[a.case]
    seed = json.loads((base / 'health-file-multi-r1-inputs.json').read_text())
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
    assert extra and all(key.startswith('.health-recovery/') for key in extra), extra
    manifests=[k for k in extra if k.endswith('/manifest.json')]
    assert len(manifests)==1
    directory=Path(manifests[0]).parent
    manifest=json.loads(base64.b64decode(current[manifests[0]]['base64']))
    assert manifest['version']==1 and manifest['domains']==['goals','meals','water','workouts'] and manifest['intent'] is True and manifest['photos'] is False
    expected={domain+'.json' for domain in manifest['domains']} | {'device-intent.json','manifest.json'}
    assert {Path(key).name for key in extra}==expected and all(Path(k).parent==directory for k in extra)
    for domain in manifest['domains']:assert current[str(directory/(domain+'.json'))]==previous_before[domain+'.json']
    assert current[str(directory/'device-intent.json')]==previous_before['health-write-intent.json']
    assert not list((root/'.health-recovery-history').glob('*.json'))
    return {'files':{key:current[key] for key in sorted(extra)},'manifest':manifest,'priorFourDomainsAndIntentExact':True}


command = ['xcodebuild','-project','Lumen.xcodeproj','-scheme','Lumen','-configuration','Debug',
    '-destination','platform=iOS Simulator,id='+device,'-derivedDataPath','/tmp/LumenBatch37Simulator',
    '-clonedSourcePackagesDirPath','/tmp/LumenBatch37Packages','-disableAutomaticPackageResolution',
    '-parallel-testing-enabled','NO','-collect-test-diagnostics','never',
    '-only-testing:LumenUITests/LumenSmokeTests/testHealthBackupFileRecoveryAllCommit'+a.case.title(),
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
                before=originals(group,value);protected_before=snapshot(root,current=False)
                previous_before=snapshot(root.with_suffix('.previous'),current=False)
                assert {'water.json','meals.json','workouts.json','goals.json','today.json','health-write-intent.json','profile.json'}.issubset(previous_before)
                checkpoint=value
            observe_source()
            if not not_now_observed and ("Added attachment named 'health-multi-"+a.case+"-not-now'") in log:
                assert snapshot(root,current=False)==protected_before
                assert snapshot(root.with_suffix('.previous'),current=False)==previous_before
                not_now_observed=True
            cancel=group/'Lumen-health-cancel-checkpoint.json'
            try:
                if cancel.stat().st_mtime<started:time.sleep(0.2);continue
                protocol=json.loads(cancel.read_bytes())
            except (FileNotFoundError,json.JSONDecodeError):time.sleep(0.2);continue
            if not protocol['attempts']:time.sleep(0.2);continue
            record=protocol['attempts'][0]
            if held is None and ("Added attachment named 'health-multi-"+a.case+"-held-1'") in log:
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
                    'protectedBefore':protected_before,'priorSnapshot':previous_before,'preservation':preservation_before,'observedAfterNativeAttachment':'health-multi-'+a.case+'-held-1'}
                target=group/'Lumen-health-cancel-release.json';temp=target.with_name(target.name+'.'+record['nonce']+'.ack.tmp')
                assert not temp.exists();temp.write_text(json.dumps({'nonce':record['nonce'],'acknowledgementOnly':True}));temp.replace(target)
            if held and released is None and ("Added attachment named 'health-multi-"+a.case+"-observed-1'") in log:
                pid=held['originalSource']['owner']['pid'];assert record['phase']=='held' and not record['uiCancelled']
                assert verify_preparation_tree(root)==preservation_before and owned_workspaces(pid)==held['ownedWorkspaces']
                assert list(Path(held['stage']).iterdir())==[]
                released={'afterNativeObservedAttachment':True,'sameActualControl':True,'allProtectedBytesExact':True,'allOriginalWorkspacesExact':True}
                target=group/'Lumen-health-cancel-release.json';temp=target.with_name(target.name+'.'+record['nonce']+'.tmp')
                assert not temp.exists();temp.write_text(json.dumps({'nonce':record['nonce']}));temp.replace(target)
            if released and success is None and ("Added attachment named 'health-multi-"+a.case+"-success'") in log:
                assert record['phase']=='released' and record['workerControlMatchesUI'] and not record['uiCancelled']
                water=json.loads((root/'water.json').read_bytes());assert len(water)==1 and water[0]['id']=='synthetic-multi-water' and water[0]['ml']==246
                receipts=list((root/'.health-recovery-history').glob('*.json'));assert len(receipts)==1
                success={'treeAfterCommit':snapshot(root,current=False),'receipt':json.loads(receipts[0].read_bytes()),'observedAfterNativeAttachment':'health-multi-'+a.case+'-success'}
            if success and final_cleanup is None and ("Added attachment named 'health-multi-"+a.case+"-parent'") in log:
                roots=held['ownedWorkspaces'];pid=held['originalSource']['owner']['pid'];until=time.monotonic()+3
                while any(Path(folder).exists() for folder in roots) and time.monotonic()<until:time.sleep(0.1)
                assert all(not Path(folder).exists() for folder in roots), roots
                assert not Path(held['stage']).exists()
                scan=no_open_roots(pid,roots);assert not owned_workspaces(pid)
                final_cleanup={'ownedRootsAbsent':True,'stageAbsent':True,'liveNoOpenPaths':scan,'hostDeletedWorkspace':False,
                    'treeAtParentBeforeRelaunch':snapshot(root,current=False),'observedAfterNativeAttachment':'health-multi-'+a.case+'-parent',
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
# Preserve actual native results before any terminal host assertion.
log_bytes=(raw/(stem+'.log')).read_bytes()
(base/(stem+'.log.gz')).write_bytes(gzip.compress(log_bytes,mtime=0))
for ext,pattern in [('PNG','*.png'),('JSON','*.json')]:
    subprocess.run(['xcrun','xcresulttool','export','attachments','--path',str(result),'--output-path',str(raw/(stem+ext)),'--filter',pattern],check=True,stdout=subprocess.DEVNULL)
retain=['python3',str(base/'retain-health-record-attachments.py'),'--stem',stem,'--prefix',prefix,'--source',a.source,'--png-dir',str(raw/(stem+'PNG')),'--json-dir',str(raw/(stem+'JSON'))]
if host_failure or code:retain.append('--include-failed-trial')
subprocess.run(retain,cwd=repo,check=True)
assert host_failure is None,host_failure
assert code==0 and summary['passedTests']==1 and summary['failedTests']==summary['skippedTests']==0
assert held and released and success and final_cleanup and not_now_observed
identity()
root = container('group.com.dbakp.lumen') / 'LumenData'
after=snapshot(root,current=False)
selected={'water.json','meals.json','workouts.json','goals.json'}
for name,row in protected_before.items():
    if name in selected or name=='health-write-intent.json':continue
    assert final_cleanup['treeAtParentBeforeRelaunch'][name]==row,name
    if name in ['profile.json','habits.json']:assert json.loads(base64.b64decode(after[name]['base64']))==json.loads(base64.b64decode(row['base64']))
    else:assert after[name]==row,name
assert snapshot(root.with_suffix('.previous'),current=False)==previous_before
for key,row in preservation_before['files'].items():assert after.get(key)==row,key
manifest=json.loads((base/'health-file-multi-r1-input-manifest.json').read_text())
expected_records=manifest['expectedRecords']
for domain in ['water','workouts','goals']:
    assert json.loads(base64.b64decode(after[domain+'.json']['base64']))==expected_records[domain],domain
meals=json.loads(base64.b64decode(after['meals.json']['base64']))
assert len(meals)==2
if a.case=='readable':
    assert all('photoID' not in m for m in meals)
    assert not (root/'photos').exists() or not list((root/'photos').iterdir())
    photo=None
else:
    ids={m.get('photoID') for m in meals};assert len(ids)==1 and None not in ids
    photo_id=next(iter(ids));assert photo_id!=manifest['photoID']
    photo_path=root/'photos'/(photo_id+'.jpg');photo=photo_path.read_bytes()
    assert len(photo)==manifest['photoBytes'] and digest(photo)==manifest['photoSHA256']
    assert {p.name for p in (root/'photos').iterdir()}=={photo_id+'.jpg'}
for actual,expected in zip(meals,expected_records['meals']):
    clean_actual={k:v for k,v in actual.items() if k!='photoID'}
    clean_expected={k:v for k,v in expected.items() if k!='photoID'}
    assert clean_actual==clean_expected
old_intent=json.loads(base64.b64decode(before['health-write-intent.json']['base64']))
new_intent=json.loads((root/'health-write-intent.json').read_bytes())
assert new_intent['owner']==old_intent['owner'] and new_intent['lifecycle']!=old_intent['lifecycle'] and new_intent['events']==[]
copies={}
for name in selected:
    found=[p for p in (root/'.health-recovery').glob('*/'+name) if p.read_bytes()==base64.b64decode(before[name]['base64'])]
    assert found,name;copies[name]=[str(p) for p in found]
receipts=list((root/'.health-recovery-history').glob('*.json'));assert len(receipts)==1
receipt=json.loads(receipts[0].read_bytes());seed=json.loads((base/'health-file-multi-r1-inputs.json').read_text())
expected_name={'legacy':'Lumen-backup-health-multi-legacy.json','encrypted':'Lumen-backup-health-multi-encrypted.lumenbackup','readable':'Lumen-readable-health-multi.json'}[a.case]
expected=next(r for r in seed['files'] if Path(r['input']).name==expected_name)
provider=Path(expected['seeded']);info=provider.lstat();assert provider.read_bytes()==(base/Path(expected['canonical']).name).read_bytes()
assert info.st_ino==expected['inode'] and info.st_dev==expected['device'] and info.st_mode==expected['mode'] and info.st_mtime_ns==expected['modifiedNS']
assert receipt['fileSource']=={'fileName':expected_name,'format':{'legacy':'legacyJSONBackup','encrypted':'encryptedBackup','readable':'readableExport'}[a.case],'byteCount':expected['bytes'],'sha256':expected['sha256']}
assert receipt['source']=='selected-file:'+expected['sha256'] and receipt['domains']==['goals','meals','water','workouts'] and receipt['omittedPhotoCount']==(2 if a.case=='readable' else 0)
assert set(receipt['recordDigests'])==selected
for name in selected:assert receipt['recordDigests'][name]==after[name]['sha256']
assert source_observations
(base/(prefix+'-host-audit.json')).write_text(json.dumps({'status':'PASS actual four-domain selected-file recovery and relaunch','source':a.source,'build':a.build,'case':a.case,'before':before,'after':after,'protectedBefore':protected_before,'previousBefore':previous_before,'preservationBeforeCommit':preservation_before,'sourceObservations':source_observations,'heldPreparation':held,'releasedPreparation':released,'successBeforeRelaunch':success,'finalCleanupBeforeRelaunch':final_cleanup,'protocol':protocol,'producerExitCode':code,'receipt':receipt,'retainedDamagedPaths':copies,'sharedPhotoSHA256':digest(photo) if photo else None,'providerIdentityExact':True,'verifierSHA256':digest(Path(__file__).read_bytes()),'scope':'Main/standard selected unavailable four-domain replacement only; full photo/healthy merge/fault/appearance/eight-group contract remains.'},indent=2)+'\n')
print('PASS:',a.case,'actual four-domain recovery/source/photo/receipt audit')
