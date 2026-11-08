"""Known synthetic failed-case raw duplicates only, after exact full GitHub backup."""
from pathlib import Path
import importlib.util,json,os,stat,hashlib,shutil,time,subprocess
b=Path('Design/native/health-write-order');proof=json.loads((b/'source234-native-failure-exact-github.json').read_text());assert proof['commit']=='f8ed03e1c8483d66db67b5fa0f1bcdc9311d34e9';by={r['file']:r for r in proof['proofs']}
prefix='health-legacy-target-change-data-source234r1'
required=list(b.glob(prefix+'-*'))+[b/'HealthLegacyTargetChangeDataSource234R1.log.gz',b/'source234-root-part126-review.json',b/'health-legacy-target-change-source234-round2-part126-native-visibility-failure.json']
for path in required:
 assert str(path) in by and not path.is_symlink();raw=path.read_bytes();r=by[str(path)];assert len(raw)==r['bytes'] and hashlib.sha256(raw).hexdigest()==r['sha256']
spec=importlib.util.spec_from_file_location('cleanup234evidence',b/'legacy-target-change-evidence-r5.py');e=importlib.util.module_from_spec(spec);spec.loader.exec_module(e);h=e.h;p=e.e.module('cleanup234process','target-postrun-process-r1.py')
state=json.loads((b/(prefix+'-driver-observations.json')).read_text());process={};p.observe(state['appPID'],state['boundaries'][0]['installed']['path'],process,lambda:None);assert process['mode']=='absent'
assert str(h.container('data'))==state['appData']
owned=h.owned(state['appPID']);assert owned==state['freshSelection']['workspaces'] and len(owned)==2
for root in owned:
 path=Path(root);assert path.parent==Path(state['appData'])/'tmp' and path.name.startswith('LumenBackupWork-v1-'+str(state['appPID'])+'-')
base=Path('/tmp/LumenBatch44Checks');stem='HealthLegacyTargetChangeDataSource234R1';targets=[base/(stem+s) for s in ['.xcresult','PNG','JSON','All','.log','-summary.json']]+[Path(n) for n in owned]
output=b/'source235-completed-failure-raw-cleanup-r1.json';assert not output.exists();rows=[];allocated=0;files=0
for path in targets:
 assert os.path.lexists(path) and not path.is_symlink();paths=[path]
 if path.is_dir():
  for parent,dirs,names in os.walk(path,followlinks=False):paths += [Path(parent)/n for n in dirs+names]
 subtotal=0
 for path2 in paths:
  facts=path2.lstat();assert not stat.S_ISLNK(facts.st_mode) and (stat.S_ISREG(facts.st_mode) or stat.S_ISDIR(facts.st_mode))
  if stat.S_ISREG(facts.st_mode):subtotal+=facts.st_blocks*512;files+=1
 allocated+=subtotal;rows.append({'path':str(path),'allocatedRegularBytes':subtotal})
before=shutil.disk_usage('.').free
out={'status':'PREPARED full failed originals exact backed; process absent and two known synthetic workspaces exact to retained source','proofCommit':proof['commit'],'exactUnion':len(by),'canonicalPathsVerified':len(required),'targets':rows,'regularFiles':files,'symlinks':0,'process':process,'ownedWorkspaces':owned,'beforeAvailableBytes':before,'allocatedRegularBytes':allocated,'deleted':[],'started':time.time(),'scope':'Host cleanup after failed case, not native Back/owner-closure acceptance. Original FAILED0/1/0/native65/driver1/R8FAILED immutable. All canonical194 originals/fullvideo retained; Debug/packages/skill/provider/191+219unbackedvideos untouched.'}
def persist():output.write_text(json.dumps(out,indent=2)+'\n')
persist()
for path in targets:
 if path.is_dir():shutil.rmtree(path)
 else:path.unlink()
 out['deleted'].append(str(path));persist()
after=shutil.disk_usage('.').free;out.update(status='PASS scoped disposable raw234 duplicates and two known synthetic abandoned workspaces removed after full exact backup',afterAvailableBytes=after,observedAvailableIncrease=after-before,creditedRecoveryBytes=min(allocated,max(0,after-before)),finished=time.time());out['aggregateCreditedRecoveryBytes']=10884644439+out['creditedRecoveryBytes'];persist();print(json.dumps({k:out[k] for k in ['regularFiles','allocatedRegularBytes','observedAvailableIncrease','creditedRecoveryBytes','aggregateCreditedRecoveryBytes','afterAvailableBytes']}))
