"""Root retained replay of actual R3 checker AST before its live-query boundary.
No native launch, reset, acknowledgement, fixture mutation or repeated live audit.
"""
from pathlib import Path
import ast,base64,gzip,hashlib,json,sys,time,struct
B=Path(__file__).resolve().parent;R=B.parents[2];P='health-legacy-confirmation-data-source248r1'
sha=lambda x:hashlib.sha256(x).hexdigest()
load=lambda n:json.loads((B/n).read_bytes())
checker=B/'check-confirmation-target-r3.py';tree=ast.parse(checker.read_text());prefix=[];body=[]
for node in tree.body:
 if isinstance(node,ast.Try):
  for stmt in node.body:
   if isinstance(stmt,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='group' for t in stmt.targets):break
   body.append(stmt)
  break
 if isinstance(node,ast.FunctionDef) and node.name=='persist':
  node.body=[ast.Pass()]
 prefix.append(node)
assert len(body)>80
sys.argv=[str(checker),P,'--checker-source','durable-source-r248.json','--case-source','durable-source-r248.json','--build','health-target-change-source248-r1-build.json','--trial','RootRetainedR1']
ns={'__file__':str(checker)}
exec(compile(ast.fix_missing_locations(ast.Module(body=prefix+body,type_ignores=[])),str(checker), 'exec'),ns)
assert ns['result']['retainedValidationComplete'] is True
assert ns['result']['checkerSourceVerification']['exactCurrentArchiveBindings']==795
counts={}
def walk(x):
 if isinstance(x,dict):
  if {'bytes','sha256','base64'}<=x.keys() and x['base64'] is not None:
   raw=base64.b64decode(x['base64'],validate=True);assert len(raw)==x['bytes'] and sha(raw)==x['sha256'];counts['payloads']=counts.get('payloads',0)+1
  for val in x.values():walk(val)
 elif isinstance(x,list):
  for val in x:walk(val)
for key,name in [('host',P+'-host-audit.json'),('actualR3',P+'-confirmation-r3-postrunr1-outcome.json')]:
 counts['payloads']=0;walk(load(name));counts[key]=counts.pop('payloads')
assert counts=={'host':559,'actualR3':60}
index=load(P+'-all-originals.json');assert index['count']==18 and index['kinds']=={'json':1,'png':17}
for row in index['rows']:
 raw=(B/row['retained']).read_bytes();assert len(raw)==row['bytes'] and sha(raw)==row['sha256'];assert raw==(Path('/tmp/LumenBatch44Checks/HealthLegacyConfirmationDataSource248R1All')/row['file']).read_bytes()
 if row['kind']=='png':assert struct.unpack('>II',raw[16:24])==(1206,2622)
report=load('health-legacy-confirmation-source248-round2-part158-native.json');bindings=[]
for row in report['provenance']+report['actualBinaryBindings']:
 p=Path(row['path']);p=p if p.is_absolute() else R/p;raw=p.read_bytes();assert len(raw)==row['bytes'] and sha(raw)==row['sha256'],str(p);bindings.append(row)
for row in report['visualObservations']:
 raw=(B/row['file']).read_bytes();assert len(raw)==row['bytes'] and sha(raw)==row['sha256'];bindings.append({k:row[k] for k in ['file','bytes','sha256']})
assert len(bindings)==65
actual=load(P+'-confirmation-r3-postrunr1-outcome.json');assert actual['checkerExit']==0 and actual['retainedValidationComplete']
execution=load('source248-confirmation-r1-checker-execution.json');assert execution['checkerExit']==0
for val in execution['streams'].values():
 raw=gzip.decompress((B/val['retained']).read_bytes());assert len(raw)==val['bytes'] and sha(raw)==val['sha256']
result={'status':'PASS root retained strict actualR3 replay/current795/pair/18 originals/619 embedded payload instances/all65 Part158 bindings','actualR3CheckerExit':0,'rootMethod':'Exact existing R3 AST retained-validation prefix executed through retainedValidationComplete under no-op persist; live-query portion deliberately excluded. Actual prior mandatoryR3 final endpoints retained separately; no repeated live query.','checkerSHA256':sha(checker.read_bytes()),'retainedStatements':len(body),'payloads':counts,'originals':18,'part158Bindings':bindings,'rootFullRead':['12773B helper','962B native summary','full38780B Part158'],'limits':'One Data confirmation case only; sampled endpoints, no continuous absence/global FD/wholeForm/contrast/VoiceOver/motion/String/cancellation/expiry/currentRelease/fullgoal acceptance. Acquisition indices unchanged.','checkedAt':time.time()}
(B/'source248-root-native-final-audit-r1.json').write_text(json.dumps(result,indent=2)+'\n');print(result['status'])
