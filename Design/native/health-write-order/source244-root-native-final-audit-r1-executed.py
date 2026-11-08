"""Root strict replay of the actual healthy-target case and actual R3 endpoints."""
from pathlib import Path
import json,gzip,importlib.util,time
B=Path(__file__).resolve().parent;prefix='health-healthy-target-change-data-source244r1'
def load(s):return json.loads((B/(prefix+s)).read_bytes())
spec=importlib.util.spec_from_file_location('root244native',B/'healthy-target-evidence-r3.py');e=importlib.util.module_from_spec(spec);spec.loader.exec_module(e);h=e.h;v=e.v
region=e.e.module('root244region','healthy-target-region-r1.py');geometry=e.e.module('root244success','target-success-viewport-r1.py');processes=e.e.module('root244process','target-postrun-process-r1.py')
state=load('-host-audit.json');out=load('-outcome.json');final=load('-healthy-r3-source244r1-outcome.json');assert final['checkerExit']==out['nativeExit']==out['driverExit']==0
assert [out['summary'][k] for k in ['passedTests','failedTests','skippedTests']]==[1,0,0]
inputs=h.verify_inputs('durable-source-r244.json','health-target-change-source244-r1-build.json');assert state['preflight']==inputs and state['hostSourceVerification']==e.verify_host_source('durable-source-r244.json')==final['checkerSourceVerification']
assert len(state['boundaries'])==len(state['messages'])==8 and [r['phase'] for r in state['boundaries']]==e.PHASES
first=state['boundaries'][0]['protected'];healthy=state['healthyBaseline'];leaf=state['boundaries'][2]['observation']['events'][6]['mealFile'];assert healthy==state['boundaries'][2]['protected'];e.healthy.validate(healthy,first,leaf,h,v)
old=state['oldSession'];fresh=state['boundaries'][5]['observation']['sessionID'];assert old!=fresh
expected=[[],['open','ready'],['open','ready','acquire'],['open','ready','acquire','acquire'],['open','ready','acquire','acquire','closed'],['open','ready','acquire','acquire','closed','open','ready'],['open','ready','acquire','acquire','closed','open','ready','acquire'],['open','ready','acquire','acquire','closed','open','ready','acquire','closed']]
for i,row in enumerate(state['boundaries']):
 assert row['status']=='PASS';value=e.check_state(row['observation'],state['started'],state['runID'],state['appPID']);assert value['sequence']==e.COUNTS[i] and value['status']==e.STATUSES[i]
 assert state['messages'][i]['value']=={**{k:value[k] for k in ['runID','pid','sessionID','captureID','sequence']},'phase':'host-'+row['phase']}
 assert [r['event'] for r in row['originEvents']]==expected[i]
 assert all(r['sessionID']==old for r in row['originEvents'][:5]) and all(r['sessionID']==fresh for r in row['originEvents'][5:])
 for ordinal,event in enumerate(row['originEvents']):
  if event['event']=='ready':assert event['domains']==(['workouts'] if ordinal==6 else ['meals','workouts'])
  if event['event']=='acquire':assert event['domains']==(['workouts'] if ordinal==7 else ['meals'])
 endpoints=row['endpoints'] if i in [4,7] else [row]
 for endpoint in endpoints:
  assert endpoint['process']=={'pid':state['appPID'],'executable':state['boundaries'][0]['installed']['path']}
  if i<2:v.protected(endpoint['protected'],first,h)
  elif i<6:e.healthy.validate(endpoint['protected'],first,leaf,h,v,healthy)
  else:e.success.validate(endpoint['success'],healthy,state['provider'],h,v,state['started'])
  v.fixed(endpoint['fixed'],h.DATA,h,e.obs)
  if 'selected' in endpoint:assert endpoint['selected']==state['freshSelection' if i>=5 else 'selection']
 if i==0:v.bootstrap(row['initialBootstrap'],row,h);v.bootstrap_context(row['finalBootstrapContext'],row,h);v.protected(row['postBootstrapProtected'],first,h)
 if i in [4,7]:
  assert len(endpoints)==2 and endpoints[1]['monotonic']-endpoints[0]['monotonic']>=3 and row['ownerClosureSamples'][-1]['workspaces']=={}
  for endpoint in endpoints:v.cleanup(endpoint['cleanup'],state['selection' if i==4 else 'freshSelection'])
 if i==6:
  def sample_check(sample):
   success=sample['success'];proof=e.success.validate_payloads(success,healthy,state['provider'],h,v,state['started']);e.retirement.validate_namespace(success['namespace'],healthy,success['current'],proof,h)
   assert sample['process']==row['process'] and sample['installed']==row['installed'];assert v.payload(sample['heldNative'],h)==v.payload(row['nativeCheckpoint'],h)
   assert sample['selected']==state['freshSelection'] and sample['originEvents']==row['originEvents'];v.fixed(sample['fixed'],h.DATA,h,e.obs)
  e.retirement.validate_wait(row['retirement'],sample_check)
