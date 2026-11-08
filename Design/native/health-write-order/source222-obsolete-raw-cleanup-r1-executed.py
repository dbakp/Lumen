"""Delete only backed completed220 raw peers and compacted isolated temp fixtures."""
from pathlib import Path
import base64,gzip,hashlib,json,os,shutil,stat,subprocess,time
repo=Path('/Users/davidbakposada/Documents/ChatGPT/Lumen');base=repo/'Design/native/health-write-order';raw=Path('/tmp/LumenBatch44Checks')
sha=lambda d:hashlib.sha256(d).hexdigest();proofs={};targets=[]

def backed(path,commit):
    path=Path(path);name=str(path.relative_to(repo));assert not path.is_symlink()
    data=path.read_bytes();assert subprocess.check_output(['git','show',commit+':'+name],cwd=repo)==data,name
    proofs[name]={'file':name,'bytes':len(data),'sha256':sha(data),'commit':commit};return data

old='0472fddabaedc17e7b17218f7709501f04406f88';current='4f754205e3241170843eaaeb412ab6190870c1f1'
assert subprocess.run(['git','merge-base','--is-ancestor',old,'origin/main'],cwd=repo).returncode==0
assert subprocess.run(['git','merge-base','--is-ancestor',current,'origin/main'],cwd=repo).returncode==0
for stem,prefix,review,root in [
 ('HealthCaptureStatePendingBackSource220R1','health-capture-state-pending-back-source220r1','health-legacy-capture-state-source220-round2-part90-pending-back-native.json','source220-capture-state-pending-back-r1-root-review-final.json'),
 ('HealthCaptureStateRetryFailureSource220R2','health-capture-state-retry-failure-source220r2','health-legacy-capture-state-source220-round2-part92-retry-failure-native.json','source220-capture-state-retry-failure-r2-root-review-final.json')]:
    outcome=json.loads(backed(base/(prefix+'-outcome.json'),old));assert outcome['nativeExit']==outcome['driverExit']==0 and outcome['hostError'] is None
    for name in [review,root,prefix+'-host-audit.json',prefix+'-retention-state.json','durable-source-r220.json','durable-source-r220.json.gz']:backed(base/name,old)
    for kind in ['images','readbacks']:
        for row in json.loads(backed(base/(prefix+'-'+kind+'.json'),old)):
            data=backed(base/row['file'],old);assert row['individuallyOpened'] and Path(row['raw']).read_bytes()==data
    for kind in ['png','json']:
        assert (raw/(stem+kind.upper())/'manifest.json').read_bytes()==gzip.decompress(backed(base/(prefix+'-'+kind+'-original-manifest.json.gz'),old))
    assert (raw/(stem+'.log')).read_bytes()==gzip.decompress(backed(base/(stem+'.log.gz'),old))
    assert (raw/(stem+'-summary.json')).read_bytes()==backed(base/(prefix+'-summary.json'),old)
    targets.extend(raw/(stem+suffix) for suffix in ['.xcresult','PNG','JSON','.log','-summary.json'])
for archive_name,outcome_name,directory in [
 ('reset-harness-isolated-r1-first-preparation-failure.json.gz',None,'/tmp/LumenResetHarnessIsolatedR1-f_q353qu'),
 ('reset-harness-isolated-r1-fixtures.json.gz','reset-harness-isolated-r1-outcome.json','/tmp/LumenResetHarnessIsolatedR1-tls095sd'),
 ('reset-inventory-isolated-r1-fixtures.json.gz','reset-inventory-isolated-r1-outcome.json','/tmp/LumenResetInventoryIsolatedR1-xbxzqvzn')]:
    archive=json.loads(gzip.decompress(backed(base/archive_name,current)));folder=Path(directory)
    if outcome_name:
        outcome=json.loads(backed(base/outcome_name,current));assert outcome['temporaryDirectory']==directory
    expected=set(archive['files'])
    for name,row in archive['files'].items():
        path=folder/name;assert not path.is_symlink();data=path.read_bytes()
        assert data==base64.b64decode(row['base64'],validate=True) and len(data)==row['bytes'] and sha(data)==row['sha256']
    regular={str(p.relative_to(folder)) for p in folder.rglob('*') if p.is_file() and not p.is_symlink()}
    extra=regular-expected
    assert extra==({'Context'} if 'tls095sd' in directory else set()),extra
    if extra:assert (folder/'Context').stat().st_size==outcome['compiledContextExecutableBytes']
    targets.append(folder)
assert len(targets)==13
inventory=[];seen=set();allocated=regular_count=symlink_count=0
for target in targets:
    assert target.exists() and not target.is_symlink()
    assert target.parent==raw or target.parent==Path('/tmp') and target.name in ['LumenResetHarnessIsolatedR1-f_q353qu','LumenResetHarnessIsolatedR1-tls095sd','LumenResetInventoryIsolatedR1-xbxzqvzn']
    scan=subprocess.run(['lsof','-nP','+D',str(target)] if target.is_dir() else ['lsof','-nP',str(target)],capture_output=True,text=True)
    assert scan.returncode==1 and not scan.stdout,'Open disposable path: '+str(target)
    files=[target] if target.is_file() else [Path(p)/n for p,ds,fs in os.walk(target,followlinks=False) for n in fs]
    entries=[]
    for path in files:
        facts=path.lstat()
        if stat.S_ISLNK(facts.st_mode):symlink_count+=1;continue
        assert stat.S_ISREG(facts.st_mode);regular_count+=1
        key=(facts.st_dev,facts.st_ino)
        if key not in seen:seen.add(key);allocated+=facts.st_blocks*512
        entries.append({'file':str(path.relative_to(target)) if target.is_dir() else target.name,'bytes':facts.st_size,'sha256':sha(path.read_bytes())})
    inventory.append({'path':str(target),'regularFiles':entries})
before=shutil.disk_usage(repo).free
for target in targets:
    shutil.rmtree(target) if target.is_dir() else target.unlink();assert not os.path.lexists(target)
after=shutil.disk_usage(repo).free
result={'status':'PASS13 named backed obsolete raw/temp targets removed','remoteProofs':list(proofs.values()),'removed':inventory,
 'regularFiles':regular_count,'symlinksUnlinkedWithoutFollowing':symlink_count,'uniqueAllocatedBytes':allocated,
 'availableBytesBefore':before,'availableBytesAfter':after,'observedFreeDeltaBytes':after-before,'positiveRecoveryCreditBytes':min(allocated,max(0,after-before)),
 'scope':'Completed220raw duplicates after90/92fullreview/exact0472 proofs, isolated131current+20historical payloads after94/source222exact4f proofs. Current222native/Release files and all native/package/Release caches are outside13targets. Both unbacked191/219videos, canonical originals/fullhelpers/reports/source and unrelated data retained. No simulator state change or cleanup-only build.',
 'checkedAt':time.time()}
(base/'source222-obsolete-raw-cleanup-r1.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({k:result[k] for k in ['status','regularFiles','symlinksUnlinkedWithoutFollowing','uniqueAllocatedBytes','observedFreeDeltaBytes','positiveRecoveryCreditBytes','availableBytesAfter']}))
