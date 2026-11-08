"""Root strict replay of the complete retained native case and R10 endpoints."""
from pathlib import Path
import json,gzip,base64,hashlib,importlib.util,time
B=Path('Design/native/health-write-order').resolve();prefix='health-legacy-target-change-string-source240r1'
def load(s):return json.loads((B/(prefix+s)).read_bytes())
spec=importlib.util.spec_from_file_location('root239final',B/'target-string-evidence-r2.py');e=importlib.util.module_from_spec(spec);spec.loader.exec_module(e);h=e.h;v=e.v
geometry=e.e.module('root239geometry','target-success-viewport-r1.py');processes=e.e.module('root239process','target-postrun-process-r1.py')
state=load('-host-audit.json');out=load('-outcome.json');final=load('-string-r2-source240r1-outcome.json');assert final['checkerExit']==out['nativeExit']==out['driverExit']==0
assert [out['summary'][k] for k in ['passedTests','failedTests','skippedTests']]==[1,0,0]
inputs=h.verify_inputs('durable-source-r239.json','health-target-change-source239-r1-build.json');assert state['preflight']==inputs and state['hostSourceVerification']==e.verify_host_source('durable-source-r240.json')==final['checkerSourceVerification']
assert len(state['boundaries'])==len(state['messages'])==8 and [r['phase'] for r in state['boundaries']]==e.PHASES
first=state['boundaries'][0]['protected'];old=state['oldSession'];fresh=state['boundaries'][5]['observation']['sessionID'];assert old!=fresh
expected=[[],['open','ready'],['open','ready','acquire'],['open','ready','acquire','acquire'],['open','ready','acquire','acquire','closed'],['open','ready','acquire','acquire','closed','open','ready'],['open','ready','acquire','acquire','closed','open','ready','acquire'],['open','ready','acquire','acquire','closed','open','ready','acquire','closed']]
for i,row in enumerate(state['boundaries']):
 assert row['status']=='PASS';value=e.check_state(row['observation'],state['started'],state['runID'],state['appPID']);assert value['sequence']==e.COUNTS[i] and value['status']==e.STATUSES[i]
 assert state['messages'][i]['value']=={**{k:value[k] for k in ['runID','pid','sessionID','captureID','sequence']},'phase':'host-'+row['phase']}
 assert [r['event'] for r in row['originEvents']]==expected[i]
 assert all(r['sessionID']==old for r in row['originEvents'][:5]) and all(r['sessionID']==fresh for r in row['originEvents'][5:])
 for ordinal,event in enumerate(row['originEvents']):
  if event['event']=='acquire':assert event['domains']==(['meals','workouts'] if ordinal==7 else ['meals'])
 endpoints=row['endpoints'] if i in [4,7] else [row]
 for endpoint in endpoints:
  assert endpoint['process']=={'pid':state['appPID'],'executable':state['boundaries'][0]['installed']['path']}
  if i<6:v.protected(endpoint['protected'],first,h)
  else:e.success.validate(endpoint['success'],first,state['provider'],h,v,state['started'])
  v.fixed(endpoint['fixed'],e.obs.OLD if i<2 else e.obs.NEW,h,e.obs)
  if 'selected' in endpoint:assert endpoint['selected']==state['freshSelection' if i>=5 else 'selection']
 if i==0:v.bootstrap(row['initialBootstrap'],row,h);v.bootstrap_context(row['finalBootstrapContext'],row,h);v.protected(row['postBootstrapProtected'],first,h)
 if i==2:v.persistence(row['preferencePersistence'],h,e.obs)
 if i in [4,7]:
  assert len(endpoints)==2 and endpoints[1]['monotonic']-endpoints[0]['monotonic']>=3 and row['ownerClosureSamples'][-1]['workspaces']=={}
  for endpoint in endpoints:v.cleanup(endpoint['cleanup'],state['selection' if i==4 else 'freshSelection'])
 if i==6:
  def sample_check(sample):
   success=sample['success'];proof=e.success.validate_payloads(success,first,state['provider'],h,v,state['started']);e.retirement.validate_namespace(success['namespace'],first,success['current'],proof,h)
   assert sample['process']==row['process'] and sample['installed']==row['installed'];assert v.payload(sample['heldNative'],h)==v.payload(row['nativeCheckpoint'],h)
   assert sample['selected']==state['freshSelection'] and sample['originEvents']==row['originEvents'];v.fixed(sample['fixed'],e.obs.NEW,h,e.obs)
  e.retirement.validate_wait(row['retirement'],sample_check)
