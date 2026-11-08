"""Read complete retained failed case; never overwrite it or claim native pass."""
import base64,gzip,hashlib,importlib.util,json,time
from pathlib import Path
B=Path(__file__).resolve().parent;prefix='health-legacy-target-change-data-source237r1'
spec=importlib.util.spec_from_file_location('root_failed237',B/'legacy-target-change-evidence-r5.py');e=importlib.util.module_from_spec(spec);spec.loader.exec_module(e)
h=e.h;v=e.v
def load(suffix):return json.loads((B/(prefix+suffix)).read_bytes())
state=load('-driver-observations.json');out=load('-outcome.json');first=state['boundaries'][0]['protected']
inputs=h.verify_inputs('durable-source-r237.json','health-target-change-source237-r1-build.json')
assert state['preflight']==inputs and state['hostSourceVerification']==e.verify_host_source('durable-source-r237.json')
assert state['hostSource']=='durable-source-r237.json' and out['source']=='durable-source-r237.json'
assert out['nativeExit']==65 and out['driverExit']==1
assert [out['summary'][key] for key in ['passedTests','failedTests','skippedTests']]==[0,1,0]
assert [row['phase'] for row in state['boundaries']]==e.PHASES[:7]
assert len(state['messages'])==7
for index,row in enumerate(state['boundaries']):
 assert row['status']=='PASS';value=e.check_state(row['observation'],state['started'],state['runID'],state['appPID'])
 assert value['sequence']==e.COUNTS[index] and value['status']==e.STATUSES[index]
 assert state['messages'][index]['value']=={**{key:value[key] for key in ['runID','pid','sessionID','captureID','sequence']},'phase':'host-'+row['phase']}
 expected=[[],['open','ready'],['open','ready','acquire'],['open','ready','acquire','acquire'],['open','ready','acquire','acquire','closed'],['open','ready','acquire','acquire','closed','open','ready'],['open','ready','acquire','acquire','closed','open','ready','acquire']][index]
 assert [event['event'] for event in row['originEvents']]==expected
 assert all(event['sessionID']==state['oldSession'] for event in row['originEvents'][:5])
 for ordinal,event in enumerate(row['originEvents']):
  if event['event']=='acquire':assert event['domains']==(['meals','workouts'] if ordinal==7 else ['meals'])
 if index>=5:assert all(event['sessionID']==state['boundaries'][5]['observation']['sessionID'] for event in row['originEvents'][5:])
 endpoints=row['endpoints'] if index==4 else [row]
 for endpoint in endpoints:
  assert endpoint['process']=={'pid':state['appPID'],'executable':state['boundaries'][0]['installed']['path']}
  if index<6:v.protected(endpoint['protected'],first,h)
  else:e.success.validate(endpoint['success'],first,state['provider'],h,v,state['started'])
  v.fixed(endpoint['fixed'],h.DATA if index<2 else e.obs.NEW,h,e.obs)
  if 'selected' in endpoint:assert endpoint['selected']==state['freshSelection' if index>=5 else 'selection']
 if index==0:
  v.bootstrap(row['initialBootstrap'],row,h);v.bootstrap_context(row['finalBootstrapContext'],row,h);v.protected(row['postBootstrapProtected'],first,h)
 if index==2:v.persistence(row['preferencePersistence'],h,e.obs)
 if index==4:
  assert len(endpoints)==2 and endpoints[1]['monotonic']-endpoints[0]['monotonic']>=3
  assert row['ownerClosureSamples'][-1]['workspaces']=={}
  for endpoint in endpoints:v.cleanup(endpoint['cleanup'],state['selection'])
 if index==6:
  def validate_sample(sample):
   success=sample['success'];assert success['group']==str(Path(row['nativeCheckpoint']['file']).parent)
   proof=e.success.validate_payloads(success,first,state['provider'],h,v,state['started'])
   e.retirement.validate_namespace(success['namespace'],first,success['current'],proof,h)
   assert sample['process']==row['process'] and sample['installed']==row['installed']
   assert v.payload(sample['heldNative'],h)==v.payload(row['nativeCheckpoint'],h)
   assert sample['selected']==state['freshSelection'] and sample['originEvents']==row['originEvents']
   v.fixed(sample['fixed'],e.obs.NEW,h,e.obs)
  e.retirement.validate_wait(row['retirement'],validate_sample)
  assert all(row[key]==row['retirement']['samples'][-1][key] for key in ['success','process','installed','heldNative','fixed','selected'])
v.all_payloads(state,h,inputs['app'])
for row in state['nativeStates']:
 assert json.loads(v.payload(row,h,128*1024))==row['value'];e.check_state(row['value'],state['started'],state['runID'],state['appPID'])
