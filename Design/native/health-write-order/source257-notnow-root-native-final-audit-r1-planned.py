"""Root retained validation replay and original-byte audit; no live app queries."""
from pathlib import Path
from types import SimpleNamespace
import ast,base64,gzip,hashlib,importlib.util,json,subprocess,time
B=Path(__file__).resolve().parent;R=B.parents[2];load=lambda n:json.loads((B/n).read_bytes());sha=lambda x:hashlib.sha256(x).hexdigest();plan=load('source257-notnow-regression-r1-plan.json');P=plan['prefix']
def module(name,file):
 s=importlib.util.spec_from_file_location(name,B/file);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
e=module('root_lifecycle_evidence','confirmation-lifecycle-evidence-r1.py');h=e.h;v=e.e.module('root_strict_validator','legacy-target-change-validation-r3.py');processes=module('root_process_classifier','target-postrun-process-r1.py')
queries=[]
def denied(*args,**kw):queries.append(str(args));raise AssertionError('No live/process query permitted in retained root replay')
for key in ['Popen','run','check_output','check_call','call']:setattr(subprocess,key,denied)
out=load(P+'-outcome.json');state=load(P+'-host-audit.json');checker=load(P+'-'+plan['checkerOutcomeProtocol']+'-'+plan['checkerTrial'].lower()+'-outcome.json');query=load(P+'-mandatory-checker-query.json');auditobs=load(P+'-mandatory-checker-audit-observation.json')
assert out['nativeExit']==out['driverExit']==checker['checkerExit']==query['exit']==0 and out['hostError'] is None
assert auditobs['actualAuditCoherent'] is True and not auditobs['error'] and not auditobs['stageErrors'] and auditobs['checkerQuery']==query
assert json.loads(base64.b64decode(auditobs['raw']['base64'],validate=True))==checker
finalizer=module('root_lifecycle_finalizer',plan['finalizer']);assert query['command']==finalizer.checker_command(B,plan,state,out)
for stream in ['stdout','stderr']:v.payload(query[stream],h,8*1024*1024)
# Execute the actual mandatory-checker strict retained section, stopping BEFORE
# native/group/live final endpoint collection. Its pure/source guards all run.
source=(B/plan['checker']).read_bytes();tree=ast.parse(source);body=next(n for n in tree.body if isinstance(n,ast.Try)).body;prefix=[]
for node in body:
 if isinstance(node,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='native' for t in node.targets):break
 prefix.append(node)
assert prefix and 'v.all_payloads(state, h, inputs' in ast.unparse(prefix[-1])
env={'BASE':B,'e':e,'h':h,'v':v,'json':json,'gzip':gzip,'base64':base64,'time':time,'Path':Path,'a':SimpleNamespace(prefix=P,case_source=plan['caseSource'],checker_source=plan['source'],build=plan['build'],trial=plan['checkerTrial']),'result':{},'persist':lambda:None}
verify=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='verify_checker_source');exec(compile(ast.fix_missing_locations(ast.Module(body=[verify],type_ignores=[])),'actual-checker-source-function','exec'),env)
exec(compile(ast.fix_missing_locations(ast.Module(body=prefix,type_ignores=[])),'actual-checker-retained-prefix','exec'),env)
assert env['state']==state and env['out']==out and env['result']['checkerSourceVerification']==checker['checkerSourceVerification']
inputs=env['inputs'];first=state['boundaries'][0]['protected'];last=state['boundaries'][-1];audit=checker['finalAudit'];assert len(audit['samples'])==2 and audit['status'].startswith('PASS two sampled')
for row in audit['samples']:
 mode=processes.classify(row['process'],state['appPID'],state['boundaries'][0]['installed']['path']);assert mode==audit['mode']==row['process']['mode']
 assert row['installed']==state['boundaries'][0]['installed']
 assert json.loads(v.payload(row['nativeState'],h,128*1024))==last['observation']
 v.protected(row['protected'],first,h);v.fixed(row['fixed'],h.DATA,h,e.obs);assert row['originEvents']==last['originEvents'] and not row['owned'] and not any(row['caseRoots'].values())
