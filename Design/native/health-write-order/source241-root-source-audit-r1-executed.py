from pathlib import Path
import json,gzip,base64,hashlib,time
b=Path('Design/native/health-write-order');sha=lambda x:hashlib.sha256(x).hexdigest();m=json.loads((b/'durable-source-r241.json').read_bytes());a=json.loads(gzip.decompress((b/'durable-source-r241.json.gz').read_bytes()));rows=[]
for group,key in [('files','files'),('fixtureInputs','binaryFiles')]:
 assert set(m[group])==set(a[key])
 for name,w in m[group].items():
  p=Path(name);assert not p.is_symlink();r=p.read_bytes();saved=a[key][name].encode() if key=='files' else base64.b64decode(a[key][name],validate=True);assert r==saved and len(r)==w['bytes'] and sha(r)==w['sha256'],name;rows.append(name)
for n in ['test','fixture']:
 p=b/f'source241-{n}-typecheck-r1.json';r=json.loads(p.read_bytes());src=Path(r['source']).read_bytes();assert len(src)==r['sourceBytes'] and sha(src)==r['sourceSHA256'] and r['exit']==0 and r['stdout']==r['stderr']==''
h=json.loads((b/'source241-healthy-host-controls-r1.json').read_bytes());assert (h['cases'],h['accepted'],h['rejected'],h['processQueryAttempts'])==(33,13,20,0)
for name in ['source241-healthy-host-controls-r1.json','source241-native-guard-controls-r1.json']:
 r=json.loads((b/name).read_bytes());raw=gzip.decompress((b/r['fixture']).read_bytes());assert len(raw)==r['decodedBytes'] and sha(raw)==r['decodedSHA256'];d=json.loads(raw)
 if 'compileExit' in d:
  assert d['compileExit']==d['runExit']==0 and d['compileStdout']==d['compileStderr']==d['runStderr']==''
  c=json.loads(d['runStdout']);assert len(c['cases'])==34 and base64.b64decode(c['healthyPayload'])==(b/'healthy-target-current-meal-r1.json').read_bytes()
 else:
  assert len(d['cases'])==33 and len(d['healthy14']['current']['files'])==14 and len(d['syntheticSuccess22']['current']['files'])==22
p=json.loads((b/'health-current-release-source241-r1-predeclared-plan.json').read_bytes());assert [len(p[k]) for k in ['checkedDevelopmentMarkers','debugPositiveControls','negativeMarkersWithoutDebugPositive','verifiedProductionMarkers']]==[207,191,16,21]
out={'status':'PASS root655current/archive and retainedisolatedcontrols/typing/helpbindings; independent141 pending','source':'durable-source-r241.json','bindings':len(rows),'sourceManifestSHA256':sha((b/'durable-source-r241.json').read_bytes()),'archiveSHA256':sha((b/'durable-source-r241.json.gz').read_bytes()),'scope':'Source/preparation audit only, no241fullbuild/native/producteligibility/transaction acceptance','checkedAt':time.time()};(b/'source241-root-source-audit-r1.json').write_text(json.dumps(out,indent=2)+'\n');print(json.dumps(out))
