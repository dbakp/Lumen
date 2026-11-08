import ast,pathlib,tempfile,shutil,json,hashlib,types,plistlib,base64,time,stat
candidate=pathlib.Path('/tmp/lumen208-driver.py');node=next(x for x in ast.parse(candidate.read_text()).body if isinstance(x,ast.FunctionDef) and x.name=='verify_fixed_keys');tree=ast.Module(body=[node],type_ignores=[])
root=pathlib.Path(tempfile.mkdtemp(prefix='Lumen208FixedPreferencesChecks-'));checks=[];expected={k:{'type':'data','bytes':42,'sha256':hashlib.sha256(b'{synthetic persisted legacy origin damaged').hexdigest(),'base64':base64.b64encode(b'{synthetic persisted legacy origin damaged').decode()} for k in ['lumen.health.meals.v1','lumen.health.workouts.v1']}
try:
 def execute(case,scenario):
  base=root/case;base.mkdir();data=base/'data';(data/'Library/Preferences').mkdir(parents=True);(data/'tmp').mkdir();out=base/'output';out.mkdir();file=data/'Library/Preferences/com.dbakp.lumen.plist';values={};clock=[0.0];sleeps=[0]
  if scenario=='changed':values={k:b'changed' for k in expected}
  file.write_bytes(plistlib.dumps(values));(data/'tmp/Lumen-legacy-root-probe-report.json').write_text(json.dumps({'runID':'known-run','phase':'failed' if scenario=='phasechanged' else 'prepared'}))
  def sleep(dt):
   clock[0]+=dt;sleeps[0]+=1
   if scenario=='eventual' and sleeps[0]==2:file.write_bytes(plistlib.dumps({k:base64.b64decode(v['base64']) for k,v in expected.items()}))
  ns=dict(pathlib=pathlib,json=json,stat=stat,plistlib=plistlib,base64=base64,P=out,sha=lambda b:hashlib.sha256(b).hexdigest(),time=types.SimpleNamespace(monotonic=lambda:clock[0],time=lambda:clock[0],sleep=sleep),write=lambda p,d:pathlib.Path(p).write_text(json.dumps(d)),read=lambda p:json.loads(pathlib.Path(p).read_text()))
  exec(compile(tree,str(candidate),'exec'),ns);error=None;rows=None
  try:rows=ns['verify_fixed_keys'](data,expected,'observed' if scenario=='observed' else 'prepared',case,'known-run',types.SimpleNamespace(poll=lambda:None),hashlib.sha256((data/'tmp/Lumen-legacy-root-probe-report.json').read_bytes()).hexdigest())
  except Exception as ex:error=ex
  return out,sleeps[0],rows,error
 out,n,rows,err=execute('eventual','eventual');assert err is None and n==2 and [r['status'] for r in rows]==['missing','missing','exact'];checks.append('Absent prepared keys become exact: all three actual file observations retained before return')
 out,n,rows,err=execute('changed','changed');assert isinstance(err,AssertionError) and n==0 and json.loads(next(out.glob('*.json')).read_text())[0]['status']=='changed';checks.append('Present changed Data rejects immediately and retains first mismatch; no waiting')
 out,n,rows,err=execute('observed','observed');assert isinstance(err,AssertionError) and n==0;checks.append('Observed-boundary missing keys reject immediately; no waiting')
 out,n,rows,err=execute('bounded','bounded');assert isinstance(err,TimeoutError) and n==120;checks.append('Prepared absent keys time out at declared30second bound with all121samples retained; simulated clock only')
 out,n,rows,err=execute('phase','phasechanged');assert isinstance(err,AssertionError) and n==0;checks.append('Changed native phase rejects before wait/ack')
 report={'status':'PASS five isolated fixed-preference observation checks; no native/product acceptance','candidateDriverBytes':candidate.stat().st_size,'candidateDriverSHA256':hashlib.sha256(candidate.read_bytes()).hexdigest(),'checks':checks,'scope':'Exact helper AST with real temporary known synthetic plist files, injected clock/process and native phase report; no actual CFPreferences mechanism or simulator result proved. Fixtures deleted after compact result.','checkedAt':time.time()};pathlib.Path('/tmp/lumen208-fixed-check-result.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
finally:shutil.rmtree(root)
