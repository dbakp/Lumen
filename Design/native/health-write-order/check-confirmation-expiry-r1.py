"""Mandatory retained-case validation plus explicit live/absent app endpoints.
Host-only successor: never reruns, launches or repairs the native app.
"""
import argparse,base64,gzip,hashlib,importlib.util,json,os,re,time,traceback
from pathlib import Path
BASE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('postrun_checker_evidence',BASE/'confirmation-expiry-evidence-r1.py')
e=importlib.util.module_from_spec(spec);spec.loader.exec_module(e);h=e.h
v=e.e.module('postrun_retained_validation','legacy-target-change-validation-r3.py')
processes=e.e.module('postrun_processes','target-postrun-process-r1.py')
f=e.e.module('postrun_durable_outcomes','capture-state-finalization-r2.py')
geometry=e.e.module('postrun_success_geometry','target-success-viewport-r1.py')
p=argparse.ArgumentParser();p.add_argument('prefix');p.add_argument('--checker-source',required=True);p.add_argument('--case-source',required=True);p.add_argument('--build',required=True);p.add_argument('--trial',required=True)
a=p.parse_args();assert re.fullmatch(r'[A-Za-z0-9-]+',a.prefix) and re.fullmatch(r'[A-Za-z0-9-]+',a.trial)
for name in [a.checker_source,a.case_source,a.build]:assert Path(name).name==name and name.endswith('.json')
path=BASE/(a.prefix+'-expiry-r1-'+a.trial.lower()+'-outcome.json');assert not os.path.lexists(path),'Never overwrite an audit attempt'
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
 assert state['device']==h.DEVICE and len(state['boundaries'])==len(state['messages'])==5
 assert [r['phase'] for r in state['boundaries']]==e.PHASES
 first=state['boundaries'][0]['protected'];v.protected(first,first,h)
 assert len(first['current']['files'])==len(first['prior']['files'])==13
 assert first['provider']==state['provider']
 for key in ['selection','freshSelection']:v.selection(state[key],state['provider'],state['appPID'],h)
 assert set(state['selection']['workspaces']).isdisjoint(state['freshSelection']['workspaces'])
 expected_traces=[[],['open','ready'],['open','ready','closed'],['open','ready','closed','open','ready'],['open','ready','closed','open','ready','closed']]
 for index,row in enumerate(state['boundaries']):
  assert row['status']=='PASS'
  value=e.check_state(row['observation'],state['started'],state['runID'],state['appPID'])
  assert value['sequence']==e.COUNTS[index] and value['status']==e.STATUSES[index]
  assert json.loads(v.payload(row['nativeCheckpoint'],h,128*1024))==value
  message=state['messages'][index]
  assert message['value']=={**{k:value[k] for k in ['runID','pid','sessionID','captureID','sequence']},'phase':'host-'+row['phase']}
  assert [r['event'] for r in row['originEvents']]==expected_traces[index]
  assert all(r['sessionID']==state['oldSession'] for r in row['originEvents'][:3])
  assert all(r['sessionID']==state['boundaries'][3]['observation']['sessionID'] for r in row['originEvents'][3:])
  for event in row['originEvents']:
   if event['event']=='ready':assert event['domains']==['meals','workouts']
  endpoints=row['endpoints'] if index in [2,4] else [row]
  if index in [2,4]:
   assert len(endpoints)==2 and endpoints[1]['monotonic']-endpoints[0]['monotonic']>=3
   assert row['ownerClosureSamples'][-1]['workspaces']=={}
   for endpoint in endpoints:v.cleanup(endpoint['cleanup'],state['selection'] if index==2 else state['freshSelection'])
  for endpoint in endpoints:
   v.protected(endpoint['protected'],first,h);v.fixed(endpoint['fixed'],h.DATA,h,e.obs)
   assert endpoint['process']=={'pid':state['appPID'],'executable':state['boundaries'][0]['installed']['path']}
   assert endpoint['installed']==state['boundaries'][0]['installed']
   if 'selected' in endpoint:assert endpoint['selected']==state['freshSelection'] if index==3 else endpoint['selected']==state['selection']
  if index==0:
   v.bootstrap(row['initialBootstrap'],row,h);v.bootstrap_context(row['finalBootstrapContext'],row,h)
   v.protected(row['postBootstrapProtected'],first,h)
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
 assert len(retained['images'])==15 and len(retained['readbacks'])==1
 names=[]
 for row in retained['images']+retained['readbacks']:
  data=h.read(BASE/row['file'],4*1024*1024);assert len(data)==row['bytes'] and h.sha(data)==row['sha256']
  if row in retained['images']:
   label=row['metadata']['suggestedHumanReadableName']
   matches=[suffix for suffix in e.IMAGES if label.startswith('health-confirmation-expiry-'+suffix+'_')]
   assert len(matches)==1;names+=matches
 assert set(names)==set(e.IMAGES)
 helper=h.load(BASE/retained['readbacks'][0]['file']);assert helper['phase']=='completed'
 assert helper['scope']=='actual-confirmation-expiry-before-notnow-late-ack'
 args=helper['launchArguments']
 for flag,expected in [('-health-legacy-target-change-ui','ready'),('-health-legacy-target-change-run',state['runID']),('-health-legacy-reset-run',state['runID']),('-health-legacy-origin-ui','data'),('-health-backup-case','legacy')]:
  assert args.count(flag)==1 and args[args.index(flag)+1]==expected
 assert not helper.get('failure')
 startup=[r for r in helper['observations'] if r['phase']=='native-before-selection-tap']
 assert len(startup)==1 and startup[0]['identifier']=='startHealthRecoveryCheck'
 assert startup[0]['beforeTouchHittable'] is True and startup[0]['beforeTouchEnabled'] is True
 assert [r['phase'] for r in helper['observations'] if 'probeValue' in r]==e.PHASES
 assert args.count('-health-legacy-confirmation-window-ui')==1
 assert args.count('-health-legacy-confirmation-lifecycle-ui')==1
 assert args.count('-health-legacy-confirmation-expiry-ui')==1
 gate=e.e.module('checked_lifecycle_geometry','confirmation-window-evidence-r3.py')
 protocol=e.e.module('checked_lifecycle_protocol','confirmation-expiry-protocol-r1.py')
 window=state['confirmationWindow'];assert window['acknowledged'] is True and window['hostCheckCompleted'] is True
 def retained_value(key,immutable=False):
  rows=window[key]['versions'];assert rows
  if immutable:assert len(rows)==1
  for row in rows:v.payload(row,h,16384)
  return json.loads(v.payload(rows[-1],h,16384))
 actual=retained_value('gate',True);protocol.binding(actual)
 gate.validate_binding(actual,state['boundaries'][1]['observation'])
 main=retained_value('trace');protocol.trace(main,actual,state['started'],complete=True)
 relays=window['relays'];assert len(relays)==4
 assert window['hostExpiryCheckpointPublished'] is True
 armed=dict(actual,taskGeneration=main['taskGeneration'],phase='armed',targetPhase='host-ready')
 ackraw=v.payload(window['ackBytes'],h,4096)
 assert window['ackIntended']['raw']==window['ackBytes']
 assert json.loads(ackraw)=={**{k:actual[k] for k in ['runID','pid','sessionID','captureID','nonce']},'phase':'ui-observed'}
 expired=retained_value('expired',True)
 presented=retained_value('presented',True);dismissed=retained_value('dismissed',True);checked=retained_value('checked',True)
 for phase,item in [('presented',presented),('expired',expired),('dismissed',dismissed),('checked',checked)]:
  protocol.marker(item,phase,armed,state['started'],time.time(),gate)
  matches=[r for r in retained['images'] if r['metadata']['suggestedHumanReadableName'].startswith(item['attachmentName']+'_')]
  assert len(matches)==1 and matches[0]['bytes']==item['imageBytes'] and matches[0]['sha256']==item['imageSHA256']
  markers=[r for r in helper['observations'] if r['phase']=='ui-marker-'+phase]
  assert len(markers)==1 and markers[0]['value']==item and markers[0]['file']==window[phase]['file']
 expiry_raw=v.payload(window['expiryTrace'],h,16384);expiry_trace=json.loads(expiry_raw)
 protocol.trace(expiry_trace,actual,state['started'])
 assert len(expiry_trace['events'])==4 and expiry_trace['checks']==[]
 assert expiry_trace['events']==main['events'][:4] and expiry_trace['taskGeneration']==main['taskGeneration']
 assert any(row=={k:window['expiryTrace'][k] for k in ['bytes','sha256','base64']} for row in window['trace']['versions'])
 assert presented['at']<=main['events'][2]['at']<=main['events'][3]['at']<=window['expiryTrace']['readAt']<=relays[1]['publicationStartedAt']<=expired['at']<=dismissed['touchAt']<=main['events'][4]['at']
 assert dismissed['touchAt']<=dismissed['tapReturnedAt']<=dismissed['at']
 assert dismissed['cancelFrame']==expired['cancelFrame']
 assert max(main['events'][-1]['at'],dismissed['at'])<=window['ackAt']<=window['ackPublishedObservedAt']
 observation=retained_value('check');value=protocol.check(observation,main,ackraw,window['ackPublishedObservedAt'],checked['touchAt'],checked['tapReturnedAt'],e)
 assert main['checks'][0]['file']==window['check']['file']
 assert main['checks'][0]['bytes']==window['check']['versions'][-1]['bytes'] and main['checks'][0]['sha256']==window['check']['versions'][-1]['sha256']
 expected=[armed,dict(armed,phase='expired',targetPhase='host-expired',expiredTraceSHA256=h.sha(expiry_raw)),dict(armed,phase='late-ack',targetPhase='host-late-ack',ackSHA256=h.sha(ackraw)),dict(armed,phase='checked',targetPhase='host-checked',ackSHA256=h.sha(ackraw),checkRequestID=value['requestID'],checkOrdinal='1')]
 for index,row in enumerate(relays):
  assert row['status']=='PUBLISHED metadata-only relay' and row['value']==expected[index]
  assert json.loads(v.payload(row['raw'],h,4096))==expected[index]
  assert row['started']<=row['publicationStartedAt']<=row['publicationObservedAt']
  if index:assert relays[index-1]['publicationObservedAt']<=row['started']
  accepted=[r for r in helper['observations'] if r['phase']=='lifecycle-relay' and r['expected']==expected[index]['phase'] and r['status']=='accepted-metadata-only']
  assert len(accepted)==1 and accepted[0]['value']==expected[index]
  assert accepted[0]['at']>=row['publicationStartedAt']
  assert json.loads(v.payload(accepted[0]['raw'],h,4096))==expected[index]
 assert relays[0]['publicationObservedAt']<=presented['at']
 assert window['ackPublishedObservedAt']<=relays[2]['publicationStartedAt']<=checked['touchAt']
 assert checked['lateRelay']==expected[2] and checked['at']<=relays[3]['publicationStartedAt']
 assert expired['expiredRelay']==expected[1] and relays[1]['publicationObservedAt']<=expired['at']
 for key in ['protectedBeforeExpired','protectedBeforeLateAck','protectedAfterCheck']:
  row=window[key];v.protected(row['protected'],first,h);v.fixed(row['fixed'],h.DATA,h,e.obs)
  assert row['selected']==state['selection'] and row['installed']==state['boundaries'][0]['installed']
  assert row['process']['pid']==state['appPID']
 for key in ['originBeforeExpired','originBeforeLateAck','originAfterCheck']:assert window[key]==state['boundaries'][1]['originEvents']
 for row in state['nativeStates']:e.check_state(json.loads(v.payload(row,h,128*1024)),state['started'],state['runID'],state['appPID'])
 v.all_payloads(state,h,inputs['app'])
 native=state['boundaries'][-1]['nativeCheckpoint'];group=Path(native['file']).parent
 data_container=Path(state['appData']);expected=state['boundaries'][0]['installed'];executable=expected['path']
 def collect(row,mode):
  row['installed']=h.installed(state['build']);persist();assert row['installed']==expected
  row['nativeState']={'file':native['file'],**h.row(h.read(native['file'],128*1024))};persist()
  assert row['nativeState']['base64']==native['base64']
  current=json.loads(base64.b64decode(row['nativeState']['base64'],validate=True))
  e.check_state(current,state['started'],state['runID'],state['appPID']);assert current==state['boundaries'][-1]['observation']
  row['protected']={};e.protected(group,row['protected'],first);persist()
  row['fixed']={};e.obs.sample(data_container/'Library/Preferences/com.dbakp.lumen.plist',h,row['fixed'],persist,[h.DATA])
  row['originEvents']=e.origin_trace(group,4,state['oldSession'],state['boundaries'][3]['observation']['sessionID']);persist()
  row['owned']=h.owned(state['appPID']);row['caseRoots']={p:os.path.lexists(p) for key in ['selection','freshSelection'] for p in state[key]['workspaces']};persist()
  assert not row['owned'] and not any(row['caseRoots'].values())
 def live_paths(sink):
  sink['old']=e.e.no_owned(state['selection'],state['appPID']);persist()
  sink['fresh']=e.e.no_owned(state['freshSelection'],state['appPID']);persist()
 result['finalAudit']={}
 processes.audit(state['appPID'],executable,result['finalAudit'],persist,collect,live_paths)
 assert not write_errors and not result.get('outcomePersistenceErrors') and not Path(str(path)+'.emergency.json').exists()
 result.update(status='PASS retained '+a.case_source+' native case and explicit final process/protected endpoints; root/independent review pending',checkerExit=0,finished=time.time(),scope='No new native run/build/relaunch/reset/defaults write. Sampled lifecycle endpoints only; Actual Not now/closed-task late acknowledgement/fresh native read only; no Recover or commit in this case. Sampled endpoints only; other windows/retained-copy/full goal remain open; diagnostic waiter expiry establishes no shipping selection TTL.')
 persist()
except BaseException:
 result.update(status='FAILED readonly successor checker; no acceptance',checkerExit=1,failure=traceback.format_exc(),finished=time.time())
 try:persist()
 except BaseException:pass
print(json.dumps({'status':result['status'],'checkerExit':result['checkerExit'],'outcome':path.name,'caseSource':a.case_source,'checkerSource':a.checker_source}),flush=True)
raise SystemExit(result['checkerExit'])
