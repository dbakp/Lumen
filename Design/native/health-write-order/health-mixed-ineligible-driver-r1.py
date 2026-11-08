"""One finite native mixed-ineligible case. No phone operations; no synthetic authority."""
import argparse, gzip, importlib.util, json, re, shutil, signal, subprocess, time, traceback
from pathlib import Path
spec=importlib.util.spec_from_file_location('mixed',Path(__file__).with_name('health-mixed-ineligible-evidence-r1.py'))
h=importlib.util.module_from_spec(spec);spec.loader.exec_module(h)
p=argparse.ArgumentParser();p.add_argument('--source',required=True);p.add_argument('--build',required=True);p.add_argument('--trial',required=True);a=p.parse_args()
assert re.fullmatch('[A-Za-z0-9-]+',a.trial)
raw=Path('/tmp/LumenBatch44Checks');raw.mkdir(exist_ok=True)
prefix='health-mixed-ineligible-'+a.trial.lower();stem='HealthMixedIneligible'+a.trial
result=raw/(stem+'.xcresult');logpath=raw/(stem+'.log');outpath=h.BASE/(prefix+'-outcome.json')
assert not result.exists() and not logpath.exists() and not outpath.exists(), 'Never restart a trial'
assert shutil.disk_usage(h.REPO).free>8*1024**3
started=time.time();state={'source':a.source,'build':a.build,'device':h.DEVICE,'started':started,'boundaries':[]}
def persist():
    (h.BASE/(prefix+'-driver-observations.json')).write_text(json.dumps(state,indent=2)+'\n')
def boundary(name,root):
    observation={'phase':name,'at':time.time()};state['boundaries'].append(observation);persist()
    try:
        observation['fixed']={}
        h.fixed(state['checkpoint']['legacyOrigins'],observation['fixed'])
        observation['provider']=h.provider();observation['installed']=h.installed(a.build)
        observation['status']='PASS'
    except Exception:
        observation['status']='FAILED';observation['error']=traceback.format_exc();raise
    finally:persist()
def message(group,name,nonce,ack):
    assert re.fullmatch('[A-Fa-f0-9-]{36}',nonce)
    target=group/name;temp=target.with_name(name+'.'+nonce+'.mixed.tmp');assert not temp.exists() and not target.is_symlink()
    data={'nonce':nonce}
    if ack:data['acknowledgementOnly']=True
    temp.write_text(json.dumps(data));temp.replace(target)
def protocol(group):
    value=h.load(group/'Lumen-health-cancel-checkpoint.json');assert len(value['attempts'])==1
    record=value['attempts'][0]
    assert record['ordinal']==1 and record['workerControlMatchesUI'] is True and record['uiCancelled'] is False
    return value,record

def cleanup(root,selection,phase):
    until=time.monotonic()+3
    while any(Path(path).exists() for path in selection['workspaces']) and time.monotonic()<until:time.sleep(.1)
    assert all(not Path(path).exists() for path in selection['workspaces'])
    pid=selection['source']['owner']['pid'];assert not h.owned(pid)
    scan=subprocess.run(['lsof','-nP','-a','-p',str(pid),'-Fn'],capture_output=True,text=True);assert scan.returncode==0
    for line in scan.stdout.splitlines():
        if line.startswith('n'):assert not any(line[1:]==path or line[1:].startswith(path+'/') for path in selection['workspaces'])
    assert not list(root.parent.glob('LumenData.restore-*'))
    return {'phase':phase,'rootsAbsent':True,'noOpenPaths':scan.stdout,'hostDeletedWorkspace':False,'tree':h.snapshot(root),'directories':h.directories(root),'guardSeconds':3}

try:
    preflight=h.verify_inputs(a.source,a.build);state['preflight']=preflight;persist()
except Exception:
    state['status']='FAILED preflight before native launch';state['hostFailure']=traceback.format_exc();persist()
    outpath.write_text(json.dumps(state,indent=2)+'\n');raise
