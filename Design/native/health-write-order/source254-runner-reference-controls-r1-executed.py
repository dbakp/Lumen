"""Actual runner AST/source and readonly prelaunch checks, never xcodebuild."""
from pathlib import Path
import ast,base64,copy,gzip,hashlib,json,re,shutil,subprocess,time
B=Path(__file__).resolve().parent;R=B.parents[2];expected='durable-source-r254.json';sha=lambda x:hashlib.sha256(x).hexdigest();queries=[]
def denied(*a,**kw):queries.append(str(a));raise AssertionError('No subprocess in prelaunch controls')
for key in ['run','Popen','check_output','check_call','call']:setattr(subprocess,key,denied)
rows=[];bindings={};trees={}
def references(file,wanted):
 raw=(B/file).read_bytes();tree=ast.parse(raw);values=[n.value for n in ast.walk(tree) if isinstance(n,ast.Constant) and isinstance(n.value,str) and re.fullmatch(r'durable-source-r\d+\.json(?:\.gz)?',n.value)]
 assert values and all(v in [wanted,wanted+'.gz'] for v in values)
 return tree,values
for tail in ['target-change-native-build-r1-planned.py','debug-release-controls-r1-planned.py','unsigned-release-r1-planned.py']:
 new='source254-'+tail;tree,values=references(new,expected);trees[tail]=tree
 bindings[new]={'bytes':(B/new).stat().st_size,'sha256':sha((B/new).read_bytes())};rows.append({'case':'current reference '+tail,'values':values,'status':'PASS'})
 try:references('source253-'+tail,expected)
 except AssertionError:rows.append({'case':'reject stale253 references '+tail,'status':'PASS'})
 else:raise AssertionError('Stale251 runner accepted')
# Execute real native-prefix statements up to first log-opening/build block.
# Real current manifest/plan/archive/all source/fixture hashes are checked.
for tail in ['target-change-native-build-r1-planned.py','unsigned-release-r1-planned.py']:
 tree=trees[tail];nodes=[]
 for node in tree.body:
  if isinstance(node,ast.With):break
  if tail.startswith('unsigned') and isinstance(node,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='plan' for t in node.targets):break
  nodes.append(node)
 env={'__file__':str(B/('source254-'+tail))};exec(compile(ast.fix_missing_locations(ast.Module(body=nodes,type_ignores=[])),'actual-readonly-runner-prefix','exec'),env)
 manifest=env['m'] if tail.startswith('target') else env['manifest'];assert manifest['source']==expected
 rows.append({'case':'actual readonly prelaunch '+tail,'bindings':len(manifest['files'])+len(manifest['fixtureInputs']),'status':'PASS'})
 # Outcome/receipt fields are evaluated from actual AST, never inferred from filenames.
 fields=[value for d in ast.walk(tree) if isinstance(d,ast.Dict) for key,value in zip(d.keys,d.values) if isinstance(key,ast.Constant) and key.value=='source']
 assert len(fields)==(2 if tail.startswith('target') else 1)
 for field in fields:assert eval(compile(ast.Expression(field),'actual-output-source','eval'),{})==expected
 rows.append({'case':'actual emitted source fields '+tail,'fields':len(fields),'status':'PASS'})
plan=json.loads((B/'health-current-release-source254-r1-predeclared-plan.json').read_bytes());assert plan['source']==expected
binder=trees['debug-release-controls-r1-planned.py'];guard=next(n for n in binder.body if isinstance(n,ast.Assert) and "receipt['source']" in ast.unparse(n))
release=trees['unsigned-release-r1-planned.py'];release_guard=next(n for n in release.body if isinstance(n,ast.Assert) and "manifest['source']" in ast.unparse(n))
native=trees['target-change-native-build-r1-planned.py'];native_guard=next(n for n in native.body if isinstance(n,ast.Assert) and "m['source']" in ast.unparse(n))
def execute_guard(name,node,env,wanted):
 try:exec(compile(ast.fix_missing_locations(ast.Module(body=[node],type_ignores=[])),'actual-source-guard','exec'),env);accepted=True
 except AssertionError:accepted=False
 assert accepted is wanted,name;rows.append({'case':name,'accepted':accepted,'status':'PASS'})
execute_guard('binder current source+plan',guard,{'receipt':{'source':expected,'buildExit':0},'plan':plan},True)
execute_guard('binder wrong receipt',guard,{'receipt':{'source':'durable-source-r249.json','buildExit':0},'plan':plan},False)
execute_guard('binder wrong plan',guard,{'receipt':{'source':expected,'buildExit':0},'plan':dict(plan,source='durable-source-r249.json')},False)
execute_guard('binder failed build',guard,{'receipt':{'source':expected,'buildExit':1},'plan':plan},False)
execute_guard('release current source+plan',release_guard,{'manifest':{'source':expected},'plan':plan},True)
execute_guard('release stale manifest',release_guard,{'manifest':{'source':'durable-source-r248.json'},'plan':plan},False)
execute_guard('native current source',native_guard,{'m':{'source':expected}},True)
execute_guard('native stale manifest',native_guard,{'m':{'source':'durable-source-r249.json'}},False)
native_plan_guard=next(n for n in native.body if isinstance(n,ast.Assert) and ast.unparse(n.test)=="plan['source'] == m['source']")
execute_guard('native matching plan',native_plan_guard,{'m':{'source':expected},'plan':plan},True)
execute_guard('native stale plan',native_plan_guard,{'m':{'source':expected},'plan':dict(plan,source='durable-source-r249.json')},False)
assert not queries
result={'status':'PASS actual3runner source/AST/readonly prelaunch controls; zero subprocess calls','cases':rows,'count':len(rows),'sources':bindings,'actualManifest':expected,'planSHA256':sha((B/'health-current-release-source254-r1-predeclared-plan.json').read_bytes()),'realProcessQueries':queries,'scope':'Actual current native prefix including source+plan+archive/hash/file equality/disk/log-absence and Release prefix before unresolved Debug-bound plan. Actual emittedsource fields and binder/source guards executed as AST fragments; stale253reference controls reject. Does not execute build/logopen/DebugbinarySHA/Releasebinary or claim currentcompile/runtime. Never rerun after native build logfile is created.','checkedAt':time.time()}
p=B/'source254-runner-reference-controls-r1.json';assert not p.exists();p.write_text(json.dumps(result,indent=2)+'\n');print(result['status'],len(rows))
