"""Execute actual caller AST/exception handler using isolated protocol files."""
import ast,base64,copy,gzip,hashlib,importlib.util,json,os,tempfile,time,traceback,types
from pathlib import Path
B=Path(__file__).resolve().parent;source=(B/'confirmation-lifecycle-driver-r2.py').read_text();tree=ast.parse(source)
def module(name,file):
 s=importlib.util.spec_from_file_location(name,B/file);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
v=module('caller_lifecycle_protocol','confirmation-lifecycle-protocol-r1.py');gate=module('caller_lifecycle_regular','confirmation-window-evidence-r3.py');relay=module('caller_lifecycle_transport','confirmation-lifecycle-transport-r1.py')
fns=[n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name in ['observe','confirmation_gate']];assert len(fns)==2
main=next(n for n in tree.body if isinstance(n,ast.Try) and 'hostSourceVerification' in ast.unparse(n))
invoke=ast.Try(body=[ast.Expr(ast.Call(ast.Name('confirmation_gate',ast.Load()),[ast.Name('group',ast.Load())],[]))],handlers=main.handlers,orelse=[],finalbody=[])
code=compile(ast.fix_missing_locations(ast.Module(body=fns+[invoke],type_ignores=[])),'actual-lifecycle-caller','exec')
sha=lambda x:hashlib.sha256(x).hexdigest();row=lambda x:{'bytes':len(x),'sha256':sha(x),'base64':base64.b64encode(x).decode()}
u='11111111-1111-4111-8111-111111111111';n='22222222-2222-4222-8222-222222222222';gen='33333333-3333-4333-8333-333333333333';clock=time.time()-30
proto={'runID':u,'pid':'123','sessionID':n,'captureID':u,'nonce':n,'appearanceID':gen,'domains':'meals','legacyDomains':'meals','omitPhotos':'false'}
armed=dict(proto,taskGeneration=gen,phase='armed',targetPhase='host-ready')
trace={'verificationProtocol':v.PROTOCOL,'binding':proto,'taskGeneration':gen,'checks':[],'problems':[],
 'events':[{'event':'created','at':clock+1},{'event':'wait-started','at':clock+2,'taskCancelled':False,'closed':False,'consumed':False,'controlCancelled':False},
 {'event':'closed','at':clock+4,'reason':'not-now','closed':True,'consumed':False,'controlCancelled':True},
 {'event':'wait-exit','at':clock+5,'errorType':'CancellationError','taskCancelled':True,'closed':True,'consumed':False,'controlCancelled':True},
 {'event':'task-value-completed','at':clock+6}]}
