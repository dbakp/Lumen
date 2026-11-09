"""Delete only verified redundant255 raw acquisitions and known dead fixture roots."""
from pathlib import Path
import gzip,hashlib,importlib.util,json,os,shutil,stat,time
B=Path(__file__).resolve().parent;R=B.parents[2];load=lambda n:json.loads((B/n).read_bytes())
def module(name,file):
 s=importlib.util.spec_from_file_location(name,B/file);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
e=module('cleanup_evidence','confirmation-lifecycle-evidence-r1.py');h=e.h;processes=module('cleanup_process','target-postrun-process-r1.py')
proof=load('source255-native-exact-github.json');assert proof['commit']=='0ee14f9578e972cacfa83a8d91953b65357da2b0' and proof['unionPaths']==2145
plan=load('source255-check-acquisition-finalization-r1-plan.json');s=load(plan['prefix']+'-driver-observations.json');diag=load('source255-post-failure-readonly-diagnostic-r1.json');assert s['source']==plan['source']
p=B/'source256-completed-failed255-cleanup-r1.json';assert not p.exists();r={'status':'Preparing scoped cleanup','priorExactCommit':proof['commit'],'priorUnion':2145,'beforeAvailableBytes':shutil.disk_usage(R).free,'freshProcess':{},'paths':[],'checkedAt':time.time()}
def persist():p.write_text(json.dumps(r,indent=2)+'\n')
persist();assert processes.observe(s['appPID'],s['boundaries'][0]['installed']['path'],r['freshProcess'],persist)=='absent';assert h.owned(s['appPID'])==diag['samples'][-1]['ownedWorkspaces']
raw=Path('/tmp/LumenBatch44Checks');stem=plan['rawStem'];bundle=Path(s['command'][s['command'].index('-resultBundlePath')+1]);assert bundle==raw/(stem+'.xcresult')
build=load('source255-target-change-native-build-r1-outcome.json');buildlog=raw/'Source255TargetChangeNativeBuildR1.log';data=buildlog.read_bytes();assert data==gzip.decompress((B/build['log']).read_bytes()) and hashlib.sha256(data).hexdigest()==build['logSHA256']
targets=[raw/(stem+suffix) for suffix in ['.xcresult','PNG','JSON','All','.log','-summary.json']]+[buildlog]
owners=[Path(x) for x in s['selection']['workspaces']];assert len(owners)==2
for path in owners:assert path.parent==Path(s['appData'])/'tmp' and path.name.startswith('LumenBackupWork-v1-'+str(s['appPID'])+'-')
targets+=owners;allocated=regular=0
for path in targets:
 assert os.path.lexists(path) and not path.is_symlink();members=[path]
 if path.is_dir():
  for parent,dirs,files in os.walk(path,followlinks=False):members.extend(Path(parent)/n for n in dirs+files)
 amount=count=0
 for item in members:
  f=item.lstat();assert not stat.S_ISLNK(f.st_mode) and (stat.S_ISREG(f.st_mode) or stat.S_ISDIR(f.st_mode))
  if stat.S_ISREG(f.st_mode):amount+=f.st_blocks*512;count+=1
 r['paths'].append({'path':str(path),'regularFiles':count,'allocatedRegularBytes':amount});allocated+=amount;regular+=count
r.update(regularFiles=regular,allocatedRegularBytes=allocated,symlinks=0);persist()
for path in targets:
 if path.is_dir():shutil.rmtree(path)
 else:path.unlink()
 assert not os.path.lexists(path)
after=shutil.disk_usage(R).free;observed=after-r['beforeAvailableBytes'];credit=max(0,min(allocated,observed));r.update(status='Removed exact2145backed7raw255acquisitions and2known dead synthetic owners',afterAvailableBytes=after,observedFreeIncreaseBytes=observed,creditedRecoveryBytes=credit,aggregateCreditedRecoveryBytes=15174045271+credit,scope='Canonicalall90/full44.9MBvideo/22518Bhelper/current951/171/root/source/provider/skill/unbacked191219 kept. Raw255native/build paths now HISTORICAL: never rerun old raw/live-source-bound255 audit/checker. Current Debug/packages immediately needed and kept. Manual dead fixture cleanup is not product Back or ownerclosure proof. No unrelated/system/browser caches, shared runtimes, other simulators or personal files removed.',finished=time.time());persist();print(json.dumps({k:r[k] for k in ['status','regularFiles','allocatedRegularBytes','observedFreeIncreaseBytes','creditedRecoveryBytes','aggregateCreditedRecoveryBytes','afterAvailableBytes']}))
