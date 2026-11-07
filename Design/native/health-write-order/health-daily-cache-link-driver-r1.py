"""Native symbolic-link rejection with no-follow host observations."""
import base64, gzip, hashlib, json, os, signal, stat, subprocess, time
from pathlib import Path
base=Path(__file__).resolve().parent; repo=base.parents[2]; raw=Path('/tmp/LumenBatch43Checks')
device='AF849DEA-DF34-4B0E-9FC1-3E45DCBE8481';stem='HealthDailyCacheLinkR1';prefix='health-daily-cache-link-r1';source_name='durable-source-r167.json';build_name='health-daily-cache-link-r1-build.json'
source=json.loads((base/source_name).read_text());build=json.loads((base/build_name).read_text());result=raw/(stem+'.xcresult');log=raw/(stem+'.log');assert not result.exists() and not log.exists()
sha=lambda d:hashlib.sha256(d).hexdigest()
def container(kind):return Path(subprocess.check_output(['xcrun','simctl','get_app_container',device,'com.dbakp.lumen',kind],text=True).strip())
def verify(installed=False):
 assert build['source']==source_name and build['buildExit']==0
 for name,f in {**source['files'],**source['fixtureInputs']}.items():
  data=(repo/name).read_bytes();assert len(data)==f['bytes'] and sha(data)==f['sha256'],name
 if installed:
  data=(container('app')/'Lumen').read_bytes();assert len(data)==build['binaryBytes'] and sha(data)==build['sha256']
def facts(p):
 f=p.lstat();r=dict(mode=f.st_mode,device=f.st_dev,inode=f.st_ino,bytes=f.st_size,modifiedNS=f.st_mtime_ns)
 if stat.S_ISLNK(f.st_mode):r.update(kind='link',destination=os.readlink(p))
 elif stat.S_ISREG(f.st_mode):
  assert f.st_size<256*1024;d=p.read_bytes();r.update(kind='file',sha256=sha(d),base64=base64.b64encode(d).decode())
 else:assert stat.S_ISDIR(f.st_mode);r['kind']='directory'
 return r
def tree(root):
 assert root.is_dir() and not root.is_symlink();rows={}
 for directory,ds,fs in os.walk(root,followlinks=False):
  for name in ds+fs:
   p=Path(directory)/name;rows[str(p.relative_to(root))]=facts(p)
 return rows
def stable(root):
 r=tree(root);assert tree(root)==r;return r
verify();command=['xcodebuild','-project','Lumen.xcodeproj','-scheme','Lumen','-configuration','Debug','-destination','platform=iOS Simulator,id='+device,'-derivedDataPath','/tmp/LumenBatch37Simulator','-clonedSourcePackagesDirPath','/tmp/LumenBatch37Packages','-disableAutomaticPackageResolution','-parallel-testing-enabled','NO','-collect-test-diagnostics','never','-only-testing:LumenUITests/LumenSmokeTests/testDailyCacheRejectsLink','-resultBundlePath',str(result),'test-without-building']
audit=dict(status='RUNNING',source=source_name,build=build_name,driverSHA256=sha(Path(__file__).read_bytes()));started=time.time();baseline=None;observed=[];error=None
with log.open('xb') as output:
 process=subprocess.Popen(command,cwd=repo,stdout=output,stderr=subprocess.STDOUT);subprocess.Popen(['caffeinate','-d','-i','-w',str(process.pid)]);audit['nativePID']=process.pid;print('Native link case PID',process.pid,flush=True)
 try:
  while process.poll() is None:
   assert time.time()-started<240,'Finite native deadline';text=log.read_text(errors='replace')
   if baseline is None and "Added attachment named 'daily-cache-link-initial'" in text:
    assert "Added attachment named 'daily-cache-link-retry-1'" not in text
    group=container('group.com.dbakp.lumen');root=group/'LumenData';prior=group/'LumenData.previous';target=group/'Lumen-ui-daily-cache-link-target.bin'
    baseline=stable(root);previous=stable(prior);original_target=facts(target)
    assert baseline['today.json']['kind']=='link' and baseline['today.json']['destination']==str(target)
    assert original_target['kind']=='file' and base64.b64decode(original_target['base64'])==b'Synthetic external snapshot target; must remain unchanged.\n'
    assert "Added attachment named 'daily-cache-link-retry-1'" not in log.read_text(errors='replace')
    verify(installed=True);audit.update(before=baseline,previousBefore=previous,targetBefore=original_target,initialCapturedBeforeFirstRetry=True)
   if baseline is not None:
    for n in [1,2]:
     label='retry-'+str(n)
     if label not in observed and "Added attachment named 'daily-cache-link-"+label+"'" in text:
      assert stable(root)==baseline and stable(prior)==previous and facts(target)==original_target
      observed.append(label);audit['exactTreeAfterRetries']=observed.copy()
   (base/(prefix+'-host-audit.json')).write_text(json.dumps(audit,indent=2)+'\n');time.sleep(.1)
 except BaseException as caught:
  error=caught;audit['loopObservationError']=repr(caught)
  if process.poll() is None:
   process.send_signal(signal.SIGINT)
   try:process.wait(timeout=45)
   except subprocess.TimeoutExpired:process.kill();process.wait()
 code=process.wait();audit['nativeExitCode']=code
try:
 summary=json.loads(subprocess.check_output(['xcrun','xcresulttool','get','test-results','summary','--path',str(result)],text=True));(base/(prefix+'-summary.json')).write_text(json.dumps(summary,indent=2)+'\n');(raw/(stem+'-summary.json')).write_text(json.dumps(summary,indent=2)+'\n')
 for extension,pattern in [('PNG','*.png'),('JSON','*.json')]:subprocess.run(['xcrun','xcresulttool','export','attachments','--path',str(result),'--output-path',str(raw/(stem+extension)),'--filter',pattern],check=True,stdout=subprocess.DEVNULL)
 retain=['python3',str(base/'retain-health-record-attachments.py'),'--stem',stem,'--prefix',prefix,'--source',source_name,'--png-dir',str(raw/(stem+'PNG')),'--json-dir',str(raw/(stem+'JSON'))]
 if code or error:retain.append('--include-failed-trial')
 subprocess.run(retain,cwd=repo,check=True)
 assert error is None,repr(error);assert code==0 and summary['passedTests']==1 and summary['failedTests']==summary['skippedTests']==0
 assert baseline is not None and observed==['retry-1','retry-2'];verify(installed=True)
 after=stable(root);previous_after=stable(prior);target_after=facts(target)
 audit.update(after=after,previousAfter=previous_after,targetAfter=target_after)
 assert after==baseline and previous_after==previous and target_after==original_target
 checkpoint=json.loads((group/'Lumen-health-cancel-checkpoint.json').read_bytes());assert checkpoint['attempts']==[]
 assert not any(p.name.startswith('LumenData.restore-') for p in group.iterdir())
 audit.update(status='PASS native symbolic-link rejection/two retries and exact root/prior/target preservation',noTransactionAttempt=True,noStage=True,scope='Main/light/standard only. Exact target preservation and static no-follow guards; no syscall trace or broad never-opened claim.')
except BaseException as caught:error=caught;audit.update(status='FAILED; actual native/host evidence retained',observationError=repr(caught))
finally:
 data=log.read_bytes();archive=stem+'.log.gz';(base/archive).write_bytes(gzip.compress(data,mtime=0));audit['nativeLog']=dict(archive=archive,bytes=len(data),sha256=sha(data));(base/(prefix+'-host-audit.json')).write_text(json.dumps(audit,indent=2)+'\n')
print(audit['status'],flush=True)
if error:raise error
