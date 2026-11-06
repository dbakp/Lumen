"""Observe actual clear-worker Cancel/Back; release only the separately confirmed retry."""
import argparse,base64,gzip,hashlib,json,re,signal,stat,subprocess,time
from pathlib import Path
base=Path(__file__).resolve().parent; repo=base.parents[2]; raw=Path('/tmp/LumenBatch43Checks')
p=argparse.ArgumentParser();p.add_argument('--source',required=True);p.add_argument('--build',required=True);p.add_argument('--action',choices=['cancel','back'],required=True);p.add_argument('--trial',required=True);args=p.parse_args();assert re.fullmatch(r'R[1-9][0-9]*',args.trial)
source=json.loads((base/args.source).read_text());build=json.loads((base/args.build).read_text());sha=lambda d:hashlib.sha256(d).hexdigest();device='AF849DEA-DF34-4B0E-9FC1-3E45DCBE8481'
stem='HealthDailyCacheInterrupt'+args.action.title()+args.trial;prefix='health-daily-cache-interrupt-'+args.action+'-'+args.trial.lower();result=raw/(stem+'.xcresult');assert not result.exists()
def container(kind):return Path(subprocess.check_output(['xcrun','simctl','get_app_container',device,'com.dbakp.lumen',kind],text=True).strip())
def verify(installed=False):
 assert build['source']==args.source and build['buildExit']==0
 for name,facts in {**source['files'],**source['fixtureInputs']}.items():
  data=(repo/name).read_bytes();assert len(data)==facts['bytes'] and sha(data)==facts['sha256'],name
 if installed:
  data=(container('app')/'Lumen').read_bytes();assert len(data)==build['binaryBytes'] and sha(data)==build['sha256']
def files(root):
 assert root.is_dir() and not root.is_symlink();rows={};total=0
 for path in root.rglob('*'):
  facts=path.lstat()
  if stat.S_ISDIR(facts.st_mode):continue
  assert stat.S_ISREG(facts.st_mode) and facts.st_size<=256*1024
  data=path.read_bytes();total+=len(data);assert total<=8*1024*1024
  rows[str(path.relative_to(root))]={'bytes':len(data),'sha256':sha(data),'base64':base64.b64encode(data).decode(),'mode':stat.S_IMODE(facts.st_mode),'inode':facts.st_ino}
 return rows
verify();test='testDailyCacheClearCorrupt'+args.action.title();log=raw/(stem+'.log');audit={'source':args.source,'build':args.build,'driverSHA256':sha(Path(__file__).read_bytes()),'status':'running','action':args.action,'scope':'Main/light/large explicit corrupt-cache clear; actual first Cancel/Back without release and separately confirmed retry only.'};acknowledged=False;released=False;started=time.time()
command=['xcodebuild','-project','Lumen.xcodeproj','-scheme','Lumen','-configuration','Debug','-destination','platform=iOS Simulator,id='+device,'-derivedDataPath','/tmp/LumenBatch37Simulator','-clonedSourcePackagesDirPath','/tmp/LumenBatch37Packages','-disableAutomaticPackageResolution','-parallel-testing-enabled','NO','-collect-test-diagnostics','never','-only-testing:LumenUITests/LumenSmokeTests/'+test,'-resultBundlePath',str(result),'test-without-building']
with log.open('xb') as output:
 process=subprocess.Popen(command,cwd=repo,stdout=output,stderr=subprocess.STDOUT);subprocess.Popen(['caffeinate','-d','-i','-w',str(process.pid)]);audit['producerPID']=process.pid
 try:
  while process.poll() is None:
   assert time.time()-started<260,'Finite native test deadline'
   try:
    group=container('group.com.dbakp.lumen');checkpoint=group/'Lumen-health-cancel-checkpoint.json'
    if checkpoint.stat().st_mtime<started:time.sleep(.2);continue
    state=json.loads(checkpoint.read_bytes())
   except (subprocess.CalledProcessError,FileNotFoundError,json.JSONDecodeError):time.sleep(.2);continue
   attempts=state.get('attempts',[]);text=log.read_text()
   if not acknowledged and len(attempts)==1 and "Added attachment named 'daily-cache-interrupt-held'" in text:
    first=attempts[0];assert first['ordinal']==1 and first['phase']=='held' and first['workerControlMatchesUI'] and not first['uiCancelled'];assert re.fullmatch(r'LumenData\.restore-[A-Fa-f0-9-]+',first['stage']);verify(installed=True)
    root=group/'LumenData';prior=group/'LumenData.previous';before=files(root);previous=files(prior);assert (group/first['stage']).is_dir()
    assert all(base64.b64decode(before[name]['base64'])==base64.b64decode(data) for name,data in first['originals'].items())
    assert base64.b64decode(before['today.json']['base64'])==b'{"syntheticUnavailableToday":'
    journal=json.loads(base64.b64decode(before['health-write-intent.json']['base64']));assert len(journal['events'])==2 and {e['action'] for e in journal['events']}=={'save','delete'} and all(e['acknowledged']==[] for e in journal['events'])
    assert not any(name.startswith('.health-cache-history/') for name in before)
    temporary=group/('Lumen-cache-ack-'+first['nonce']+'.tmp');temporary.write_text(json.dumps({'nonce':first['nonce'],'acknowledgementOnly':True}));temporary.replace(group/'Lumen-health-cancel-release.json');acknowledged=True
    audit.update(before=before,previousBefore=previous,firstHeld=first,acknowledgementOnly=True,firstStageObserved=True)
   if acknowledged and not released and len(attempts)==2 and "Added attachment named 'daily-cache-interrupt-retry-held'" in text:
    first,second=attempts;assert first['ordinal']==1 and first['phase']=='cancelled' and first['uiCancelled'] and first['workerControlMatchesUI'];assert not (group/first['stage']).exists()
    assert second['ordinal']==2 and second['phase']=='held' and second['workerControlMatchesUI'] and not second['uiCancelled'];assert re.fullmatch(r'LumenData\.restore-[A-Fa-f0-9-]+',second['stage']) and (group/second['stage']).is_dir()
    release=json.loads((group/'Lumen-health-cancel-release.json').read_text());assert release=={'nonce':first['nonce'],'acknowledgementOnly':True}
    assert "Added attachment named 'daily-cache-interrupt-idle'" in text
    post_cancel=files(root);post_previous=files(prior);assert post_cancel==before and post_previous==previous
    audit.update(firstCancelled=first,firstStageAbsentBeforeRetryRelease=True,firstWorkerNeverReleased=True,afterCancel=post_cancel,previousAfterCancel=post_previous,retryHeld=second)
    temporary=group/('Lumen-cache-retry-release-'+second['nonce']+'.tmp');temporary.write_text(json.dumps({'nonce':second['nonce']}));temporary.replace(group/'Lumen-health-cancel-release.json');released=True
   time.sleep(.2)
  code=process.wait();audit['producerExitCode']=code
 except BaseException as error:
  audit['observationError']=repr(error)
  if process.poll() is None:
   process.send_signal(signal.SIGINT)
   try:process.wait(timeout=45)
   except subprocess.TimeoutExpired:process.kill();process.wait()
  audit['producerExitCode']=process.returncode
  raise
 finally:(base/(prefix+'-host-audit.json')).write_text(json.dumps(audit,indent=2)+'\n')
