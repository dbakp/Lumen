"""Strict failedcase replay/original byte verification before successor edits."""
from pathlib import Path
import base64,gzip,hashlib,importlib.util,json,time
B=Path(__file__).resolve().parent;P='health-confirmation-notnow-data-source253r1';load=lambda n:json.loads((B/n).read_bytes())
def module(name,file):
 spec=importlib.util.spec_from_file_location(name,B/file);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
e=module('failed_lifecycle_evidence','confirmation-lifecycle-evidence-r1.py');h=e.h;v=e.v;protocol=module('failed_lifecycle_protocol','confirmation-lifecycle-protocol-r1.py');geometry=module('failed_lifecycle_geometry','confirmation-window-evidence-r3.py')
s=load(P+'-driver-observations.json');out=load(P+'-outcome.json');checker=load(P+'-lifecycle-r2-currentr2-outcome.json');query=load('source253-mandatory-r2-checker-r2.json')
assert out['nativeExit']==65 and out['driverExit']==checker['checkerExit']==query['exit']==1
assert [out['summary'][k] for k in ['passedTests','failedTests','skippedTests']]==[0,1,0] and 'finalAudit' not in checker
inputs=h.verify_inputs('durable-source-r253.json','health-target-change-source253-r1-build.json');assert s['preflight']==inputs and s['hostSourceVerification']==e.verify_host_source(s['hostSource'])==checker['checkerSourceVerification']
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
window=s['confirmationWindow'];assert window['acknowledged'] is True and all(k in window for k in ['ackIntended','ackBytes','dismissed']) and not any(k in window for k in ['checked','check'])
assert len(window['relays'])==2 and [r['value']['phase'] for r in window['relays']]==['armed','late-ack']
def latest(key):
 versions=window[key]['versions'];assert versions
 for value in versions:v.payload(value,h,16384)
 return json.loads(v.payload(versions[-1],h,16384))
gate=latest('gate');protocol.binding(gate);geometry.validate_binding(gate,s['boundaries'][1]['observation'])
trace=latest('trace');protocol.trace(trace,gate,s['started'],True);assert trace['checks']==[]
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

ret=out['retention'];assert not ret['errors'] and ret==load(P+'-retention-state.json') and ret['images']==load(P+'-images.json') and ret['readbacks']==load(P+'-readbacks.json') and ret['summary']==load(P+'-summary.json')
assert len(ret['images'])==8 and len(ret['readbacks'])==1
for q in ret['queries']:
 assert q['exitCode']==0
 for key in ['stdout','stderr']:
  f=q[key];raw=gzip.decompress((B/f['retained']).read_bytes());assert f['retainedExact'] and len(raw)==f['bytes'] and h.sha(raw)==f['sha256']
f=ret['log'];raw=gzip.decompress((B/f['retained']).read_bytes());assert len(raw)==f['bytes'] and h.sha(raw)==f['sha256'];text=raw.decode();assert 'Tap "Not now" Button' in text and 'Tap "Recover" Button' not in text
helper=load(ret['readbacks'][0]['file']);assert helper['phase']=='check' and helper['failure']=='Actual cancellation Check control unavailable' and helper['scope']=='actual-confirmation-notnow-before-late-ack'
pans=[r for r in helper['observations'] if r.get('phase')=='not-now-choice-0'];assert len(pans)==2 and all(r['direction']==-1 and r['missingAbove'] is True and r['navigationStillPresent'] is True for r in pans) and pans[-1]['targetPresent'] is True
choices=[r for r in helper['observations'] if r.get('phase')=='not-now-choice'];assert [r['choice'] for r in choices]==[0,1,2] and [r['value'] for r in choices]==['1','0','0'] and all(r['enabled'] is True for r in choices)
tap=[r for r in helper['observations'] if r.get('phase')=='not-now-tap'];assert len(tap)==1 and tap[0]['touchAt']==dismissed['touchAt'] and tap[0]['tapReturnedAt']==dismissed['tapReturnedAt'] and tap[0]['cancelFrame']==dismissed['cancelFrame']
dismiss=[r for r in helper['observations'] if r.get('phase')=='not-now-dismissal'];assert len(dismiss)==1 and dismiss[0]['alertDismissed'] is True and dismissed['tapReturnedAt']<=dismiss[0]['at']<=dismissed['at']
accepted=[r for r in helper['observations'] if r.get('phase')=='lifecycle-relay' and r['expected']=='late-ack' and r['status']=='accepted-metadata-only'];assert len(accepted)==1 and accepted[0]['value']==window['relays'][1]['value'] and accepted[0]['at']>=window['relays'][1]['publicationStartedAt']
index=load(P+'-all-originals.json');assert index['count']==71 and index['kinds']=={'binary-plist':54,'png':8,'text':7,'json':1,'video':1}
archive=index['otherArchive'];raw=gzip.decompress((B/archive['file']).read_bytes());assert len(raw)==archive['decodedBytes'] and h.sha(raw)==archive['decodedSHA256'];others=json.loads(raw)['files'];assert len(others)==61
manifest=index['completeManifest'];raw=gzip.decompress((B/manifest['file']).read_bytes());assert len(raw)==manifest['bytes'] and h.sha(raw)==manifest['sha256']
root=Path('/tmp/LumenBatch44Checks/HealthConfirmationNotNowDataSource253R1All')
for row in index['rows']:
 raw=(root/row['file']).read_bytes();assert len(raw)==row['bytes'] and h.sha(raw)==row['sha256']
 if 'retained' in row:assert raw==(B/row['retained']).read_bytes()
 else:assert v.payload(others[row['file']],h)==raw
