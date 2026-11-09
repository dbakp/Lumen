"""Remove only exact-backed completed257 cache/raw acquisitions; preserve current Debug/packages."""
from pathlib import Path
import hashlib,importlib.util,json,os,shutil,stat,subprocess,time,traceback
B=Path(__file__).resolve().parent;R=B.parents[2];load=lambda n:json.loads((B/n).read_bytes());sha=lambda raw:hashlib.sha256(raw).hexdigest()
proof=load('source257-release-exact-github.json');commit=proof['commit'];assert proof['unionPaths']==2410 and commit=='5701c734fee2e101d04e3f978a752865eda1159c'
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=R,text=True).strip()==commit==subprocess.check_output(['git','rev-parse','origin/main'],cwd=R,text=True).strip()
assert subprocess.check_output(['git','branch','--show-current'],cwd=R,text=True).strip()=='main'
rows={row['file']:row for row in proof['proofs']};required=set()
for name in ['health-current-release-source257-round2-part178.json','source257-root-part178-review.json','health-legacy-confirmation-expiry-source257-round2-part177-native.json','source257-root-part177-review.json']:
 required.add(str((B/name).relative_to(R)))
for row in load('health-current-release-source257-round2-part178.json')['bindings']:required.add(row['file'])
for prefix in ['health-confirmation-notnow-data-source257r1','health-confirmation-expiry-data-source257r1']:
 for name in ['images','readbacks']:
  for row in load(prefix+'-'+name+'.json'):required.add(str((B/row['file']).relative_to(R)))
for name in required:
 p=R/name;assert not p.is_symlink() and name in rows;raw=p.read_bytes();assert len(raw)==rows[name]['bytes'] and sha(raw)==rows[name]['sha256']
report={'status':'PENDING guarded scoped completed257 cleanup','priorExactCommit':commit,'priorUnion':2410,'verifiedCanonicalBindings':len(required),'beforeAvailableBytes':shutil.disk_usage(R).free,'checkedAt':time.time(),'processGuards':[],'removedPaths':[]}
out=B/'source258-completed257-cleanup-r1.json';assert not out.exists()
def persist():out.write_text(json.dumps(report,indent=2)+'\n')
persist()
try:
 spec=importlib.util.spec_from_file_location('cleanup_process_classification',B/'target-postrun-process-r1.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
 for prefix in ['health-confirmation-notnow-data-source257r1','health-confirmation-expiry-data-source257r1']:
  state=load(prefix+'-host-audit.json');guard={};report['processGuards'].append(guard);assert m.observe(state['appPID'],state['boundaries'][0]['installed']['path'],guard,persist)=='absent'
  roots=[path for key in ['selection','freshSelection'] for path in state[key]['workspaces']];assert all(not os.path.lexists(path) for path in roots)
  guard['knownCaseRootsAlreadyAbsent']=roots;persist()
 query=subprocess.run(['/bin/ps','-axo','pid=,comm=,args='],capture_output=True,check=True,timeout=10);matches=[]
 for line in query.stdout.decode().splitlines():
  parts=line.strip().split(None,2)
  if len(parts)==3 and Path(parts[1]).name in ['xcodebuild','swiftc','swift-frontend','clang','clang++','ld','libtool','builtin-SwiftDriver'] and any(path in parts[2] for path in ['/tmp/LumenBatch37Release','/private/tmp/LumenBatch37Release']):matches.append({'pid':parts[0],'executable':parts[1]})
 report['noTaskReleaseBuildProcess']={'command':['/bin/ps','-axo','pid=,comm=,args='],'exit':query.returncode,'stdoutBytes':len(query.stdout),'stdoutSHA256':sha(query.stdout),'matchingTaskBuilders':matches,'scope':'Only builders naming this task-owned Release path block cleanup; other processes/cache preserved.'};persist();assert not matches
 raw=Path('/tmp/LumenBatch44Checks');paths=[Path('/tmp/LumenBatch37Release')]
 for stem in ['HealthConfirmationNotNowDataSource257R1','HealthConfirmationExpiryDataSource257R1']:
  paths += [raw/(stem+suffix) for suffix in ['.xcresult','.log','-summary.json','PNG','JSON','All']]
 paths += [raw/name for name in ['Source257UnsignedReleaseR1.log','Source257UnsignedReleaseR1Audit.log','Source257UnsignedReleaseR1Settings.json','Source257UnsignedReleaseR1Settings.log','Source257TargetChangeNativeBuildR1.log']]
 def inventory(path):
  count=allocated=links=0
  def visit(p):
   nonlocal count,allocated,links
   facts=p.lstat()
   if stat.S_ISLNK(facts.st_mode):links+=1
   elif stat.S_ISDIR(facts.st_mode):
    for child in p.iterdir():visit(child)
   else:assert stat.S_ISREG(facts.st_mode);count+=1;allocated+=facts.st_blocks*512
  visit(path);return {'file':str(path),'regularFiles':count,'allocatedRegularBytes':allocated,'symlinksNotFollowed':links}
 report['plannedPaths']=[inventory(p) for p in paths];persist()
 for p in paths:
  assert p==Path('/tmp/LumenBatch37Release') or p.parent==raw
  assert not p.is_symlink()
  if p.is_dir():shutil.rmtree(p)
  else:p.unlink()
  report['removedPaths'].append(str(p));persist()
 report['afterAvailableBytes']=shutil.disk_usage(R).free
 report['observedFreeIncreaseBytes']=max(0,report['afterAvailableBytes']-report['beforeAvailableBytes'])
 report['allocatedRegularBytes']=sum(row['allocatedRegularBytes'] for row in report['plannedPaths'])
 report['creditedRecoveryBytes']=min(report['observedFreeIncreaseBytes'],report['allocatedRegularBytes'])
 report['aggregateCreditedRecoveryBytes']=16001797719+report['creditedRecoveryBytes']
 report.update(status='Completed exact2410backed scoped257Releasecache/rawRelease/build/native acquisitions removed',finished=time.time(),scope='Only listed task-owned /tmp paths. Known8syntheticownerroots alreadyabsent via productBack, no simulator ownerdata manually removed. Canonical31 original files/175–178/root/1045/archive/provider/skill/unbacked191219/Debug/packages kept. All raw257native/Release/build/cache/generated/FileList paths now HISTORICAL; never rerun their old actual raw/live/sourcebound auditors/checkers/root/prefix/settings. No system/browser/unrelated cache, sharedruntime, other simulator or userfile cleanup. No docs-only build.')
 for name in required:
  p=R/name;rawbytes=p.read_bytes();assert len(rawbytes)==rows[name]['bytes'] and sha(rawbytes)==rows[name]['sha256']
 persist();print(json.dumps({key:report[key] for key in ['status','creditedRecoveryBytes','aggregateCreditedRecoveryBytes','afterAvailableBytes']}))
except BaseException:
 report.update(status='FAILED or partial scopedcleanup; inspect removedPaths',failure=traceback.format_exc(),finished=time.time());persist();raise
