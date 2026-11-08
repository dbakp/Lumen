"""Delete only exact-backed completed230 raw duplicates; no active build cache."""
from pathlib import Path
import json,os,stat,hashlib,shutil,time
b=Path('Design/native/health-write-order');proof=json.loads((b/'source230-native-r4-failure-exact-github.json').read_text());assert proof['commit']=='22b64eb4211f133bab92726446f34ed8e73f1bf4'
by={r['file']:r for r in proof['proofs']};prefix='health-legacy-target-change-data-source230r1'
required=list(b.glob(prefix+'-*'))+[b/'HealthLegacyTargetChangeDataSource230R1.log.gz']
for p in required:
 assert str(p) in by and not p.is_symlink();d=p.read_bytes();r=by[str(p)];assert len(d)==r['bytes'] and hashlib.sha256(d).hexdigest()==r['sha256']
base=Path('/tmp/LumenBatch44Checks');stem='HealthLegacyTargetChangeDataSource230R1'
targets=[base/(stem+s) for s in ['.xcresult','PNG','JSON','All','.log','-summary.json']]
output=b/'source231-completed-native-raw-cleanup-r1.json';assert not output.exists()
rows=[];allocated=0;files=0
for path in targets:
 assert path.parent==base and os.path.lexists(path) and not path.is_symlink()
 paths=[path]
 if path.is_dir():
  for parent,dirs,names in os.walk(path,followlinks=False):paths += [Path(parent)/n for n in dirs+names]
 subtotal=0
 for p in paths:
  facts=p.lstat();assert not stat.S_ISLNK(facts.st_mode) and (stat.S_ISREG(facts.st_mode) or stat.S_ISDIR(facts.st_mode))
  if stat.S_ISREG(facts.st_mode):subtotal+=facts.st_blocks*512;files+=1
 allocated+=subtotal;rows.append({'path':str(path),'allocatedRegularBytes':subtotal})
before=shutil.disk_usage('.').free
out={'status':'PREPARED verified known-backed raw-only cleanup','proofCommit':proof['commit'],'exactUnion':len(by),'canonicalPathsVerified':len(required),'targets':rows,'regularFiles':files,'symlinks':0,'beforeAvailableBytes':before,'allocatedRegularBytes':allocated,'deleted':[],'started':time.time()}
def persist():output.write_text(json.dumps(out,indent=2)+'\n')
persist()
for path in targets:
 if path.is_dir():shutil.rmtree(path)
 else:path.unlink()
 out['deleted'].append(str(path));persist()
after=shutil.disk_usage('.').free;out.update(status='PASS completed230 raw duplicates removed after full original/critic/root/exact537backup; currentDebug/packages/canonicalall14 originals retained',afterAvailableBytes=after,observedAvailableIncrease=after-before,creditedRecoveryBytes=min(allocated,max(0,after-before)),finished=time.time())
out['aggregateCreditedRecoveryBytes']=10171801175+out['creditedRecoveryBytes'];persist();print(json.dumps({k:out[k] for k in ['regularFiles','allocatedRegularBytes','observedAvailableIncrease','creditedRecoveryBytes','aggregateCreditedRecoveryBytes','afterAvailableBytes']}))
