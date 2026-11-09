"""Execute actual finalizer main with isolated files and injected child outputs."""
from pathlib import Path
from types import SimpleNamespace
import contextlib,copy,gzip,hashlib,importlib.util,io,json,sys,tempfile,time
B=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('actual_r3_finalizer',B/'confirmation-expiry-finalization-r1.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
state=json.loads((B/'health-confirmation-notnow-data-source253r1-driver-observations.json').read_bytes());out=json.loads((B/'health-confirmation-notnow-data-source253r1-outcome.json').read_bytes());plan=json.loads((B/'source257-expiry-execution-r1-plan.json').read_bytes())
for d in [state,out,state['preflight']]:d.update(source=plan['caseSource'],build=plan['build'])
state['hostSource']=plan['source'];state['hostSourceVerification']['source']=plan['source']
valid={'checkerSourceVerification':{'source':plan['source']},'caseSource':plan['caseSource'],'checkerSource':plan['source'],'build':plan['build'],'prefix':plan['prefix'],'trial':plan['checkerTrial']}
cases=[('missing',None,False),('empty',b'',False),('malformed',b'{"bad":',False),('list',b'[]',False),('null',b'null',False),('empty-object',b'{}',False),('wrong-verification-shape',json.dumps(dict(valid,checkerSourceVerification=[])).encode(),False),('wrong-source',json.dumps(dict(valid,caseSource='durable-source-r252.json')).encode(),False),('coherent-native-rejection',json.dumps(valid).encode(),True),('coherent-native-success',json.dumps(valid).encode(),True),('query-write-failure',json.dumps(valid).encode(),True)]
rows=[];real_queries=[];saved_argv=sys.argv[:];realPath=Path;real_write=m.write_new
for name,audit,expected in cases:
 with tempfile.TemporaryDirectory(prefix='lumen257-expiry-finalizer-caller-') as temp:
  base=Path(temp)/'base';base.mkdir();rawroot=Path(temp)/'raw';rawroot.mkdir();prefix=plan['prefix'];commands=[]
  m.__file__=str(base/'confirmation-expiry-finalization-r1.py')
  def fixturePath(*args,**kwargs):
   if args==('/tmp/LumenBatch44Checks',):return rawroot
   return realPath(*args,**kwargs)
  m.Path=fixturePath
  actual_state=copy.deepcopy(state);actual_state['command'][actual_state['command'].index('-resultBundlePath')+1]=str(rawroot/(plan['rawStem']+'.xcresult'))
  native_exit=0 if name=='coherent-native-success' else 65
  actual_out=dict(out,nativeExit=native_exit,driverExit=0 if native_exit==0 else 1)
  for file,d in [('plan.json',plan),(prefix+'-driver-observations.json',actual_state),(prefix+'-outcome.json',actual_out)]: (base/file).write_text(json.dumps(d))
  def inject_write(path,value):
   if name=='query-write-failure' and path.name==prefix+'-mandatory-checker-query.json':raise OSError('INJECTED query-write failure')
   return real_write(path,value)
  m.write_new=inject_write
  auditfile=base/(prefix+'-'+plan['checkerOutcomeProtocol']+'-'+plan['checkerTrial'].lower()+'-outcome.json')
  class Child:
   pid=424242;returncode=0 if native_exit==0 else 1
   def communicate(self):
    if audit is not None:auditfile.write_bytes(audit)
    return b'INJECTED checker stdout\n',b'INJECTED checker stderr\n'
  def popen(command,**kwargs):commands.append({'kind':'checker','command':command});return Child()
  def export(command,**kwargs):
   commands.append({'kind':'export','command':command})
   observation=json.loads((base/(prefix+'-mandatory-checker-audit-observation.json')).read_bytes());assert observation['actualAuditCoherent'] is expected
   query=observation['checkerQuery'] if name=='query-write-failure' else json.loads((base/(prefix+'-mandatory-checker-query.json')).read_bytes())
   assert query['pid']==424242 and query['exit']==Child.returncode and query['stdout']==m.payload(b'INJECTED checker stdout\n') and query['stderr']==m.payload(b'INJECTED checker stderr\n')
   if name=='query-write-failure':assert observation['stageErrors'] and not (base/(prefix+'-mandatory-checker-query.json')).exists()
   if not expected:assert observation['error']
   target=Path(command[command.index('--output-path')+1]);target.mkdir();(target/'manifest.json').write_text('{"synthetic":true}');(target/'helper.json').write_text('{"synthetic":"helper"}');(target/'trace.txt').write_bytes(b'SYNTHETIC original text\n')
   return SimpleNamespace(returncode=0,stdout=b'INJECTED export stdout\n',stderr=b'')
  m.subprocess.Popen=popen;m.subprocess.run=export
  sys.argv=['caller-controls','--plan','plan.json'];failure=None
  try:
   with contextlib.redirect_stdout(io.StringIO()):m.main()
  except AssertionError as error:failure=str(error)
  assert (failure is None)==(expected and name!='query-write-failure'),(name,failure)
  assert [x['kind'] for x in commands]==['checker','export']
  index=json.loads((base/(prefix+'-all-originals.json')).read_bytes());assert index['count']==2 and index['kinds']=={'json':1,'text':1}
  helper=base/(prefix+'-helper.json');assert helper.read_bytes()==b'{"synthetic":"helper"}'
  archive=json.loads(gzip.decompress((base/(prefix+'-all-other-originals.json.gz')).read_bytes()));assert archive['files']['trace.txt']==m.payload(b'SYNTHETIC original text\n')
  obs=json.loads((base/(prefix+'-mandatory-checker-audit-observation.json')).read_bytes())
  rows.append({'case':name,'syntheticCheckerPID':424242,'syntheticCheckerExit':Child.returncode,'actualMainRan':True,'actualQueryRetainedBeforeExport':True,'queryPersistenceFailureInjected':name=='query-write-failure','auditCoherent':obs['actualAuditCoherent'],'auditError':obs['error'],'stageErrors':obs['stageErrors'],'fullUnfilteredAcquisitionAttempted':True,'syntheticOriginalsRetained':2,'finalFailure':failure,'status':'PASS'})
sys.argv=saved_argv
raw=(B/'confirmation-expiry-finalization-r1.py').read_bytes();r={'status':'PASS actual main malformed/missing/wrong-shape audit retention paths, coherent failed-native case; isolated files/injected child and exporter only','cases':rows,'count':len(rows),'actualSource':{'file':'confirmation-expiry-finalization-r1.py','bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()},'scope':'Actual main and real persistence/archive code execute. Path dependency maps only fixed raw acquisition root to unique temporary fixture root. Child/export process dependencies injected; no real checker, native run, xcresult export, process/device query or production proof. Synthetic temp fixtures removed by TemporaryDirectory.','realProcessQueries':real_queries,'checkedAt':time.time()}
p=B/'source257-finalizer-caller-controls-r1.json';assert not p.exists();p.write_text(json.dumps(r,indent=2)+'\n');print(r['status'],r['count'])