command=['xcodebuild','-project','Lumen.xcodeproj','-scheme','Lumen','-configuration','Debug',
 '-destination','platform=iOS Simulator,id='+h.DEVICE,'-derivedDataPath','/tmp/LumenBatch37Simulator',
 '-clonedSourcePackagesDirPath','/tmp/LumenBatch37Packages','-disableAutomaticPackageResolution',
 '-parallel-testing-enabled','NO','-collect-test-diagnostics','never',
 '-only-testing:LumenUITests/LumenSmokeTests/testHealthBackupFileRecoveryMixedIneligibleLegacy',
 '-resultBundlePath',str(result),'test-without-building']
host_failure=None;code=None
with logpath.open('xb') as stream:
    process=subprocess.Popen(command,cwd=h.REPO,stdout=stream,stderr=subprocess.STDOUT)
    subprocess.Popen(['caffeinate','-d','-i','-w',str(process.pid)])
    state['command']=command;state['pid']=process.pid;persist();print('Native mixed case PID',process.pid,flush=True)
    deadline=time.monotonic()+800
    try:
        while process.poll() is None:
            assert time.monotonic()<deadline,'Finite mixed case deadline'
            group=h.container('group.com.dbakp.lumen');root=group/'LumenData'
            log=logpath.read_text();captured=lambda suffix:("Added attachment named 'health-mixed-ineligible-legacy-"+suffix+"'") in log
            if 'checkpoint' not in state:
                baseline=group/'Lumen-health-backup-baseline.json'
                if not baseline.exists() or baseline.stat().st_mtime<started or 'Tap "chooseBackup" Button' not in log:time.sleep(.2);continue
                checkpoint=h.load(baseline);assert checkpoint['case']=='legacy' and checkpoint['missing']==['meals.json','workouts.json']
                before=h.snapshot(root)
                for name,encoded in checkpoint['originals'].items():
                    actual=before[name]['base64']
                    if name=='profile.json':assert json.loads(h.base64.b64decode(actual))==json.loads(h.base64.b64decode(encoded))
                    else:assert actual==encoded,name
                assert not {'meals.json','workouts.json'}&set(before)
                assert json.loads(h.read(root/'water.json'))[0]['ml']==137
                goals=h.load(root/'goals.json');assert [goals[k] for k in ['stepGoal','weightKg','heightCm','age']]==[6543,88.5,181,42]
                assert not list((root/'.health-recovery-history').glob('*.json'))
                state.update({'checkpoint':checkpoint,'before':before,'metadataBefore':h.metadata(root),'directoriesBefore':h.directories(root),'previous':h.snapshot(root.with_suffix('.previous')),'previousMetadata':h.metadata(root.with_suffix('.previous'))})
                boundary('initial-before-file-selection',root)
            if 'selection' not in state and captured('source'):
                state['selection']=h.selected(started);boundary('selected-original',root)
            if 'held' not in state and captured('held-1'):
                assert 'selection' in state;h.source_exact(state['selection']);value,record=protocol(group)
                assert record['phase']=='held' and re.fullmatch(r'LumenData\.restore-[A-Fa-f0-9-]+',record['stage'])
                stage=group/record['stage'];assert stage.is_dir() and not stage.is_symlink() and h.stat.S_IMODE(stage.stat().st_mode)==0o700 and list(stage.iterdir())==[]
                prior=h.preparation(root,state['before'],state['previous'])
                for name,encoded in record['originals'].items():assert state['before'][name]['base64']==encoded
                assert h.metadata(root)==state['metadataBefore']|{k:h.identity(root/k) for k in prior['files']}
                # Normal preparation may retire .previous; exact selected prior
                # workouts/intent are proven in the v1 private copy above.
                state['held']={'record':record.copy(),'protocol':value,'priorCopy':prior,'stage':str(stage),'at':time.time()}
                boundary('held-before-ack',root);message(group,'Lumen-health-cancel-release.json',record['nonce'],True)
            if 'held' in state and 'released' not in state and captured('observed-1'):
                value,record=protocol(group);assert record==state['held']['record']
                assert h.preparation(root,state['before'],state['previous'])==state['held']['priorCopy']
                assert list(Path(state['held']['stage']).iterdir())==[];h.source_exact(state['selection'])
                assert h.metadata(root)==state['metadataBefore']|{k:h.identity(root/k) for k in state['held']['priorCopy']['files']}
                boundary('observed-before-intentional-release',root)
                state['released']={'record':record.copy(),'intentionallyHostReleased':True,'at':time.time()};persist()
                message(group,'Lumen-health-cancel-release.json',record['nonce'],False)
            if 'released' in state and 'success' not in state and captured('success'):
                noncepath=group/'Lumen-health-success-checkpoint.json'
                if not noncepath.exists() or noncepath.stat().st_mtime<started:time.sleep(.1);continue
                nonce=h.load(noncepath)['nonce'];value,record=protocol(group)
                assert record==state['held']['record']|{'phase':'released'};h.source_exact(state['selection'])
                boundary('success-before-ack',root)
                # Observe actual asynchronous retirement before the success ack.
                samples=[];until=time.monotonic()+15
                while True:
                    sample={'at':time.time(),'priorExists':root.with_suffix('.previous').exists(),
                        'restore':list(map(str,root.parent.glob('LumenData.restore-*'))),
                        'retired':list(map(str,root.parent.glob('LumenData.retired-*')))}
                    samples.append(sample);state['retirementSamples']=samples;persist()
                    sample['paths']={}
                    paths=([str(root.with_suffix('.previous'))] if sample['priorExists'] else [])+sample['restore']+sample['retired']
                    for path in paths:
                        target=Path(path)
                        # Only these source-derived product retirement paths may
                        # disappear while their asynchronous remover runs.
                        assert target.parent==root.parent and (target==root.with_suffix('.previous') or target.name.startswith(('LumenData.restore-','LumenData.retired-')))
                        sample['paths'][path]={'state':'listed-before-read'};persist()
                        try:
                            facts=h.identity(target);sample['paths'][path]['metadata']=facts;persist()
                            assert h.stat.S_ISDIR(facts['st_mode']) and not target.is_symlink()
                            sample['paths'][path].update({'files':h.snapshot(target),'directories':h.directories(target),'fileMetadata':h.metadata(target),'state':'observed-directory'})
                        except FileNotFoundError as error:
                            sample['paths'][path].update({'state':'entry-disappeared-during-retirement-observation','error':str(error)})
                            # Do not credit a clean sample from a partial read;
                            # the next bounded sample must observe all absent.
                        finally:persist()
                    if not sample['priorExists'] and not sample['restore'] and not sample['retired']:break
                    assert time.monotonic()<until,'Retirement readiness not observed before bounded deadline'
                    time.sleep(.1)
                state['commitObservedTree']=h.snapshot(root);state['commitObservedDirectories']=h.directories(root);persist()
                assert h.directories(root)==h.allowed_directories(state['directoriesBefore'],state['commitObservedTree'])
                state['commitFixedObservation']={'status':'checking','values':{}};persist()
                try:
                    state['success']=h.committed(root,state['before'],state['held']['priorCopy'],state['checkpoint']['legacyOrigins'],state['commitFixedObservation']['values'])|{'nonce':nonce,'record':record,'at':time.time()}
                    state['commitFixedObservation']['status']='PASS'
                except Exception:
                    state['commitFixedObservation']['status']='FAILED';state['commitFixedObservation']['error']=traceback.format_exc();raise
                finally:persist()
                message(group,'Lumen-health-success-ack.json',nonce,True)
            if 'success' in state and 'parent' not in state and captured('parent'):
                state['parent']=cleanup(root,state['selection'],'parent')
                assert state['parent']['tree']==state['success']['tree']
                trace=h.events(group);owners={x['sessionID'] for x in trace};assert len(owners)==1
                assert [x['event'] for x in trace[:3]]==['open','ready','acquire'] and all(x['event']=='closed' for x in trace[3:]) and len(trace)>3
                assert trace[1]['domains']==trace[2]['domains']==['workouts']
                state['originEvents']=trace;boundary('parent-before-relaunch',root)
            if 'parent' in state and 'relaunchSelection' not in state and captured('relaunch-review'):
                fresh=h.selected(started);assert set(fresh['workspaces']).isdisjoint(state['selection']['workspaces'])
                assert fresh['source']['owner']['id']!=state['selection']['source']['owner']['id']
                state['relaunchSelection']=fresh;boundary('fresh-relaunch-review',root)
                assert h.events(group)==state['originEvents'], 'Relaunch without fixture flags adds no DEBUG trace'
            if 'relaunchSelection' in state and 'relaunchParent' not in state and captured('relaunch-parent'):
                state['relaunchParent']=cleanup(root,state['relaunchSelection'],'relaunch-parent');boundary('final-after-relaunch',root)
            persist();time.sleep(.2)
        code=process.wait()
    except Exception:
        host_failure=traceback.format_exc();state['hostFailure']=host_failure;persist()
        # Permit real native failures/timeouts to finish and write their summary.
        try:code=process.wait(timeout=180)
        except subprocess.TimeoutExpired:
            process.send_signal(signal.SIGINT)
            try:code=process.wait(timeout=30)
            except subprocess.TimeoutExpired:
                process.terminate()
                try:code=process.wait(timeout=15)
                except subprocess.TimeoutExpired:process.kill();code=process.wait()
    finally:
        state['nativeExit']=code;persist()

