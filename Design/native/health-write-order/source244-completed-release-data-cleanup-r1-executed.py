"""Remove only verified task-owned completed244Release/normalData outputs; preserve immediate Debug reuse."""
from pathlib import Path
import json,os,stat,hashlib,shutil,subprocess,time
b=Path('Design/native/health-write-order');proof=json.loads((b/'source244-release-data-exact-github.json').read_text());assert proof['commit']=='a61f745fa801c229f43e2e5bdee91fa7fc53a770' and proof['unionPaths']==1402
by={r['file']:r for r in proof['proofs']};required=[b/'health-legacy-target-change-source244-round2-part149-data-native.json',b/'source244-root-part149-review.json',b/'source244-data-root-native-final-audit-r1.json',b/'source244-data-root-native-original-observations-r1.json',b/'health-current-release-source244-round2-part148.json',b/'source244-root-part148-review.json',b/'source244-unsigned-release-r1-build.log.gz',b/'source244-unsigned-release-r1-settings-audit.json',b/'source244-unsigned-release-r1-swift-filelist.txt.gz']+list(b.glob('health-legacy-target-change-data-source244datar1-*'))
for p in required:
 assert not p.is_symlink();d=p.read_bytes();r=by[str(p)];assert len(d)==r['bytes'] and hashlib.sha256(d).hexdigest()==r['sha256']
raw=Path('/tmp/LumenBatch44Checks');stem='HealthLegacyTargetChangeDataSource244DataR1';targets=[raw/(stem+s) for s in ['.xcresult','PNG','JSON','All','.log','-summary.json']]+[Path('/tmp/LumenBatch37Release')]+[raw/n for n in ['Source244UnsignedReleaseR1.log','Source244UnsignedReleaseR1Settings.json','Source244UnsignedReleaseR1Settings.log']]
auditlog=raw/'Source244UnsignedReleaseR1Audit.log'
assert auditlog.read_text()==json.loads((b/'health-current-release-source244-r1-outcome.json').read_text())['auditOutput'];targets.append(auditlog)
ps=subprocess.run(['ps','-axo','pid=,command='],capture_output=True,text=True,check=True).stdout
active=[line for line in ps.splitlines() if any(n in line for n in ['xcodebuild','swift-frontend','clang -']) and any(str(p) in line for p in targets)];assert not active,active
rows=[];files=0;links=0;allocated=0
for p in targets:
 assert os.path.lexists(p) and not p.is_symlink() and (p.parent==raw or p==Path('/tmp/LumenBatch37Release'))
 items=[p]
 if p.is_dir():
  for parent,dirs,names in os.walk(p,followlinks=False):items.extend(Path(parent)/n for n in dirs+names)
 subtotal=0
 for item in items:
  st=item.lstat();assert stat.S_ISREG(st.st_mode) or stat.S_ISDIR(st.st_mode) or stat.S_ISLNK(st.st_mode)
  if stat.S_ISREG(st.st_mode):files+=1;subtotal+=st.st_blocks*512
  elif stat.S_ISLNK(st.st_mode):links+=1
 allocated+=subtotal;rows.append({'path':str(p),'allocatedRegularBytes':subtotal})
output=b/'source244-completed-release-data-cleanup-r1.json';assert not output.exists();before=shutil.disk_usage('.').free
out={'status':'PREPARED exact1402backed completed244Release/normalData outputs only','proofCommit':proof['commit'],'exactUnion':1402,'canonicalPathsVerified':len(required),'targets':rows,'regularFiles':files,'symlinksUnlinkedWithoutFollowing':links,'beforeAvailableBytes':before,'allocatedRegularBytes':allocated,'deleted':[],'started':time.time()}
def persist():output.write_text(json.dumps(out,indent=2)+'\n')
persist()
for p in targets:
 if p.is_dir():shutil.rmtree(p)
 else:p.unlink()
 assert not os.path.lexists(p);out['deleted'].append(str(p));persist()
after=shutil.disk_usage('.').free;credit=min(allocated,max(0,after-before));out.update(status='PASS exact-backed completed244 Release cache and rawData244 duplicates removed; canonical evidence/currentDebug/packages/provider/skill/unbacked191219videos retained',afterAvailableBytes=after,observedAvailableIncrease=after-before,creditedRecoveryBytes=credit,aggregateCreditedRecoveryBytes=13293731415+credit,finished=time.time());persist();print(json.dumps({k:out[k] for k in ['regularFiles','symlinksUnlinkedWithoutFollowing','allocatedRegularBytes','observedAvailableIncrease','creditedRecoveryBytes','aggregateCreditedRecoveryBytes','afterAvailableBytes']}))
