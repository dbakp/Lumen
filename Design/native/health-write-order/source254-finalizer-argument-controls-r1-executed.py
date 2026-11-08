"""Pure actual builder controls using retained253 inputs, never old live audits."""
from pathlib import Path
import ast,copy,hashlib,importlib.util,json,subprocess,time
B=Path(__file__).resolve().parent;queries=[]
def deny(*a,**kw):queries.append(str(a));raise AssertionError('No process query permitted')
for name in ['Popen','run','check_output','check_call','call']:setattr(subprocess,name,deny)
s=importlib.util.spec_from_file_location('actual_lifecycle_finalizer',B/'confirmation-lifecycle-finalization-r2.py');m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
state=json.loads((B/'health-confirmation-notnow-data-source253r1-driver-observations.json').read_bytes());out=json.loads((B/'health-confirmation-notnow-data-source253r1-outcome.json').read_bytes());plan={'source':state['source'],'build':state['build'],'nativeTrial':'Source253R1','prefix':'health-confirmation-notnow-data-source253r1','rawStem':'HealthConfirmationNotNowDataSource253R1','checkerTrial':'HistoricalControlOnly'}
expected=['python3',str(B/'check-confirmation-lifecycle-r2.py'),plan['prefix'],'--checker-source',state['source'],'--case-source',state['source'],'--build',state['build'],'--trial',plan['checkerTrial']]
rows=[]
def check(label,p,s,o,accept):
 try:command=m.checker_command(B,p,s,o);actual=True
 except AssertionError:command=None;actual=False
 assert actual==accept,label
 rows.append({'case':label,'accepted':actual,'command':command})
check('actual retained253 correct arguments, no execution',plan,state,out,True);assert rows[-1]['command']==expected
for label,path,value in [('case source',['source'],'durable-source-r252.json'),('host source',['hostSource'],'durable-source-r252.json'),('preflight source',['preflight','source'],'durable-source-r252.json'),('host verification source',['hostSourceVerification','source'],'durable-source-r252.json'),('build',['build'],'health-target-change-source252-r1-build.json'),('preflight build',['preflight','build'],'health-target-change-source252-r1-build.json'),('result bundle',['command'],['xcodebuild','-resultBundlePath','/tmp/LumenBatch44Checks/HealthConfirmationNotNowDataSource252R1.xcresult']),('duplicate bundle arg',['command'],state['command']+['-resultBundlePath','invalid'])]:
 x=copy.deepcopy(state);target=x
 for key in path[:-1]:target=target[key]
 target[path[-1]]=value;check('reject '+label,plan,x,out,False)
for field,value in [('source','durable-source-r252.json'),('build','health-target-change-source252-r1-build.json'),('prefix','health-confirmation-notnow-data-source252r1'),('rawStem','HealthConfirmationNotNowDataSource252R1'),('nativeTrial','Source252R1'),('checkerTrial','../unsafe')]:
 p=dict(plan);p[field]=value;check('reject plan '+field,p,state,out,False)
for field,value in [('source','durable-source-r252.json'),('build','health-target-change-source252-r1-build.json')]:
 o=dict(out);o[field]=value;check('reject outcome '+field,plan,state,o,False)
future=json.loads((B/'source254-check-acquisition-finalization-r1-plan.json').read_bytes());fs=copy.deepcopy(state);fo=copy.deepcopy(out)
for target in [fs,fo,fs['preflight']]:target.update(source=future['source'],build=future['build'])
fs['hostSource']=future['source'];fs['hostSourceVerification']['source']=future['source'];fs['command'][fs['command'].index('-resultBundlePath')+1]='/tmp/LumenBatch44Checks/'+future['rawStem']+'.xcresult'
check('synthetic coherent254 argument fixture only',future,fs,fo,True)
raw=(B/'confirmation-lifecycle-finalization-r2.py').read_bytes();tree=ast.parse(raw);main=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='main');calls=[(n.lineno,ast.unparse(n.func)) for n in ast.walk(main) if isinstance(n,ast.Call)]
line=lambda f:min(n for n,name in calls if name==f)
assert line('checker_command')<line('subprocess.Popen')<line('proc.communicate')<line('subprocess.run')
# Checker failure is not asserted before full unfiltered export and durable index.
coherent_assert=next(n for n in ast.walk(main) if isinstance(n,ast.Assert) and ast.unparse(n.test)=='coherent');assert coherent_assert.lineno>line('subprocess.run')
assert not queries
r={'status':'PASS actual pure argument builder and actual main ordering; no subprocess calls','count':len(rows),'cases':rows,'actualFinalizer':{'file':'confirmation-lifecycle-finalization-r2.py','bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()},'processQueries':queries,'scope':'Retained historical253 used only as data; no old checker or live/sourcebound audit executed. Future254 fixture is synthetic, not runtime proof. Actual full export and checker process still required.','checkedAt':time.time()}
p=B/'source254-finalizer-argument-controls-r1.json';assert not p.exists();p.write_text(json.dumps(r,indent=2)+'\n');print(r['status'],r['count'])
