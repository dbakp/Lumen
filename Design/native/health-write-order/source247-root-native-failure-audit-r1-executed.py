"""Strict replay of actual failed confirmation observation; no native acceptance."""
from pathlib import Path
import base64,gzip,hashlib,importlib.util,json,time
B=Path(__file__).resolve().parent;P='health-legacy-confirmation-data-source247r1';load=lambda n:json.loads((B/n).read_bytes())
spec=importlib.util.spec_from_file_location('failed_confirmation',B/'confirmation-target-evidence-r1.py');e=importlib.util.module_from_spec(spec);spec.loader.exec_module(e);h=e.h;v=e.v
s=load(P+'-driver-observations.json');o=load(P+'-outcome.json');checker=load(P+'-confirmation-r2-postrunr1-outcome.json')
assert o['nativeExit']==65 and o['driverExit']==checker['checkerExit']==1
assert [o['summary'][k] for k in ['passedTests','failedTests','skippedTests']]==[0,1,0] and 'finalAudit' not in checker
inputs=h.verify_inputs('durable-source-r247.json','health-target-change-source247-r1-build.json');assert s['preflight']==inputs and s['hostSourceVerification']==e.verify_host_source('durable-source-r247.json')==checker['checkerSourceVerification']
assert len(s['boundaries'])==len(s['messages'])==2
first=s['boundaries'][0]['protected'];assert len(first['current']['files'])==len(first['prior']['files'])==13
for i,r in enumerate(s['boundaries']):
 assert r['status']=='PASS' and r['phase']==e.PHASES[i]
 value=e.check_state(r['observation'],s['started'],s['runID'],s['appPID']);assert value['sequence']==e.COUNTS[i] and value['status']==e.STATUSES[i]
 assert s['messages'][i]['value']==dict({k:value[k] for k in ['runID','pid','sessionID','captureID','sequence']},phase='host-'+r['phase'])
 v.protected(r['protected'],first,h);v.fixed(r['fixed'],h.DATA,h,e.obs)
 assert [x['event'] for x in r['originEvents']]==[[],['open','ready']][i]
v.bootstrap(s['boundaries'][0]['initialBootstrap'],s['boundaries'][0],h);v.bootstrap_context(s['boundaries'][0]['finalBootstrapContext'],s['boundaries'][0],h)
v.selection(s['selection'],s['provider'],s['appPID'],h);v.all_payloads(s,h,inputs['app'])
for r in s['nativeStates']:assert json.loads(v.payload(r,h))==r['value'];e.check_state(r['value'],s['started'],s['runID'],s['appPID'])
assert s['nativeStates'][-1]['value']['sequence']==3 and s['nativeStates'][-1]['value']['knownKeyWritten'] is False
window=s['confirmationWindow'];assert window['gateAcquisition']['status']=='PARSED' and not any(k in window for k in ['marker','ackIntended','acknowledged','ackBytes'])
gate=json.loads(v.payload(window['gate'],h));assert gate['runID']==s['runID'] and int(gate['pid'])==s['appPID'] and gate['domains']==gate['legacyDomains']=='meals' and gate['omitPhotos']=='false'
assert not Path(window['gateFile']).with_name(Path(window['gateFile']).stem+'-ack.json').exists()
ret=o['retention'];assert not ret['errors'] and ret==load(P+'-retention-state.json') and ret['images']==load(P+'-images.json') and ret['readbacks']==load(P+'-readbacks.json') and ret['summary']==load(P+'-summary.json')
for query in ret['queries']:
 assert query['exitCode']==0
 for stream in ['stdout','stderr']:
  r=query[stream];raw=gzip.decompress((B/r['retained']).read_bytes());assert r['retainedExact'] and len(raw)==r['bytes'] and h.sha(raw)==r['sha256']
r=ret['log'];raw=gzip.decompress((B/r['retained']).read_bytes());assert len(raw)==r['bytes'] and h.sha(raw)==r['sha256']
assert len(ret['images'])==5 and len(ret['readbacks'])==1
helper=load(ret['readbacks'][0]['file']);assert helper['phase']=='confirmation-gate' and helper['failure']=='Actual Recover gate value missing' and helper['scope']=='actual-legacy-target-change-during-confirmation'
assert [x['phase'] for x in helper['observations'] if 'probeValue' in x]==['before-selection','ready']
index=load(P+'-all-originals.json');assert index['count']==65 and index['kinds']=={'png':5,'json':1,'binary-plist':52,'text':6,'video':1}
r=index['otherArchive'];raw=gzip.decompress((B/r['file']).read_bytes());assert len(raw)==r['decodedBytes'] and h.sha(raw)==r['decodedSHA256'];others=json.loads(raw)['files'];assert len(others)==58
r=index['completeManifest'];raw=gzip.decompress((B/r['file']).read_bytes());assert len(raw)==r['bytes'] and h.sha(raw)==r['sha256']
root=Path('/tmp/LumenBatch44Checks/HealthLegacyConfirmationDataSource247R1All')
for r in index['rows']:
 raw=(root/r['file']).read_bytes();assert len(raw)==r['bytes'] and h.sha(raw)==r['sha256']
 if r['kind'] in ['png','json','video']:assert raw==(B/r['retained']).read_bytes()
 else:assert v.payload(others[r['file']],h)==raw
payloads=[0]
def check(x):
 if isinstance(x,dict):
  if isinstance(x.get('base64'),str):v.payload(x,h,64*1024*1024);payloads[0]+=1
  for y in x.values():check(y)
 elif isinstance(x,list):
  for y in x:check(y)
check(s)
diagnostic=load('source247-post-failure-readonly-diagnostic-r1.json');assert len(diagnostic['samples'])==2
for r in diagnostic['samples']:
 assert r['process']['mode']=='absent';v.protected(r['protected'],first,h);v.fixed(r['fixed'],h.DATA,h,e.obs)
 assert r['nativeValue']==s['nativeStates'][-1]['value'] and len(r['ownedWorkspaces'])==2 and all(r['caseRoots'].values())
 assert [x['event'] for x in r['originEvents']]==['open','ready']
video=next(x for x in index['rows'] if x['kind']=='video')
report={'status':'FAILED CASE REPLAYED EXACT; no timing/recovery/closure acceptance','sourceInputs':inputs['inputs'],'nativeCounts':[0,1,0],'nativeExit':65,'driverExit':1,'checkerExit':1,'passedHostBoundaries':2,'hostPayloadInstances':payloads[0],'allOriginals':65,'originalPNGs':5,'fullHelperBytes':ret['readbacks'][0]['bytes'],'videoBytes':video['bytes'],'videoSHA256':video['sha256'],'videoInspection':'Full bytes/hash retained unplayed','finding':'Expected armed JSON on actual Recover action not observed in10s; app gate raw parsed, no UI marker/ack/write/Recover. Actual Recover.value not retained, exact transport/propagation cause unknown. No universal API diagnosis.','laterSamples':'Two absent-app endpoints preserve13current/prior13/rawmetadata/bothknownData42/source/provider/installed/native3; two held workspaces remain. No Back, lifecycle closure, continuousabsence or exitcause credit.','scope':'Current765archive/currentpair/full actual failure/all65rawcanonical payloads verified. Separate latent missing e.obs.OLD was not reached in this actual failure. Full independent156/root/exact before successor edits/reset/cleanup.','checkedAt':time.time()};(B/'source247-root-native-failure-audit-r1.json').write_text(json.dumps(report,indent=2)+'\n');print(report['status'],payloads[0],'payload instances')