v.selection(state['selection'],state['provider'],state['appPID'],h);v.selection(state['freshSelection'],state['provider'],state['appPID'],h);assert set(state['selection']['workspaces']).isdisjoint(state['freshSelection']['workspaces'])
v.all_payloads(state,h,inputs['app'])
for n in state['nativeStates']:assert json.loads(v.payload(n,h))==n['value'];e.check_state(n['value'],state['started'],state['runID'],state['appPID'])
assert state['nativeStates'][-1]['value']==state['boundaries'][-1]['observation']
ret=out['retention'];assert not ret['errors'] and ret==load('-retention-state.json') and ret['images']==load('-images.json') and ret['readbacks']==load('-readbacks.json');assert len(ret['images'])==17 and len(ret['readbacks'])==1
for query in ret['queries']:
 assert query['exitCode']==0
 for key in ['stdout','stderr']:
  f=query[key];raw=gzip.decompress((B/f['retained']).read_bytes());assert f['retainedExact'] and len(raw)==f['bytes'] and h.sha(raw)==f['sha256']
f=ret['log'];raw=gzip.decompress((B/f['retained']).read_bytes());assert f['retainedExact'] and len(raw)==f['bytes'] and h.sha(raw)==f['sha256']
for row in ret['images']+ret['readbacks']:
 raw=(B/row['file']).read_bytes();assert len(raw)==row['bytes'] and h.sha(raw)==row['sha256']
labels=[r['metadata']['suggestedHumanReadableName'] for r in ret['images']];matches=[]
for label in labels:
 found=[suffix for suffix in e.IMAGES if label.startswith('health-healthy-target-change-'+suffix+'_')];assert len(found)==1;matches+=found
assert len(set(matches))==17 and set(matches)==set(e.IMAGES)
helper=json.loads((B/ret['readbacks'][0]['file']).read_bytes());assert helper['phase']=='completed' and not helper.get('failure') and helper['scope']=='actual-healthy-current-file-after-ready-before-confirmation'
assert [r['phase'] for r in helper['observations'] if 'probeValue' in r]==e.PHASES
fresh_region=[r for r in helper['observations'] if r['phase']=='fresh-healthy-target'];ready=[r for r in helper['observations'] if r['phase']=='fresh-workout-ready-visible'];assert len(fresh_region)==len(ready)==1;region.validate(fresh_region[0]);region.validate_readiness(ready[0]);assert helper['observations'].index(ready[0])<helper['observations'].index(fresh_region[0])
commits=[r for r in helper['observations'] if r['phase']=='fresh-committed' and 'message' in r];assert len(commits)==1 and commits[0]['wholeSuccessBeforeAnyTestScroll'] is True;actual_geometry=geometry.validate(commits[0]);assert not any(r['phase']=='fresh-committed' and 'pan' in r for r in helper['observations'])
end=final['finalAudit'];assert end['status'].startswith('PASS') and len(end['samples'])==2
for row in end['samples']:
 assert processes.classify(row['process'],state['appPID'],state['boundaries'][0]['installed']['path'])==end['mode']
 e.success.validate(row['success'],healthy,state['provider'],h,v,state['started']);v.fixed(row['fixed'],h.DATA,h,e.obs)
 assert not row['owned'] and not any(row['caseRoots'].values()) and row['originEvents']==state['boundaries'][7]['originEvents']
 assert json.loads(v.payload(row['nativeState'],h))==state['boundaries'][7]['observation'] and row['installed']==state['boundaries'][0]['installed']
