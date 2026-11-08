"""Strict genuine healthy eligibility failure replay; never accepts the failed case."""
from pathlib import Path
import json,gzip,importlib.util,time
B=Path(__file__).resolve().parent;prefix='health-healthy-target-change-data-source243r1'
def load(s):return json.loads((B/(prefix+s)).read_bytes())
spec=importlib.util.spec_from_file_location('root243failure',B/'healthy-target-evidence-r3.py');e=importlib.util.module_from_spec(spec);spec.loader.exec_module(e);h=e.h;v=e.v;region=e.e.module('root243region','healthy-target-region-r1.py')
state=load('-driver-observations.json');out=load('-outcome.json');final=load('-healthy-r3-source243r1-outcome.json')
assert out['nativeExit']==65 and out['driverExit']==final['checkerExit']==1 and 'finalAudit' not in final
assert [out['summary'][k] for k in ['passedTests','failedTests','skippedTests']]==[0,1,0]
inputs=h.verify_inputs('durable-source-r242.json','health-target-change-source242-r1-build.json');assert state['preflight']==inputs and state['hostSourceVerification']==e.verify_host_source('durable-source-r243.json')==final['checkerSourceVerification']
assert len(state['boundaries'])==len(state['messages'])==6 and [r['phase'] for r in state['boundaries']]==e.PHASES[:6]
first=state['boundaries'][0]['protected'];healthy=state['healthyBaseline'];leaf=state['boundaries'][2]['observation']['events'][6]['mealFile'];assert healthy==state['boundaries'][2]['protected'];e.healthy.validate(healthy,first,leaf,h,v)
old=state['oldSession'];fresh=state['boundaries'][5]['observation']['sessionID'];assert old!=fresh
expected=[[],['open','ready'],['open','ready','acquire'],['open','ready','acquire','acquire'],['open','ready','acquire','acquire','closed'],['open','ready','acquire','acquire','closed','open','ready']]
for i,row in enumerate(state['boundaries']):
 assert row['status']=='PASS';value=e.check_state(row['observation'],state['started'],state['runID'],state['appPID']);assert value['sequence']==e.COUNTS[i] and value['status']==e.STATUSES[i]
 assert state['messages'][i]['value']=={**{k:value[k] for k in ['runID','pid','sessionID','captureID','sequence']},'phase':'host-'+row['phase']}
 assert [r['event'] for r in row['originEvents']]==expected[i]
 assert all(r['sessionID']==old for r in row['originEvents'][:5]) and all(r['sessionID']==fresh for r in row['originEvents'][5:])
 for ordinal,event in enumerate(row['originEvents']):
  if event['event']=='ready':assert event['domains']==(['workouts'] if ordinal==6 else ['meals','workouts'])
  if event['event']=='acquire':assert event['domains']==['meals']
 endpoints=row['endpoints'] if i==4 else [row]
 for endpoint in endpoints:
  assert endpoint['process']=={'pid':state['appPID'],'executable':state['boundaries'][0]['installed']['path']}
  if i<2:v.protected(endpoint['protected'],first,h)
  else:e.healthy.validate(endpoint['protected'],first,leaf,h,v,healthy)
  v.fixed(endpoint['fixed'],h.DATA,h,e.obs)
  if 'selected' in endpoint:assert endpoint['selected']==state['freshSelection' if i==5 else 'selection']
 if i==0:v.bootstrap(row['initialBootstrap'],row,h);v.bootstrap_context(row['finalBootstrapContext'],row,h);v.protected(row['postBootstrapProtected'],first,h)
 if i==4:
  assert len(endpoints)==2 and endpoints[1]['monotonic']-endpoints[0]['monotonic']>=3 and row['ownerClosureSamples'][-1]['workspaces']=={}
  for endpoint in endpoints:v.cleanup(endpoint['cleanup'],state['selection'])
v.selection(state['selection'],state['provider'],state['appPID'],h);v.selection(state['freshSelection'],state['provider'],state['appPID'],h)
assert set(state['selection']['workspaces']).isdisjoint(state['freshSelection']['workspaces'])
v.all_payloads(state,h,inputs['app'])
for n in state['nativeStates']:assert json.loads(v.payload(n,h))==n['value'];e.check_state(n['value'],state['started'],state['runID'],state['appPID'])
assert state['nativeStates'][-1]['value']==state['boundaries'][-1]['observation'] and state['nativeStates'][-1]['value']['sequence']==12
ret=out['retention'];assert not ret['errors'] and ret==load('-retention-state.json') and ret['images']==load('-images.json') and ret['readbacks']==load('-readbacks.json') and ret['summary']==load('-summary.json')
for q in ret['queries']:
 assert q['exitCode']==0
 for key in ['stdout','stderr']:
  f=q[key];raw=gzip.decompress((B/f['retained']).read_bytes());assert f['retainedExact'] and len(raw)==f['bytes'] and h.sha(raw)==f['sha256']
