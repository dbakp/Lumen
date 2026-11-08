"""Mandatory retained-case validation plus explicit live/absent app endpoints.
Host-only successor: never reruns, launches or repairs the native app.
"""
import argparse,base64,gzip,hashlib,importlib.util,json,os,re,time,traceback
from pathlib import Path
BASE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('postrun_checker_evidence',BASE/'confirmation-target-evidence-r1.py')
e=importlib.util.module_from_spec(spec);spec.loader.exec_module(e);h=e.h
v=e.e.module('postrun_retained_validation','legacy-target-change-validation-r3.py')
processes=e.e.module('postrun_processes','target-postrun-process-r1.py')
f=e.e.module('postrun_durable_outcomes','capture-state-finalization-r2.py')
geometry=e.e.module('postrun_success_geometry','target-success-viewport-r1.py')
p=argparse.ArgumentParser();p.add_argument('prefix');p.add_argument('--checker-source',required=True);p.add_argument('--case-source',required=True);p.add_argument('--build',required=True);p.add_argument('--trial',required=True)
a=p.parse_args();assert re.fullmatch(r'[A-Za-z0-9-]+',a.prefix) and re.fullmatch(r'[A-Za-z0-9-]+',a.trial)
for name in [a.checker_source,a.case_source,a.build]:assert Path(name).name==name and name.endswith('.json')
path=BASE/(a.prefix+'-confirmation-r1-'+a.trial.lower()+'-outcome.json');assert not os.path.lexists(path),'Never overwrite an audit attempt'
result={'status':'FAILED or incomplete readonly checker; no acceptance','checkerExit':1,'checkerSource':a.checker_source,'caseSource':a.case_source,'build':a.build,'prefix':a.prefix,'trial':a.trial,'physicalPhoneActions':False,'started':time.time()}
write_errors=[]
def persist():
 failure=f.record_outcome(path,result)
 if failure:
  write_errors.append(failure)
  raise RuntimeError('Outcome persistence failed; no acceptance')
def verify_checker_source(name):
 source=h.load(BASE/name);archive=json.loads(gzip.decompress(h.read(BASE/(name+'.gz'),8*1024*1024)));count=0
 for group,key in [('files','files'),('fixtureInputs','binaryFiles')]:
  assert set(source[group])==set(archive[key])
  for file,wanted in source[group].items():
   raw=h.read(h.REPO/file,4*1024*1024)
   saved=archive[key][file].encode() if key=='files' else base64.b64decode(archive[key][file],validate=True)
   assert raw==saved and len(raw)==wanted['bytes'] and h.sha(raw)==wanted['sha256'],file
   count+=1
 return {'source':name,'exactCurrentArchiveBindings':count,'manifestSHA256':h.sha(h.read(BASE/name))}
