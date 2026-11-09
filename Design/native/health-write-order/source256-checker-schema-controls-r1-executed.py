"""Actual completion predicates and strict retained marker/native-check segment; no full case claim."""
from pathlib import Path
from types import SimpleNamespace
import ast,base64,copy,gzip,hashlib,importlib.util,json,subprocess,time
B=Path(__file__).resolve().parent

def module(name,file):
 s=importlib.util.spec_from_file_location(name,B/file);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
E=module('schema_evidence','confirmation-lifecycle-evidence-r1.py');H=E.h;V=module('schema_validator','legacy-target-change-validation-r3.py');queries=[]
def denied(*a,**kw):queries.append(str(a));raise AssertionError('No real process query permitted')
for key in ['Popen','run','check_output','check_call','call']:setattr(subprocess,key,denied)
state=json.loads((B/'health-confirmation-notnow-data-source255r1-driver-observations.json').read_bytes());retained=json.loads((B/'health-confirmation-notnow-data-source255r1-retention-state.json').read_bytes());helper=json.loads((B/retained['readbacks'][0]['file']).read_bytes());source=(B/'check-confirmation-lifecycle-r3.py').read_bytes();tree=ast.parse(source);body=next(n for n in tree.body if isinstance(n,ast.Try)).body
start=next(i for i,n in enumerate(body) if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='gate' for t in n.targets));end=next(i for i,n in enumerate(body) if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='expected' for t in n.targets));segment=body[start:end]
rows=[]
def attempt(label,candidate,wanted):
 env={'state':{'confirmationWindow':candidate,'started':state['started'],'boundaries':state['boundaries']},'retained':retained,'helper':helper,'e':E,'h':H,'v':V,'json':json,'time':time}
 error=None
 try:exec(compile(ast.fix_missing_locations(ast.Module(body=copy.deepcopy(segment),type_ignores=[])),'actual-checker-marker-native-segment','exec'),env)
 except (AssertionError,KeyError,TypeError,AttributeError) as x:error=type(x).__name__+': '+str(x)
 assert (error is None)==wanted,(label,error)
 rows.append({'case':label,'accepted':error is None,'failure':error,'status':'PASS'})
window=copy.deepcopy(state['confirmationWindow']);window['hostCheckCompleted']=True
attempt('synthetic completion flag plus actual255 strict marker/check data only',window,True)
for label,value in [('false',False),('integer-one',1),('truthy-string','true'),('truthy-dictionary',{'checked':True})]:
 x=copy.deepcopy(window);x['hostCheckCompleted']=value;attempt('reject completion '+label,x,False)
x=copy.deepcopy(window);x.pop('hostCheckCompleted');attempt('reject missing completion',x,False)
for label,key in [('missing native check','check'),('missing checked marker','checked')]:
 x=copy.deepcopy(window);x.pop(key);attempt('reject '+label,x,False)
x=copy.deepcopy(window);x['checked']=True;attempt('reject marker overwritten by completion Boolean',x,False)
x=copy.deepcopy(window);x['checked']['versions']=[];attempt('reject missing marker payload',x,False)
x=copy.deepcopy(window);x['checked']['versions'][-1]['sha256']='0'*64;attempt('reject tampered raw marker',x,False)
def change(key,mutate):
 x=copy.deepcopy(window);raw=base64.b64decode(x[key]['versions'][-1]['base64'],validate=True);value=json.loads(raw);mutate(value);data=json.dumps(value,sort_keys=True).encode();x[key]['versions'][-1]=H.row(data);return x
attempt('reject checked marker gate spoof',change('checked',lambda x:x['gate'].update(nonce='00000000-0000-0000-0000-000000000000')),False)
attempt('reject native check status',change('check',lambda x:x['check'].update(status='rejected')),False)
attempt('reject native known-write flag',change('check',lambda x:x['check']['nativeFacts']['fixtureFlags'].update(knownKeyWritten=True)),False)
x=copy.deepcopy(window);x['ackBytes']=H.row(b'{}');attempt('reject wrong lateack',x,False)
# All driver owner-closure/final acceptance assertions must use explicit Boolean.
driver=ast.parse((B/'confirmation-lifecycle-driver-r3.py').read_bytes());guards=[n for n in ast.walk(driver) if isinstance(n,ast.Assert) and "state['confirmationWindow']['hostCheckCompleted']" in ast.unparse(n.test)];assert len(guards)==2
for ordinal,guard in enumerate(guards):
 for label,value,wanted in [('true',True,True),('one',1,False),('dictionary',{'raw':'marker'},False),('false',False,False)]:
  accepted=True
  try:exec(compile(ast.fix_missing_locations(ast.Module(body=[copy.deepcopy(guard)],type_ignores=[])),'actual-driver-completion-guard','exec'),{'state':{'confirmationWindow':{'hostCheckCompleted':value,'acknowledged':True}}})
  except AssertionError:accepted=False
  assert accepted==wanted;rows.append({'case':f'driver guard{ordinal} {label}','accepted':accepted,'status':'PASS'})
# Actual current checker source verification, with one virtual byte-tamper negative.
verify=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='verify_checker_source');env={'BASE':B,'h':H,'json':json,'gzip':gzip,'base64':base64};exec(compile(ast.fix_missing_locations(ast.Module(body=[verify],type_ignores=[])),'actual-current-source-verifier','exec'),env);verified=env['verify_checker_source']('durable-source-r256.json');rows.append({'case':'actual current256 archive verification','accepted':True,'status':'PASS'})
read=H.read;checkerpath=B/'check-confirmation-lifecycle-r3.py'
def tampered(path,*a,**kw):
 raw=read(path,*a,**kw);return raw+b'\n' if Path(path)==checkerpath else raw
H.read=tampered
try:
 try:env['verify_checker_source']('durable-source-r256.json')
 except AssertionError:rows.append({'case':'reject virtual currentchecker byte tamper, no file mutation','accepted':False,'status':'PASS'})
 else:raise AssertionError('Tampered checker source accepted')
finally:H.read=read
assert not queries
bindings={}
for n in ['check-confirmation-lifecycle-r3.py','confirmation-lifecycle-driver-r3.py','confirmation-lifecycle-protocol-r1.py']:
 raw=(B/n).read_bytes();bindings[n]={'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()}
r={'status':'PASS actual checker marker/nativecheck/completion/source schema and driver explicit-completion predicates','count':len(rows),'cases':rows,'sources':bindings,'currentSourceVerification':verified,'processQueries':queries,'scope':'Actual checker AST segment from geometry setup through nativeCheck/header validation before three-relay/postCheck/final endpoints checks. Actual255 JSON/native Check as fixture data, plus explicitly synthetic completion flag; NOT a full checker/native pass. Current256 source verifier actually checks full frozen archive; one mocked read byte tamper rejects with no file mutation. All processes denied. Actual255 was failed, oldrawpaths not reopened.','checkedAt':time.time()};p=B/'source256-checker-schema-controls-r1.json';assert not p.exists();p.write_text(json.dumps(r,indent=2)+'\n');print(r['status'],r['count'])
