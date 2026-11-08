"""Pure wrong-context rejection, exact unchanged-function comparison and guarded help tests."""
from pathlib import Path
import ast,copy,hashlib,importlib.util,json,subprocess,time
B=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('mixed_context_controls',B/'health-mixed-ineligible-evidence-r2.py');h=importlib.util.module_from_spec(spec);spec.loader.exec_module(h)
context=json.loads((B/'source224-reset-provider-context.json').read_text());calls=[];rows=[]
def forbidden(*a,**k):calls.append(a);raise RuntimeError('No process or device query in isolated context controls')
original={n:getattr(subprocess,n) for n in ['run','check_output','Popen','check_call','call']}
for n in original:setattr(subprocess,n,forbidden)
def check(label,value,accept):
 before=len(calls)
 try:h.validate_context(value);actual=True
 except AssertionError:actual=False
 assert actual==accept and len(calls)==before,label
 rows.append({'name':label,'accepted':actual,'expected':accept,'newProcessQueries':len(calls)-before})
try:
 check('exact frozen approved context',context,True)
 cases=[('device','AF849DEA-DF34-4B0E-9FC1-3E45DCBE8481'),('device','unknown'),('input',str(B/'other.json')),('seeded',context['seeded'].replace(h.SAFE_DEVICE,'AF849DEA-DF34-4B0E-9FC1-3E45DCBE8481')),('seeded',context['seeded']+'/../'+h.NAME),('bytes',True),('bytes',4991),('sha256','0'*64)]
 for key,value in cases:
  x=copy.deepcopy(context);x[key]=value;check('reject changed '+key+' '+repr(value),x,False)
 for key in h.FIELDS:
  for value in [0,True,context['identity'][key]+1]:
   x=copy.deepcopy(context);x['identity'][key]=value;check('reject identity '+key+' '+str(value),x,False)
 x=copy.deepcopy(context);x['identity']['extra']=1;check('reject unknown identity field',x,False)
 safe=h.DEVICE;h.DEVICE='AF849DEA-DF34-4B0E-9FC1-3E45DCBE8481'
 check('reject runtime device redirected to preserved simulator',context,False)
 before=len(calls)
 try:h.container('data');raise AssertionError('unexpected container acceptance')
 except AssertionError as error:assert 'approved dedicated' in str(error)
 assert len(calls)==before;rows.append({'name':'container refuses runtime old-device redirect before subprocess','accepted':False,'expected':False,'newProcessQueries':0});h.DEVICE=safe
finally:
 h.DEVICE=h.SAFE_DEVICE
 for n,fn in original.items():setattr(subprocess,n,fn)
old=ast.parse((B/'health-mixed-ineligible-evidence-r1.py').read_text());new=ast.parse((B/'health-mixed-ineligible-evidence-r2.py').read_text());functions=lambda tree:{n.name:ast.dump(n,include_attributes=False) for n in tree.body if isinstance(n,(ast.FunctionDef,ast.AsyncFunctionDef))};a,c=functions(old),functions(new);unchanged=[n for n in a if n not in ['provider','container']];assert all(a[n]==c[n] for n in unchanged);assert set(c)-set(a)=={'validate_context','verify_host_source'}
guard='''import runpy,sys,subprocess
calls=[]
def forbidden(*a,**k):calls.append(a);raise AssertionError("No process/device query on help path")
for name in ["run","check_output","Popen","check_call","call"]:setattr(subprocess,name,forbidden)
sys.argv=[sys.argv[1],"--help"]
try:runpy.run_path(sys.argv[0],run_name="__main__")
except SystemExit as error:
 assert error.code==0 and not calls
 raise
'''
help_rows=[]
for name in ['health-mixed-ineligible-driver-r2.py','check-mixed-ineligible-evidence-r2.py']:
 r=subprocess.run(['python3','-B','-c',guard,str(B/name)],capture_output=True,text=True);assert r.returncode==0,(name,r.stderr);help_rows.append({'file':name,'exit':r.returncode,'stdout':r.stdout,'stderr':r.stderr,'queryGuardSource':guard})
p=B/'source245-safe-context-controls-r1.json';assert not p.exists();p.write_text(json.dumps({'status':'PASS isolated exact/wrong-context rejection and actual guardedR2help controls','checks':rows,'count':len(rows),'accept':sum(r['accepted'] for r in rows),'reject':sum(not r['accepted'] for r in rows),'processDeviceQueries':len(calls),'unchangedExistingEvidenceFunctions':unchanged,'newFunctions':['validate_context','verify_host_source'],'entrypoints':help_rows,'scope':'Pure known metadata/AST/help only; no simulator/app/defaults query, seed, reset or native execution; not actual mixed acceptance','checkedAt':time.time()},indent=2)+'\n');print('PASS',len(rows),'context guards;',len(unchanged),'unchanged existing evidence functions; 2 guardedhelp; zero devicequeries')
