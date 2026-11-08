import ast,pathlib,tempfile,shutil,json,hashlib,types,subprocess,gzip,time,uuid,stat,contextlib,io
P=pathlib.Path('Design/native/health-write-order');driver_name='Design/native/health-write-order/health-legacy-root-acquisition-driver-r1.py';old=json.loads(gzip.decompress((P/'durable-source-r209.json.gz').read_bytes()))['files'][driver_name];candidate=P/'health-legacy-root-acquisition-driver-r1.py';new=candidate.read_text();root=pathlib.Path(tempfile.mkdtemp(prefix='Lumen210LateSafetyFlag-'))
try:
 def execute(source,label):
  base=root/label;base.mkdir();canonical=base/'canonical';canonical.mkdir();raw=base/'raw';raw.mkdir();data=base/'data';(data/'tmp').mkdir(parents=True);group=base/'group';group.mkdir();current=group/'LumenData';run_id=str(uuid.uuid4()).upper();products=base/'products';test=products/'Runner.app/PlugIns/Test.xctest/Test';test.parent.mkdir(parents=True);test.write_bytes(b'synthetic test');app=products/'Lumen.app/Lumen';app.parent.mkdir();app.write_bytes(b'synthetic app');h=lambda b:hashlib.sha256(b).hexdigest();state={'assessed':False,'failed':False,'polls':0,'clock':0.0,'acks':[]};absent={'root':{'exists':False},'entries':{}}
  args=types.SimpleNamespace(source='source.json',build='build.json',case='no-prior',trial='Flag'+label,expect='safe');(canonical/'source.json').write_text('{}');(canonical/'build.json').write_text(json.dumps({'source':'source.json','buildExit':0,'testBinary':str(test),'binaryBytes':app.stat().st_size,'sha256':h(app.read_bytes()),'testBinaryBytes':test.stat().st_size,'testBinarySHA256':h(test.read_bytes())}))
  prepared={'mode':'legacy-root-missing-no-prior','runID':run_id,'phase':'prepared','paths':{'root':str(current),'previous':str(group/'LumenData.previous'),'moved':str(group/('LumenData.legacy-root-probe-'+run_id)),'movedPrevious':str(group/('LumenData.legacy-prior-probe-'+run_id))},'initialRoot':absent,'initialPrevious':absent,'initialFixed':{},'leaseReady':True};observed={**prepared,'phase':'observed','finalRoot':absent,'finalPrevious':absent,'movedRoot':absent,'movedPrevious':absent};native=data/'tmp/Lumen-legacy-root-probe-report.json';native.write_text(json.dumps(prepared))
  class Parser:
   def add_argument(self,*a,**k):pass
   def parse_args(self):return args
  class Process:
   pid=999998
   def poll(self):
    if state['failed']:
     state['polls']+=1;return None if state['polls']<=2 else 65
    return None
   def wait(self,**kw):return 65
   def terminate(self):raise AssertionError('unexpected forced termination')
   def kill(self):raise AssertionError('unexpected forced kill')
  def write(path,value):
   pathlib.Path(path).write_text(json.dumps(value))
   if str(path).endswith('-host-failure.json'):state['failed']=True
   if pathlib.Path(path).name=='Lumen-legacy-root-probe-ack.json':
    state['acks'].append(value['phase']);assert value['phase']=='prepared';native.write_text(json.dumps(observed))
  def manifest_verify(m):
   if state['assessed']:raise RuntimeError('injected hostfailure after preliminary safe judgment')
  def assess(report,args,evidence):evidence['safetyAcceptance']=True;state['assessed']=True
  def cmd(*a):return str(data) if a[-1]=='data' else str(app.parent) if a[-1]=='app' else str(group)
  def sleep(dt):state['clock']+=dt
  ns=dict(argparse=types.SimpleNamespace(ArgumentParser=Parser),pathlib=types.SimpleNamespace(Path=lambda v:raw if str(v)=='/tmp/LumenBatch44Checks' else pathlib.Path(v)),P=canonical,REPO=base,MODES={'no-prior':('legacy-root-missing-no-prior','NoPrior')},SIM='synthetic',sha=h,read=lambda p:json.loads(pathlib.Path(p).read_text()),write=write,manifest_verify=manifest_verify,exact_payload_rows=lambda r:0,live_tree=lambda p:absent,verify_fixed_keys=lambda *a,**k:[],assess_observed=assess,retain_terminal=lambda *a:[],cmd=cmd,uuid=uuid,json=json,stat=stat,time=types.SimpleNamespace(time=lambda:1000+state['clock'],monotonic=lambda:state['clock'],sleep=sleep),subprocess=types.SimpleNamespace(Popen=lambda *a,**k:Process(),STDOUT=-2,CalledProcessError=subprocess.CalledProcessError,TimeoutExpired=subprocess.TimeoutExpired),gzip=gzip)
  tree=ast.Module(body=[next(n for n in ast.parse(source).body if isinstance(n,ast.FunctionDef) and n.name=='main')],type_ignores=[]);exec(compile(tree,label,'exec'),ns)
  with contextlib.redirect_stdout(io.StringIO()):code=ns['main']()
  result=json.loads(next(canonical.glob('*-outcome.json')).read_text());assert code==1 and result['driverExitCode']==1 and state['acks']==['prepared'] and 'injected hostfailure' in result['error'];assert result['nativeFinalizedNaturallyAfterHostFailure'] and not result.get('failureFinalizationReadErrors');return {'driverExitCode':1,'status':result['status'],'safetyAcceptance':result['safetyAcceptance'],'acknowledgedPhases':state['acks'],'lateHostFailurePreserved':True,'retentionErrorsInjected':False}
 baseline=execute(old,'baseline209');fixed=execute(new,'fixed210');assert baseline['safetyAcceptance'] is True and fixed['safetyAcceptance'] is False
 report={'status':'PASS isolated late-host-failure flag regression; no native/product acceptance','baselineSource':'durable-source-r209.json.gz','baselineDriverSHA256':hashlib.sha256(old.encode()).hexdigest(),'candidateDriverBytes':candidate.stat().st_size,'candidateDriverSHA256':hashlib.sha256(candidate.read_bytes()).hexdigest(),'baseline':baseline,'fixed':fixed,'scope':'Exact old/new main ASTs with fake source/installed/live/mode/native/retention endpoints and real known temporary files. Mode stub deliberately sets preliminarytrue; later source-check fault, successfuldiagnostic retention and noobservedack isolateP58F1. No actual safe-recovery/authority/exporter behavior proved. Fixtures deleted after compact result.','checkedAt':time.time()};(P/'source210-late-safety-flag-check-r1.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
finally:shutil.rmtree(root)
