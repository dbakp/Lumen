"""Actual R2 driver caller AST + its actual exception handler, isolated filesystem."""
import ast,base64,copy,hashlib,importlib.util,json,os,tempfile,time,traceback,types
from pathlib import Path
B=Path(__file__).resolve().parent;source=(B/'confirmation-target-driver-r3.py').read_text();tree=ast.parse(source)
fn=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='confirmation_gate')
main=next(n for n in tree.body if isinstance(n,ast.Try) and any(isinstance(x,ast.Assign) and any(isinstance(t,ast.Subscript) for t in x.targets) for x in n.body))
# The final producer try contains hostSourceVerification; select it explicitly.
main=next(n for n in tree.body if isinstance(n,ast.Try) and 'hostSourceVerification' in ast.unparse(n))
invoke=ast.Try(body=[ast.Expr(value=ast.Call(func=ast.Name(id='confirmation_gate',ctx=ast.Load()),args=[ast.Name(id='group',ctx=ast.Load())],keywords=[]))],handlers=main.handlers,orelse=[],finalbody=[])
module=ast.fix_missing_locations(ast.Module(body=[fn,invoke],type_ignores=[]));code=compile(module,'actual-driver-caller-and-handler','exec')
spec=importlib.util.spec_from_file_location('caller_gate',B/'confirmation-window-evidence-r3.py');gate=importlib.util.module_from_spec(spec);spec.loader.exec_module(gate)
import subprocess
original_processes={k:getattr(subprocess,k) for k in ['Popen','run','check_output','check_call','call']};actual_queries=[]
def denied(*a,**k):actual_queries.append(str(a));raise AssertionError('No real process query in caller controls')
for key in original_processes:setattr(subprocess,key,denied)
real_spec=importlib.util.spec_from_file_location('actual_caller_dependencies',B/'confirmation-target-evidence-r1.py');actual=importlib.util.module_from_spec(real_spec);real_spec.loader.exec_module(actual)
relay_spec=importlib.util.spec_from_file_location('actual_runner_relay',B/'confirmation-runner-relay-r1.py');relay=importlib.util.module_from_spec(relay_spec);relay_spec.loader.exec_module(relay)
assert actual.h.DEVICE=='5C4C4A6C-4D9E-4181-8794-E3925C1A7EA7' and len(actual.h.DATA)==42
required=lambda code:sorted({n.attr for n in ast.walk(ast.parse(code)) if isinstance(n,ast.Attribute) and isinstance(n.value,ast.Attribute) and isinstance(n.value.value,ast.Name) and n.value.value.id=='e' and n.value.attr=='obs'})
missing=lambda code:[name for name in required(code) if not hasattr(actual.obs,name)]
assert missing(source)==[] and missing((B/'confirmation-target-driver-r2.py').read_text())==['OLD']