try:
 persist()
 result['checkerSourceVerification']=verify_checker_source(a.checker_source);persist()
 out=h.load(BASE/(a.prefix+'-outcome.json'))
 assert out['source']==a.case_source and out['build']==a.build;assert out['driverExit']==out['nativeExit']==0 and out['hostError'] is None
 assert out['status'].startswith('PASS actual native1/0/0')
 for key in ['outcomePersistenceErrors','finalizationPersistenceErrors','nativeFinalizationError','retainerException','salvageException','emergencyOutcomePersistenceError','failure']:
  assert not out.get(key),key
 assert not list(BASE.glob(a.prefix+'*emergency.json'))
 state=h.load(BASE/(a.prefix+'-host-audit.json'));assert state['source']==a.case_source and state['build']==a.build
 assert state['hostSource']==a.checker_source
 assert state['hostSourceVerification']==result['checkerSourceVerification']==e.verify_host_source(a.checker_source)
 inputs=h.verify_inputs(state['source'],state['build'])
 assert state['preflight']==inputs, 'Retained preflight must bind actual reviewed source/build/app/test inputs'
 assert state['device']==h.DEVICE and len(state['boundaries'])==len(state['messages'])==8
 assert [r['phase'] for r in state['boundaries']]==e.PHASES
 first=state['boundaries'][0]['protected'];v.protected(first,first,h)
 assert len(first['current']['files'])==len(first['prior']['files'])==13
 assert first['provider']==state['provider'];v.selection(state['selection'],state['provider'],state['appPID'],h)
 v.selection(state['freshSelection'],state['provider'],state['appPID'],h)
 assert set(state['selection']['workspaces']).isdisjoint(state['freshSelection']['workspaces'])
 assert not {'meals.json','workouts.json'}&set(first['current']['files'])
 for index,row in enumerate(state['boundaries']):
  assert row['status']=='PASS'
  value=e.check_state(row['observation'],state['started'],state['runID'],state['appPID'])
  assert value['sequence']==e.COUNTS[index] and value['status']==e.STATUSES[index]
  assert state['messages'][index]['value']=={**{k:value[k] for k in ['runID','pid','sessionID','captureID','sequence']},'phase':'host-'+row['phase']}
  # Recheck actual trace rows without replacing retained data with live data.
  expected=[[],['open','ready'],['open','ready','acquire'],['open','ready','acquire','acquire'],['open','ready','acquire','acquire','closed'],['open','ready','acquire','acquire','closed','open','ready'],['open','ready','acquire','acquire','closed','open','ready','acquire'],['open','ready','acquire','acquire','closed','open','ready','acquire','closed']][index]
  assert [r['event'] for r in row['originEvents']]==expected
  assert all(r['sessionID']==state['oldSession'] for r in row['originEvents'][:5])
  assert all(r['sessionID']==state['boundaries'][5]['observation']['sessionID'] for r in row['originEvents'][5:])
  for ordinal,event in enumerate(row['originEvents']):
   if event['event']=='ready':assert event['domains']==['meals','workouts']
   if event['event']=='acquire':assert event['domains']==(['meals','workouts'] if ordinal==7 else ['meals'])
  endpoints=row['endpoints'] if index in [4,7] else [row]
  if index in [4,7]:
   assert len(endpoints)==2 and endpoints[1]['monotonic']-endpoints[0]['monotonic']>=3
   selection=state['selection'] if index==4 else state['freshSelection']
   assert row['ownerClosureSamples'][-1]['workspaces']=={}
   for endpoint in endpoints:v.cleanup(endpoint['cleanup'],selection)
  for endpoint in endpoints:
   if index<6:v.protected(endpoint['protected'],first,h)
   else:e.success.validate(endpoint['success'],first,state['provider'],h,v,state['started'])
   if index>=6:assert endpoint['success']['group']==str(Path(row['nativeCheckpoint']['file']).parent)
   v.fixed(endpoint['fixed'],h.DATA if index<2 else e.obs.NEW,h,e.obs)
   assert endpoint['process']['pid']==state['appPID']
   if 'selected' in endpoint:
    selection=state['freshSelection'] if index>=5 else state['selection']
    assert endpoint['selected']==selection
  if index==0:
   v.bootstrap(row['initialBootstrap'],row,h)
   v.bootstrap_context(row['finalBootstrapContext'],row,h)
   v.protected(row['postBootstrapProtected'],first,h)
  if index==2:v.persistence(row['preferencePersistence'],h,e.obs)
  if index==6:
   def check_retirement_sample(sample):
    success=sample['success'];assert success['group']==str(Path(row['nativeCheckpoint']['file']).parent)
    checked=e.success.validate_payloads(success,first,state['provider'],h,v,state['started'])
    e.retirement.validate_namespace(success['namespace'],first,success['current'],checked,h)
    assert success['namespace']['group']==success['group']
    assert sample['process']=={'pid':state['appPID'],'executable':first_installed['path']}
    assert sample['installed']==first_installed
    assert sample['heldNative']['file']==row['nativeCheckpoint']['file']
    assert v.payload(sample['heldNative'],h,128*1024)==v.payload(row['nativeCheckpoint'],h,128*1024)
    v.fixed(sample['fixed'],e.obs.NEW,h,e.obs)
    assert sample['selected']==state['freshSelection'] and sample['originEvents']==row['originEvents']
   first_installed=state['boundaries'][0]['installed']
   e.retirement.validate_wait(row['retirement'],check_retirement_sample)
   final=row['retirement']['samples'][-1]
   assert all(row[key]==final[key] for key in ['success','process','installed','heldNative','fixed','selected'])

 retained=out['retention'];assert not retained['errors']
 assert retained==h.load(BASE/(a.prefix+'-retention-state.json'))
 assert retained['images']==h.load(BASE/(a.prefix+'-images.json'))
 assert retained['readbacks']==h.load(BASE/(a.prefix+'-readbacks.json'))
 assert retained['summary']==out['summary']==h.load(BASE/(a.prefix+'-summary.json'))
 assert retained['summaryAvailable'] is True
 import gzip
 for query in retained['queries']:
  assert query['exitCode']==0
  for stream in ['stdout','stderr']:
   fact=query[stream];raw=gzip.decompress(h.read(BASE/fact['retained'],4*1024*1024))
   assert fact['retainedExact'] is True and len(raw)==fact['bytes'] and h.sha(raw)==fact['sha256']
 fact=retained['log'];raw=gzip.decompress(h.read(BASE/fact['retained'],8*1024*1024))
 assert fact['retainedExact'] is True and len(raw)==fact['bytes'] and h.sha(raw)==fact['sha256']
 assert [retained['summary'][k] for k in ['passedTests','failedTests','skippedTests']]==[1,0,0]
 assert len(retained['images'])==17 and len(retained['readbacks'])==1
 names=[]
 for row in retained['images']+retained['readbacks']:
  data=h.read(BASE/row['file'],4*1024*1024);assert len(data)==row['bytes'] and h.sha(data)==row['sha256']
  if row in retained['images']:
   label=row['metadata']['suggestedHumanReadableName']
   matches=[suffix for suffix in e.IMAGES if label.startswith('health-legacy-target-change-'+suffix+'_')]
   assert len(matches)==1;names+=matches
 assert set(names)==set(e.IMAGES)
 helper=h.load(BASE/retained['readbacks'][0]['file']);assert helper['phase']=='completed'
 assert helper['scope']=='actual-legacy-target-change-during-confirmation'
 commits=[r for r in helper['observations'] if r['phase']=='fresh-committed' and 'message' in r]
 assert len(commits)==1 and commits[0]['hittable'] is True and commits[0]['message']=='Selected data recovered'
 assert commits[0]['wholeSuccessBeforeAnyTestScroll'] is True
 geometry.validate(commits[0])
 assert state['started'] <= commits[0]['at'] <= time.time()
 assert not any(r['phase']=='fresh-committed' and 'pan' in r for r in helper['observations'])
 args=helper['launchArguments']
 for flag,expected in [('-health-legacy-target-change-ui','ready'),('-health-legacy-target-change-run',state['runID']),('-health-legacy-reset-run',state['runID']),('-health-legacy-origin-ui','data'),('-health-backup-case','legacy')]:
  assert args.count(flag)==1 and args[args.index(flag)+1]==expected
 assert not helper.get('failure')
 startup=[r for r in helper['observations'] if r['phase']=='native-before-selection-tap']
 assert len(startup)==1 and startup[0]['identifier']=='startHealthRecoveryCheck'
 assert startup[0]['beforeTouchHittable'] is True and startup[0]['beforeTouchEnabled'] is True
 assert [r['phase'] for r in helper['observations'] if 'probeValue' in r]==e.PHASES
 assert args.count('-health-legacy-confirmation-window-ui')==1
 gate=e.e.module('checked_confirmation_window','confirmation-window-evidence-r1.py')
 window=state['confirmationWindow'];assert window['acknowledged'] is True
 gateValue=json.loads(base64.b64decode(window['gate']['base64'],validate=True))
 marker=json.loads(base64.b64decode(window['marker']['base64'],validate=True))
 native=json.loads(base64.b64decode(window['nativeBefore']['base64'],validate=True))
 assert native==state['boundaries'][1]['observation']
 ack=gate.validate(gateValue,native,marker,state['started'],window['ackAt'])
 assert window['ackIntended']['value']==ack
 assert json.loads(base64.b64decode(window['ackBytes']['base64'],validate=True))==ack
 assert window['markerFile'].endswith('/tmp/Lumen-confirmation-ui-'+gateValue['nonce'].lower()+'.json')
 assert marker['at']<=window['ackAt']<=state['boundaries'][2]['observation']['at']
 assert window['gateIdentity']['st_mtime_ns']/1e9>=state['started']
 assert window['markerIdentity']['st_mtime_ns']/1e9>=state['started']
 v.protected(window['protectedBeforeAck'],first,h)
 assert window['selected']==state['selection'] and window['installed']==state['boundaries'][0]['installed']
 v.fixed(window['fixed'],h.DATA,h,e.obs)
 observed=[r for r in helper['observations'] if r['phase']=='confirmation-before-mutation']
 assert len(observed)==1 and observed[0]['marker']==marker and observed[0]['markerFile']==window['markerFile']
 screenshots=[r for r in retained['images'] if r['metadata']['suggestedHumanReadableName'].startswith('health-legacy-target-change-confirmation-before-mutation_')]
 assert len(screenshots)==1 and screenshots[0]['sha256']==marker['imageSHA256'] and screenshots[0]['bytes']==marker['imageBytes']
 assert screenshots[0]['metadata']['timestamp']<=marker['at']+0.5
 result['confirmationWindow']={'status':'PASS retained actual UI/nonce gate/unchanged-old baseline/native single-write ordering','nonce':gateValue['nonce'],'originalImageSHA256':marker['imageSHA256'],'markerAt':marker['at'],'ackAt':window['ackAt']};persist()
 v.all_payloads(state,h,inputs['app'])
 previous=-1
 for native in state['nativeStates']:
  data=v.payload(native,h,128*1024);assert json.loads(data)==native['value']
  value=e.check_state(native['value'],state['started'],state['runID'],state['appPID'])
  assert value['sequence']>=previous;previous=value['sequence']
 assert state['nativeStates'][-1]['value']==state['boundaries'][-1]['observation']
 result['retainedValidationComplete']=True
 result['actualNativeCounts']=[retained['summary'][k] for k in ['passedTests','failedTests','skippedTests']]
 result['actualNativeExit']=out['nativeExit'];result['actualDriverExit']=out['driverExit'];persist()
 group=h.container('group.com.dbakp.lumen');data_container=h.container('data')
 assert str(data_container)==state['appData']
 expected=state['boundaries'][0]['installed']
 result['installedBeforeAudit']=h.installed(state['build']);persist()
 assert result['installedBeforeAudit']==expected
 executable=expected['path'];native=state['nativeStates'][-1]
 assert Path(native['file']).parent==group
 def collect(row,mode):
  row['installed']=h.installed(state['build']);persist();assert row['installed']==expected
  row['nativeState']={'file':native['file'],**h.row(h.read(native['file'],128*1024))};persist()
  assert row['nativeState']['base64']==native['base64']
  current=json.loads(base64.b64decode(row['nativeState']['base64'],validate=True))
  e.check_state(current,state['started'],state['runID'],state['appPID']);assert current==state['boundaries'][-1]['observation']
  row['success']={};e.success.collect_current(group,row['success'],first,state['provider'],h,e,v,state['started']);persist()
  row['success']['namespace']={};e.retirement.collect(group,row['success']['namespace'],first,row['success']['current'],row['success']['validation'],h,persist)
  e.retirement.validate_namespace(row['success']['namespace'],first,row['success']['current'],row['success']['validation'],h)
  e.success.validate(row['success'],first,state['provider'],h,v,state['started']);persist()
  row['fixed']={};e.obs.sample(data_container/'Library/Preferences/com.dbakp.lumen.plist',h,row['fixed'],persist,[e.obs.NEW])
  row['originEvents']=e.origin_trace(group,7,state['oldSession'],state['boundaries'][5]['observation']['sessionID']);persist()
  row['owned']=h.owned(state['appPID']);row['caseRoots']={p:os.path.lexists(p) for key in ['selection','freshSelection'] for p in state[key]['workspaces']};persist()
  assert not row['owned'] and not any(row['caseRoots'].values())
 def live_paths(sink):
  sink['old']=e.e.no_owned(state['selection'],state['appPID']);persist()
  sink['fresh']=e.e.no_owned(state['freshSelection'],state['appPID']);persist()
 result['finalAudit']={}
 processes.audit(state['appPID'],executable,result['finalAudit'],persist,collect,live_paths)
 assert not write_errors and not result.get('outcomePersistenceErrors') and not Path(str(path)+'.emergency.json').exists()
 result.update(status='PASS retained '+a.case_source+' native case and explicit final process/protected endpoints; root/independent review pending',checkerExit=0,finished=time.time(),scope='No new native run/build/relaunch/reset/defaults write. Sampled lifecycle endpoints only; original R4failure remains immutable, fresh commit is separately validated at retained and final endpoints; remaining timings/String/healthy/retained-copy/full43/eightgroups open.')
 persist()
except BaseException:
 result.update(status='FAILED readonly successor checker; no acceptance',checkerExit=1,failure=traceback.format_exc(),finished=time.time())
 try:persist()
 except BaseException:pass
print(json.dumps({'status':result['status'],'checkerExit':result['checkerExit'],'outcome':path.name,'caseSource':a.case_source,'checkerSource':a.checker_source}),flush=True)
raise SystemExit(result['checkerExit'])
