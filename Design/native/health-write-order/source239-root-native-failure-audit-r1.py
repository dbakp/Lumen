"""Strict full retained failure replay, never changes rejected native evidence."""
from pathlib import Path
import json,gzip,base64,hashlib,importlib.util,time
B=Path(__file__).resolve().parent;prefix='health-legacy-target-change-string-source239r1'
def load(s):return json.loads((B/(prefix+s)).read_bytes())
spec=importlib.util.spec_from_file_location('failure239root',B/'target-string-evidence-r1.py');e=importlib.util.module_from_spec(spec);spec.loader.exec_module(e);h=e.h;v=e.v
state=load('-driver-observations.json');out=load('-outcome.json');first=state['boundaries'][0]['protected'];inputs=h.verify_inputs('durable-source-r239.json','health-target-change-source239-r1-build.json');assert state['preflight']==inputs and state['hostSourceVerification']==e.verify_host_source('durable-source-r239.json')
assert out['nativeExit']==65 and out['driverExit']==1 and [out['summary'][k] for k in ['passedTests','failedTests','skippedTests']]==[0,1,0]
assert [r['phase'] for r in state['boundaries']]==e.PHASES[:2] and len(state['messages'])==2
for i,row in enumerate(state['boundaries']):
 assert row['status']=='PASS';value=e.check_state(row['observation'],state['started'],state['runID'],state['appPID']);assert value['sequence']==e.COUNTS[i]
 assert state['messages'][i]['value']=={**{k:value[k] for k in ['runID','pid','sessionID','captureID','sequence']},'phase':'host-'+row['phase']}
 v.protected(row['protected'],first,h);v.fixed(row['fixed'],e.obs.OLD,h,e.obs)
 if i==0:v.bootstrap(row['initialBootstrap'],row,h);v.bootstrap_context(row['finalBootstrapContext'],row,h);v.protected(row['postBootstrapProtected'],first,h)
 else:v.selection(row['selected'],state['provider'],state['appPID'],h)
v.all_payloads(state,h,inputs['app']);last=state['nativeStates'][-1]['value'];assert last['status']=='mutated' and last['sequence']==7 and last['failed'] is False and last['originKind']=='string'
assert [x['event'] for x in last['events']]==e.EVENTS[:7] and last['events'][4]['oldTokenVerified'] is True
# Reproduce the original type rejection, then independently bind all bytes and units.
try:e.check_state(last,state['started'],state['runID'],state['appPID'])
except AssertionError:rejected=True
else:rejected=False
assert rejected and 'target-string-observation-r1.py' in out['hostError'] and "value['type'] in" in out['hostError']
observed_types=set()
for i in [3,4,5,6]:
 for key in e.obs.KEYS:
  wanted=e.obs.NEW if i>=5 and key==e.obs.KEYS[0] else e.obs.OLD
  for fact in last['events'][i]['fixed'][key].values():
   assert fact['present'] is True and fact['bytes']==len(wanted) and fact['utf16Units']*2==len(wanted) and fact['sha256']==h.sha(wanted) and base64.b64decode(fact['payload'],validate=True)==wanted
   observed_types.add(fact['type'])
assert observed_types=={'__NSCFString','Swift.__SharedStringStorage'}
ret=out['retention'];assert not ret['errors'] and ret==load('-retention-state.json') and ret['images']==load('-images.json') and ret['readbacks']==load('-readbacks.json') and ret['summary']==load('-summary.json')
for query in ret['queries']:
 assert query['exitCode']==0
 for k in ['stdout','stderr']:
  fact=query[k];raw=gzip.decompress((B/fact['retained']).read_bytes());assert fact['retainedExact'] and len(raw)==fact['bytes'] and h.sha(raw)==fact['sha256']
fact=ret['log'];raw=gzip.decompress((B/fact['retained']).read_bytes());assert len(raw)==fact['bytes'] and h.sha(raw)==fact['sha256']
helper=json.loads((B/ret['readbacks'][0]['file']).read_bytes());assert helper['phase']=='target-changed' and helper['failure']=='Actual host audit acknowledgement missing' and [x['phase'] for x in helper['observations'] if 'probeValue' in x]==e.PHASES[:2]
index=load('-all-originals.json');assert index['count']==196 and index['kinds']=={'png':5,'json':1,'text':51,'binary-plist':138,'video':1}
raw=gzip.decompress((B/index['otherArchive']['file']).read_bytes());assert len(raw)==index['otherArchive']['decodedBytes'] and h.sha(raw)==index['otherArchive']['decodedSHA256'];other=json.loads(raw)['files'];assert len(other)==189
manifest=gzip.decompress((B/index['completeManifest']['file']).read_bytes());assert len(manifest)==index['completeManifest']['bytes'] and h.sha(manifest)==index['completeManifest']['sha256']
root=Path('/tmp/LumenBatch44Checks/HealthLegacyTargetChangeStringSource239R1All')
for row in index['rows']:
 raw=(root/row['file']).read_bytes();assert len(raw)==row['bytes'] and h.sha(raw)==row['sha256']
 if row['kind'] in ['png','json','video']:assert raw==(B/row['retained']).read_bytes()
 else:assert v.payload(other[row['file']],h)==raw
count=[0]
def all_raw(x):
 if isinstance(x,dict):
  if isinstance(x.get('base64'),str):v.payload(x,h,64*1024*1024);count[0]+=1
  for val in x.values():all_raw(val)
 elif isinstance(x,list):
  for val in x:all_raw(val)
all_raw(state)
final=load('-string-r1-source239r1-outcome.json');assert final['checkerExit']==1 and 'finalAudit' not in final
video=next(x for x in index['rows'] if x['kind']=='video')
r={'status':'Root fully retained FAILED239native0/1/0/native65/driver1/checker1; exactoriginalString guard and actualwrite facts bound, no recovery/UIclosure acceptance','source':'durable-source-r239.json','sourceBindings':618,'nativePID':state['nativePID'],'appPID':state['appPID'],'runID':state['runID'],'passedHostBoundaries':2,'latestNativeSequence':7,'actualFailure':'Host native_fixed runtime-class whitelist rejects Swift.__SharedStringStorage despite exactnew66B UTF16LE/digest/unit and originalworkout70B. Native finite ackwait then fails. No actual Recover confirmation/stale error/fresh commit/Back/closure occurred.','observedRuntimeTypes':sorted(observed_types),'nativeCounts':[0,1,0],'nativeExit':65,'driverExit':1,'checkerExit':1,'embeddedPayloadInstances':count[0],'completeAttachments':196,'originalPNGs':5,'fullNativeHelperBytes':2858,'video':{'file':video['retained'],'bytes':video['bytes'],'sha256':video['sha256'],'played':False},'scope':'Original failedschema remains rejected. Byteagreement and first2protected checkpoints do not retroactively pass the failedcase or prove lateprotectedstate; separate laterreadonly record required. NoStringfullruntime/Release/continuousabsence/exitcause/VOspeech/motion/fullgoal acceptance.','checkedAt':time.time()};target=B/'source239-root-native-failure-audit-r1.json';assert not target.exists();target.write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r,indent=2))
