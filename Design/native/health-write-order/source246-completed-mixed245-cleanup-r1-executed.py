"""Remove only reviewed exact-GitHub-backed completed Mixed245 raw duplicates."""
from pathlib import Path
import hashlib,json,os,shutil,stat,subprocess,time
B=Path(__file__).resolve().parent;R=B.parents[2]
proof=json.loads((B/'source245-native-exact-github.json').read_bytes());assert proof['commit']=='16f707116f92a754d59466f194de1b0025a4060b' and proof['unionPaths']==1522
by={x['file']:x for x in proof['proofs']};required=list(B.glob('health-mixed-ineligible-source245r1-*'))+[B/n for n in ['health-mixed-ineligible-source245-round2-part152-native.json','source245-root-part152-review.json','source245-root-native-original-observations-r1.json','source245-root-native-final-audit-r1.json','source245-mixed-r1-checker-execution.json','source245-mixed-r1-checker.json','HealthMixedIneligibleSource245R1.log.gz']]
for p in required:
 data=p.read_bytes();want=by[str(p.relative_to(R))];assert not p.is_symlink() and len(data)==want['bytes'] and hashlib.sha256(data).hexdigest()==want['sha256']
state=json.loads((B/'health-mixed-ineligible-source245r1-host-audit.json').read_bytes());assert state['nativeExit']==0
assert all(not Path(n).exists() for k in ['selection','relaunchSelection'] for n in state[k]['workspaces'])
query=subprocess.run(['/bin/ps','-axo','pid=,comm='],capture_output=True,check=True);assert not query.stderr
parsed=[]
for line in query.stdout.decode().splitlines():
 if not line.strip():continue
 pid,command=line.strip().split(None,1);assert pid.isdigit();parsed.append((int(pid),command))
assert parsed and not any(pid==state['pid'] or Path(command).name in ['xcodebuild','swift-frontend'] for pid,command in parsed)
base=Path('/tmp/LumenBatch44Checks');stem='HealthMixedIneligibleSource245R1';targets=[base/(stem+x) for x in ['.xcresult','PNG','JSON','All','.log','-summary.json']];rows=[];allocated=count=0
for p in targets:
 assert os.path.lexists(p) and not p.is_symlink();items=[p]
 if p.is_dir():
  for parent,dirs,names in os.walk(p,followlinks=False):items.extend(Path(parent)/n for n in dirs+names)
 subtotal=0
 for item in items:
  f=item.lstat();assert stat.S_ISREG(f.st_mode) or stat.S_ISDIR(f.st_mode)
  if stat.S_ISREG(f.st_mode):count+=1;subtotal+=f.st_blocks*512
 allocated+=subtotal;rows.append({'path':str(p),'allocatedRegularBytes':subtotal})
output=B/'source246-completed-mixed245-cleanup-r1.json';assert not output.exists()
out={'status':'PREPARED exact1522backed Mixed245raw only','proofCommit':proof['commit'],'unionPaths':1522,'canonicalFilesVerified':len(required),'targets':rows,'regularFiles':count,'symlinks':0,'allocatedRegularBytes':allocated,'nativePID':state['pid'],'nativePIDAbsent':True,'noActiveXcodebuildOrSwiftFrontend':True,'processListBytes':len(query.stdout),'processListSHA256':hashlib.sha256(query.stdout).hexdigest(),'deleted':[],'started':time.time()}
def persist():output.write_text(json.dumps(out,indent=2)+'\n')
persist();before=shutil.disk_usage(R).free;out['beforeAvailableBytes']=before;persist()
for p in targets:
 if p.is_dir():shutil.rmtree(p)
 else:p.unlink()
 assert not os.path.lexists(p);out['deleted'].append(str(p));persist()
after=shutil.disk_usage(R).free;credit=min(allocated,max(0,after-before));out.update(status='PASS completed backed Mixed245raw removed; raw paths historical, do not rerun old raw/live-source audits',afterAvailableBytes=after,observedAvailableIncrease=after-before,creditedRecoveryBytes=credit,aggregateCreditedRecoveryBytes=14056627799+credit,retained='Canonical15originals/fullhelper/summary/log/reports/source, Debug/packages/provider/skill/unbacked191219; no app data/defaults/workspace/cache/runtime/phone change',finished=time.time());persist();print(json.dumps({k:out[k] for k in ['regularFiles','allocatedRegularBytes','observedAvailableIncrease','creditedRecoveryBytes','aggregateCreditedRecoveryBytes','afterAvailableBytes']}))
