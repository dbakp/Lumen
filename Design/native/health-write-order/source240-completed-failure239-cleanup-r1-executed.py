"""Delete only exact984-backed239 raw duplicates and two known abandoned synthetic roots."""
from pathlib import Path
import json,hashlib,importlib.util,os,stat,shutil,time
B=Path(__file__).resolve().parent;proof=json.loads((B/'source239-native-failure-exact-github.json').read_text());assert proof['commit']=='6290f329015b3770e5dfde4b09cb8b14cc9e7020' and proof['unionPaths']==984
repo=B.parents[2];by={r['file']:r for r in proof['proofs']};required=list(B.glob('health-legacy-target-change-string-source239r1-*'))+[B/'health-legacy-target-change-source239-round2-part137-native-type-failure.json',B/'source239-root-part137-review.json',B/'source239-post-failure-readonly-diagnostic-r1.json']
for path in required:
 raw=path.read_bytes();r=by[str(path.relative_to(repo))];assert not path.is_symlink() and len(raw)==r['bytes'] and hashlib.sha256(raw).hexdigest()==r['sha256']
spec=importlib.util.spec_from_file_location('cleanup240base',B/'target-string-evidence-r1.py');e=importlib.util.module_from_spec(spec);spec.loader.exec_module(e);h=e.h;p=e.e.module('cleanup240process','target-postrun-process-r1.py')
s=json.loads((B/'health-legacy-target-change-string-source239r1-driver-observations.json').read_text());late=json.loads((B/'source239-post-failure-readonly-diagnostic-r1.json').read_text());assert h.owned(s['appPID'])==s['selection']['workspaces']==late['samples'][-1]['ownedWorkspaces']
rawbase=Path('/tmp/LumenBatch44Checks');stem='HealthLegacyTargetChangeStringSource239R1';targets=[rawbase/(stem+suffix) for suffix in ['.xcresult','PNG','JSON','All','.log','-summary.json']]
for name,value in s['selection']['workspaces'].items():
 path=Path(name);assert path.parent==Path(s['appData'])/'tmp' and path.name=='LumenBackupWork-v1-'+str(s['appPID'])+'-'+value['owner']['id'];targets.append(path)
rows=[];allocated=0;files=0
for path in targets:
 assert os.path.lexists(path) and not path.is_symlink();items=[path]
 if path.is_dir():
  for parent,dirs,names in os.walk(path,followlinks=False):items.extend(Path(parent)/n for n in dirs+names)
 subtotal=0
 for item in items:
  st=item.lstat();assert stat.S_ISREG(st.st_mode) or stat.S_ISDIR(st.st_mode)
  if stat.S_ISREG(st.st_mode):files+=1;subtotal+=st.st_blocks*512
 allocated+=subtotal;rows.append({'path':str(path),'allocatedRegularBytes':subtotal})
output=B/'source240-completed-failure239-cleanup-r1.json';assert not output.exists();out={'status':'PREPARED verified984backed239raw/known2syntheticroots','proofCommit':proof['commit'],'exactUnion':984,'canonicalPathsVerified':len(required),'targets':rows,'regularFiles':files,'symlinks':0,'allocatedRegularBytes':allocated,'process':{},'deleted':[],'started':time.time()}
def persist():output.write_text(json.dumps(out,indent=2)+'\n')
persist();assert p.observe(s['appPID'],s['boundaries'][0]['installed']['path'],out['process'],persist)=='absent';assert h.owned(s['appPID'])==s['selection']['workspaces'];before=shutil.disk_usage(repo).free;out['beforeAvailableBytes']=before;persist()
for path in targets:
 if path.is_dir():shutil.rmtree(path)
 else:path.unlink()
 assert not os.path.lexists(path);out['deleted'].append(str(path));persist()
after=shutil.disk_usage(repo).free;credit=min(allocated,max(0,after-before));out.update(status='PASS exact-backed completed239 rawduplicates and two verifieddead knownsyntheticworkspaces removed; Debug/packages/canonical196/fullvideo/provider/skill/unbacked191219 kept',afterAvailableBytes=after,observedAvailableIncrease=after-before,creditedRecoveryBytes=credit,aggregateCreditedRecoveryBytes=11948994135+credit,finished=time.time());persist();print(json.dumps({k:out[k] for k in ['regularFiles','allocatedRegularBytes','observedAvailableIncrease','creditedRecoveryBytes','aggregateCreditedRecoveryBytes','afterAvailableBytes']}))
