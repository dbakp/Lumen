"""One finite synthetic target-change native case; no physical device actions."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time
import traceback
import importlib.util
BASE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('target_evidence', BASE/'target-string-evidence-r1.py')
e=importlib.util.module_from_spec(spec); spec.loader.exec_module(e)
h=e.h
f=e.e.module('target_shared_finalization','capture-state-finalization-r2.py')
terminal=e.e.module('target_terminal','legacy-target-change-finalization-r1.py')
p=argparse.ArgumentParser(); p.add_argument('--source',required=True); p.add_argument('--host-source',required=True); p.add_argument('--build',required=True); p.add_argument('--trial',required=True)
a=p.parse_args(); assert re.fullmatch(r'[A-Za-z0-9-]+',a.trial)
raw=Path('/tmp/LumenBatch44Checks'); raw.mkdir(exist_ok=True)
stem='HealthLegacyTargetChangeString'+a.trial
prefix='health-legacy-target-change-string-'+a.trial.lower()
result=raw/(stem+'.xcresult'); log=raw/(stem+'.log'); outpath=BASE/(prefix+'-outcome.json')
assert not result.exists() and not log.exists() and not any(BASE.glob(prefix+'-*')), 'Never overwrite a trial'
assert shutil.disk_usage(h.REPO).free>8*1024**3
state={'source':a.source,'hostSource':a.host_source,'build':a.build,'case':'string-ready-before-confirmation','device':h.DEVICE,'context':e.e.context,
       'started':time.time(),'boundaries':[],'nativeStates':[],'messages':[],'status':'RUNNING actual target change; no acceptance'}
process=None; error=None

def persist():
    (BASE/(prefix+'-driver-observations.json')).write_text(json.dumps(state,indent=2)+'\n')

def alive(value):
    command=subprocess.check_output(['ps','-p',str(value['pid']),'-o','comm='],text=True).strip()
    assert Path(command)==h.container('app')/'Lumen'
    return {'pid':value['pid'],'executable':command}

def acknowledge(group,value,phase):
    path=group/('Lumen-legacy-target-change-'+value['runID'].lower()+'-ack.json')
    if os.path.lexists(path):
        assert state['messages'] and h.load(path)==state['messages'][-1]['value']
    else: assert not state['messages']
    message={k:value[k] for k in ['runID','pid','sessionID','captureID','sequence']}; message['phase']='host-'+phase
    temporary=path.with_suffix('.tmp')
    state['messageIntended']={'file':str(path),'value':message};persist()
    fd=os.open(temporary,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
    try:
        data=json.dumps(message,sort_keys=True).encode(); assert os.write(fd,data)==len(data);os.fsync(fd)
    finally:os.close(fd)
    temporary.replace(path)
    state['messages'].append({'file':str(path),'value':message,'phase':phase,'at':time.time()})
    state['messageIntended']=None;persist()

def fixed(group,row,meals):
    row['fixed']={}
    path=h.container('data')/'Library/Preferences/com.dbakp.lumen.plist'
    e.obs.sample(path,h,row['fixed'],persist,[meals])

def bootstrap_context(group,value,path,reference,sink):
    # All observations are read-only. No simulator/preferences mutation.
    sink['native']={'file':str(path),**h.row(h.read(path,128*1024))}
    sink['nativeIdentity']=h.identity(path)
    sink['processCommand']=subprocess.check_output(['ps','-p',str(value['pid']),'-o','comm='],text=True,timeout=10).strip()
    sink['currentRootIdentity']=h.identity(group/'LumenData')
    sink['priorRootIdentity']=h.identity(group/'LumenData.previous')
    provider=Path(state['provider']['file']);data=h.read(provider)
    sink['provider']={'file':str(provider),'identity':h.identity(provider),'bytes':len(data),'sha256':h.sha(data)}
    app=Path(reference['process']['executable']);data=h.read(app,64*1024*1024)
    sink['installed']={'path':str(app),'bytes':len(data),'sha256':h.sha(data)}
    sink['ownedPaths']=[str(p) for p in (Path(state['appData'])/'tmp').glob('LumenBackupWork-v1-'+str(value['pid'])+'-*')]
    persist()
    current=json.loads(h.read(path,128*1024));assert current==value
    e.check_state(current,state['started'],state['runID'],state['appPID'])
    assert current['status']=='before-selection' and current['sequence']==0
    assert sink['native']['base64']==reference['nativeCheckpoint']['base64']
    assert sink['processCommand']==reference['process']['executable']
    assert sink['currentRootIdentity']==reference['protected']['current']['rootIdentity']
    assert sink['priorRootIdentity']==reference['protected']['prior']['rootIdentity']
    assert sink['provider']=={k:state['provider'][k] for k in ['file','identity','bytes','sha256']}
    assert sink['installed']==reference['installed'] and not sink['ownedPaths']

def preserved(group,row,value,meals,selection=None,committed=False):
    row['process']=alive(value)
    if committed:
        row['success']={};e.success.collect_current(group,row['success'],state['boundaries'][0]['protected'],state['provider'],h,e,e.v,state['started']);persist()
        row['success']['namespace']={};e.retirement.collect(group,row['success']['namespace'],state['boundaries'][0]['protected'],row['success']['current'],row['success']['validation'],h,persist)
        e.retirement.validate_namespace(row['success']['namespace'],state['boundaries'][0]['protected'],row['success']['current'],row['success']['validation'],h)
        row['installed']=h.installed(a.build);persist();assert row['installed']==state['boundaries'][0]['installed']
        native=state['nativeStates'][-1];row['heldNative']={'file':native['file'],**h.row(h.read(native['file'],128*1024))};persist()
        assert json.loads(h.read(native['file'],128*1024))==value and row['heldNative']['base64']==native['base64']
        row['originEvents']=e.origin_trace(group,6 if value['sequence']==13 else 7,state['oldSession'],state['boundaries'][5]['observation']['sessionID'])
    else:
        row['protected']={};e.protected(group,row['protected'],state['boundaries'][0]['protected'])
    fixed(group,row,meals)
    if selection:
        row['selected']={'source':selection['source'],'workspaces':h.owned(value['pid'])}
        h.source_exact(selection)
        assert row['selected']==selection
    persist()

try:
    state['hostSourceVerification']=e.verify_host_source(a.host_source);persist()
    state['preflight']=h.verify_inputs(a.source,a.build);state['provider']=h.provider();persist()
    command=['xcodebuild','-project','Lumen.xcodeproj','-scheme','Lumen','-configuration','Debug',
        '-destination','platform=iOS Simulator,id='+h.DEVICE,'-derivedDataPath','/tmp/LumenBatch37Simulator',
        '-clonedSourcePackagesDirPath','/tmp/LumenBatch37Packages','-disableAutomaticPackageResolution',
        '-parallel-testing-enabled','NO','-collect-test-diagnostics','never',
        '-only-testing:LumenUITests/LumenSmokeTests/testHealthBackupFileRecoveryTargetChangedAfterReadyOriginString',
        '-resultBundlePath',str(result),'test-without-building']
    state['command']=command;persist()
    with log.open('xb') as stream:
        process=subprocess.Popen(command,cwd=h.REPO,stdout=stream,stderr=subprocess.STDOUT)
        subprocess.Popen(['caffeinate','-i','-w',str(process.pid)])
        state['nativePID']=process.pid;persist();print('Actual target-change native PID',process.pid,flush=True)
        deadline=time.monotonic()+750;last=None
        while process.poll() is None:
            assert time.monotonic()<deadline,'Finite producer deadline'
            group=h.container('group.com.dbakp.lumen')
            candidates=[x for x in group.glob('Lumen-legacy-target-change-*.json') if not x.name.endswith('-ack.json') and x.lstat().st_mtime>=state['started']]
            if not candidates:time.sleep(0.2);continue
            assert len(candidates)==1
            data=h.read(candidates[0],128*1024)
            if data==last:time.sleep(0.2);continue
            last=data
            actual={'file':str(candidates[0]),'identity':h.identity(candidates[0]),**h.row(data)}
            state['nativeStates'].append(actual);persist()
            value=json.loads(data);actual['value']=value;persist()
            e.check_state(value,state['started'],state.get('runID'),state.get('appPID'))
            state.setdefault('runID',value['runID']);state.setdefault('appPID',value['pid'])
            index=len(state['boundaries']);assert index<len(e.PHASES)
            assert value['sequence']<=e.COUNTS[index], 'Skipped a mandatory acknowledged boundary'
            if index==0 and value['status'] in ['prepared','bootstrap-checking']:
                time.sleep(0.1);continue
            if value['sequence']!=e.COUNTS[index]:time.sleep(0.1);continue
            assert value['status']==e.STATUSES[index]
            # The prepared marker precedes remaining fixture work. Never accept
            # a stale or partially written app baseline as the initial authority.
            baseline_path=group/'Lumen-health-backup-baseline.json'
            if index==0 and (not baseline_path.exists() or baseline_path.stat().st_mtime<state['started']):
                last=None;time.sleep(0.1);continue
            phase=e.PHASES[index]
            row={'phase':phase,'at':time.time(),'observation':value,'nativeCheckpoint':actual,'status':'OBSERVING'}
            state['boundaries'].append(row);persist()
            try:
                row['process']=alive(value);row['installed']=h.installed(a.build)
                # Shared reset preflight record is keyed to this same run/PID.
                row['actualPreflight']={}
                e.e.preflight(group,dict(value,mode='initial-fixture'),state['started'],row['actualPreflight'])
                if index==0:
                    state['rawBaseline']=h.row(h.read(baseline_path));state['baseline']=json.loads(h.read(baseline_path))
                    assert state['baseline']['case']=='legacy' and state['baseline']['legacyOrigins']['kind']=='string'
                    row['protected']={};e.protected(group,row['protected'])
                    state['appData']=str(h.container('data'))
                    row['initialBootstrap']={}
                    e.bootstrap.wait(Path(state['appData'])/'Library/Preferences/com.dbakp.lumen.plist',h,row['initialBootstrap'],persist,
                        lambda sink:bootstrap_context(group,value,candidates[0],row,sink))
                    row['finalBootstrapContext']={};bootstrap_context(group,value,candidates[0],row,row['finalBootstrapContext'])
                    row['postBootstrapProtected']={};e.protected(group,row['postBootstrapProtected'],row['protected'])
                    fixed(group,row,e.obs.OLD)
                    assert not h.owned(value['pid'])
                    assert row['protected']['provider']==state['provider']
                elif index==1:
                    state['selection']=h.selected(state['started']);assert state['selection']['source']['owner']['pid']==value['pid']
                    preserved(group,row,value,e.obs.OLD,state['selection'])
                    state['oldSession']=value['sessionID'];state['oldCapture']=value['captureID']
                elif index==2:
                    row['preferencePersistence']={}
                    e.obs.wait(h.container('data')/'Library/Preferences/com.dbakp.lumen.plist',h,row['preferencePersistence'],persist)
                    # Mandatory native new facts were checked by check_state;
                    # require final disk new + all protected state before ack.
                    preserved(group,row,value,e.obs.NEW,state['selection'])
                elif index==3:
                    preserved(group,row,value,e.obs.NEW,state['selection'])
                elif index in [4,7]:
                    selection=state['selection'] if index==4 else state['freshSelection']
                    row['ownerClosureSamples']=[]
                    stop=time.monotonic()+10
                    while True:
                        owners=h.owned(value['pid'])
                        row['ownerClosureSamples'].append({'at':time.time(),'workspaces':owners});persist()
                        if not owners:break
                        assert time.monotonic()<stop,'Parent/input owners did not close in finite window'
                        time.sleep(0.1)
                    row['endpoints']=[]
                    for ordinal in range(2):
                        if ordinal:time.sleep(3)
                        endpoint={'at':time.time(),'monotonic':time.monotonic()};row['endpoints'].append(endpoint);persist()
                        preserved(group,endpoint,value,e.obs.NEW,committed=index==7)
                        if index==7:e.success.validate(endpoint['success'],state['boundaries'][0]['protected'],state['provider'],h,e.v,state['started'])
                        endpoint['cleanup']=e.e.no_owned(selection,value['pid']);persist()
                    assert row['endpoints'][1]['monotonic']-row['endpoints'][0]['monotonic']>=3
                elif index==6:
                    row['retirement']={}
                    final=e.retirement.wait(row['retirement'],lambda sample:preserved(group,sample,value,e.obs.NEW,state['freshSelection'],committed=True),persist)
                    for key in ['success','process','installed','heldNative','fixed','selected']:row[key]=final[key]
                    e.success.validate(row['success'],state['boundaries'][0]['protected'],state['provider'],h,e.v,state['started'])
                else:
                    assert index==5 and value['sessionID']!=state['oldSession'] and value['captureID']!=state['oldCapture']
                    state['freshSelection']=h.selected(state['started'])
                    assert set(state['freshSelection']['workspaces']).isdisjoint(state['selection']['workspaces'])
                    preserved(group,row,value,e.obs.NEW,state['freshSelection'])
                row['originEvents']=e.origin_trace(group,index,state.get('oldSession'),value['sessionID'] if index>=5 else None)
                row['status']='PASS'
            except BaseException:
                row['status']='FAILED';row['error']=traceback.format_exc();raise
            finally:persist()
            acknowledge(group,value,phase);print('Actual target-change boundary',phase,'PASS',flush=True)
        code=process.wait();state['nativeExit']=code;persist()
        assert code==0 and len(state['boundaries'])==len(e.PHASES)
        state['status']='PASS actual target-change boundaries; retention/root/critic pending'
except BaseException:
    error=traceback.format_exc();state.update(hostError=error,status='FAILED or incomplete actual target change; no acceptance')
finally:
    def accept(retained):
        assert not retained['errors']
        assert [retained['summary'][x] for x in ['passedTests','failedTests','skippedTests']]==[1,0,0]
        assert len(retained['images'])==len(e.IMAGES) and len(retained['readbacks'])==1
        assert len(state['boundaries'])==8 and all(r['status']=='PASS' for r in state['boundaries'])
        helper=h.load(BASE/retained['readbacks'][0]['file']);assert helper['phase']=='completed'
        assert [r['phase'] for r in helper['observations'] if 'probeValue' in r]==e.PHASES
        (BASE/(prefix+'-host-audit.json')).write_text(json.dumps(state,indent=2)+'\n')
    outcome=terminal.finalize(process,state,persist,outpath,lambda:e.e.module('target_retainer','retain-mixed-ineligible-results-r1.py'),
        BASE,raw,stem,prefix,a.source,accept,f,host_error=error)
    print(outcome['status'],flush=True)
raise SystemExit(outcome['driverExit'])