v.all_payloads(state,h,inputs['app'])
for native in state['nativeStates']:assert json.loads(v.payload(native,h))==native['value'];e.check_state(native['value'],state['started'],state['runID'],state['appPID'])
ret=out['retention'];assert not ret['errors'] and ret==load('-retention-state.json') and ret['images']==load('-images.json') and ret['readbacks']==load('-readbacks.json');assert len(ret['images'])==16 and len(ret['readbacks'])==1
for query in ret['queries']:
 assert query['exitCode']==0
 for key in ['stdout','stderr']:
  r=query[key];raw=gzip.decompress((B/r['retained']).read_bytes());assert r['retainedExact'] and len(raw)==r['bytes'] and h.sha(raw)==r['sha256']
r=ret['log'];raw=gzip.decompress((B/r['retained']).read_bytes());assert r['retainedExact'] and len(raw)==r['bytes'] and h.sha(raw)==r['sha256']
helper=json.loads((B/ret['readbacks'][0]['file']).read_bytes());assert helper['phase']=='completed' and not helper.get('failure');assert [r['phase'] for r in helper['observations'] if 'probeValue' in r]==e.PHASES
commits=[r for r in helper['observations'] if r['phase']=='fresh-committed' and 'message' in r];assert len(commits)==1;actual_geometry=geometry.validate(commits[0]);assert not any(r['phase']=='fresh-committed' and 'pan' in r for r in helper['observations'])
end=final['finalAudit'];assert end['status'].startswith('PASS') and len(end['samples'])==2
for row in end['samples']:
 assert processes.classify(row['process'],state['appPID'],state['boundaries'][0]['installed']['path'])==end['mode']
 e.success.validate(row['success'],first,state['provider'],h,v,state['started']);v.fixed(row['fixed'],e.obs.NEW,h,e.obs)
 assert not row['owned'] and not any(row['caseRoots'].values()) and row['originEvents']==state['boundaries'][7]['originEvents']
 assert json.loads(v.payload(row['nativeState'],h))==state['boundaries'][7]['observation'];assert row['installed']==state['boundaries'][0]['installed']
index=load('-all-originals.json');manifest=gzip.decompress((B/index['completeManifest']['file']).read_bytes());assert len(manifest)==index['completeManifest']['bytes'] and h.sha(manifest)==index['completeManifest']['sha256'];raw=gzip.decompress((B/index['otherArchive']['file']).read_bytes());assert len(raw)==index['otherArchive']['decodedBytes'] and h.sha(raw)==index['otherArchive']['decodedSHA256'];others=json.loads(raw)['files']
rawroot=Path('/tmp/LumenBatch44Checks/HealthLegacyTargetChangeStringSource240R1All')
for row in index['rows']:
 raw=(rawroot/row['file']).read_bytes();assert len(raw)==row['bytes'] and h.sha(raw)==row['sha256']
 if row['kind'] in ['png','json','video']:assert (B/row['retained']).read_bytes()==raw
 else:assert v.payload(others[row['file']],h)==raw
counts={}
def payloads(value):
 count=0
 if isinstance(value,dict):
  if isinstance(value.get('base64'),str):v.payload(value,h,64*1024*1024);count+=1
  count+=sum(payloads(x) for x in value.values())
 elif isinstance(value,list):count+=sum(payloads(x) for x in value)
 return count
for name,data in [('nativeHost',state),('finalR10',final)]:counts[name]=payloads(data)
result={'status':'Root strict retained240native1/0/0/0/driver0/all8phases/R10exit0 and fullcurrent26/private/receipt/photos/journal/protected/finalBack endpoints replay passed; original-image/helper design review separately required','caseSource':'durable-source-r239.json','hostSource':'durable-source-r240.json','nativePID':state['nativePID'],'appPID':state['appPID'],'runID':state['runID'],'counts':[1,0,0],'nativeExit':0,'driverExit':0,'R10exit':0,'caseBindings':618,'hostBindings':630,'embeddedPayloadInstances':counts,'hostBoundaries':8,'originalAttachments':index['count'],'kinds':index['kinds'],'helperBytes':ret['readbacks'][0]['bytes'],'successGeometry':actual_geometry,'freshCommitProof':state['boundaries'][6]['success']['validation'],'oldClosureSpan':state['boundaries'][4]['endpoints'][1]['monotonic']-state['boundaries'][4]['endpoints'][0]['monotonic'],'freshClosureSpan':state['boundaries'][7]['endpoints'][1]['monotonic']-state['boundaries'][7]['endpoints'][0]['monotonic'],'finalProcessMode':end['mode'],'finalSampleSpan':end['samples'][1]['monotonic']-end['samples'][0]['monotonic'],'scope':'Sampled synthetic String/main/light/standard only, no continuousabsence/exitcause/globalFD/VOspeech/motion/Release/other timings/fullgoal acceptance','checkedAt':time.time()};target=B/'source240-root-native-final-audit-r1.json';assert not target.exists();target.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({k:result[k] for k in ['status','embeddedPayloadInstances','originalAttachments','kinds','helperBytes','successGeometry','oldClosureSpan','freshClosureSpan','finalProcessMode','finalSampleSpan']},indent=2))
