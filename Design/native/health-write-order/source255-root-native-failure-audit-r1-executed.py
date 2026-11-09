"""Strict failedcase replay/original byte verification before successor edits."""
from pathlib import Path
import base64,gzip,hashlib,importlib.util,json,time
B=Path(__file__).resolve().parent;P='health-confirmation-notnow-data-source255r1';load=lambda n:json.loads((B/n).read_bytes())
def module(name,file):
 spec=importlib.util.spec_from_file_location(name,B/file);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
e=module('failed_lifecycle_evidence','confirmation-lifecycle-evidence-r1.py');h=e.h;v=e.v;protocol=module('failed_lifecycle_protocol','confirmation-lifecycle-protocol-r1.py');geometry=module('failed_lifecycle_geometry','confirmation-window-evidence-r3.py')
s=load(P+'-driver-observations.json');out=load(P+'-outcome.json');checker=load(P+'-lifecycle-r2-source255r1-outcome.json');query=load(P+'-mandatory-checker-query.json')
assert out['nativeExit']==65 and out['driverExit']==checker['checkerExit']==query['exit']==1
assert [out['summary'][k] for k in ['passedTests','failedTests','skippedTests']]==[0,1,0] and 'finalAudit' not in checker
inputs=h.verify_inputs('durable-source-r253.json','health-target-change-source255-r1-build.json');assert s['preflight']==inputs and s['hostSourceVerification']==e.verify_host_source(s['hostSource'])==checker['checkerSourceVerification']
assert len(s['boundaries'])==len(s['messages'])==2
first=s['boundaries'][0]['protected'];assert len(first['current']['files'])==len(first['prior']['files'])==13
for index,row in enumerate(s['boundaries']):
 assert row['status']=='PASS' and row['phase']==e.PHASES[index]
 value=e.check_state(row['observation'],s['started'],s['runID'],s['appPID']);assert value['sequence']==e.COUNTS[index]
 assert s['messages'][index]['value']==dict({k:value[k] for k in ['runID','pid','sessionID','captureID','sequence']},phase='host-'+row['phase'])
 v.protected(row['protected'],first,h);v.fixed(row['fixed'],h.DATA,h,e.obs);assert [x['event'] for x in row['originEvents']]==[[],['open','ready']][index]
v.bootstrap(s['boundaries'][0]['initialBootstrap'],s['boundaries'][0],h);v.bootstrap_context(s['boundaries'][0]['finalBootstrapContext'],s['boundaries'][0],h)
v.selection(s['selection'],s['provider'],s['appPID'],h);v.all_payloads(s,h,inputs['app'])
for row in s['nativeStates']:
 assert json.loads(v.payload(row,h))==row['value'];e.check_state(row['value'],s['started'],s['runID'],s['appPID'])
window=s['confirmationWindow'];assert window['acknowledged'] is True and all(k in window for k in ['ackIntended','ackBytes','dismissed']) and all(k in window for k in ['checked','check']) and not any(k in window for k in ['protectedAfterCheck','originAfterCheck'])
assert len(window['relays'])==2 and [r['value']['phase'] for r in window['relays']]==['armed','late-ack']
def latest(key):
 versions=window[key]['versions'];assert versions
 for value in versions:v.payload(value,h,16384)
 return json.loads(v.payload(versions[-1],h,16384))
gate=latest('gate');protocol.binding(gate);geometry.validate_binding(gate,s['boundaries'][1]['observation'])
trace=latest('trace');protocol.trace(trace,gate,s['started'],True);assert len(trace['checks'])==1
marker=latest('presented');protocol.marker(marker,'presented',window['relays'][0]['value'],s['started'],time.time(),geometry)
dismissed=latest('dismissed');protocol.marker(dismissed,'dismissed',window['relays'][0]['value'],s['started'],time.time(),geometry)
assert marker['at']<=dismissed['touchAt']<=trace['events'][2]['at']<=dismissed['tapReturnedAt']<=dismissed['at']
assert max(trace['events'][-1]['at'],dismissed['at'])<=window['ackAt']<=window['ackPublishedObservedAt']
ackraw=v.payload(window['ackBytes'],h,4096);assert window['ackIntended']['raw']==window['ackBytes']
assert json.loads(ackraw)=={**{k:gate[k] for k in ['runID','pid','sessionID','captureID','nonce']},'phase':'ui-observed'}
before=window['protectedBeforeLateAck'];v.protected(before['protected'],first,h);v.fixed(before['fixed'],h.DATA,h,e.obs);assert before['selected']==s['selection'] and before['installed']==s['boundaries'][0]['installed']
assert window['originBeforeLateAck']==s['boundaries'][1]['originEvents']
assert window['relays'][1]['value']==dict(window['relays'][0]['value'],phase='late-ack',targetPhase='host-late-ack',ackSHA256=h.sha(ackraw))
assert window['ackPublishedObservedAt']<=window['relays'][1]['publicationStartedAt']

