"""Remove only exact-backed completed Release cache and native256 raw duplicates."""
from pathlib import Path
import gzip,hashlib,importlib.util,json,os,shutil,stat,subprocess,time
B=Path(__file__).resolve().parent;R=B.parents[2];load=lambda n:json.loads((B/n).read_bytes());sha=lambda x:hashlib.sha256(x).hexdigest()
def module(name,file):
 s=importlib.util.spec_from_file_location(name,B/file);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
E=module('cleanup_current_evidence','confirmation-lifecycle-evidence-r1.py');H=E.h;processes=module('cleanup_bound_process','target-postrun-process-r1.py');proof=load('source255-release-exact-github.json');assert proof['commit']=='5d6304c0abc52c351115156e0c8ac811ed7168b2' and proof['unionPaths']==2235
plan=load('source256-host-completion-separation-r1-plan.json');s=load(plan['prefix']+'-host-audit.json');out=load(plan['prefix']+'-outcome.json');assert out['nativeExit']==out['driverExit']==0
p=B/'source257-completed-release255-native256-cleanup-r2.json';assert not p.exists();result={'status':'Preparing scoped cleanup','priorExactCommit':proof['commit'],'priorUnion':2235,'beforeAvailableBytes':shutil.disk_usage(R).free,'freshProcess':{},'paths':[],'checkedAt':time.time()}
def persist():p.write_text(json.dumps(result,indent=2)+'\n')
persist();assert processes.observe(s['appPID'],s['boundaries'][0]['installed']['path'],result['freshProcess'],persist)=='absent';assert H.owned(s['appPID'])=={}
roots=[Path(x) for key in ['selection','freshSelection'] for x in s[key]['workspaces']];assert len(roots)==4 and all(not os.path.lexists(x) for x in roots)
query=subprocess.run(['/bin/ps','-axo','pid=,comm=,args='],capture_output=True,check=True);rows=[line.strip().split(None,2) for line in query.stdout.decode().splitlines() if line.strip()];assert all(len(r)>=2 and r[0].isdigit() for r in rows)
builders=[r for r in rows if Path(r[1]).name in ['xcodebuild','swift-frontend','swiftc','clang','clang++']]
related=[{'pid':int(r[0]),'executable':r[1]} for r in builders if any(cache in (r[2] if len(r)==3 else '') for cache in ['/tmp/LumenBatch37Release','/private/tmp/LumenBatch37Release'])];assert not related,related
result['noTaskReleaseBuildProcess']={'command':['/bin/ps','-axo','pid=,comm=,args='],'exit':0,'parsedRows':len(rows),'stdoutBytes':len(query.stdout),'stdoutSHA256':sha(query.stdout),'matchingTaskReleaseBuildProcesses':related,'unrelatedBuildProcessesPreserved':len(builders),'scope':'Only compiler/build command arguments naming this task-owned Releasecache block disposal. Other builds/processes/cachedata untouched. No globalno-build claim.'};persist()
raw=Path('/tmp/LumenBatch44Checks');cache=Path('/tmp/LumenBatch37Release');assert cache.is_dir() and not cache.is_symlink();release=load('health-current-release-source255-r1-outcome.json');settings=load('source255-unsigned-release-r1-settings-audit.json');audit=load('health-current-release-source255-r1-audit.json');binary=cache/'Build/Products/Release-iphoneos/Lumen.app/Lumen';data=binary.read_bytes();assert len(data)==audit['executableBytes'] and sha(data)==audit['executableSHA256']
log=raw/'Source255UnsignedReleaseR1.log';data=log.read_bytes();assert data==gzip.decompress((B/release['log']).read_bytes()) and sha(data)==release['logSHA256']
settingsraw=Path(settings['rawSettingsPath']);assert settingsraw.parent==raw and settingsraw.name=='Source255UnsignedReleaseR1Settings.json';assert sha(settingsraw.read_bytes())==settings['rawSettingsSHA256'];assert (raw/'Source255UnsignedReleaseR1Settings.log').read_bytes()==b''
assert (raw/'Source255UnsignedReleaseR1Audit.log').read_text()==release['auditOutput']
targets=[cache,log,settingsraw,raw/'Source255UnsignedReleaseR1Settings.log',raw/'Source255UnsignedReleaseR1Audit.log']+[raw/(plan['rawStem']+suffix) for suffix in ['.xcresult','PNG','JSON','All','.log','-summary.json']]
allocated=regular=links=0
for path in targets:
 assert os.path.lexists(path) and not path.is_symlink();members=[path]
 if path.is_dir():
  for parent,dirs,files in os.walk(path,followlinks=False):members.extend(Path(parent)/n for n in dirs+files)
 amount=count=symlinks=0
 for item in members:
  f=item.lstat()
  if stat.S_ISLNK(f.st_mode):symlinks+=1;continue
  assert stat.S_ISREG(f.st_mode) or stat.S_ISDIR(f.st_mode)
  if stat.S_ISREG(f.st_mode):amount+=f.st_blocks*512;count+=1
 result['paths'].append({'path':str(path),'regularFiles':count,'allocatedRegularBytes':amount,'symlinksUnlinkedWithoutFollowing':symlinks});allocated+=amount;regular+=count;links+=symlinks
result.update(regularFiles=regular,allocatedRegularBytes=allocated,symlinksUnlinkedWithoutFollowing=links);persist()
for path in targets:
 if path.is_dir():shutil.rmtree(path)
 else:path.unlink()
 assert not os.path.lexists(path)
after=shutil.disk_usage(R).free;observed=after-result['beforeAvailableBytes'];credit=max(0,min(allocated,observed));result.update(status='Removed exact2235backed completedRelease255 cache+4raw outputs and6native256raw duplicates',afterAvailableBytes=after,observedFreeIncreaseBytes=observed,creditedRecoveryBytes=credit,aggregateCreditedRecoveryBytes=15279312471+credit,scope='Only known task-owned Release cache and listed obsolete raw acquisitions. Task-owned links unlinked without following; no shared packages/Debug cache removed. Canonical15/current951+977/173+174/qualification/loggzip/settingssummary/FileList/provider/skill/unbacked191219 preserved. Raw256native/Release255/cache/FileList-generated paths now HISTORICAL; never rerun corresponding oldraw/live/sourcebound checker/root/settings/prefix commands. Actual4knownowners already absent via productBack, none manually removed. No unrelated/system/browser caches, shared runtimes, other simulators or personal files touched.',finished=time.time());persist();print(json.dumps({k:result[k] for k in ['status','regularFiles','symlinksUnlinkedWithoutFollowing','allocatedRegularBytes','observedFreeIncreaseBytes','creditedRecoveryBytes','aggregateCreditedRecoveryBytes','afterAvailableBytes']}))
