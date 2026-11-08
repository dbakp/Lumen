"""Exact-backed failed247 redundant raw and two dead known synthetic owners only."""
from pathlib import Path
import gzip,hashlib,importlib.util,json,os,shutil,stat,time
B=Path(__file__).resolve().parent;R=B.parents[2];proof=json.loads((B/'source247-native-exact-github.json').read_bytes());assert proof['commit']=='2a1c55d2b40e861d6c22402aafcc825121548e19' and proof['unionPaths']==1641
by={r['file']:r for r in proof['proofs']};prefix='health-legacy-confirmation-data-source247r1';required=list(B.glob(prefix+'-*'))+[B/n for n in ['health-legacy-target-change-source247-round2-part156-native-failure.json','source247-root-part156-review.json','source247-root-native-failure-audit-r1.json','source247-root-native-original-observations-r1.json','source247-post-failure-readonly-diagnostic-r1.json','source247-dependency-diagnostic-r1.json','HealthLegacyConfirmationDataSource247R1.log.gz','source247-target-change-native-build-r1.log.gz']]
for p in required:
 data=p.read_bytes();wanted=by[str(p.relative_to(R))];assert not p.is_symlink() and len(data)==wanted['bytes'] and hashlib.sha256(data).hexdigest()==wanted['sha256']
spec=importlib.util.spec_from_file_location('failed247cleanup',B/'confirmation-target-evidence-r1.py');e=importlib.util.module_from_spec(spec);spec.loader.exec_module(e);h=e.h;process=e.e.module('failed247cleanup_process','target-postrun-process-r1.py');state=json.loads((B/(prefix+'-driver-observations.json')).read_bytes());assert h.DEVICE=='5C4C4A6C-4D9E-4181-8794-E3925C1A7EA7'
assert h.owned(state['appPID'])==state['selection']['workspaces']
raw=Path('/tmp/LumenBatch44Checks');stem='HealthLegacyConfirmationDataSource247R1';targets=[raw/(stem+suffix) for suffix in ['.xcresult','PNG','JSON','All','.log','-summary.json']]+[raw/'Source247TargetChangeNativeBuildR1.log']
assert gzip.decompress((B/'source247-target-change-native-build-r1.log.gz').read_bytes())==targets[-1].read_bytes()
for root,owner in state['selection']['workspaces'].items():
 p=Path(root);assert p.parent==Path(state['appData'])/'tmp' and p.name=='LumenBackupWork-v1-'+str(state['appPID'])+'-'+owner['owner']['id'];targets.append(p)
rows=[];allocated=files=0
for p in targets:
 assert os.path.lexists(p) and not p.is_symlink();items=[p]
 if p.is_dir():
  for parent,dirs,names in os.walk(p,followlinks=False):items.extend(Path(parent)/n for n in dirs+names)
 subtotal=0
 for item in items:
  facts=item.lstat();assert stat.S_ISDIR(facts.st_mode) or stat.S_ISREG(facts.st_mode)
  if stat.S_ISREG(facts.st_mode):files+=1;subtotal+=facts.st_blocks*512
 rows.append({'path':str(p),'allocatedRegularBytes':subtotal});allocated+=subtotal
output=B/'source248-completed-failed247-cleanup-r1.json';assert not output.exists();out={'status':'PREPARED exactbacked obsolete247raw/known2deadowners','proofCommit':proof['commit'],'unionPaths':1641,'canonicalFilesVerified':len(required),'targets':rows,'regularFiles':files,'symlinks':0,'allocatedRegularBytes':allocated,'process':{},'deleted':[],'started':time.time()}
def persist():output.write_text(json.dumps(out,indent=2)+'\n')
persist();assert process.observe(state['appPID'],state['boundaries'][0]['installed']['path'],out['process'],persist)=='absent';assert h.owned(state['appPID'])==state['selection']['workspaces'];before=shutil.disk_usage(R).free;out['beforeAvailableBytes']=before;persist()
for p in targets:
 if p.is_dir():shutil.rmtree(p)
 else:p.unlink()
 assert not os.path.lexists(p);out['deleted'].append(str(p));persist()
after=shutil.disk_usage(R).free;credit=min(allocated,max(0,after-before));out.update(status='PASS backed redundant247raw+two known dead owners removed; oldraw/liveowner paths historical, neverrerunoldaudits',afterAvailableBytes=after,observedAvailableIncrease=after-before,creditedRecoveryBytes=credit,aggregateCreditedRecoveryBytes=14088285783+credit,retained='Canonical65/full37MBvideo/source/reports/Debug/packages/provider/skill/unbacked191219 retained. Manualdeadowner deletion is not productBackclosure acceptance. No defaults/current/prior/private/root reset/cache/runtime/phone action.',finished=time.time());persist();print(json.dumps({k:out[k] for k in ['regularFiles','allocatedRegularBytes','observedAvailableIncrease','creditedRecoveryBytes','aggregateCreditedRecoveryBytes','afterAvailableBytes']}))