checked=latest('checked');protocol.marker(checked,'checked',window['relays'][0]['value'],s['started'],time.time(),geometry)
observation=latest('check');nativecheck=protocol.check(observation,trace,ackraw,window['ackPublishedObservedAt'],checked['touchAt'],checked['tapReturnedAt'],e)
assert isinstance(window['checked'],dict) and window['checked']['versions'] and 'hostCheckCompleted' not in window
# Exact old guard, evaluated on the actual retained marker dictionary.
import ast,copy
host=ast.parse((B/'confirmation-lifecycle-driver-r2.py').read_bytes());function=next(n for n in host.body if isinstance(n,ast.FunctionDef) and n.name=='confirmation_gate');guard=next(n for n in function.body if isinstance(n,ast.If) and ast.unparse(n.test)=="window.get('checked')")
probe=ast.FunctionDef(name='probe',args=ast.arguments(posonlyargs=[],args=[ast.arg(arg='window')],kwonlyargs=[],kw_defaults=[],defaults=[]),body=[copy.deepcopy(guard),ast.Return(value=ast.Constant(value='after-guard'))],decorator_list=[]);env={};exec(compile(ast.fix_missing_locations(ast.Module(body=[probe],type_ignores=[])),'actual-old-checked-guard','exec'),env);assert env['probe'](copy.deepcopy(window)) is None
ret=out['retention'];assert not ret['errors'] and ret==load(P+'-retention-state.json') and ret['images']==load(P+'-images.json') and ret['readbacks']==load(P+'-readbacks.json') and ret['summary']==load(P+'-summary.json')
assert len(ret['images'])==9 and len(ret['readbacks'])==1
for q in ret['queries']:
 assert q['exitCode']==0
 for key in ['stdout','stderr']:
  f=q[key];raw=gzip.decompress((B/f['retained']).read_bytes());assert f['retainedExact'] and len(raw)==f['bytes'] and h.sha(raw)==f['sha256']
f=ret['log'];raw=gzip.decompress((B/f['retained']).read_bytes());assert len(raw)==f['bytes'] and h.sha(raw)==f['sha256'];text=raw.decode();assert 'Tap "Not now" Button' in text and 'Tap "checkConfirmationLifecycle" Button' in text and 'Tap "Recover" Button' not in text
helper=load(ret['readbacks'][0]['file']);assert helper['phase']=='relay-checked' and helper['failure']=='Missing bounded lifecycle relay'
choices=[r for r in helper['observations'] if r.get('phase')=='not-now-choice'];assert [r['value'] for r in choices]==['1','0','0'] and all(r['enabled'] is True for r in choices)
acquired=[r for r in helper['observations'] if r.get('phase')=='check-acquisition-before-touch'];assert len(acquired)==1
f=acquired[0];assert f['queryCount']==1 and f['identifier']=='checkConfirmationLifecycle' and all(f[k] is True for k in ['exists','enabled','hittable','finiteFrame','positiveWholeFrame','roleIsButton','navigationStillPresent','ready']);assert f['frame']['width']==370 and f['frame']['height']==52
assert len([r for r in helper['observations'] if r.get('phase')=='check-reveal'])==2
markers=[r for r in helper['observations'] if r.get('phase')=='ui-marker-checked'];assert len(markers)==1 and markers[0]['value']==checked and checked['value']=='checked-1'
failedrelay=[r for r in helper['observations'] if r.get('phase')=='lifecycle-relay' and r['expected']=='checked'];assert failedrelay and all(r['status']=='binding-or-phase-mismatch' for r in failedrelay)
index=load(P+'-all-originals.json');assert index['count']==90 and index['kinds']=={'text':13,'binary-plist':66,'png':9,'video':1,'json':1} and not index['stageErrors']
archive=index['otherArchive'];raw=gzip.decompress((B/archive['file']).read_bytes());assert len(raw)==archive['decodedBytes'] and h.sha(raw)==archive['decodedSHA256'];others=json.loads(raw)['files'];assert len(others)==79
manifest=index['completeManifest'];raw=gzip.decompress((B/manifest['file']).read_bytes());assert len(raw)==manifest['bytes'] and h.sha(raw)==manifest['sha256']
root=Path('/tmp/LumenBatch44Checks/HealthConfirmationNotNowDataSource255R1All');assert raw==(root/'manifest.json').read_bytes()
for row in index['rows']:
 raw=(root/row['file']).read_bytes();assert len(raw)==row['bytes'] and h.sha(raw)==row['sha256']
 assert raw==((B/row['retained']).read_bytes() if 'retained' in row else v.payload(others[row['file']],h))
