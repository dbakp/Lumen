"""Execute actual corrected checker preflight guard and all_payloads call."""
from pathlib import Path
import ast,base64,copy,gzip,hashlib,importlib.util,json,time
B=Path(__file__).resolve().parent;sha=lambda x:hashlib.sha256(x).hexdigest()
def module(name,file):
 spec=importlib.util.spec_from_file_location(name,B/file);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
v=module('checker_api_validator','legacy-target-change-validation-r3.py');e=module('checker_api_evidence','confirmation-lifecycle-evidence-r1.py')
source=(B/'check-confirmation-lifecycle-r2.py').read_bytes();tree=ast.parse(source)
call=next(n for n in ast.walk(tree) if isinstance(n,ast.Expr) and isinstance(n.value,ast.Call) and isinstance(n.value.func,ast.Attribute) and n.value.func.attr=='all_payloads')
assert ast.unparse(call)=="v.all_payloads(state, h, inputs['app'])"
guard=next(n for n in ast.walk(tree) if isinstance(n,ast.Assert) and ast.unparse(n.test)=="state['preflight'] == inputs")
code=compile(ast.fix_missing_locations(ast.Module(body=[guard,call],type_ignores=[])),'actual-corrected-checker-API-fragment','exec')
prior=B/'health-legacy-confirmation-data-source248r1-host-audit.json';original=json.loads(prior.read_bytes());inputs=copy.deepcopy(original['preflight']);cases=[];fixtures=[]
def check(name,state,wanted=True,expected_inputs=inputs):
 error=None
 try:exec(code,{'v':v,'h':e.h,'state':state,'inputs':expected_inputs});accepted=True
 except (AssertionError,TypeError,ValueError,KeyError) as ex:accepted=False;error=type(ex).__name__+': '+str(ex)
 assert accepted is wanted,name
 cases.append({'case':name,'expectedAccepted':wanted,'actualAccepted':accepted,'error':error})
 fixtures.append({'case':name,'state':state,'expectedInputs':expected_inputs,'accepted':accepted})
base={'preflight':copy.deepcopy(inputs),'appData':original['appData']}
check('genuine-retained-preflight-exact-null-exception',copy.deepcopy(base))
check('full-genuine-retained248-state',copy.deepcopy(original))
for label,mutate in [
 ('app-string-instead-of-metadata',lambda x:x['preflight'].update(app=x['appData'])),
 ('spoofed-app-hash',lambda x:x['preflight']['app'].update(sha256='0'*64)),
 ('spoofed-app-size',lambda x:x['preflight']['app'].update(bytes=1)),
 ('spoofed-app-base64',lambda x:x['preflight']['app'].update(base64='eA==')),
 ('missing-preflight',lambda x:x.pop('preflight')),
 ('arbitrary-null-payload',lambda x:x.update(other=copy.deepcopy(inputs['app']))),
 ('null-at-wrong-path',lambda x:x.update(preflightCopy={'app':copy.deepcopy(inputs['app'])})),
 ('bad-payload-bytes',lambda x:x.update(other={'bytes':2,'sha256':sha(b'x'),'base64':'eA=='})),
 ('bad-payload-hash',lambda x:x.update(other={'bytes':1,'sha256':sha(b'y'),'base64':'eA=='})),
 ('bad-payload-base64',lambda x:x.update(other={'bytes':1,'sha256':sha(b'x'),'base64':'!!!'}))]:
 s=copy.deepcopy(base);mutate(s);check(label,s,False)
check('wrong-independently-supplied-metadata',copy.deepcopy(base),False,dict(inputs,app=dict(inputs['app'],sha256='f'*64)))
check('wrong-independently-supplied-path',copy.deepcopy(base),False,dict(inputs,app=original['appData']))
raw=json.dumps({'checkerSHA256':sha(source),'guardAST':ast.dump(guard,include_attributes=False),'callAST':ast.dump(call,include_attributes=False),'cases':fixtures}).encode();fixture='source251-checker-api-controls-r1-fixtures.json.gz';assert not (B/fixture).exists();(B/fixture).write_bytes(gzip.compress(raw,mtime=0))
result={'status':'PASS actual corrected checker preflight+payload API fragment','count':len(cases),'cases':cases,'checker':{'file':'check-confirmation-lifecycle-r2.py','bytes':len(source),'sha256':sha(source)},'fixture':fixture,'decodedBytes':len(raw),'decodedSHA256':sha(raw),'priorRealInput':{'file':prior.name,'sha256':sha(prior.read_bytes())},'scope':'Actual corrected checker AST preflight equality+all_payloads call on genuine historical248retained facts and explicit negatives, expected metadata isolated from copied state; no fresh currentbinary verification, new native/checker endtoend, defaults/process or oldraw audit acceptance.','checkedAt':time.time()}
p=B/'source251-checker-api-controls-r1.json';assert not p.exists();p.write_text(json.dumps(result,indent=2)+'\n');print(result['status'],len(cases))