# Every available actual summary/log/PNG/JSON peer is salvaged independently.
outcome={'source':a.source,'build':a.build,'prefix':prefix,'stem':stem,'nativeExit':code,'hostFailure':host_failure,'status':'FAILED or incomplete','summary':None}
outpath.write_text(json.dumps(outcome,indent=2)+'\n')
try:
    spec=importlib.util.spec_from_file_location('retainer',Path(__file__).with_name('retain-mixed-ineligible-results-r1.py'))
    retainer=importlib.util.module_from_spec(spec);spec.loader.exec_module(retainer)
    retained=retainer.retain(h.BASE,raw,stem,prefix,a.source);outcome['retention']=retained
    summary=retained['summary']
    outcome['summary']=summary
    assert host_failure is None,host_failure
    assert code==0 and summary is not None and not retained['errors']
    assert [summary[k] for k in ['passedTests','failedTests','skippedTests']]==[1,0,0]
    assert all(k in state for k in ['held','released','success','parent','relaunchSelection','relaunchParent'])
    h.verify_inputs(a.source,a.build);h.installed(a.build)
    root=h.container('group.com.dbakp.lumen')/'LumenData'
    after=h.snapshot(root);assert set(after)==set(state['success']['tree'])
    for name,want in state['success']['tree'].items():
        if name in ['profile.json','habits.json']:assert json.loads(h.base64.b64decode(after[name]['base64']))==json.loads(h.base64.b64decode(want['base64']))
        else:assert after[name]==want,name
    assert h.directories(root)==state['commitObservedDirectories']
    assert not root.with_suffix('.previous').exists() and not list(root.parent.glob('LumenData.retired-*')) and not list(root.parent.glob('LumenData.restore-*'))
    assert not (root/'meals.json').exists() and h.read(root/'workouts.json')==b'[]'
    assert h.events(root.parent)==state['originEvents'];h.provider()
    state['finalFixedObservation']={'status':'checking','values':{}};persist()
    try:
        h.fixed(state['checkpoint']['legacyOrigins'],state['finalFixedObservation']['values'])
        state['finalFixedObservation']['status']='PASS'
    except Exception:
        state['finalFixedObservation']['status']='FAILED';state['finalFixedObservation']['error']=traceback.format_exc();raise
    finally:persist()
    state['after']=after;state['directoriesAfter']=h.directories(root)
    state['status']='PASS actual one mixed-ineligible native flow; not broad product acceptance';persist()
    (h.BASE/(prefix+'-host-audit.json')).write_text(json.dumps(state,indent=2)+'\n')
    outcome['status']='PASS actual native1/0/0 and strict host audit'
except Exception:
    outcome['finalizationFailure']=traceback.format_exc()
    raise
finally:
    outcome['finished']=time.time();outpath.write_text(json.dumps(outcome,indent=2)+'\n')
print(outcome['status'],flush=True)