for row in ret['images']+ret['readbacks']:
 raw=(B/row['file']).read_bytes();assert raw==Path(row['raw']).read_bytes() and len(raw)==row['bytes'] and h.sha(raw)==row['sha256']
diagnostic=load('source253-post-failure-readonly-diagnostic-r1.json');assert len(diagnostic['samples'])==2
for row in diagnostic['samples']:
 assert not row['errors'] and row['mode']==row['process']['mode']=='absent'
 v.protected(row['protected'],first,h);v.fixed(row['fixed'],h.DATA,h,e.obs);assert row['installed']==s['boundaries'][0]['installed']
 assert json.loads(v.payload(row['native'],h,128*1024))==row['nativeValue']==s['nativeStates'][-1]['value']
 assert json.loads(v.payload(row['trace'],h,16384))==trace
 assert row['ackExists'] is True and row['checkFileExists'] is False and row['uiMarkers']=={'presented':True,'dismissed':True,'checked':False}
 assert row['sourceExact'] is True and len(row['ownedWorkspaces'])==2 and all(row['caseRoots'].values())
 assert [r['event'] for r in row['originEvents']]==['open','ready']
video=next(r for r in index['rows'] if r['kind']=='video')
result={'status':'FAILED actual252case replayed exactly; no freshCheck/Back/full native success','sourceInputs':inputs['inputs'],'nativeCounts':[0,1,0],'nativePID':s['nativePID'],'appPID':s['appPID'],'runID':s['runID'],'nativeExit':65,'driverExit':1,'checkerPID':query['pid'],'checkerExit':1,'passedHostBoundaries':2,'allOriginals':71,'originalPNGs':8,'helperBytes':ret['readbacks'][0]['bytes'],'videoBytes':video['bytes'],'videoSHA256':video['sha256'],'videoScope':'Full45MBbytes/hash retained unplayed; no motion acceptance', 'finding':'Actualmeal reveal succeeds after2backwardpans; all3enabled retainedchoices1/0/0, actualtap/dismissfacts and strictdismissedmarker observed. Validlateack toexactclosednonce onlyafteractualtaskvaluecompletion+choices+strictprotectedoldsource/fixed checks; lateack relayreadaccepted. NativefailscompoundCheck(waitexists&&enabled&&hittable) beforetap. IndividualCheckpredicate/role/frame facts were notretained; no uniqueAX/API/toolbarcause claimed. VisibleDEBUGbutton inoriginal not equivalenttohittability. No nativeCheckcallback/request/read/Back/freshowner/finalclosure.',
'laterSamples':'Twoabsentapp endpoints preserve13current/prior13/rawmetadata/Data42/provider/source/currentinstalled/native3/trace5/exactlateack; nativecheckfile/checkedmarkerabsent. Twoheldworkspaces/openreadytrace remain, no owner/FDclosure/continuousabsence/exitcause proof.',
'next':'Samecritic168/root/exact fullfailedcase before separate254Checkdiagnostics and boundedactualcontrol materialization/positivehittability+geometry; considerDEBUGonlyprobe placement ifneeded. Do not relaxactualtouch/freshread/strictlateack authority guards. No reset/source edit/cleanup beforebackup.' ,'checkedAt':time.time()};p=B/'source253-root-native-failure-audit-r2.json';assert not p.exists();p.write_text(json.dumps(result,indent=2)+'\n');print(result['status'])
