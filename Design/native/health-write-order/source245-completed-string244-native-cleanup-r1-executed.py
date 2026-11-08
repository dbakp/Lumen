"""Remove only exact1452-backed completed String244 raw result/export duplicates."""
from pathlib import Path
import json,hashlib,importlib.util,os,stat,shutil,time
B=Path(__file__).resolve().parent;repo=B.parents[2];proof=json.loads((B/'source244-string-exact-github.json').read_text());assert proof['commit']=='b02f7464cbb16201f51b31e46205c56164f597e3' and proof['unionPaths']==1452
by={r['file']:r for r in proof['proofs']};required=list(B.glob('health-legacy-target-change-string-source244stringr1-*'))+[B/'health-legacy-target-change-source244-round2-part150-string-native.json',B/'source244-root-part150-review.json',B/'source244-string-root-native-original-observations-r1.json',B/'source244-string-root-native-final-audit-r1.json',B/'HealthLegacyTargetChangeStringSource244StringR1.log.gz']
for path in required:
 raw=path.read_bytes();r=by[str(path.relative_to(repo))];assert not path.is_symlink() and len(raw)==r['bytes'] and hashlib.sha256(raw).hexdigest()==r['sha256']
spec=importlib.util.spec_from_file_location('cleanup244healthy',B/'healthy-target-evidence-r3.py');e=importlib.util.module_from_spec(spec);spec.loader.exec_module(e);h=e.h;p=e.e.module('cleanup244healthyprocess','target-postrun-process-r1.py');s=json.loads((B/'health-legacy-target-change-string-source244stringr1-host-audit.json').read_text());assert not h.owned(s['appPID'])
rawbase=Path('/tmp/LumenBatch44Checks');stem='HealthLegacyTargetChangeStringSource244StringR1';targets=[rawbase/(stem+suffix) for suffix in ['.xcresult','PNG','JSON','All','.log','-summary.json']];rows=[];allocated=files=0
for path in targets:
 assert os.path.lexists(path) and not path.is_symlink();items=[path]
 if path.is_dir():
  for parent,dirs,names in os.walk(path,followlinks=False):items.extend(Path(parent)/n for n in dirs+names)
 subtotal=0
 for item in items:
  st=item.lstat();assert stat.S_ISREG(st.st_mode) or stat.S_ISDIR(st.st_mode)
  if stat.S_ISREG(st.st_mode):files+=1;subtotal+=st.st_blocks*512
 allocated+=subtotal;rows.append({'path':str(path),'allocatedRegularBytes':subtotal})
output=B/'source245-completed-string244-native-cleanup-r1.json';assert not output.exists();out={'status':'PREPARED exact-backed String244raw duplicates only','proofCommit':proof['commit'],'exactUnion':1452,'canonicalPathsVerified':len(required),'targets':rows,'regularFiles':files,'symlinks':0,'allocatedRegularBytes':allocated,'process':{},'deleted':[],'started':time.time()}
def persist():output.write_text(json.dumps(out,indent=2)+'\n')
persist();assert p.observe(s['appPID'],s['boundaries'][0]['installed']['path'],out['process'],persist)=='absent';assert not h.owned(s['appPID']);before=shutil.disk_usage(repo).free;out['beforeAvailableBytes']=before;persist()
for path in targets:
 if path.is_dir():shutil.rmtree(path)
 else:path.unlink()
 assert not os.path.lexists(path);out['deleted'].append(str(path));persist()
after=shutil.disk_usage(repo).free;credit=min(allocated,max(0,after-before));out.update(status='PASS backed completed String244raw duplicates removed; currentMixed245 raw/currentDebug/packages/canonical17/provider/skill/unbacked191219 retained',afterAvailableBytes=after,observedAvailableIncrease=after-before,creditedRecoveryBytes=credit,aggregateCreditedRecoveryBytes=14027923031+credit,finished=time.time());persist();print(json.dumps({k:out[k] for k in ['regularFiles','allocatedRegularBytes','observedAvailableIncrease','creditedRecoveryBytes','aggregateCreditedRecoveryBytes','afterAvailableBytes']}))
