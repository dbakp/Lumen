"""Remove only exact-backed completed252 raw duplicates and two dead fixtures."""
from pathlib import Path
import importlib.util,json,os,shutil,stat,time
B=Path(__file__).resolve().parent;REPO=B.parents[2]
def module(name,file):
 s=importlib.util.spec_from_file_location(name,B/file);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
e=module('cleanup252_evidence','confirmation-lifecycle-evidence-r1.py');h=e.h;p=module('cleanup252_process','target-postrun-process-r1.py')
proof=h.load(B/'source252-native-exact-github.json');assert proof['commit']=='dcc4de89cb73007e5d0bf22a595c8aabb0992235' and proof['unionPaths']==1971
s=h.load(B/'health-confirmation-notnow-data-source252r1-driver-observations.json');diag=h.load(B/'source252-post-failure-readonly-diagnostic-r1.json');result={'status':'Preparing scoped cleanup','priorExactCommit':proof['commit'],'priorUnion':1971,'freshProcess':{},'paths':[],'beforeAvailableBytes':shutil.disk_usage(REPO).free,'checkedAt':time.time()};output=B/'source253-completed-failed252-cleanup-r1.json';assert not output.exists()
def persist():output.write_text(json.dumps(result,indent=2)+'\n')
persist();assert p.observe(s['appPID'],s['boundaries'][0]['installed']['path'],result['freshProcess'],persist)=='absent'
assert h.owned(s['appPID'])==diag['samples'][-1]['ownedWorkspaces']
raw=Path('/tmp/LumenBatch44Checks');stem='HealthConfirmationNotNowDataSource252R1';targets=[raw/(stem+x) for x in ['.xcresult','PNG','JSON','All','.log','-summary.json']]+[raw/'Source252TargetChangeNativeBuildR1.log']
owners=[Path(p) for p in s['selection']['workspaces']];assert len(owners)==2
for path in owners:
 assert path.parent==Path(s['appData'])/'tmp' and path.name.startswith('LumenBackupWork-v1-'+str(s['appPID'])+'-')
 targets.append(path)
allocated=regular=0
for path in targets:
 assert os.path.lexists(path) and not path.is_symlink()
 paths=[path]
 if path.is_dir():
  for parent,dirs,files in os.walk(path,followlinks=False):paths.extend(Path(parent)/name for name in dirs+files)
 amount=count=0
 for item in paths:
  facts=item.lstat();assert not stat.S_ISLNK(facts.st_mode) and (stat.S_ISREG(facts.st_mode) or stat.S_ISDIR(facts.st_mode))
  if stat.S_ISREG(facts.st_mode):amount+=facts.st_blocks*512;count+=1
 result['paths'].append({'path':str(path),'regularFiles':count,'allocatedRegularBytes':amount});allocated+=amount;regular+=count
result.update(allocatedRegularBytes=allocated,regularFiles=regular,symlinks=0);persist()
for path in targets:
 if path.is_dir():shutil.rmtree(path)
 else:path.unlink()
 assert not os.path.lexists(path)
after=shutil.disk_usage(REPO).free;observed=after-result['beforeAvailableBytes'];credit=max(0,min(allocated,observed));result.update(status='Removed exact-backed completed252 raw duplicates and two known dead synthetic owners',afterAvailableBytes=after,observedFreeIncreaseBytes=observed,creditedRecoveryBytes=credit,aggregateCreditedRecoveryBytes=14930816599+credit,scope='Only7raw acquisition paths+2known252deadworkspace roots; canonical99/full63MBvideo/9145Bhelper/source887/166/root/provider/skill/unbacked191219 kept. Raw252native/build paths now HISTORICAL; do not rerun their old live/sourcebound/raw audits. CurrentDebug/packages immediatelyneeded253build and retained. No unrelated/system/browser caches/simulators/user data removed.',finished=time.time());persist();print(json.dumps({k:result[k] for k in ['status','regularFiles','allocatedRegularBytes','observedFreeIncreaseBytes','creditedRecoveryBytes','aggregateCreditedRecoveryBytes','afterAvailableBytes']}))