assert audit['samples'][1]['monotonic']-audit['samples'][0]['monotonic']>=0.25
v.all_payloads(checker,h,inputs['app'])
ret=out['retention'];helper=load(ret['readbacks'][0]['file']);assert helper['phase']=='completed' and not helper.get('failure')
facts=[r for r in helper['observations'] if r.get('phase')=='check-acquisition-before-touch'];assert len(facts)==1;f=facts[0]
assert all(f[k] is True for k in ['exists','enabledObserved','enabled','hittableObserved','hittable','frameObserved','finiteFrame','positiveWholeFrame','roleObserved','roleIsButton','navigationStillPresent','ready']) and f['queryCount']==1 and f['identifier']=='checkConfirmationLifecycle'
assert f['frame']['width']>=44 and f['frame']['height']>=44
index=load(P+'-all-originals.json');assert not index['stageErrors'];root=Path('/tmp/LumenBatch44Checks')/(plan['rawStem']+'All');otherfact=index['otherArchive'];raw=gzip.decompress((B/otherfact['file']).read_bytes());assert len(raw)==otherfact['decodedBytes'] and sha(raw)==otherfact['decodedSHA256'];other=json.loads(raw)['files']
manifest=index['completeManifest'];raw=gzip.decompress((B/manifest['file']).read_bytes());assert len(raw)==manifest['bytes'] and sha(raw)==manifest['sha256'] and raw==(root/'manifest.json').read_bytes()
assert index['count']==len(index['rows'])
for row in index['rows']:
 raw=(root/row['file']).read_bytes();assert len(raw)==row['bytes'] and sha(raw)==row['sha256']
 assert raw==((B/row['retained']).read_bytes() if 'retained' in row else v.payload(other[row['file']],h))
for row in ret['images']+ret['readbacks']:
 raw=(B/row['file']).read_bytes();assert raw==Path(row['raw']).read_bytes() and len(raw)==row['bytes'] and sha(raw)==row['sha256']
assert len(ret['images'])==14 and len(ret['readbacks'])==1
proof=load('source257-source-exact-github.json');assert proof['commit']=='5b9d3281274d44432a61d1a03fb0333dfe97d78a' and proof['unionPaths']==2297 and proof['source']==plan['source'] and proof['checkedAt']<=state['started']
assert not queries
result={'status':'PASS root actualSource257R1 Notnow retained strict R3 checker replay/currenthost1045/case1045/originals/final endpoints; original visual review and independent native review pending','source':plan['source'],'caseSource':plan['caseSource'],'sourceInputs':inputs['inputs'],'nativeCounts':[1,0,0],'nativePID':state['nativePID'],'appPID':state['appPID'],'runID':state['runID'],'nativeExit':0,'driverExit':0,'checkerPID':query['pid'],'checkerExit':0,'passedHostBoundaries':5,'originalPNGs':14,'helperBytes':ret['readbacks'][0]['bytes'],'allOriginals':index['count'],'originalKinds':index['kinds'],'actualCheckAcquisition':f,'endpointMode':audit['mode'],'endpointGapSeconds':audit['samples'][1]['monotonic']-audit['samples'][0]['monotonic'],'retainedCheckerASTStatements':len(prefix),'deniedProcessQueries':queries,'scope':'Actual strict current mandatory R3 checker retained-prefix replay stops before live-query boundary under process denial; mandatory checker itself made fresh endpoints. All raw/canonical originals byte-exact; screenshots still require individual visual review. Sampled endpoints only; no continuous absence/globalFD/exitcause/all43/fullgoal/distribution acceptance. No video exported in this successful15-original export; no motion/recording proof.','checkedAt':time.time()}
p=B/'source257-notnow-root-native-final-audit-r1.json';assert not p.exists();p.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