f=ret['log'];raw=gzip.decompress((B/f['retained']).read_bytes());assert len(raw)==f['bytes'] and h.sha(raw)==f['sha256']
helper=json.loads((B/ret['readbacks'][0]['file']).read_bytes());assert helper['phase']=='fresh-healthy-target' and helper['failure']=='A healthy meal target must not be selectable or offer photo omission'
assert helper['scope']=='actual-healthy-current-file-after-ready-before-confirmation'
ready=next(r for r in helper['observations'] if r['phase']=='fresh-workout-ready-visible');region.validate_readiness(ready)
meal=next(r for r in helper['observations'] if r['phase']=='fresh-healthy-target');assert helper['observations'].index(ready)<helper['observations'].index(meal)
assert all(meal[k] is True for k in ['mealToggleExists','mealToggleEnabled','mealToggleHittable','omissionExists','omissionEnabled','omissionHittable','reviewAnchorExists','reviewAnchorHittable','wholeMealRegionBeforeWorkoutSelection','workoutEnabledAfterCapture'])
assert meal['disclosureCount']==0 and meal['disclosureLabel']=='' and meal['disclosureRect']==[] and meal['omissionValue']=='0'
app=region.rectangle(meal['appRect']);nav=region.rectangle(meal['navigationRect']);view=region.rectangle(meal['viewportRect']);assert region.contains(app,nav)
assert meal['viewportRect']==[app[0],nav[3],app[2]-app[0],app[3]-40-nav[3]]
review=region.rectangle(meal['reviewAnchorRect']);omit=region.rectangle(meal['omissionRect']);control=region.rectangle(meal['mealToggleRect']);whole=region.rectangle(meal['regionRect'])
assert all(region.contains(view,r) for r in [review,omit,control,whole]);assert review[3]<=control[1] and control[3]<=omit[1]
assert whole==(min(review[0],omit[0]),min(review[1],omit[1]),max(review[2],omit[2]),max(review[3],omit[3]))
try:region.validate(meal)
except AssertionError:rejected=True
else:rejected=False
assert rejected
index=load('-all-originals.json');assert index['count']==108 and index['kinds']=={'png':12,'json':1,'binary-plist':85,'text':9,'video':1}
f=index['otherArchive'];raw=gzip.decompress((B/f['file']).read_bytes());assert len(raw)==f['decodedBytes'] and h.sha(raw)==f['decodedSHA256'];others=json.loads(raw)['files'];assert len(others)==94
f=index['completeManifest'];raw=gzip.decompress((B/f['file']).read_bytes());assert len(raw)==f['bytes'] and h.sha(raw)==f['sha256']
root=Path('/tmp/LumenBatch44Checks/HealthHealthyTargetChangeDataSource243R1All')
for row in index['rows']:
 raw=(root/row['file']).read_bytes();assert len(raw)==row['bytes'] and h.sha(raw)==row['sha256']
 if row['kind'] in ['png','json','video']:assert raw==(B/row['retained']).read_bytes()
 else:assert v.payload(others[row['file']],h)==raw
count=[0]
def payloads(x):
 if isinstance(x,dict):
  if isinstance(x.get('base64'),str):v.payload(x,h,64*1024*1024);count[0]+=1
  for y in x.values():payloads(y)
 elif isinstance(x,list):
  for y in x:payloads(y)
payloads(state);video=next(r for r in index['rows'] if r['kind']=='video')
result={'status':'Root strictFAILED243case: sixhostboundaries/genuine staleRecover/oldclosure pass, freshhealthymeal+omission wronglyenabled inwholeanchoredregion; no freshcommit or finalclosure','caseSource':'durable-source-r242.json','hostSource':'durable-source-r243.json','caseBindings':674,'hostBindings':685,'nativePID':state['nativePID'],'appPID':state['appPID'],'runID':state['runID'],'nativeCounts':[0,1,0],'nativeExit':65,'driverExit':1,'checkerExit':1,'hostBoundaries':6,'nativeRawStates':len(state['nativeStates']),'embeddedPayloadInstances':count[0],'healthyMealBytes':len(e.healthy.HEALTHY),'actualFreshRegion':meal,'actualWorkoutReadiness':ready,'oldClosureSpan':state['boundaries'][4]['endpoints'][1]['monotonic']-state['boundaries'][4]['endpoints'][0]['monotonic'],'fullNativeHelperBytes':ret['readbacks'][0]['bytes'],'originalAttachments':108,'originalPNGs':12,'video':{'file':video['retained'],'bytes':video['bytes'],'sha256':video['sha256'],'played':False},'scope':'Freshpresentation failure only, no actual healthyoverwrite/workoutselection/commit/finalBack. Exacthealthy14/prior13/Data42 protectedthroughfreshready; laterreadonlyrecordrequiredaftertest. No continuousabsence/exitcause/globalFD/VOspeech/motion/Release/fullgoalacceptance.','checkedAt':time.time()};p=B/'source243-root-native-failure-audit-r1.json';assert not p.exists();p.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({k:result[k] for k in ['status','nativeRawStates','embeddedPayloadInstances','oldClosureSpan','fullNativeHelperBytes','video']}))
