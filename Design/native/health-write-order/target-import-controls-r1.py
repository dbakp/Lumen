"""Real helper imports and CLI help; native producer code must not execute."""
import ast,contextlib,copy,gzip,hashlib,importlib.util,io,json,subprocess,sys,time
from pathlib import Path
from types import SimpleNamespace
B=Path(__file__).resolve().parent
checks=[];fixtures=[];queries=[]
def sha(raw):return hashlib.sha256(raw).hexdigest()
def test(name,action,accept=True):
 try:value=action();accepted=True;error=None
 except Exception as exception:value=None;accepted=False;error=type(exception).__name__
 assert accepted is accept,(name,accepted,error)
 checks.append({'name':name,'expectedAcceptance':accept,'actualAcceptance':accepted,'errorType':error});return value
def load(file,name):
 spec=importlib.util.spec_from_file_location(name,B/file);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
def forbidden(*args,**kwargs):queries.append('attempted subprocess during helper import');raise AssertionError('Import must not query or launch processes')
old={name:getattr(subprocess,name) for name in ['run','Popen','check_output']}
try:
 for name in old:setattr(subprocess,name,forbidden)
 test('original actual dependency import remains rejected',lambda:load('legacy-target-change-evidence-r4.py','original_failed_import'),False)
 module=test('corrected actual evidence import',lambda:load('legacy-target-change-evidence-r5.py','corrected_real_import'))
 assert module is not None and not queries
 test('private base is exact intended R2',lambda:None if Path(module._base.__file__).name=='legacy-target-change-evidence-r2.py' else (_ for _ in []).throw(AssertionError()))
 assert module.PHASES==['before-selection','ready','target-changed','rejected','owners-closed','fresh-ready','fresh-committed','final-closed']
 assert module.STATUSES==['before-selection','ready','mutated','rejected','closed','fresh-ready','fresh-recovery-committed','closed']
 assert module.COUNTS==[0,3,7,8,9,12,13,14] and len(module.IMAGES)==len(set(module.IMAGES))==16
 checks.append({'name':'actual eight-phase/status/count and16suffix contract','expectedAcceptance':True,'actualAcceptance':True,'errorType':None})
 tree=ast.parse((B/'legacy-target-change-evidence-r5.py').read_text())
 loop=next(node for node in tree.body if isinstance(node,ast.For))
 nested=SimpleNamespace(parent=SimpleNamespace(),time='kept-time',value=42,_base='must-not-export')
 scope={'_base':nested};exec(compile(ast.Module(body=[loop],type_ignores=[]),'actual-export-loop','exec'),scope)
 assert scope['_base'] is nested and scope['parent'] is nested.parent and scope['time']=='kept-time' and scope['value']==42
 checks.append({'name':'actual export loop withstands parent/private-base collision','expectedAcceptance':True,'actualAcceptance':True,'errorType':None})
 baseline=json.loads((B/'health-legacy-target-change-data-source230r1-host-audit.json').read_bytes())
 ready=baseline['boundaries'][5]['observation'];started=baseline['started']
 committed=copy.deepcopy(ready);committed['sequence']=13;committed['status']='fresh-recovery-committed';committed['events'].append({'event':'actual-recovery-success','sessionID':ready['sessionID'],'captureID':ready['captureID']})
 closed=copy.deepcopy(committed);closed['sequence']=14;closed['status']='closed';closed['events'].append({'event':'closed','sessionID':ready['sessionID']})
 def schema(name,value,accept=True):
  fixtures.append({'name':name,'value':copy.deepcopy(value),'expectedAcceptance':accept})
  test(name,lambda:module.check_state(value,started,baseline['runID'],baseline['appPID']),accept)
 schema('actual retained fresh-ready prefix delegates strictR2',ready)
 schema('constructed fresh commit schema',committed)
 schema('constructed committed closed schema',closed)
 for name,change in [
  ('bootstrap flag false rejected',lambda value:value.update(bootstrapNativeChecked=False)),
  ('bootstrap Health connection rejected',lambda value:value['bootstrapObservation'].update(healthConnected=True)),
  ('wrong fresh commit capture rejected',lambda value:value['events'][12].update(captureID='00000000-0000-0000-0000-000000000001')),
  ('old-session success rejected',lambda value:value['events'][12].update(sessionID=baseline['oldSession'])),
  ('old error classification lost rejected',lambda value:value['events'][7].update(changedClassification=False))]:
  value=copy.deepcopy(committed);change(value);schema(name,value,False)
 # Public parent is legitimately exported, but must never become delegation.
 exported_parent=module.parent;module.parent=SimpleNamespace()
 try:
  schema('public parent overwritten cannot bypass strict base',committed)
  original_trace=module._base.origin_trace;sentinel=object();module._base.origin_trace=lambda *args,**kwargs:sentinel
  try:assert module.origin_trace('/synthetic',0) is sentinel
  finally:module._base.origin_trace=original_trace
  checks.append({'name':'origin trace delegates same private base','expectedAcceptance':True,'actualAcceptance':True,'errorType':None})
 finally:module.parent=exported_parent
 verification=test('real535host inputs/archive verify without OS query',lambda:module.verify_host_source('durable-source-r233.json'))
 assert verification['exactCurrentArchiveBindings']==535
 test('unsafe host manifest path rejected',lambda:module.verify_host_source('../durable-source-r233.json'),False)
 test('non-json host manifest rejected',lambda:module.verify_host_source('other.txt'),False)
