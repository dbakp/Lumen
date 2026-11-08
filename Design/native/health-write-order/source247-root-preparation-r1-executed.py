"""Read-only root frozen-source/control replay before independent readiness/build."""
from pathlib import Path
import ast,base64,gzip,hashlib,json,time
B=Path(__file__).resolve().parent;R=B.parents[2];sha=lambda x:hashlib.sha256(x).hexdigest()
load=lambda n:json.loads((B/n).read_bytes())
m=load('durable-source-r247.json');a=json.loads(gzip.decompress((B/'durable-source-r247.json.gz').read_bytes()));old=load('durable-source-r246.json');count=0
for group,key in [('files','files'),('fixtureInputs','binaryFiles')]:
 assert set(m[group])==set(a[key])
 for n,w in m[group].items():
  data=(R/n).read_bytes();arch=a[key][n].encode() if key=='files' else base64.b64decode(a[key][n],validate=True)
  assert not (R/n).is_symlink() and data==arch and len(data)==w['bytes'] and sha(data)==w['sha256'];count+=1
assert count==765
modified=[n for n,w in old['files'].items() if m['files'][n]!=w];assert modified==['LumenUITests/LumenSmokeTests.swift']
assert all(m['fixtureInputs'][n]==w for n,w in old['fixtureInputs'].items())
sdk=load('source247-uitest-sdk-typecheck-r1.json');assert sdk['exit']==0 and sdk['stdout']==sdk['stderr']=='' and sha((R/sdk['file']).read_bytes())==sdk['sourceSHA256']
gate=load('source246-gate-sdk-typecheck-r2.json');assert gate['exit']==0 and gate['stdout']==gate['stderr']=='' and sha((R/gate['file']).read_bytes())==gate['sourceSHA256']
for n,key,total in [('source247-confirmation-query-controls-r1.json','cases',7),('source247-confirmation-marker-controls-r1.json','checks',39)]:
 d=load(n);assert len(d[key])==total and all(r['accepted']==r['expected'] for r in d[key])
entry=load('source247-entrypoint-controls-r1.json');assert entry['processQueries']==[] and len(entry['rows'])==2
for row in entry['rows']:assert row['exit']==0 and row['stderr']=='' and sha((B/row['entrypoint']).read_bytes())==row['sourceSHA256']
c=load('source247-caller-controls-r1.json');raw=gzip.decompress((B/'source247-caller-controls-r1-fixtures.json.gz').read_bytes());assert len(raw)==c['archiveDecodedBytes'] and sha(raw)==c['archiveDecodedSHA256'];archive=json.loads(raw)
tree=ast.parse((B/'confirmation-target-driver-r2.py').read_text());fn=next(x for x in tree.body if isinstance(x,ast.FunctionDef) and x.name=='confirmation_gate');main=next(x for x in tree.body if isinstance(x,ast.Try) and 'hostSourceVerification' in ast.unparse(x));assert archive['functionAST']==ast.dump(fn,include_attributes=False) and archive['exceptionHandlerAST']==[ast.dump(x,include_attributes=False) for x in main.handlers]
assert len(c['cases'])==len(archive['fixtures'])==18 and c['sourceSHA256']==sha((B/'confirmation-target-driver-r2.py').read_bytes())
assert all(x['status']=='PASS' and x['realProcessQueries']==0 for x in c['cases']);assert sum(x['acknowledged'] for x in c['cases'])==1
payloads=0
def verify(x):
 global payloads
 if isinstance(x,dict):
  if {'base64','bytes','sha256'}<=x.keys() and x['base64'] is not None:
   data=base64.b64decode(x['base64'],validate=True);assert len(data)==x['bytes'] and sha(data)==x['sha256'];payloads+=1
  for v in x.values():verify(v)
 elif isinstance(x,list):
  for v in x:verify(v)
verify(archive)
for trial in archive['fixtures']:
 window=trial['canonicalState']['confirmationWindow']
 if trial['name'].startswith('exact valid'):assert window['acknowledged'] is True and trial['preAckCalls']==['protected','fixed','source']
 else:assert not window.get('acknowledged') and not window.get('ackIntended') and trial['canonicalState']['status'].startswith('FAILED')
for kind in ['gate','marker']:
 malformed=[x for x in archive['fixtures'] if x['name'].startswith(kind+' ') and ' schema ' not in x['name']]
 assert len(malformed)==5
 for x in malformed:
  observed=x['canonicalState']['confirmationWindow'];assert observed[kind]==x['input'] and observed[kind+'Acquisition']['status']=='FAILED_IDENTITY_OR_PARSE' and observed[kind+'Acquisition']['rawInputs']==[x['input']]
plan=load('health-current-release-source247-r1-predeclared-plan.json');prior=load('health-current-release-source246-r1-predeclared-plan.json');keys=['checkedDevelopmentMarkers','debugPositiveControls','negativeMarkersWithoutDebugPositive','verifiedProductionMarkers'];assert [len(plan[k]) for k in keys]==[211,195,16,21] and all(plan[k]==prior[k] for k in keys)
report={'status':'Root765current/archive/onepriorUITestchange/7matcher39pure18actualcaller/SDKcurrent/2actualzeroqueryhelp/unchangedgate/nativeguards carry verified;155readiness pending','source':'durable-source-r247.json','bindings':count,'priorModified':modified,'priorUnchanged':741,'appended':23,'callerRawPayloadInstances':payloads,'callerScope':'Actual caller AST+actual exception handler, isolated real files/real predicate and reader, stub runner/protected dependencies; zero real queries, not runtime acceptance','currentSDK':'Whole currentUITest0/empty streams; unchanged whole gate actualSDKR2 with stubs carried only','markerArrays':[211,195,16,21],'runtime':'No246/247fullapp/build/native/Release yet; current244pair historical runnable only. Runner tmp, real alertvalue, cancellation/expiry/native gates remain open.','checkedAt':time.time()};(B/'source247-root-preparation-r1.json').write_text(json.dumps(report,indent=2)+'\n');print(report['status']);print('decoded caller payload instances',payloads)