for row in ret['images']+ret['readbacks']:
 raw=(B/row['file']).read_bytes();assert raw==Path(row['raw']).read_bytes() and len(raw)==row['bytes'] and h.sha(raw)==row['sha256']
auditobs=load(P+'-mandatory-checker-audit-observation.json');assert auditobs['actualAuditCoherent'] is True and auditobs['error'] is None and not auditobs['stageErrors'] and auditobs['checkerQuery']==query
assert json.loads(v.payload(auditobs['raw'],h,8*1024*1024))==checker
v.all_payloads(auditobs,h,inputs['app'])
diagnostic=load('source255-post-failure-readonly-diagnostic-r1.json');assert len(diagnostic['samples'])==2
for row in diagnostic['samples']:
 assert not row['errors'] and row['mode']==row['process']['mode']=='absent'
 v.protected(row['protected'],first,h);v.fixed(row['fixed'],h.DATA,h,e.obs);assert row['installed']==s['boundaries'][0]['installed']
 assert json.loads(v.payload(row['native'],h,128*1024))==row['nativeValue']==s['nativeStates'][-1]['value']
 assert json.loads(v.payload(row['trace'],h,16384))==trace and json.loads(v.payload(row['nativeCheck'],h,16384))==observation
 assert row['ackExists'] is True and row['checkFileExists'] is True and row['uiMarkers']=={'presented':True,'dismissed':True,'checked':True}
 assert row['sourceExact'] is True and len(row['ownedWorkspaces'])==2 and all(row['caseRoots'].values())
 assert [r['event'] for r in row['originEvents']]==['open','ready']
 v.all_payloads(row,h,inputs['app'])
video=next(r for r in index['rows'] if r['kind']=='video')
result={'status':'FAILED actual255 case retained and strictly replayed; actual Form acquisition/tap/fresh nativeCheck partial supported, no Back/fullcase acceptance','sourceInputs':inputs['inputs'],'nativeCounts':[0,1,0],'nativePID':s['nativePID'],'appPID':s['appPID'],'runID':s['runID'],'nativeExit':65,'driverExit':1,'checkerPID':query['pid'],'checkerExit':1,'passedHostBoundaries':2,'allOriginals':90,'originalPNGs':9,'helperBytes':ret['readbacks'][0]['bytes'],'videoBytes':video['bytes'],'videoSHA256':video['sha256'],'videoScope':'Full original bytes retained unplayed; no motion acceptance','actualCheckAcquisition':acquired[0],'nativeCheckRequestID':nativecheck['requestID'],'finding':'Actual checked marker dictionary stored at window.checked makes exact actual old if window.get(checked):return guard return early after native check validation. Actual2relays only, no protectedAfterCheck/originAfterCheck/checkedrelay/hostcompletion flag. Native awaits checked relay, reads still-late-ack and times out. Separate host completion Boolean is required without clobbering raw checked marker; mandatory checker acceptance uses separate flag while retained_value(checked) keeps original dictionary. Actual AST guard on retained dictionary confirms early return. No app/toolbar/native cancellation defect inferred.','laterSamples':'Two explicit absent/protected endpoints preserve13current13prior/Data42/provider/source/currentinstalled/native3/trace5/nativecheck/lateack/UIchecked;2heldworkspaces/openreadytrace remain. No Back/ownerclosure/globalFD/continuousabsence/exitcause claim.','scope':'Current951inputs verified by actualcurrentR2checker before nativefailure rejection and root verify_inputs. R3 actualfailed-case query persisted/coherence/rawaudit/full90 acquisition succeeded. No nativefullcase/Release/global acceptance.','checkedAt':time.time()}
p=B/'source255-root-native-failure-audit-r1.json';assert not p.exists();p.write_text(json.dumps(result,indent=2)+'\n');print(result['status'])
