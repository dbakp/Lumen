"""Strict retained failed-case replay; original predicate remains rejected."""
from pathlib import Path
import json,gzip,base64,hashlib,importlib.util,time
B=Path(__file__).resolve().parent;prefix='health-healthy-target-change-data-source242r1'
def load(s):return json.loads((B/(prefix+s)).read_bytes())
spec=importlib.util.spec_from_file_location('failure242root',B/'healthy-target-evidence-r2.py');e=importlib.util.module_from_spec(spec);spec.loader.exec_module(e);h=e.h;v=e.v
state=load('-driver-observations.json');out=load('-outcome.json');first=state['boundaries'][0]['protected'];inputs=h.verify_inputs('durable-source-r242.json','health-target-change-source242-r1-build.json');assert state['preflight']==inputs and state['hostSourceVerification']==e.verify_host_source('durable-source-r242.json')
assert out['nativeExit']==65 and out['driverExit']==1 and [out['summary'][k] for k in ['passedTests','failedTests','skippedTests']]==[0,1,0]
assert [r['phase'] for r in state['boundaries']]==e.PHASES[:3] and len(state['messages'])==2
for i,row in enumerate(state['boundaries'][:2]):
 assert row['status']=='PASS';value=e.check_state(row['observation'],state['started'],state['runID'],state['appPID']);assert value['sequence']==e.COUNTS[i]
 assert state['messages'][i]['value']=={**{k:value[k] for k in ['runID','pid','sessionID','captureID','sequence']},'phase':'host-'+row['phase']}
 v.protected(row['protected'],first,h);v.fixed(row['fixed'],h.DATA,h,e.obs)
 if i==0:v.bootstrap(row['initialBootstrap'],row,h);v.bootstrap_context(row['finalBootstrapContext'],row,h);v.protected(row['postBootstrapProtected'],first,h)
 else:v.selection(row['selected'],state['provider'],state['appPID'],h)
v.all_payloads(state,h,inputs['app'])
for n in state['nativeStates']:
 assert json.loads(v.payload(n,h))==n['value'];e.check_state(n['value'],state['started'],state['runID'],state['appPID'])
last=state['nativeStates'][-1]['value'];assert last['status']=='mutated' and last['sequence']==7 and not last['failed'] and last['knownFileWritten']
assert last['events'][4]['oldTokenVerified'] is True
for i in [3,4,5,6]:e.obs.native_fixed(last['events'][i]['fixed'],h.DATA,h)
row=state['boundaries'][2];assert row['status']=='FAILED' and 'healthy-target-protected-r1.py' in out['hostError'] and "['st_ino','st_dev','st_mode','st_nlink']" in out['hostError']
observed=row['protected'];before=first['current'];current=observed['current']
for name in ['current','prior']:v.tree(observed[name],h)
for key in ['rootIdentity','files','metadata']:assert observed['prior'][key]==first['prior'][key]
assert observed['provider']==first['provider'] and observed['residuals']==first['residuals'] and not any(observed['residuals'].values())
assert len(before['files'])==13 and len(current['files'])==14 and set(current['files'])==set(before['files'])|{'meals.json'}
for name,wanted in before['files'].items():assert current['files'][name]==wanted and current['metadata']['files'][name]==before['metadata']['files'][name]
assert current['metadata']['directories']==before['metadata']['directories']
for key in ['st_ino','st_dev','st_mode']:assert current['rootIdentity'][key]==before['rootIdentity'][key]
assert current['rootIdentity']['st_nlink']==before['rootIdentity']['st_nlink']+1
leaf=last['events'][6]['mealFile'];e.healthy.native_leaf(leaf,Path(leaf['path']).parent,True,h)
assert v.payload(current['files']['meals.json'],h)==e.healthy.HEALTHY and current['metadata']['files']['meals.json']['identity']==leaf['identity']
try:e.healthy.validate(observed,first,leaf,h,v)
except AssertionError:rejected=True
else:rejected=False
assert rejected
ret=out['retention'];assert not ret['errors'] and ret==load('-retention-state.json') and ret['images']==load('-images.json') and ret['readbacks']==load('-readbacks.json') and ret['summary']==load('-summary.json')
for query in ret['queries']:
 assert query['exitCode']==0
 for key in ['stdout','stderr']:
  fact=query[key];raw=gzip.decompress((B/fact['retained']).read_bytes());assert fact['retainedExact'] and len(raw)==fact['bytes'] and h.sha(raw)==fact['sha256']
fact=ret['log'];raw=gzip.decompress((B/fact['retained']).read_bytes());assert len(raw)==fact['bytes'] and h.sha(raw)==fact['sha256']
helper=json.loads((B/ret['readbacks'][0]['file']).read_bytes());assert helper['phase']=='target-changed' and helper['failure']=='Actual host audit acknowledgement missing' and [x['phase'] for x in helper['observations'] if 'probeValue' in x]==e.PHASES[:2]
assert helper['scope']=='actual-healthy-current-file-after-ready-before-confirmation'
index=load('-all-originals.json');assert index['count']==197 and index['kinds']=={'png':5,'json':1,'text':52,'binary-plist':138,'video':1}
raw=gzip.decompress((B/index['otherArchive']['file']).read_bytes());assert len(raw)==index['otherArchive']['decodedBytes'] and h.sha(raw)==index['otherArchive']['decodedSHA256'];other=json.loads(raw)['files'];assert len(other)==190
manifest=gzip.decompress((B/index['completeManifest']['file']).read_bytes());assert len(manifest)==index['completeManifest']['bytes'] and h.sha(manifest)==index['completeManifest']['sha256']
root=Path('/tmp/LumenBatch44Checks/HealthHealthyTargetChangeDataSource242R1All')
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
final=load('-healthy-r2-source242r1-outcome.json');assert final['checkerExit']==1 and 'finalAudit' not in final
video=next(x for x in index['rows'] if x['kind']=='video')
r={'status':'Root retainedFAILED242native0/1/0/native65/driver1/checker1; actualknownhealthyfile14 and exactold13/prior13, rootnlink13to14 observed; originalpredicate stillrejected','source':'durable-source-r242.json','sourceBindings':674,'nativePID':state['nativePID'],'appPID':state['appPID'],'runID':state['runID'],'passedHostBoundaries':2,'failedHostBoundary':'target-changed','latestNativeSequence':7,'actualFailure':'Hostrequiresrootst_nlinkunchanged althoughactualnativeadditionofonehealthymealfile changesrootnlink13to14, withsameinode/device/mode, old13rawandmetadata/directories/prior/providerexact. Nativefiniteackwaitthenfails; noactualRecover/stalerejection/freshreview/commit/Back/closure occurred.','beforeRoot':before['rootIdentity'],'afterRoot':current['rootIdentity'],'nativeCounts':[0,1,0],'nativeExit':65,'driverExit':1,'checkerExit':1,'embeddedPayloadInstances':count[0],'completeAttachments':197,'originalPNGs':5,'fullNativeHelperBytes':3125,'video':{'file':video['retained'],'bytes':video['bytes'],'sha256':video['sha256'],'played':False},'scope':'ContemporaneousfournativefixedData42facts bound; failedhostboundaryneverreacheditsfixed/selectedchecks. Laterreadonlyendpointrecordrequiredforlateprotectedstate. Nohealthyfullruntime/Release/continuousabsence/exitcause/VOspeech/motion/fullgoalacceptance.','checkedAt':time.time()};target=B/'source242-root-native-failure-audit-r1.json';assert not target.exists();target.write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r,indent=2))
