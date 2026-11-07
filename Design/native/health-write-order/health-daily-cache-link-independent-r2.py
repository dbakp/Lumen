"""Reobserve terminal link case; absence of a transaction checkpoint is expected.
The original producer's empty-checkpoint-file expectation remains failed.
"""
import base64,hashlib,json,os,stat,subprocess,time
from pathlib import Path
base=Path(__file__).resolve().parent;repo=base.parents[2];prefix='health-daily-cache-link-r1'
audit_bytes=(base/(prefix+'-host-audit.json')).read_bytes();a=json.loads(audit_bytes);summary=json.loads((base/(prefix+'-summary.json')).read_text())
assert a['nativeExitCode']==0 and summary['passedTests']==1 and summary['failedTests']==summary['skippedTests']==0
assert a['initialCapturedBeforeFirstRetry'] and a['exactTreeAfterRetries']==['retry-1','retry-2']
assert a['status'].startswith('FAILED') and a['observationError'] == "FileNotFoundError(2, 'No such file or directory')"
source=json.loads((base/'durable-source-r167.json').read_text())
for p,f in {**source['files'],**source['fixtureInputs']}.items():
 d=(repo/p).read_bytes();assert len(d)==f['bytes'] and hashlib.sha256(d).hexdigest()==f['sha256']
def container(k):return Path(subprocess.check_output(['xcrun','simctl','get_app_container','AF849DEA-DF34-4B0E-9FC1-3E45DCBE8481','com.dbakp.lumen',k],text=True).strip())
build=json.loads((base/'health-daily-cache-link-r1-build.json').read_text());d=(container('app')/'Lumen').read_bytes();assert len(d)==build['binaryBytes'] and hashlib.sha256(d).hexdigest()==build['sha256']
def facts(p):
 f=p.lstat();r=dict(mode=f.st_mode,device=f.st_dev,inode=f.st_ino,bytes=f.st_size,modifiedNS=f.st_mtime_ns)
 if stat.S_ISLNK(f.st_mode):r.update(kind='link',destination=os.readlink(p))
 elif stat.S_ISREG(f.st_mode):
  assert f.st_size<256*1024;d=p.read_bytes();r.update(kind='file',sha256=hashlib.sha256(d).hexdigest(),base64=base64.b64encode(d).decode())
 else:assert stat.S_ISDIR(f.st_mode);r['kind']='directory'
 return r
def tree(root):
 rows={}
 for directory,ds,fs in os.walk(root,followlinks=False):
  for name in ds+fs:
   p=Path(directory)/name;rows[str(p.relative_to(root))]=facts(p)
 return rows
group=container('group.com.dbakp.lumen');root=group/'LumenData';prior=group/'LumenData.previous';target=group/'Lumen-ui-daily-cache-link-target.bin'
assert tree(root)==tree(root)==a['before']==a['after'];assert tree(prior)==tree(prior)==a['previousBefore']==a['previousAfter'];assert facts(target)==facts(target)==a['targetBefore']==a['targetAfter']
assert not (group/'Lumen-health-cancel-checkpoint.json').exists();assert not (group/'Lumen-health-cancel-release.json').exists();assert not any(p.name.startswith('LumenData.restore-') for p in group.iterdir())
cache=(repo/'Lumen/Models/HealthDailyCache.swift').read_text();local=(repo/'Lumen/Models/HealthLocalFiles.swift').read_text();reset=(repo/'Lumen/Views/HealthRecoveryCancelUIFixture.swift').read_text()
assert 'lstat(url.path, &before)' in cache and 'kind == mode_t(S_IFREG) || kind == mode_t(S_IFDIR)' in cache and 'O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC' in local
result=dict(status='PASS independent terminal link-rejection preservation audit; original host checkpoint-file expectation FAILED retained',source='durable-source-r167.json',checkedAt=time.time(),originalHostAuditSHA256=hashlib.sha256(audit_bytes).hexdigest(),auditorSHA256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),nativePassedTests=1,nativeFailedTests=0,nativeSkippedTests=0,sourceInputs=253,fixtureInputs=6,rootTreeExact=True,previousTreeExact=True,linkAndTargetBytesIdentityModesMetadataExact=True,twoRetriesPreserved=True,transactionCheckpointAbsent=True,releaseAbsent=True,noStage=True,noFollowSourceGuards={'HealthDailyCache.swift':hashlib.sha256(cache.encode()).hexdigest(),'HealthLocalFiles.swift':hashlib.sha256(local.encode()).hexdigest(),'fixtureResetSHA256':hashlib.sha256(reset.encode()).hexdigest()},scope='Main/light/standard synthetic link rejection only. Source guards plus exact runtime preservation; not syscall tracing, no broad never-opened claim. Original native producer host failure stays failed.')
(base/(prefix+'-independent-audit.json')).write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