finally:
 for name,value in old.items():setattr(subprocess,name,value)
assert not queries
helps=[]
for filename in ['legacy-target-change-driver-r5.py','check-legacy-target-change-r8.py']:
 command=[sys.executable,'-B',str(B/filename),'--help']
 result=subprocess.run(command,capture_output=True,text=True,timeout=30)
 helps.append({'command':command,'exit':result.returncode,'stdout':result.stdout,'stderr':result.stderr})
 assert result.returncode==0 and result.stdout.startswith('usage:') and not result.stderr
 assert '--host-source' in result.stdout if filename.startswith('legacy-target') else '--checker-source' in result.stdout
 checks.append({'name':filename+' real --help subprocess','expectedAcceptance':True,'actualAcceptance':True,'errorType':None})
assert not list(B.glob('health-legacy-target-change-data-source234r1-*'))
decoded=json.dumps({'scope':'Pure constructed schemas using pinned old native metadata; no current native execution','fixtures':fixtures,'started':started,'runID':baseline['runID'],'appPID':baseline['appPID']},sort_keys=True).encode()
target=B/'source234-import-controls-r1-fixtures.json.gz';assert not target.exists();target.write_bytes(gzip.compress(decoded,mtime=0))
facts=[]
for name in ['legacy-target-change-evidence-r5.py','legacy-target-change-driver-r5.py','check-legacy-target-change-r8.py']:
 raw=(B/name).read_bytes();facts.append({'file':name,'bytes':len(raw),'sha256':sha(raw)})
output={'status':'PASS actual dependency imports/private-base controls and real driver/checker help','count':len(checks),'checks':checks,'subprocessQueryAttemptsDuringDirectImports':queries,'helps':helps,'hostCaseVerification':verification,'sourceFiles':facts,'fixtureArchive':{'file':target.name,'bytes':target.stat().st_size,'sha256':sha(target.read_bytes()),'decodedBytes':len(decoded),'decodedSHA256':sha(decoded)},'scope':'Direct helper imports guarded against subprocess queries; CLI help imports then exits argparse before native path. Native schema records constructed from pinned old prefix only; no app reset/launch/native tests/phone actions or new app build.','checkedAt':time.time()}
(B/'source234-import-controls-r1.json').write_text(json.dumps(output,indent=2)+'\n');print(json.dumps({key:value for key,value in output.items() if key not in ['checks','helps']},indent=2))
