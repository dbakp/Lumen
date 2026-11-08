"""Actual composed String predicates, previous real retained inputs, and entrypoint help.
No native launch/reset; prior ready-window outcomes do not prove confirmation timing.
"""
from pathlib import Path
import ast,base64,copy,gzip,hashlib,importlib.util,json,runpy,sys,subprocess,time,contextlib,io
B=Path(__file__).resolve().parent
sha=lambda b:hashlib.sha256(b).hexdigest()
queries=[]
def denied(*args,**kwargs):queries.append(str(args));raise AssertionError('No process queries in isolated preparation')
for key in ['Popen','run','check_output','check_call','call']:setattr(subprocess,key,denied)
spec=importlib.util.spec_from_file_location('actual_string_confirmation',B/'confirmation-string-evidence-r1.py');e=importlib.util.module_from_spec(spec);spec.loader.exec_module(e)
assert Path(e.obs.__file__).name=='target-string-observation-r2.py' and Path(e.success.__file__).name=='target-string-success-r1.py' and Path(e.v.__file__).name=='target-string-validation-r1.py'
assert len(e.obs.OLD)==70 and len(e.obs.NEW)==66
source=B/'health-legacy-target-change-string-source244stringr1-host-audit.json';old=json.loads(source.read_bytes());cases=[];fixtures=[]
def check(name,value,accept):
 ok=True
 try:e.check_state(value,old['started'],old['runID'],old['appPID'])
 except (AssertionError,KeyError,ValueError):ok=False
 assert ok is accept,name
 cases.append({'name':name,'expectedAccepted':accept,'status':'PASS'});fixtures.append({'name':name,'value':value,'expectedAccepted':accept})
for i,row in enumerate(old['nativeStates']):check('actual prior String native state '+str(i),row['value'],True)
base=old['boundaries'][2]['observation']
for label,change in [('Data origin kind',lambda x:x.__setitem__('originKind','data')),('missing kind',lambda x:x.pop('originKind')),('changed classification',lambda x:x['events'][4].__setitem__('oldTokenVerified',False)),('wrong run',lambda x:x.__setitem__('runID','11111111-1111-4111-8111-111111111111'))]:
 value=copy.deepcopy(base);change(value);check(label,value,False)
# Actual String native fixed observations reject Data aliases and normalization.
facts=copy.deepcopy(base['events'][4]['fixed']);e.obs.native_fixed(facts,e.obs.OLD,e.h)
for label,mutate in [('Data class',lambda x:x[e.obs.KEYS[0]]['persisted'].__setitem__('type','Foundation.__NSSwiftData')),('normalized UTF16',lambda x:x[e.obs.KEYS[0]]['persisted'].__setitem__('payload',base64.b64encode('Synthetic persisted old value é 🫖'.encode('utf-16-le')).decode())),('wrong UTF16 units',lambda x:x[e.obs.KEYS[0]]['persisted'].__setitem__('utf16Units',1))]:
 value=copy.deepcopy(facts);mutate(value);rejected=False
 try:e.obs.native_fixed(value,e.obs.OLD,e.h)
 except AssertionError:rejected=True
 assert rejected,label;cases.append({'name':label,'expectedAccepted':False,'status':'PASS'});fixtures.append({'name':label,'fixed':value})
help_rows=[]
for file in ['confirmation-string-driver-r1.py','check-confirmation-string-r1.py']:
 sys.argv=[str(B/file),'--help'];stdout=io.StringIO();stderr=io.StringIO()
 with contextlib.redirect_stdout(stdout),contextlib.redirect_stderr(stderr):
  try:runpy.run_path(str(B/file),run_name='__main__')
  except SystemExit as err:assert err.code==0
  else:raise AssertionError('Help must exit before any producer work')
 help_rows.append({'file':file,'exit':0,'stdout':stdout.getvalue(),'stderr':stderr.getvalue(),'realProcessQueries':0})
assert not queries
# Shared native routine is byte-exact; only one new test wrapper is permitted.
manifest=json.loads((B/'durable-source-r248.json').read_bytes());archive=json.loads(gzip.decompress((B/'durable-source-r248.json.gz').read_bytes()))
key='LumenUITests/LumenSmokeTests.swift';prior=archive['files'][key];current=(B.parents[2]/key).read_text();addition='''    @MainActor
    func testHealthBackupFileRecoveryTargetChangedDuringConfirmationOriginString() throws {
        try exerciseHealthBackupFileRecoveryTargetChangedAfterReady(duringConfirmation: true)
    }

'''
assert current.count(addition)==1 and current.replace(addition,'')==prior
raw=json.dumps({'cases':fixtures,'priorRealStringSource':str(source.name),'priorSHA256':sha(source.read_bytes()),'help':help_rows},ensure_ascii=False).encode();(B/'source249-string-preparation-controls-r1-fixtures.json.gz').write_bytes(gzip.compress(raw,mtime=0))
out={'status':'PASS actual composedString predicates/UTF16/type negatives/actual entrypoint help zeroqueries/shared native routine unchanged','cases':cases,'count':len(cases),'help':help_rows,'actualNamespaces':{k:Path(getattr(e,k).__file__).name for k in ['obs','success','v']},'realProcessQueries':0,'archiveDecodedBytes':len(raw),'archiveDecodedSHA256':sha(raw),'changedUITestSHA256':sha(current.encode()),'scope':'Isolated preparation and historical prior real String predicate compatibility only; no new confirmation/relay/alert/native/Release/cancellation/expiry/fullgoal acceptance.','checkedAt':time.time()};(B/'source249-string-preparation-controls-r1.json').write_text(json.dumps(out,indent=2)+'\n');print(len(cases),'predicate controls and2help PASS; zeroqueries')