index=load('-all-originals.json');assert index['count']==18 and index['kinds']=={'json':1,'png':17}
f=index['completeManifest'];raw=gzip.decompress((B/f['file']).read_bytes());assert len(raw)==f['bytes'] and h.sha(raw)==f['sha256'];f=index['otherArchive'];raw=gzip.decompress((B/f['file']).read_bytes());assert len(raw)==f['decodedBytes'] and h.sha(raw)==f['decodedSHA256'] and json.loads(raw)['files']=={}
root=Path('/tmp/LumenBatch44Checks/HealthHealthyTargetChangeDataSource244R1All')
for row in index['rows']:
 raw=(root/row['file']).read_bytes();assert len(raw)==row['bytes'] and h.sha(raw)==row['sha256'] and raw==(B/row['retained']).read_bytes()
counts={}
def payloads(x):
 count=0
 if isinstance(x,dict):
  if isinstance(x.get('base64'),str):v.payload(x,h,64*1024*1024);count+=1
  count+=sum(payloads(y) for y in x.values())
 elif isinstance(x,list):count+=sum(payloads(y) for y in x)
 return count
for name,value in [('host',state),('actualR3Final',final)]:counts[name]=payloads(value)
out={'status':'Root strictactual244native1/0/0/native0/driver0/all8/R3checker0/fullhealthy14→workout-only22/privatecopies/receipt/journal/retirement/visiblecompletion/finalBack endpoints passed; individualoriginal/helper reviewseparate','source':'durable-source-r244.json','bindings':708,'nativePID':state['nativePID'],'appPID':state['appPID'],'runID':state['runID'],'nativeCounts':[1,0,0],'nativeExit':0,'driverExit':0,'R3checkerExit':0,'hostBoundaries':8,'nativeRawStates':len(state['nativeStates']),'embeddedPayloadInstances':counts,'originalAttachments':18,'originalPNGs':17,'helperBytes':ret['readbacks'][0]['bytes'],'healthyRegion':fresh_region[0],'workoutReadiness':ready[0],'successGeometry':actual_geometry,'freshCommitProof':state['boundaries'][6]['success']['validation'],'oldClosureSpan':state['boundaries'][4]['endpoints'][1]['monotonic']-state['boundaries'][4]['endpoints'][0]['monotonic'],'freshClosureSpan':state['boundaries'][7]['endpoints'][1]['monotonic']-state['boundaries'][7]['endpoints'][0]['monotonic'],'finalProcessMode':end['mode'],'finalSampleSpan':end['samples'][1]['monotonic']-end['samples'][0]['monotonic'],'scope':'SyntheticData/healthycurrentfile/main-light-standard/afterready-beforeconfirmation only; sampled endpoints notcontinuousabsence/exitcause/globalFD/VOspeech/motion/Release/generalrace/fullgoal acceptance. Original243failure immutable.','checkedAt':time.time()};p=B/'source244-root-native-final-audit-r1.json';assert not p.exists();p.write_text(json.dumps(out,indent=2)+'\n');print(json.dumps({k:out[k] for k in ['status','embeddedPayloadInstances','nativeRawStates','oldClosureSpan','freshClosureSpan','finalProcessMode','finalSampleSpan']}))
