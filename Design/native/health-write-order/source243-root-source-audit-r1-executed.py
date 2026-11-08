"""Root independent current/archive/case/pair and retained actual-observation replay."""
from pathlib import Path
import importlib.util,json,gzip,base64,hashlib,time
B=Path(__file__).resolve().parent;repo=B.parents[2];sha=lambda x:hashlib.sha256(x).hexdigest();bindings={}
for source in ['durable-source-r243.json','durable-source-r242.json']:
 m=json.loads((B/source).read_bytes());a=json.loads(gzip.decompress((B/(source+'.gz')).read_bytes()));count=0
 for group,key in [('files','files'),('fixtureInputs','binaryFiles')]:
  assert set(m[group])==set(a[key])
  for name,w in m[group].items():
   p=repo/name;assert not p.is_symlink();raw=p.read_bytes();saved=a[key][name].encode() if key=='files' else base64.b64decode(a[key][name],validate=True);assert raw==saved and len(raw)==w['bytes'] and sha(raw)==w['sha256'],name;count+=1
 bindings[source]=count
spec=importlib.util.spec_from_file_location('root243host',B/'healthy-target-evidence-r3.py');e=importlib.util.module_from_spec(spec);spec.loader.exec_module(e);h=e.h
inputs=h.verify_inputs('durable-source-r242.json','health-target-change-source242-r1-build.json');assert e.verify_host_source('durable-source-r243.json')['exactCurrentArchiveBindings']==685
state=json.loads((B/'health-healthy-target-change-data-source242r1-driver-observations.json').read_bytes());first=state['boundaries'][0]['protected'];actual=state['boundaries'][2]['protected'];leaf=state['nativeStates'][-1]['value']['events'][6]['mealFile'];e.healthy.validate(actual,first,leaf,h,e.v);e.healthy.validate(actual,first,leaf,h,e.v,actual)
old=e.e.module('root243originalpredicate','healthy-target-protected-r1.py')
try:old.validate(actual,first,leaf,h,e.v)
except AssertionError:rejected=True
else:rejected=False
assert rejected
for n in state['nativeStates']:assert json.loads(e.v.payload(n,h))==n['value'];e.check_state(n['value'],state['started'],state['runID'],state['appPID'])
controls=json.loads((B/'source243-directory-controls-r1.json').read_bytes());raw=gzip.decompress((B/controls['fixture']).read_bytes());assert len(raw)==controls['decodedBytes'] and sha(raw)==controls['decodedSHA256'];fixture=json.loads(raw);assert len(fixture['caseResults'])==47 and (controls['accepted'],controls['rejected'],controls['processQueryAttempts'])==(26,21,0)
helps=json.loads((B/'source243-host-entrypoint-controls-r1.json').read_bytes());assert len(helps['controls'])==2
for row in helps['controls']:
 raw=(repo/row['file']).read_bytes();assert len(raw)==row['bytes'] and sha(raw)==row['sha256'] and row['exit']==0 and row['stderr']==''
out={'status':'PASS root685host+674compiledcase current/archive/pair; actualfailed242record accepted onlybynewpredicate, originalR1stillrejects;47isolatedcontrols/helpbindings exact; independent144pending','source':'durable-source-r243.json','caseSource':'durable-source-r242.json','bindings':bindings,'nativeRetainedStates':len(state['nativeStates']),'hostManifestSHA256':sha((B/'durable-source-r243.json').read_bytes()),'hostArchiveSHA256':sha((B/'durable-source-r243.json.gz').read_bytes()),'casePreflight':inputs,'newAppBuildRequired':False,'scope':'Retainedcontrol/source/pair verification only; no freshhealthy native/recovery/freshUI/commit/closure/Release acceptance. Original242failed143 unchanged.','checkedAt':time.time()};p=B/'source243-root-source-audit-r1.json';assert not p.exists();p.write_text(json.dumps(out,indent=2)+'\n');print(json.dumps({k:out[k] for k in ['status','bindings','nativeRetainedStates','newAppBuildRequired']}))