r=lambda x,y,w,h:dict(x=x,y=y,width=w,height=h)
presented={'scope':'actual-confirmation-notnow-before-late-ack','phase':'presented','gate':armed,'at':clock+3,'attachmentName':'health-confirmation-notnow-presented','imageBytes':200000,'imageSHA256':'a'*64,'title':'Replace selected data?','body':gate.BODY,'appFrame':r(0,0,402,874),'alertFrame':r(40,345,322,210),'bodyFrame':r(70,390,260,80),'recoverFrame':r(210,490,130,48),'cancelFrame':r(60,490,130,48)}
dismissed={'scope':presented['scope'],'phase':'dismissed','gate':armed,'at':clock+7,'attachmentName':'health-confirmation-notnow-not-now-choices','imageBytes':200000,'imageSHA256':'b'*64,'touchAt':clock+3.5,'tapReturnedAt':clock+4.5,'cancelFrame':presented['cancelFrame'],'alertDismissed':True,'choiceValues':['1','0','0']}
cases=[];fixtures=[]
def test(name,mutate=None,expected='error'):
 with tempfile.TemporaryDirectory(prefix='lumen251-caller-') as temp:
  root=Path(temp);group=root/'group';group.mkdir();runner=root/'runner';(runner/'tmp').mkdir(parents=True)
  paths={'gate':group/('Lumen-confirmation-window-'+u.lower()+'-'+n.lower()+'.json'),'trace':group/('Lumen-confirmation-lifecycle-'+u.lower()+'-'+n.lower()+'.json'),'presented':runner/'tmp'/('Lumen-confirmation-lifecycle-ui-'+n.lower()+'-presented.json'),'dismissed':runner/'tmp'/('Lumen-confirmation-lifecycle-ui-'+n.lower()+'-dismissed.json')}
  values=copy.deepcopy(dict(gate=proto,trace=trace,presented=presented,dismissed=dismissed))
  if mutate:mutate(values)
  for key,path in paths.items():
   value=values[key]
   if value is not None:path.write_bytes(value if type(value) is bytes else json.dumps(value).encode())
  native={k:proto[k] for k in ['runID','sessionID','captureID']};native.update(pid=123,status='ready',sequence=3,knownKeyWritten=False,singleUseConsumed=False)
  state={'runID':u,'oldSession':n,'started':clock,'selection':{'source':'stub'},'boundaries':[{'protected':{'sentinel':'baseline'}},{}],'nativeStates':[{'value':native}], 'confirmationWindow':{'runner':str(runner)}}
  saved=root/'state.json';order=[]
  def persist():saved.write_text(json.dumps(state,sort_keys=True))
  def preserve(group,sink,value,data,selection):order.append('protected-fixed-source-installed');sink['stubbedProtection']=True
  def denied(*a,**kw):raise AssertionError('No process queries in isolated caller')
  h=types.SimpleNamespace(DATA=b'original42',row=row,read=gate.regular,identity=lambda p:{'mode':Path(p).lstat().st_mode})
  e=types.SimpleNamespace(origin_trace=lambda group,index,old: [{'event':'stub-ready'}])
  env={'Path':Path,'state':state,'gate':gate,'relay':relay,'v':v,'base64':base64,'h':h,'e':e,'os':os,'json':json,'time':time,'traceback':traceback,'subprocess':types.SimpleNamespace(check_output=denied),'preserved':preserve,'persist':persist,'a':types.SimpleNamespace(build='stub-build'),'group':group,'error':None}
  # Real orchestration first sees an active waiter and arms UI before the
  # synthetic later dismissal/completion inputs are made visible.
  if expected!='created-pending':
   original={k:(p.read_bytes() if p.exists() else None) for k,p in paths.items()}
   paths['gate'].write_text(json.dumps(proto));initial=copy.deepcopy(trace);initial['events']=initial['events'][:2]
   paths['trace'].write_text(json.dumps(initial))
   for key in ['presented','dismissed']:
    if paths[key].exists():paths[key].unlink()
   persist();exec(code,env);assert env['error'] is None and len(state['confirmationWindow']['relays'])==1
   for key,p in paths.items():
    if original[key] is None:
     if p.exists():p.unlink()
    else:p.write_bytes(original[key])
  persist();exec(code,env);stored=json.loads(saved.read_bytes());window=stored['confirmationWindow'];acks=list(group.glob('*-ack.json'))
  if expected=='ack':
   assert env['error'] is None and len(acks)==1 and window['acknowledged'] and len(window['relays'])==2
   assert order==['protected-fixed-source-installed'] and json.loads(acks[0].read_bytes())=={**{k:proto[k] for k in ['runID','pid','sessionID','captureID','nonce']},'phase':'ui-observed'}
  else:
   assert not acks and not window.get('ackIntended') and not order
   assert bool(env['error']) is (expected=='error')
   if expected=='created-pending':assert not window.get('relays')
  cases.append({'case':name,'expected':expected,'actualAck':bool(acks),'status':'PASS'})
  fixtures.append({'case':name,'state':stored,'protectionCalls':order,'realQueries':0})
test('created-only-does-not-arm-UI',lambda x:x['trace'].update(events=x['trace']['events'][:1]),expected='created-pending')
test('valid-completed-cancel-before-one-late-ack',expected='ack')
test('missing-completion-is-pending',lambda x:x['trace']['events'].pop(),expected='pending')
test('missing-dismissed-is-pending',lambda x:x.update(dismissed=None),expected='pending')
for name,mutate in [
 ('malformed-gate',lambda x:x.update(gate=b'{')),
 ('malformed-trace',lambda x:x.update(trace=b'[]')),
 ('malformed-presented',lambda x:x.update(presented=b'\xff')),
 ('malformed-dismissed',lambda x:x.update(dismissed=b'{')),
 ('wrong-closed-reason',lambda x:x['trace']['events'][2].update(reason='presentation-change')),
 ('task-not-cancelled',lambda x:x['trace']['events'][3].update(taskCancelled=False)),
 ('wrong-nonce',lambda x:x['trace']['binding'].update(nonce=u)),
 ('dismissed-before-touch',lambda x:x['dismissed'].update(at=clock+1)),
 ('wrong-retained-choices',lambda x:x['dismissed'].update(choiceValues=['0','0','0'])),
 ('outside-modal',lambda x:x['presented']['recoverFrame'].update(y=999))]:test(name,mutate)
raw=json.dumps({'sourceSHA256':sha(source.encode()),'actualFunctionAST':[ast.dump(n,include_attributes=False) for n in fns],'actualExceptionHandlerAST':[ast.dump(n,include_attributes=False) for n in main.handlers],'fixtures':fixtures}).encode();fixture='source251-lifecycle-caller-controls-r1-fixtures.json.gz';assert not (B/fixture).exists();(B/fixture).write_bytes(gzip.compress(raw,mtime=0))
result={'status':'PASS actual caller/actual exception handler isolated controls','cases':cases,'count':len(cases),'sourceSHA256':sha(source.encode()),'fixture':fixture,'decodedBytes':len(raw),'decodedSHA256':sha(raw),'scope':'Actual caller+raw reader+protocol/publisher/outer handler on isolated files, runner preseeded/protection+fixed/source+installed stubbed. No actual native/UI/app/preferences/process acceptance.','checkedAt':time.time()};out=B/'source251-lifecycle-caller-controls-r1.json';assert not out.exists();out.write_text(json.dumps(result,indent=2)+'\n');print(result['status'],len(cases))