u='C7ED94D3-DDC6-45DD-ACC9-EC583731AEC7';nonce='ED54372B-AF7D-4972-A183-EDA40AD6C4EB';device='5C4C4A6C-4D9E-4181-8794-E3925C1A7EA7'
proto={'runID':u,'pid':'123','sessionID':nonce,'captureID':u,'nonce':nonce,'appearanceID':u,'domains':'meals','legacyDomains':'meals','omitPhotos':'false'}
native={k:proto[k] for k in ['runID','sessionID','captureID']};native.update(pid=123,status='ready',sequence=3,knownKeyWritten=False,singleUseConsumed=False)
r=lambda x,y,w,h:dict(x=x,y=y,width=w,height=h)
marker={'gate':dict(proto,phase='armed',targetPhase='host-ready'),'scope':'actual-legacy-target-change-during-confirmation-runner-relay','title':'Replace selected data?','body':gate.BODY,'appFrame':r(0,0,402,874),'alertFrame':r(40,345,322,210),'bodyFrame':r(70,390,260,80),'recoverFrame':r(210,490,130,48),'cancelFrame':r(60,490,130,48),'at':time.time(),'attachmentName':'health-legacy-target-change-confirmation-before-mutation','imageBytes':200000,'imageSHA256':'a'*64}
# Deterministic publisher clock for predeclared marker fixtures; no runtime ordering credit.
relay.time=types.SimpleNamespace(time=lambda:marker['at']-0.001)
sha=lambda d:hashlib.sha256(d).hexdigest()
def row(d):return {'bytes':len(d),'sha256':sha(d),'base64':base64.b64encode(d).decode()}
results=[];fixtures=[]
def test(name,kind,data,success=False,parse_failure=True):
 with tempfile.TemporaryDirectory(prefix='lumen247-caller-') as folder:
  root=Path(folder);home=root/'home';group=root/'group';group.mkdir();runner=home/'Library/Developer/CoreSimulator/Devices'/device/'data/Containers/Data/Application'/'00000000-1111-4222-8333-444444444444';(runner/'tmp').mkdir(parents=True)
  class LocalPath(type(Path())):
   @classmethod
   def home(cls):return cls(home)
  gatepath=group/('Lumen-confirmation-window-'+u.lower()+'-'+nonce.lower()+'.json');markerpath=runner/'tmp'/('Lumen-confirmation-ui-'+nonce.lower()+'.json')
  gatepath.write_bytes(data if kind=='gate' else json.dumps(proto).encode());markerpath.write_bytes(data if kind=='marker' else json.dumps(marker).encode());queries=[];order=[];installed={'path':'synthetic-app','sha256':'b'*64};protected={'sentinel':'baseline'}
  state={'runID':u,'boundaries':[{'protected':protected,'installed':installed},{'observation':native}],'nativeStates':[dict(row(json.dumps(native).encode()),value=native)],'started':marker['at']-1,'selection':{'sentinel':'source'}}
  persisted=root/'canonical-state.json'
  def persist():persisted.write_text(json.dumps(state,sort_keys=True))
  def query(command,**kw):
   assert command==['xcrun','simctl','get_app_container',device,'com.dbakp.lumen.LumenUITests.xctrunner','data'];queries.append(command);return str(runner)+'\n'
  def protected_check(group,sink,baseline):assert baseline==protected;order.append('protected');sink['sentinel']='checked'
  def fixed(group,sink,old):assert old==actual.h.DATA;order.append('fixed');sink['fixed']={'sentinel':'actual old Data42'}
  h=types.SimpleNamespace(DEVICE=device,DATA=actual.h.DATA,row=actual.h.row,read=actual.h.read,identity=actual.h.identity,source_exact=lambda selection:order.append('source'),installed=lambda build:installed)
  e=types.SimpleNamespace(protected=protected_check,obs=actual.obs)
  env={'Path':LocalPath,'state':state,'gate':gate,'relay':relay,'base64':base64,'h':h,'e':e,'os':os,'json':json,'time':time,'traceback':traceback,'subprocess':types.SimpleNamespace(check_output=query),'fixed':fixed,'persist':persist,'a':types.SimpleNamespace(build='synthetic-build'),'group':LocalPath(group),'error':None}
  persist();exec(code,env);saved=json.loads(persisted.read_bytes());window=saved.get('confirmationWindow',{})
  ack=list(group.glob('*-ack.json'))
  if success:
   assert env['error'] is None and len(ack)==1 and window['acknowledged'] is True
   assert order==['protected','fixed','source'] and json.loads(ack[0].read_bytes())==gate.validate(proto,native,marker,state['started'],time.time())
  else:
   assert env['error'] and saved['status'].startswith('FAILED') and not ack and not window.get('acknowledged') and not window.get('ackIntended')
   observed=window[kind+'Acquisition']
   if parse_failure:assert observed['status']=='FAILED_IDENTITY_OR_PARSE' and observed['error']
   else:assert observed['status']=='PARSED'
   assert base64.b64decode(window[kind]['base64'],validate=True)==data and observed['rawInputs']==[row(data)]
   assert not order and len(queries)==(0 if kind=='gate' else 1)
  results.append({'name':name,'status':'PASS','acknowledged':bool(ack),'realProcessQueries':0,'mockRunnerQueries':len(queries),'failureRawRetained':not success})
  fixtures.append({'name':name,'input':row(data),'canonicalState':saved,'realProcessQueries':0,'mockRunnerQueries':queries,'preAckCalls':order})
for kind in ['gate','marker']:
 for label,data in [('unfinished',b'{'),('invalidUTF8',b'\xff'),('trailing',b'{}junk'),('array',b'[]'),('null',b'null')]:test(kind+' '+label,kind,data)
for key,value in [('nonce','bad-nonce'),('pid','124'),('domains','workouts'),('unexpected','field')]:
 altered=dict(proto);altered[key]=value;test('gate schema '+key,'gate',json.dumps(altered).encode(),parse_failure=False)
for name,change in [('nonce',lambda x:x['gate'].__setitem__('nonce',u)),('expired',lambda x:x.__setitem__('at',marker['at']-100)),('offscreen',lambda x:x['recoverFrame'].__setitem__('y',1000))]:
 altered=copy.deepcopy(marker);change(altered);test('marker schema '+name,'marker',json.dumps(altered).encode(),parse_failure=False)
test('exact valid caller publishes one ack after all protected checks','marker',json.dumps(marker).encode(),True)
assert not actual_queries
for key,value in original_processes.items():setattr(subprocess,key,value)
archive=json.dumps({'actualObservationModule':Path(actual.obs.__file__).name,'requiredObserverAttributes':required(source),'missingObserverAttributes':missing(source),'old247MissingAttributes':missing((B/'confirmation-target-driver-r2.py').read_text()),'actualOldData42':row(actual.h.DATA),'functionAST':ast.dump(fn,include_attributes=False),'exceptionHandlerAST':[ast.dump(x,include_attributes=False) for x in main.handlers],'fixtures':fixtures}).encode();import gzip
(B/'source248-caller-controls-r1-fixtures.json.gz').write_bytes(gzip.compress(archive,mtime=0));out={'status':'PASS actualR2caller+actualexceptionhandler malformed-gate/marker raw retention and zeroack controls','cases':results,'count':len(results),'sourceSHA256':sha(source.encode()),'archiveDecodedBytes':len(archive),'archiveDecodedSHA256':sha(archive),'scope':'Actual extracted R3caller+exceptionhandler, actual composed observer/Data42, actual predicate/nofollow/relay on isolated files; stub runner/protection/publisherclock dependencies, no real simulator/alert/native/cancellation acceptance','checkedAt':time.time()};(B/'source248-caller-controls-r1.json').write_text(json.dumps(out,indent=2)+'\n');print(len(results),'actual caller controls PASS')
