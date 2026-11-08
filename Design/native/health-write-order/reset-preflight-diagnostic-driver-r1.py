"""Metadata-only diagnostic launch; no generic fixture reset or Settings action."""
import argparse,gzip,json,os,re,shutil,subprocess,time,traceback,importlib.util
from pathlib import Path
BASE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('diagnostic_evidence',BASE/'reset-preflight-diagnostic-evidence-r1.py');e=importlib.util.module_from_spec(spec);spec.loader.exec_module(e);h=e.h
f=e.module('diagnostic_shared_finalizer','capture-state-finalization-r2.py');terminal=e.module('diagnostic_terminal','legacy-settings-erase-finalization-r2.py')
p=argparse.ArgumentParser();p.add_argument('--source',required=True);p.add_argument('--build',required=True);p.add_argument('--trial',required=True);a=p.parse_args();assert re.fullmatch('[A-Za-z0-9-]+',a.trial)
raw=Path('/tmp/LumenBatch44Checks');raw.mkdir(exist_ok=True);stem='HealthResetPreflightDiagnostic'+a.trial;prefix='health-reset-preflight-diagnostic-'+a.trial.lower();result=raw/(stem+'.xcresult');log=raw/(stem+'.log');outpath=BASE/(prefix+'-outcome.json')
assert not result.exists() and not log.exists() and not any(BASE.glob(prefix+'-*')),'Never overwrite a trial'
assert shutil.disk_usage(h.REPO).free>8*1024**3
state={'source':a.source,'build':a.build,'case':'metadata-only-preflight-diagnostic','device':h.DEVICE,'started':time.time(),'status':'RUNNING metadata-only guard classification, no erasure acceptance'};process=None;error=None

def persist():(BASE/(prefix+'-driver-observations.json')).write_text(json.dumps(state,indent=2)+'\n')

try:
 state['preflight']=h.verify_inputs(a.source,a.build)
 state['priorInstalled']=h.installed('health-settings-erasure-source222-r1-build.json')
 old=h.load(BASE/'health-capture-state-retry-failure-source220r2-host-audit.json');state['legacy']=old['checkpoint']['legacyOrigins']
 group=h.container('group.com.dbakp.lumen');state['group']=str(group)
 state['before']={};e.snapshot(group,state['before'],state['legacy']);persist()
 assert state['before']['currentTree']['files']==old['after'] and state['before']['currentTree']['metadata']==old['afterMetadata']
 assert state['before']['priorTree']['files']==old['prior'] and state['before']['priorTree']['metadata']==old['priorMetadata']
 command=['xcodebuild','-project','Lumen.xcodeproj','-scheme','Lumen','-configuration','Debug','-destination','platform=iOS Simulator,id='+h.DEVICE,
  '-derivedDataPath','/tmp/LumenBatch37Simulator','-clonedSourcePackagesDirPath','/tmp/LumenBatch37Packages','-disableAutomaticPackageResolution',
  '-parallel-testing-enabled','NO','-collect-test-diagnostics','never','-only-testing:LumenUITests/LumenSmokeTests/testHealthLegacyResetPreflightDiagnostic',
  '-resultBundlePath',str(result),'test-without-building'];state['command']=command
 with log.open('xb') as stream:
  process=subprocess.Popen(command,cwd=h.REPO,stdout=stream,stderr=subprocess.STDOUT);subprocess.Popen(['caffeinate','-i','-w',str(process.pid)]);state['nativePID']=process.pid;persist();print('Actual metadata-only diagnostic native PID',process.pid,flush=True)
  deadline=time.monotonic()+210
  while process.poll() is None:
   assert time.monotonic()<deadline,'Finite diagnostic producer deadline'
   assert h.container('group.com.dbakp.lumen')==group
   files=[x for x in group.glob(e.PREFIX+'*.json') if x.stat().st_mtime>=state['started']]
   if files and 'diagnostic' not in state:
    assert len(files)==1
    data=h.read(files[0]);state['rawDiagnostic']={'file':str(files[0]),'identity':h.identity(files[0]),**h.row(data)};state['diagnostic']=json.loads(data);persist()
    state['classification']=e.validate(state['diagnostic'],state['started'])
    state['installed']=h.installed(a.build)
    pid=state['diagnostic']['pid'];comm=subprocess.check_output(['ps','-p',str(pid),'-o','comm='],text=True).strip();assert Path(comm)==h.container('app')/'Lumen';state['appExecutable']=comm
    state['after']={}
    try:
     e.snapshot(group,state['after'],state['legacy']);e.unchanged(state['before'],state['after']);assert not h.owned(pid)
     state['unchangedAtDiagnostic']=True
    finally:persist()
    print('Actual metadata-only guard classification',state['classification'],flush=True)
   time.sleep(0.15)
  state['nativeExit']=process.wait();assert state['nativeExit']==0 and state.get('unchangedAtDiagnostic') is True
  state['afterNative']={};e.snapshot(group,state['afterNative'],state['legacy']);e.unchanged(state['before'],state['afterNative']);persist()
  state['status']='PASS metadata-only guard observed and current/prior/fixed/provider unchanged; Settings erasure unexecuted'
except BaseException:
 error=traceback.format_exc();state.update(hostError=error,status='FAILED/incomplete diagnostic; no erasure acceptance')
finally:
 def accept(retained):
  assert not retained['errors'] and [retained['summary'][x] for x in ['passedTests','failedTests','skippedTests']]==[1,0,0]
  assert len(retained['images'])==len(retained['readbacks'])==1
  helper=h.load(BASE/retained['readbacks'][0]['file']);assert helper['scope']=='metadata-only-reset-preflight-diagnostic' and helper['statusExists'] is True
  assert helper['statusValue']==state['classification'] and helper['settingsEraseAttempted'] is False
  args=helper['launchArguments'];assert '-health-legacy-reset-diagnostic-only' in args
  run=args[args.index('-health-legacy-reset-run')+1];assert run==state['diagnostic']['runID']
  assert state['unchangedAtDiagnostic'] and state['afterNative']
  (BASE/(prefix+'-host-audit.json')).write_text(json.dumps(state,indent=2)+'\n')
 outcome=terminal.finalize(process,state,persist,outpath,lambda:e.module('diagnostic_retainer','retain-mixed-ineligible-results-r1.py'),BASE,raw,stem,prefix,a.source,accept,f,host_error=error,
  success_status='PASS actual metadata-only preflight diagnostic/native and unchanged data; Settings erasure unexecuted')
 print(outcome['status'],flush=True)
raise SystemExit(outcome['driverExit'])
