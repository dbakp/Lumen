import ast,pathlib,tempfile,shutil,json,hashlib,types,subprocess,gzip,time,uuid,os,base64,stat,contextlib,io
candidate=pathlib.Path('/tmp/lumen209-driver.py');tree=ast.Module(body=[next(n for n in ast.parse(candidate.read_text()).body if isinstance(n,ast.FunctionDef) and n.name=='main')],type_ignores=[])
root=pathlib.Path(tempfile.mkdtemp(prefix='Lumen209KnownPhaseChecks-'));checks=[]
try:
 def execute(case):
  base=root/case;base.mkdir();canon=base/'canonical';canon.mkdir();raw=base/'raw';raw.mkdir();data=base/'data';(data/'tmp').mkdir(parents=True);group=base/'group';group.mkdir();current=group/'LumenData';run_id=str(uuid.uuid4()).upper();products=base/'products';test=products/'Runner.app/PlugIns/Test.xctest/Test';test.parent.mkdir(parents=True);test.write_bytes(b'known synthetic test executable');app=products/'Lumen.app/Lumen';app.parent.mkdir();app.write_bytes(b'known synthetic app executable');h=lambda b:hashlib.sha256(b).hexdigest();state={'dataQueries':0,'installedQueries':0,'hostFailure':False,'pollsAfterFailure':0,'clock':0.0}
  args=types.SimpleNamespace(source='source.json',build='build.json',case='no-prior',trial='Isolated'+case,expect='mutation')
  (canon/'source.json').write_text('{}');(canon/'build.json').write_text(json.dumps({'source':'source.json','buildExit':0,'testBinary':str(test),'binaryBytes':app.stat().st_size,'sha256':h(app.read_bytes()),'testBinaryBytes':test.stat().st_size,'testBinarySHA256':h(test.read_bytes())}))
  report={'mode':'legacy-root-missing-no-prior','runID':run_id,'phase':'observed' if case=='order' else 'prepared','paths':{'root':str(current),'previous':str(group/'LumenData.previous'),'moved':str(group/('LumenData.legacy-root-probe-'+run_id)),'movedPrevious':str(group/('LumenData.legacy-prior-probe-'+run_id))},'initialRoot':{},'initialPrevious':{},'initialFixed':{},'leaseReady':True};report_file=data/'tmp/Lumen-legacy-root-probe-report.json';report_file.write_text(json.dumps(report))
  class Parser:
   def add_argument(self,*a,**k):pass
   def parse_args(self):return args
  class Process:
   pid=999999
   def poll(self):
    if state['hostFailure']:
     state['pollsAfterFailure']+=1
     return None if state['pollsAfterFailure']<=2 else 65
    return None
   def wait(self,**kw):return 65
   def terminate(self):raise AssertionError('unexpected forced termination')
   def kill(self):raise AssertionError('unexpected forced kill')
  def cmd(*argv):
   kind=argv[-1]
   if kind=='data':
    state['dataQueries']+=1
    if state['dataQueries']>1:raise RuntimeError('known phase incorrectly retried discovery')
    return str(data)
   if kind=='app':
    state['installedQueries']+=1
    if case=='query':raise subprocess.CalledProcessError(7,['known synthetic installed query'])
    return str(app.parent)
   if kind=='group.com.dbakp.lumen':return str(group)
   raise AssertionError(argv)
  def live_tree(path):
   if case=='file':raise FileNotFoundError('injected known-phase child disappearance')
   return {}
  def fixed(*a,**kw):
   if case=='decode':raise json.JSONDecodeError('injected known-phase report decode','!',0)
   return []
  def write(path,value):
   pathlib.Path(path).write_text(json.dumps(value))
   if str(path).endswith('-host-failure.json'):state['hostFailure']=True
  def path_factory(value):return raw if str(value)=='/tmp/LumenBatch44Checks' else pathlib.Path(value)
  def sleep(dt):state['clock']+=dt
  ns=dict(argparse=types.SimpleNamespace(ArgumentParser=Parser),pathlib=types.SimpleNamespace(Path=path_factory),P=canon,REPO=base,MODES={'no-prior':('legacy-root-missing-no-prior','NoPrior')},SIM='synthetic',sha=h,read=lambda p:json.loads(pathlib.Path(p).read_text()),write=write,manifest_verify=lambda m:None,exact_payload_rows=lambda r:0,live_tree=live_tree,verify_fixed_keys=fixed,assess_observed=lambda *a:None,retain_terminal=lambda *a:[],cmd=cmd,uuid=uuid,json=json,stat=stat,time=types.SimpleNamespace(time=lambda:1000+state['clock'],monotonic=lambda:state['clock'],sleep=sleep),subprocess=types.SimpleNamespace(Popen=lambda *a,**k:Process(),STDOUT=-2,CalledProcessError=subprocess.CalledProcessError,TimeoutExpired=subprocess.TimeoutExpired),gzip=gzip)
  exec(compile(tree,str(candidate),'exec'),ns)
  with contextlib.redirect_stdout(io.StringIO()):code=ns['main']()
  out=json.loads(next(canon.glob('*-outcome.json')).read_text());assert code==1 and out['driverExitCode']==1 and state['dataQueries']==1 and not (data/'tmp/Lumen-legacy-root-probe-ack.json').exists();assert out['nativeFinalizedNaturallyAfterHostFailure'] and not out.get('forcedTerminationAfterGrace') and not out.get('failureFinalizationReadErrors') and len(out['failureFinalizationReports'])==1
  expected={'file':'FileNotFoundError','query':'CalledProcessError','decode':'JSONDecodeError','order':'observed phase without actual prepared acknowledgement'}[case];assert expected in out['error'],out['error']
  if case=='order':assert state['installedQueries']==0
  return {'fault':case,'failure':out['error'],'discoveryQueries':state['dataQueries'],'ackSent':False,'simulatedNaturalFinalization':True,'originalAppReportSalvaged':True}
 for case in ['file','query','decode','order']:checks.append(execute(case))
 report={'status':'PASS four exact-main orchestration fault checks; no simulator/native/product credit','candidateDriverBytes':candidate.stat().st_size,'candidateDriverSHA256':hashlib.sha256(candidate.read_bytes()).hexdigest(),'checks':checks,'scope':'Exact current main AST with fake native/tool/source-validation/retention endpoints and only known synthetic temporary files. Tests known-phase error routing, no rediscovery/ack and simulated natural finalization, not actual native failure/export/identity behavior. Raw output destination redirected to temporary fixture root via injected Path factory; main AST unchanged. Fixtures deleted after compact result.','checkedAt':time.time()};pathlib.Path('/tmp/lumen209-orchestration-check-result.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
finally:shutil.rmtree(root)