ret=out['retention'];assert not ret['errors'];assert ret==load('-retention-state.json')
assert ret['images']==load('-images.json') and ret['readbacks']==load('-readbacks.json') and ret['summary']==load('-summary.json')
for query in ret['queries']:
 assert query['exitCode']==0
 for key in ['stdout','stderr']:
  fact=query[key];raw=gzip.decompress((B/fact['retained']).read_bytes());assert fact['retainedExact'] and len(raw)==fact['bytes'] and h.sha(raw)==fact['sha256']
fact=ret['log'];raw=gzip.decompress((B/fact['retained']).read_bytes());assert fact['retainedExact'] and len(raw)==fact['bytes'] and h.sha(raw)==fact['sha256']
assert len(ret['images'])==14 and len(ret['readbacks'])==1
for fact in ret['images']+ret['readbacks']:
 raw=(B/fact['file']).read_bytes();assert len(raw)==fact['bytes'] and h.sha(raw)==fact['sha256']
helper=json.loads((B/ret['readbacks'][0]['file']).read_bytes());assert helper['phase']=='fresh-committed' and helper['failure']=='Whole completion message was not automatically visible before test scrolling'
assert [row['phase'] for row in helper['observations'] if 'probeValue' in row]==e.PHASES[:6]
assert state['nativeStates'][-1]['value']['status']=='fresh-recovery-committed'
index=load('-all-originals.json');assert index['count']==160 and index['kinds']=={'png':14,'json':1,'text':18,'binary-plist':126,'video':1}
archive=gzip.decompress((B/index['otherArchive']['file']).read_bytes());assert len(archive)==index['otherArchive']['decodedBytes'] and h.sha(archive)==index['otherArchive']['decodedSHA256']
other=json.loads(archive)['files'];assert len(other)==144
for name,row in other.items():assert v.payload(row,h)==(Path('/tmp/LumenBatch44Checks/HealthLegacyTargetChangeDataSource237R1All')/name).read_bytes()
manifest=gzip.decompress((B/index['completeManifest']['file']).read_bytes());assert h.sha(manifest)==index['completeManifest']['sha256']
for fact in index['rows']:
 raw=(Path('/tmp/LumenBatch44Checks/HealthLegacyTargetChangeDataSource237R1All')/fact['file']).read_bytes()
 assert len(raw)==fact['bytes'] and h.sha(raw)==fact['sha256']
 if fact['kind'] in ['png','json','video']:assert (B/fact['retained']).read_bytes()==raw
video=next(r for r in index['rows'] if r['kind']=='video')
retirement=state['boundaries'][6]['retirement'];proof=state['boundaries'][6]['success']['validation']
payload_count=[0]
def count_payloads(value):
 if isinstance(value,dict):
  if isinstance(value.get('base64'),str):v.payload(value,h,64*1024*1024);payload_count[0]+=1
  for child in value.values():count_payloads(child)
 elif isinstance(value,list):
  for child in value:count_payloads(child)
count_payloads(state)
result={'status':'Retained failed native0/1/0/65/driver1 fully read; seven host boundaries and fresh backend commit facts validated, no UI/final-close acceptance','caseSource':'durable-source-r237.json','hostSource':'durable-source-r237.json','actualNativePID':state['nativePID'],'appPID':state['appPID'],'runID':state['runID'],'nativeCounts':[0,1,0],'nativeExit':65,'driverExit':1,'retainedPayloadInstances':payload_count[0],'hostBoundaries':7,'freshBackendCommitProof':proof,'retirementSamples':len(retirement['samples']),'retirementCompletedElapsed':[sample['completedElapsed'] for sample in retirement['samples']],'retirementAcceptedElapsed':retirement['acceptedElapsed'],'oldOwnerClosureSpan':state['boundaries'][4]['endpoints'][1]['monotonic']-state['boundaries'][4]['endpoints'][0]['monotonic'],'completeAttachments':160,'originalPNGs':14,'nativeHelperBytes':ret['readbacks'][0]['bytes'],'videoBytes':video['bytes'],'videoPlayed':False,'actualFailure':'Actual success label EXISTS before test scrolling but native whole-visible predicate failed. Original failure screenshot shows whole readable message; retained AX label frame y132,height52 and nav frame y78,height54 prove its arbitrary nav.maxY+12 rectangle excludes the first12pt of the label. This necessary failing geometry explains the bounds gate; it does not retroactively pass original test or prove all other predicate branches. No final Back/closure/fullR9 acceptance.','scope':'Partial runtime evidence only; not a passed case, no final workspace closure/continuous absence/full UI/relaunch/Release/fullgoal acceptance.','checkedAt':time.time()}
target=B/'source237-root-native-failure-audit-r1.json';assert not target.exists();target.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
