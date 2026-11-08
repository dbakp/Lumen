"""Actual frozen checker call reproducer and isolated correction projection."""
from pathlib import Path
import ast,base64,copy,hashlib,importlib.util,json,time
B=Path(__file__).resolve().parent
sha=lambda x:hashlib.sha256(x).hexdigest()
def module(name,file):
 spec=importlib.util.spec_from_file_location(name,B/file);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
v=module('metadata_diagnostic_validator','legacy-target-change-validation-r3.py');e=module('metadata_diagnostic_evidence','confirmation-lifecycle-evidence-r1.py')
source=(B/'check-confirmation-lifecycle-r1.py').read_bytes();tree=ast.parse(source)
call=next(n for n in ast.walk(tree) if isinstance(n,ast.Expr) and isinstance(n.value,ast.Call) and isinstance(n.value.func,ast.Attribute) and n.value.func.attr=='all_payloads')
actual=compile(ast.fix_missing_locations(ast.Module(body=[call],type_ignores=[])),'actual-frozen-checker-all-payloads','exec')
projected=copy.deepcopy(call);projected.value.args[2]=ast.Subscript(value=ast.Name(id='inputs',ctx=ast.Load()),slice=ast.Constant('app'),ctx=ast.Load())
corrected=compile(ast.fix_missing_locations(ast.Module(body=[projected],type_ignores=[])),'isolated-one-argument-projection','exec')
prior=B/'health-legacy-confirmation-data-source248r1-host-audit.json';real=json.loads(prior.read_bytes());metadata=real['preflight']['app'];cases=[]
base={'preflight':{'app':metadata},'appData':real['appData']}
def check(name,code,state,expected):
 error=None
 try:exec(code,{'v':v,'h':e.h,'state':state,'inputs':{'app':metadata}});accepted=True
 except (AssertionError,TypeError,ValueError) as ex:accepted=False;error=type(ex).__name__+': '+str(ex)
 assert accepted is expected,name
 cases.append({'case':name,'accepted':accepted,'expected':expected,'error':error})
check('actual250call-rejects-genuine-metadata',actual,copy.deepcopy(base),False)
check('projected-fresh-inputs-app-accepts-genuine-metadata',corrected,copy.deepcopy(base),True)
s=copy.deepcopy(base);s['preflight']['app']['sha256']='0'*64;check('projected-rejects-spoofed-app-metadata',corrected,s,False)
s=copy.deepcopy(base);s['arbitraryNull']=copy.deepcopy(metadata);check('projected-rejects-arbitrary-null-payload',corrected,s,False)
s=copy.deepcopy(base);s['arbitraryPayload']={'bytes':1,'sha256':sha(b'x'),'base64':base64.b64encode(b'y').decode()};check('projected-rejects-invalid-payload-hash',corrected,s,False)
check('actual250call-full-retained248-fails',actual,copy.deepcopy(real),False)
check('projected-full-retained248-passes',corrected,copy.deepcopy(real),True)
report={'status':'CONFIRMED frozen250checker wrongargument; isolated one-argument projection passes7controls','actualChecker':{'file':'check-confirmation-lifecycle-r1.py','bytes':len(source),'sha256':sha(source),'callAST':ast.dump(call,include_attributes=False)},'projectionAST':ast.dump(projected,include_attributes=False),'priorRealInput':{'file':prior.name,'sha256':sha(prior.read_bytes())},'validator':{'file':'legacy-target-change-validation-r3.py','sha256':sha((B/'legacy-target-change-validation-r3.py').read_bytes())},'cases':cases,'scope':'Actual frozen250call plus isolated AST projection only; no Source251 source written, sourceReady/currentbuild/native/lateack or simulator acceptance. No old live/raw audit or process/defaults action.','checkedAt':time.time()}
p=B/'source250-checker-metadata-diagnostic-r1.json';assert not p.exists();p.write_text(json.dumps(report,indent=2)+'\n');print(report['status'])