summary=json.loads(subprocess.check_output(['xcrun','xcresulttool','get','test-results','summary','--path',str(result)],text=True));(raw/(stem+'-summary.json')).write_text(json.dumps(summary,indent=2)+'\n')
for extension,pattern in [('PNG','*.png'),('JSON','*.json')]:
 with (raw/(stem+extension+'Export.log')).open('xb') as output:subprocess.run(['xcrun','xcresulttool','export','attachments','--path',str(result),'--output-path',str(raw/(stem+extension)),'--filter',pattern],stdout=output,stderr=subprocess.STDOUT,check=True)
retain=['python3',str(base/'retain-health-record-attachments.py'),'--stem',stem,'--prefix',prefix,'--source',args.source,'--png-dir',str(raw/(stem+'PNG')),'--json-dir',str(raw/(stem+'JSON'))]
if code:retain.append('--include-failed-trial')
subprocess.run(retain,cwd=repo,check=True);assert code==0 and summary['passedTests']==1 and summary['failedTests']==summary['skippedTests']==0;assert acknowledged and released;verify(installed=True)
after=files(root);previous_after=files(prior);assert previous_after==previous
for name,facts in before.items():
 if name!='today.json':assert after[name]==facts,name
assert all(name.startswith(('.health-cache-history/','.health-recovery/')) for name in set(after)-set(before));current=json.loads(base64.b64decode(after['today.json']['base64']));assert current['readings']=={} and current['recordedTotalKeys']==[] and current['excludesLumenNutrition'] is True
rawpaths=[name for name,facts in after.items() if name not in before and name.endswith('/today.json') and facts['sha256']==before['today.json']['sha256']];assert len(rawpaths)==1;intent=after[str(Path(rawpaths[0]).parent/'device-intent.json')];assert all(intent[k]==before['health-write-intent.json'][k] for k in ['bytes','sha256','base64'])
receipts=[name for name in after if name.startswith('.health-cache-history/')];assert len(receipts)==1;receipt=json.loads(base64.b64decode(after[receipts[0]]['base64']));assert receipt['action']=='clear' and receipt['owner']==journal['owner'] and receipt['rawDigest']==after['today.json']['sha256'] and receipt['prior']['entries']['']['digest']==before['today.json']['sha256']
assert not (group/audit['retryHeld']['stage']).exists();assert len({name.split('/')[1] for name in after if name.startswith('.health-recovery/')})==2
audit.update(status='passed: first actual UI cancellation stops worker without host release; all files exact before separately confirmed retry; retry actual iOS commit preserves other current/prior/raw/intent files',after=after,previousAfter=previous_after,retryStageAbsent=True,receipt=receipt,privateCopiesAfter=2)
(base/(prefix+'-host-audit.json')).write_text(json.dumps(audit,indent=2)+'\n');print('PASS',args.action,'first worker cancelled without release; retry saves; original/current/prior/Health intent exact',flush=True)
